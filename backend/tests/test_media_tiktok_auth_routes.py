from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_tiktok_user_session_store, get_x_user_session_store
from app.api.routes.media import get_media_service
from app.main import create_app
from app.models.job import DownloadJob
from app.models.media import MediaMetadata
from app.services.media_service import MediaService
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore
from app.services.x_user_session_store import EphemeralXUserSessionStore

_TIKTOK_URL = "https://www.tiktok.com/@user/video/7123456789012345678"
_X_URL = "https://x.com/user/status/123"


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralTikTokUserSessionStore:
    return EphemeralTikTokUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def x_session_store(tmp_path: Path) -> EphemeralXUserSessionStore:
    return EphemeralXUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def app_instance(
    session_store: EphemeralTikTokUserSessionStore,
    x_session_store: EphemeralXUserSessionStore,
):
    app = create_app()
    app.dependency_overrides[get_tiktok_user_session_store] = lambda: session_store
    app.dependency_overrides[get_x_user_session_store] = lambda: x_session_store
    return app


@pytest.fixture
def client(app_instance) -> TestClient:
    with TestClient(app_instance) as test_client:
        yield test_client
    app_instance.dependency_overrides.clear()


def test_media_info_guest_request_without_header(
    app_instance,
    client: TestClient,
) -> None:
    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="7123456789012345678",
        title="Test TikTok",
        platform="tiktok",
        source_url=_TIKTOK_URL,
        webpage_url=_TIKTOK_URL,
        extractor="tiktok",
        extractor_key="TikTok",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        response = client.post(
            "/media/info",
            json={"url": _TIKTOK_URL},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True
        assert payload["data"]["title"] == "Test TikTok"
        assert "tiktok_session_id" not in payload["data"]

        mock_media_service.get_metadata.assert_called_once_with(
            _TIKTOK_URL,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_media_info_with_valid_tiktok_session_id(
    app_instance,
    client: TestClient,
    session_store: EphemeralTikTokUserSessionStore,
) -> None:
    session = session_store.create_session(
        sessionid="TEST_SESSIONID_VALUE",
        sid_tt="TEST_SID_TT_VALUE",
    )

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="7123456789012345678",
        title="Protected TikTok",
        platform="tiktok",
        source_url=_TIKTOK_URL,
        webpage_url=_TIKTOK_URL,
        extractor="tiktok",
        extractor_key="TikTok",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        response = client.post(
            "/media/info",
            json={"url": _TIKTOK_URL},
            headers={"TikTok-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True
        assert payload["data"]["title"] == "Protected TikTok"
        assert "tiktok_session_id" not in payload["data"]
        assert "session_id" not in payload["data"]

        mock_media_service.get_metadata.assert_called_once_with(
            _TIKTOK_URL,
            auth_source="user_session",
            auth_session_id=session.session_id,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_media_info_with_unknown_tiktok_session_id(
    client: TestClient,
) -> None:
    response = client.post(
        "/media/info",
        json={"url": _TIKTOK_URL},
        headers={"TikTok-Session-ID": "0123456789abcdef0123456789abcdef"},
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_NOT_FOUND"


def test_media_info_with_malformed_tiktok_session_id(
    client: TestClient,
) -> None:
    response = client.post(
        "/media/info",
        json={"url": _TIKTOK_URL},
        headers={"TikTok-Session-ID": "not-a-valid-hex-token!@#$"},
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_NOT_FOUND"


def test_media_info_with_expired_tiktok_session_id(
    app_instance,
    client: TestClient,
    tmp_path: Path,
) -> None:
    current_time = datetime.now(UTC)
    time_travel_store = EphemeralTikTokUserSessionStore(
        storage_dir=tmp_path,
        now=lambda: current_time,
        cleanup_on_startup=False,
    )
    app_instance.dependency_overrides[get_tiktok_user_session_store] = lambda: time_travel_store

    try:
        session = time_travel_store.create_session(
            sessionid="TEST_SESSIONID_VALUE",
            sid_tt="TEST_SID_TT_VALUE",
            ttl_seconds=60,
        )

        current_time = current_time + timedelta(seconds=61)

        response = client.post(
            "/media/info",
            json={"url": _TIKTOK_URL},
            headers={"TikTok-Session-ID": session.session_id},
        )
        assert response.status_code == 401
        payload = response.json()
        assert payload["success"] is False
        assert payload["error"]["code"] == "SESSION_EXPIRED"
    finally:
        app_instance.dependency_overrides.pop(get_tiktok_user_session_store, None)


def test_media_info_with_revoked_tiktok_session_id(
    client: TestClient,
    session_store: EphemeralTikTokUserSessionStore,
) -> None:
    session = session_store.create_session(
        sessionid="TEST_SESSIONID_VALUE",
        sid_tt="TEST_SID_TT_VALUE",
    )
    session_store.invalidate(session.session_id)

    response = client.post(
        "/media/info",
        json={"url": _TIKTOK_URL},
        headers={"TikTok-Session-ID": session.session_id},
    )
    assert response.status_code == 401
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_INVALID"


def test_media_download_with_valid_tiktok_session_id(
    app_instance,
    client: TestClient,
    session_store: EphemeralTikTokUserSessionStore,
) -> None:
    session = session_store.create_session(
        sessionid="TEST_SESSIONID_VALUE",
        sid_tt="TEST_SID_TT_VALUE",
    )

    mock_job = MagicMock(spec=DownloadJob)
    mock_job.job_id = uuid4()

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.create_download_job.return_value = mock_job

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        response = client.post(
            "/media/download",
            json={
                "url": _TIKTOK_URL,
                "media_type": "video",
                "quality_height": 1080,
            },
            headers={"TikTok-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True

        mock_media_service.create_download_job.assert_called_once()
        _, kwargs = mock_media_service.create_download_job.call_args
        assert kwargs["auth_source"] == "user_session"
        assert kwargs["auth_session_id"] == session.session_id
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_tiktok_session_not_propagated_to_x_url(
    app_instance,
    client: TestClient,
    session_store: EphemeralTikTokUserSessionStore,
) -> None:
    session = session_store.create_session(
        sessionid="TEST_SESSIONID_VALUE",
        sid_tt="TEST_SID_TT_VALUE",
    )

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="123",
        title="Tweet",
        platform="twitter",
        source_url=_X_URL,
        webpage_url=_X_URL,
        extractor="twitter",
        extractor_key="Twitter",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        # Pass TikTok-Session-ID on an X/Twitter URL
        response = client.post(
            "/media/info",
            json={"url": _X_URL},
            headers={"TikTok-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        # TikTok session ID MUST NOT be used for X/Twitter
        mock_media_service.get_metadata.assert_called_once_with(
            _X_URL,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_x_session_not_propagated_to_tiktok_url(
    app_instance,
    client: TestClient,
    x_session_store: EphemeralXUserSessionStore,
) -> None:
    session = x_session_store.create_session(
        auth_token="TEST_AUTH_TOKEN",
        ct0="TEST_CT0",
    )

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="7123456789012345678",
        title="TikTok Video",
        platform="tiktok",
        source_url=_TIKTOK_URL,
        webpage_url=_TIKTOK_URL,
        extractor="tiktok",
        extractor_key="TikTok",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        # Pass X-Session-ID on a TikTok URL
        response = client.post(
            "/media/info",
            json={"url": _TIKTOK_URL},
            headers={"X-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        # X session ID MUST NOT be used for TikTok
        mock_media_service.get_metadata.assert_called_once_with(
            _TIKTOK_URL,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_tiktok_session_not_propagated_to_spoofed_domain(
    app_instance,
    client: TestClient,
    session_store: EphemeralTikTokUserSessionStore,
) -> None:
    session = session_store.create_session(
        sessionid="TEST_SESSIONID",
    )

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="spoofed_id",
        title="Spoofed Video",
        platform="unknown",
        source_url="https://evil-tiktok.com/@user/video/7123456789012345678",
        webpage_url="https://evil-tiktok.com/@user/video/7123456789012345678",
        extractor="generic",
        extractor_key="Generic",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        spoofed_url = "https://evil-tiktok.com/@user/video/7123456789012345678"
        response = client.post(
            "/media/info",
            json={"url": spoofed_url},
            headers={"TikTok-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        # Spoofed domain MUST NOT receive TikTok credentials or user session context
        mock_media_service.get_metadata.assert_called_once_with(
            spoofed_url,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)

