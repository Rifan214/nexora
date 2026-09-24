from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


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
