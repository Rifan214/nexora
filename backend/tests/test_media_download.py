from __future__ import annotations

import threading
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest
from yt_dlp.utils import DownloadCancelled, DownloadError

import app.services.media_service as media_service_module
from app.models.job import JobStatus
from app.models.requests import MediaDownloadRequest
from app.services.download_process_manager import get_download_process_manager
from app.services.job_manager import get_job_manager
from app.services.media_service import MediaService
from app.utils.storage import get_temp_storage_dir


@pytest.fixture(autouse=True)
def clear_job_manager() -> None:
    get_job_manager.cache_clear()
    get_download_process_manager.cache_clear()
    yield
    get_job_manager.cache_clear()
    get_download_process_manager.cache_clear()


class FakeYoutubeDL:
    instances: list["FakeYoutubeDL"] = []
    download_error: Exception | None = None

    def __init__(self, options: dict) -> None:
        self.options = options
        self.instances.append(self)

    def __enter__(self) -> "FakeYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, _: str, *, download: bool) -> dict:
        if not download:
            return {
                "title": "A title that must not become a filename",
                "extractor_key": "Youtube",
            }

        if self.download_error is not None:
            raise self.download_error

        progress_hook = self.options["progress_hooks"][0]
        progress_hook({"status": "downloading", "downloaded_bytes": 25, "total_bytes": 100})
        progress_hook({"status": "downloading", "downloaded_bytes": 100, "total_bytes": 100})
        progress_hook({"status": "finished"})

        extension = "mp3" if self.options.get("postprocessors") else "mp4"
        output_path = Path(self.options["outtmpl"].replace("%(ext)s", extension))
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(b"downloaded-media")
        return {"title": "A title that must not become a filename"}


@pytest.mark.parametrize(
    ("url", "format_id"),
    [
        ("https://www.youtube.com/watch?v=normal-video", "18"),
        ("https://www.youtube.com/shorts/short-video", "22"),
    ],
)
def test_background_download_completes_for_youtube_videos_and_shorts(
    monkeypatch: pytest.MonkeyPatch,
    url: str,
    format_id: str,
) -> None:
    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = None
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)

    service = MediaService()
    request = MediaDownloadRequest(url=url, format_id=format_id, type="video")
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id=request.format_id,
        output_type=request.type,
    )
    progress_updates: list[int] = []
    job_manager = get_job_manager()
    update_progress = job_manager.update_progress

    def record_progress(*args: object, **kwargs: object):
        updated_job = update_progress(*args, **kwargs)
        progress_updates.append(updated_job.progress)
        return updated_job

    monkeypatch.setattr(job_manager, "update_progress", record_progress)

    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"
    try:
        service._download_job_background(job.job_id, request.url, request.format_id, request.type)

        completed_job = get_job_manager().get_job(job.job_id)
        assert completed_job is not None
        assert completed_job.status is JobStatus.completed
        assert completed_job.progress == 100
        assert completed_job.download_url == f"/files/{job.job_id}"
        assert completed_job.expires_at is not None
        assert completed_job.title == "A title that must not become a filename"
        assert downloaded_file.read_bytes() == b"downloaded-media"
        assert not list(downloaded_file.parent.glob("*A title that must not become a filename*"))
        assert progress_updates == [25, 99]

        download_options = FakeYoutubeDL.instances[1].options
        assert download_options["format"] == format_id
        assert "postprocessors" not in download_options
    finally:
        downloaded_file.unlink(missing_ok=True)


def test_background_audio_download_extracts_a_high_quality_mp3(monkeypatch: pytest.MonkeyPatch) -> None:
    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = None
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)

    service = MediaService()
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=audio-only",
        media_type="audio",
    )
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id="bestaudio/best",
        output_type=request.media_type,
    )
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp3"

    try:
        service._download_job_background(job.job_id, request.url, "bestaudio/best", request.media_type)

        completed_job = get_job_manager().get_job(job.job_id)
        assert completed_job is not None
        assert completed_job.status is JobStatus.completed
        assert completed_job.progress == 100
        assert completed_job.output_type == "audio"
        assert completed_job.download_url == f"/files/{job.job_id}"
        assert downloaded_file.read_bytes() == b"downloaded-media"

        download_options = FakeYoutubeDL.instances[1].options
        assert download_options["format"] == "bestaudio/best"
        assert download_options["postprocessors"] == [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "0",
            }
        ]
    finally:
        downloaded_file.unlink(missing_ok=True)


