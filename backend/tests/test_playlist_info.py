from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.routes.media import get_media_service
from app.core.exceptions import APIError
from app.main import create_app
from app.services.media_service import MediaService


def test_playlist_info_returns_lightweight_importable_items(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_playlist_info", lambda _: _playlist_info())

    metadata = service.get_playlist_metadata(
        "https://www.youtube.com/playlist?list=playlist-test"
    )

    assert metadata.model_dump() == {
        "title": "Playlist test",
        "total_count": 2,
        "items": [
            {
                "title": "First video",
                "thumbnail_url": "https://example.test/first.jpg",
                "webpage_url": "https://www.youtube.com/watch?v=first",
                "duration_seconds": 61,
            },
            {
                "title": "Second video",
                "thumbnail_url": None,
                "webpage_url": "https://www.youtube.com/watch?v=second",
                "duration_seconds": None,
            },
        ],
    }


def test_playlist_info_endpoint_does_not_expose_formats_or_create_jobs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    monkeypatch.setattr(service, "_extract_playlist_info", lambda _: _playlist_info())
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = TestClient(app).post(
            "/media/playlist/info",
            json={"url": "https://www.youtube.com/playlist?list=playlist-test"},
        )

        assert response.status_code == 200
        data = response.json()["data"]
        assert data["title"] == "Playlist test"
        assert data["total_count"] == 2
        assert "formats" not in str(data)
        assert "video_qualities" not in data
        assert "audio_options" not in data
    finally:
        app.dependency_overrides.clear()


def test_non_playlist_urls_are_rejected_by_playlist_preview(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()

    def raise_not_a_playlist(_: str) -> dict:
        raise APIError(
            code="NOT_A_PLAYLIST",
            message="Playlist unavailable",
            details="The supplied URL does not reference a playlist",
            status_code=422,
        )

    monkeypatch.setattr(service, "_extract_playlist_info", raise_not_a_playlist)
    with pytest.raises(APIError) as error:
        service.get_playlist_metadata("https://www.youtube.com/watch?v=not-a-playlist")

    assert error.value.code == "NOT_A_PLAYLIST"


def _playlist_info() -> dict:
    return {
        "_type": "playlist",
        "extractor_key": "YoutubeTab",
        "title": "Playlist test",
        "entries": [
            {
                "id": "first",
                "extractor_key": "Youtube",
                "title": "First video",
                "thumbnail": "https://example.test/first.jpg",
                "duration": 61,
            },
            {
                "id": "second",
                "extractor_key": "Youtube",
                "title": "Second video",
            },
        ],
    }
