from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.exceptions import _SENSITIVE_LOC_PARTS, _sanitize_validation_errors
from app.models.instagram_auth import (
    InstagramAuthContext,
    InstagramAuthSession,
    InstagramAuthSource,
    InstagramAuthStatus,
    InstagramSessionCreateRequest,
    InstagramSessionResponse,
)

_VALID_SESSIONID = "synthetic_instagram_sessionid_12345%3AAbCdEf"
_VALID_DS_USER_ID = "61234567890"
_VALID_CSRFTOKEN = "csrf_token_test_abc123"


def test_session_create_request_valid() -> None:
    req = InstagramSessionCreateRequest(
        sessionid=_VALID_SESSIONID,
        ds_user_id=_VALID_DS_USER_ID,
        csrftoken=_VALID_CSRFTOKEN,
    )
    assert req.sessionid.get_secret_value() == _VALID_SESSIONID
    assert req.ds_user_id is not None
    assert req.ds_user_id.get_secret_value() == _VALID_DS_USER_ID
    assert req.csrftoken is not None
    assert req.csrftoken.get_secret_value() == _VALID_CSRFTOKEN


def test_session_create_request_optional_fields() -> None:
    req = InstagramSessionCreateRequest(sessionid=_VALID_SESSIONID)
    assert req.sessionid.get_secret_value() == _VALID_SESSIONID
    assert req.ds_user_id is None
    assert req.csrftoken is None


def test_session_create_request_empty_sessionid_raises() -> None:
    with pytest.raises(ValidationError) as exc:
        InstagramSessionCreateRequest(sessionid="   ")
    assert "must not be empty" in str(exc.value)


def test_session_create_request_too_long_raises() -> None:
    too_long = "a" * 513
    with pytest.raises(ValidationError) as exc:
        InstagramSessionCreateRequest(sessionid=too_long)
    assert "exceeds maximum length" in str(exc.value)

    with pytest.raises(ValidationError) as exc:
        InstagramSessionCreateRequest(sessionid=_VALID_SESSIONID, ds_user_id=too_long)
    assert "exceeds maximum length" in str(exc.value)


def test_session_create_request_forbids_extra_fields() -> None:
    with pytest.raises(ValidationError) as exc:
        InstagramSessionCreateRequest(
            sessionid=_VALID_SESSIONID,
            extra_field="malicious_value",  # type: ignore[call-arg]
        )
    assert "extra_forbidden" in str(exc.value).lower() or "extra fields not permitted" in str(exc.value).lower()


def test_auth_context_repr_safe() -> None:
    ctx = InstagramAuthContext(
        source=InstagramAuthSource.USER_SESSION,
        authenticated=True,
        status=InstagramAuthStatus.AVAILABLE,
        session_id="abcdef0123456789abcdef0123456789",
    )
    repr_str = repr(ctx)
    assert "InstagramAuthContext" in repr_str
    assert "abcdef0123456789abcdef0123456789" in repr_str
    # Raw credentials should never even be present in context
    assert not hasattr(ctx, "sessionid")
    assert not hasattr(ctx, "ds_user_id")


def test_sensitive_parts_contain_instagram_credentials() -> None:
    assert "sessionid" in _SENSITIVE_LOC_PARTS
    assert "ds_user_id" in _SENSITIVE_LOC_PARTS
    assert "csrftoken" in _SENSITIVE_LOC_PARTS


def test_sanitize_validation_errors_strips_instagram_credentials() -> None:
    raw_errors = [
        {
            "loc": ("body", "sessionid"),
            "msg": "Value error, sessionid must not be empty or whitespace",
            "type": "value_error",
            "input": "super_secret_session_token_123",
            "ctx": {"error": ValueError(), "actual_length": 30},
        },
        {
            "loc": ("body", "ds_user_id"),
            "msg": "Value error, ds_user_id exceeds maximum length",
            "type": "value_error",
            "input": "61234567890",
            "ctx": {"error": ValueError(), "actual_length": 11},
        },
        {
            "loc": ("body", "csrftoken"),
            "msg": "Value error, csrftoken invalid",
            "type": "value_error",
            "input": "secret_csrf_123",
            "ctx": {"error": ValueError()},
        },
        {
            "loc": ("body", "normal_field"),
            "msg": "Field required",
            "type": "missing",
            "input": "public_data",
        },
    ]

    sanitized = _sanitize_validation_errors(raw_errors)

    # First three should have "input" removed
    assert "input" not in sanitized[0]
    assert "actual_length" not in sanitized[0].get("ctx", {})
    assert "input" not in sanitized[1]
    assert "actual_length" not in sanitized[1].get("ctx", {})
    assert "input" not in sanitized[2]

    # Fourth should keep input since it's not in _SENSITIVE_LOC_PARTS
    assert sanitized[3]["input"] == "public_data"
