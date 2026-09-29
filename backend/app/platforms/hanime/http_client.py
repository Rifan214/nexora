from __future__ import annotations

import logging
import time
from typing import Any
from urllib.parse import urlsplit

import httpx

from app.platforms.hanime.crypto import encrypt_handshake_token
from app.platforms.hanime.signature_provider import HanimeSignature

logger = logging.getLogger(__name__)

_ALLOWED_HOSTS = frozenset({"hanime.tv", "www.hanime.tv", "auth.hanime.tv"})
_DEFAULT_CONNECT_TIMEOUT = 10.0
_DEFAULT_READ_TIMEOUT = 15.0
_DEFAULT_WRITE_TIMEOUT = 10.0
_DEFAULT_POOL_TIMEOUT = 15.0

_HANDSHAKE_ENDPOINT = "https://auth.hanime.tv/api/v11/handshake"
_DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)


class HanimeExtractionError(Exception):
    """Base exception for Hanime operations."""


class HanimeHttpClientError(HanimeExtractionError):
    """Base exception for Hanime HTTP operations."""

    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class HanimeNetworkError(HanimeHttpClientError):
    """Raised on connection drop, timeout, or DNS resolution failure."""


class HanimeSecurityError(HanimeHttpClientError):
    """Raised when an untrusted destination, scheme, or SSRF attempt is detected."""


class HanimeHandshakeAuthError(HanimeHttpClientError):
    """Raised when handshake returns 401 or 403 (e.g. signature expired/invalid)."""


class HanimeRateLimitError(HanimeHttpClientError):
    """Raised when handshake returns HTTP 429 Too Many Requests."""


class HanimeServerError(HanimeHttpClientError):
    """Raised when upstream server returns HTTP 5xx."""


class HanimeMalformedResponseError(HanimeHttpClientError):
    """Raised when the server response is missing expected headers or payload is malformed."""


def _validate_allowed_host(url: str) -> None:
    """Ensure destination host is in the strict whitelist to prevent SSRF."""
    try:
        parsed = urlsplit(url)
    except Exception as exc:
        raise HanimeSecurityError(f"Malformed URL: {url}") from exc

    if (parsed.scheme or "").casefold() not in {"http", "https"}:
        raise HanimeSecurityError(f"Unsupported URL scheme '{parsed.scheme}'. Only HTTP/HTTPS is permitted.")

    hostname = (parsed.hostname or "").casefold()
    if not hostname or hostname not in _ALLOWED_HOSTS:
        raise HanimeSecurityError(
            f"Access to host '{hostname}' is blocked by security policy. Allowed: {sorted(_ALLOWED_HOSTS)}"
        )


