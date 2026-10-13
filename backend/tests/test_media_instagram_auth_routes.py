from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_instagram_user_session_store, get_x_user_session_store, get_tiktok_user_session_store
from app.api.routes.media import get_media_service
from app.core.config import get_settings
from app.main import create_app
from app.models.instagram_auth import InstagramAuthStatus
from app.models.media import AvailableQuality, MediaMetadata
from app.models.requests import MediaDownloadRequest
from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore
from app.services.media_service import MediaService
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore
from app.services.x_user_session_store import EphemeralXUserSessionStore

_IG_URL = "https://www.instagram.com/reel/C_test_12345/"
_TIKTOK_URL = "https://www.tiktok.com/@user/video/7123456789012345678"
_X_URL = "https://x.com/jack/status/20"


@pytest.fixture(autouse=True)
def clear_caches() -> None:
    get_settings.cache_clear()
    get_media_service.cache_clear()
    yield
    get_settings.cache_clear()
    get_media_service.cache_clear()


@pytest.fixture
def ig_store(tmp_path: Path) -> EphemeralInstagramUserSessionStore:
    return EphemeralInstagramUserSessionStore(storage_dir=tmp_path / "ig", cleanup_on_startup=True)


@pytest.fixture
def x_store(tmp_path: Path) -> EphemeralXUserSessionStore:
    return EphemeralXUserSessionStore(storage_dir=tmp_path / "x", cleanup_on_startup=True)


@pytest.fixture
def tiktok_store(tmp_path: Path) -> EphemeralTikTokUserSessionStore:
    return EphemeralTikTokUserSessionStore(storage_dir=tmp_path / "tt", cleanup_on_startup=True)


@pytest.fixture
def client(
    ig_store: EphemeralInstagramUserSessionStore,
    x_store: EphemeralXUserSessionStore,
    tiktok_store: EphemeralTikTokUserSessionStore,
) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_instagram_user_session_store] = lambda: ig_store
    app.dependency_overrides[get_x_user_session_store] = lambda: x_store
    app.dependency_overrides[get_tiktok_user_session_store] = lambda: tiktok_store
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _mock_metadata(url: str, platform: str) -> MediaMetadata:
    return MediaMetadata(
        id="test_media_123",
        platform=platform,
        title="Test Media Title",
        webpage_url=url,
        extractor=platform,
        extractor_key=platform.capitalize(),
        video_qualities=[AvailableQuality(label="720p", height=720, extension="mp4")],
        audio_options=[],
    )


# ==============================================================================
# 1. Instagram-Session-ID Header Acceptance & Routing
# ==============================================================================

