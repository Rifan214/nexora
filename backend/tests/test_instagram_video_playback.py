from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.exceptions import APIError
from app.main import app
from app.models.job import DownloadJob, JobStatus
from app.models.requests import MediaDownloadRequest
from app.services.download_file_service import DownloadFileService
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.quality_selector import QualitySelector
from app.utils.media_probe import (
    AUDIO_ONLY_SUFFIXES,
    IMAGE_SUFFIXES,
    probe_media_streams,
    validate_download_artifact,
)
from app.utils.storage import find_downloaded_file


# ==============================================================================
# 1. FORMAT SELECTION: INSTAGRAM AUTHENTICATED FORMATS
# ==============================================================================


def test_instagram_dash_formats_pair_video_and_audio() -> None:
    """1. An authenticated Instagram video request selects a video-containing format paired with audio rather than audio-only."""
    selector = QualitySelector()
    formats = [
        {
            "format_id": "dash-audio",
            "url": "https://instagram.fcdn.net/dash_audio.m4a",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "audio_ext": "m4a",
            "abr": 128,
            "protocol": "https",
        },
        {
            "format_id": "dash-video-720",
            "url": "https://instagram.fcdn.net/dash_720.mp4",
            "ext": "mp4",
            "vcodec": "avc1.64001f",
            "acodec": "none",
            "audio_ext": None,
            "width": 720,
            "height": 1280,
            "protocol": "https",
        },
        {
            "format_id": "dash-video-1080",
            "url": "https://instagram.fcdn.net/dash_1080.mp4",
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": "none",
            "audio_ext": None,
            "width": 1080,
            "height": 1920,
            "protocol": "https",
        },
    ]

    selections = selector.select_qualities(formats, platform="instagram")
    assert len(selections) == 2

    # Verify 720p selection pairs video and audio
    sel_720 = selector.select_for_height(formats, 720, platform="instagram")
    assert sel_720 is not None
    assert sel_720.video_format_id == "dash-video-720"
    assert sel_720.audio_format_id == "dash-audio"
    assert sel_720.selector == "dash-video-720+dash-audio"

    # Verify 1080p selection pairs video and audio
    sel_1080 = selector.select_for_height(formats, 1080, platform="instagram")
    assert sel_1080 is not None
    assert sel_1080.video_format_id == "dash-video-1080"
    assert sel_1080.audio_format_id == "dash-audio"
    assert sel_1080.selector == "dash-video-1080+dash-audio"


def test_instagram_direct_mp4_with_missing_vcodec_recognized_as_progressive() -> None:
    """Direct Instagram progressive formats with missing vcodec/acodec metadata are recognized as video."""
    selector = QualitySelector()
    formats = [
        {
            "format_id": "101",
            "url": "https://instagram.fcdn.net/direct_720.mp4",
            "ext": "mp4",
            "vcodec": None,
            "acodec": None,
            "width": 720,
            "height": 1280,
            "protocol": "https",
        },
    ]

    sel_720 = selector.select_for_height(formats, 720, platform="instagram")
    assert sel_720 is not None
    assert sel_720.video_format_id == "101"
    assert sel_720.audio_format_id is None
    assert sel_720.selector == "101"


def test_video_download_request_rejects_audio_only_selector() -> None:
    """A video request cannot select an audio-only stream."""
    service = MediaService()
    formats = [
        {
            "format_id": "dash-audio",
            "url": "https://instagram.fcdn.net/dash_audio.m4a",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "audio_ext": "m4a",
            "abr": 128,
            "protocol": "https",
        },
    ]
    info = {
        "id": "C_test_audio_only",
        "title": "Audio Only Test",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "formats": formats,
    }

    req = MediaDownloadRequest(
        url="https://www.instagram.com/reel/C_test_audio_only/",
        media_type="video",
        format_id="dash-audio",
    )

    with patch.object(service, "_get_or_extract_supported_info", return_value=(info, "instagram", True, req.url)):
        with pytest.raises(APIError) as exc_info:
            service.create_download_job(req)

        assert exc_info.value.code == "QUALITY_NOT_AVAILABLE"
        assert exc_info.value.status_code == 409


# ==============================================================================
# 2. FFMPEG MERGE/REMUX OPTIONS
# ==============================================================================