@pytest.mark.parametrize(
    ("download_error", "expected_message"),
    [
        (DownloadError("Requested format is not available"), "Requested quality is no longer available"),
        (DownloadCancelled("Download cancelled"), "Download cancelled"),
        (DownloadError("unable to download video data: HTTP Error 403: Forbidden"), "The media source rejected the download request"),
        (DownloadError("Unable to download webpage: timed out"), "Network interruption while downloading"),
    ],
)
def test_background_download_marks_yt_dlp_failures_as_failed(
    monkeypatch: pytest.MonkeyPatch,
    download_error: Exception,
    expected_message: str,
) -> None:
    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = download_error
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)

    service = MediaService()
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=unavailable-format",
        format_id="unavailable",
        type="video",
    )
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id=request.format_id,
        output_type=request.type,
    )

    service._download_job_background(job.job_id, request.url, request.format_id, request.type)

    failed_job = get_job_manager().get_job(job.job_id)
    assert failed_job is not None
    assert failed_job.status is JobStatus.failed
    assert failed_job.error_message == expected_message


def test_background_download_removes_partial_artifacts_after_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = DownloadError("unable to download video data")
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)

    service = MediaService()
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=partial-artifact",
        format_id="18",
        type="video",
    )
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id=request.format_id,
        output_type=request.type,
    )
    partial_files = [
        get_temp_storage_dir() / f"{job.job_id}.mp4.part",
        get_temp_storage_dir() / f"{job.job_id}.f18.mp4",
    ]
    for partial_file in partial_files:
        partial_file.write_bytes(b"partial")

    try:
        service._download_job_background(job.job_id, request.url, request.format_id, request.type)

        assert all(not partial_file.exists() for partial_file in partial_files)
        failed_job = get_job_manager().get_job(job.job_id)
        assert failed_job is not None
        assert failed_job.status is JobStatus.failed
    finally:
        for partial_file in partial_files:
            partial_file.unlink(missing_ok=True)


def test_background_audio_download_reports_a_missing_ffmpeg(monkeypatch: pytest.MonkeyPatch) -> None:
    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = DownloadError("Postprocessing: ffmpeg not found")
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)

    service = MediaService()
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=audio-no-ffmpeg",
        media_type="audio",
    )
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id="bestaudio/best",
        output_type=request.media_type,
    )

    service._download_job_background(job.job_id, request.url, "bestaudio/best", request.media_type)

    failed_job = get_job_manager().get_job(job.job_id)
    assert failed_job is not None
    assert failed_job.status is JobStatus.failed
    assert failed_job.error_message == "FFmpeg is required to process this download but is unavailable"


def test_background_download_marks_filesystem_errors_as_failed(monkeypatch: pytest.MonkeyPatch) -> None:
    def unavailable_temp_directory() -> Path:
        raise PermissionError("Temporary storage is not writable")

    FakeYoutubeDL.instances = []
    FakeYoutubeDL.download_error = None
    monkeypatch.setattr(media_service_module, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(media_service_module, "get_temp_storage_dir", unavailable_temp_directory)

    service = MediaService()
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=storage-error",
        format_id="18",
        type="video",
    )
    job = get_job_manager().create_job(
        media_url=request.url,
        platform="youtube",
        format_id=request.format_id,
        output_type=request.type,
    )

    service._download_job_background(job.job_id, request.url, request.format_id, request.type)

    failed_job = get_job_manager().get_job(job.job_id)
    assert failed_job is not None
    assert failed_job.status is JobStatus.failed
    assert failed_job.error_message == "Filesystem error: Temporary storage is not writable"


