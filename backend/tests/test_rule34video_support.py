from __future__ import annotations

import json
from pathlib import Path
from yt_dlp.utils import DownloadError
from typing import Any
from unittest.mock import ANY, AsyncMock, MagicMock, patch
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes.media import get_media_service
from app.core.config import get_settings
from app.core.exceptions import APIError
from app.main import app
from app.models.requests import MediaDownloadRequest, MediaInfoRequest
from app.platforms.rule34video import (
    ALLOWED_CDN_DOMAIN,
    ALLOWED_MEDIA_HOSTS,
    RULE34VIDEO_HOST,
    RULE34VIDEO_REFERER,
    RULE34VIDEO_USER_AGENT,
    RULE34VIDEO_WWW_HOST,
    HttpRule34VideoClient,
    Rule34VideoAccessDeniedError,
    Rule34VideoError,
    Rule34VideoExtractor,
    Rule34VideoMalformedResponseError,
    Rule34VideoNetworkError,
    Rule34VideoNotFoundError,
    Rule34VideoRateLimitedError,
    Rule34VideoSecurityError,
    Rule34VideoServerError,
    Rule34VideoTimeoutError,
    Rule34VideoTlsError,
    Rule34VideoUnsupportedMediaError,
    Rule34VideoUrlError,
    extract_rule34video_video_id,
    is_allowed_rule34video_cdn_host,
    is_rule34video_host,
    is_rule34video_targeted_host,
    is_rule34video_targeted_url,
    is_safe_ip,
    parse_clock_duration,
    parse_filesize_bytes,
    parse_iso8601_duration,
    sanitize_url_for_logging,
    validate_url_security,
    MAX_REDIRECT_HOPS,
    SafeRule34VideoRedirectHandler,
    configure_rule34video_network_guards,
)
from app.services.media_service import MediaService
from app.services.quality_selector import QualitySelector
from app.utils.platforms import (
    detect_platform_from_url,
    is_rule34video_media_url,
    normalize_media_url,
)


from app.services.job_manager import get_job_manager


@pytest.fixture(autouse=True)
def clear_caches() -> None:
    get_settings.cache_clear()
    get_media_service.cache_clear()
    get_job_manager.cache_clear()
    yield
    get_settings.cache_clear()
    get_media_service.cache_clear()
    get_job_manager.cache_clear()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


_SAMPLE_RULE34VIDEO_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Fujiwara Chika Ecchi Past time Animation - Rule34Video</title>
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "VideoObject",
      "name": "Fujiwara Chika Ecchi Past time Animation",
      "description": "Chika s Ecchi Pasttime",
      "thumbnailUrl": "https://rule34video.com/contents/videos_screenshots/4667000/4667334/preview.jpg",
      "uploadDate": "2026-10-14",
      "duration": "PT0H1M52S",
      "contentUrl": "https://rule34video.com/get_file/58/5084998489e92997a5abbb4edca5813c/4667000/4667334/4667334_360.mp4/",
      "interactionStatistic": [
        {
          "@type": "InteractionCounter",
          "interactionType": "http://schema.org/WatchAction",
          "userInteractionCount": "54230"
        },
        {
          "@type": "InteractionCounter",
          "interactionType": "http://schema.org/LikeAction",
          "userInteractionCount": "167"
        }
      ]
    }
    </script>
</head>
<body>
    <div class="video-sheet">
        <a class="tag_item tag_item_download vp-sheet__item" href="https://rule34video.com/get_file/58/f163c2e9126e93c1429e2016c179db70/4667000/4667334/4667334_1080p.mp4/?v-acctoken=token1&download=true">
            <svg class="vp-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v9.6l3.3-3.3"/></svg>
            MP4 1080p<span class="vp-sheet__meta">55 MB</span>
        </a>
        <a class="tag_item tag_item_download vp-sheet__item" href="https://rule34video.com/get_file/58/9616fee946c74b9a20cfa6681c18ecb3/4667000/4667334/4667334_720p.mp4/?v-acctoken=token2&download=true">
            <svg class="vp-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v9.6l3.3-3.3"/></svg>
            MP4 720p<span class="vp-sheet__meta">30 MB</span>
        </a>
        <a class="tag_item tag_item_download vp-sheet__item" href="https://rule34video.com/get_file/58/00306b8059930177e68881582c85c17a/4667000/4667334/4667334_480p.mp4/?v-acctoken=token3&download=true">
            <svg class="vp-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v9.6l3.3-3.3"/></svg>
            MP4 480p<span class="vp-sheet__meta">16 MB</span>
        </a>
        <a class="tag_item tag_item_download vp-sheet__item" href="https://rule34video.com/get_file/58/5084998489e92997a5abbb4edca5813c/4667000/4667334/4667334_360.mp4/?v-acctoken=token4&download=true">
            <svg class="vp-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v9.6l3.3-3.3"/></svg>
            MP4 360p<span class="vp-sheet__meta">11 MB</span>
        </a>
    </div>

    <script>
    var flashvars = {
        video_id: '4667334',
        video_title: 'Fujiwara Chika Ecchi Past time Animation',
        video_models: 'Shiina Ecchi',
        preview_url: 'https://rule34video.com/contents/videos_screenshots/4667000/4667334/preview.jpg',
        video_url: 'https://rule34video.com/get_file/58/5084998489e92997a5abbb4edca5813c/4667000/4667334/4667334_360.mp4/?download=true',
        video_url_text: '360p',
        video_alt_url: 'https://rule34video.com/get_file/58/00306b8059930177e68881582c85c17a/4667000/4667334/4667334_480p.mp4/?download=true',
        video_alt_url_text: '480p',
        video_alt_url2: 'https://rule34video.com/get_file/58/9616fee946c74b9a20cfa6681c18ecb3/4667000/4667334/4667334_720p.mp4/?download=true',
        video_alt_url2_text: '720p',
        video_alt_url3: 'https://rule34video.com/get_file/58/f163c2e9126e93c1429e2016c179db70/4667000/4667334/4667334_1080p.mp4/?download=true',
        video_alt_url3_text: '1080p'
    };
    </script>
