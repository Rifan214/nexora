from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
import ssl
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.platforms.rule34video.constants import (
    DEFAULT_CONNECT_TIMEOUT,
    DEFAULT_POOL_TIMEOUT,
    DEFAULT_READ_TIMEOUT,
    DEFAULT_WRITE_TIMEOUT,
    MAX_REDIRECT_HOPS,
    RULE34VIDEO_REFERER,
    RULE34VIDEO_USER_AGENT,
    is_rule34video_host,
    is_rule34video_targeted_host,
)
from app.platforms.rule34video.exceptions import (
    Rule34VideoAccessDeniedError,
    Rule34VideoError,
    Rule34VideoNetworkError,
    Rule34VideoNotFoundError,
    Rule34VideoRateLimitedError,
    Rule34VideoSecurityError,
    Rule34VideoServerError,
    Rule34VideoTimeoutError,
    Rule34VideoTlsError,
)

logger = logging.getLogger(__name__)


def is_safe_ip(ip_str: str) -> bool:
    """Check if an IP string is public and not private/loopback/link-local/reserved.

    Evaluates both IPv4 and IPv6 addresses consistently, unwrapping IPv4-mapped
    IPv6 addresses to their underlying IPv4 representations.
    """
    try:
        ip = ipaddress.ip_address(ip_str)
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
            ip = ip.ipv4_mapped
        return not (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        )
    except ValueError:
        return False


try:
    from httpcore._backends.anyio import AnyIOBackend

    class SafeNetworkBackend(AnyIOBackend):
        """Network backend ensuring the connected TCP socket peer IP is public and safe."""

        def __init__(self, *, allow_http_for_tests: bool = False) -> None:
            super().__init__()
            self._allow_http_for_tests = allow_http_for_tests

        async def connect_tcp(
            self,
            host: str,
            port: int,
            timeout: float | None = None,
            local_address: str | None = None,
            socket_options: Any = None,
        ) -> Any:
            stream = await super().connect_tcp(
                host,
                port,
                timeout=timeout,
                local_address=local_address,
                socket_options=socket_options,
            )
            if not self._allow_http_for_tests:
                peer_ip = None
                try:
                    server_addr = stream.get_extra_info("server_addr")
                    if server_addr and isinstance(server_addr, tuple) and len(server_addr) > 0:
                        peer_ip = str(server_addr[0])
                    else:
                        sock = stream.get_extra_info("socket")
                        if sock is None:
                            sock = getattr(getattr(stream, "_stream", None), "_raw_socket", None)
                        if sock and hasattr(sock, "getpeername"):
                            peer_ip = str(sock.getpeername()[0])
                except Exception as exc:
                    await stream.aclose()
                    raise Rule34VideoSecurityError(
                        f"Failed to inspect peer address for host '{host}': {exc}"
                    ) from exc

                if not peer_ip or not is_safe_ip(peer_ip):
                    await stream.aclose()
                    raise Rule34VideoSecurityError(
                        f"Host '{host}' established connection to forbidden or unverified peer IP '{peer_ip}'."
                    )
            return stream

except ImportError:
    SafeNetworkBackend = Any  # type: ignore[misc,assignment]


class SafeAsyncHTTPTransport(httpx.AsyncHTTPTransport):
    """Async HTTP transport enforcing socket connection peer IP validation."""

    def __init__(self, *args: Any, allow_http_for_tests: bool = False, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        if (
            SafeNetworkBackend is not Any
            and hasattr(self, "_pool")
            and hasattr(self._pool, "_network_backend")
        ):
            self._pool._network_backend = SafeNetworkBackend(
                allow_http_for_tests=allow_http_for_tests
            )


def sanitize_url_for_logging(url: str) -> str:
    """Redact sensitive query parameters from URLs before logging."""
    try:
        parsed = urlsplit(url)
        if not parsed.query:
            return url
        return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "<redacted>", ""))
    except Exception:
        return "<invalid-url>"


