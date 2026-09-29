from __future__ import annotations

import os
from typing import Any
from unittest.mock import AsyncMock

import pytest

from app.platforms.hanime.crypto import encrypt_handshake_token
from app.platforms.hanime.extractor import (
    HanimeDecryptionFailureError,
    HanimeExtractor,
    HanimeMalformedPayloadError,
    HanimeNoPlayableFormatsError,
    HanimeUrlError,
    parse_iso_duration,
)
from app.platforms.hanime.http_client import (
    HanimeHandshakeAuthError,
    HttpHanimeClient,
)
from app.platforms.hanime.signature_provider import (
    HanimeSignature,
    HanimeSignatureProvider,
)


_SAMPLE_JSON_LD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Terra Story 1 - Hanime.tv</title>
    <script type="application/ld+json">
    {
        "@context": "https://schema.org",
        "@type": "VideoObject",
        "name": "Terra Story 1",
        "description": "Episode 1 of Terra Story adventure.",
        "thumbnailUrl": "https://static.hanime.tv/images/cover/terra-story-1.jpg",
        "uploadDate": "2024-03-15T12:00:00Z",
        "duration": "PT29M18S"
    }
    </script>
</head>
<body>
    <div id="app"></div>
</body>
</html>
"""

_SAMPLE_FALLBACK_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Terra Story 1 Fallback - Hanime.tv</title>
    <meta property="og:title" content="Terra Story 1 Fallback Title" />
    <meta property="og:description" content="Fallback description text." />
    <meta property="og:image" content="https://static.hanime.tv/fallback.jpg" />
</head>
<body>
    <div class="astro-island" data-props='{"video_id":[0,3537],"poster_url":[0,"https://static.hanime.tv/poster.jpg"]}'></div>
</body>
</html>
"""


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def mock_sig_provider() -> AsyncMock:
    provider = AsyncMock(spec=HanimeSignatureProvider)
    provider.get_signature.return_value = HanimeSignature(
        signature="b" * 64,
        stime=1727500000,
        version="web2",
    )
    return provider


@pytest.fixture
def mock_http_client() -> AsyncMock:
    client = AsyncMock(spec=HttpHanimeClient)
    client.get_video_page.return_value = _SAMPLE_JSON_LD_HTML
    return client


def _create_sample_x_token(sources: list[dict[str, Any]] | None = None) -> str:
    if sources is None:
        sources = [
            {"src": "", "height": 1080, "width": 1440, "label": "1080p", "kind": "promotion"},
            {"src": "/hls/3537/stream720.m3u8", "height": 720, "width": 960, "label": "720p", "kind": "normal"},
            {"src": "/hls/3537/stream480.m3u8", "height": 480, "width": 640, "label": "480p", "kind": "normal"},
            {"src": "/hls/3537/stream360.m3u8", "height": 360, "width": 480, "label": "360p", "kind": "normal"},
        ]
    payload = {"sources": sources}
    return encrypt_handshake_token(payload)


# ---------------------------------------------------------------------------
# Unit Tests 13 - 23
# ---------------------------------------------------------------------------