</body>
</html>
"""


# ============================================================================
# 1. URL Parsing and Platform Detection Tests
# ============================================================================


def test_is_rule34video_media_url_valid() -> None:
    assert is_rule34video_media_url(
        "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    )
    assert is_rule34video_media_url(
        "https://www.rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    )
    assert is_rule34video_media_url("https://rule34video.com/video/4667334/")
    assert is_rule34video_media_url("https://rule34video.com/video/4667334")
    assert is_rule34video_media_url("https://rule34video.com/videos/4667334/some-slug/")


def test_is_rule34video_media_url_invalid() -> None:
    assert not is_rule34video_media_url("https://rule34video.com/categories/")
    assert not is_rule34video_media_url("https://rule34video.com/search/chika/")
    assert not is_rule34video_media_url("https://rule34video.com/video/0/")
    assert not is_rule34video_media_url("https://rule34video.com/video/-5/")
    assert not is_rule34video_media_url("https://rule34video.com/video/abc/")
    assert not is_rule34video_media_url("https://fake-rule34video.com/video/4667334/")
    assert not is_rule34video_media_url("ftp://rule34video.com/video/4667334/")


def test_detect_platform_from_url_rule34video() -> None:
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    assert detect_platform_from_url(url) == "rule34video"

    www_url = "https://www.rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    assert detect_platform_from_url(www_url) == "rule34video"


def test_extract_rule34video_video_id() -> None:
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    assert extract_rule34video_video_id(url) == 4667334

    short_url = "https://rule34video.com/video/4667334"
    assert extract_rule34video_video_id(short_url) == 4667334

    assert extract_rule34video_video_id("https://rule34video.com/tags/chika/") is None
    assert extract_rule34video_video_id("https://not-rule34video.com/video/4667334/") is None


def test_normalize_media_url_rule34video() -> None:
    url = "http://www.rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/?ref=share#section"
    normalized = normalize_media_url(url)
    assert normalized == "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"


# ============================================================================
# 2. SSRF, Host Whitelisting & Security Tests
# ============================================================================


def test_is_rule34video_host() -> None:
    assert is_rule34video_host("rule34video.com")
    assert is_rule34video_host("www.rule34video.com")
    assert is_rule34video_host("RULE34VIDEO.COM")
    assert not is_rule34video_host("evil-rule34video.com")
    assert not is_rule34video_host("cdn.rule34video.com.attacker.com")
    assert not is_rule34video_host(None)


def test_is_allowed_rule34video_cdn_host() -> None:
    assert is_allowed_rule34video_cdn_host("boomio-cdn.com")
    assert is_allowed_rule34video_cdn_host("eu-cdn10-prem.boomio-cdn.com")
    assert is_allowed_rule34video_cdn_host("us-cdn2.boomio-cdn.com")
    assert not is_allowed_rule34video_cdn_host("evilboomio-cdn.com")
    assert not is_allowed_rule34video_cdn_host("boomio-cdn.com.evil.com")
    assert not is_allowed_rule34video_cdn_host(None)


def test_is_safe_ip() -> None:
    assert is_safe_ip("8.8.8.8")
    assert is_safe_ip("1.1.1.1")
    assert not is_safe_ip("127.0.0.1")
    assert not is_safe_ip("10.0.0.1")
    assert not is_safe_ip("192.168.1.1")
    assert not is_safe_ip("172.16.0.1")
    assert not is_safe_ip("169.254.1.1")
    assert not is_safe_ip("::1")
    assert not is_safe_ip("fe80::1")
    assert not is_safe_ip("invalid_ip")


def test_validate_url_security_valid() -> None:
    validate_url_security("https://rule34video.com/video/123/slug/")
    validate_url_security("https://www.rule34video.com/video/123/slug/")
    validate_url_security(
        "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=test.mp4",
        allow_cdn=True,
    )


def test_validate_url_security_insecure_scheme() -> None:
    with pytest.raises(Rule34VideoSecurityError, match="Insecure or unsupported URL scheme"):
        validate_url_security("http://rule34video.com/video/123/slug/")
    with pytest.raises(Rule34VideoSecurityError, match="Insecure or unsupported URL scheme"):
        validate_url_security("ftp://rule34video.com/video/123/slug/")


def test_validate_url_security_untrusted_host() -> None:
    with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
        validate_url_security("https://attacker.com/malicious.mp4")
    with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
        validate_url_security("https://eu-cdn10-prem.boomio-cdn.com/test.mp4", allow_cdn=False)


def test_validate_url_security_private_ip() -> None:
    with pytest.raises(Rule34VideoSecurityError, match="forbidden|not permitted"):
        validate_url_security("https://127.0.0.1/video/123/")
    with pytest.raises(Rule34VideoSecurityError, match="forbidden|not permitted"):
        validate_url_security("https://192.168.1.1/video/123/")


def test_sanitize_url_for_logging() -> None:
    url = "https://rule34video.com/get_file/123.mp4/?v-acctoken=SECRET_TOKEN&download=true"
    sanitized = sanitize_url_for_logging(url)
    assert "SECRET_TOKEN" not in sanitized
    assert "<redacted>" in sanitized
    assert sanitized.startswith("https://rule34video.com/get_file/123.mp4/?<redacted>")


# ============================================================================
# 3. Parsers & Helpers Tests
# ============================================================================


def test_parse_iso8601_duration() -> None:
    assert parse_iso8601_duration("PT0H1M52S") == 112
    assert parse_iso8601_duration("PT1M52S") == 112
    assert parse_iso8601_duration("PT45S") == 45
    assert parse_iso8601_duration("PT1H0M0S") == 3600
    assert parse_iso8601_duration("PT2H30M15S") == 9015
    assert parse_iso8601_duration(None) is None
    assert parse_iso8601_duration("invalid") is None


def test_parse_clock_duration() -> None:
    assert parse_clock_duration("1:52") == 112
    assert parse_clock_duration("01:52") == 112
    assert parse_clock_duration("45") == 45
    assert parse_clock_duration("01:00:00") == 3600
    assert parse_clock_duration(None) is None
    assert parse_clock_duration("abc") is None


def test_parse_filesize_bytes() -> None:
    assert parse_filesize_bytes("55 MB") == 55 * 1024 * 1024
    assert parse_filesize_bytes("30.5 MB") == int(30.5 * 1024 * 1024)
    assert parse_filesize_bytes("1.2 GB") == int(1.2 * 1024 * 1024 * 1024)
    assert parse_filesize_bytes("500 KB") == 500 * 1024
    assert parse_filesize_bytes(None) is None
    assert parse_filesize_bytes("no digits") is None


# ============================================================================
# 4. HTTP Client Mock Tests
# ============================================================================


@pytest.mark.anyio
async def test_http_client_fetch_200() -> None:
    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 200
    mock_response.text = _SAMPLE_RULE34VIDEO_HTML

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    html = await client.fetch_html("https://rule34video.com/video/4667334/slug/")
    assert "Fujiwara Chika" in html


@pytest.mark.anyio
async def test_http_client_fetch_404() -> None:
    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 404
    mock_response.text = "Not Found"

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoNotFoundError, match="HTTP 404"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_fetch_403() -> None:
    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 403
    mock_response.text = "Forbidden"

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoAccessDeniedError, match="HTTP 403"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_fetch_429() -> None:
    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 429
    mock_response.text = "Rate Limited"

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoRateLimitedError, match="HTTP 429"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_fetch_500() -> None:
    mock_response = MagicMock(spec=httpx.Response)
    mock_response.status_code = 500
    mock_response.text = "Internal Server Error"

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoServerError, match="HTTP 500"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_timeout() -> None:
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(side_effect=httpx.ReadTimeout("Timeout"))
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoTimeoutError, match="timed out"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_tls_error() -> None:
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(side_effect=httpx.ConnectError("SSL: certificate verify failed"))
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoTlsError, match="TLS certificate verification failed"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_http_client_redirect_ssrf_blocked() -> None:
    # First response is a 302 pointing to an attacker host
    redirect_resp = MagicMock(spec=httpx.Response)
    redirect_resp.status_code = 302
    redirect_resp.headers = {"Location": "https://attacker.com/steal-data"}
    redirect_resp.url = httpx.URL("https://rule34video.com/video/4667334/slug/")

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=redirect_resp)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
        await client.fetch_html("https://rule34video.com/video/4667334/slug/")


# ============================================================================
# 5. Extractor Unit Tests
# ============================================================================


@pytest.mark.anyio
async def test_extractor_extract_success() -> None:
    mock_http_client = AsyncMock(spec=HttpRule34VideoClient)
    mock_http_client.fetch_html = AsyncMock(return_value=_SAMPLE_RULE34VIDEO_HTML)

    extractor = Rule34VideoExtractor(http_client=mock_http_client)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    result = await extractor.extract(url)

    assert result["id"] == "4667334"
    assert result["title"] == "Fujiwara Chika Ecchi Past time Animation"
    assert result["duration"] == 112
    assert result["view_count"] == 54230
    assert result["like_count"] == 167
    assert result["thumbnail"] == "https://rule34video.com/contents/videos_screenshots/4667000/4667334/preview.jpg"
    assert result["uploader"] == "Shiina Ecchi"
    assert result["extractor"] == "rule34video"

    formats = result["formats"]
    assert len(formats) == 4
    assert [f["format_id"] for f in formats] == ["1080p", "720p", "480p", "360p"]
    assert formats[0]["height"] == 1080
    assert formats[0]["filesize"] is None
    assert formats[0]["filesize_approx"] == 55 * 1024 * 1024
    assert formats[0]["ext"] == "mp4"
    assert formats[0]["vcodec"] == "h264"
    assert formats[0]["acodec"] == "aac"


@pytest.mark.anyio
async def test_extractor_invalid_url() -> None:
    extractor = Rule34VideoExtractor()
    with pytest.raises(Rule34VideoUrlError, match="Invalid or unsupported Rule34Video URL"):
        await extractor.extract("https://rule34video.com/categories/")


@pytest.mark.anyio
async def test_extractor_no_formats_found() -> None:
    empty_html = "<html><body><h1>No video here</h1></body></html>"
    mock_http_client = AsyncMock(spec=HttpRule34VideoClient)
    mock_http_client.fetch_html = AsyncMock(return_value=empty_html)

    extractor = Rule34VideoExtractor(http_client=mock_http_client)
    with pytest.raises(Rule34VideoUnsupportedMediaError, match="No downloadable video formats were found"):
        await extractor.extract("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_extractor_empty_response() -> None:
    mock_http_client = AsyncMock(spec=HttpRule34VideoClient)
    mock_http_client.fetch_html = AsyncMock(return_value="")

    extractor = Rule34VideoExtractor(http_client=mock_http_client)
    with pytest.raises(Rule34VideoMalformedResponseError, match="Empty response received"):
        await extractor.extract("https://rule34video.com/video/4667334/slug/")


@pytest.mark.anyio
async def test_extractor_fallback_to_flashvars_when_anchors_missing() -> None:
    flashvars_only_html = """
    <html>
    <head><title>Chika Video - Rule34Video</title></head>
    <body>
    <script>
    var flashvars = {
        video_id: '4667334',
        video_title: 'Chika Video',
        video_url: 'https://rule34video.com/get_file/360.mp4/?download=true',
        video_url_text: '360p',
        video_alt_url: 'https://rule34video.com/get_file/720.mp4/?download=true',
        video_alt_url_text: '720p'
    };
    </script>
    </body>
    </html>
    """
    mock_http_client = AsyncMock(spec=HttpRule34VideoClient)
    mock_http_client.fetch_html = AsyncMock(return_value=flashvars_only_html)

    extractor = Rule34VideoExtractor(http_client=mock_http_client)
    result = await extractor.extract("https://rule34video.com/video/4667334/chika-video/")
    assert result["title"] == "Chika Video"
    assert len(result["formats"]) == 2
    assert [f["format_id"] for f in result["formats"]] == ["720p", "360p"]


# ============================================================================
# 6. QualitySelector Integration Tests
# ============================================================================


def test_quality_selector_rule34video_progressive_candidates() -> None:
    formats = [
        {
            "format_id": "1080p",
            "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
            "ext": "mp4",
            "height": 1080,
            "filesize": 55 * 1024 * 1024,
            "vcodec": "h264",
            "acodec": "aac",
            "protocol": "https",
        },
        {
            "format_id": "720p",
            "url": "https://rule34video.com/get_file/720.mp4/?download=true",
            "ext": "mp4",
            "height": 720,
            "filesize": 30 * 1024 * 1024,
            "vcodec": "h264",
            "acodec": "aac",
            "protocol": "https",
        },
    ]

    qs = QualitySelector()
    qualities = qs.build_qualities(formats, platform="rule34video")
    assert len(qualities) == 2
    assert qualities[0].height == 720
    assert qualities[1].height == 1080
    assert qualities[1].label == "1080p Full HD"


# ============================================================================
# 7. MediaService Integration Tests
# ============================================================================


def test_media_service_extract_rule34video_success() -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        return_value={
            "id": "4667334",
            "title": "Fujiwara Chika Ecchi Past time Animation",
            "description": "Chika s Ecchi Pasttime",
            "duration": 112,
            "thumbnail": "https://rule34video.com/preview.jpg",
            "upload_date": "20261014",
            "view_count": 54230,
            "like_count": 167,
            "uploader": "Shiina Ecchi",
            "extractor": "rule34video",
            "extractor_key": "rule34video",
            "webpage_url": "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/",
            "formats": [
                {
                    "format_id": "1080p",
                    "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
                    "ext": "mp4",
                    "height": 1080,
                    "filesize": 55 * 1024 * 1024,
                    "vcodec": "h264",
                    "acodec": "aac",
                    "protocol": "https",
                }
            ],
        }
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    media_item = service.get_metadata(url)

    assert media_item.platform == "rule34video"
    assert media_item.title == "Fujiwara Chika Ecchi Past time Animation"
    assert media_item.duration_seconds == 112
    assert len(media_item.video_qualities) == 1
    assert media_item.video_qualities[0].height == 1080


def test_media_service_extract_rule34video_not_found() -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        side_effect=Rule34VideoNotFoundError("Rule34Video content was not found (HTTP 404)")
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    with pytest.raises(APIError) as exc_info:
        service.get_metadata(url)
    assert exc_info.value.code == "RULE34VIDEO_MEDIA_NOT_AVAILABLE"
    assert exc_info.value.status_code == 404


def test_media_service_extract_rule34video_unsupported_media() -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        side_effect=Rule34VideoUnsupportedMediaError("No downloadable video formats were found")
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    with pytest.raises(APIError) as exc_info:
        service.get_metadata(url)
    assert exc_info.value.code == "RULE34VIDEO_UNSUPPORTED_MEDIA"
    assert exc_info.value.status_code == 422


def test_media_service_extract_rule34video_server_error() -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        side_effect=Rule34VideoServerError("Rule34Video server returned an error (HTTP 502)")
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    with pytest.raises(APIError) as exc_info:
        service.get_metadata(url)
    assert exc_info.value.code == "RULE34VIDEO_EXTRACTION_UNAVAILABLE"
    assert exc_info.value.status_code == 502


def test_media_service_extract_rule34video_security_error() -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        side_effect=Rule34VideoSecurityError("Untrusted host")
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    with pytest.raises(APIError) as exc_info:
        service.get_metadata(url)
    assert exc_info.value.code == "RULE34VIDEO_SECURITY_ERROR"
    assert exc_info.value.status_code == 422


def test_media_service_validate_invalid_rule34video_url() -> None:
    service = MediaService()
    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://rule34video.com/categories/")
    assert exc_info.value.code == "INVALID_RULE34VIDEO_URL"
    assert exc_info.value.status_code == 422


# ============================================================================
# 8. API Endpoint Tests
# ============================================================================


def test_api_post_media_info_rule34video(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        return_value={
            "id": "4667334",
            "title": "Fujiwara Chika Ecchi Past time Animation",
            "description": "Chika s Ecchi Pasttime",
            "duration": 112,
            "thumbnail": "https://rule34video.com/preview.jpg",
            "upload_date": "20261014",
            "view_count": 54230,
            "like_count": 167,
            "uploader": "Shiina Ecchi",
            "extractor": "rule34video",
            "extractor_key": "rule34video",
            "webpage_url": "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/",
            "formats": [
                {
                    "format_id": "1080p",
                    "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
                    "ext": "mp4",
                    "height": 1080,
                    "filesize": 55 * 1024 * 1024,
                    "vcodec": "h264",
                    "acodec": "aac",
                    "protocol": "https",
                }
            ],
        }
    )

    custom_service = MediaService(rule34video_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: custom_service

    try:
        response = client.post(
            "/media/info",
            json={"url": "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"},
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["platform"] == "rule34video"
        assert data["title"] == "Fujiwara Chika Ecchi Past time Animation"
        assert data["duration_seconds"] == 112
        assert len(data["video_qualities"]) == 1
        assert data["video_qualities"][0]["height"] == 1080
    finally:
        app.dependency_overrides.pop(get_media_service, None)


def test_api_post_media_download_rule34video(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=Rule34VideoExtractor)
    mock_extractor.extract = AsyncMock(
        return_value={
            "id": "4667334",
            "title": "Fujiwara Chika Ecchi Past time Animation",
            "description": "Chika s Ecchi Pasttime",
            "duration": 112,
            "thumbnail": "https://rule34video.com/preview.jpg",
            "upload_date": "20261014",
            "view_count": 54230,
            "like_count": 167,
            "uploader": "Shiina Ecchi",
            "extractor": "rule34video",
            "extractor_key": "rule34video",
            "webpage_url": "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/",
            "formats": [
                {
                    "format_id": "1080p",
                    "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
                    "ext": "mp4",
                    "height": 1080,
                    "filesize": 55 * 1024 * 1024,
                    "vcodec": "h264",
                    "acodec": "aac",
                    "protocol": "https",
                }
            ],
        }
    )

    custom_service = MediaService(rule34video_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: custom_service

    try:
        with patch.object(custom_service, "_start_download_worker") as mock_worker:
            response = client.post(
                "/media/download",
                json={
                    "url": "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/",
                    "media_type": "video",
                    "quality_height": 1080,
                },
            )
            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert "job_id" in data["data"]
            mock_worker.assert_called_once()
    finally:
        app.dependency_overrides.pop(get_media_service, None)


def test_media_service_build_download_options_rule34video_headers() -> None:
    service = MediaService()
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"
    headers = {"User-Agent": RULE34VIDEO_USER_AGENT, "Referer": RULE34VIDEO_REFERER}
    options = service._build_download_options(
        job_id=uuid4(),
        format_selector="1080p",
        output_type="video",
        output_template="test.%(ext)s",
        temp_dir=Path("/tmp"),
        job_manager=MagicMock(),
        resume_state_manager=MagicMock(),
        continue_download=False,
        http_headers=headers,
    )
    assert options["http_headers"]["User-Agent"] == RULE34VIDEO_USER_AGENT
    assert options["http_headers"]["Referer"] == RULE34VIDEO_REFERER


def test_media_service_map_yt_dlp_error_rule34video() -> None:
    service = MediaService()
    url = "https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/"

    err_no_format = DownloadError("ERROR: [Rule34Video] 4667334: No video formats found!")
    api_err = service._map_yt_dlp_error(err_no_format, url=url)
    assert api_err.code == "RULE34VIDEO_UNSUPPORTED_MEDIA"
    assert api_err.status_code == 422

    err_not_found = DownloadError("HTTP Error 404: Not Found")
    api_err404 = service._map_yt_dlp_error(err_not_found, url=url)
    assert api_err404.code == "RULE34VIDEO_MEDIA_NOT_AVAILABLE"
    assert api_err404.status_code == 404

    err_net = DownloadError("Unable to download webpage: <urlopen error timed out>")
    api_err_net = service._map_yt_dlp_error(err_net, url=url)
    assert api_err_net.code in ("RULE34VIDEO_EXTRACTION_UNAVAILABLE", "NETWORK_FAILURE")
    assert api_err_net.status_code == 502


# ============================================================================
# 9. Pipeline Hardening Tests (CDN Redirects, Connection Validation, Filesize)
# ============================================================================


@pytest.mark.anyio
async def test_resolve_media_url_valid_cdn_redirect() -> None:
    # 1. 302 from rule34video.com to boomio-cdn.com
    redirect_resp = MagicMock(spec=httpx.Response)
    redirect_resp.status_code = 302
    cdn_target = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=vid1080.mp4"
    redirect_resp.headers = {"Location": cdn_target}
    redirect_resp.url = httpx.URL("https://rule34video.com/get_file/1080.mp4/?download=true")

    # 2. 200 from boomio-cdn.com with exact Content-Length
    cdn_resp = MagicMock(spec=httpx.Response)
    cdn_resp.status_code = 200
    cdn_resp.headers = {"content-length": "57218883", "content-type": "video/mp4"}
    cdn_resp.url = httpx.URL(cdn_target)

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(side_effect=[redirect_resp, cdn_resp])
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    final_url, exact_size = await client.resolve_media_url(
        "https://rule34video.com/get_file/1080.mp4/?download=true"
    )

    assert final_url == cdn_target
    assert exact_size == 57218883
    assert mock_client.head.call_count == 2


@pytest.mark.anyio
async def test_resolve_media_url_unapproved_destination_blocked() -> None:
    redirect_resp = MagicMock(spec=httpx.Response)
    redirect_resp.status_code = 302
    redirect_resp.headers = {"Location": "https://unauthorized-attacker.com/payload.mp4"}
    redirect_resp.url = httpx.URL("https://rule34video.com/get_file/1080.mp4/?download=true")

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=redirect_resp)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
        await client.resolve_media_url("https://rule34video.com/get_file/1080.mp4/?download=true")


@pytest.mark.anyio
async def test_resolve_media_url_http_downgrade_blocked() -> None:
    redirect_resp = MagicMock(spec=httpx.Response)
    redirect_resp.status_code = 302
    redirect_resp.headers = {"Location": "http://eu-cdn10-prem.boomio-cdn.com/insecure.mp4"}
    redirect_resp.url = httpx.URL("https://rule34video.com/get_file/1080.mp4/?download=true")

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=redirect_resp)
    mock_client.is_closed = False

    # Do not allow http for this test to enforce https-only
    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=False)
    with pytest.raises(Rule34VideoSecurityError, match="Insecure or unsupported URL scheme"):
        await client.resolve_media_url("https://rule34video.com/get_file/1080.mp4/?download=true")


@pytest.mark.anyio
async def test_resolve_media_url_exceeds_max_hops_blocked() -> None:
    loop_resp = MagicMock(spec=httpx.Response)
    loop_resp.status_code = 302
    loop_resp.headers = {"Location": "https://rule34video.com/get_file/loop.mp4"}
    loop_resp.url = httpx.URL("https://rule34video.com/get_file/loop.mp4")

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=loop_resp)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoNetworkError, match="Exceeded maximum redirect hops"):
        await client.resolve_media_url(
            "https://rule34video.com/get_file/loop.mp4", max_redirects=5
        )


@pytest.mark.anyio
async def test_resolve_media_url_private_ip_destination_blocked() -> None:
    redirect_resp = MagicMock(spec=httpx.Response)
    redirect_resp.status_code = 302
    redirect_resp.headers = {"Location": "https://127.0.0.1/local-file.mp4"}
    redirect_resp.url = httpx.URL("https://rule34video.com/get_file/1080.mp4/?download=true")

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=redirect_resp)
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    with pytest.raises(Rule34VideoSecurityError, match="forbidden|not permitted"):
        await client.resolve_media_url("https://rule34video.com/get_file/1080.mp4/?download=true")


def test_is_safe_ip_ipv4_and_ipv6_variants() -> None:
    # IPv4 loopback, private, link-local, broadcast
    assert not is_safe_ip("127.0.0.1")
    assert not is_safe_ip("10.0.0.1")
    assert not is_safe_ip("192.168.1.1")
    assert not is_safe_ip("172.16.0.1")
    assert not is_safe_ip("169.254.169.254")
    assert not is_safe_ip("0.0.0.0")
    assert not is_safe_ip("255.255.255.255")

    # IPv6 loopback, link-local, multicast, unspecified
    assert not is_safe_ip("::1")
    assert not is_safe_ip("fe80::1")
    assert not is_safe_ip("ff02::1")
    assert not is_safe_ip("::")

    # IPv4-mapped IPv6 addresses evaluated consistently
    assert not is_safe_ip("::ffff:127.0.0.1")
    assert not is_safe_ip("::ffff:169.254.169.254")
    assert not is_safe_ip("::ffff:192.168.1.1")
    assert is_safe_ip("::ffff:8.8.8.8")

    # Valid public IPv4 and IPv6
    assert is_safe_ip("8.8.8.8")
    assert is_safe_ip("1.1.1.1")
    assert is_safe_ip("2606:4700:4700::1111")


def test_header_handling_across_different_origins() -> None:
    handler = SafeRule34VideoRedirectHandler(max_hops=5)
    mock_req = MagicMock()
    mock_req.full_url = "https://rule34video.com/get_file/1080.mp4"
    mock_req.headers = {
        "User-Agent": RULE34VIDEO_USER_AGENT,
        "Referer": RULE34VIDEO_REFERER,
        "Authorization": "Bearer secret-token",
        "Cookie": "session=sensitive_cookie_value",
    }
    mock_req.get_method = MagicMock(return_value="GET")
    mock_req.origin_req_host = "rule34video.com"
    mock_req.data = None

    new_url = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=test.mp4"
    redirected = handler.redirect_request(mock_req, None, 302, "Found", {}, new_url)

    # Sensitive headers stripped across origins
    assert "Authorization" not in redirected.headers
    assert "Cookie" not in redirected.headers

    # Upstream required headers preserved
    header_lower = {k.casefold(): v for k, v in redirected.headers.items()}
    assert header_lower.get("user-agent") == RULE34VIDEO_USER_AGENT
    assert header_lower.get("referer") == RULE34VIDEO_REFERER


@pytest.mark.anyio
async def test_resolve_media_format_approx_and_exact_filesize() -> None:
    format_item = {
        "format_id": "1080p",
        "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
        "ext": "mp4",
        "height": 1080,
        "filesize": None,
        "filesize_approx": 57671680,
    }

    mock_http_client = AsyncMock(spec=HttpRule34VideoClient)
    cdn_final = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=test.mp4"
    mock_http_client.resolve_media_url = AsyncMock(return_value=(cdn_final, 57218883))

    extractor = Rule34VideoExtractor(http_client=mock_http_client)
    resolved = await extractor.resolve_media_format(format_item)

    assert resolved["url"] == cdn_final
    assert resolved["filesize"] == 57218883
    assert resolved["filesize_approx"] == 57671680


def test_download_worker_uses_validated_final_url() -> None:
    cdn_final = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=1080.mp4"
    mock_extractor = MagicMock(spec=Rule34VideoExtractor)
    mock_extractor.resolve_media_formats_for_selector = AsyncMock(
        return_value={
            "id": "4667334",
            "formats": [
                {
                    "format_id": "1080p",
                    "url": cdn_final,
                    "ext": "mp4",
                    "height": 1080,
                    "filesize": 57218883,
                    "filesize_approx": 57671680,
                }
            ],
        }
    )

    service = MediaService(rule34video_extractor=mock_extractor)
    mock_ydl = MagicMock()
    mock_ydl.process_ie_result = MagicMock(return_value={"id": "4667334", "title": "Test"})

    raw_download_info = {
        "id": "4667334",
        "formats": [
            {
                "format_id": "1080p",
                "url": "https://rule34video.com/get_file/1080.mp4/?download=true",
                "ext": "mp4",
                "height": 1080,
                "filesize": None,
                "filesize_approx": 57671680,
            }
        ],
    }

    service._process_download_with_youtube_dl(
        mock_ydl,
        job_id=uuid4(),
        url="https://rule34video.com/video/4667334/slug/",
        output_type="video",
        format_selector="1080p",
        download_info=raw_download_info,
        detected_platform="rule34video",
    )

    # Verify that process_ie_result received the pre-resolved validated CDN URL
    mock_ydl.process_ie_result.assert_called_once()
    passed_info = mock_ydl.process_ie_result.call_args[0][0]
    format_used = passed_info["formats"][0]
    assert format_used["url"] == cdn_final
    assert format_used["filesize"] == 57218883


def test_configure_rule34video_network_guards_blocks_runtime_untrusted_redirect() -> None:
    mock_ydl = MagicMock()
    mock_urllib_rh = MagicMock()
    mock_urllib_rh.handlers = []

    # Simulate opener creation with default RedirectHandler
    from yt_dlp.networking._urllib import RedirectHandler
    mock_opener = MagicMock()
    mock_opener.handlers = [RedirectHandler()]
    mock_urllib_rh._create_instance = MagicMock(return_value=mock_opener)

    mock_rd = MagicMock()
    mock_rd.handlers = {"Urllib": mock_urllib_rh}
    mock_ydl._request_director = mock_rd
    mock_ydl.urlopen = MagicMock()

    configure_rule34video_network_guards(mock_ydl)

    # Verify custom create instance was installed
    assert mock_urllib_rh._create_instance != mock_opener
    new_opener = mock_urllib_rh._create_instance()
    custom_handler = next(
        (h for h in new_opener.handlers if isinstance(h, SafeRule34VideoRedirectHandler)),
        None,
    )
    assert custom_handler is not None

    # Verify handler blocks untrusted redirect
    with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
        custom_handler.redirect_request(
            None, None, 302, "Found", {}, "https://malicious.org/stream.mp4"
        )


# ============================================================================
# 8. Hardening Verification Tests (Socket peer, fallback guards, live execution)
# ============================================================================


@pytest.mark.anyio
async def test_safe_network_backend_socket_inspection_fail_safe() -> None:
    """Verify that socket inspection failures fail safely by raising Rule34VideoSecurityError."""
    from app.platforms.rule34video.http_client import SafeNetworkBackend

    backend = SafeNetworkBackend(allow_http_for_tests=False)

    mock_stream = AsyncMock()
    mock_stream.get_extra_info = MagicMock(return_value=None)
    mock_stream._stream = MagicMock()
    mock_stream._stream._raw_socket = None
    mock_stream.aclose = AsyncMock()

    with patch("httpcore._backends.anyio.AnyIOBackend.connect_tcp", return_value=mock_stream):
        with pytest.raises(Rule34VideoSecurityError, match="forbidden or unverified peer IP"):
            await backend.connect_tcp("rule34video.com", 443)
        mock_stream.aclose.assert_awaited_once()


@pytest.mark.anyio
async def test_safe_network_backend_blocks_private_and_loopback_sockets() -> None:
    """Verify that private and loopback socket connections close the stream and raise security error."""
    from app.platforms.rule34video.http_client import SafeNetworkBackend

    backend = SafeNetworkBackend(allow_http_for_tests=False)

    for forbidden_ip in ("127.0.0.1", "::1", "10.0.0.1", "192.168.1.5", "::ffff:127.0.0.1"):
        mock_stream = AsyncMock()
        mock_stream.get_extra_info = MagicMock(return_value=(forbidden_ip, 443))
        mock_stream.aclose = AsyncMock()

        with patch("httpcore._backends.anyio.AnyIOBackend.connect_tcp", return_value=mock_stream):
            with pytest.raises(Rule34VideoSecurityError, match="forbidden or unverified peer IP"):
                await backend.connect_tcp("rule34video.com", 443)
            mock_stream.aclose.assert_awaited_once()


@pytest.mark.anyio
async def test_safe_network_backend_allows_public_ip_socket() -> None:
    """Verify that connections to public IPs are permitted."""
    from app.platforms.rule34video.http_client import SafeNetworkBackend

    backend = SafeNetworkBackend(allow_http_for_tests=False)

    mock_stream = AsyncMock()
    mock_stream.get_extra_info = MagicMock(return_value=("104.26.12.146", 443))
    mock_stream.aclose = AsyncMock()

    with patch("httpcore._backends.anyio.AnyIOBackend.connect_tcp", return_value=mock_stream):
        result = await backend.connect_tcp("rule34video.com", 443)
        assert result is mock_stream
        mock_stream.aclose.assert_not_called()


@pytest.mark.anyio
async def test_resolve_media_url_streaming_range_fallback_on_405() -> None:
    """Verify fallback to streaming Range request when HEAD returns 405 Method Not Allowed."""
    cdn_url = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=1080.mp4"

    mock_head_resp = MagicMock(spec=httpx.Response)
    mock_head_resp.status_code = 405
    mock_head_resp.headers = {}
    mock_head_resp.url = httpx.URL(cdn_url)

    mock_stream_resp = MagicMock()
    mock_stream_resp.status_code = 206
    mock_stream_resp.headers = {
        "content-range": "bytes 0-0/57218883",
        "content-length": "1",
    }
    mock_stream_resp.url = httpx.URL(cdn_url)

    class MockStreamContext:
        async def __aenter__(self) -> Any:
            return mock_stream_resp

        async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
            pass

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=mock_head_resp)
    mock_client.stream = MagicMock(return_value=MockStreamContext())
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    final_url, exact_size = await client.resolve_media_url(cdn_url)

    assert final_url == cdn_url
    assert exact_size == 57218883
    mock_client.stream.assert_called_once_with("GET", cdn_url, headers=ANY)


@pytest.mark.anyio
async def test_resolve_media_url_streaming_range_fallback_when_head_lacks_content_length() -> None:
    """Verify fallback to streaming Range request when HEAD returns 200 without Content-Length."""
    cdn_url = "https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?file=1080.mp4"

    mock_head_resp = MagicMock(spec=httpx.Response)
    mock_head_resp.status_code = 200
    mock_head_resp.headers = {}  # No content-length
    mock_head_resp.url = httpx.URL(cdn_url)

    mock_stream_resp = MagicMock()
    mock_stream_resp.status_code = 206
    mock_stream_resp.headers = {
        "content-range": "bytes 0-0/12345678",
        "content-length": "1",
    }
    mock_stream_resp.url = httpx.URL(cdn_url)

    class MockStreamContext:
        async def __aenter__(self) -> Any:
            return mock_stream_resp

        async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
            pass

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.head = AsyncMock(return_value=mock_head_resp)
    mock_client.stream = MagicMock(return_value=MockStreamContext())
    mock_client.is_closed = False

    client = HttpRule34VideoClient(client=mock_client, allow_http_for_tests=True)
    final_url, exact_size = await client.resolve_media_url(cdn_url)

    assert final_url == cdn_url
    assert exact_size == 12345678
    mock_client.stream.assert_called_once_with("GET", cdn_url, headers=ANY)


def test_ytdlp_runtime_execution_blocks_malicious_redirect_with_local_fixture() -> None:
    """Test actual socket execution through yt-dlp urllib opener with local fixture."""
    import http.server
    import threading
    import urllib.request
    from yt_dlp import YoutubeDL

    class RedirectTestHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(302)
            self.send_header("Location", "https://unauthorized-destination.com/malicious.mp4")
            self.end_headers()

        def log_message(self, format: str, *args: Any) -> None:
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), RedirectTestHandler)
    port = server.server_port
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        ydl = YoutubeDL({"quiet": True})
        configure_rule34video_network_guards(ydl)

        urllib_rh = ydl._request_director.handlers["Urllib"]
        opener = urllib_rh._create_instance({}, None)

        req = urllib.request.Request(f"http://127.0.0.1:{port}/start")
        with pytest.raises(Rule34VideoSecurityError, match="Untrusted host"):
            opener.open(req)
    finally:
        server.shutdown()
        server.server_close()


def test_fallback_youtube_dl_receives_network_guards() -> None:
    """Verify that both primary youtube_dl and fallback_youtube_dl receive network guards."""
    import inspect
    from app.services.media_service import MediaService

    source = inspect.getsource(MediaService._download_job_background)
    # Check primary instance
    assert "configure_rule34video_network_guards(youtube_dl)" in source
    # Check fallback instance
    assert "configure_rule34video_network_guards(fallback_youtube_dl)" in source