def test_ffmpeg_merge_options_applied_for_video_download(tmp_path: Path) -> None:
    """2. The expected FFmpeg merge/remux options are applied when required by video formats."""
    service = MediaService()
    job_id = uuid4()
    job_manager = JobManager()

    # Video options must include merge_output_format: "mp4"
    video_options = service._build_download_options(
        job_id=job_id,
        format_selector="dash-video-1080+dash-audio",
        output_type="video",
        output_template=str(tmp_path / f"{job_id}.%(ext)s"),
        temp_dir=tmp_path,
        job_manager=job_manager,
        resume_state_manager=service._resume_state_manager,
        continue_download=False,
    )
    assert video_options.get("merge_output_format") == "mp4"

    # Audio options must configure MP3 postprocessor and not merge_output_format
    audio_options = service._build_download_options(
        job_id=job_id,
        format_selector="bestaudio/best",
        output_type="audio",
        output_template=str(tmp_path / f"{job_id}.%(ext)s"),
        temp_dir=tmp_path,
        job_manager=job_manager,
        resume_state_manager=service._resume_state_manager,
        continue_download=False,
    )
    assert "merge_output_format" not in audio_options
    assert "postprocessors" in audio_options
    assert any(pp.get("key") == "FFmpegExtractAudio" for pp in audio_options["postprocessors"])


# ==============================================================================
# 3. ARTIFACT VALIDATION: VIDEO VS AUDIO-ONLY ARTIFACTS
# ==============================================================================


def test_valid_video_artifact_passes_validation(tmp_path: Path) -> None:
    """3. A valid video-plus-audio artifact is recognized as a completed download."""
    video_file = tmp_path / "valid_video.mp4"
    video_file.write_bytes(b"\x00" * 1024)  # non-empty

    with patch("app.utils.media_probe.probe_media_streams") as mock_probe:
        mock_probe.return_value = [
            {"codec_type": "video", "codec_name": "h264", "width": 1080, "height": 1920},
            {"codec_type": "audio", "codec_name": "aac"},
        ]
        # Should not raise
        validate_download_artifact(video_file, output_type="video")


def test_audio_only_artifact_fails_video_download_validation(tmp_path: Path) -> None:
    """4. An audio-only artifact is not incorrectly reported as a successful video download."""
    # Sub-case A: Audio-only suffix (.m4a)
    m4a_file = tmp_path / "download.m4a"
    m4a_file.write_bytes(b"\x00" * 1024)

    with pytest.raises(ValueError, match="audio-only file"):
        validate_download_artifact(m4a_file, output_type="video")

    # Sub-case B: .mp4 container but ffprobe detects only audio stream
    mp4_audio_only = tmp_path / "audio_in_mp4.mp4"
    mp4_audio_only.write_bytes(b"\x00" * 1024)

    with patch("app.utils.media_probe.probe_media_streams") as mock_probe:
        mock_probe.return_value = [
            {"codec_type": "audio", "codec_name": "aac"},
        ]
        with pytest.raises(ValueError, match="does not contain any video streams"):
            validate_download_artifact(mp4_audio_only, output_type="video")


def test_missing_or_empty_artifact_fails_validation(tmp_path: Path) -> None:
    """5. Missing, empty, or invalid final artifacts are handled as failures rather than published."""
    # Sub-case A: Missing file
    missing_file = tmp_path / "nonexistent.mp4"
    with pytest.raises(FileNotFoundError):
        validate_download_artifact(missing_file, output_type="video")

    # Sub-case B: 0-byte file
    empty_file = tmp_path / "empty.mp4"
    empty_file.touch()
    with pytest.raises(ValueError, match="empty \\(0 bytes\\)"):
        validate_download_artifact(empty_file, output_type="video")

    # Sub-case C: Image file
    img_file = tmp_path / "thumb.jpg"
    img_file.write_bytes(b"\xff\xd8\xff" * 100)
    with pytest.raises(ValueError, match="image file"):
        validate_download_artifact(img_file, output_type="video")


# ==============================================================================
# 4. STORAGE CANDIDATE DISCOVERY & INTERMEDIATE STREAM EXCLUSION
# ==============================================================================


def test_find_downloaded_file_filtering(tmp_path: Path) -> None:
    """6. find_downloaded_file ignores intermediate files, images, and audio files for video jobs."""
    job_id = uuid4()

    # Create various candidate files in tmp_path
    part_file = tmp_path / f"{job_id}.mp4.part"
    part_file.write_bytes(b"partial")

    info_json = tmp_path / f"{job_id}.info.json"
    info_json.write_text("{}", encoding="utf-8")

    thumb_jpg = tmp_path / f"{job_id}.jpg"
    thumb_jpg.write_bytes(b"image")

    intermediate_audio = tmp_path / f"{job_id}.fdash-audio.m4a"
    intermediate_audio.write_bytes(b"audio")

    intermediate_video = tmp_path / f"{job_id}.fdash-video-1080.mp4"
    intermediate_video.write_bytes(b"video")

    merged_mp4 = tmp_path / f"{job_id}.mp4"
    merged_mp4.write_bytes(b"merged_video_and_audio")

    # For a video job: must find merged_mp4, ignoring .part, .json, .jpg, .m4a, and intermediate .fdash-video
    found = find_downloaded_file(job_id, temp_dir=tmp_path, output_type="video")
    assert found is not None
    assert found == merged_mp4
    assert found.suffix == ".mp4"


