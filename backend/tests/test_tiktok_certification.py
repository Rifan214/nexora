from __future__ import annotations

import pytest
from pydantic import ValidationError
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.core.exceptions import APIError
from app.models.job import JobStatus
from app.models.requests import MediaDownloadRequest, MediaInfoRequest
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.queue_manager import QueueManager
from app.utils.storage import get_temp_storage_dir


def test_tiktok_metadata_exposes_display_safe_video_and_audio_options(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _tiktok_info())

    source_url = "https://vt.tiktok.com/ZS4FhYvSh/"
    metadata = service.get_metadata(source_url)

    assert metadata.platform == "tiktok"
    assert metadata.title == "TikTok test video"
    assert metadata.thumbnail_url == "https://example.test/tiktok-thumbnail.jpg"
    assert metadata.duration_seconds == 17
    assert metadata.webpage_url == source_url
    assert metadata.video_qualities[0].label == "720p HD"
    assert metadata.audio_options[0].model_dump() == {
        "label": "MP3",
        "extension": "mp3",
    }


@pytest.mark.parametrize(
    "url",
    [
        "not-a-url",
        "ftp://www.tiktok.com/@nexora/video/12345",
        "https://",
    ],
)
def test_invalid_tiktok_urls_are_rejected_by_request_validation(url: str) -> None:
    with pytest.raises(ValidationError):
        MediaInfoRequest(url=url)


@pytest.mark.parametrize(
    ("media_type", "quality_height", "expected_selector"),
    [
        ("video", 720, "0"),
        ("audio", None, "bestaudio/best"),
    ],
)
def test_tiktok_download_jobs_reuse_the_existing_quality_and_audio_pipeline(
    monkeypatch: pytest.MonkeyPatch,
    media_type: str,
    quality_height: int | None,
    expected_selector: str,
) -> None:
    started_threads: list[_FakeThread] = []
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    monkeypatch.setattr(service, "_extract_info", lambda _: _tiktok_info())

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        started_threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)
    request = MediaDownloadRequest(
        url=_tiktok_url(f"{media_type}-download"),
        media_type=media_type,
        quality_height=quality_height,
    )

    job = service.create_download_job(request)

    assert job.platform == "tiktok"
    assert job.format_id == expected_selector
    assert started_threads[0].started is True
    assert started_threads[0].args[2] == expected_selector
    assert started_threads[0].args[3] == media_type


def test_tiktok_job_creation_reuses_the_recently_analyzed_snapshot(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source_url = "https://vt.tiktok.com/ZS4FhYvSh/"
    info = _tiktok_info()
    info["id"] = "7667886632720256269"
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    monkeypatch.setattr(service, "_extract_info", lambda _: info)
    service.get_metadata(source_url)
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(AssertionError("unexpected re-extraction")),
    )
    started_threads: list[_FakeThread] = []

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        started_threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)

    service.create_download_job(
        MediaDownloadRequest(url=source_url, media_type="video", quality_height=720)
    )

    assert started_threads[0].args[4]["id"] == info["id"]


def test_tiktok_download_reuses_the_analyzed_snapshot_without_reextracting(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source_url = "https://vt.tiktok.com/ZS4FhYvSh/"
    info = _tiktok_info()
    info.update({"id": "7667886632720256269", "original_url": source_url})
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    service = MediaService(process_manager=process_manager, job_manager=job_manager)
    monkeypatch.setattr(service, "_extract_info", lambda _: info)

    # Metadata is the only extraction call. The following job must use this
    # snapshot rather than contacting TikTok again before or during download.
    service.get_metadata(source_url)
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(AssertionError("unexpected re-extraction")),
    )
    monkeypatch.setattr(media_service_module, "YoutubeDL", _SnapshotYoutubeDL)
    _SnapshotYoutubeDL.instances = []

    job = job_manager.create_job(
        media_url=source_url,
        platform="tiktok",
        format_id="0",
        output_type="video",
    )
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"

    try:
        service._download_job_background(
            job.job_id,
            source_url,
            "0",
            "video",
            service._snapshot_cache.get(source_url).extracted_info,
        )

        completed_job = job_manager.get_job(job.job_id)
        assert completed_job is not None
        assert completed_job.status is JobStatus.completed
        assert _SnapshotYoutubeDL.instances[0].processed_info_ids == [info["id"]]
    finally:
        downloaded_file.unlink(missing_ok=True)


