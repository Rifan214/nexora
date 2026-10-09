from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_instagram_user_session_store
from app.main import create_app
from app.models.instagram_auth import InstagramAuthSource, InstagramAuthStatus
from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore

_SYNTHETIC_SESSIONID = "synthetic_instagram_session_12345%3AABC"
_SYNTHETIC_DS_USER_ID = "61234567890"
_SYNTHETIC_CSRFTOKEN = "csrf_token_test_abc"


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralInstagramUserSessionStore:
    return EphemeralInstagramUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def client(session_store: EphemeralInstagramUserSessionStore) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_instagram_user_session_store] = lambda: session_store
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# ==============================================================================
# A. POST /auth/instagram/session Creation Tests
# ==============================================================================

def test_create_session_success(client: TestClient, session_store: EphemeralInstagramUserSessionStore) -> None:
    response = client.post(
        "/auth/instagram/session",
        json={
            "sessionid": _SYNTHETIC_SESSIONID,
            "ds_user_id": _SYNTHETIC_DS_USER_ID,
            "csrftoken": _SYNTHETIC_CSRFTOKEN,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["message"] == "Ephemeral Instagram session created"

    data = body["data"]
    assert "session_id" in data
    assert len(data["session_id"]) == 32
    assert data["source"] == InstagramAuthSource.USER_SESSION.value
    assert data["status"] == InstagramAuthStatus.AVAILABLE.value
    assert data["authenticated"] is True
    assert data["created_at"] is not None
    assert data["expires_at"] is not None
    assert isinstance(data["expires_in_seconds"], int)
    assert data["expires_in_seconds"] > 0

    # Ensure raw credentials NEVER leak into the response payload or headers
    assert _SYNTHETIC_SESSIONID not in response.text
    assert _SYNTHETIC_DS_USER_ID not in response.text
    assert _SYNTHETIC_CSRFTOKEN not in response.text


def test_create_session_minimal_only_sessionid(client: TestClient) -> None:
    response = client.post(
        "/auth/instagram/session",
        json={"sessionid": _SYNTHETIC_SESSIONID},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert "session_id" in body["data"]


def test_create_session_missing_sessionid(client: TestClient) -> None:
    response = client.post(
        "/auth/instagram/session",
        json={"ds_user_id": _SYNTHETIC_DS_USER_ID},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert _SYNTHETIC_DS_USER_ID not in response.text


def test_create_session_empty_sessionid(client: TestClient) -> None:
    response = client.post(
        "/auth/instagram/session",
        json={"sessionid": "   "},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"


# ==============================================================================
# B. GET /auth/instagram/session/{session_id} Status Lookup Tests
# ==============================================================================

def test_get_session_success(client: TestClient) -> None:
    create_resp = client.post(
        "/auth/instagram/session",
        json={"sessionid": _SYNTHETIC_SESSIONID},
    )
    assert create_resp.status_code == 201
    session_id = create_resp.json()["data"]["session_id"]

    get_resp = client.get(f"/auth/instagram/session/{session_id}")
    assert get_resp.status_code == 200
    body = get_resp.json()
    assert body["success"] is True
    assert body["data"]["session_id"] == session_id
    assert body["data"]["status"] == InstagramAuthStatus.AVAILABLE.value
    assert body["data"]["authenticated"] is True
    assert body["data"]["expires_in_seconds"] > 0
    assert _SYNTHETIC_SESSIONID not in get_resp.text


def test_get_session_unknown_returns_404(client: TestClient) -> None:
    unknown_id = "0123456789abcdef0123456789abcdef"
    resp = client.get(f"/auth/instagram/session/{unknown_id}")
    assert resp.status_code == 404
    body = resp.json()
    assert body["success"] is False
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


def test_get_session_invalid_format_returns_404(client: TestClient) -> None:
    resp = client.get("/auth/instagram/session/not-a-valid-hex-id")
    assert resp.status_code == 404
    body = resp.json()
    assert body["success"] is False
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


# ==============================================================================
# C. DELETE /auth/instagram/session/{session_id} Revocation Tests
# ==============================================================================

def test_revoke_session_success(client: TestClient) -> None:
    create_resp = client.post(
        "/auth/instagram/session",
        json={"sessionid": _SYNTHETIC_SESSIONID},
    )
    session_id = create_resp.json()["data"]["session_id"]

    del_resp = client.delete(f"/auth/instagram/session/{session_id}")
    assert del_resp.status_code == 200
    del_body = del_resp.json()
    assert del_body["success"] is True
    assert del_body["message"] == "Ephemeral Instagram session revoked"
    assert del_body["data"]["session_id"] == session_id
    assert del_body["data"]["status"] == InstagramAuthStatus.INVALID.value
    assert del_body["data"]["revoked"] is True

    # Subsequent GET returns status INVALID
    get_resp = client.get(f"/auth/instagram/session/{session_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["data"]["status"] == InstagramAuthStatus.INVALID.value
    assert get_resp.json()["data"]["authenticated"] is False


def test_revoke_unknown_session_returns_404(client: TestClient) -> None:
    unknown_id = "0123456789abcdef0123456789abcdef"
    resp = client.delete(f"/auth/instagram/session/{unknown_id}")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "SESSION_NOT_FOUND"
