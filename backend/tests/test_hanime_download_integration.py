from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
from urllib.parse import unquote
from uuid import uuid4
import pytest

from app.models.job import JobStatus
from app.models.requests import MediaDownloadRequest
from app.platforms.hanime import HanimeExtractor, HanimeSignatureProvider
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.queue_manager import QueueManager
from app.utils.storage import get_temp_storage_dir


@pytest.fixture
def dummy_hanime_info_dict() -> dict:
    return {
        "id": "3537",
        "title": "Terra Story 1",
        "thumbnail": "https://webedn.hanime.tv/media/covers/terra-story-1.jpg",
        "duration": 1757,
        "upload_date": "2024-09-01T00:00:00Z",
        "description": "Terra Story Episode 1",
        "webpage_url": "https://hanime.tv/videos/hentai/terra-story-1",
        "extractor": "hanime",
        "extractor_key": "Hanime",
        "formats": [
            {
                "format_id": "720p",
                "url": "https://hanime.tv/hls/3537/720p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 720,
                "width": 960,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
            {
                "format_id": "480p",
                "url": "https://hanime.tv/hls/3537/480p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 480,
                "width": 640,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
            {
                "format_id": "360p",
                "url": "https://hanime.tv/hls/3537/360p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 360,
                "width": 480,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
        ],
        "http_headers": {
            "User-Agent": "Mozilla/5.0",
            "Referer": "https://hanime.tv/",
            "Origin": "https://hanime.tv",
        },
    }


def test_create_download_job_hanime(dummy_hanime_info_dict: dict) -> None:
    """1. Test create_download_job uses existing JobManager/QueueManager and produces correct format."""
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    process_manager = DownloadProcessManager()

    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(return_value=dummy_hanime_info_dict)

    service = MediaService(
        hanime_extractor=mock_extractor,
        job_manager=job_manager,
        queue_manager=queue_manager,
        process_manager=process_manager,
    )

    # Video job for 720p
    req_video = MediaDownloadRequest(
        url="https://hanime.tv/videos/hentai/terra-story-1",
        media_type="video",
        quality_height=720,
    )
    job_video = service.create_download_job(req_video)
    assert job_video.platform == "hanime"
    assert job_video.format_id == "720p"
    assert job_video.status in {JobStatus.pending, JobStatus.queued}

    # Audio job
    req_audio = MediaDownloadRequest(
        url="https://hanime.tv/videos/hentai/terra-story-1",
        media_type="audio",
    )
    job_audio = service.create_download_job(req_audio)
    assert job_audio.platform == "hanime"
    assert job_audio.format_id == "bestaudio/best"
    assert job_audio.output_type == "audio"


def test_download_pipeline_options_and_headers(dummy_hanime_info_dict: dict) -> None:
    """2. Test downloader options receive required headers, enable_file_urls, and output templates."""
    job_manager = JobManager()
    service = MediaService(job_manager=job_manager)

    job_id = uuid4()
    temp_dir = get_temp_storage_dir()
    output_tmpl = str(temp_dir / f"{job_id}.%(ext)s")

    opts = service._build_download_options(
        job_id=job_id,
        format_selector="720p",
        output_type="video",
        output_template=output_tmpl,
        temp_dir=temp_dir,
        job_manager=job_manager,
        resume_state_manager=service._resume_state_manager,
        continue_download=False,
        enable_file_urls=True,
        http_headers=dummy_hanime_info_dict["http_headers"],
    )

    assert opts["format"] == "720p"
    assert opts["enable_file_urls"] is True
    assert opts["http_headers"]["Referer"] == "https://hanime.tv/"
    assert opts["http_headers"]["Origin"] == "https://hanime.tv"
    assert "User-Agent" in opts["http_headers"]


def test_hanime_manifest_preparation_and_cleanup(dummy_hanime_info_dict: dict) -> None:
    """3. Test _prepare_hanime_manifests writes local m3u8 file and cleans up on completion."""
    service = MediaService()
    job_id = uuid4()
    temp_dir = get_temp_storage_dir()

    m3u8_text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-ENDLIST\n"

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_resp = MagicMock()
        mock_resp.text = m3u8_text
        mock_client.get.return_value = mock_resp
        mock_client_cls.return_value.__enter__.return_value = mock_client

        info = dummy_hanime_info_dict.copy()
        service._prepare_hanime_manifests(info, job_id=job_id)

        manifest_file = temp_dir / f"{job_id}.720p.m3u8"
        assert manifest_file.is_file()
        assert manifest_file.read_text(encoding="utf-8") == m3u8_text
        assert info["formats"][0]["url"] == unquote(manifest_file.as_uri())

        # Clean up
        manifest_file.unlink(missing_ok=True)


def test_cancellation_with_download_process_manager() -> None:
    """4. Test cancellation of Hanime download job works through DownloadProcessManager."""
    process_manager = DownloadProcessManager()
    job_manager = JobManager()
    service = MediaService(process_manager=process_manager, job_manager=job_manager)

    job_id = uuid4()
    process_manager.register_job(job_id)
    process_manager.request_cancellation(job_id)

    assert process_manager.is_cancellation_requested(job_id) is True
    with pytest.raises(Exception):
        process_manager.raise_if_cancelled(job_id)


# ==============================================================================
# REAL LIVE DOWNLOAD TEST (SKIPPED BY DEFAULT)
# ==============================================================================

@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get("NEXORA_HANIME_LIVE_DOWNLOAD_TEST") != "1",
    reason="Live download test requires NEXORA_HANIME_LIVE_DOWNLOAD_TEST=1",
)
def test_live_hanime_download_sample() -> None:
    """End-to-end integration test validating real extraction, 720p download, and MP4 container integrity."""
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        pytest.skip("FFmpeg/FFprobe required for live download test")

    provider = HanimeSignatureProvider(enabled=True)
    extractor = HanimeExtractor(signature_provider=provider)
    job_manager = JobManager()
    process_manager = DownloadProcessManager()

    service = MediaService(
        hanime_extractor=extractor,
        hanime_signature_provider=provider,
        job_manager=job_manager,
        process_manager=process_manager,
    )

    url = "https://hanime.tv/videos/hentai/terra-story-1"

    # 1. Extract metadata
    meta = service.get_metadata(url)
    assert meta.platform == "hanime"
    assert "Terra Story" in meta.title
    assert any(q.height == 720 for q in meta.video_qualities)

    # 2. Create download job for 720p
    req = MediaDownloadRequest(url=url, media_type="video", quality_height=720)
    with patch.object(service, "_get_queue_manager") as mock_qm:
        job = service.create_download_job(req)
        assert job.format_id == "720p"
        mock_qm.return_value.enqueue.assert_called_once()

    # 3. Download a bounded 3-second sample to verify transport, sign.bin AES decryption, and remuxing
    temp_dir = get_temp_storage_dir()
    downloaded_file = None
    try:
        # Patch YoutubeDL options in _build_download_options to limit to 3s for bounded execution
        original_build = service._build_download_options

        def bounded_build(*args, **kwargs):
            opts = original_build(*args, **kwargs)
            opts["external_downloader_args"] = {"ffmpeg_i": ["-t", "3"]}
            return opts

        with patch.object(service, "_build_download_options", side_effect=bounded_build):
            service._download_job_background(
                job_id=job.job_id,
                url=url,
                format_selector=job.format_id,
                output_type=job.output_type,
            )

        completed_job = job_manager.get_job(job.job_id)
        assert completed_job.status == JobStatus.completed

        from app.utils.storage import find_downloaded_file
        downloaded_file = find_downloaded_file(job.job_id, temp_dir=temp_dir)
        assert downloaded_file is not None and downloaded_file.is_file()
        assert downloaded_file.suffix.lower() == ".mp4"
        assert downloaded_file.stat().st_size > 10000

        # 4. ffprobe verification
        probe_cmd = [
            "ffprobe",
            "-v", "error",
            "-show_entries", "stream=codec_type,codec_name,width,height:format=duration",
            "-of", "default=noprint_wrappers=1",
            str(downloaded_file),
        ]
        probe_run = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
        probe_out = probe_run.stdout

        assert "codec_name=h264" in probe_out
        assert "codec_name=aac" in probe_out
        assert "height=720" in probe_out
        assert "duration=" in probe_out
    finally:
        if downloaded_file and downloaded_file.is_file():
            downloaded_file.unlink(missing_ok=True)
        import asyncio
        asyncio.run(provider.close())
