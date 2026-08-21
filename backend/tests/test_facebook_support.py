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
    is_facebook_media_url,
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
            "https://www.facebook.com/watch/?v=647537299265662",
            "https://www.facebook.com/watch/?v=647537299265662",
        ),
        (
            "https://www.facebook.com/watch/?v=647537299265662&fbclid=IwAR3abc&mibextid=rS40aB",
            "https://www.facebook.com/watch/?v=647537299265662",
        ),
        (
            "https://facebook.com/reel/1195289147628387",
            "https://www.facebook.com/reel/1195289147628387/",
        ),
        (
            "https://www.facebook.com/reel/1195289147628387/?mibextid=rS40aB7S9Ucbxw6v",
            "https://www.facebook.com/reel/1195289147628387/",
        ),
        (
            "https://www.facebook.com/reels/1195289147628387/",
            "https://www.facebook.com/reel/1195289147628387/",
        ),
        (
            "https://m.facebook.com/cnn/videos/10155529876156509/?ref=sharing",
            "https://www.facebook.com/cnn/videos/10155529876156509/",
        ),
        (
            "https://www.facebook.com/radiokicksfm/videos/3676516585958356/",
            "https://www.facebook.com/radiokicksfm/videos/3676516585958356/",
        ),
        (
            "https://www.facebook.com/user/posts/10153807558977570",
            "https://www.facebook.com/user/posts/10153807558977570",
        ),
        (
            "https://www.facebook.com/share/v/123456789/",
            "https://www.facebook.com/share/v/123456789/",
        ),
        (
            "https://www.facebook.com/share/r/987654321/",
            "https://www.facebook.com/share/r/987654321/",
        ),
        (
            "https://fb.watch/123456789/",
            "https://fb.watch/123456789/",
        ),
        (
            "https://web.facebook.com/watch/?v=12345&notif_t=video_reply",
            "https://www.facebook.com/watch/?v=12345",
        ),
    ],
)
def test_facebook_media_urls_are_detected_and_normalized(
    url: str,
    expected_normalized: str,
) -> None:
    assert detect_platform_from_url(url) == "facebook"
    assert is_facebook_media_url(url) is True
    assert normalize_media_url(url) == expected_normalized


@pytest.mark.parametrize(
    "url",
    [
        "https://www.facebook.com/username",
        "https://www.facebook.com/username/",
        "https://www.facebook.com/groups/feed/",
        "https://www.facebook.com/marketplace/",
        "https://www.facebook.com/events/",
        "https://www.facebook.com/friends/",
        "https://www.facebook.com/",
    ],
)
def test_non_media_facebook_urls_are_rejected_as_media(url: str) -> None:
    assert detect_platform_from_url(url) == "facebook"
    assert is_facebook_media_url(url) is False


def test_invalid_facebook_url_raises_api_error() -> None:
    service = MediaService()
    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://www.facebook.com/username")

    assert exc_info.value.code == "INVALID_FACEBOOK_URL"
    assert exc_info.value.status_code == 422


# ==============================================================================
# 2. QUALITY SELECTOR TESTS FOR FACEBOOK
# ==============================================================================


def test_facebook_progressive_sd_and_hd_formats_map_to_conservative_resolutions() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "sd",
            "ext": "mp4",
            "protocol": "https",
            "vcodec": None,
            "acodec": None,
            "width": None,
            "height": None,
            "tbr": 800.0,
        },
        {
            "format_id": "hd",
            "ext": "mp4",
            "protocol": "https",
            "vcodec": None,
            "acodec": None,
            "width": None,
            "height": None,
            "tbr": 1800.0,
        },
    ]

    qualities = selector.select_qualities(formats, platform="facebook")
    assert len(qualities) == 2
    assert qualities[0].quality.height == 480
    assert qualities[0].selector == "sd"
    assert qualities[1].quality.height == 720
    assert qualities[1].selector == "hd"
    assert selector.has_audio_available(formats, platform="facebook") is True

    # When platform is not facebook, missing codec & dimension formats must be rejected
    assert selector.select_qualities(formats, platform="youtube") == []
    assert selector.has_audio_available(formats, platform="youtube") is False


def test_facebook_explicit_video_only_is_rejected_as_progressive_candidate() -> None:
    selector = QualitySelector()
    video_only_format = {
        "format_id": "sd",
        "ext": "mp4",
        "protocol": "https",
        "vcodec": "avc1.4d401f",
        "acodec": "none",
        "audio_ext": "none",
        "height": 480,
        "width": 854,
    }

    assert selector.has_audio_available([video_only_format], platform="facebook") is False
    assert selector.select_qualities([video_only_format], platform="facebook") == []


