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
    is_reddit_media_url,
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
            "https://www.reddit.com/r/videos/comments/6rrwyj/that_small_heart_attack/",
            "https://www.reddit.com/r/videos/comments/6rrwyj/that_small_heart_attack/",
        ),
        (
            "https://reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/?utm_source=share&utm_medium=web2x&context=3",
            "https://www.reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/",
        ),
        (
            "https://old.reddit.com/r/gifs/comments/19cdefg/amazing_trick/",
            "https://www.reddit.com/r/gifs/comments/19cdefg/amazing_trick/",
        ),
        (
            "https://sh.reddit.com/r/memes/comments/18xyzab/funny_meme/",
            "https://www.reddit.com/r/memes/comments/18xyzab/funny_meme/",
        ),
        (
            "https://m.reddit.com/r/funny/comments/124pp33/prank/",
            "https://www.reddit.com/r/funny/comments/124pp33/prank/",
        ),
        (
            "https://www.reddit.com/comments/124pp33",
            "https://www.reddit.com/comments/124pp33/",
        ),
        (
            "https://www.reddit.com/user/creepyt0es/comments/nip71r/stickers_and_prints/",
            "https://www.reddit.com/user/creepyt0es/comments/nip71r/stickers_and_prints/",
        ),
        (
            "https://www.reddit.com/u/creator/comments/17abcde/my_clip/",
            "https://www.reddit.com/u/creator/comments/17abcde/my_clip/",
        ),
        (
            "https://redd.it/124pp33",
            "https://redd.it/124pp33/",
        ),
        (
            "https://v.redd.it/gyh95hiqc0b11",
            "https://v.redd.it/gyh95hiqc0b11/",
        ),
        (
            "https://www.redditmedia.com/r/serbia/comments/pu9wbx/post_title/",
            "https://www.reddit.com/r/serbia/comments/pu9wbx/post_title/",
        ),
    ],
)
def test_reddit_media_urls_are_detected_and_normalized(
    url: str,
    expected_normalized: str,
) -> None:
    assert detect_platform_from_url(url) == "reddit"
    assert is_reddit_media_url(url) is True
    assert normalize_media_url(url) == expected_normalized


@pytest.mark.parametrize(
    "url",
    [
        "https://www.reddit.com/r/videos",
        "https://www.reddit.com/r/videos/",
        "https://www.reddit.com/user/username",
        "https://www.reddit.com/user/username/",
        "https://www.reddit.com/settings/",
        "https://www.reddit.com/message/inbox/",
        "https://www.reddit.com/",
        "https://old.reddit.com/",
    ],
)
def test_non_media_reddit_urls_are_rejected_as_media(url: str) -> None:
    assert detect_platform_from_url(url) == "reddit"
    assert is_reddit_media_url(url) is False


def test_invalid_reddit_url_raises_api_error() -> None:
    service = MediaService()
    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://www.reddit.com/r/videos")

    assert exc_info.value.code == "INVALID_REDDIT_URL"
    assert exc_info.value.status_code == 422


# ==============================================================================
# 2. QUALITY SELECTOR TESTS FOR REDDIT
# ==============================================================================


