from __future__ import annotations

import json
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes.media import get_media_service
from app.core.config import get_settings
from app.core.exceptions import APIError
from app.main import app
from app.models.requests import MediaDownloadRequest, MediaInfoRequest
from app.platforms.danbooru import (
    ALLOWED_MEDIA_HOSTS,
    DANBOORU_CDN_HOST,
    DANBOORU_HOST,
    DANBOORU_USER_AGENT,
    DanbooruAccessDeniedError,
    DanbooruExtractor,
    DanbooruMalformedResponseError,
    DanbooruNetworkError,
    DanbooruPostNotFoundError,
    DanbooruRateLimitedError,
    DanbooruSecurityError,
    DanbooruServerError,
    DanbooruTimeoutError,
    DanbooruTlsError,
    DanbooruUnsupportedMediaError,
    DanbooruUrlError,
    HttpDanbooruClient,
    extract_danbooru_post_id,
    is_danbooru_targeted_host,
    is_danbooru_targeted_url,
)
from app.services.media_service import MediaService
from app.services.quality_selector import QualitySelector
from app.utils.platforms import (
    detect_platform_from_url,
    is_danbooru_media_url,
    normalize_media_url,
)


@pytest.fixture(autouse=True)
def clear_caches() -> None:
    get_settings.cache_clear()
    get_media_service.cache_clear()
    yield
    get_settings.cache_clear()
    get_media_service.cache_clear()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


_SAMPLE_DANBOORU_PAYLOAD = {
    "id": 11766677,
    "created_at": "2026-07-10T15:32:39.456-04:00",
    "uploader_id": 480071,
    "score": 27,
    "source": "https://x.com/ProvocativePix/status/2075656302144225764",
    "md5": "cf93f726b0ef6b3f91c147fb80a3eaff",
    "rating": "e",
    "image_width": 1440,
    "image_height": 1080,
    "tag_string": "leon_s._kennedy jill_valentine ada_wong claire_redfield animated video",
    "fav_count": 26,
    "file_ext": "mp4",
    "file_size": 33606189,
    "is_pending": False,
    "is_flagged": False,
    "is_deleted": False,
    "is_banned": False,
    "tag_string_artist": "provocativepix",
    "tag_string_character": "ada_wong claire_redfield jill_valentine leon_s._kennedy",
    "tag_string_meta": "animated commentary sound video",
    "file_url": "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4",
    "large_file_url": "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4",
    "preview_file_url": "https://cdn.donmai.us/180x180/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.jpg",
    "media_asset": {
        "id": 49142401,
        "duration": 49.173333,
        "image_width": 1440,
        "image_height": 1080,
        "file_size": 33606189,
        "file_ext": "mp4",
        "variants": [
            {
                "type": "180x180",
                "url": "https://cdn.donmai.us/180x180/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.jpg",
                "width": 180,
                "height": 135,
                "file_ext": "jpg",
            },
            {
                "type": "original",
                "url": "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4",
                "width": 1440,
                "height": 1080,
                "file_ext": "mp4",
            },
        ],
    },
}


# ==============================================================================
# 1. URL RECOGNITION AND NORMALIZATION TESTS
# ==============================================================================


@pytest.mark.parametrize(
    "url, expected_valid, expected_post_id",
    [
        ("https://danbooru.donmai.us/posts/11766677", True, 11766677),
        ("https://danbooru.donmai.us/posts/11766677/", True, 11766677),
        ("https://danbooru.donmai.us/posts/11766677?q=tag+video", True, 11766677),
        ("http://danbooru.donmai.us/posts/11766677", True, 11766677),
        ("https://danbooru.donmai.us/posts/0", False, None),
        ("https://danbooru.donmai.us/posts/notanumber", False, None),
        ("https://danbooru.donmai.us/posts/", False, None),
        ("https://danbooru.donmai.us/posts", False, None),
        ("https://danbooru.donmai.us/artists/123", False, None),
        ("https://danbooru.donmai.us/explore/posts", False, None),
        # Deceptive domains
        ("https://evil-danbooru.donmai.us.attacker.com/posts/11766677", False, None),
        ("https://notdanbooru.donmai.us/posts/11766677", False, None),
        ("https://attacker-donmai.us/posts/11766677", False, None),
        ("https://danbooru.donmai.us.scam.org/posts/11766677", False, None),
        ("ftp://danbooru.donmai.us/posts/11766677", False, None),
    ],
)
def test_danbooru_url_validation_and_id_extraction(
    url: str, expected_valid: bool, expected_post_id: int | None
) -> None:
    assert is_danbooru_media_url(url) is expected_valid
    assert extract_danbooru_post_id(url) == expected_post_id
    if expected_valid:
        assert detect_platform_from_url(url) == "danbooru"
    else:
        assert detect_platform_from_url(url) != "danbooru"