def test_facebook_dash_adaptive_video_and_audio_pairing() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "audio_128k",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "protocol": "https",
            "abr": 128.0,
        },
        {
            "format_id": "video_360p",
            "ext": "mp4",
            "vcodec": "vp09.00.21.08",
            "acodec": "none",
            "protocol": "https",
            "width": 360,
            "height": 640,
            "tbr": 500.0,
        },
        {
            "format_id": "video_720p",
            "ext": "mp4",
            "vcodec": "vp09.00.31.08",
            "acodec": "none",
            "protocol": "https",
            "width": 720,
            "height": 1280,
            "tbr": 1500.0,
        },
        {
            "format_id": "video_1080p",
            "ext": "mp4",
            "vcodec": "vp09.00.40.08",
            "acodec": "none",
            "protocol": "https",
            "width": 1080,
            "height": 1920,
            "tbr": 3000.0,
        },
    ]

    qualities = selector.select_qualities(formats, platform="facebook")
    assert len(qualities) == 3
    assert [q.quality.height for q in qualities] == [360, 720, 1080]
    assert qualities[0].selector == "video_360p+audio_128k"
    assert qualities[1].selector == "video_720p+audio_128k"
    assert qualities[2].selector == "video_1080p+audio_128k"
    assert selector.has_audio_available(formats, platform="facebook") is True


# ==============================================================================
# 3. METADATA EXTRACTION & AUDIO OPTIONS
# ==============================================================================


