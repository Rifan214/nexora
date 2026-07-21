from __future__ import annotations

import threading

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

import app.services.media_service as media_service_module
from app.api.routes.media import get_media_service
from app.core.exceptions import APIError
from app.main import create_app
from app.models.requests import MediaDownloadRequest
from app.services.job_manager import JobManager, get_job_manager
from app.services.media_service import MediaService


@pytest.fixture(autouse=True)
def clear_job_manager() -> None:
    get_job_manager.cache_clear()
    yield
    get_job_manager.cache_clear()


def test_metadata_exposes_video_and_audio_options_without_raw_format_details(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())

    metadata = service.get_metadata("https://www.youtube.com/watch?v=quality-metadata")
    payload = metadata.model_dump()

    assert "formats" not in payload
    expected_qualities = [
        {
            "label": "360p",
            "height": 360,
            "extension": "mp4",
            "estimated_filesize": 12_000,
        },
        {
            "label": "1080p Full HD",
            "height": 1080,
            "extension": "mp4",
            "estimated_filesize": 113_000,
        },
    ]
    assert payload["video_qualities"] == expected_qualities
    assert payload["audio_options"] == [{"label": "MP3", "extension": "mp3"}]
    assert "audio_available" not in payload
    assert "qualities" not in payload
    assert "format_id" not in str(payload)
    assert "video_codec" not in str(payload)
    assert "audio_codec" not in str(payload)


def test_metadata_endpoint_exposes_audio_options_and_video_qualities(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = TestClient(app).post(
            "/media/info",
            json={"url": "https://www.youtube.com/watch?v=audio-metadata"},
        )

        assert response.status_code == 200
        payload = response.json()["data"]
        assert payload["audio_options"] == [{"label": "MP3", "extension": "mp3"}]
        assert "audio_available" not in payload
        assert "qualities" not in payload
        assert "format_id" not in str(payload)
    finally:
        app.dependency_overrides.clear()


def test_metadata_returns_an_empty_audio_options_list_when_audio_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    info = _youtube_info()
    info["formats"] = [
        {
            "format_id": "299",
            "height": 1080,
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": "none",
        }
    ]
    monkeypatch.setattr(service, "_extract_info", lambda _: info)

    metadata = service.get_metadata("https://www.youtube.com/watch?v=no-audio-metadata")

    assert metadata.audio_options == []


def test_download_request_resolves_quality_height_to_an_internal_selector(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())
    started_threads: list[_FakeThread] = []

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        started_threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)

    job = service.create_download_job(
        MediaDownloadRequest(
            url="https://www.youtube.com/watch?v=quality-download",
            quality_height=1080,
        )
    )

    assert job.format_id == "299+251"
    assert started_threads[0].started is True
    assert started_threads[0].args[2] == "299+251"
    assert started_threads[0].args[3] == "video"


def test_audio_download_request_uses_bestaudio_and_reuses_the_job_worker(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())
    started_threads: list[_FakeThread] = []

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        started_threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)

    job = service.create_download_job(
        MediaDownloadRequest(
            url="https://www.youtube.com/watch?v=audio-download",
            media_type="audio",
        )
    )

    assert job.format_id == "bestaudio/best"
    assert job.output_type == "audio"
    assert started_threads[0].started is True
    assert started_threads[0].args[2] == "bestaudio/best"
    assert started_threads[0].args[3] == "audio"


def test_audio_download_request_requires_an_available_audio_stream(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    info = _youtube_info()
    info["formats"] = [
        {
            "format_id": "299",
            "height": 1080,
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": "none",
        }
    ]
    monkeypatch.setattr(service, "_extract_info", lambda _: info)

    with pytest.raises(APIError) as error:
        service.create_download_job(
            MediaDownloadRequest(
                url="https://www.youtube.com/watch?v=no-audio",
                media_type="audio",
            )
        )

    assert error.value.code == "AUDIO_NOT_AVAILABLE"
    assert error.value.status_code == 409


def test_audio_download_endpoint_returns_a_standardized_unavailable_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    info = _youtube_info()
    info["formats"] = []
    monkeypatch.setattr(service, "_extract_info", lambda _: info)
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = TestClient(app).post(
            "/media/download",
            json={
                "url": "https://www.youtube.com/watch?v=no-audio-endpoint",
                "media_type": "audio",
            },
        )

        assert response.status_code == 409
        assert response.json()["success"] is False
        assert response.json()["error"]["code"] == "AUDIO_NOT_AVAILABLE"
    finally:
        app.dependency_overrides.clear()


def test_audio_download_request_does_not_accept_a_quality_or_format_identifier() -> None:
    with pytest.raises(ValidationError):
        MediaDownloadRequest(
            url="https://www.youtube.com/watch?v=invalid-audio-request",
            media_type="audio",
            format_id="140",
        )


def test_unavailable_quality_returns_a_standardized_api_error(monkeypatch: pytest.MonkeyPatch) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())

    with pytest.raises(APIError) as error:
        service.create_download_job(
            MediaDownloadRequest(
                url="https://www.youtube.com/watch?v=quality-missing",
                quality_height=2160,
            )
        )

    assert error.value.code == "QUALITY_NOT_AVAILABLE"
    assert error.value.status_code == 409
    assert error.value.message == "Requested quality unavailable"


def test_download_endpoint_returns_standardized_error_for_an_unavailable_quality(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_info", lambda _: _youtube_info())
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = TestClient(app).post(
            "/media/download",
            json={
                "url": "https://www.youtube.com/watch?v=quality-missing-endpoint",
                "quality_height": 2160,
            },
        )

        assert response.status_code == 409
        assert response.json()["success"] is False
        assert response.json()["error"]["code"] == "QUALITY_NOT_AVAILABLE"
    finally:
        app.dependency_overrides.clear()


def test_legacy_format_id_is_accepted_during_the_transition() -> None:
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=legacy-client",
        format_id="18",
        type="video",
    )

    assert request.quality_height is None
    assert request.format_id == "18"
    assert request.media_type == "video"


def test_legacy_type_field_remains_an_alias_for_media_type() -> None:
    request = MediaDownloadRequest(
        url="https://www.youtube.com/watch?v=legacy-audio",
        type="audio",
    )

    assert request.media_type == "audio"
    assert request.type == "audio"


def test_job_status_does_not_expose_the_internal_format_selector() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=hidden-selector",
        platform="youtube",
        format_id="399+251",
    )
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager

    try:
        response = TestClient(app).get(f"/jobs/{job.job_id}")

        assert response.status_code == 200
        assert "format_id" not in response.json()["data"]
    finally:
        app.dependency_overrides.clear()


def _youtube_info() -> dict:
    return {
        "title": "Quality Test Video",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "formats": [
            {
                "format_id": "18",
                "height": 360,
                "ext": "mp4",
                "vcodec": "avc1.42001E",
                "acodec": "mp4a.40.2",
                "filesize": 12_000,
            },
            {
                "format_id": "299",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.640028",
                "acodec": "none",
                "filesize": 110_000,
            },
            {
                "format_id": "303",
                "height": 1080,
                "ext": "webm",
                "vcodec": "vp09.00.40.08",
                "acodec": "none",
                "filesize": 105_000,
            },
            {
                "format_id": "399",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "av01.0.08M.08",
                "acodec": "none",
                "filesize": 100_000,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "abr": 128,
                "filesize": 2_000,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
                "filesize": 3_000,
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