def test_reddit_dash_adaptive_video_and_audio_pairing() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "dash-audio_0",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "protocol": "https",
            "abr": 128.0,
        },
        {
            "format_id": "dash-video_240",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": "none",
            "protocol": "https",
            "width": 426,
            "height": 240,
            "tbr": 300.0,
        },
        {
            "format_id": "dash-video_360",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": "none",
            "protocol": "https",
            "width": 640,
            "height": 360,
            "tbr": 600.0,
        },
        {
            "format_id": "dash-video_480",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": "none",
            "protocol": "https",
            "width": 854,
            "height": 480,
            "tbr": 1200.0,
        },
        {
            "format_id": "dash-video_720",
            "ext": "mp4",
            "vcodec": "avc1.4d401f",
            "acodec": "none",
            "protocol": "https",
            "width": 1280,
            "height": 720,
            "tbr": 2400.0,
        },
        {
            "format_id": "dash-video_1080",
            "ext": "mp4",
            "vcodec": "avc1.640028",
            "acodec": "none",
            "protocol": "https",
            "width": 1920,
            "height": 1080,
            "tbr": 5000.0,
        },
        {
            "format_id": "fallback",
            "ext": "mp4",
            "vcodec": "h264",
            "acodec": "none",
            "protocol": "https",
            "width": 1920,
            "height": 1080,
            "tbr": 4500.0,
        },
    ]

    qualities = selector.select_qualities(formats, platform="reddit")
    assert len(qualities) == 5
    assert [q.quality.height for q in qualities] == [240, 360, 480, 720, 1080]
    assert qualities[0].selector == "dash-video_240+dash-audio_0"
    assert qualities[1].selector == "dash-video_360+dash-audio_0"
    assert qualities[2].selector == "dash-video_480+dash-audio_0"
    assert qualities[3].selector == "dash-video_720+dash-audio_0"
    assert qualities[4].selector == "dash-video_1080+dash-audio_0"
    assert selector.has_audio_available(formats, platform="reddit") is True


# ==============================================================================
# 3. METADATA EXTRACTION & AUDIO OPTIONS
# ==============================================================================


def test_reddit_metadata_extraction_returns_media_metadata() -> None:
    service = MediaService()
    mock_info = {
        "id": "gyh95hiqc0b11",
        "display_id": "90bu6w",
        "title": "Heat index was 110 degrees so we offered him a cold drink",
        "uploader": "FootLoosePickleJuice",
        "uploader_url": "https://www.reddit.com/user/FootLoosePickleJuice",
        "duration": 14,
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": "https://www.reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/",
        "formats": [
            {
                "format_id": "dash-audio_0",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "protocol": "https",
                "abr": 128.0,
            },
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "protocol": "https",
                "width": 1280,
                "height": 720,
                "tbr": 2400.0,
            },
            {
                "format_id": "dash-video_1080",
                "ext": "mp4",
                "vcodec": "avc1.640028",
                "acodec": "none",
                "protocol": "https",
                "width": 1920,
                "height": 1080,
                "tbr": 4500.0,
            },
        ],
    }

    with patch.object(service, "_extract_info", return_value=mock_info):
        meta = service.get_metadata("https://www.reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/")

    assert meta.platform == "reddit"
    assert meta.title == "Heat index was 110 degrees so we offered him a cold drink"
    assert len(meta.video_qualities) == 2
    assert [q.height for q in meta.video_qualities] == [720, 1080]
    assert len(meta.audio_options) == 1
    assert meta.audio_options[0].extension == "mp3"


# ==============================================================================
# 4. AUTHENTICATED EXTRACTION FALLBACK
# ==============================================================================


def _create_reddit_cookie_file(tmp_path: Path) -> Path:
    cookie_file = tmp_path / "reddit.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".reddit.com\tTRUE\t/\tTRUE\t2147483647\treddit_session\tsecret_reddit_session_token\n"
        ".reddit.com\tTRUE\t/\tTRUE\t2147483647\ttoken_v2\tsecret_token_v2\n"
        ".reddit.com\tTRUE\t/\tTRUE\t2147483647\tloid\tsecret_loid\n",
        encoding="utf-8",
    )
    return cookie_file


def test_reddit_guest_success_does_not_attempt_authenticated_extraction(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _create_reddit_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_REDDIT_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()
    mock_info = {
        "id": "12345",
        "title": "Guest Reddit Video",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "formats": [
            {
                "format_id": "dash-audio_0",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
            },
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "width": 1280,
                "height": 720,
            },
        ],
    }

    with patch.object(service, "_extract_info", return_value=mock_info) as mock_extract:
        meta = service.get_metadata("https://www.reddit.com/r/videos/comments/6rrwyj/test/")

    assert meta.title == "Guest Reddit Video"
    assert mock_extract.call_count == 1
    assert "cookie_file" not in mock_extract.call_args.kwargs or mock_extract.call_args.kwargs["cookie_file"] is None