def test_facebook_metadata_extraction_returns_media_metadata() -> None:
    service = MediaService()
    mock_info = {
        "id": "647537299265662",
        "title": "Public Facebook Video",
        "uploader": "Facebook Creator",
        "uploader_url": "https://www.facebook.com/creator",
        "duration": 65,
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": "https://www.facebook.com/watch/?v=647537299265662",
        "formats": [
            {
                "format_id": "sd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            },
            {
                "format_id": "hd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            },
        ],
    }

    with patch.object(service, "_extract_info_or_raise_api_error", return_value=mock_info):
        meta = service.get_metadata("https://www.facebook.com/watch/?v=647537299265662")

    assert meta.platform == "facebook"
    assert meta.title == "Public Facebook Video"
    assert len(meta.video_qualities) == 2
    assert [q.height for q in meta.video_qualities] == [480, 720]
    assert len(meta.audio_options) == 1
    assert meta.audio_options[0].extension == "mp3"


# ==============================================================================
# 4. AUTHENTICATED EXTRACTION FALLBACK
# ==============================================================================


def _create_facebook_cookie_file(tmp_path: Path) -> Path:
    cookie_file = tmp_path / "facebook.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".facebook.com\tTRUE\t/\tTRUE\t2147483647\tc_user\t100012345\n"
        ".facebook.com\tTRUE\t/\tTRUE\t2147483647\txs\tsecret_session_token\n"
        ".facebook.com\tTRUE\t/\tTRUE\t2147483647\tdatr\tsecret_datr\n",
        encoding="utf-8",
    )
    return cookie_file


def test_facebook_guest_success_does_not_attempt_authenticated_extraction(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_facebook_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_FACEBOOK_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()
    mock_info = {
        "id": "647537299265662",
        "title": "Guest Facebook Video",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "formats": [
            {
                "format_id": "hd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            }
        ],
    }

    with patch.object(service, "_extract_info", return_value=mock_info) as mock_extract:
        meta = service.get_metadata("https://www.facebook.com/watch/?v=647537299265662")

    assert meta.title == "Guest Facebook Video"
    assert mock_extract.call_count == 1
    assert "cookie_file" not in mock_extract.call_args.kwargs or mock_extract.call_args.kwargs["cookie_file"] is None


def test_facebook_authenticated_fallback_triggers_when_guest_fails_private(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cookie_file = _create_facebook_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_FACEBOOK_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()

    auth_info = {
        "id": "123456789",
        "title": "Private Facebook Video",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": "https://www.facebook.com/watch/?v=123456789",
        "formats": [
            {
                "format_id": "hd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            }
        ],
        "c_user": "100012345",
        "xs": "secret_session_token",
    }

    def _side_effect(url: str, *, cookie_file: Path | None = None) -> dict[str, Any]:
        if cookie_file is None:
            raise DownloadError("This video is private or restricted")
        return auth_info

    with patch.object(service, "_extract_info", side_effect=_side_effect) as mock_extract:
        meta = service.get_metadata("https://www.facebook.com/watch/?v=123456789")

    assert mock_extract.call_count == 2
    assert meta.platform == "facebook"
    assert meta.title == "Private Facebook Video"


def test_facebook_authenticated_fallback_disabled_when_cookie_file_unconfigured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NEXORA_FACEBOOK_AUTH_COOKIE_FILE", raising=False)
    service = MediaService()

    with patch.object(
        service,
        "_extract_info",
        side_effect=DownloadError("This video is private"),
    ):
        with pytest.raises(APIError) as exc_info:
            service.get_metadata("https://www.facebook.com/watch/?v=123456789")

    assert exc_info.value.code == "VIDEO_PRIVATE"
    assert exc_info.value.status_code == 403


# ==============================================================================
# 5. SNAPSHOT SECURITY & CACHE SANITIZATION
# ==============================================================================


def test_facebook_snapshot_sanitization_removes_sensitive_cookie_keys() -> None:
    raw_info = {
        "id": "12345",
        "title": "FB Video",
        "c_user": "100012345",
        "xs": "secret_xs",
        "fr": "secret_fr",
        "datr": "secret_datr",
        "sb": "secret_sb",
        "presence": "secret_presence",
        "wd": "1920x1080",
        "authorization": "Bearer token",
        "formats": [
            {
                "format_id": "sd",
                "url": "https://video.xx.fbcdn.net/v/t2/sd.mp4",
                "http_headers": {
                    "cookie": "c_user=100012345; xs=secret_xs;",
                    "authorization": "Bearer 123",
                },
            }
        ],
    }

    sanitized = MediaService._sanitize_authenticated_snapshot_info(raw_info)

    assert "c_user" not in sanitized
    assert "xs" not in sanitized
    assert "fr" not in sanitized
    assert "datr" not in sanitized
    assert "sb" not in sanitized
    assert "presence" not in sanitized
    assert "wd" not in sanitized
    assert "authorization" not in sanitized

    format_headers = sanitized["formats"][0].get("http_headers", {})
    assert "cookie" not in format_headers
    assert "authorization" not in format_headers


def test_facebook_authenticated_snapshot_invalidated_when_cookie_file_is_removed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cookie_file = _create_facebook_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_FACEBOOK_AUTH_COOKIE_FILE", str(cookie_file))

    snapshot_cache = MediaSnapshotCache()
    service = MediaService(snapshot_cache=snapshot_cache)
    url = "https://www.facebook.com/watch/?v=123456789"
    normalized_url = normalize_media_url(url)

    cached_info = {
        "id": "123456789",
        "title": "Private Facebook Video",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": normalized_url,
        "formats": [
            {
                "format_id": "hd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            }
        ],
    }

    # Store authenticated snapshot
    service._snapshot_cache.put(normalized_url, cached_info, authenticated=True)

    # 1. While cookie is set, cached snapshot is accepted
    cached_result = service._get_cached_supported_info(normalized_url)
    assert cached_result is not None
    info, platform, authenticated, source_url = cached_result
    assert authenticated is True
    assert platform == "facebook"

    # 2. When cookie configuration is removed, snapshot must be rejected / invalidated
    monkeypatch.setenv("NEXORA_FACEBOOK_AUTH_COOKIE_FILE", "")
    get_settings.cache_clear()
    service._settings = get_settings()
    invalidated_result = service._get_cached_supported_info(normalized_url)
    assert invalidated_result is None
    assert service._snapshot_cache.get(normalized_url) is None


# ==============================================================================
# 6. TRANSPORT REFRESH
# ==============================================================================


def test_facebook_enters_transport_refresh_path() -> None:
    service = MediaService()
    url = "https://www.facebook.com/watch/?v=647537299265662"
    normalized = normalize_media_url(url)

    initial_snapshot = {
        "id": "647537299265662",
        "title": "FB Video",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": normalized,
        "formats": [
            {
                "format_id": "sd",
                "ext": "mp4",
                "url": "https://video.fbcdn.net/stale.mp4",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            }
        ],
    }

    refreshed_data = {
        "id": "647537299265662",
        "title": "FB Video",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": normalized,
        "formats": [
            {
                "format_id": "sd",
                "ext": "mp4",
                "url": "https://video.fbcdn.net/fresh.mp4",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            }
        ],
    }

    mock_ydl = MagicMock()
    mock_ydl.extract_info.return_value = refreshed_data
    mock_ydl.process_ie_result.return_value = refreshed_data

    resolved, legacy = service._refresh_download_transport_info(
        mock_ydl,
        url=normalized,
        snapshot=initial_snapshot,
    )

    mock_ydl.extract_info.assert_called_once_with(
        normalized,
        download=False,
        process=False,
    )
    assert resolved["formats"][0]["url"] == "https://video.fbcdn.net/fresh.mp4"
    assert legacy["formats"][0]["url"] == "https://video.fbcdn.net/fresh.mp4"


# ==============================================================================
# 7. ERROR CLASSIFICATION AND MAPPING
# ==============================================================================


def test_facebook_error_mappings() -> None:
    service = MediaService()
    url = "https://www.facebook.com/watch/?v=123"

    # Unsupported URL
    err_unsupported = service._map_yt_dlp_error(DownloadError("Unsupported URL: facebook.com/..."), url=url)
    assert err_unsupported.code == "INVALID_FACEBOOK_URL"
    assert err_unsupported.status_code == 422

    # No video in post
    err_no_video = service._map_yt_dlp_error(ExtractorError("Cannot parse data"), url=url)
    assert err_no_video.code == "NO_VIDEO_IN_POST"
    assert err_no_video.status_code == 422

    # Private
    err_private = service._map_yt_dlp_error(DownloadError("This video is private"), url=url)
    assert err_private.code == "VIDEO_PRIVATE"
    assert err_private.status_code == 403

    # Deleted / 404
    err_404 = service._map_yt_dlp_error(DownloadError("HTTP Error 404: Not Found"), url=url)
    assert err_404.code == "FACEBOOK_MEDIA_NOT_AVAILABLE"
    assert err_404.status_code == 404

    # Transient 5xx / general failure
    err_500 = service._map_yt_dlp_error(DownloadError("Facebook internal server error (500)"), url=url)
    assert err_500.code == "FACEBOOK_EXTRACTION_UNAVAILABLE"
    assert err_500.status_code == 502


# ==============================================================================
# 8. PLAYLIST / MULTI-MEDIA SUPPORT
# ==============================================================================


def test_facebook_is_registered_for_transport_refresh() -> None:
    from app.services.media_service import _PLATFORMS_REQUIRING_TRANSPORT_REFRESH

    assert "facebook" in _PLATFORMS_REQUIRING_TRANSPORT_REFRESH


def test_facebook_multi_video_playlist_metadata() -> None:
    service = MediaService()
    playlist_info = {
        "_type": "playlist",
        "id": "album_123",
        "title": "Facebook Video Album",
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "entries": [
            {
                "id": "vid_1",
                "title": "Video 1",
                "duration": 30,
                "extractor": "facebook",
                "extractor_key": "Facebook",
                "formats": [{"format_id": "sd", "ext": "mp4"}],
            },
            {
                "id": "img_2",
                "title": "Photo 2",
                "formats": [],
                "duration": None,
            },
            {
                "id": "vid_3",
                "title": "Video 3",
                "duration": 45,
                "extractor": "facebook",
                "extractor_key": "Facebook",
                "formats": [{"format_id": "hd", "ext": "mp4"}],
            },
        ],
    }

    with patch.object(service, "_extract_playlist_info_or_raise_api_error", return_value=playlist_info):
        meta = service.get_playlist_metadata("https://www.facebook.com/watch/?v=123")

    assert meta.total_count == 2
    assert meta.items[0].title == "Video 1"
    assert meta.items[0].webpage_url == "https://www.facebook.com/watch/?v=vid_1"
    assert meta.items[1].title == "Video 3"
    assert meta.items[1].webpage_url == "https://www.facebook.com/watch/?v=vid_3"


def test_facebook_single_video_rejected_by_playlist_endpoint() -> None:
    service = MediaService()
    single_video_info = {
        "id": "647537299265662",
        "title": "Single Video",
        "extractor": "facebook",
        "formats": [{"format_id": "hd", "ext": "mp4"}],
    }

    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.return_value = single_video_info
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl
        with pytest.raises(APIError) as exc_info:
            service.get_playlist_metadata("https://www.facebook.com/watch/?v=647537299265662")

    assert exc_info.value.code == "NOT_A_PLAYLIST"
    assert exc_info.value.status_code == 422


# ==============================================================================
# 9. END-TO-END DOWNLOAD JOB FLOW
# ==============================================================================


def test_facebook_download_job_creation(client: TestClient) -> None:
    mock_info = {
        "id": "647537299265662",
        "title": "Padre ensena a su hijo",
        "uploader": "Facebook Creator",
        "duration": 60,
        "extractor": "facebook",
        "extractor_key": "Facebook",
        "webpage_url": "https://www.facebook.com/watch/?v=647537299265662",
        "formats": [
            {
                "format_id": "sd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            },
            {
                "format_id": "hd",
                "ext": "mp4",
                "protocol": "https",
                "vcodec": None,
                "acodec": None,
                "width": None,
                "height": None,
            },
        ],
    }

    with patch("app.services.media_service.MediaService._extract_info_or_raise_api_error", return_value=mock_info):
        response = client.post(
            "/media/download",
            json={
                "url": "https://www.facebook.com/watch/?v=647537299265662",
                "media_type": "video",
                "quality_height": 720,
            },
        )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "job_id" in data["data"]
