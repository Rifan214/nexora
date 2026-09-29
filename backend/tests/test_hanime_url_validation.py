from __future__ import annotations

import pytest

from app.utils.platforms import (
    detect_platform_from_url,
    is_hanime_media_url,
    normalize_media_url,
)


# ==============================================================================
# 1. VALID HANIME URL DETECTION & NORMALIZATION
# ==============================================================================

@pytest.mark.parametrize(
    ("raw_url", "expected_normalized"),
    [
        (
            "https://hanime.tv/videos/hentai/terra-story-1",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            "https://www.hanime.tv/videos/hentai/terra-story-1",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            "https://hanime.tv/videos/hentai/terra-story-1/",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            "https://WWW.HANIME.TV/videos/hentai/terra-story-1",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            "https://Hanime.TV/videos/hentai/terra-story-1/",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            "https://hanime.tv/videos/hentai/123-abc-456",
            "https://hanime.tv/videos/hentai/123-abc-456",
        ),
        (
            "https://hanime.tv/videos/hentai/kanojo-wa-dare-to-demo-sex-suru-1",
            "https://hanime.tv/videos/hentai/kanojo-wa-dare-to-demo-sex-suru-1",
        ),
        (
            # Case preservation for slug
            "https://WWW.HANIME.TV/videos/hentai/Terra-Story-1/",
            "https://hanime.tv/videos/hentai/Terra-Story-1",
        ),
        (
            # Strips utm tracking parameters
            "https://hanime.tv/videos/hentai/terra-story-1?utm_source=twitter&utm_medium=social&utm_campaign=spring",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            # Strips ref and share_id tracking parameters
            "https://hanime.tv/videos/hentai/terra-story-1?ref=feed&share_id=abc123xyz",
            "https://hanime.tv/videos/hentai/terra-story-1",
        ),
        (
            # Preserves non-tracking query parameters
            "https://hanime.tv/videos/hentai/terra-story-1?playlist_id=99",
            "https://hanime.tv/videos/hentai/terra-story-1?playlist_id=99",
        ),
    ],
)
def test_valid_hanime_url_detection_and_normalization(raw_url: str, expected_normalized: str) -> None:
    assert is_hanime_media_url(raw_url) is True
    assert detect_platform_from_url(raw_url) == "hanime"
    assert normalize_media_url(raw_url) == expected_normalized


# ==============================================================================
# 2. INVALID URL DETECTION (REJECTION)
# ==============================================================================

@pytest.mark.parametrize(
    "invalid_url",
    [
        # Insecure scheme (must be https)
        "http://hanime.tv/videos/hentai/test",
        "http://www.hanime.tv/videos/hentai/terra-story-1",
        # Root and non-media paths
        "https://hanime.tv/",
        "https://hanime.tv/videos/",
        "https://hanime.tv/videos/hentai/",
        "https://hanime.tv/videos/hentai",
        "https://hanime.tv/videos/other/test",
        "https://hanime.tv/blog/test",
        "https://hanime.tv/community",
        # Subdomain / domain hijacking & SSRF vectors
        "https://evil-hanime.tv/videos/hentai/test",
        "https://hanime.tv.evil.com/videos/hentai/test",
        "https://evil.com/?url=https://hanime.tv/videos/hentai/test",
        "https://not-hanime.tv/videos/hentai/test",
        # Localhost and internal IP variants
        "https://localhost/videos/hentai/test",
        "https://127.0.0.1/videos/hentai/test",
        "https://192.168.1.1/videos/hentai/test",
        "https://[::1]/videos/hentai/test",
        # Malformed strings
        "not-a-valid-url",
        "hanime.tv/videos/hentai/test",
        "",
        "   ",
        "https:///videos/hentai/test",
    ],
)
def test_invalid_hanime_urls_are_rejected(invalid_url: str) -> None:
    assert is_hanime_media_url(invalid_url) is False
    assert detect_platform_from_url(invalid_url) != "hanime"


# ==============================================================================
# 3. EXISTING PLATFORMS REGRESSION AUDIT
# ==============================================================================

@pytest.mark.parametrize(
    ("url", "expected_platform"),
    [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "youtube"),
        ("https://youtu.be/dQw4w9WgXcQ", "youtube"),
        ("https://www.tiktok.com/@user/video/7123456789012345678", "tiktok"),
        ("https://x.com/user/status/1800000000000000000", "twitter"),
        ("https://twitter.com/user/status/1800000000000000000", "twitter"),
        ("https://www.instagram.com/reel/C1234567890/", "instagram"),
        ("https://www.facebook.com/watch/?v=1234567890", "facebook"),
        ("https://www.reddit.com/r/videos/comments/123456/title/", "reddit"),
        ("https://vimeo.com/123456789", "vimeo"),
    ],
)
def test_existing_platform_detection_unaffected(url: str, expected_platform: str) -> None:
    assert detect_platform_from_url(url) == expected_platform
    assert is_hanime_media_url(url) is False