def test_reddit_authenticated_fallback_triggers_when_guest_fails_private(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cookie_file = _create_reddit_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_REDDIT_AUTH_COOKIE_FILE", str(cookie_file))

    service = MediaService()

    auth_info = {
        "id": "private_123",
        "title": "Private Subreddit Video",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": "https://www.reddit.com/r/private_sub/comments/private_123/",
        "formats": [
            {
                "format_id": "dash-audio_0",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
            },
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "width": 1280,
                "height": 720,
            },
        ],
        "reddit_session": "secret_reddit_session_token",
        "token_v2": "secret_token_v2",
    }

    def _side_effect(url: str, *, cookie_file: Path | None = None) -> dict[str, Any]:
        if cookie_file is None:
            raise DownloadError("Private subreddit; an account that has been approved is required")
        return auth_info

    with patch.object(service, "_extract_info", side_effect=_side_effect) as mock_extract:
        meta = service.get_metadata("https://www.reddit.com/r/private_sub/comments/private_123/")

    assert mock_extract.call_count == 2
    assert meta.platform == "reddit"
    assert meta.title == "Private Subreddit Video"


def test_reddit_authenticated_fallback_disabled_when_cookie_file_unconfigured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NEXORA_REDDIT_AUTH_COOKIE_FILE", raising=False)
    service = MediaService()

    with patch.object(
        service,
        "_extract_info",
        side_effect=DownloadError("Quarantined subreddit; an account that has opted in is required"),
    ):
        with pytest.raises(APIError) as exc_info:
            service.get_metadata("https://www.reddit.com/r/quarantine_sub/comments/123/")

    assert exc_info.value.code == "VIDEO_PRIVATE"
    assert exc_info.value.status_code == 403


# ==============================================================================
# 5. SNAPSHOT SECURITY & CACHE SANITIZATION
# ==============================================================================


def test_reddit_snapshot_sanitization_removes_sensitive_cookie_keys() -> None:
    raw_info = {
        "id": "12345",
        "title": "Reddit Video",
        "reddit_session": "secret_reddit_session_token",
        "token_v2": "secret_token_v2",
        "session_tracker": "secret_tracker",
        "loid": "secret_loid",
        "csv": "secret_csv",
        "edgebucket": "secret_edgebucket",
        "authorization": "Bearer token",
        "formats": [
            {
                "format_id": "dash-video_720",
                "url": "https://v.redd.it/12345/DASH_720.mp4",
                "http_headers": {
                    "cookie": "reddit_session=secret_reddit_session_token;",
                    "authorization": "Bearer 123",
                },
            }
        ],
    }

    sanitized = MediaService._sanitize_authenticated_snapshot_info(raw_info)

    assert "reddit_session" not in sanitized
    assert "token_v2" not in sanitized
    assert "session_tracker" not in sanitized
    assert "loid" not in sanitized
    assert "csv" not in sanitized
    assert "edgebucket" not in sanitized
    assert "authorization" not in sanitized

    format_headers = sanitized["formats"][0].get("http_headers", {})
    assert "cookie" not in format_headers
    assert "authorization" not in format_headers


