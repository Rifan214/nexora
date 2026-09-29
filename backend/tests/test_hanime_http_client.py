from __future__ import annotations

import logging
import pytest
import httpx

from app.platforms.hanime.http_client import (
    HanimeHandshakeAuthError,
    HanimeHttpClientError,
    HanimeMalformedResponseError,
    HanimeNetworkError,
    HanimeRateLimitError,
    HanimeSecurityError,
    HanimeServerError,
    HttpHanimeClient,
)
from app.platforms.hanime.signature_provider import HanimeSignature


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def dummy_signature() -> HanimeSignature:
    return HanimeSignature(
        signature="a" * 64,
        stime=1727500000,
        version="web2",
    )


@pytest.mark.anyio
async def test_01_successful_page_fetch():
    """1. Test successful HTML retrieval for a valid Hanime page."""
    html_content = "<html><head><title>Terra Story 1</title></head><body>Video Content</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "https://hanime.tv/videos/hentai/terra-story-1"
        assert request.headers["Referer"] == "https://hanime.tv/"
        return httpx.Response(200, text=html_content)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    result = await hanime_client.get_video_page("https://hanime.tv/videos/hentai/terra-story-1")
    assert result == html_content
    await hanime_client.close()


@pytest.mark.anyio
async def test_02_page_timeout():
    """2. Test timeout while fetching a video page maps to HanimeNetworkError."""
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("Timed out reading page")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeNetworkError, match="timed out"):
        await hanime_client.get_video_page("https://hanime.tv/videos/hentai/terra-story-1")


@pytest.mark.anyio
async def test_03_page_http_error():
    """3. Test page fetch handling for 404 and other non-200 HTTP statuses."""
    # 404 test
    def not_found_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, text="Not Found")

    client_404 = httpx.AsyncClient(transport=httpx.MockTransport(not_found_handler))
    hanime_client_404 = HttpHanimeClient(client=client_404)

    with pytest.raises(HanimeHttpClientError) as exc_info:
        await hanime_client_404.get_video_page("https://hanime.tv/videos/hentai/non-existent-video")
    assert exc_info.value.status_code == 404

    # 500 test
    def server_err_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="Internal Server Error")

    client_500 = httpx.AsyncClient(transport=httpx.MockTransport(server_err_handler))
    hanime_client_500 = HttpHanimeClient(client=client_500)

    with pytest.raises(HanimeHttpClientError) as exc_info500:
        await hanime_client_500.get_video_page("https://hanime.tv/videos/hentai/terra-story-1")
    assert exc_info500.value.status_code == 500


@pytest.mark.anyio
async def test_04_successful_handshake(dummy_signature: HanimeSignature):
    """4. Test successful handshake returns x-token from headers."""
    expected_token = "valid_encrypted_handshake_token_abc123"

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "https://auth.hanime.tv/api/v11/handshake"
        assert request.headers["x-signature"] == dummy_signature.signature
        assert request.headers["x-time"] == str(dummy_signature.stime)
        assert request.headers["x-signature-version"] == "web2"
        return httpx.Response(200, json={"status": "ok"}, headers={"x-token": expected_token})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    token = await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)
    assert token == expected_token


@pytest.mark.anyio
async def test_05_handshake_auth_error_401_403(dummy_signature: HanimeSignature):
    """5. Test 401 and 403 responses map to HanimeHandshakeAuthError."""
    # 401
    def handler_401(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "Signature expired"})

    client_401 = httpx.AsyncClient(transport=httpx.MockTransport(handler_401))
    hanime_client_401 = HttpHanimeClient(client=client_401)

    with pytest.raises(HanimeHandshakeAuthError) as exc_401:
        await hanime_client_401.post_handshake(slug="terra-story-1", signature=dummy_signature)
    assert exc_401.value.status_code == 401

    # 403
    def handler_403(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, json={"error": "Forbidden"})

    client_403 = httpx.AsyncClient(transport=httpx.MockTransport(handler_403))
    hanime_client_403 = HttpHanimeClient(client=client_403)

    with pytest.raises(HanimeHandshakeAuthError) as exc_403:
        await hanime_client_403.post_handshake(slug="terra-story-1", signature=dummy_signature)
    assert exc_403.value.status_code == 403


@pytest.mark.anyio
async def test_06_handshake_rate_limit_429(dummy_signature: HanimeSignature):
    """6. Test 429 response maps to HanimeRateLimitError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "Too Many Requests"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeRateLimitError) as exc:
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)
    assert exc.value.status_code == 429


@pytest.mark.anyio
async def test_07_handshake_server_error_5xx(dummy_signature: HanimeSignature):
    """7. Test 5xx responses map to HanimeServerError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(502, text="Bad Gateway")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeServerError) as exc:
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)
    assert exc.value.status_code == 502


@pytest.mark.anyio
async def test_08_handshake_missing_x_token(dummy_signature: HanimeSignature):
    """8. Test 200 OK without x-token header or body maps to HanimeMalformedResponseError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"status": "ok"})  # No x-token

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeMalformedResponseError, match="x-token header was missing"):
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)


@pytest.mark.anyio
async def test_09_handshake_invalid_json_response(dummy_signature: HanimeSignature):
    """9. Test 200 OK with invalid JSON body maps to HanimeMalformedResponseError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"invalid-non-json-content", headers={"content-type": "application/json"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeMalformedResponseError, match="not valid JSON"):
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)


@pytest.mark.anyio
async def test_10_network_failure(dummy_signature: HanimeSignature):
    """10. Test connection drop or DNS failure maps to HanimeNetworkError."""
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("Failed to establish connection")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with pytest.raises(HanimeNetworkError, match="network failure"):
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)


@pytest.mark.anyio
async def test_11_redirect_and_host_validation(dummy_signature: HanimeSignature):
    """11. Test SSRF protection rejects untrusted hosts and redirects."""
    hanime_client = HttpHanimeClient()

    # Untrusted domain
    with pytest.raises(HanimeSecurityError, match="blocked by security policy"):
        await hanime_client.get_video_page("https://evil-phishing.com/video")

    # Untrusted scheme
    with pytest.raises(HanimeSecurityError, match="Unsupported URL scheme"):
        await hanime_client.get_video_page("file:///etc/passwd")

    # Redirect rejection on page fetch
    def redirect_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(302, headers={"Location": "https://hanime.tv/other"})

    client_redir = httpx.AsyncClient(transport=httpx.MockTransport(redirect_handler))
    hanime_client_redir = HttpHanimeClient(client=client_redir)

    with pytest.raises(HanimeSecurityError, match="Unexpected redirect"):
        await hanime_client_redir.get_video_page("https://hanime.tv/videos/hentai/test")


@pytest.mark.anyio
async def test_12_credentials_not_logged(dummy_signature: HanimeSignature, caplog: pytest.LogCaptureFixture):
    """12. Verify that sensitive tokens, signatures, and payloads are never logged."""
    token = "secret_x_token_9999"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"status": "ok"}, headers={"x-token": token})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    hanime_client = HttpHanimeClient(client=client)

    with caplog.at_level(logging.DEBUG):
        await hanime_client.post_handshake(slug="terra-story-1", signature=dummy_signature)

    full_log_text = caplog.text
    assert dummy_signature.signature not in full_log_text
    assert str(dummy_signature.stime) not in full_log_text
    assert token not in full_log_text
