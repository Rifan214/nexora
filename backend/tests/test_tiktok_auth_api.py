from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_tiktok_user_session_store
from app.main import create_app
from app.models.tiktok_auth import TikTokAuthSource, TikTokAuthStatus
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore

_SYNTHETIC_SESSIONID = "synthetic_sessionid_abc123"
_SYNTHETIC_SID_TT = "synthetic_sid_tt_def456"


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralTikTokUserSessionStore:
    return EphemeralTikTokUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def client(session_store: EphemeralTikTokUserSessionStore) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_tiktok_user_session_store] = lambda: session_store
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# ==============================================================================
# A. POST /auth/tiktok/session Creation Tests
# ==============================================================================

def test_create_session_success(client: TestClient, session_store: EphemeralTikTokUserSessionStore) -> None:
    response = client.post(
        "/auth/tiktok/session",
        json={"sessionid": _SYNTHETIC_SESSIONID, "sid_tt": _SYNTHETIC_SID_TT},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["message"] == "Ephemeral TikTok session created"

    data = body["data"]
    assert "session_id" in data
    assert len(data["session_id"]) == 32
    assert data["source"] == TikTokAuthSource.USER_SESSION.value
    assert data["status"] == TikTokAuthStatus.AVAILABLE.value
    assert data["authenticated"] is True
    assert data["created_at"] is not None
    assert data["expires_at"] is not None
    assert isinstance(data["expires_in_seconds"], int)
    assert data["expires_in_seconds"] > 0

    # Ensure raw credentials NEVER leak into the response payload or headers
    assert _SYNTHETIC_SESSIONID not in response.text
    assert _SYNTHETIC_SID_TT not in response.text
    assert "cookie" not in data
    assert "cookie_file" not in data
    assert "temp_cookie_file" not in data

    # Verify session was registered in the store
    assert session_store.is_valid(data["session_id"]) is True


def test_create_session_without_sid_tt(client: TestClient, session_store: EphemeralTikTokUserSessionStore) -> None:
    response = client.post(
        "/auth/tiktok/session",
        json={"sessionid": _SYNTHETIC_SESSIONID},
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert session_store.is_valid(data["session_id"]) is True
    assert _SYNTHETIC_SESSIONID not in response.text


# ==============================================================================
# B. Input Validation Tests
# ==============================================================================

def test_create_session_missing_sessionid(client: TestClient) -> None:
    response = client.post("/auth/tiktok/session", json={"sid_tt": _SYNTHETIC_SID_TT})
    assert response.status_code == 422
    assert response.json()["success"] is False
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_create_session_empty_or_whitespace(client: TestClient) -> None:
    # Empty string
    r1 = client.post("/auth/tiktok/session", json={"sessionid": "", "sid_tt": _SYNTHETIC_SID_TT})
    assert r1.status_code == 422
    assert r1.json()["success"] is False

    # Whitespace only
    r2 = client.post("/auth/tiktok/session", json={"sessionid": "   ", "sid_tt": _SYNTHETIC_SID_TT})
    assert r2.status_code == 422

    r3 = client.post("/auth/tiktok/session", json={"sessionid": _SYNTHETIC_SESSIONID, "sid_tt": "   \t\n "})
    assert r3.status_code == 422


def test_create_session_excessive_length(client: TestClient) -> None:
    too_long = "a" * 1025
    response = client.post("/auth/tiktok/session", json={"sessionid": too_long})
    assert response.status_code == 422
    assert response.json()["success"] is False


def test_create_session_malformed_json(client: TestClient) -> None:
    response = client.post(
        "/auth/tiktok/session",
        content="not-json",
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_create_session_forbids_extra_fields(client: TestClient) -> None:
    payload = {
        "sessionid": _SYNTHETIC_SESSIONID,
        "sid_tt": _SYNTHETIC_SID_TT,
        "session_id": "malicious_injected_id",
        "ttl": 999999,
        "cookie_file": "/etc/passwd",
    }
    response = client.post("/auth/tiktok/session", json=payload)
    assert response.status_code == 422
    assert response.json()["success"] is False
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


# ==============================================================================
# C. GET /auth/tiktok/session/{session_id} Tests
# ==============================================================================

def test_get_valid_session(client: TestClient) -> None:
    create_res = client.post(
        "/auth/tiktok/session",
        json={"sessionid": _SYNTHETIC_SESSIONID, "sid_tt": _SYNTHETIC_SID_TT},
    )
    session_id = create_res.json()["data"]["session_id"]

    get_res = client.get(f"/auth/tiktok/session/{session_id}")
    assert get_res.status_code == 200
    body = get_res.json()
    assert body["success"] is True
    data = body["data"]
    assert data["session_id"] == session_id
    assert data["status"] == TikTokAuthStatus.AVAILABLE.value
    assert data["authenticated"] is True
    assert data["source"] == TikTokAuthSource.USER_SESSION.value
    assert data["expires_in_seconds"] > 0
    assert _SYNTHETIC_SESSIONID not in get_res.text
    assert _SYNTHETIC_SID_TT not in get_res.text


def test_get_expired_session(tmp_path: Path) -> None:
    clock = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path, now=lambda: clock)
    app = create_app()
    app.dependency_overrides[get_tiktok_user_session_store] = lambda: store

    with TestClient(app) as custom_client:
        create_res = custom_client.post(
            "/auth/tiktok/session",
            json={"sessionid": _SYNTHETIC_SESSIONID, "sid_tt": _SYNTHETIC_SID_TT},
        )
        session_id = create_res.json()["data"]["session_id"]

        # Advance clock past default TTL (1 hour)
        clock += timedelta(hours=2)

        get_res = custom_client.get(f"/auth/tiktok/session/{session_id}")
        assert get_res.status_code == 200
        data = get_res.json()["data"]
        assert data["status"] == TikTokAuthStatus.EXPIRED.value
        assert data["authenticated"] is False
        assert data["expires_in_seconds"] == 0


def test_get_unknown_session_returns_404(client: TestClient) -> None:
    unknown_id = "0123456789abcdef0123456789abcdef"
    response = client.get(f"/auth/tiktok/session/{unknown_id}")
    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


def test_get_path_traversal_session_returns_404(client: TestClient) -> None:
    response = client.get("/auth/tiktok/session/../../etc/passwd")
    assert response.status_code in (404, 422)


# ==============================================================================
# D. DELETE /auth/tiktok/session/{session_id} Tests
# ==============================================================================

def test_delete_session_success(client: TestClient, session_store: EphemeralTikTokUserSessionStore) -> None:
    create_res = client.post(
        "/auth/tiktok/session",
        json={"sessionid": _SYNTHETIC_SESSIONID, "sid_tt": _SYNTHETIC_SID_TT},
    )
    session_id = create_res.json()["data"]["session_id"]
    assert session_store.is_valid(session_id) is True

    delete_res = client.delete(f"/auth/tiktok/session/{session_id}")
    assert delete_res.status_code == 200
    body = delete_res.json()
    assert body["success"] is True
    assert body["message"] == "Ephemeral TikTok session revoked"
    assert body["data"]["session_id"] == session_id
    assert body["data"]["status"] == TikTokAuthStatus.INVALID.value
    assert body["data"]["revoked"] is True

    # Subsequent GET reflects invalid state
    get_res = client.get(f"/auth/tiktok/session/{session_id}")
    assert get_res.status_code == 200
    assert get_res.json()["data"]["status"] == TikTokAuthStatus.INVALID.value
    assert get_res.json()["data"]["authenticated"] is False


def test_delete_unknown_session_returns_404(client: TestClient) -> None:
    unknown_id = "0123456789abcdef0123456789abcdef"
    response = client.delete(f"/auth/tiktok/session/{unknown_id}")
    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


# ==============================================================================
# E. Sensitive Data Redaction Tests
# ==============================================================================

def test_sensitive_credentials_never_logged_on_validation_error(
    client: TestClient,
    caplog: pytest.LogCaptureFixture,
) -> None:
    with caplog.at_level(logging.DEBUG):
        client.post(
            "/auth/tiktok/session",
            json={"sessionid": "a" * 1025, "sid_tt": "super_secret_sid"},
        )
    assert "super_secret_sid" not in caplog.text
