from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from http.cookiejar import LoadError, MozillaCookieJar
from pathlib import Path
from typing import Callable

from app.models.instagram_auth import (
    InstagramAuthSession,
    InstagramAuthSource,
    InstagramAuthStatus,
)
from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore

logger = logging.getLogger("app.services.media_service")


class InstagramAuthProvider(ABC):
    """Abstract interface for Instagram authentication providers."""

    @property
    @abstractmethod
    def source(self) -> InstagramAuthSource:
        """The source type identifying this provider."""
        raise NotImplementedError

    @abstractmethod
    def is_available(self, session_id: str | None = None) -> bool:
        """Return True if this provider can supply credentials or valid session."""
        raise NotImplementedError

    @abstractmethod
    def get_session(self, session_id: str | None = None) -> InstagramAuthSession:
        """Return safe descriptor metadata for the current session."""
        raise NotImplementedError

    @abstractmethod
    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        """Return a path to a validated Netscape cookie file, if applicable."""
        raise NotImplementedError

    @abstractmethod
    def invalidate(self, session_id: str | None = None) -> None:
        """Invalidate cached session state."""
        raise NotImplementedError

    def acquire_lease(self, session_id: str | None = None) -> Path | None:
        """Acquire active execution lease on the cookie file."""
        return self.get_cookie_file(session_id)

    def release_lease(self, session_id: str | None = None) -> None:
        """Release active execution lease."""
        pass


class GuestInstagramAuthProvider(InstagramAuthProvider):
    """Provider for public/unauthenticated Instagram access."""

    @property
    def source(self) -> InstagramAuthSource:
        return InstagramAuthSource.GUEST

    def is_available(self, session_id: str | None = None) -> bool:
        return True

    def get_session(self, session_id: str | None = None) -> InstagramAuthSession:
        return InstagramAuthSession(
            source=InstagramAuthSource.GUEST,
            authenticated=False,
            status=InstagramAuthStatus.AVAILABLE,
            metadata={"source": "guest"},
        )

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        return None

    def invalidate(self, session_id: str | None = None) -> None:
        pass


class ServiceAccountInstagramAuthProvider(InstagramAuthProvider):
    """Provider using a configured server-side service account cookie file."""

    def __init__(
        self,
        cookie_file_path: str | Path | Callable[[], str | Path | None] | None = None,
        *,
        auth_logger: logging.Logger | None = None,
    ) -> None:
        self._cookie_source = cookie_file_path
        self._logger = auth_logger or logger

    @property
    def source(self) -> InstagramAuthSource:
        return InstagramAuthSource.SERVICE_ACCOUNT

    def _resolve_raw_path(self) -> str:
        if callable(self._cookie_source):
            val = self._cookie_source()
            return str(val or "").strip()
        return str(self._cookie_source or "").strip()

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        raw_path = self._resolve_raw_path()
        if not raw_path:
            return None

        cookie_path = Path(raw_path).expanduser()
        try:
            if not cookie_path.is_file():
                self._logger.warning(
                    "Instagram authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
                )
                return None

            cookie_jar = MozillaCookieJar(str(cookie_path))
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            cookie_names = {cookie.name for cookie in cookie_jar}
            if "sessionid" in cookie_names or "csrftoken" in cookie_names or "ds_user_id" in cookie_names:
                return cookie_path
        except (LoadError, OSError):
            self._logger.warning(
                "Instagram authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
            )
            return None

        self._logger.warning(
            "Instagram authenticated fallback enabled=true attempted=false reason=cookie_file_invalid"
        )
        return None

    def is_available(self, session_id: str | None = None) -> bool:
        return self.get_cookie_file(session_id) is not None

    def get_session(self, session_id: str | None = None) -> InstagramAuthSession:
        cookie_file = self.get_cookie_file(session_id)
        if cookie_file is None:
            return InstagramAuthSession(
                source=InstagramAuthSource.SERVICE_ACCOUNT,
                authenticated=False,
                status=InstagramAuthStatus.UNAVAILABLE,
                metadata={"source": "service_account"},
            )
        return InstagramAuthSession(
            source=InstagramAuthSource.SERVICE_ACCOUNT,
            authenticated=True,
            status=InstagramAuthStatus.AVAILABLE,
            metadata={"source": "service_account"},
        )

    def invalidate(self, session_id: str | None = None) -> None:
        pass


class UserSessionInstagramAuthProvider(InstagramAuthProvider):
    """Provider managing ephemeral user sessions for Instagram."""

    def __init__(
        self,
        session_store: EphemeralInstagramUserSessionStore | None = None,
    ) -> None:
        self._store = session_store or EphemeralInstagramUserSessionStore()

    @property
    def source(self) -> InstagramAuthSource:
        return InstagramAuthSource.USER_SESSION

    @property
    def store(self) -> EphemeralInstagramUserSessionStore:
        return self._store

    def is_available(self, session_id: str | None = None) -> bool:
        if not session_id:
            return False
        return self._store.has_session(session_id)

    def get_session(self, session_id: str | None = None) -> InstagramAuthSession:
        if not session_id:
            return InstagramAuthSession(
                source=InstagramAuthSource.USER_SESSION,
                authenticated=False,
                status=InstagramAuthStatus.UNAVAILABLE,
                metadata={"source": "user_session", "reason": "missing_session_id"},
            )
        return self._store.get_session(session_id)

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        if not session_id:
            return None
        return self._store.get_cookie_file(session_id)

    def acquire_lease(self, session_id: str | None = None) -> Path | None:
        if not session_id:
            return None
        return self._store.acquire_session_lease(session_id)

    def release_lease(self, session_id: str | None = None) -> None:
        if session_id:
            self._store.release_session_lease(session_id)

    def invalidate(self, session_id: str | None = None) -> None:
        if session_id:
            self._store.invalidate(session_id)
