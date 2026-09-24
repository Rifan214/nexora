from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from http.cookiejar import LoadError, MozillaCookieJar
from pathlib import Path
from typing import Any, Callable

from app.models.x_auth import XAuthSession, XAuthSource, XAuthStatus

logger = logging.getLogger("app.services.media_service")


class XAuthProvider(ABC):
    """Abstract interface for X/Twitter authentication providers."""

    @property
    @abstractmethod
    def source(self) -> XAuthSource:
        """The source type identifying this provider."""
        raise NotImplementedError

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this provider can supply credentials or valid session."""
        raise NotImplementedError

    @abstractmethod
    def get_session(self) -> XAuthSession:
        """Return safe descriptor metadata for the current session."""
        raise NotImplementedError

    @abstractmethod
    def get_cookie_file(self) -> Path | None:
        """Return a path to a validated Netscape cookie file, if applicable."""
        raise NotImplementedError

    @abstractmethod
    def invalidate(self) -> None:
        """Invalidate cached session state."""
        raise NotImplementedError


class GuestXAuthProvider(XAuthProvider):
    """Provider for public/unauthenticated X access."""

    @property
    def source(self) -> XAuthSource:
        return XAuthSource.GUEST

    def is_available(self) -> bool:
        return True

    def get_session(self) -> XAuthSession:
        return XAuthSession(
            source=XAuthSource.GUEST,
            authenticated=False,
            status=XAuthStatus.AVAILABLE,
            metadata={"source": "guest"},
        )

    def get_cookie_file(self) -> Path | None:
        return None

    def invalidate(self) -> None:
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

    def is_available(self) -> bool:
        return self._resolve_cookie_file() is not None

    def get_session(self) -> XAuthSession:
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

    def get_cookie_file(self) -> Path | None:
        return self._resolve_cookie_file()

    def invalidate(self) -> None:
        pass


class UserSessionXAuthProvider(XAuthProvider):
    """Extension point placeholder for future user-session authentication (e.g., mobile WebView)."""

    def __init__(self, metadata: dict[str, Any] | None = None) -> None:
        self._metadata = metadata or {}

    @property
    def source(self) -> XAuthSource:
        return XAuthSource.USER_SESSION

    def is_available(self) -> bool:
        return False

    def get_session(self) -> XAuthSession:
        return XAuthSession(
            source=XAuthSource.USER_SESSION,
            authenticated=False,
            status=XAuthStatus.UNAVAILABLE,
            metadata={"source": "user_session", "implemented": False, **self._metadata},
        )

    def get_cookie_file(self) -> Path | None:
        return None

    def invalidate(self) -> None:
        pass
