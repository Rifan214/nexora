from __future__ import annotations


class Rule34VideoError(Exception):
    """Base exception for all Rule34Video adapter operations."""


class Rule34VideoUrlError(Rule34VideoError):
    """Raised when an invalid, malformed, or unsupported Rule34Video URL is supplied."""


class Rule34VideoNotFoundError(Rule34VideoError):
    """Raised when the requested Rule34Video video is not found (404) or deleted."""


class Rule34VideoAccessDeniedError(Rule34VideoError):
    """Raised when upstream returns HTTP 403 Forbidden."""


class Rule34VideoRateLimitedError(Rule34VideoError):
    """Raised when upstream returns HTTP 429 Too Many Requests."""


class Rule34VideoServerError(Rule34VideoError):
    """Raised when upstream returns HTTP 5xx Server Error."""


class Rule34VideoNetworkError(Rule34VideoError):
    """Raised when network connectivity fails while reaching Rule34Video."""


class Rule34VideoTimeoutError(Rule34VideoNetworkError):
    """Raised when connection or read timeout expires."""


class Rule34VideoTlsError(Rule34VideoNetworkError):
    """Raised when TLS handshake or certificate verification fails."""


class Rule34VideoMalformedResponseError(Rule34VideoError):
    """Raised when upstream returns invalid HTML, unparseable JSON-LD, or unexpected structure."""


class Rule34VideoUnsupportedMediaError(Rule34VideoError):
    """Raised when the post does not contain downloadable video media or formats."""


class Rule34VideoSecurityError(Rule34VideoError):
    """Raised when media URLs or redirect destinations fail SSRF/security validation."""