def test_reddit_authenticated_snapshot_invalidated_when_cookie_file_is_removed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cookie_file = _create_reddit_cookie_file(tmp_path)
    monkeypatch.setenv("NEXORA_REDDIT_AUTH_COOKIE_FILE", str(cookie_file))

    snapshot_cache = MediaSnapshotCache()
    service = MediaService(snapshot_cache=snapshot_cache)
    url = "https://www.reddit.com/r/private_sub/comments/123456/"
    normalized_url = normalize_media_url(url)

    cached_info = {
        "id": "123456",
        "title": "Private Subreddit Video",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": normalized_url,
        "formats": [
            {
                "format_id": "dash-audio_0",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
            },
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "width": 1280,
                "height": 720,
            },
        ],
    }

    # Store authenticated snapshot
    service._snapshot_cache.put(normalized_url, cached_info, authenticated=True)

    # 1. While cookie is set, cached snapshot is accepted
    cached_result = service._get_cached_supported_info(normalized_url)
    assert cached_result is not None
    info, platform, authenticated, source_url = cached_result
    assert authenticated is True
    assert platform == "reddit"

    # 2. When cookie configuration is removed, snapshot must be rejected / invalidated
    monkeypatch.setenv("NEXORA_REDDIT_AUTH_COOKIE_FILE", "")
    get_settings.cache_clear()
    service._settings = get_settings()
    invalidated_result = service._get_cached_supported_info(normalized_url)
    assert invalidated_result is None
    assert service._snapshot_cache.get(normalized_url) is None


# ==============================================================================
# 6. TRANSPORT REFRESH
# ==============================================================================


def test_reddit_is_registered_for_transport_refresh() -> None:
    from app.services.media_service import _PLATFORMS_REQUIRING_TRANSPORT_REFRESH

    assert "reddit" in _PLATFORMS_REQUIRING_TRANSPORT_REFRESH


