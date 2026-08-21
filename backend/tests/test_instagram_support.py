from __future__ import annotations

import logging
from http.cookiejar import MozillaCookieJar
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from yt_dlp.utils import DownloadError, ExtractorError

from app.api.routes.media import get_media_service
from app.core.config import Settings, get_settings
from app.core.exceptions import APIError
from app.main import app
from app.models.media import AudioOption, MediaMetadata, PlaylistItem, PlaylistMetadata
from app.models.requests import MediaDownloadRequest
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.media_snapshot_cache import MediaSnapshotCache
from app.services.download_process_manager import DownloadProcessManager
from app.services.quality_selector import QualitySelector
from app.utils.platforms import (
    detect_platform_from_url,
    is_instagram_media_url,
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
def client() -> TestClient:
    return TestClient(app)


# ==============================================================================
# 1. URL DETECTION AND NORMALIZATION TESTS
# ==============================================================================


@pytest.mark.parametrize(
    "url, expected_normalized",
    [
        (
            "https://www.instagram.com/reel/C12345abcde/",
            "https://www.instagram.com/reel/C12345abcde/",
        ),
        (
            "https://instagram.com/reel/C12345abcde?igsh=MXZsdjExZ2",
            "https://www.instagram.com/reel/C12345abcde/",
        ),
        (
            "https://www.instagram.com/reels/C12345abcde/",
            "https://www.instagram.com/reel/C12345abcde/",
        ),
        (
            "https://www.instagram.com/p/C12345abcde/",
            "https://www.instagram.com/p/C12345abcde/",
        ),
        (
            "https://instagram.com/p/C12345abcde/?utm_source=ig_web_copy_link",
            "https://www.instagram.com/p/C12345abcde/",
        ),
        (
            "https://www.instagram.com/tv/C12345abcde/",
            "https://www.instagram.com/p/C12345abcde/",
        ),
        (
            "https://www.instagram.com/username/reel/C12345abcde/",
            "https://www.instagram.com/reel/C12345abcde/",
        ),
        (
            "https://www.instagram.com/username/p/C12345abcde/",
            "https://www.instagram.com/p/C12345abcde/",
        ),
    ],
)
def test_instagram_media_urls_are_detected_and_normalized(
    url: str,
    expected_normalized: str,
) -> None:
    assert detect_platform_from_url(url) == "instagram"
    assert is_instagram_media_url(url) is True
    assert normalize_media_url(url) == expected_normalized


@pytest.mark.parametrize(
    "url",
    [
        "https://www.instagram.com/username",
        "https://www.instagram.com/username/",
        "https://www.instagram.com/explore/",
        "https://www.instagram.com/explore/tags/travel/",
        "https://www.instagram.com/direct/inbox/",
        "https://instagram.com/stories/username/1234567890/",
        "https://www.instagram.com/",
    ],
)
def test_non_media_instagram_urls_are_rejected_as_media(url: str) -> None:
    assert detect_platform_from_url(url) == "instagram"
    assert is_instagram_media_url(url) is False


def test_invalid_instagram_url_raises_api_error() -> None:
    service = MediaService()
    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://www.instagram.com/username")

    assert exc_info.value.code == "INVALID_INSTAGRAM_URL"
    assert exc_info.value.status_code == 422


# ==============================================================================
# 2. QUALITY SELECTOR TESTS FOR INSTAGRAM
# ==============================================================================


def test_instagram_direct_mp4_missing_acodec_is_detected_as_having_audio() -> None:
    """Instagram direct MP4s omit acodec metadata while carrying multiplexed AAC."""
    selector = QualitySelector()
    direct_format = {
        "format_id": "0",
        "ext": "mp4",
        "vcodec": "avc1.64001f",
        "acodec": None,
        "width": 720,
        "height": 1280,
        "protocol": "https",
        "fps": 30,
        "tbr": 1500.0,
    }

    # Should detect audio when platform is instagram
    assert selector.has_audio_available([direct_format], platform="instagram") is True

    # Should NOT detect audio when platform is none / generic / youtube
    assert selector.has_audio_available([direct_format], platform="youtube") is False
    assert selector.has_audio_available([direct_format]) is False


def test_instagram_direct_mp4_builds_valid_video_qualities() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "0",
            "ext": "mp4",
            "vcodec": "avc1.64001f",
            "acodec": None,
            "width": 720,
            "height": 1280,
            "protocol": "https",
            "fps": 30,
            "tbr": 1500.0,
        },
        {
            "format_id": "1",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": None,
            "width": 480,
            "height": 854,
            "protocol": "https",
            "fps": 30,
            "tbr": 800.0,
        },
    ]

    qualities = selector.build_qualities(formats, platform="instagram")
    assert len(qualities) == 2
    assert qualities[0].height == 480
    assert "480p" in qualities[0].label
    assert qualities[1].height == 720
    assert "720p" in qualities[1].label