def test_mixed_youtube_and_tiktok_jobs_retain_fifo_queue_behavior(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    started_threads: list[_FakeThread] = []
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )

    def metadata_for_url(url: str) -> dict:
        return _tiktok_info() if "tiktok.com" in url else _youtube_info()

    def start_worker(*, job_id, **_: object) -> None:
        started_threads.append(_FakeThread.started_for(job_id))
        job_manager.update_progress(job_id, 0)

    monkeypatch.setattr(service, "_extract_info", metadata_for_url)
    monkeypatch.setattr(service, "_start_download_worker", start_worker)

    tiktok_job = service.create_download_job(
        MediaDownloadRequest(url=_tiktok_url("queue"), quality_height=720)
    )
    youtube_job = service.create_download_job(
        MediaDownloadRequest(
            url="https://www.youtube.com/watch?v=queue-test",
            quality_height=720,
        )
    )

    assert tiktok_job.status is JobStatus.pending
    assert job_manager.get_job(youtube_job.job_id).status is JobStatus.queued
    assert len(started_threads) == 1

    job_manager.mark_completed(tiktok_job.job_id)

    assert len(started_threads) == 2
    assert job_manager.get_job(youtube_job.job_id).status is JobStatus.processing


@pytest.mark.parametrize(
    ("error_message", "expected_code"),
    [
        ("This video is private", "VIDEO_PRIVATE"),
        ("Video is unavailable", "VIDEO_UNAVAILABLE"),
    ],
)
def test_tiktok_private_and_deleted_videos_return_standardized_errors(
    monkeypatch: pytest.MonkeyPatch,
    error_message: str,
    expected_code: str,
) -> None:
    service = MediaService()

    def raise_download_error(_: str) -> dict:
        raise DownloadError(error_message)

    monkeypatch.setattr(service, "_extract_info", raise_download_error)

    with pytest.raises(APIError) as error:
        service.get_metadata(_tiktok_url("unavailable"))

    assert error.value.code == expected_code
    assert "yt-dlp" not in error.value.details.lower()


def test_tiktok_playlist_import_is_rejected_before_extraction() -> None:
    service = MediaService()

    with pytest.raises(APIError) as error:
        service.get_playlist_metadata(_tiktok_url("playlist"))

    assert error.value.code == "TIKTOK_PLAYLIST_NOT_SUPPORTED"
    assert error.value.message == "TikTok playlist import is unavailable"


def test_tiktok_rehydration_failures_return_a_friendly_platform_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()

    def raise_download_error(_: str) -> dict:
        raise DownloadError("Unable to extract universal data for rehydration")

    monkeypatch.setattr(service, "_extract_info", raise_download_error)

    with pytest.raises(APIError) as error:
        service.get_metadata(_tiktok_url("rehydration"))

    assert error.value.code == "TIKTOK_EXTRACTION_UNAVAILABLE"
    assert error.value.message == "TikTok video temporarily unavailable"


def _tiktok_url(identifier: str) -> str:
    return f"https://www.tiktok.com/@nexora/video/{identifier}"


def _tiktok_info() -> dict:
    return {
        "title": "TikTok test video",
        "uploader": "Nexora",
        "thumbnail": "https://example.test/tiktok-thumbnail.jpg",
        "duration": 17,
        "webpage_url": _tiktok_url("metadata"),
        "extractor": "TikTok",
        "extractor_key": "TikTok",
        "formats": [
            {
                "format_id": "0",
                "height": 720,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
                "filesize": 10_000,
            },
        ],
    }


def _youtube_info() -> dict:
    return {
        "title": "YouTube test video",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "formats": [
            {
                "format_id": "18",
                "height": 720,
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": "mp4a.40.2",
            },
        ],
    }


class _FakeThread:
    def __init__(self, *, target, args, daemon, name) -> None:
        self.target = target
        self.args = args
        self.daemon = daemon
        self.name = name
        self.started = False

    def start(self) -> None:
        self.started = True

    @classmethod
    def started_for(cls, job_id: object) -> "_FakeThread":
        thread = cls(target=None, args=(job_id,), daemon=True, name="test-worker")
        thread.start()
        return thread


class _SnapshotYoutubeDL:
    instances: list["_SnapshotYoutubeDL"] = []

    def __init__(self, options: dict) -> None:
        self.options = options
        self.processed_info_ids: list[str] = []
        self.instances.append(self)

    def __enter__(self) -> "_SnapshotYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def process_ie_result(self, info: dict, *, download: bool) -> dict:
        assert download is True
        self.processed_info_ids.append(info["id"])
        output_path = get_temp_storage_dir() / self.options["outtmpl"].split("\\")[-1].replace(
            "%(ext)s", "mp4"
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(b"tiktok-media")
        return info