def test_create_download_job_returns_before_the_worker_finishes(monkeypatch: pytest.MonkeyPatch) -> None:
    started = threading.Event()
    release_worker = threading.Event()

    def blocked_download(*_: object) -> None:
        started.set()
        release_worker.wait(timeout=1)

    monkeypatch.setattr(MediaService, "_download_job_background", blocked_download)
    service = MediaService()
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: {"title": "Background Worker", "extractor_key": "Youtube"},
    )
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=background-worker",
        format_id="18",
        type="video",
    )

    job = service.create_download_job(request)

    assert job.status is JobStatus.pending
    assert started.wait(timeout=0.2)
    release_worker.set()


def test_youtube_transport_refresh_invokes_extraction_without_process_false_and_merges_transport() -> None:
    service = MediaService()
    url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    initial_snapshot = {
        "id": "dQw4w9WgXcQ",
        "title": "Initial YouTube Video Title",
        "uploader": "RickAstleyVEVO",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "formats": [
            {
                "format_id": "18",
                "url": "https://rr1---sn-expired.googlevideo.com/videoplayback?expire=1",
                "width": 640,
                "height": 360,
                "http_headers": {"User-Agent": "old-agent"},
            }
        ],
    }
    refreshed_data = {
        "id": "dQw4w9WgXcQ",
        "title": "Fresh Title From Backend",
        "formats": [
            {
                "format_id": "18",
                "url": "https://rr1---sn-fresh.googlevideo.com/videoplayback?expire=9999",
                "width": 640,
                "height": 360,
                "http_headers": {"User-Agent": "new-agent"},
            }
        ],
        "http_headers": {"Authorization": "Bearer fresh-token"},
    }

    mock_ydl = MagicMock()
    mock_ydl.extract_info.return_value = refreshed_data

    resolved, refreshed = service._refresh_download_transport_info(
        mock_ydl,
        url=url,
        snapshot=initial_snapshot,
    )

    # Must invoke extraction with download=False and without process=False
    mock_ydl.extract_info.assert_called_once_with(url, download=False)
    call_kwargs = mock_ydl.extract_info.call_args.kwargs
    assert "process" not in call_kwargs or call_kwargs["process"] is not False

    # Presentation metadata from snapshot is preserved
    assert resolved["id"] == "dQw4w9WgXcQ"
    assert resolved["title"] == "Initial YouTube Video Title"
    assert resolved["uploader"] == "RickAstleyVEVO"

    # Transport fields are updated from refreshed info
    assert resolved["formats"][0]["url"] == "https://rr1---sn-fresh.googlevideo.com/videoplayback?expire=9999"
    assert resolved["formats"][0]["http_headers"] == {"User-Agent": "new-agent"}
    assert resolved["http_headers"] == {"Authorization": "Bearer fresh-token"}
    assert refreshed == refreshed_data


