from __future__ import annotations

from pathlib import Path
from typing import Callable

from yt_dlp.utils import DownloadError

from app.models.x_auth import XAuthContext, XAuthSession, XAuthSource, XAuthStatus
from app.services.x_auth_providers import (
    GuestXAuthProvider,
    ServiceAccountXAuthProvider,
    UserSessionXAuthProvider,
    XAuthProvider,
)


class XAuthManager:
    """Entry point and manager for X/Twitter authentication providers."""

    def __init__(
        self,
        *,
        guest_provider: GuestXAuthProvider | None = None,
        service_account_provider: ServiceAccountXAuthProvider | None = None,
        user_session_provider: UserSessionXAuthProvider | None = None,
        service_account_cookie_file: str | Path | Callable[[], str | Path | None] | None = None,
    ) -> None:
        self._guest_provider = guest_provider or GuestXAuthProvider()
        self._service_account_provider = (
            service_account_provider
            or ServiceAccountXAuthProvider(cookie_file_path=service_account_cookie_file)
        )
        self._user_session_provider = user_session_provider or UserSessionXAuthProvider()

    def guest(self) -> GuestXAuthProvider:
        """Return the unauthenticated guest provider."""
        return self._guest_provider

    def service_account(self) -> ServiceAccountXAuthProvider:
        """Return the server-configured service account provider."""
        return self._service_account_provider

    def user_session(self) -> UserSessionXAuthProvider:
        """Return the user-session provider placeholder."""
        return self._user_session_provider

    def get_provider_for_source(self, source: XAuthSource | str | None) -> XAuthProvider:
        """Resolve the appropriate provider for an authentication source."""
        if source in (XAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider
        if source in (XAuthSource.USER_SESSION, "user_session"):
            return self._user_session_provider
        return self._guest_provider

    def get_authenticated_provider(self) -> XAuthProvider | None:
        """Return an active authenticated provider, prioritizing service account."""
        if self._service_account_provider.is_available():
            return self._service_account_provider
        if self._user_session_provider.is_available():
            return self._user_session_provider
        return None

    def is_authenticated_available(self) -> bool:
        """Return True if any authenticated provider is ready for extraction."""
        return self.get_authenticated_provider() is not None

    def get_session(self, source: XAuthSource | str | None = None) -> XAuthSession:
        """Return the session descriptor for a source or active authenticated session."""
        if source is not None:
            return self.get_provider_for_source(source).get_session()
        auth_provider = self.get_authenticated_provider()
        if auth_provider is not None:
            return auth_provider.get_session()
        return self._guest_provider.get_session()

    def get_cookie_file(self, source: XAuthSource | str | None = None) -> Path | None:
        """Return a validated Netscape cookie file path if available."""
        if source is not None:
            return self.get_provider_for_source(source).get_cookie_file()
        auth_provider = self.get_authenticated_provider()
        if auth_provider is not None:
            return auth_provider.get_cookie_file()
        return None

    def require_authenticated_cookie_file(self, source: XAuthSource | str | None = None) -> Path:
        """Return a validated cookie file or raise DownloadError."""
        cookie_file = self.get_cookie_file(source=source)
        if cookie_file is None:
            raise DownloadError("Authenticated X session unavailable")
        return cookie_file

    def build_context(self, source: XAuthSource | str | None = None) -> XAuthContext:
        """Construct safe execution context metadata without secret credentials."""
        session = self.get_session(source=source)
        return XAuthContext(
            source=session.source,
            authenticated=session.authenticated,
            status=session.status,
            metadata=dict(session.metadata),
        )
