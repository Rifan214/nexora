from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_x_user_session_store
from app.api.routes.media import get_media_service
from app.main import create_app
from app.models.job import DownloadJob
from app.models.media import MediaMetadata
from app.services.media_service import MediaService
from app.services.x_user_session_store import EphemeralXUserSessionStore


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralXUserSessionStore:
    return EphemeralXUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def app_instance(session_store: EphemeralXUserSessionStore):
    app = create_app()
    app.dependency_overrides[get_x_user_session_store] = lambda: session_store
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
        id="123",
        title="Test Tweet",
        platform="twitter",
        source_url="https://x.com/user/status/123",
        webpage_url="https://x.com/user/status/123",
        extractor="twitter",
        extractor_key="Twitter",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        response = client.post(
            "/media/info",
            json={"url": "https://x.com/user/status/123"},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True
        assert payload["data"]["title"] == "Test Tweet"
        assert "x_session_id" not in payload["data"]

        mock_media_service.get_metadata.assert_called_once_with(
            "https://x.com/user/status/123",
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_media_info_with_valid_x_session_id(
    app_instance,
    client: TestClient,
    session_store: EphemeralXUserSessionStore,
) -> None:
    session = session_store.create_session(
        auth_token="TEST_AUTH_TOKEN_VALUE",
        ct0="TEST_CT0_VALUE",
    )

    mock_media_service = MagicMock(spec=MediaService)
    mock_media_service.get_metadata.return_value = MediaMetadata(
        id="123",
        title="Protected Tweet",
        platform="twitter",
        source_url="https://x.com/user/status/123",
        webpage_url="https://x.com/user/status/123",
        extractor="twitter",
        extractor_key="Twitter",
        video_qualities=[],
        audio_options=[],
    )

    app_instance.dependency_overrides[get_media_service] = lambda: mock_media_service
    try:
        response = client.post(
            "/media/info",
            json={"url": "https://x.com/user/status/123"},
            headers={"X-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True
        assert payload["data"]["title"] == "Protected Tweet"
        # Session ID must not appear in response payload
        assert "x_session_id" not in payload["data"]
        assert "session_id" not in payload["data"]

        mock_media_service.get_metadata.assert_called_once_with(
            "https://x.com/user/status/123",
            auth_source="user_session",
            auth_session_id=session.session_id,
        )
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_media_info_with_unknown_x_session_id(
    client: TestClient,
) -> None:
    response = client.post(
        "/media/info",
        json={"url": "https://x.com/user/status/123"},
        headers={"X-Session-ID": "0123456789abcdef0123456789abcdef"},
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_NOT_FOUND"


def test_media_info_with_malformed_x_session_id(
    client: TestClient,
) -> None:
    response = client.post(
        "/media/info",
        json={"url": "https://x.com/user/status/123"},
        headers={"X-Session-ID": "not-a-valid-hex-token!@#$"},
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_NOT_FOUND"


def test_media_info_with_expired_x_session_id(
    app_instance,
    client: TestClient,
    tmp_path: Path,
) -> None:
    current_time = datetime.now(UTC)
    time_travel_store = EphemeralXUserSessionStore(
        storage_dir=tmp_path,
        now=lambda: current_time,
        cleanup_on_startup=False,
    )
    app_instance.dependency_overrides[get_x_user_session_store] = lambda: time_travel_store

    try:
        session = time_travel_store.create_session(
            auth_token="TEST_AUTH_TOKEN_VALUE",
            ct0="TEST_CT0_VALUE",
            ttl_seconds=60,
        )

        # Advance time by 61 seconds so it expires
        current_time = current_time + timedelta(seconds=61)

        response = client.post(
            "/media/info",
            json={"url": "https://x.com/user/status/123"},
            headers={"X-Session-ID": session.session_id},
        )
        assert response.status_code == 401
        payload = response.json()
        assert payload["success"] is False
        assert payload["error"]["code"] == "SESSION_EXPIRED"
    finally:
        app_instance.dependency_overrides.pop(get_x_user_session_store, None)


def test_media_info_with_revoked_x_session_id(
    client: TestClient,
    session_store: EphemeralXUserSessionStore,
) -> None:
    session = session_store.create_session(
        auth_token="TEST_AUTH_TOKEN_VALUE",
        ct0="TEST_CT0_VALUE",
    )
    session_store.invalidate(session.session_id)

    response = client.post(
        "/media/info",
        json={"url": "https://x.com/user/status/123"},
        headers={"X-Session-ID": session.session_id},
    )
    assert response.status_code == 401
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_INVALID"


def test_media_download_with_valid_x_session_id(
    app_instance,
    client: TestClient,
    session_store: EphemeralXUserSessionStore,
) -> None:
    session = session_store.create_session(
        auth_token="TEST_AUTH_TOKEN_VALUE",
        ct0="TEST_CT0_VALUE",
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
                "url": "https://x.com/user/status/123",
                "media_type": "video",
                "quality_height": 720,
            },
            headers={"X-Session-ID": session.session_id},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is True
        assert payload["data"]["job_id"] == str(mock_job.job_id)
        assert "x_session_id" not in payload["data"]

        assert mock_media_service.create_download_job.call_count == 1
        args, kwargs = mock_media_service.create_download_job.call_args
        assert kwargs["auth_source"] == "user_session"
        assert kwargs["auth_session_id"] == session.session_id
    finally:
        app_instance.dependency_overrides.pop(get_media_service, None)


def test_media_download_with_invalid_x_session_id(
    client: TestClient,
) -> None:
    response = client.post(
        "/media/download",
        json={
            "url": "https://x.com/user/status/123",
            "media_type": "video",
            "quality_height": 720,
        },
        headers={"X-Session-ID": "0123456789abcdef0123456789abcdef"},
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "SESSION_NOT_FOUND"
