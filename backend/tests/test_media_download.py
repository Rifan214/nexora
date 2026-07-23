from __future__ import annotations

import threading
from pathlib import Path

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
        assert progress_updates == [0, 25, 99]

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