def validate_url_security(
    url: str,
    *,
    allow_cdn: bool = False,
    allow_http_for_tests: bool = False,
) -> None:
    """Enforce strict host and scheme validation to prevent SSRF and insecure requests."""
    try:
        parsed = urlsplit(url)
    except Exception as exc:
        raise Rule34VideoSecurityError(f"Malformed URL: '{url}'") from exc

    scheme = (parsed.scheme or "").casefold()
    allowed_schemes = {"https", "http"} if allow_http_for_tests else {"https"}
    if scheme not in allowed_schemes:
        raise Rule34VideoSecurityError(
            f"Insecure or unsupported URL scheme '{scheme}'. Expected https."
        )

    hostname = (parsed.hostname or "").casefold()
    if not hostname:
        raise Rule34VideoSecurityError("URL has no hostname.")

    # Check if hostname is an IP literal
    try:
        ip = ipaddress.ip_address(hostname)
        if not is_safe_ip(str(ip)):
            raise Rule34VideoSecurityError(
                f"Direct IP access to private/loopback address '{hostname}' is forbidden."
            )
        raise Rule34VideoSecurityError(
            f"Direct IP address access '{hostname}' is not permitted."
        )
    except ValueError:
        pass

    # Check host against allowlist
    if is_rule34video_host(hostname):
        return
    if allow_cdn and is_rule34video_targeted_host(hostname):
        return

    raise Rule34VideoSecurityError(
        f"Untrusted host '{hostname}'. Media and requests must target authorized Rule34Video hosts."
    )


def verify_resolved_ip_is_safe(hostname: str) -> None:
    """Resolve hostname and ensure it does not map to private/loopback network addresses."""
    try:
        addrinfo = socket.getaddrinfo(hostname, None)
        for _, _, _, _, sockaddr in addrinfo:
            ip_str = sockaddr[0]
            if not is_safe_ip(ip_str):
                raise Rule34VideoSecurityError(
                    f"Host '{hostname}' resolved to private/forbidden IP '{ip_str}'."
                )
    except socket.gaierror:
        # Let network client handle DNS resolution failure
        pass


