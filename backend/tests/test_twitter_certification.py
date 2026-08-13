from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.api.routes.media import get_media_service
from app.main import create_app
from app.core.exceptions import APIError
from app.models.requests import MediaDownloadRequest
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.queue_manager import QueueManager
from app.utils.platforms import detect_platform_from_url, is_x_status_url, normalize_media_url


_X_MEDIA_NOT_AVAILABLE_MESSAGE = (
    "Unable to access downloadable media from this X post. "
    "The post may be restricted, require login, or temporarily unavailable."
)


@pytest.mark.parametrize(
    "url",
    [
        "https://x.com/nexora/status/1900000000000000001",
        "https://twitter.com/nexora/status/1900000000000000001",
    ],
)
def test_x_status_urls_are_detected_and_normalized(url: str) -> None:
    assert detect_platform_from_url(url) == "twitter"
    assert is_x_status_url(url) is True
    assert normalize_media_url(url) == "https://x.com/nexora/status/1900000000000000001"


@pytest.mark.parametrize(
    "url",
    [
        "https://x.com/nexora",
        "https://twitter.com/search?q=nexora",
        "https://x.com/home",
        "https://x.com/nexora/status/not-a-status-id",
    ],
)
def test_non_status_x_urls_are_rejected_before_extraction(url: str) -> None:
    service = MediaService()

    with pytest.raises(APIError) as error:
        service.get_metadata(url)

    assert error.value.code == "INVALID_X_URL"
    assert error.value.status_code == 422


def test_x_metadata_exposes_existing_video_and_audio_options(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _twitter_info())

    metadata = service.get_metadata("https://twitter.com/nexora/status/1900000000000000001")

    assert metadata.platform == "twitter"
    assert metadata.title == "X certification video"
    assert metadata.uploader == "Nexora"
    assert metadata.thumbnail_url == "https://example.test/x-thumbnail.jpg"
    assert metadata.duration_seconds == 24
    assert metadata.webpage_url == "https://x.com/nexora/status/1900000000000000001"
    assert [quality.label for quality in metadata.video_qualities] == ["480p", "720p HD"]
    assert metadata.audio_options[0].model_dump() == {"label": "MP3", "extension": "mp3"}


def test_x_metadata_endpoint_preserves_the_existing_response_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _twitter_info())
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = TestClient(app).post(
            "/media/info",
            json={"url": "https://x.com/nexora/status/1900000000000000001"},
        )

        assert response.status_code == 200
        assert response.json()["success"] is True
        assert response.json()["data"]["platform"] == "twitter"
        assert response.json()["data"]["video_qualities"][1]["label"] == "720p HD"
        assert response.json()["data"]["audio_options"] == [{"label": "MP3", "extension": "mp3"}]
        assert "formats" not in response.json()["data"]
    finally:
        app.dependency_overrides.clear()


def test_x_post_without_downloadable_media_returns_a_friendly_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    info = _twitter_info()
    info["formats"] = []
    monkeypatch.setattr(service, "_extract_info", lambda _: info)

    with pytest.raises(APIError) as error:
        service.get_metadata("https://x.com/nexora/status/1900000000000000001")

    assert error.value.code == "X_MEDIA_NOT_AVAILABLE"
    assert error.value.message == _X_MEDIA_NOT_AVAILABLE_MESSAGE
    assert error.value.details == _X_MEDIA_NOT_AVAILABLE_MESSAGE
    assert error.value.status_code == 422
    assert "yt-dlp" not in error.value.details.lower()


@pytest.mark.parametrize(
    ("media_type", "quality_height", "expected_selector"),
    [
        ("video", 720, "x-720"),
        ("audio", None, "bestaudio/best"),
    ],
)
def test_x_download_jobs_reuse_the_existing_video_and_audio_pipeline(
    monkeypatch: pytest.MonkeyPatch,
    media_type: str,
    quality_height: int | None,
    expected_selector: str,
) -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    monkeypatch.setattr(service, "_extract_info", lambda _: _twitter_info())
    threads: list[_FakeThread] = []

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)
    job = service.create_download_job(
        MediaDownloadRequest(
            url="https://twitter.com/nexora/status/1900000000000000001",
            media_type=media_type,
            quality_height=quality_height,
        )
    )

    assert job.platform == "twitter"
    assert job.media_url == "https://x.com/nexora/status/1900000000000000001"
    assert job.format_id == expected_selector
    assert threads[0].started is True
    assert threads[0].args[2] == expected_selector
    assert threads[0].args[3] == media_type