def test_reddit_enters_transport_refresh_path() -> None:
    service = MediaService()
    url = "https://www.reddit.com/r/aww/comments/90bu6w/test/"
    normalized = normalize_media_url(url)

    initial_snapshot = {
        "id": "gyh95hiqc0b11",
        "title": "Reddit Video",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": normalized,
        "formats": [
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "url": "https://v.redd.it/gyh95hiqc0b11/DASH_720.mp4?stale=1",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "width": 1280,
                "height": 720,
            }
        ],
    }

    refreshed_data = {
        "id": "gyh95hiqc0b11",
        "title": "Reddit Video",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": normalized,
        "formats": [
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "url": "https://v.redd.it/gyh95hiqc0b11/DASH_720.mp4?fresh=1",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "width": 1280,
                "height": 720,
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
    )
    assert resolved["formats"][0]["url"] == "https://v.redd.it/gyh95hiqc0b11/DASH_720.mp4?fresh=1"
    assert legacy["formats"][0]["url"] == "https://v.redd.it/gyh95hiqc0b11/DASH_720.mp4?fresh=1"


# ==============================================================================
# 7. ERROR CLASSIFICATION AND MAPPING
# ==============================================================================


def test_reddit_error_mappings() -> None:
    service = MediaService()
    url = "https://www.reddit.com/r/videos/comments/123/test/"

    # Unsupported URL
    err_unsupported = service._map_yt_dlp_error(DownloadError("Unsupported URL: reddit.com/..."), url=url)
    assert err_unsupported.code == "INVALID_REDDIT_URL"
    assert err_unsupported.status_code == 422

    # No video in post
    err_no_video = service._map_yt_dlp_error(ExtractorError("No media found"), url=url)
    assert err_no_video.code == "NO_VIDEO_IN_POST"
    assert err_no_video.status_code == 422

    # Private / Quarantined / Login required
    err_private = service._map_yt_dlp_error(DownloadError("Account authentication is required"), url=url)
    assert err_private.code == "VIDEO_PRIVATE"
    assert err_private.status_code == 403

    # Deleted / 404
    err_404 = service._map_yt_dlp_error(DownloadError("HTTP Error 404: Not Found"), url=url)
    assert err_404.code == "REDDIT_MEDIA_NOT_AVAILABLE"
    assert err_404.status_code == 404

    # Transient 5xx / general failure
    err_500 = service._map_yt_dlp_error(DownloadError("Reddit internal server error (500)"), url=url)
    assert err_500.code == "REDDIT_EXTRACTION_UNAVAILABLE"
    assert err_500.status_code == 502


# ==============================================================================
# 8. PLAYLIST / MULTI-MEDIA SUPPORT
# ==============================================================================


def test_reddit_multi_video_playlist_metadata() -> None:
    service = MediaService()
    playlist_info = {
        "_type": "playlist",
        "id": "gallery_123",
        "title": "Reddit Video Gallery",
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "entries": [
            {
                "id": "vid_1",
                "display_id": "post_abc",
                "title": "Clip 1",
                "duration": 15,
                "extractor": "reddit",
                "extractor_key": "Reddit",
                "formats": [
                    {
                        "format_id": "dash-audio_0",
                        "ext": "m4a",
                        "vcodec": "none",
                        "acodec": "mp4a.40.2",
                    },
                    {
                        "format_id": "dash-video_720",
                        "ext": "mp4",
                        "vcodec": "avc1.4d401f",
                        "acodec": "none",
                        "width": 1280,
                        "height": 720,
                    },
                ],
            },
            {
                "id": "img_2",
                "title": "Photo 2",
                "formats": [],
                "duration": None,
            },
            {
                "id": "vid_3",
                "display_id": "post_abc",
                "title": "Clip 3",
                "duration": 20,
                "extractor": "reddit",
                "extractor_key": "Reddit",
                "formats": [
                    {
                        "format_id": "dash-audio_0",
                        "ext": "m4a",
                        "vcodec": "none",
                        "acodec": "mp4a.40.2",
                    },
                    {
                        "format_id": "dash-video_1080",
                        "ext": "mp4",
                        "vcodec": "avc1.640028",
                        "acodec": "none",
                        "width": 1920,
                        "height": 1080,
                    },
                ],
            },
        ],
    }

    with patch.object(service, "_extract_playlist_info_or_raise_api_error", return_value=playlist_info):
        meta = service.get_playlist_metadata("https://www.reddit.com/r/videos/comments/post_abc/gallery/")

    assert meta.total_count == 2
    assert meta.items[0].title == "Clip 1"
    assert meta.items[0].webpage_url == "https://www.reddit.com/comments/post_abc"
    assert meta.items[1].title == "Clip 3"
    assert meta.items[1].webpage_url == "https://www.reddit.com/comments/post_abc"


def test_reddit_single_video_rejected_by_playlist_endpoint() -> None:
    service = MediaService()
    single_video_info = {
        "id": "gyh95hiqc0b11",
        "title": "Single Reddit Video",
        "extractor": "reddit",
        "formats": [{"format_id": "dash-video_720", "ext": "mp4"}],
    }

    with patch("app.services.media_service.YoutubeDL") as mock_ydl_cls:
        mock_ydl = MagicMock()
        mock_ydl.extract_info.return_value = single_video_info
        mock_ydl_cls.return_value.__enter__.return_value = mock_ydl
        with pytest.raises(APIError) as exc_info:
            service.get_playlist_metadata("https://www.reddit.com/r/aww/comments/90bu6w/single/")

    assert exc_info.value.code == "NOT_A_PLAYLIST"
    assert exc_info.value.status_code == 422


# ==============================================================================
# 9. END-TO-END DOWNLOAD JOB FLOW
# ==============================================================================


def test_reddit_download_job_creation(client: TestClient) -> None:
    mock_info = {
        "id": "gyh95hiqc0b11",
        "title": "Heat index was 110 degrees",
        "uploader": "FootLoosePickleJuice",
        "duration": 14,
        "extractor": "reddit",
        "extractor_key": "Reddit",
        "webpage_url": "https://www.reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/",
        "formats": [
            {
                "format_id": "dash-audio_0",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "protocol": "https",
                "abr": 128.0,
            },
            {
                "format_id": "dash-video_720",
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "protocol": "https",
                "width": 1280,
                "height": 720,
                "tbr": 2400.0,
            },
        ],
    }

    with patch("app.services.media_service.MediaService._extract_info_or_raise_api_error", return_value=mock_info):
        response = client.post(
            "/media/download",
            json={
                "url": "https://www.reddit.com/r/aww/comments/90bu6w/heat_index_was_110_degrees/",
                "media_type": "video",
                "quality_height": 720,
            },
        )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "job_id" in data["data"]