def test_instagram_dash_adaptive_formats_are_paired_properly() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "dash-video-1080",
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": "none",
            "width": 1080,
            "height": 1920,
            "protocol": "https",
            "fps": 30,
            "tbr": 3000.0,
        },
        {
            "format_id": "dash-audio",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "protocol": "https",
            "abr": 128.0,
        },
    ]

    qualities = selector.build_qualities(formats, platform="instagram")
    assert len(qualities) == 1
    assert qualities[0].height == 1080


def test_instagram_explicit_video_only_format_without_audio_is_rejected() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "video-only",
            "ext": "mp4",
            "vcodec": "avc1.64001f",
            "acodec": "none",
            "audio_ext": "none",
            "width": 720,
            "height": 1280,
            "protocol": "https",
        }
    ]

    assert selector.has_audio_available(formats, platform="instagram") is False


# ==============================================================================
# 3. MEDIA SERVICE METADATA & DOWNLOAD TESTS
# ==============================================================================


def test_instagram_metadata_endpoint_success(client: TestClient) -> None:
    mock_info = {
        "id": "C_meta_123",
        "title": "Instagram Reel by testuser",
        "uploader": "testuser",
        "uploader_url": "https://www.instagram.com/testuser/",
        "thumbnail": "https://instagram.fcdn.net/thumb.jpg",
        "duration": 30,
        "webpage_url": "https://www.instagram.com/reel/C_meta_123/",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "view_count": 10000,
        "like_count": 500,
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
                "fps": 30,
            }
        ],
    }

    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.return_value = mock_info
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post("/media/info", json={"url": "https://www.instagram.com/reel/C_meta_123/"})

    assert response.status_code == 200
    res_json = response.json()
    assert res_json["success"] is True
    data = res_json["data"]
    assert data["platform"] == "instagram"
    assert data["title"] == "Instagram Reel by testuser"
    assert data["duration_seconds"] == 30
    assert len(data["video_qualities"]) == 1
    assert data["video_qualities"][0]["height"] == 720
    assert len(data["audio_options"]) == 1
    assert data["audio_options"][0]["extension"] == "mp3"


def test_instagram_download_job_creation(client: TestClient) -> None:
    mock_info = {
        "id": "C_down_123",
        "title": "Instagram Reel by testuser",
        "duration": 30,
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
            }
        ],
    }

    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.return_value = mock_info
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post(
            "/media/download",
            json={
                "url": "https://www.instagram.com/reel/C_down_123/",
                "media_type": "video",
                "quality_height": 720,
            },
        )

    assert response.status_code == 200
    res_json = response.json()
    assert res_json["success"] is True
    data = res_json["data"]
    assert data["job_id"] is not None


def test_instagram_post_with_no_video_returns_friendly_error(client: TestClient) -> None:
    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.side_effect = DownloadError("There is no video in this post")
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post("/media/info", json={"url": "https://www.instagram.com/p/C_novideo_123/"})

    assert response.status_code == 422
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "NO_VIDEO_IN_POST"