class HttpRule34VideoClient:
    """Specialized async HTTP client for Rule34Video web requests with SSRF protections."""

    def __init__(
        self,
        *,
        client: httpx.AsyncClient | None = None,
        connect_timeout: float = DEFAULT_CONNECT_TIMEOUT,
        read_timeout: float = DEFAULT_READ_TIMEOUT,
        write_timeout: float = DEFAULT_WRITE_TIMEOUT,
        pool_timeout: float = DEFAULT_POOL_TIMEOUT,
        user_agent: str = RULE34VIDEO_USER_AGENT,
        verify: bool | Any = True,
        allow_http_for_tests: bool = False,
    ) -> None:
        self._user_agent = user_agent
        self._verify = verify
        self._allow_http_for_tests = allow_http_for_tests
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
        current_loop = asyncio.get_running_loop()
        if (
            self._client is None
            or self._client.is_closed
            or (self._external_client is None and self._client_loop != current_loop)
        ):
            transport = SafeAsyncHTTPTransport(
                verify=self._verify,
                allow_http_for_tests=self._allow_http_for_tests,
            )
            self._client = httpx.AsyncClient(
                transport=transport,
                timeout=self._timeout,
                follow_redirects=False,
                verify=self._verify,
                headers={
                    "User-Agent": self._user_agent,
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    "Accept-Language": "en-US,en;q=0.9",
                    "Referer": RULE34VIDEO_REFERER,
                },
            )
            self._client_loop = current_loop
        return self._client

    async def close(self) -> None:
        """Close the internally managed HTTP client session."""
        if self._client is not None and self._external_client is None:
            if not self._client.is_closed:
                await self._client.aclose()
            self._client = None

    async def fetch_html(self, url: str) -> str:
        """Fetch webpage HTML from Rule34Video with manual redirect and SSRF checks.

        Args:
            url: Target Rule34Video webpage URL.

        Returns:
            Webpage HTML content string.
        """
        validate_url_security(
            url,
            allow_cdn=False,
            allow_http_for_tests=self._allow_http_for_tests,
        )
        parsed = urlsplit(url)
        if parsed.hostname and not self._allow_http_for_tests:
            verify_resolved_ip_is_safe(parsed.hostname)

        client = await self._get_client()
        current_url = url
        redirect_hops = 0

        while True:
            logger.debug(
                "Fetching Rule34Video webpage url=%s hop=%d",
                sanitize_url_for_logging(current_url),
                redirect_hops,
            )

            try:
                response = await client.get(current_url)
            except httpx.TimeoutException as exc:
                logger.warning(
                    "Rule34Video request timed out url=%s: %s",
                    sanitize_url_for_logging(current_url),
                    exc,
                )
                raise Rule34VideoTimeoutError(
                    f"Connection to Rule34Video timed out for {sanitize_url_for_logging(current_url)}."
                ) from exc
            except (ssl.SSLError, httpx.ConnectError) as exc:
                msg = str(exc).casefold()
                if (
                    "certificate" in msg
                    or "ssl" in msg
                    or "verify" in msg
                    or isinstance(exc, ssl.SSLError)
                ):
                    logger.warning(
                        "Rule34Video TLS verification failed url=%s: %s",
                        sanitize_url_for_logging(current_url),
                        exc,
                    )
                    raise Rule34VideoTlsError(
                        f"TLS certificate verification failed for {sanitize_url_for_logging(current_url)}."
                    ) from exc
                logger.warning(
                    "Rule34Video connection failed url=%s: %s",
                    sanitize_url_for_logging(current_url),
                    exc,
                )
                raise Rule34VideoNetworkError(
                    f"Failed to connect to Rule34Video for {sanitize_url_for_logging(current_url)}."
                ) from exc
            except httpx.RequestError as exc:
                logger.warning(
                    "Rule34Video request failed url=%s: %s",
                    sanitize_url_for_logging(current_url),
                    exc,
                )
                raise Rule34VideoNetworkError(
                    f"Network request to Rule34Video failed: {exc}"
                ) from exc

            # Handle redirects manually to enforce SSRF validation at every hop
            if response.status_code in (301, 302, 303, 307, 308):
                redirect_hops += 1
                if redirect_hops > MAX_REDIRECT_HOPS:
                    raise Rule34VideoNetworkError(
                        f"Exceeded maximum redirect hops ({MAX_REDIRECT_HOPS})."
                    )

                location = response.headers.get("Location")
                if not location:
                    raise Rule34VideoNetworkError("Redirect received without Location header.")

                # Resolve relative redirects safely
                next_url = str(response.url.join(location))
                validate_url_security(
                    next_url,
                    allow_cdn=True,
                    allow_http_for_tests=self._allow_http_for_tests,
                )
                next_parsed = urlsplit(next_url)
                if next_parsed.hostname and not self._allow_http_for_tests:
                    verify_resolved_ip_is_safe(next_parsed.hostname)

                current_url = next_url
                continue

            status = response.status_code
            if status == 200:
                return response.text
            elif status == 404:
                raise Rule34VideoNotFoundError(
                    f"Rule34Video content was not found (HTTP 404): {sanitize_url_for_logging(current_url)}"
                )
            elif status == 403:
                raise Rule34VideoAccessDeniedError(
                    f"Access to Rule34Video content was forbidden (HTTP 403): {sanitize_url_for_logging(current_url)}"
                )
            elif status == 429:
                raise Rule34VideoRateLimitedError(
                    "Rule34Video rate limit reached (HTTP 429). Please wait before retrying."
                )
            elif 500 <= status < 600:
                raise Rule34VideoServerError(
                    f"Rule34Video server returned an error (HTTP {status}). Please try again later."
                )
            else:
                raise Rule34VideoError(
                    f"Unexpected HTTP {status} response from Rule34Video for {sanitize_url_for_logging(current_url)}."
                )

    async def resolve_media_url(
        self,
        media_url: str,
        *,
        max_redirects: int = MAX_REDIRECT_HOPS,
    ) -> tuple[str, int | None]:
        """Resolve a Rule34Video media URL through its redirect chain to the final validated CDN URL.

        Inspects each HTTP redirect hop individually, validating:
        - HTTPS scheme (rejects HTTP downgrades).
        - Destination host is an authorized Rule34Video or approved CDN host.
        - Destination host and connected IP are public and safe (no SSRF to private/loopback).
        - Redirect chain does not exceed max_redirects (default 5).
        - Preserves required upstream headers (User-Agent, Referer) while avoiding forwarding
          sensitive headers across different origins.
        - Reads Content-Length from the final CDN response to provide the exact media filesize.

        Returns:
            tuple of (final_validated_cdn_url, exact_content_length_or_none)
        """
        validate_url_security(
            media_url,
            allow_cdn=True,
            allow_http_for_tests=self._allow_http_for_tests,
        )
        parsed = urlsplit(media_url)
        if parsed.hostname and not self._allow_http_for_tests:
            verify_resolved_ip_is_safe(parsed.hostname)

        client = await self._get_client()
        current_url = media_url
        redirect_hops = 0

        while True:
            logger.debug(
                "Resolving Rule34Video media URL=%s hop=%d",
                sanitize_url_for_logging(current_url),
                redirect_hops,
            )
            headers = {
                "User-Agent": self._user_agent,
                "Referer": RULE34VIDEO_REFERER,
            }

            try:
                # First try HEAD to avoid downloading any response payload
                response = await client.head(current_url, headers=headers)
                # If HEAD is disallowed (405) or returns 200 without Content-Length, fall back to streaming Range request
                if response.status_code == 405 or (
                    response.status_code == 200 and not response.headers.get("content-length")
                ):
                    async with client.stream(
                        "GET",
                        current_url,
                        headers={**headers, "Range": "bytes=0-0"},
                    ) as stream_resp:
                        status = stream_resp.status_code
                        resp_headers = dict(stream_resp.headers)
                        resp_url = stream_resp.url
                else:
                    status = response.status_code
                    resp_headers = dict(response.headers)
                    resp_url = response.url
            except httpx.TimeoutException as exc:
                raise Rule34VideoTimeoutError(
                    f"Connection to media server timed out for {sanitize_url_for_logging(current_url)}."
                ) from exc
            except (ssl.SSLError, httpx.ConnectError) as exc:
                msg = str(exc).casefold()
                if "certificate" in msg or "ssl" in msg or "verify" in msg or isinstance(exc, ssl.SSLError):
                    raise Rule34VideoTlsError(
                        f"TLS certificate verification failed for {sanitize_url_for_logging(current_url)}."
                    ) from exc
                raise Rule34VideoNetworkError(
                    f"Failed to connect to media server for {sanitize_url_for_logging(current_url)}."
                ) from exc
            except httpx.RequestError as exc:
                raise Rule34VideoNetworkError(
                    f"Network request to media server failed: {exc}"
                ) from exc

            # Handle redirects hop-by-hop with security validation
            if status in (301, 302, 303, 307, 308):
                redirect_hops += 1
                if redirect_hops > max_redirects:
                    raise Rule34VideoNetworkError(
                        f"Exceeded maximum redirect hops ({max_redirects})."
                    )

                location = resp_headers.get("location") or resp_headers.get("Location")
                if not location:
                    raise Rule34VideoNetworkError("Redirect received without Location header.")

                next_url = str(resp_url.join(location))
                validate_url_security(
                    next_url,
                    allow_cdn=True,
                    allow_http_for_tests=self._allow_http_for_tests,
                )
                next_parsed = urlsplit(next_url)
                if next_parsed.hostname and not self._allow_http_for_tests:
                    verify_resolved_ip_is_safe(next_parsed.hostname)

                current_url = next_url
                continue

            if status in (200, 206):
                # Parse exact Content-Length
                exact_size: int | None = None
                cl = resp_headers.get("content-length")
                if cl and cl.isdigit():
                    exact_size = int(cl)
                if status == 206:
                    cr = resp_headers.get("content-range")
                    if cr and "/" in cr:
                        total_part = cr.rsplit("/", 1)[-1].strip()
                        if total_part.isdigit():
                            exact_size = int(total_part)

                return current_url, exact_size
            elif status == 404:
                raise Rule34VideoNotFoundError(
                    f"Rule34Video media was not found (HTTP 404): {sanitize_url_for_logging(current_url)}"
                )
            elif status == 403:
                raise Rule34VideoAccessDeniedError(
                    f"Access to Rule34Video media was forbidden (HTTP 403): {sanitize_url_for_logging(current_url)}"
                )
            elif status == 429:
                raise Rule34VideoRateLimitedError(
                    "Rule34Video rate limit reached (HTTP 429). Please wait before retrying."
                )
            elif 500 <= status < 600:
                raise Rule34VideoServerError(
                    f"Rule34Video media server returned an error (HTTP {status})."
                )
            else:
                raise Rule34VideoError(
                    f"Unexpected HTTP {status} response from media server for {sanitize_url_for_logging(current_url)}."
                )

