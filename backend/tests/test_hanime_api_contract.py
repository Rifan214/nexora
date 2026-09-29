from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.routes.media import get_media_service
from app.main import create_app
from app.platforms.hanime import HanimeExtractor
from app.services.job_manager import JobManager, get_job_manager
from app.services.media_service import MediaService
from app.services.queue_manager import QueueManager


@pytest.fixture
def mock_hanime_info_dict() -> dict:
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


def _create_test_app(info_dict: dict | None = None) -> tuple[TestClient, MediaService]:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    mock_extractor = MagicMock(spec=HanimeExtractor)
    if info_dict is not None:
        mock_extractor.extract = AsyncMock(return_value=info_dict)

    service = MediaService(
        hanime_extractor=mock_extractor,
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    service._download_job_background = MagicMock()

    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service
    return TestClient(app), service


def test_api_media_info_hanime_contract(mock_hanime_info_dict: dict) -> None:
    """1. Verify POST /media/info returns standard contract with Hanime qualities and audio."""
    client, _ = _create_test_app(mock_hanime_info_dict)

    response = client.post(
        "/media/info",
        json={"url": "https://hanime.tv/videos/hentai/terra-story-1"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert "data" in body

    data = body["data"]
    assert data["platform"] == "hanime"
    assert data["title"] == "Terra Story 1"
    assert data["duration_seconds"] == 1757
    assert data["thumbnail_url"] == "https://webedn.hanime.tv/media/covers/terra-story-1.jpg"
    assert data["webpage_url"] == "https://hanime.tv/videos/hentai/terra-story-1"

    # Video qualities
    qualities = data["video_qualities"]
    assert len(qualities) == 3
    assert {q["height"] for q in qualities} == {720, 480, 360}
    assert any(q["height"] == 720 and "720" in q["label"] for q in qualities)
    assert any(q["height"] == 480 and "480" in q["label"] for q in qualities)
    assert any(q["height"] == 360 and "360" in q["label"] for q in qualities)
    assert all(q["extension"] == "mp4" for q in qualities)

    # Audio options
    audio_options = data["audio_options"]
    assert len(audio_options) == 1
    assert audio_options[0]["label"] == "MP3"
    assert audio_options[0]["extension"] == "mp3"

    # Hygiene: no internal HLS tokens, secrets, or AES keys
    assert "formats" not in data
    assert "x-token" not in str(body)
    assert "x-signature" not in str(body)
    assert "secret" not in str(body)


def test_api_media_info_invalid_hanime_url_rejected() -> None:
    """2. Verify POST /media/info rejects invalid Hanime path with 422."""
    client, _ = _create_test_app()

    response = client.post(
        "/media/info",
        json={"url": "https://hanime.tv/browse/trending"},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "INVALID_HANIME_URL"
    assert "Invalid Hanime URL" in body["message"]


def test_api_media_info_no_playable_formats_rejected() -> None:
    """3. Verify POST /media/info surfaces 422 when Hanime video has no playable streams."""
    empty_formats_dict = {
        "id": "9999",
        "title": "Empty Video",
        "webpage_url": "https://hanime.tv/videos/hentai/empty-video",
        "extractor": "hanime",
        "extractor_key": "Hanime",
        "formats": [],
    }
    client, _ = _create_test_app(empty_formats_dict)

    response = client.post(
        "/media/info",
        json={"url": "https://hanime.tv/videos/hentai/empty-video"},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "HANIME_NO_PLAYABLE_FORMATS"


def test_api_media_download_video_job_creation(mock_hanime_info_dict: dict) -> None:
    """4. Verify POST /media/download creates a valid 720p Hanime download job."""
    client, service = _create_test_app(mock_hanime_info_dict)

    response = client.post(
        "/media/download",
        json={
            "url": "https://hanime.tv/videos/hentai/terra-story-1",
            "media_type": "video",
            "quality_height": 720,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert "job_id" in body["data"]

    job_id = UUID(body["data"]["job_id"])
    job = service._job_manager.get_job(job_id)
    assert job is not None
    assert job.platform == "hanime"
    assert job.format_id == "720p"
    assert job.output_type == "video"
    assert job.title == "Terra Story 1"


def test_api_media_download_audio_job_creation(mock_hanime_info_dict: dict) -> None:
    """5. Verify POST /media/download creates a valid MP3 Hanime audio download job."""
    client, service = _create_test_app(mock_hanime_info_dict)

    response = client.post(
        "/media/download",
        json={
            "url": "https://hanime.tv/videos/hentai/terra-story-1",
            "media_type": "audio",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert "job_id" in body["data"]

    job_id = UUID(body["data"]["job_id"])
    job = service._job_manager.get_job(job_id)
    assert job is not None
    assert job.platform == "hanime"
    assert job.output_type == "audio"
