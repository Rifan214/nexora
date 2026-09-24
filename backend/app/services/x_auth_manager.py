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
from app.services.x_user_session_store import EphemeralXUserSessionStore


class XAuthManager:
    """Entry point and manager for X/Twitter authentication providers."""

    def __init__(
        self,
        *,
        guest_provider: GuestXAuthProvider | None = None,
        service_account_provider: ServiceAccountXAuthProvider | None = None,
        user_session_provider: UserSessionXAuthProvider | None = None,
        service_account_cookie_file: str | Path | Callable[[], str | Path | None] | None = None,
        user_session_store: EphemeralXUserSessionStore | None = None,
    ) -> None:
        self._guest_provider = guest_provider or GuestXAuthProvider()
        self._service_account_provider = (
            service_account_provider
            or ServiceAccountXAuthProvider(cookie_file_path=service_account_cookie_file)
        )
        self._user_session_provider = (
            user_session_provider
            or UserSessionXAuthProvider(session_store=user_session_store)
        )

    def guest(self) -> GuestXAuthProvider:
        """Return the unauthenticated guest provider."""
        return self._guest_provider

    def service_account(self) -> ServiceAccountXAuthProvider:
        """Return the server-configured service account provider."""
        return self._service_account_provider

    def user_session(self) -> UserSessionXAuthProvider:
        """Return the user-session provider."""
        return self._user_session_provider

    @property
    def user_session_store(self) -> EphemeralXUserSessionStore:
        """Access the underlying ephemeral user session store."""
        return self._user_session_provider.store

    def get_provider_for_source(self, source: XAuthSource | str | None) -> XAuthProvider:
        """Resolve the appropriate provider for an authentication source."""
        if source in (XAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider
        if source in (XAuthSource.USER_SESSION, "user_session"):
            return self._user_session_provider
        return self._guest_provider

    def get_authenticated_provider(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> XAuthProvider | None:
        """Return an active authenticated provider.

        Rules:
        - If source is explicitly USER_SESSION: only return user_session_provider if session_id is valid.
          Never fall back to service account or guest!
        - If source is explicitly SERVICE_ACCOUNT: only return service_account_provider if available.
        - If source is None:
          - If session_id is provided and valid: return user_session_provider.
          - Otherwise, check service_account_provider.
          - Otherwise, return None.
        """
        if source in (XAuthSource.USER_SESSION, "user_session"):
            if self._user_session_provider.is_available(session_id):
                return self._user_session_provider
            return None

        if source in (XAuthSource.SERVICE_ACCOUNT, "service_account"):
            if self._service_account_provider.is_available():
                return self._service_account_provider
            return None

        # Default fallback order when source is unspecified
        if session_id and self._user_session_provider.is_available(session_id):
            return self._user_session_provider
        if self._service_account_provider.is_available():
            return self._service_account_provider
        return None

    def is_authenticated_available(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> bool:
        """Return True if the target authenticated provider is ready for extraction."""
        return self.get_authenticated_provider(source=source, session_id=session_id) is not None

    def get_session(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> XAuthSession:
        """Return the session descriptor for a source or active authenticated session."""
        if source in (XAuthSource.USER_SESSION, "user_session") or session_id is not None:
            return self._user_session_provider.get_session(session_id=session_id)
        if source in (XAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider.get_session()
        auth_provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if auth_provider is not None:
            return auth_provider.get_session(session_id=session_id)
        return self._guest_provider.get_session()

    def get_cookie_file(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Return a validated Netscape cookie file path if available."""
        if source in (XAuthSource.USER_SESSION, "user_session") or session_id is not None:
            return self._user_session_provider.get_cookie_file(session_id=session_id)
        if source in (XAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider.get_cookie_file()
        auth_provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if auth_provider is not None:
            return auth_provider.get_cookie_file(session_id=session_id)
        return None

    def require_authenticated_cookie_file(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path:
        """Return a validated cookie file or raise DownloadError."""
        cookie_file = self.get_cookie_file(source=source, session_id=session_id)
        if cookie_file is None:
            raise DownloadError("Authenticated X session unavailable")
        return cookie_file

    def build_context(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> XAuthContext:
        """Construct safe execution context metadata without secret credentials."""
        session = self.get_session(source=source, session_id=session_id)
        return XAuthContext(
            source=session.source,
            authenticated=session.authenticated,
            status=session.status,
            session_id=session.session_id,
            metadata=dict(session.metadata),
        )

    def acquire_session_lease(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Acquire active execution lease for download workers."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is not None:
            return provider.acquire_lease(session_id=session_id)
        return None

    def release_session_lease(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> None:
        """Release active execution lease."""
        if source in (XAuthSource.USER_SESSION, "user_session") or session_id is not None:
            self._user_session_provider.release_lease(session_id=session_id)