def test_danbooru_url_normalization() -> None:
    url = "https://danbooru.donmai.us/posts/11766677/?query=param&utm_source=test"
    normalized = normalize_media_url(url)
    assert normalized == "https://danbooru.donmai.us/posts/11766677"


# ==============================================================================
# 2. TARGETED HEADER TESTS
# ==============================================================================


def test_targeted_headers_scoped_to_approved_origins_only() -> None:
    assert is_danbooru_targeted_host("danbooru.donmai.us") is True
    assert is_danbooru_targeted_host("cdn.donmai.us") is True
    assert is_danbooru_targeted_url("https://danbooru.donmai.us/posts/11766677") is True
    assert is_danbooru_targeted_url("https://cdn.donmai.us/original/test.mp4") is True

    # Unrelated domains must return False
    assert is_danbooru_targeted_host("youtube.com") is False
    assert is_danbooru_targeted_host("tiktok.com") is False
    assert is_danbooru_targeted_host("twitter.com") is False
    assert is_danbooru_targeted_host("x.com") is False
    assert is_danbooru_targeted_host("instagram.com") is False
    assert is_danbooru_targeted_host("facebook.com") is False
    assert is_danbooru_targeted_host("reddit.com") is False
    assert is_danbooru_targeted_host("hanime.tv") is False
    assert is_danbooru_targeted_host("attacker-donmai.us") is False
    assert is_danbooru_targeted_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ") is False


# ==============================================================================
# 3. HTTP CLIENT AND ERROR MAPPING TESTS
# ==============================================================================


@pytest.mark.anyio
async def test_http_client_sets_correct_user_agent_and_accept_header() -> None:
    mock_resp = httpx.Response(
        status_code=200,
        json=_SAMPLE_DANBOORU_PAYLOAD,
        request=httpx.Request("GET", "https://danbooru.donmai.us/posts/11766677.json"),
    )
    mock_async_client = AsyncMock(spec=httpx.AsyncClient)
    mock_async_client.get.return_value = mock_resp
    mock_async_client.is_closed = False

    client = HttpDanbooruClient(client=mock_async_client)
    payload = await client.fetch_post_json(11766677)

    assert payload["id"] == 11766677
    mock_async_client.get.assert_awaited_once_with("https://danbooru.donmai.us/posts/11766677.json")


@pytest.mark.anyio
@pytest.mark.parametrize(
    "status_code, expected_exc",
    [
        (404, DanbooruPostNotFoundError),
        (403, DanbooruAccessDeniedError),
        (429, DanbooruRateLimitedError),
        (500, DanbooruServerError),
        (502, DanbooruServerError),
        (503, DanbooruServerError),
    ],
)
async def test_http_client_maps_http_status_codes(
    status_code: int, expected_exc: type[Exception]
) -> None:
    mock_resp = httpx.Response(
        status_code=status_code,
        request=httpx.Request("GET", "https://danbooru.donmai.us/posts/11766677.json"),
    )
    mock_async_client = AsyncMock(spec=httpx.AsyncClient)
    mock_async_client.get.return_value = mock_resp
    mock_async_client.is_closed = False

    client = HttpDanbooruClient(client=mock_async_client)
    with pytest.raises(expected_exc):
        await client.fetch_post_json(11766677)


@pytest.mark.anyio
async def test_http_client_maps_network_and_timeout_errors() -> None:
    mock_async_client = AsyncMock(spec=httpx.AsyncClient)
    mock_async_client.is_closed = False

    # Timeout
    mock_async_client.get.side_effect = httpx.ReadTimeout("Read timed out")
    client = HttpDanbooruClient(client=mock_async_client)
    with pytest.raises(DanbooruTimeoutError):
        await client.fetch_post_json(11766677)

    # Connect error
    mock_async_client.get.side_effect = httpx.ConnectError("Connection refused")
    with pytest.raises(DanbooruNetworkError):
        await client.fetch_post_json(11766677)

    # SSL / TLS error
    mock_async_client.get.side_effect = httpx.ConnectError("certificate verify failed")
    with pytest.raises(DanbooruTlsError):
        await client.fetch_post_json(11766677)


