from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, SecretStr, ValidationInfo, field_validator


class XAuthSource(str, Enum):
    """Source of X/Twitter authentication credentials."""

    GUEST = "guest"
    SERVICE_ACCOUNT = "service_account"
    USER_SESSION = "user_session"


class XAuthStatus(str, Enum):
    """Operational status of an X/Twitter authentication provider."""

    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"
    INVALID = "invalid"
    EXPIRED = "expired"


class XAuthSession(BaseModel):
    """Safe internal session descriptor for an X/Twitter authentication provider.

    Contains no secret credentials (no auth_token, no ct0, no cookie headers).
    """

    source: XAuthSource = XAuthSource.GUEST
    authenticated: bool = False
    status: XAuthStatus = XAuthStatus.AVAILABLE
    session_id: str | None = None
    created_at: datetime | None = None
    expires_at: datetime | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @property
    def is_authenticated(self) -> bool:
        return self.authenticated

    @property
    def is_available(self) -> bool:
        return self.status == XAuthStatus.AVAILABLE

    def is_expired(self, now: datetime | None = None) -> bool:
        if self.expires_at is None:
            return False
        current = now or datetime.now(UTC)
        return current >= self.expires_at


class XAuthContext(BaseModel):
    """Contextual metadata passed to workers or diagnostics for X requests.

    Guaranteed never to hold raw cookies, auth_token, or ct0 secrets.
    """

    source: XAuthSource = XAuthSource.GUEST
    authenticated: bool = False
    status: XAuthStatus = XAuthStatus.AVAILABLE
    session_id: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    def __repr__(self) -> str:
        if self.session_id is not None:
            return (
                f"XAuthContext(source={self.source.value!r}, "
                f"authenticated={self.authenticated!r}, "
                f"status={self.status.value!r}, "
                f"session_id={self.session_id!r})"
            )
        return (
            f"XAuthContext(source={self.source.value!r}, "
            f"authenticated={self.authenticated!r}, "
            f"status={self.status.value!r})"
        )

    def __str__(self) -> str:
        return repr(self)


class XSessionCreateRequest(BaseModel):
    """Request model for registering an ephemeral X user session."""

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "auth_token": "<redacted_auth_token>",
                "ct0": "<redacted_ct0>",
            }
        },
    }

    auth_token: SecretStr = Field(
        ...,
        description="X authentication token (auth_token cookie value from active web session)",
    )
    ct0: SecretStr = Field(
        ...,
        description="X CSRF token (ct0 cookie value from active web session)",
    )

    @field_validator("auth_token", "ct0", mode="after")
    @classmethod
    def validate_non_empty_secret(cls, v: SecretStr, info: ValidationInfo) -> SecretStr:
        val = v.get_secret_value().strip()
        field_name = info.field_name or "credential"
        if not val:
            raise ValueError(f"{field_name} must not be empty or whitespace")
        if len(val) > 512:
            raise ValueError(f"{field_name} exceeds maximum length of 512 characters")
        return SecretStr(val)


class XSessionResponse(BaseModel):
    """Safe public API representation of an ephemeral X user session."""

    session_id: str = Field(..., description="Opaque non-sensitive session identifier")
    source: XAuthSource = Field(default=XAuthSource.USER_SESSION, description="Credential source")
    status: XAuthStatus = Field(default=XAuthStatus.AVAILABLE, description="Session status")
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
        session: XAuthSession,
        *,
        now: datetime | None = None,
    ) -> "XSessionResponse":
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


class XSessionRevokeResponse(BaseModel):
    """Confirmation payload returned when a session is invalidated."""

    session_id: str = Field(..., description="Opaque session identifier that was revoked")
    status: XAuthStatus = Field(default=XAuthStatus.INVALID, description="Status after revocation")
    revoked: bool = Field(default=True, description="Whether the revocation succeeded")