def test_instagram_private_post_returns_private_error(client: TestClient) -> None:
    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.side_effect = DownloadError(
            "This video is private. Only registered users who follow this account can see it."
        )
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post("/media/info", json={"url": "https://www.instagram.com/reel/C_private_123/"})

    assert response.status_code == 403
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "VIDEO_PRIVATE"


def test_instagram_deleted_or_unavailable_post_returns_unavailable_error(client: TestClient) -> None:
    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.side_effect = DownloadError("The media is unavailable or removed")
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post("/media/info", json={"url": "https://www.instagram.com/reel/C_unavail_123/"})

    assert response.status_code == 404
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "INSTAGRAM_MEDIA_NOT_AVAILABLE"


# ==============================================================================
# 4. INSTAGRAM AUTHENTICATED FALLBACK TESTS
# ==============================================================================


def _create_instagram_cookie_file(tmp_path: Path) -> Path:
    cookie_file = tmp_path / "instagram.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\tsecret_session_token\n"
        ".instagram.com\tTRUE\t/\tTRUE\t2147483647\tcsrftoken\tsecret_csrf_token\n"
        ".instagram.com\tTRUE\t/\tTRUE\t2147483647\tds_user_id\t123456789\n",
        encoding="utf-8",
    )
    return cookie_file


def test_instagram_guest_success_does_not_attempt_authenticated_extraction(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_instagram_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()
    mock_info = {
        "id": "C_guest_123",
        "title": "Guest Instagram Video",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
            }
        ],
    }

    with patch.object(service, "_extract_info", return_value=mock_info) as mock_extract:
        meta = service.get_metadata("https://www.instagram.com/reel/C_guest_123/")

    assert meta.title == "Guest Instagram Video"
    assert mock_extract.call_count == 1
    assert "cookie_file" not in mock_extract.call_args.kwargs or mock_extract.call_args.kwargs["cookie_file"] is None


def test_instagram_guest_failure_retries_with_configured_authentication(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_instagram_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()
    auth_info = {
        "id": "C_auth_123",
        "title": "Authenticated Instagram Video",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
            }
        ],
    }

    def _side_effect(url: str, cookie_file: Path | None = None) -> dict[str, Any]:
        if cookie_file is None:
            raise DownloadError("Login required to view this post")
        return auth_info

    with patch.object(service, "_extract_info", side_effect=_side_effect) as mock_extract:
        meta = service.get_metadata("https://www.instagram.com/reel/C_auth_123/")

    assert meta.title == "Authenticated Instagram Video"
    assert mock_extract.call_count == 2
    assert mock_extract.call_args_list[1].kwargs["cookie_file"] == cookie_file


def test_instagram_authenticated_failure_preserves_the_guest_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_instagram_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()

    with patch.object(
        service,
        "_extract_info",
        side_effect=DownloadError("Post is private"),
    ):
        with pytest.raises(APIError) as exc_info:
            service.get_metadata("https://www.instagram.com/reel/C_auth_fail_123/")

    assert exc_info.value.code == "VIDEO_PRIVATE"
    assert exc_info.value.status_code == 403


def test_authenticated_snapshot_never_contains_instagram_cookie_secrets(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_instagram_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()
    raw_info = {
        "id": "C_secret_123",
        "title": "Secret Token Video",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "sessionid": "super_secret_session_token",
        "csrftoken": "super_secret_csrf_token",
        "ds_user_id": "123456789",
        "http_headers": {
            "Cookie": "sessionid=super_secret_session_token; csrftoken=super_secret_csrf_token",
        },
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
                "http_headers": {
                    "Cookie": "sessionid=super_secret_session_token",
                },
            }
        ],
    }

    sanitized = service._sanitize_authenticated_snapshot_info(raw_info)
    assert "sessionid" not in sanitized
    assert "csrftoken" not in sanitized
    assert "ds_user_id" not in sanitized
    assert "Cookie" not in sanitized.get("http_headers", {})
    assert "Cookie" not in sanitized["formats"][0].get("http_headers", {})


# ==============================================================================
# 5. INSTAGRAM CAROUSEL PLAYLIST TESTS
# ==============================================================================