def test_youtube_background_download_with_snapshot_refreshes_transport_without_process_false(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    extract_info_calls: list[dict[str, Any]] = []

    class _CaptureYoutubeDL:
        instances: list["_CaptureYoutubeDL"] = []

        def __init__(self, options: dict) -> None:
            self.options = options
            self.instances.append(self)

        def __enter__(self) -> "_CaptureYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def extract_info(self, url: str, **kwargs: Any) -> dict:
            extract_info_calls.append({"url": url, "kwargs": kwargs})
            if not kwargs.get("download", True):
                return {
                    "id": "dQw4w9WgXcQ",
                    "extractor_key": "Youtube",
                    "formats": [{"format_id": "18", "url": "https://fresh.googlevideo.com/stream"}],
                }
            progress_hook = self.options["progress_hooks"][0]
            progress_hook({"status": "downloading", "downloaded_bytes": 100, "total_bytes": 100})
            progress_hook({"status": "finished"})
            output_path = Path(self.options["outtmpl"].replace("%(ext)s", "mp4"))
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(b"yt-video")
            return {"title": "YouTube Video"}

        def process_ie_result(self, info: dict, *, download: bool) -> dict:
            output_path = Path(self.options["outtmpl"].replace("%(ext)s", "mp4"))
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(b"yt-video")
            return info

    monkeypatch.setattr(media_service_module, "YoutubeDL", _CaptureYoutubeDL)

    service = MediaService()
    url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    snapshot = {
        "id": "dQw4w9WgXcQ",
        "title": "Cached YouTube Video",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "formats": [{"format_id": "18", "url": "https://expired.googlevideo.com/stream"}],
    }
    job = get_job_manager().create_job(
        media_url=url,
        platform="youtube",
        format_id="18",
        output_type="video",
    )
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"

    try:
        service._download_job_background(
            job.job_id,
            url,
            "18",
            "video",
            snapshot,
        )

        completed_job = get_job_manager().get_job(job.job_id)
        assert completed_job is not None
        assert completed_job.status is JobStatus.completed

        # Transport refresh must be invoked with download=False and without process=False
        refresh_call = extract_info_calls[0]
        assert refresh_call["url"] == url
        assert refresh_call["kwargs"].get("download") is False
        assert refresh_call["kwargs"].get("process") is not False
    finally:
        downloaded_file.unlink(missing_ok=True)


def test_background_worker_preserves_pending_status_until_download_starts(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    job_statuses_during_execution: list[JobStatus] = []

    class _StatusTrackingYoutubeDL:
        def __init__(self, options: dict) -> None:
            self.options = options

        def __enter__(self) -> "_StatusTrackingYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def extract_info(self, _: str, *, download: bool) -> dict:
            current_job = get_job_manager().get_job(test_job_id)
            if current_job:
                job_statuses_during_execution.append(current_job.status)

            if download:
                progress_hook = self.options["progress_hooks"][0]
                # First progress hook invocation with downloading status
                progress_hook({"status": "downloading", "downloaded_bytes": 10, "total_bytes": 100})
                post_hook_job = get_job_manager().get_job(test_job_id)
                if post_hook_job:
                    job_statuses_during_execution.append(post_hook_job.status)

                progress_hook({"status": "finished"})

                output_path = Path(self.options["outtmpl"].replace("%(ext)s", "mp4"))
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_bytes(b"yt-video")

            return {"title": "Test Status Video", "extractor_key": "Youtube"}

    monkeypatch.setattr(media_service_module, "YoutubeDL", _StatusTrackingYoutubeDL)

    service = MediaService()
    url = "https://www.youtube.com/watch?v=status-test"
    job = get_job_manager().create_job(
        media_url=url,
        platform="youtube",
        format_id="18",
        output_type="video",
    )
    test_job_id = job.job_id
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"

    try:
        service._download_job_background(job.job_id, url, "18", "video")

        completed_job = get_job_manager().get_job(job.job_id)
        assert completed_job is not None
        assert completed_job.status is JobStatus.completed

        # Verification: during extraction and preparation, status remained pending.
        # After the downloading progress hook was invoked, status transitioned to processing.
        assert job_statuses_during_execution == [
            JobStatus.pending,
            JobStatus.pending,
            JobStatus.processing,
        ]
    finally:
        downloaded_file.unlink(missing_ok=True)


def test_cancellation_while_pending_in_background_worker() -> None:
    service = MediaService()
    process_manager = get_download_process_manager()
    job_manager = get_job_manager()

    url = "https://www.youtube.com/watch?v=cancel-test"
    job = job_manager.create_job(
        media_url=url,
        platform="youtube",
        format_id="18",
        output_type="video",
    )

    # Request cancellation while job is pending
    process_manager.request_cancellation(job.job_id)
    job_manager.mark_cancelling(job.job_id)
    cancelling_job = job_manager.get_job(job.job_id)
    assert cancelling_job is not None
    assert cancelling_job.status is JobStatus.cancelling

    # Calling worker on a cancelled pending job should cleanly abort without error
    service._download_job_background(job.job_id, url, "18", "video")
    final_job = job_manager.get_job(job.job_id)
    assert final_job is not None
    assert final_job.status is JobStatus.cancelled
