from __future__ import annotations


class DanbooruError(Exception):
    """Base exception for all Danbooru adapter operations."""


class DanbooruUrlError(DanbooruError):
    """Raised when an invalid, malformed, or unsupported Danbooru URL is supplied."""


class DanbooruPostNotFoundError(DanbooruError):
    """Raised when the requested Danbooru post is not found (404), deleted, or banned."""


class DanbooruAccessDeniedError(DanbooruError):
    """Raised when upstream returns HTTP 403 Forbidden."""


class DanbooruRateLimitedError(DanbooruError):
    """Raised when upstream returns HTTP 429 Too Many Requests."""


class DanbooruServerError(DanbooruError):
    """Raised when upstream returns HTTP 5xx Server Error."""


class DanbooruNetworkError(DanbooruError):
    """Raised when network connectivity fails while reaching Danbooru."""


class DanbooruTimeoutError(DanbooruNetworkError):
    """Raised when connection or read timeout expires."""


class DanbooruTlsError(DanbooruNetworkError):
    """Raised when TLS handshake or certificate verification fails."""


class DanbooruMalformedResponseError(DanbooruError):
    """Raised when upstream returns invalid JSON or corrupted payload structure."""


class DanbooruUnsupportedMediaError(DanbooruError):
    """Raised when the post does not contain downloadable video or audio media."""


class DanbooruSecurityError(DanbooruError):
    """Raised when media URLs fail origin validation (e.g. untrusted host or scheme)."""