def test_instagram_carousel_metadata_filters_image_only_entries(client: TestClient) -> None:
    carousel_info = {
        "_type": "playlist",
        "id": "C12345carousel",
        "title": "Instagram Carousel Post",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "entries": [
            # Entry 1: Image only (no formats, no duration) -> should be filtered out
            {
                "id": "slide1_img",
                "title": "Slide 1 Image",
                "formats": [],
                "duration": None,
                "ie_key": "Instagram",
            },
            # Entry 2: Video slide -> should be included
            {
                "id": "slide2_vid",
                "title": "Slide 2 Video",
                "duration": 15,
                "thumbnail": "https://instagram.fcdn.net/slide2.jpg",
                "formats": [
                    {
                        "format_id": "0",
                        "ext": "mp4",
                        "vcodec": "avc1.64001f",
                        "acodec": None,
                        "width": 720,
                        "height": 1280,
                    }
                ],
                "ie_key": "Instagram",
            },
            # Entry 3: Video slide -> should be included
            {
                "id": "slide3_vid",
                "title": "Slide 3 Video",
                "duration": 20,
                "thumbnail": "https://instagram.fcdn.net/slide3.jpg",
                "formats": [
                    {
                        "format_id": "0",
                        "ext": "mp4",
                        "vcodec": "avc1.64001f",
                        "acodec": None,
                        "width": 720,
                        "height": 1280,
                    }
                ],
                "ie_key": "Instagram",
            },
        ],
    }

    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.return_value = carousel_info
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl

        response = client.post("/media/playlist/info", json={"url": "https://www.instagram.com/p/C12345carousel/"})

    assert response.status_code == 200
    res_json = response.json()
    assert res_json["success"] is True
    data = res_json["data"]
    assert data["total_count"] == 2
    assert len(data["items"]) == 2
    assert data["items"][0]["title"] == "Slide 2 Video"
    assert data["items"][0]["duration_seconds"] == 15
    assert data["items"][0]["webpage_url"] == "https://www.instagram.com/p/slide2_vid/"
    assert data["items"][1]["title"] == "Slide 3 Video"
    assert data["items"][1]["duration_seconds"] == 20
    assert data["items"][1]["webpage_url"] == "https://www.instagram.com/p/slide3_vid/"


def test_instagram_is_registered_for_transport_refresh() -> None:
    from app.services.media_service import _PLATFORMS_REQUIRING_TRANSPORT_REFRESH

    assert "instagram" in _PLATFORMS_REQUIRING_TRANSPORT_REFRESH


def test_instagram_download_transport_refresh_is_invoked(
    client: TestClient,
    tmp_path: Path,
) -> None:
    from app.services.media_service import MediaService

    service = MediaService()
    initial_snapshot = {
        "id": "C_refresh_test",
        "title": "Refresh Test Video",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "webpage_url": "https://www.instagram.com/reel/C_refresh_test/",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "url": "https://instagram.fcdn.net/expired_token.mp4",
            }
        ],
    }
    refreshed_data = {
        "id": "C_refresh_test",
        "title": "Refresh Test Video",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "webpage_url": "https://www.instagram.com/reel/C_refresh_test/",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "url": "https://instagram.fcdn.net/fresh_token.mp4",
            }
        ],
    }

    mock_ydl = MagicMock()
    mock_ydl.extract_info.return_value = refreshed_data
    mock_ydl.process_ie_result.return_value = refreshed_data

    resolved, legacy = service._refresh_download_transport_info(
        mock_ydl,
        url="https://www.instagram.com/reel/C_refresh_test/",
        snapshot=initial_snapshot,
    )

    mock_ydl.extract_info.assert_called_once_with(
        "https://www.instagram.com/reel/C_refresh_test/",
        download=False,
        process=False,
    )
    assert resolved["formats"][0]["url"] == "https://instagram.fcdn.net/fresh_token.mp4"
    assert legacy["formats"][0]["url"] == "https://instagram.fcdn.net/fresh_token.mp4"


