from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, SecretStr, ValidationInfo, field_validator


class TikTokAuthSource(str, Enum):
    """Source of TikTok authentication credentials."""

    GUEST = "guest"
    SERVICE_ACCOUNT = "service_account"
    USER_SESSION = "user_session"


class TikTokAuthStatus(str, Enum):
    """Operational status of a TikTok authentication provider."""

    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"
    INVALID = "invalid"
    EXPIRED = "expired"


class TikTokAuthSession(BaseModel):
    """Safe internal session descriptor for a TikTok authentication provider.

    Contains no secret credentials (no sessionid, no sid_tt, no cookie headers).
    """

    source: TikTokAuthSource = TikTokAuthSource.GUEST
    authenticated: bool = False
    status: TikTokAuthStatus = TikTokAuthStatus.AVAILABLE
    session_id: str | None = None
    created_at: datetime | None = None
    expires_at: datetime | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @property
    def is_authenticated(self) -> bool:
        return self.authenticated

    @property
    def is_available(self) -> bool:
        return self.status == TikTokAuthStatus.AVAILABLE

    def is_expired(self, now: datetime | None = None) -> bool:
        if self.expires_at is None:
            return False
        current = now or datetime.now(UTC)
        return current >= self.expires_at


class TikTokAuthContext(BaseModel):
    """Contextual metadata passed to workers or diagnostics for TikTok requests.

    Guaranteed never to hold raw cookies, sessionid, or sid_tt secrets.
    """

    source: TikTokAuthSource = TikTokAuthSource.GUEST
    authenticated: bool = False
    status: TikTokAuthStatus = TikTokAuthStatus.AVAILABLE
    session_id: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    def __repr__(self) -> str:
        if self.session_id is not None:
            return (
                f"TikTokAuthContext(source={self.source.value!r}, "
                f"authenticated={self.authenticated!r}, "
                f"status={self.status.value!r}, "
                f"session_id={self.session_id!r})"
            )
        return (
            f"TikTokAuthContext(source={self.source.value!r}, "
            f"authenticated={self.authenticated!r}, "
            f"status={self.status.value!r})"
        )

    def __str__(self) -> str:
        return repr(self)


class TikTokSessionCreateRequest(BaseModel):
    """Request model for registering an ephemeral TikTok user session."""

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "sessionid": "<redacted_sessionid>",
                "sid_tt": "<redacted_sid_tt>",
            }
        },
    }

    sessionid: SecretStr = Field(
        ...,
        description="TikTok session ID (sessionid cookie value from active web session)",
    )
    sid_tt: SecretStr | None = Field(
        default=None,
        description="Optional TikTok sid_tt cookie value from active web session",
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

    @field_validator("sid_tt", mode="after")
    @classmethod
    def validate_sid_tt(cls, v: SecretStr | None, info: ValidationInfo) -> SecretStr | None:
        if v is None:
            return None
        val = v.get_secret_value().strip()
        field_name = info.field_name or "credential"
        if not val:
            raise ValueError(f"{field_name} must not be empty or whitespace")
        if len(val) > 512:
            raise ValueError(f"{field_name} exceeds maximum length of 512 characters")
        return SecretStr(val)


class TikTokSessionResponse(BaseModel):
    """Safe public API representation of an ephemeral TikTok user session."""

    session_id: str = Field(..., description="Opaque non-sensitive session identifier")
    source: TikTokAuthSource = Field(default=TikTokAuthSource.USER_SESSION, description="Credential source")
    status: TikTokAuthStatus = Field(default=TikTokAuthStatus.AVAILABLE, description="Session status")
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
        session: TikTokAuthSession,
        *,
        now: datetime | None = None,
    ) -> "TikTokSessionResponse":
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


class TikTokSessionRevokeResponse(BaseModel):
    """Confirmation payload returned when a session is invalidated."""

    session_id: str = Field(..., description="Opaque session identifier that was revoked")
    status: TikTokAuthStatus = Field(default=TikTokAuthStatus.INVALID, description="Status after revocation")
    revoked: bool = Field(default=True, description="Whether the revocation succeeded")