def test_media_info_with_valid_instagram_session(
    client: TestClient,
    ig_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = ig_store.create_session(sessionid="test_sessionid_abc")

    with patch("app.services.media_service.MediaService.get_metadata") as mock_get_metadata:
        mock_get_metadata.return_value = _mock_metadata(_IG_URL, "instagram")

        resp = client.post(
            "/media/info",
            json={"url": _IG_URL},
            headers={"Instagram-Session-ID": session.session_id},
        )

        assert resp.status_code == 200
        mock_get_metadata.assert_called_once_with(
            _IG_URL,
            auth_source="user_session",
            auth_session_id=session.session_id,
        )


def test_media_info_without_session_uses_guest(
    client: TestClient,
) -> None:
    with patch("app.services.media_service.MediaService.get_metadata") as mock_get_metadata:
        mock_get_metadata.return_value = _mock_metadata(_IG_URL, "instagram")

        resp = client.post(
            "/media/info",
            json={"url": _IG_URL},
        )

        assert resp.status_code == 200
        mock_get_metadata.assert_called_once_with(_IG_URL)


# ==============================================================================
# 2. Cross-Platform Header Isolation
# ==============================================================================

def test_instagram_session_header_ignored_for_tiktok_url(
    client: TestClient,
    ig_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = ig_store.create_session(sessionid="test_sessionid_abc")

    with patch("app.services.media_service.MediaService.get_metadata") as mock_get_metadata:
        mock_get_metadata.return_value = _mock_metadata(_TIKTOK_URL, "tiktok")

        resp = client.post(
            "/media/info",
            json={"url": _TIKTOK_URL},
            headers={"Instagram-Session-ID": session.session_id},
        )

        assert resp.status_code == 200
        # For TikTok URL, auth_source should remain guest because Instagram-Session-ID was provided
        mock_get_metadata.assert_called_once_with(_TIKTOK_URL)


def test_tiktok_session_header_ignored_for_instagram_url(
    client: TestClient,
    tiktok_store: EphemeralTikTokUserSessionStore,
) -> None:
    tt_session = tiktok_store.create_session(sessionid="test_tt_sessionid")

    with patch("app.services.media_service.MediaService.get_metadata") as mock_get_metadata:
        mock_get_metadata.return_value = _mock_metadata(_IG_URL, "instagram")

        resp = client.post(
            "/media/info",
            json={"url": _IG_URL},
            headers={"TikTok-Session-ID": tt_session.session_id},
        )

        assert resp.status_code == 200
        mock_get_metadata.assert_called_once_with(_IG_URL)


# ==============================================================================
# 3. Invalid & Expired Instagram Session Handling
# ==============================================================================

def test_media_info_unknown_session_returns_404(client: TestClient) -> None:
    resp = client.post(
        "/media/info",
        json={"url": _IG_URL},
        headers={"Instagram-Session-ID": "0123456789abcdef0123456789abcdef"},
    )
    assert resp.status_code == 404
    body = resp.json()
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


def test_media_info_revoked_session_returns_401(
    client: TestClient,
    ig_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = ig_store.create_session(sessionid="test_sessionid_abc")
    ig_store.invalidate(session.session_id)

    resp = client.post(
        "/media/info",
        json={"url": _IG_URL},
        headers={"Instagram-Session-ID": session.session_id},
    )
    assert resp.status_code == 401
    body = resp.json()
    assert body["error"]["code"] == "SESSION_INVALID"


# ==============================================================================
# 4. Media Download Route with Instagram-Session-ID & Snapshot Isolation
# ==============================================================================

def test_media_download_with_valid_instagram_session(
    client: TestClient,
    ig_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = ig_store.create_session(sessionid="test_sessionid_abc")

    with patch("app.services.media_service.MediaService.create_download_job") as mock_create_job:
        mock_job = MagicMock()
        mock_job.job_id = uuid4()
        mock_create_job.return_value = mock_job

        resp = client.post(
            "/media/download",
            json={"url": _IG_URL, "media_type": "video", "quality_height": 1080},
            headers={"Instagram-Session-ID": session.session_id},
        )

        assert resp.status_code == 200
        mock_create_job.assert_called_once()
        args, kwargs = mock_create_job.call_args
        assert isinstance(args[0], MediaDownloadRequest)
        assert args[0].url == _IG_URL
        assert kwargs["auth_source"] == "user_session"
        assert kwargs["auth_session_id"] == session.session_id


def test_media_download_does_not_downgrade_when_guest_snapshot_exists(
    ig_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = ig_store.create_session(sessionid="test_sessionid_abc")
    service = MediaService()

    # Seed a guest snapshot in the cache for the same URL
    service._snapshot_cache.put(
        _IG_URL,
        {"title": "Guest cached title", "extractor": "instagram", "id": "123"},
        authenticated=False,
        auth_source="guest",
        session_id=None,
    )

    request = MediaDownloadRequest(url=_IG_URL, media_type="video", quality_height=1080)
    with patch.object(service, "_start_download_worker") as mock_start_worker, \
         patch.object(service, "_extract_and_cache_supported_info") as mock_extract:
        mock_extract.return_value = (
            {
                "title": "Auth title",
                "extractor": "instagram",
                "id": "123",
                "formats": [
                    {
                        "format_id": "1",
                        "height": 1080,
                        "vcodec": "h264",
                        "acodec": "aac",
                        "ext": "mp4",
                    }
                ],
            },
            "instagram",
            True,
            _IG_URL,
        )

        job = service.create_download_job(
            request,
            auth_source="user_session",
            auth_session_id=session.session_id,
        )

        assert job is not None
        mock_start_worker.assert_called_once()
        call_kwargs = mock_start_worker.call_args.kwargs
        assert call_kwargs["auth_source"] == "user_session"
        assert call_kwargs["auth_session_id"] == session.session_id
