from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, SecretStr, ValidationInfo, field_validator


class InstagramAuthSource(str, Enum):
    """Source of Instagram authentication credentials."""

    GUEST = "guest"
    SERVICE_ACCOUNT = "service_account"
    USER_SESSION = "user_session"


class InstagramAuthStatus(str, Enum):
    """Operational status of an Instagram authentication provider."""

    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"
    INVALID = "invalid"
    EXPIRED = "expired"


class InstagramAuthSession(BaseModel):
    """Safe internal session descriptor for an Instagram authentication provider.

    Contains no secret credentials (no sessionid, no ds_user_id, no csrftoken, no cookies).
    """

    source: InstagramAuthSource = InstagramAuthSource.GUEST
    authenticated: bool = False
    status: InstagramAuthStatus = InstagramAuthStatus.AVAILABLE
    session_id: str | None = None
    created_at: datetime | None = None
    expires_at: datetime | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @property
    def is_authenticated(self) -> bool:
        return self.authenticated

    @property
    def is_available(self) -> bool:
        return self.status == InstagramAuthStatus.AVAILABLE

    def is_expired(self, now: datetime | None = None) -> bool:
        if self.expires_at is None:
            return False
        current = now or datetime.now(UTC)
        return current >= self.expires_at


class InstagramAuthContext(BaseModel):
    """Contextual metadata passed to workers or diagnostics for Instagram requests.

    Guaranteed never to hold raw cookies, sessionid, ds_user_id, or csrftoken secrets.
    """

    source: InstagramAuthSource = InstagramAuthSource.GUEST
    authenticated: bool = False
    status: InstagramAuthStatus = InstagramAuthStatus.AVAILABLE
    session_id: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    def __repr__(self) -> str:
        if self.session_id is not None:
            return (
                f"InstagramAuthContext(source={self.source.value!r}, "
                f"authenticated={self.authenticated!r}, "
                f"status={self.status.value!r}, "
                f"session_id={self.session_id!r})"
            )
        return (
            f"InstagramAuthContext(source={self.source.value!r}, "
            f"authenticated={self.authenticated!r}, "
            f"status={self.status.value!r})"
        )

    def __str__(self) -> str:
        return repr(self)


class InstagramSessionCreateRequest(BaseModel):
    """Request model for registering an ephemeral Instagram user session."""

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "sessionid": "<redacted_sessionid>",
                "ds_user_id": "<redacted_ds_user_id>",
                "csrftoken": "<redacted_csrftoken>",
            }
        },
    }

    sessionid: SecretStr = Field(
        ...,
        description="Instagram session ID (sessionid cookie value from active web session)",
    )
    ds_user_id: SecretStr | None = Field(
        default=None,
        description="Optional Instagram ds_user_id cookie value from active web session",
    )
    csrftoken: SecretStr | None = Field(
        default=None,
        description="Optional Instagram csrftoken cookie value from active web session",
    )

    @field_validator("sessionid", mode="after")
    @classmethod
    def validate_sessionid(cls, v: SecretStr, info: ValidationInfo) -> SecretStr:
        val = v.get_secret_value().strip()
        field_name = info.field_name or "credential"
        if not val:
            raise ValueError(f"{field_name} must not be empty or whitespace")
        if len(val) > 512:
            raise ValueError(f"{field_name} exceeds maximum length of 512 characters")
        return SecretStr(val)

    @field_validator("ds_user_id", mode="after")
    @classmethod
    def validate_ds_user_id(cls, v: SecretStr | None, info: ValidationInfo) -> SecretStr | None:
        if v is None:
            return None
        val = v.get_secret_value().strip()
        field_name = info.field_name or "credential"
        if not val:
            raise ValueError(f"{field_name} must not be empty or whitespace")
        if len(val) > 512:
            raise ValueError(f"{field_name} exceeds maximum length of 512 characters")
        return SecretStr(val)

    @field_validator("csrftoken", mode="after")
    @classmethod
    def validate_csrftoken(cls, v: SecretStr | None, info: ValidationInfo) -> SecretStr | None:
        if v is None:
            return None
        val = v.get_secret_value().strip()
        field_name = info.field_name or "credential"
        if not val:
            raise ValueError(f"{field_name} must not be empty or whitespace")
        if len(val) > 512:
            raise ValueError(f"{field_name} exceeds maximum length of 512 characters")
        return SecretStr(val)


class InstagramSessionResponse(BaseModel):
    """Safe public API representation of an ephemeral Instagram user session."""

    session_id: str = Field(..., description="Opaque non-sensitive session identifier")
    source: InstagramAuthSource = Field(default=InstagramAuthSource.USER_SESSION, description="Credential source")
    status: InstagramAuthStatus = Field(default=InstagramAuthStatus.AVAILABLE, description="Session status")
    authenticated: bool = Field(default=True, description="Whether the session is authenticated")
    created_at: datetime | None = Field(default=None, description="Creation timestamp (UTC)")
    expires_at: datetime | None = Field(default=None, description="Expiration timestamp (UTC)")
    expires_in_seconds: int | None = Field(
        default=None,
        description="Remaining lifetime in seconds (0 if expired)",
    )

    @classmethod
    def from_session(
        cls,
        session: InstagramAuthSession,
        *,
        now: datetime | None = None,
    ) -> "InstagramSessionResponse":
        current = now or datetime.now(UTC)
        expires_in = None
        if session.expires_at is not None:
            remaining = int((session.expires_at - current).total_seconds())
            expires_in = max(0, remaining)
        return cls(
            session_id=session.session_id or "",
            source=session.source,
            status=session.status,
            authenticated=session.authenticated,
            created_at=session.created_at,
            expires_at=session.expires_at,
            expires_in_seconds=expires_in,
        )


class InstagramSessionRevokeResponse(BaseModel):
    """Confirmation payload returned when a session is invalidated."""

    session_id: str = Field(..., description="Opaque session identifier that was revoked")
    status: InstagramAuthStatus = Field(default=InstagramAuthStatus.INVALID, description="Status after revocation")
    revoked: bool = Field(default=True, description="Whether the revocation succeeded")