def test_x_job_creation_reuses_the_snapshot_for_equivalent_twitter_urls(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    monkeypatch.setattr(service, "_extract_info", lambda _: _twitter_info())
    service.get_metadata("https://twitter.com/nexora/status/1900000000000000001")
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(AssertionError("unexpected re-extraction")),
    )
    monkeypatch.setattr(media_service_module.threading, "Thread", _FakeThread)

    job = service.create_download_job(
        MediaDownloadRequest(
            url="https://x.com/nexora/status/1900000000000000001",
            quality_height=720,
        )
    )

    assert job.platform == "twitter"
    assert service._snapshot_cache.get(job.media_url) is not None


def test_x_snapshot_download_refreshes_transport_and_discards_processed_fields() -> None:
    service = MediaService()
    snapshot = _twitter_info()
    snapshot.update(
        {
            "requested_formats": [{"format_id": "x-720", "url": "https://expired.example.test/video"}],
            "requested_downloads": [{"filepath": "expired.mp4"}],
        }
    )
    downloader = _RefreshingTwitterYoutubeDL()

    service._process_download_with_youtube_dl(
        downloader,
        job_id=uuid4(),
        url="https://x.com/nexora/status/1900000000000000001",
        output_type="audio",
        format_selector="bestaudio/best",
        download_info=snapshot,
        detected_platform="twitter",
    )

    assert downloader.refresh_calls == [
        ("https://x.com/nexora/status/1900000000000000001", False, False)
    ]
    assert downloader.processed_info["formats"][0]["url"] == "https://fresh.example.test/video"
    assert "requested_formats" not in downloader.processed_info
    assert "requested_downloads" not in downloader.processed_info
    assert downloader.processed_info["title"] == "X certification video"


@pytest.mark.parametrize(
    ("message", "expected_code"),
    [
        ("No video could be found in this tweet", "X_MEDIA_NOT_AVAILABLE"),
        ("This post is private", "VIDEO_PRIVATE"),
        ("This post is unavailable", "VIDEO_UNAVAILABLE"),
    ],
)
def test_x_extraction_failures_use_standardized_errors(
    monkeypatch: pytest.MonkeyPatch,
    message: str,
    expected_code: str,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: (_ for _ in ()).throw(DownloadError(message)))

    with pytest.raises(APIError) as error:
        service.get_metadata("https://x.com/nexora/status/1900000000000000001")

    assert error.value.code == expected_code
    if expected_code == "X_MEDIA_NOT_AVAILABLE":
        assert error.value.message == _X_MEDIA_NOT_AVAILABLE_MESSAGE
        assert error.value.details == _X_MEDIA_NOT_AVAILABLE_MESSAGE
        assert error.value.status_code == 422
    assert "yt-dlp" not in error.value.details.lower()


def _twitter_info() -> dict:
    return {
        "id": "1900000000000000001",
        "title": "X certification video",
        "uploader": "Nexora",
        "thumbnail": "https://example.test/x-thumbnail.jpg",
        "duration": 24,
        "webpage_url": "https://twitter.com/nexora/status/1900000000000000001",
        "extractor": "Twitter",
        "extractor_key": "Twitter",
        "formats": [
            {
                "format_id": "x-480",
                "width": 854,
                "height": 480,
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "mp4a.40.2",
                "filesize": 1_000_000,
                "url": "https://cached.example.test/480",
            },
            {
                "format_id": "x-720",
                "width": 1280,
                "height": 720,
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": "mp4a.40.2",
                "filesize": 2_000_000,
                "url": "https://cached.example.test/720",
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


class _RefreshingTwitterYoutubeDL:
    def __init__(self) -> None:
        self.refresh_calls: list[tuple[str, bool, bool]] = []
        self.processed_info: dict = {}

    def extract_info(self, url: str, *, download: bool, process: bool = True) -> dict:
        self.refresh_calls.append((url, download, process))
        refreshed = _twitter_info()
        refreshed["formats"][0]["url"] = "https://fresh.example.test/video"
        return refreshed

    def process_ie_result(self, info: dict, *, download: bool) -> dict:
        assert download is True
        self.processed_info = info
        return info