class HttpHanimeClient:
    """Specialized HTTP client for Hanime page fetching and handshake protocol."""

    def __init__(
        self,
        *,
        client: httpx.AsyncClient | None = None,
        connect_timeout: float = _DEFAULT_CONNECT_TIMEOUT,
        read_timeout: float = _DEFAULT_READ_TIMEOUT,
        write_timeout: float = _DEFAULT_WRITE_TIMEOUT,
        pool_timeout: float = _DEFAULT_POOL_TIMEOUT,
        user_agent: str = _DEFAULT_USER_AGENT,
        verify: bool | Any = True,
    ) -> None:
        self._user_agent = user_agent
        self._verify = verify
        self._timeout = httpx.Timeout(
            connect=connect_timeout,
            read=read_timeout,
            write=write_timeout,
            pool=pool_timeout,
        )
        self._external_client = client
        self._client: httpx.AsyncClient | None = client
        self._client_loop: Any = None

    async def _get_client(self) -> httpx.AsyncClient:
        import asyncio
        current_loop = asyncio.get_running_loop()
        if (
            self._client is None
            or self._client.is_closed
            or (self._external_client is None and self._client_loop != current_loop)
        ):
            self._client = httpx.AsyncClient(
                timeout=self._timeout,
                follow_redirects=False,  # Security: do not automatically follow arbitrary redirects
                verify=self._verify,
                headers={"User-Agent": self._user_agent},
            )
            self._client_loop = current_loop
        return self._client

    async def close(self) -> None:
        """Close the underlying HTTP client session if internally created."""
        if self._client is not None and self._external_client is None:
            if not self._client.is_closed:
                await self._client.aclose()
            self._client = None

    async def get_video_page(self, url: str) -> str:
        """Fetch the HTML content of a Hanime video page.

        Args:
            url: Canonical Hanime video URL.

        Returns:
            The raw HTML content string.

        Raises:
            HanimeSecurityError: If URL targets an untrusted host.
            HanimeNetworkError: On connection/timeout failures.
            HanimeHttpClientError: On non-200 HTTP responses.
        """
        _validate_allowed_host(url)
        client = await self._get_client()

        headers = {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Referer": "https://hanime.tv/",
        }

        try:
            resp = await client.get(url, headers=headers)
        except httpx.TimeoutException as exc:
            raise HanimeNetworkError("Connection timed out while fetching Hanime video page.") from exc
        except httpx.RequestError as exc:
            raise HanimeNetworkError(f"Network error fetching video page: {exc.__class__.__name__}") from exc

        if resp.is_redirect:
            raise HanimeSecurityError(
                f"Unexpected redirect to '{resp.headers.get('location')}' (redirects disabled for security).",
                status_code=resp.status_code,
            )
        if resp.status_code == 404:
            raise HanimeHttpClientError("Hanime video page not found (404).", status_code=404)
        if resp.status_code != 200:
            raise HanimeHttpClientError(
                f"Failed to fetch video page, HTTP status {resp.status_code}.",
                status_code=resp.status_code,
            )

        return resp.text

    async def post_handshake(self, *, slug: str, signature: HanimeSignature) -> str:
        """Execute the authenticated handshake with auth.hanime.tv.

        Args:
            slug: Video slug identifier.
            signature: Valid HanimeSignature object.

        Returns:
            The raw encrypted x-token string from response headers.

        Raises:
            HanimeSecurityError: On unexpected redirect or untrusted host.
            HanimeHandshakeAuthError: On 401 or 403 responses.
            HanimeRateLimitError: On 429 response.
            HanimeServerError: On 5xx server responses.
            HanimeMalformedResponseError: When response is 200 but x-token header is absent or JSON is invalid.
        """
        _validate_allowed_host(_HANDSHAKE_ENDPOINT)
        client = await self._get_client()

        # Build encrypted handshake request payload discovered in H-1/H-2
        handshake_payload = {
            "timestamp_unix": int(time.time()),
            "directive": "htv_player_handshake",
            "slug": slug,
        }
        encrypted_token = encrypt_handshake_token(handshake_payload)

        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://hanime.tv/",
            "Origin": "https://hanime.tv",
            "x-signature-version": signature.version,
            "x-time": str(signature.stime),
            "x-signature": signature.signature,
            "x-csrf-token": "null",
        }

        try:
            resp = await client.post(
                _HANDSHAKE_ENDPOINT,
                json={"token": encrypted_token},
                headers=headers,
            )
        except httpx.TimeoutException as exc:
            raise HanimeNetworkError("Handshake request timed out.") from exc
        except httpx.RequestError as exc:
            raise HanimeNetworkError(f"Handshake network failure: {exc.__class__.__name__}") from exc

        if resp.is_redirect:
            raise HanimeSecurityError(
                f"Unexpected redirect from handshake endpoint to '{resp.headers.get('location')}'.",
                status_code=resp.status_code,
            )

        # Handle HTTP status codes explicitly
        if resp.status_code in (401, 403):
            raise HanimeHandshakeAuthError(
                f"Handshake authentication failed with HTTP {resp.status_code}.",
                status_code=resp.status_code,
            )
        if resp.status_code == 429:
            raise HanimeRateLimitError(
                "Rate limited by Hanime authentication server (HTTP 429).",
                status_code=429,
            )
        if resp.status_code >= 500:
            raise HanimeServerError(
                f"Hanime authentication service error (HTTP {resp.status_code}).",
                status_code=resp.status_code,
            )
        if resp.status_code != 200:
            raise HanimeHttpClientError(
                f"Handshake failed with unexpected HTTP {resp.status_code}.",
                status_code=resp.status_code,
            )

        # Validate JSON content if response body is non-empty
        body_json = None
        if resp.content and resp.content.strip():
            try:
                body_json = resp.json()
            except Exception as exc:
                raise HanimeMalformedResponseError("Handshake response body is not valid JSON.") from exc

        # Extract x-token header
        x_token = resp.headers.get("x-token")
        if not x_token or not x_token.strip():
            if isinstance(body_json, dict) and body_json.get("x-token"):
                x_token = body_json["x-token"]

        if not x_token or not x_token.strip():
            raise HanimeMalformedResponseError("Handshake returned 200 OK but x-token header was missing.")

        return x_token.strip()