def test_find_downloaded_file_rejects_audio_when_video_requested(tmp_path: Path) -> None:
    """find_downloaded_file returns None when only audio files exist and video is requested."""
    job_id = uuid4()
    audio_file = tmp_path / f"{job_id}.m4a"
    audio_file.write_bytes(b"audio_only")

    found_video = find_downloaded_file(job_id, temp_dir=tmp_path, output_type="video")
    assert found_video is None

    found_audio = find_downloaded_file(job_id, temp_dir=tmp_path, output_type="audio")
    assert found_audio == audio_file


# ==============================================================================
# 5. FILE SERVING & EXTENSION PRESERVATION
# ==============================================================================


def test_file_serving_validates_and_preserves_mp4_extension(tmp_path: Path) -> None:
    """File serving delivers valid mp4 files with correct Content-Disposition and rejects invalid files."""
    job_id = uuid4()
    job_manager = JobManager()
    job = job_manager.create_job(
        media_url="https://www.instagram.com/reel/C_test_reel/",
        platform="instagram",
        title="My Reel Title",
        format_id="dash-video-1080+dash-audio",
    )
    job_manager.mark_completed(job.job_id, download_url=f"/media/download/{job.job_id}/file")

    # Create the completed file in temp storage
    file_path = tmp_path / f"{job.job_id}.mp4"
    file_path.write_bytes(b"\x00" * 2048)

    file_service = DownloadFileService()

    with patch("app.services.download_file_service.find_downloaded_file", return_value=file_path):
        with patch("app.utils.media_probe.probe_media_streams") as mock_probe:
            mock_probe.return_value = [
                {"codec_type": "video", "codec_name": "h264"},
                {"codec_type": "audio", "codec_name": "aac"},
            ]
            response = file_service.create_file_response(job.job_id, job_manager=job_manager)

    assert response.status_code == 200
    assert response.media_type == "video/mp4"
    assert 'filename="My Reel Title.mp4"' in response.headers["Content-Disposition"]


def test_file_serving_fails_when_artifact_is_corrupt_or_audio_only(tmp_path: Path) -> None:
    """File serving returns 500 when the final artifact fails validation."""
    job_id = uuid4()
    job_manager = JobManager()
    job = job_manager.create_job(
        media_url="https://www.instagram.com/reel/C_corrupt_reel/",
        platform="instagram",
        title="Corrupt Reel",
        format_id="dash-video-1080+dash-audio",
    )
    job_manager.mark_completed(job.job_id, download_url=f"/media/download/{job.job_id}/file")

    # Create an empty file
    file_path = tmp_path / f"{job.job_id}.mp4"
    file_path.touch()

    file_service = DownloadFileService()

    with patch("app.services.download_file_service.find_downloaded_file", return_value=file_path):
        with pytest.raises(APIError) as exc_info:
            file_service.create_file_response(job.job_id, job_manager=job_manager)

        assert exc_info.value.code == "DOWNLOAD_FILE_INVALID"
        assert exc_info.value.status_code == 500


# ==============================================================================
# 6. DOWNLOAD BACKGROUND JOB MARKS FAILURE ON ARTIFACT VALIDATION ERROR
# ==============================================================================


def test_download_job_background_marks_failure_when_artifact_is_audio_only(tmp_path: Path) -> None:
    """When a video download results in an audio-only file, the background job marks it failed."""
    service = MediaService()
    job_manager = service._get_job_manager()
    job = job_manager.create_job(
        media_url="https://www.instagram.com/reel/C_fail_reel/",
        platform="instagram",
        title="Failing Reel",
        format_id="dash-audio",
    )

    # Simulate yt-dlp downloading only an audio file into temp
    audio_file = tmp_path / f"{job.job_id}.m4a"
    audio_file.write_bytes(b"\x00" * 1024)

    mock_download_info = {
        "id": "C_fail_reel",
        "title": "Failing Reel",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
    }

    with patch("app.services.media_service.get_temp_storage_dir", return_value=tmp_path):
        with patch.object(service, "_process_download_with_youtube_dl", return_value=mock_download_info):
            service._download_job_background(
                job_id=job.job_id,
                url=job.media_url,
                format_selector="dash-audio",
                output_type="video",
                download_info=mock_download_info,
            )

    updated_job = job_manager.get_job(job.job_id)
    assert updated_job is not None
    assert updated_job.status is JobStatus.failed
    assert "audio-only" in (updated_job.error_message or "").lower() or "not found" in (updated_job.error_message or "").lower()


