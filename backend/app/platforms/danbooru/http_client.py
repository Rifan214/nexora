from __future__ import annotations

import asyncio
import json
import logging
import ssl
from typing import Any

import httpx

from app.platforms.danbooru.constants import (
    DANBOORU_POST_API_TEMPLATE,
    DANBOORU_USER_AGENT,
    DEFAULT_CONNECT_TIMEOUT,
    DEFAULT_POOL_TIMEOUT,
    DEFAULT_READ_TIMEOUT,
    DEFAULT_WRITE_TIMEOUT,
)
from app.platforms.danbooru.exceptions import (
    DanbooruAccessDeniedError,
    DanbooruError,
    DanbooruMalformedResponseError,
    DanbooruNetworkError,
    DanbooruPostNotFoundError,
    DanbooruRateLimitedError,
    DanbooruServerError,
    DanbooruTimeoutError,
    DanbooruTlsError,
)

logger = logging.getLogger(__name__)


class HttpDanbooruClient:
    """Specialized HTTP client for Danbooru JSON API operations.

    Preserves strict TLS certificate verification, applies the approved
    targeted User-Agent, and enforces finite timeouts with redirect protection.
    """

    def __init__(
        self,
        *,
        client: httpx.AsyncClient | None = None,
        connect_timeout: float = DEFAULT_CONNECT_TIMEOUT,
        read_timeout: float = DEFAULT_READ_TIMEOUT,
        write_timeout: float = DEFAULT_WRITE_TIMEOUT,
        pool_timeout: float = DEFAULT_POOL_TIMEOUT,
        user_agent: str = DANBOORU_USER_AGENT,
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
        current_loop = asyncio.get_running_loop()
        if (
            self._client is None
            or self._client.is_closed
            or (self._external_client is None and self._client_loop != current_loop)
        ):
            self._client = httpx.AsyncClient(
                timeout=self._timeout,
                follow_redirects=False,
                verify=self._verify,
                headers={
                    "User-Agent": self._user_agent,
                    "Accept": "application/json",
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

    async def fetch_post_json(self, post_id: int) -> dict[str, Any]:
        """Fetch and parse post metadata from Danbooru's JSON API.

        Args:
            post_id: Positive integer ID of the Danbooru post.

        Returns:
            Decoded dictionary representing the post metadata.

        Raises:
            DanbooruPostNotFoundError: When the post returns HTTP 404.
            DanbooruAccessDeniedError: When the post returns HTTP 403.
            DanbooruRateLimitedError: When upstream returns HTTP 429.
            DanbooruServerError: When upstream returns HTTP 5xx.
            DanbooruTimeoutError: When connection or read times out.
            DanbooruTlsError: When TLS verification fails.
            DanbooruNetworkError: When connection to upstream fails.
            DanbooruMalformedResponseError: When response JSON is unparseable or unexpected.
        """
        api_url = DANBOORU_POST_API_TEMPLATE.format(post_id=post_id)
        client = await self._get_client()

        logger.debug("Fetching Danbooru post JSON url=%s post_id=%s", api_url, post_id)

        try:
            response = await client.get(api_url)
        except httpx.TimeoutException as exc:
            logger.warning("Danbooru API request timed out post_id=%s: %s", post_id, exc)
            raise DanbooruTimeoutError(f"Connection to Danbooru timed out for post {post_id}.") from exc
        except (ssl.SSLError, httpx.ConnectError) as exc:
            msg = str(exc).lower()
            if "certificate" in msg or "ssl" in msg or "verify" in msg or isinstance(exc, ssl.SSLError):
                logger.warning("Danbooru TLS verification failed post_id=%s: %s", post_id, exc)
                raise DanbooruTlsError(f"TLS certificate verification failed for post {post_id}.") from exc
            logger.warning("Danbooru network connection failed post_id=%s: %s", post_id, exc)
            raise DanbooruNetworkError(f"Failed to connect to Danbooru servers for post {post_id}.") from exc
        except httpx.RequestError as exc:
            logger.warning("Danbooru request failed post_id=%s: %s", post_id, exc)
            raise DanbooruNetworkError(f"Network request to Danbooru failed for post {post_id}: {exc}") from exc

        # Map HTTP status codes
        status = response.status_code
        if status == 200:
            pass
        elif status == 404:
            raise DanbooruPostNotFoundError(f"Danbooru post {post_id} was not found (HTTP 404).")
        elif status == 403:
            raise DanbooruAccessDeniedError(f"Access to Danbooru post {post_id} was forbidden (HTTP 403).")
        elif status == 429:
            raise DanbooruRateLimitedError("Danbooru rate limit reached (HTTP 429). Please wait before retrying.")
        elif 500 <= status < 600:
            raise DanbooruServerError(f"Danbooru server returned an error (HTTP {status}). Please try again later.")
        else:
            raise DanbooruError(f"Unexpected HTTP {status} response from Danbooru for post {post_id}.")

        try:
            payload = response.json()
        except (json.JSONDecodeError, ValueError) as exc:
            raise DanbooruMalformedResponseError(
                f"Danbooru returned invalid JSON for post {post_id}."
            ) from exc

        if not isinstance(payload, dict):
            raise DanbooruMalformedResponseError(
                f"Danbooru response for post {post_id} was not a valid dictionary."
            )

        return payload
