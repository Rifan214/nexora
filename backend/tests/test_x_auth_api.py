from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_x_user_session_store
from app.main import create_app
from app.models.x_auth import XAuthSource, XAuthStatus
from app.services.x_user_session_store import EphemeralXUserSessionStore

_SYNTHETIC_TOKEN = "synthetic_auth_token_abc123"
_SYNTHETIC_CT0 = "synthetic_ct0_def456"


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralXUserSessionStore:
    return EphemeralXUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


@pytest.fixture
def client(session_store: EphemeralXUserSessionStore) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_x_user_session_store] = lambda: session_store
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# ==============================================================================
# A. POST /auth/x/session Creation Tests
# ==============================================================================

def test_create_session_success(client: TestClient, session_store: EphemeralXUserSessionStore) -> None:
    response = client.post(
        "/auth/x/session",
        json={"auth_token": _SYNTHETIC_TOKEN, "ct0": _SYNTHETIC_CT0},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["message"] == "Ephemeral X session created"

    data = body["data"]
    assert "session_id" in data
    assert len(data["session_id"]) == 32
    assert data["source"] == XAuthSource.USER_SESSION.value
    assert data["status"] == XAuthStatus.AVAILABLE.value
    assert data["authenticated"] is True
    assert data["created_at"] is not None
    assert data["expires_at"] is not None
    assert isinstance(data["expires_in_seconds"], int)
    assert data["expires_in_seconds"] > 0

    # Ensure raw credentials NEVER leak into the response payload or headers
    assert _SYNTHETIC_TOKEN not in response.text
    assert _SYNTHETIC_CT0 not in response.text
    assert "cookie" not in data
    assert "cookie_file" not in data
    assert "temp_cookie_file" not in data

    # Verify session was registered in the store
    assert session_store.is_valid(data["session_id"]) is True


# ==============================================================================
# B. Input Validation Tests
# ==============================================================================

def test_create_session_missing_fields(client: TestClient) -> None:
    # Missing ct0
    r1 = client.post("/auth/x/session", json={"auth_token": _SYNTHETIC_TOKEN})
    assert r1.status_code == 422
    assert r1.json()["success"] is False
    assert r1.json()["error"]["code"] == "VALIDATION_ERROR"

    # Missing auth_token
    r2 = client.post("/auth/x/session", json={"ct0": _SYNTHETIC_CT0})
    assert r2.status_code == 422
    assert r2.json()["success"] is False

    # Empty payload
    r3 = client.post("/auth/x/session", json={})
    assert r3.status_code == 422


def test_create_session_empty_or_whitespace(client: TestClient) -> None:
    # Empty string
    r1 = client.post("/auth/x/session", json={"auth_token": "", "ct0": _SYNTHETIC_CT0})
    assert r1.status_code == 422
    assert r1.json()["success"] is False

    # Whitespace only
    r2 = client.post("/auth/x/session", json={"auth_token": "   ", "ct0": _SYNTHETIC_CT0})
    assert r2.status_code == 422

    r3 = client.post("/auth/x/session", json={"auth_token": _SYNTHETIC_TOKEN, "ct0": "   \t\n "})
    assert r3.status_code == 422


def test_create_session_excessive_length(client: TestClient) -> None:
    too_long = "a" * 513
    response = client.post("/auth/x/session", json={"auth_token": too_long, "ct0": _SYNTHETIC_CT0})
    assert response.status_code == 422
    assert response.json()["success"] is False


def test_create_session_malformed_json(client: TestClient) -> None:
    response = client.post(
        "/auth/x/session",
        content="not-json",
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_create_session_forbids_extra_fields(client: TestClient) -> None:
    # Client trying to choose session_id, ttl, or filesystem cookie path
    payload = {
        "auth_token": _SYNTHETIC_TOKEN,
        "ct0": _SYNTHETIC_CT0,
        "session_id": "malicious_injected_id",
        "ttl": 999999,
        "cookie_file": "/etc/passwd",
        "authenticated": False,
    }
    response = client.post("/auth/x/session", json=payload)
    assert response.status_code == 422
    assert response.json()["success"] is False
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


# ==============================================================================
# C. GET /auth/x/session/{session_id} Tests
# ==============================================================================

def test_get_valid_session(client: TestClient) -> None:
    create_res = client.post(
        "/auth/x/session",
        json={"auth_token": _SYNTHETIC_TOKEN, "ct0": _SYNTHETIC_CT0},
    )
    session_id = create_res.json()["data"]["session_id"]

    get_res = client.get(f"/auth/x/session/{session_id}")
    assert get_res.status_code == 200
    body = get_res.json()
    assert body["success"] is True
    data = body["data"]
    assert data["session_id"] == session_id
    assert data["status"] == XAuthStatus.AVAILABLE.value
    assert data["authenticated"] is True
    assert _SYNTHETIC_TOKEN not in get_res.text
    assert _SYNTHETIC_CT0 not in get_res.text


def test_get_expired_session(tmp_path: Path) -> None:
    clock = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    store = EphemeralXUserSessionStore(storage_dir=tmp_path, now=lambda: clock)
    app = create_app()
    app.dependency_overrides[get_x_user_session_store] = lambda: store

    with TestClient(app) as custom_client:
        create_res = custom_client.post(
            "/auth/x/session",
            json={"auth_token": _SYNTHETIC_TOKEN, "ct0": _SYNTHETIC_CT0},
        )
        session_id = create_res.json()["data"]["session_id"]

        # Advance clock past default TTL (1 hour)
        clock += timedelta(hours=2)

        get_res = custom_client.get(f"/auth/x/session/{session_id}")
        assert get_res.status_code == 200
        data = get_res.json()["data"]
        assert data["status"] == XAuthStatus.EXPIRED.value
        assert data["authenticated"] is False
        assert data["expires_in_seconds"] == 0


def test_get_unknown_session_returns_404(client: TestClient) -> None:
    # Valid hex format but non-existent
    unknown_id = "0123456789abcdef0123456789abcdef"
    response = client.get(f"/auth/x/session/{unknown_id}")
    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "SESSION_NOT_FOUND"


def test_get_path_traversal_session_returns_404(client: TestClient) -> None:
    response = client.get("/auth/x/session/../../etc/passwd")
    assert response.status_code in (404, 422)


# ==============================================================================
# D. DELETE /auth/x/session/{session_id} Tests
# ==============================================================================

def test_delete_session_success(client: TestClient, session_store: EphemeralXUserSessionStore) -> None:
    create_res = client.post(
        "/auth/x/session",
        json={"auth_token": _SYNTHETIC_TOKEN, "ct0": _SYNTHETIC_CT0},
    )
    session_id = create_res.json()["data"]["session_id"]

    delete_res = client.delete(f"/auth/x/session/{session_id}")
    assert delete_res.status_code == 200
    body = delete_res.json()
    assert body["success"] is True
    assert body["message"] == "Ephemeral X session revoked"
    assert body["data"]["session_id"] == session_id
    assert body["data"]["status"] == XAuthStatus.INVALID.value
    assert body["data"]["revoked"] is True

    # Subsequent GET reflects invalid state
    get_res = client.get(f"/auth/x/session/{session_id}")
    assert get_res.status_code == 200
    assert get_res.json()["data"]["status"] == XAuthStatus.INVALID.value
    assert get_res.json()["data"]["authenticated"] is False

    # Store no longer considers it valid
    assert session_store.is_valid(session_id) is False


def test_delete_unknown_session_returns_404(client: TestClient) -> None:
    unknown_id = "0123456789abcdef0123456789abcdef"
    response = client.delete(f"/auth/x/session/{unknown_id}")
    assert response.status_code == 404
    assert response.json()["success"] is False
    assert response.json()["error"]["code"] == "SESSION_NOT_FOUND"


def test_delete_one_session_does_not_affect_another(client: TestClient) -> None:
    res_a = client.post("/auth/x/session", json={"auth_token": "token_A_12345", "ct0": "ct0_A_12345"})
    res_b = client.post("/auth/x/session", json={"auth_token": "token_B_67890", "ct0": "ct0_B_67890"})
    id_a = res_a.json()["data"]["session_id"]
    id_b = res_b.json()["data"]["session_id"]

    # Delete session A
    del_res = client.delete(f"/auth/x/session/{id_a}")
    assert del_res.status_code == 200

    # Session A is invalid
    assert client.get(f"/auth/x/session/{id_a}").json()["data"]["status"] == XAuthStatus.INVALID.value

    # Session B remains available and authenticated
    res_b_check = client.get(f"/auth/x/session/{id_b}")
    assert res_b_check.status_code == 200
    assert res_b_check.json()["data"]["status"] == XAuthStatus.AVAILABLE.value
    assert res_b_check.json()["data"]["authenticated"] is True


# ==============================================================================
# E. Security & Redaction Tests
# ==============================================================================

def test_validation_errors_never_log_secret_credentials(
    client: TestClient,
    caplog: pytest.LogCaptureFixture,
) -> None:
    secret_canary = "SUPER_SECRET_CANARY_VALUE_NEVER_LOG_THIS"
    with caplog.at_level(logging.WARNING):
        # Trigger validation error with secret canary value (e.g. excessive length)
        client.post(
            "/auth/x/session",
            json={"auth_token": secret_canary * 20, "ct0": _SYNTHETIC_CT0},
        )

    # Verify canary secret was stripped and NEVER appeared in any captured log record
    for record in caplog.records:
        assert secret_canary not in record.message
        assert secret_canary not in str(record.args)