def test_instagram_authenticated_snapshot_invalidation_when_cookie_removed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services.media_service import MediaService
    from app.services.media_snapshot_cache import MediaSnapshotCache

    cookie_file = tmp_path / "instagram.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\tvalid_session\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    snapshot_cache = MediaSnapshotCache()
    service = MediaService(snapshot_cache=snapshot_cache)

    cached_info = {
        "id": "C_auth_invalidate",
        "title": "Authenticated Post",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "webpage_url": "https://www.instagram.com/p/C_auth_invalidate/",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
            }
        ],
    }
    normalized_url = "https://www.instagram.com/p/C_auth_invalidate/"
    service._snapshot_cache.put(normalized_url, cached_info, authenticated=True)

    # 1. While cookie is set, cached result is returned
    cached_result = service._get_cached_supported_info(normalized_url)
    assert cached_result is not None
    info, platform, authenticated, source_url = cached_result
    assert authenticated is True
    assert platform == "instagram"

    # 2. When cookie setting is removed, cache is invalidated
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", "")
    get_settings.cache_clear()
    service._settings = get_settings()
    invalidated_result = service._get_cached_supported_info(normalized_url)
    assert invalidated_result is None
    assert service._snapshot_cache.get(normalized_url) is None


def test_instagram_multi_resolution_progressive_sorting() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "1080",
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": None,
            "width": 1080,
            "height": 1920,
            "protocol": "https",
            "fps": 30,
            "tbr": 3500.0,
        },
        {
            "format_id": "360",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": None,
            "width": 360,
            "height": 640,
            "protocol": "https",
            "fps": 30,
            "tbr": 500.0,
        },
        {
            "format_id": "720",
            "ext": "mp4",
            "vcodec": "avc1.64001f",
            "acodec": None,
            "width": 720,
            "height": 1280,
            "protocol": "https",
            "fps": 30,
            "tbr": 1800.0,
        },
        {
            "format_id": "480",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": None,
            "width": 480,
            "height": 854,
            "protocol": "https",
            "fps": 30,
            "tbr": 900.0,
        },
        # Malformed format (should be rejected)
        {
            "format_id": "bad",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": None,
            "width": 0,
            "height": -1,
            "protocol": "https",
        },
    ]

    qualities = selector.build_qualities(formats, platform="instagram")
    assert len(qualities) == 4
    assert qualities[0].height == 360
    assert qualities[0].label == "360p"
    assert qualities[1].height == 480
    assert qualities[1].label == "480p"
    assert qualities[2].height == 720
    assert qualities[2].label == "720p HD"
    assert qualities[3].height == 1080
    assert qualities[3].label == "1080p Full HD"

    # Non-Instagram platform must reject these formats (missing acodec)
    youtube_qualities = selector.build_qualities(formats, platform="youtube")
    assert len(youtube_qualities) == 0


def test_instagram_authenticated_fallback_after_502(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    client: TestClient,
) -> None:
    from app.core.exceptions import APIError
    from app.services.media_service import MediaService

    cookie_file = tmp_path / "instagram.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\tvalid_session_502\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("NEXORA_INSTAGRAM_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()

    authenticated_info = {
        "id": "C_retry_502",
        "title": "Post after 502",
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "webpage_url": "https://www.instagram.com/reel/C_retry_502/",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
            }
        ],
    }

    guest_502_error = APIError(
        code="INSTAGRAM_EXTRACTION_UNAVAILABLE",
        message="Instagram post temporarily unavailable",
        details="Instagram returned a temporary error.",
        status_code=502,
    )

    with patch.object(service, "_extract_info_or_raise_api_error", return_value=authenticated_info) as mock_auth_extract:
        result = service._try_authenticated_instagram_extraction(
            "https://www.instagram.com/reel/C_retry_502/",
            guest_error=guest_502_error,
        )

    assert result is not None
    info, platform = result
    assert platform == "instagram"
    assert info["id"] == "C_retry_502"
    mock_auth_extract.assert_called_once()