@pytest.mark.anyio
async def test_13_valid_url_accepted(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """13. Valid Hanime URL is accepted, normalized, and extracted."""
    mock_http_client.post_handshake.return_value = _create_sample_x_token()
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    valid_url = "https://hanime.tv/videos/hentai/terra-story-1"
    info_dict = await extractor.extract(valid_url)

    assert info_dict["id"] == "terra-story-1"
    assert info_dict["title"] == "Terra Story 1"
    assert info_dict["extractor"] == "hanime"
    assert len(info_dict["formats"]) == 3


@pytest.mark.anyio
async def test_14_invalid_url_rejected(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """14. Invalid or non-Hanime URLs are rejected with HanimeUrlError."""
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    with pytest.raises(HanimeUrlError, match="Unsupported or invalid"):
        await extractor.extract("https://youtube.com/watch?v=123")

    with pytest.raises(HanimeUrlError, match="Unsupported or invalid"):
        await extractor.extract("https://hanime.tv/browse/trending")

    with pytest.raises(HanimeUrlError, match="Unsupported or invalid"):
        await extractor.extract("not_even_a_url")


def test_15_duration_and_jsonld_metadata_parsing():
    """15. Test duration parsing from ISO 8601 string and JSON-LD fields."""
    assert parse_iso_duration("PT29M18S") == 1758
    assert parse_iso_duration("PT1H2M3S") == 3723
    assert parse_iso_duration("PT45S") == 45
    assert parse_iso_duration("PT1H") == 3600
    assert parse_iso_duration("invalid") is None
    assert parse_iso_duration(None) is None


@pytest.mark.anyio
async def test_15_metadata_extraction_from_jsonld(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """15. Extract title, thumbnail, duration, and upload_date from JSON-LD."""
    mock_http_client.get_video_page.return_value = _SAMPLE_JSON_LD_HTML
    mock_http_client.post_handshake.return_value = _create_sample_x_token()
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    assert info_dict["title"] == "Terra Story 1"
    assert info_dict["thumbnail"] == "https://static.hanime.tv/images/cover/terra-story-1.jpg"
    assert info_dict["duration"] == 1758
    assert info_dict["upload_date"] == "20240315"
    assert info_dict["description"] == "Episode 1 of Terra Story adventure."


@pytest.mark.anyio
async def test_16_metadata_fallback_if_jsonld_missing(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """16. Verify fallback to OpenGraph meta tags and Astro island props when JSON-LD is absent."""
    mock_http_client.get_video_page.return_value = _SAMPLE_FALLBACK_HTML
    mock_http_client.post_handshake.return_value = _create_sample_x_token()
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    assert info_dict["id"] == "3537"
    assert info_dict["title"] == "Terra Story 1 Fallback Title"
    assert info_dict["thumbnail"] == "https://static.hanime.tv/fallback.jpg"
    assert info_dict["description"] == "Fallback description text."
    assert info_dict["duration"] is None


@pytest.mark.anyio
async def test_17_successful_handshake_and_decryption(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """17. Complete pipeline: signature -> handshake -> token decryption -> info_dict."""
    mock_http_client.post_handshake.return_value = _create_sample_x_token()
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    assert info_dict["webpage_url"] == "https://hanime.tv/videos/hentai/terra-story-1"
    assert info_dict["extractor_key"] == "Hanime"
    assert isinstance(info_dict["formats"], list)
    assert len(info_dict["formats"]) == 3


@pytest.mark.anyio
async def test_18_1080p_empty_source_omitted(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """18. Verify empty/promotional 1080p source is excluded and never fabricated."""
    sources = [
        {"src": "", "height": 1080, "width": 1440, "label": "1080p", "kind": "promotion"},
        {"src": "/hls/stream720.m3u8", "height": 720, "width": 960, "label": "720p", "kind": "normal"},
    ]
    mock_http_client.post_handshake.return_value = _create_sample_x_token(sources)
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    format_labels = [f["format_id"] for f in info_dict["formats"]]
    assert "1080p" not in format_labels
    assert len(info_dict["formats"]) == 1
    assert info_dict["formats"][0]["format_id"] == "720p"


@pytest.mark.anyio
async def test_19_valid_formats_retained_with_full_urls(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """19. 720p, 480p, 360p formats retained with proper URLs and yt-dlp schema."""
    sources = [
        {"src": "/hls/3537/stream720.m3u8", "height": 720, "width": 960, "label": "720p", "kind": "normal"},
        {"src": "/hls/3537/stream480.m3u8", "height": 480, "width": 640, "label": "480p", "kind": "normal"},
        {"src": "https://hanime.tv/hls/3537/stream360.m3u8", "height": 360, "width": 480, "label": "360p", "kind": "normal"},
    ]
    mock_http_client.post_handshake.return_value = _create_sample_x_token(sources)
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    formats = info_dict["formats"]
    assert len(formats) == 3

    # Check 720p
    f720 = formats[0]
    assert f720["format_id"] == "720p"
    assert f720["height"] == 720
    assert f720["width"] == 960
    assert f720["url"] == "https://hanime.tv/hls/3537/stream720.m3u8"
    assert f720["protocol"] == "m3u8_native"
    assert f720["ext"] == "mp4"
    assert "Referer" in f720["http_headers"]

    # Check 360p (already absolute)
    f360 = formats[2]
    assert f360["format_id"] == "360p"
    assert f360["url"] == "https://hanime.tv/hls/3537/stream360.m3u8"


@pytest.mark.anyio
async def test_20_malformed_decrypted_payload_rejected(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """20. Test rejection when decrypted token is not a dict or missing sources list."""
    # Decryptable token containing invalid payload (not a dict)
    invalid_token_1 = encrypt_handshake_token(["not", "a", "dict"])
    mock_http_client.post_handshake.return_value = invalid_token_1
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    with pytest.raises(HanimeMalformedPayloadError, match="not a valid dictionary"):
        await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    # Missing sources key
    invalid_token_2 = encrypt_handshake_token({"other_field": 123})
    mock_http_client.post_handshake.return_value = invalid_token_2
    with pytest.raises(HanimeMalformedPayloadError, match="missing 'sources' list"):
        await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    # Undecryptable token
    mock_http_client.post_handshake.return_value = "totally_invalid_token_base64"
    with pytest.raises(HanimeDecryptionFailureError, match="Failed to decrypt"):
        await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")


@pytest.mark.anyio
async def test_21_no_playable_formats_rejected(mock_http_client: AsyncMock, mock_sig_provider: AsyncMock):
    """21. Rejection with HanimeNoPlayableFormatsError when all sources are empty/promo."""
    sources = [
        {"src": "", "height": 1080, "width": 1440, "label": "1080p", "kind": "promotion"},
        {"src": "", "height": 720, "width": 960, "label": "720p", "kind": "promotion"},
    ]
    mock_http_client.post_handshake.return_value = _create_sample_x_token(sources)
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    with pytest.raises(HanimeNoPlayableFormatsError, match="No playable formats available"):
        await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")


@pytest.mark.anyio
async def test_22_expired_signature_causes_exactly_one_forced_refresh(
    mock_http_client: AsyncMock, mock_sig_provider: AsyncMock
):
    """22. 401/403 triggers exactly one forced signature refresh and retries handshake."""
    valid_token = _create_sample_x_token()
    # First call fails with 401, second succeeds
    mock_http_client.post_handshake.side_effect = [
        HanimeHandshakeAuthError("Signature expired", status_code=401),
        valid_token,
    ]
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    info_dict = await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    assert mock_sig_provider.get_signature.call_count == 2
    mock_sig_provider.get_signature.assert_any_call(force_refresh=False)
    mock_sig_provider.get_signature.assert_any_call(force_refresh=True)
    assert mock_http_client.post_handshake.call_count == 2
    assert len(info_dict["formats"]) == 3


@pytest.mark.anyio
async def test_23_second_handshake_failure_surfaces_error(
    mock_http_client: AsyncMock, mock_sig_provider: AsyncMock
):
    """23. If second handshake also fails, error surfaces and no more retries occur."""
    mock_http_client.post_handshake.side_effect = [
        HanimeHandshakeAuthError("First 401", status_code=401),
        HanimeHandshakeAuthError("Second 401", status_code=401),
    ]
    extractor = HanimeExtractor(http_client=mock_http_client, signature_provider=mock_sig_provider)

    with pytest.raises(HanimeHandshakeAuthError, match="Second 401"):
        await extractor.extract("https://hanime.tv/videos/hentai/terra-story-1")

    assert mock_sig_provider.get_signature.call_count == 2
    assert mock_http_client.post_handshake.call_count == 2


# ---------------------------------------------------------------------------
# Opt-in Live Integration Test (Skipped by default)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(
    os.getenv("NEXORA_HANIME_LIVE_TEST") != "1",
    reason="Opt-in live integration test. Set NEXORA_HANIME_LIVE_TEST=1 to run.",
)
@pytest.mark.anyio
async def test_live_hanime_extraction():
    """Live integration test fetching real page and authenticating with auth.hanime.tv."""
    extractor = HanimeExtractor()
    try:
        url = "https://hanime.tv/videos/hentai/terra-story-1"
        result = await extractor.extract(url)

        assert result["title"], "Title must not be empty"
        assert result["extractor"] == "hanime"
        assert len(result["formats"]) > 0, "Must have playable formats"

        labels = [f["format_id"] for f in result["formats"]]
        assert "1080p" not in labels, "1080p must not be fabricated"
        assert any("720" in l for l in labels)
        for fmt in result["formats"]:
            assert fmt["url"].startswith("http")
            assert fmt["protocol"] == "m3u8_native"
    finally:
        await extractor.close()
