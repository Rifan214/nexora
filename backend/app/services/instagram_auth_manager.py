from __future__ import annotations

from pathlib import Path
from typing import Callable

from yt_dlp.utils import DownloadError

from app.models.instagram_auth import (
    InstagramAuthContext,
    InstagramAuthSession,
    InstagramAuthSource,
    InstagramAuthStatus,
)
from app.services.instagram_auth_providers import (
    GuestInstagramAuthProvider,
    InstagramAuthProvider,
    ServiceAccountInstagramAuthProvider,
    UserSessionInstagramAuthProvider,
)
from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore


class InstagramAuthManager:
    """Entry point and manager for Instagram authentication providers."""

    def __init__(
        self,
        *,
        guest_provider: GuestInstagramAuthProvider | None = None,
        service_account_provider: ServiceAccountInstagramAuthProvider | None = None,
        user_session_provider: UserSessionInstagramAuthProvider | None = None,
        service_account_cookie_file: str | Path | Callable[[], str | Path | None] | None = None,
        user_session_store: EphemeralInstagramUserSessionStore | None = None,
    ) -> None:
        self._guest_provider = guest_provider or GuestInstagramAuthProvider()
        self._service_account_provider = (
            service_account_provider
            or ServiceAccountInstagramAuthProvider(cookie_file_path=service_account_cookie_file)
        )
        self._user_session_provider = (
            user_session_provider
            or UserSessionInstagramAuthProvider(session_store=user_session_store)
        )

    def guest(self) -> GuestInstagramAuthProvider:
        """Return the unauthenticated guest provider."""
        return self._guest_provider

    def service_account(self) -> ServiceAccountInstagramAuthProvider:
        """Return the server-configured service account provider."""
        return self._service_account_provider

    def user_session(self) -> UserSessionInstagramAuthProvider:
        """Return the user-session provider."""
        return self._user_session_provider

    @property
    def user_session_store(self) -> EphemeralInstagramUserSessionStore:
        """Access the underlying ephemeral user session store."""
        return self._user_session_provider.store

    def get_provider_for_source(self, source: InstagramAuthSource | str | None) -> InstagramAuthProvider:
        """Resolve the appropriate provider for an authentication source."""
        if source in (InstagramAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider
        if source in (InstagramAuthSource.USER_SESSION, "user_session"):
            return self._user_session_provider
        return self._guest_provider

    def get_authenticated_provider(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> InstagramAuthProvider | None:
        """Return an active authenticated provider.

        Rules:
        - If source is explicitly USER_SESSION: only return user_session_provider if session_id is valid.
        - If source is explicitly SERVICE_ACCOUNT: only return service_account_provider if available.
        - If source is None:
          - If session_id is provided and valid: return user_session_provider.
          - Otherwise, check service_account_provider.
          - Otherwise, return None.
        """
        if source in (InstagramAuthSource.USER_SESSION, "user_session"):
            if self._user_session_provider.is_available(session_id):
                return self._user_session_provider
            return None

        if source in (InstagramAuthSource.SERVICE_ACCOUNT, "service_account"):
            if self._service_account_provider.is_available():
                return self._service_account_provider
            return None

        if session_id and self._user_session_provider.is_available(session_id):
            return self._user_session_provider
        if self._service_account_provider.is_available():
            return self._service_account_provider
        return None

    def is_authenticated_available(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> bool:
        """Return True if an authenticated provider can supply credentials."""
        return self.get_authenticated_provider(source=source, session_id=session_id) is not None

    def get_cookie_file(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Retrieve the cookie file path from an available authenticated provider."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is None:
            return None
        return provider.get_cookie_file(session_id)

    def require_authenticated_cookie_file(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path:
        """Enforce that an authenticated cookie file exists or raise DownloadError."""
        cookie_file = self.get_cookie_file(source=source, session_id=session_id)
        if cookie_file is None:
            raise DownloadError("No authenticated cookie file available for Instagram request")
        return cookie_file

    def acquire_session_lease(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Acquire active execution lease from provider, preventing file cleanup mid-flight."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is None:
            return None
        return provider.acquire_lease(session_id)

    def release_session_lease(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> None:
        """Release previously acquired lease from the provider."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is not None:
            provider.release_lease(session_id)

    def invalidate(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> None:
        """Invalidate the session associated with the given source/session_id."""
        if source in (InstagramAuthSource.USER_SESSION, "user_session") or session_id:
            self._user_session_provider.invalidate(session_id)
        elif source in (InstagramAuthSource.SERVICE_ACCOUNT, "service_account"):
            self._service_account_provider.invalidate()

    def get_auth_context(
        self,
        source: InstagramAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> InstagramAuthContext:
        """Return safe descriptor metadata for logging or diagnostics."""
        provider = self.get_provider_for_source(source)
        session = provider.get_session(session_id)
        return InstagramAuthContext(
            source=session.source,
            authenticated=session.authenticated,
            status=session.status,
            session_id=session.session_id,
            metadata=session.metadata,
        )