@pytest.mark.anyio
async def test_http_client_maps_malformed_json() -> None:
    mock_resp = httpx.Response(
        status_code=200,
        content=b"<!DOCTYPE html><html>Not JSON</html>",
        headers={"content-type": "text/html"},
        request=httpx.Request("GET", "https://danbooru.donmai.us/posts/11766677.json"),
    )
    mock_async_client = AsyncMock(spec=httpx.AsyncClient)
    mock_async_client.get.return_value = mock_resp
    mock_async_client.is_closed = False

    client = HttpDanbooruClient(client=mock_async_client)
    with pytest.raises(DanbooruMalformedResponseError):
        await client.fetch_post_json(11766677)


# ==============================================================================
# 4. ADAPTER EXTRACTION TESTS
# ==============================================================================


@pytest.mark.anyio
async def test_adapter_extracts_structured_metadata_successfully() -> None:
    mock_http_client = AsyncMock(spec=HttpDanbooruClient)
    mock_http_client.fetch_post_json.return_value = _SAMPLE_DANBOORU_PAYLOAD

    extractor = DanbooruExtractor(http_client=mock_http_client)
    info = await extractor.extract("https://danbooru.donmai.us/posts/11766677")

    assert info["id"] == "11766677"
    assert info["title"] == "Danbooru Post 11766677 (provocativepix)"
    assert info["uploader"] == "provocativepix"
    assert info["webpage_url"] == "https://danbooru.donmai.us/posts/11766677"
    assert info["extractor"] == "danbooru"
    assert info["extractor_key"] == "Danbooru"
    assert info["duration"] == 49
    assert info["upload_date"] == "20260710"
    assert info["thumbnail"] == "https://cdn.donmai.us/180x180/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.jpg"
    assert info["http_headers"]["User-Agent"] == DANBOORU_USER_AGENT

    formats = info["formats"]
    assert len(formats) == 1
    fmt = formats[0]
    assert fmt["format_id"] == "danbooru-11766677-video"
    assert fmt["url"] == "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4"
    assert fmt["ext"] == "mp4"
    assert fmt["width"] == 1440
    assert fmt["height"] == 1080
    assert fmt["filesize"] == 33606189
    assert fmt["vcodec"] == "h264"
    assert fmt["acodec"] == "aac"
    assert fmt["http_headers"]["User-Agent"] == DANBOORU_USER_AGENT


@pytest.mark.anyio
async def test_adapter_fallback_to_large_file_url() -> None:
    payload = dict(_SAMPLE_DANBOORU_PAYLOAD)
    payload["file_url"] = None
    payload["large_file_url"] = "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4"

    mock_http_client = AsyncMock(spec=HttpDanbooruClient)
    mock_http_client.fetch_post_json.return_value = payload

    extractor = DanbooruExtractor(http_client=mock_http_client)
    info = await extractor.extract("https://danbooru.donmai.us/posts/11766677")
    assert info["formats"][0]["url"] == payload["large_file_url"]


