from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from http.cookiejar import LoadError, MozillaCookieJar
from pathlib import Path
from typing import Any, Callable

from app.models.x_auth import XAuthSession, XAuthSource, XAuthStatus
from app.services.x_user_session_store import EphemeralXUserSessionStore

logger = logging.getLogger("app.services.media_service")


class XAuthProvider(ABC):
    """Abstract interface for X/Twitter authentication providers."""

    @property
    @abstractmethod
    def source(self) -> XAuthSource:
        """The source type identifying this provider."""
        raise NotImplementedError

    @abstractmethod
    def is_available(self, session_id: str | None = None) -> bool:
        """Return True if this provider can supply credentials or valid session."""
        raise NotImplementedError

    @abstractmethod
    def get_session(self, session_id: str | None = None) -> XAuthSession:
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


class GuestXAuthProvider(XAuthProvider):
    """Provider for public/unauthenticated X access."""

    @property
    def source(self) -> XAuthSource:
        return XAuthSource.GUEST

    def is_available(self, session_id: str | None = None) -> bool:
        return True

    def get_session(self, session_id: str | None = None) -> XAuthSession:
        return XAuthSession(
            source=XAuthSource.GUEST,
            authenticated=False,
            status=XAuthStatus.AVAILABLE,
            metadata={"source": "guest"},
        )

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        return None

    def invalidate(self, session_id: str | None = None) -> None:
        pass


class ServiceAccountXAuthProvider(XAuthProvider):
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
    def source(self) -> XAuthSource:
        return XAuthSource.SERVICE_ACCOUNT

    def _resolve_raw_path(self) -> str:
        if callable(self._cookie_source):
            val = self._cookie_source()
            return str(val).strip() if val is not None else ""
        if self._cookie_source is not None:
            return str(self._cookie_source).strip()
        return ""

    def _resolve_cookie_file(self) -> Path | None:
        configured_path = self._resolve_raw_path()
        if not configured_path:
            return None

        cookie_file = Path(configured_path).expanduser()
        try:
            if not cookie_file.is_file():
                raise FileNotFoundError
            cookie_jar = MozillaCookieJar(str(cookie_file))
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            cookie_names = {cookie.name for cookie in cookie_jar}
            if {"auth_token", "ct0"}.issubset(cookie_names):
                return cookie_file
        except (LoadError, OSError):
            self._logger.warning(
                "X authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
            )
            return None

        self._logger.warning(
            "X authenticated fallback enabled=true attempted=false reason=cookie_file_invalid"
        )
        return None

    def is_available(self, session_id: str | None = None) -> bool:
        return self._resolve_cookie_file() is not None

    def get_session(self, session_id: str | None = None) -> XAuthSession:
        cookie_file = self._resolve_cookie_file()
        if cookie_file is not None:
            return XAuthSession(
                source=XAuthSource.SERVICE_ACCOUNT,
                authenticated=True,
                status=XAuthStatus.AVAILABLE,
                metadata={"source": "service_account"},
            )
        return XAuthSession(
            source=XAuthSource.SERVICE_ACCOUNT,
            authenticated=False,
            status=XAuthStatus.UNAVAILABLE,
            metadata={"source": "service_account"},
        )

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        return self._resolve_cookie_file()

    def invalidate(self, session_id: str | None = None) -> None:
        pass


class UserSessionXAuthProvider(XAuthProvider):
    """Ephemeral user-session authentication provider backed by an in-memory session store."""

    def __init__(
        self,
        session_store: EphemeralXUserSessionStore | None = None,
        *,
        default_session_id: str | None = None,
        auth_logger: logging.Logger | None = None,
    ) -> None:
        self._store = session_store or EphemeralXUserSessionStore()
        self._default_session_id = default_session_id
        self._logger = auth_logger or logger

    @property
    def source(self) -> XAuthSource:
        return XAuthSource.USER_SESSION

    @property
    def store(self) -> EphemeralXUserSessionStore:
        return self._store

    def is_available(self, session_id: str | None = None) -> bool:
        target_id = session_id or self._default_session_id
        if not target_id:
            return False
        return self._store.is_valid(target_id)

    def get_session(self, session_id: str | None = None) -> XAuthSession:
        target_id = session_id or self._default_session_id
        if not target_id:
            return XAuthSession(
                source=XAuthSource.USER_SESSION,
                authenticated=False,
                status=XAuthStatus.UNAVAILABLE,
                metadata={"source": "user_session"},
            )
        return self._store.get_session(target_id)

    def get_cookie_file(self, session_id: str | None = None) -> Path | None:
        target_id = session_id or self._default_session_id
        if not target_id:
            return None
        return self._store.get_cookie_file(target_id)

    def invalidate(self, session_id: str | None = None) -> None:
        target_id = session_id or self._default_session_id
        if target_id:
            self._store.invalidate(target_id)

    def acquire_lease(self, session_id: str | None = None) -> Path | None:
        target_id = session_id or self._default_session_id
        if not target_id:
            return None
        return self._store.acquire_lease(target_id)

    def release_lease(self, session_id: str | None = None) -> None:
        target_id = session_id or self._default_session_id
        if target_id:
            self._store.release_lease(target_id)
