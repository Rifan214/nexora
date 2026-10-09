from __future__ import annotations

from pathlib import Path
from typing import Callable

from yt_dlp.utils import DownloadError

from app.models.tiktok_auth import (
    TikTokAuthContext,
    TikTokAuthSession,
    TikTokAuthSource,
    TikTokAuthStatus,
)
from app.services.tiktok_auth_providers import (
    GuestTikTokAuthProvider,
    ServiceAccountTikTokAuthProvider,
    TikTokAuthProvider,
    UserSessionTikTokAuthProvider,
)
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore


class TikTokAuthManager:
    """Entry point and manager for TikTok authentication providers."""

    def __init__(
        self,
        *,
        guest_provider: GuestTikTokAuthProvider | None = None,
        service_account_provider: ServiceAccountTikTokAuthProvider | None = None,
        user_session_provider: UserSessionTikTokAuthProvider | None = None,
        service_account_cookie_file: str | Path | Callable[[], str | Path | None] | None = None,
        user_session_store: EphemeralTikTokUserSessionStore | None = None,
    ) -> None:
        self._guest_provider = guest_provider or GuestTikTokAuthProvider()
        self._service_account_provider = (
            service_account_provider
            or ServiceAccountTikTokAuthProvider(cookie_file_path=service_account_cookie_file)
        )
        self._user_session_provider = (
            user_session_provider
            or UserSessionTikTokAuthProvider(session_store=user_session_store)
        )

    def guest(self) -> GuestTikTokAuthProvider:
        """Return the unauthenticated guest provider."""
        return self._guest_provider

    def service_account(self) -> ServiceAccountTikTokAuthProvider:
        """Return the server-configured service account provider."""
        return self._service_account_provider

    def user_session(self) -> UserSessionTikTokAuthProvider:
        """Return the user-session provider."""
        return self._user_session_provider

    @property
    def user_session_store(self) -> EphemeralTikTokUserSessionStore:
        """Access the underlying ephemeral user session store."""
        return self._user_session_provider.store

    def get_provider_for_source(self, source: TikTokAuthSource | str | None) -> TikTokAuthProvider:
        """Resolve the appropriate provider for an authentication source."""
        if source in (TikTokAuthSource.SERVICE_ACCOUNT, "service_account"):
            return self._service_account_provider
        if source in (TikTokAuthSource.USER_SESSION, "user_session"):
            return self._user_session_provider
        return self._guest_provider

    def get_authenticated_provider(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> TikTokAuthProvider | None:
        """Return an active authenticated provider.

        Rules:
        - If source is explicitly USER_SESSION: only return user_session_provider if session_id is valid.
        - If source is explicitly SERVICE_ACCOUNT: only return service_account_provider if available.
        - If source is None:
          - If session_id is provided and valid: return user_session_provider.
          - Otherwise, check service_account_provider.
          - Otherwise, return None.
        """
        if source in (TikTokAuthSource.USER_SESSION, "user_session"):
            if self._user_session_provider.is_available(session_id):
                return self._user_session_provider
            return None

        if source in (TikTokAuthSource.SERVICE_ACCOUNT, "service_account"):
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
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> bool:
        """Check if an authenticated provider is currently available."""
        return self.get_authenticated_provider(source=source, session_id=session_id) is not None

    def get_cookie_file(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Return the Netscape cookie file path for the active provider."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is None:
            return None
        return provider.get_cookie_file(session_id)

    def acquire_session_lease(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        """Acquire an active execution lease on the provider's cookie file."""
        provider = self.get_authenticated_provider(source=source, session_id=session_id)
        if provider is None:
            return None
        return provider.acquire_lease(session_id)

    def release_session_lease(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> None:
        """Release an active execution lease on the provider's cookie file."""
        provider = self.get_provider_for_source(source)
        provider.release_lease(session_id)

    def require_authenticated_cookie_file(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path:
        """Return cookie file path or raise DownloadError if unavailable."""
        cookie_file = self.get_cookie_file(source=source, session_id=session_id)
        if cookie_file is None:
            raise DownloadError("Authenticated TikTok session unavailable")
        return cookie_file

    def build_auth_context(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> TikTokAuthContext:
        """Construct a safe, diagnostic context descriptor."""
        provider = self.get_provider_for_source(source)
        session = provider.get_session(session_id)
        return TikTokAuthContext(
            source=session.source,
            authenticated=session.authenticated,
            status=session.status,
            session_id=session.session_id,
            metadata=dict(session.metadata),
        )

    def build_context(
        self,
        source: TikTokAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> TikTokAuthContext:
        """Alias for build_auth_context matching XAuthManager interface."""
        return self.build_auth_context(source=source, session_id=session_id)