@pytest.mark.anyio
async def test_adapter_rejects_ssrf_and_untrusted_media_hosts() -> None:
    mock_http_client = AsyncMock(spec=HttpDanbooruClient)

    # Untrusted domain
    evil_payload = dict(_SAMPLE_DANBOORU_PAYLOAD)
    evil_payload["file_url"] = "https://attacker.com/malicious.mp4"
    mock_http_client.fetch_post_json.return_value = evil_payload

    extractor = DanbooruExtractor(http_client=mock_http_client)
    with pytest.raises(DanbooruSecurityError, match="Untrusted media host"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")

    # Localhost SSRF
    evil_payload["file_url"] = "http://127.0.0.1:8080/secret.mp4"
    with pytest.raises(DanbooruSecurityError, match="Untrusted media host"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")

    # Unsupported scheme
    evil_payload["file_url"] = "file:///etc/passwd"
    with pytest.raises(DanbooruSecurityError, match="Unsupported media URL scheme"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")


@pytest.mark.anyio
async def test_adapter_rejects_static_image_posts() -> None:
    image_payload = dict(_SAMPLE_DANBOORU_PAYLOAD)
    image_payload["file_ext"] = "png"
    image_payload["tag_string"] = "solo 1girl highres"
    image_payload["tag_string_meta"] = "highres"
    image_payload["media_asset"] = {"file_ext": "png", "duration": None}

    mock_http_client = AsyncMock(spec=HttpDanbooruClient)
    mock_http_client.fetch_post_json.return_value = image_payload

    extractor = DanbooruExtractor(http_client=mock_http_client)
    with pytest.raises(DanbooruUnsupportedMediaError, match="not a supported video format"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")


@pytest.mark.anyio
async def test_adapter_rejects_deleted_and_banned_posts() -> None:
    mock_http_client = AsyncMock(spec=HttpDanbooruClient)
    deleted_payload = dict(_SAMPLE_DANBOORU_PAYLOAD)
    deleted_payload["is_deleted"] = True
    mock_http_client.fetch_post_json.return_value = deleted_payload

    extractor = DanbooruExtractor(http_client=mock_http_client)
    with pytest.raises(DanbooruPostNotFoundError, match="deleted"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")

    banned_payload = dict(_SAMPLE_DANBOORU_PAYLOAD)
    banned_payload["is_banned"] = True
    mock_http_client.fetch_post_json.return_value = banned_payload
    with pytest.raises(DanbooruPostNotFoundError, match="unavailable"):
        await extractor.extract("https://danbooru.donmai.us/posts/11766677")


# ==============================================================================
# 5. QUALITY SELECTOR COMPATIBILITY TESTS
# ==============================================================================


def test_quality_selector_selects_danbooru_progressive_mp4() -> None:
    selector = QualitySelector()
    danbooru_formats = [
        {
            "format_id": "danbooru-11766677-video",
            "url": "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4",
            "ext": "mp4",
            "width": 1440,
            "height": 1080,
            "filesize": 33606189,
            "vcodec": "h264",
            "acodec": "aac",
            "http_headers": {"User-Agent": DANBOORU_USER_AGENT},
        }
    ]

    qualities = selector.build_qualities(danbooru_formats, platform="danbooru")
    assert len(qualities) == 1
    assert qualities[0].height == 1080
    assert qualities[0].label == "1080p Full HD"
    assert qualities[0].extension == "mp4"
    assert qualities[0].estimated_filesize == 33606189

    selection = selector.select_for_height(danbooru_formats, 1080, platform="danbooru")
    assert selection is not None
    assert selection.selector == "danbooru-11766677-video"
    assert selection.audio_format_id is None
    assert selector.has_audio_available(danbooru_formats, platform="danbooru") is True


def test_quality_selector_preserves_resolution_without_inventing_heights() -> None:
    selector = QualitySelector()
    no_height_format = [
        {
            "format_id": "danbooru-11766677-video",
            "url": "https://cdn.donmai.us/original/cf/93/cf93f726b0ef6b3f91c147fb80a3eaff.mp4",
            "ext": "mp4",
            "width": None,
            "height": None,
            "vcodec": "h264",
            "acodec": "aac",
        }
    ]
    qualities = selector.build_qualities(no_height_format, platform="danbooru")
    assert qualities == []


# ==============================================================================
# 6. API ENDPOINT AND LIFECYCLE INTEGRATION TESTS
# ==============================================================================


def test_media_info_endpoint_returns_danbooru_metadata(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=DanbooruExtractor)
    mock_extractor.extract.return_value = {
        "id": "11766677",
        "title": "Danbooru Post 11766677 (provocativepix)",
        "description": "tag list",
        "thumbnail": "https://cdn.donmai.us/180x180/sample.jpg",
        "duration": 49,
        "upload_date": "20260710",
        "uploader": "provocativepix",
        "webpage_url": "https://danbooru.donmai.us/posts/11766677",
        "extractor": "danbooru",
        "extractor_key": "Danbooru",
        "formats": [
            {
                "format_id": "danbooru-11766677-video",
                "url": "https://cdn.donmai.us/original/sample.mp4",
                "ext": "mp4",
                "width": 1440,
                "height": 1080,
                "filesize": 33606189,
                "vcodec": "h264",
                "acodec": "aac",
                "http_headers": {"User-Agent": DANBOORU_USER_AGENT},
            }
        ],
        "http_headers": {"User-Agent": DANBOORU_USER_AGENT},
    }

    service = MediaService(danbooru_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = client.post(
            "/media/info",
            json={"url": "https://danbooru.donmai.us/posts/11766677"},
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["platform"] == "danbooru"
        assert data["title"] == "Danbooru Post 11766677 (provocativepix)"
        assert data["uploader"] == "provocativepix"
        assert data["duration_seconds"] == 49
        assert len(data["video_qualities"]) == 1
        assert data["video_qualities"][0]["height"] == 1080
        assert len(data["audio_options"]) == 1
        assert data["audio_options"][0]["extension"] == "mp3"
    finally:
        app.dependency_overrides.clear()


def test_media_download_job_creation_and_targeted_header_propagation(
    client: TestClient,
) -> None:
    mock_extractor = AsyncMock(spec=DanbooruExtractor)
    extracted_info = {
        "id": "11766677",
        "title": "Danbooru Post 11766677 (provocativepix)",
        "description": "tag list",
        "thumbnail": "https://cdn.donmai.us/180x180/sample.jpg",
        "duration": 49,
        "upload_date": "20260710",
        "uploader": "provocativepix",
        "webpage_url": "https://danbooru.donmai.us/posts/11766677",
        "extractor": "danbooru",
        "extractor_key": "Danbooru",
        "formats": [
            {
                "format_id": "danbooru-11766677-video",
                "url": "https://cdn.donmai.us/original/sample.mp4",
                "ext": "mp4",
                "width": 1440,
                "height": 1080,
                "filesize": 33606189,
                "vcodec": "h264",
                "acodec": "aac",
                "http_headers": {"User-Agent": DANBOORU_USER_AGENT},
            }
        ],
        "http_headers": {"User-Agent": DANBOORU_USER_AGENT},
    }
    mock_extractor.extract.return_value = extracted_info

    service = MediaService(danbooru_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: service

    with patch.object(service, "_start_download_worker") as mock_start_worker:
        try:
            response = client.post(
                "/media/download",
                json={
                    "url": "https://danbooru.donmai.us/posts/11766677",
                    "media_type": "video",
                    "quality_height": 1080,
                },
            )
            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert "job_id" in data["data"]

            # Verify that download worker received the extracted info with targeted headers
            mock_start_worker.assert_called_once()
            call_kwargs = mock_start_worker.call_args[1]
            assert call_kwargs["format_selector"] == "danbooru-11766677-video"
            assert call_kwargs["download_info"]["http_headers"]["User-Agent"] == DANBOORU_USER_AGENT

            from pathlib import Path
            download_options = service._build_download_options(
                job_id=uuid4(),
                format_selector="danbooru-11766677-video",
                output_type="video",
                output_template="test.%(ext)s",
                temp_dir=Path("/tmp"),
                job_manager=MagicMock(),
                resume_state_manager=MagicMock(),
                continue_download=False,
                http_headers=call_kwargs["download_info"]["http_headers"],
            )
            assert download_options["http_headers"]["User-Agent"] == DANBOORU_USER_AGENT
            assert "impersonate" not in download_options
        finally:
            app.dependency_overrides.clear()


def test_media_info_error_mapping_on_post_not_found(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=DanbooruExtractor)
    mock_extractor.extract.side_effect = DanbooruPostNotFoundError("Post not found")

    service = MediaService(danbooru_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = client.post(
            "/media/info",
            json={"url": "https://danbooru.donmai.us/posts/999999999"},
        )
        assert response.status_code == 404
        body = response.json()
        assert body["error"]["code"] == "DANBOORU_POST_NOT_FOUND"
    finally:
        app.dependency_overrides.clear()


def test_media_info_error_mapping_on_access_denied(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=DanbooruExtractor)
    mock_extractor.extract.side_effect = DanbooruAccessDeniedError("Access denied")

    service = MediaService(danbooru_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = client.post(
            "/media/info",
            json={"url": "https://danbooru.donmai.us/posts/11766677"},
        )
        assert response.status_code == 403
        body = response.json()
        assert body["error"]["code"] == "DANBOORU_ACCESS_DENIED"
    finally:
        app.dependency_overrides.clear()


def test_media_info_error_mapping_on_rate_limit(client: TestClient) -> None:
    mock_extractor = AsyncMock(spec=DanbooruExtractor)
    mock_extractor.extract.side_effect = DanbooruRateLimitedError("Rate limit")

    service = MediaService(danbooru_extractor=mock_extractor)
    app.dependency_overrides[get_media_service] = lambda: service

    try:
        response = client.post(
            "/media/info",
            json={"url": "https://danbooru.donmai.us/posts/11766677"},
        )
        assert response.status_code == 429
        body = response.json()
        assert body["error"]["code"] == "DANBOORU_RATE_LIMITED"
    finally:
        app.dependency_overrides.clear()