# ==============================================================================
# 7. PROBE FALLBACK WHEN FFPROBE IS UNAVAILABLE
# ==============================================================================


def test_probe_media_streams_fallback_when_ffprobe_missing(tmp_path: Path) -> None:
    """When ffprobe is missing, container parsing fallback correctly identifies video and audio tracks."""
    import struct

    # Construct a minimal valid ISO-BMFF structure with a video track and an audio track
    def make_box(box_type: bytes, payload: bytes) -> bytes:
        return struct.pack(">I4s", len(payload) + 8, box_type) + payload

    # Video track: moov -> trak -> mdia -> hdlr (vide) + minf -> stbl -> stsd (avc1)
    v_hdlr = make_box(b"hdlr", b"\x00" * 8 + b"vide" + b"\x00" * 12)
    v_stsd_entry = struct.pack(">I4s", 16, b"avc1") + b"\x00" * 8
    v_stsd = make_box(b"stsd", b"\x00" * 8 + v_stsd_entry)
    v_stbl = make_box(b"stbl", v_stsd)
    v_minf = make_box(b"minf", v_stbl)
    v_mdia = make_box(b"mdia", v_hdlr + v_minf)
    v_trak = make_box(b"trak", v_mdia)

    # Audio track: moov -> trak -> mdia -> hdlr (soun) + minf -> stbl -> stsd (mp4a)
    a_hdlr = make_box(b"hdlr", b"\x00" * 8 + b"soun" + b"\x00" * 12)
    a_stsd_entry = struct.pack(">I4s", 16, b"mp4a") + b"\x00" * 8
    a_stsd = make_box(b"stsd", b"\x00" * 8 + a_stsd_entry)
    a_stbl = make_box(b"stbl", a_stsd)
    a_minf = make_box(b"minf", a_stbl)
    a_mdia = make_box(b"mdia", a_hdlr + a_minf)
    a_trak = make_box(b"trak", a_mdia)

    moov = make_box(b"moov", v_trak + a_trak)
    test_mp4 = tmp_path / "valid_muxed.mp4"
    test_mp4.write_bytes(moov)

    # Patch subprocess.run to simulate ffprobe being missing (FileNotFoundError)
    with patch("subprocess.run", side_effect=FileNotFoundError("ffprobe not found")):
        streams = probe_media_streams(test_mp4)

    assert streams is not None
    assert len(streams) == 2
    assert any(s.get("codec_type") == "video" and s.get("codec_name") == "avc1" for s in streams)
    assert any(s.get("codec_type") == "audio" and s.get("codec_name") == "mp4a" for s in streams)

    # Validation should pass for video
    validate_download_artifact(test_mp4, output_type="video")


def test_probe_media_streams_fallback_detects_audio_only_mp4(tmp_path: Path) -> None:
    """When ffprobe is missing, container parsing fallback detects an audio-only MP4 container."""
    import struct

    def make_box(box_type: bytes, payload: bytes) -> bytes:
        return struct.pack(">I4s", len(payload) + 8, box_type) + payload

    # Only audio track: moov -> trak -> mdia -> hdlr (soun)
    a_hdlr = make_box(b"hdlr", b"\x00" * 8 + b"soun" + b"\x00" * 12)
    a_stsd_entry = struct.pack(">I4s", 16, b"mp4a") + b"\x00" * 8
    a_stsd = make_box(b"stsd", b"\x00" * 8 + a_stsd_entry)
    a_stbl = make_box(b"stbl", a_stsd)
    a_minf = make_box(b"minf", a_stbl)
    a_mdia = make_box(b"mdia", a_hdlr + a_minf)
    a_trak = make_box(b"trak", a_mdia)

    moov = make_box(b"moov", a_trak)
    audio_only_mp4 = tmp_path / "audio_only.mp4"
    audio_only_mp4.write_bytes(moov)

    with patch("subprocess.run", side_effect=FileNotFoundError("ffprobe not found")):
        with pytest.raises(ValueError) as exc_info:
            validate_download_artifact(audio_only_mp4, output_type="video")

    assert "does not contain any video streams" in str(exc_info.value)

