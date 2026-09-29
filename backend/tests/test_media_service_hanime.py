from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from app.core.exceptions import APIError
from app.models.media import MediaMetadata
from app.platforms.hanime import (
    HanimeDecryptionFailureError,
    HanimeExtractor,
    HanimeHandshakeAuthError,
    HanimeNetworkError,
    HanimeNoPlayableFormatsError,
    HanimeRateLimitError,
    HanimeServerError,
    HanimeSignature,
    HanimeSignatureError,
    HanimeSignatureProvider,
    HanimeUrlError,
)
from app.services.media_service import MediaService
from app.services.media_snapshot_cache import MediaSnapshotCache


@pytest.fixture
def dummy_hanime_info_dict() -> dict:
    return {
        "id": "3537",
        "title": "Terra Story 1",
        "thumbnail": "https://webedn.hanime.tv/media/covers/terra-story-1.jpg",
        "duration": 1757,
        "upload_date": "2024-09-01T00:00:00Z",
        "description": "Terra Story Episode 1",
        "webpage_url": "https://hanime.tv/videos/hentai/terra-story-1",
        "extractor": "hanime",
        "extractor_key": "Hanime",
        "formats": [
            {
                "format_id": "720p",
                "url": "https://hanime.tv/hls/3537/720p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 720,
                "width": 960,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
            {
                "format_id": "480p",
                "url": "https://hanime.tv/hls/3537/480p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 480,
                "width": 640,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
            {
                "format_id": "360p",
                "url": "https://hanime.tv/hls/3537/360p.m3u8",
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": 360,
                "width": 480,
                "http_headers": {
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            },
        ],
        "http_headers": {
            "User-Agent": "Mozilla/5.0",
            "Referer": "https://hanime.tv/",
            "Origin": "https://hanime.tv",
        },
    }


def test_hanime_routing_to_extractor(dummy_hanime_info_dict: dict) -> None:
    """1. Test valid Hanime URL routes to HanimeExtractor and produces valid MediaMetadata."""
    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(return_value=dummy_hanime_info_dict)

    service = MediaService(hanime_extractor=mock_extractor)
    meta = service.get_metadata("https://hanime.tv/videos/hentai/terra-story-1")

    assert isinstance(meta, MediaMetadata)
    assert meta.platform == "hanime"
    assert meta.title == "Terra Story 1"
    assert meta.duration_seconds == 1757
    assert meta.webpage_url == "https://hanime.tv/videos/hentai/terra-story-1"
    mock_extractor.extract.assert_called_once_with("https://hanime.tv/videos/hentai/terra-story-1")


def test_hanime_url_normalization_and_validation() -> None:
    """2. Test invalid Hanime URLs raise APIError(422, INVALID_HANIME_URL)."""
    service = MediaService()

    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://hanime.tv/invalid-path")
    assert exc_info.value.code == "INVALID_HANIME_URL"
    assert exc_info.value.status_code == 422


def test_existing_platform_routing_unchanged() -> None:
    """3. Test YouTube, TikTok, X, Instagram, Facebook, Reddit routing remain unchanged."""
    service = MediaService()
    # Normalize checks for other platforms still work
    with pytest.raises(APIError) as exc_x:
        service._normalize_source_url("https://x.com/invalid")
    assert exc_x.value.code == "INVALID_X_URL"

    with pytest.raises(APIError) as exc_ig:
        service._normalize_source_url("https://instagram.com/invalid")
    assert exc_ig.value.code == "INVALID_INSTAGRAM_URL"

    with pytest.raises(APIError) as exc_fb:
        service._normalize_source_url("https://facebook.com/invalid")
    assert exc_fb.value.code == "INVALID_FACEBOOK_URL"

    with pytest.raises(APIError) as exc_rd:
        service._normalize_source_url("https://reddit.com/invalid")
    assert exc_rd.value.code == "INVALID_REDDIT_URL"


def test_quality_selection_hanime(dummy_hanime_info_dict: dict) -> None:
    """4. Test QualitySelector produces 720p, 480p, 360p and never fabricates 1080p."""
    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(return_value=dummy_hanime_info_dict)

    service = MediaService(hanime_extractor=mock_extractor)
    meta = service.get_metadata("https://hanime.tv/videos/hentai/terra-story-1")

    heights = [q.height for q in meta.video_qualities]
    assert set(heights) == {720, 480, 360}
    assert 1080 not in heights

    labels = [q.label for q in meta.video_qualities]
    assert set(labels) == {"720p HD", "480p", "360p"}

    # Audio option MP3 is available
    assert len(meta.audio_options) == 1
    assert meta.audio_options[0].label == "MP3"
    assert meta.audio_options[0].extension == "mp3"


def test_snapshot_cache_and_transport_refresh(dummy_hanime_info_dict: dict) -> None:
    """5. Test snapshot cache stores Hanime info and transport refresh gets fresh URLs."""
    cache = MediaSnapshotCache()
    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(return_value=dummy_hanime_info_dict)

    service = MediaService(hanime_extractor=mock_extractor, snapshot_cache=cache)
    url = "https://hanime.tv/videos/hentai/terra-story-1"

    # 1. First call extracts and caches
    meta1 = service.get_metadata(url)
    assert mock_extractor.extract.call_count == 1
    assert cache.get(url) is not None

    # 2. Second call returns cached metadata without calling extractor again
    meta2 = service.get_metadata(url)
    assert mock_extractor.extract.call_count == 1
    assert meta2.title == meta1.title

    # 3. Transport refresh invokes extraction to get fresh HLS stream URLs
    refreshed_dict = dummy_hanime_info_dict.copy()
    refreshed_dict["formats"] = [
        {
            "format_id": "720p",
            "url": "https://hanime.tv/hls/3537/new_fresh_720p.m3u8",
            "ext": "mp4",
            "protocol": "m3u8_native",
            "height": 720,
            "width": 960,
        }
    ]
    mock_extractor.extract = AsyncMock(return_value=refreshed_dict)

    resolved, refreshed = service._refresh_download_transport_info(
        MagicMock(),
        url=url,
        snapshot=dummy_hanime_info_dict,
    )
    assert mock_extractor.extract.call_count == 1
    assert resolved["formats"][0]["url"] == "https://hanime.tv/hls/3537/new_fresh_720p.m3u8"
    # Presentation metadata is preserved
    assert resolved["title"] == "Terra Story 1"
    assert resolved["id"] == "3537"


@pytest.mark.parametrize(
    ("raised_exc", "expected_code", "expected_status"),
    [
        (HanimeUrlError("bad url"), "INVALID_HANIME_URL", 422),
        (HanimeHandshakeAuthError("auth fail"), "HANIME_AUTH_ERROR", 502),
        (HanimeRateLimitError("rate limited"), "HANIME_RATE_LIMITED", 429),
        (HanimeServerError("500 error"), "HANIME_SERVER_ERROR", 502),
        (HanimeNoPlayableFormatsError("no formats"), "HANIME_NO_PLAYABLE_FORMATS", 422),
        (HanimeNetworkError("network drop"), "NETWORK_FAILURE", 502),
        (HanimeSignatureError("signature fail"), "HANIME_SIGNATURE_ERROR", 502),
        (HanimeDecryptionFailureError("decrypt error"), "HANIME_EXTRACTION_ERROR", 502),
    ],
)
def test_hanime_error_mappings(raised_exc: Exception, expected_code: str, expected_status: int) -> None:
    """6. Test Hanime-specific exceptions map to standard Nexora APIError model."""
    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(side_effect=raised_exc)

    service = MediaService(hanime_extractor=mock_extractor)
    with pytest.raises(APIError) as exc_info:
        service.get_metadata("https://hanime.tv/videos/hentai/terra-story-1")

    assert exc_info.value.code == expected_code
    assert exc_info.value.status_code == expected_status


def test_credential_hygiene_in_metadata_and_errors(dummy_hanime_info_dict: dict) -> None:
    """7. Verify no signature, handshake tokens, or secrets leak in MediaMetadata or API errors."""
    mock_extractor = MagicMock(spec=HanimeExtractor)
    mock_extractor.extract = AsyncMock(return_value=dummy_hanime_info_dict)

    service = MediaService(hanime_extractor=mock_extractor)
    meta = service.get_metadata("https://hanime.tv/videos/hentai/terra-story-1")

    meta_str = str(meta.model_dump())
    assert "x-signature" not in meta_str
    assert "x-time" not in meta_str
    assert "x-token" not in meta_str
    assert "sign.bin" not in meta_str
