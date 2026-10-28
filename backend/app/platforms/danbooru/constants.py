from __future__ import annotations

from urllib.parse import urlsplit

DANBOORU_HOST = "danbooru.donmai.us"
DANBOORU_CDN_HOST = "cdn.donmai.us"
DANBOORU_TARGETED_HOSTS = frozenset({DANBOORU_HOST, DANBOORU_CDN_HOST})

# The approved User-Agent strictly targeted to Danbooru and its media CDN
DANBOORU_USER_AGENT = "curl/8.18.0"

DANBOORU_POST_API_TEMPLATE = "https://danbooru.donmai.us/posts/{post_id}.json"

ALLOWED_MEDIA_HOSTS = frozenset({DANBOORU_CDN_HOST, DANBOORU_HOST})
SUPPORTED_VIDEO_EXTENSIONS = frozenset({"mp4", "webm", "mkv", "mov"})

DEFAULT_CONNECT_TIMEOUT = 10.0
DEFAULT_READ_TIMEOUT = 15.0
DEFAULT_WRITE_TIMEOUT = 10.0
DEFAULT_POOL_TIMEOUT = 15.0


def is_danbooru_targeted_host(hostname: str | None) -> bool:
    """Return whether a hostname exactly matches the approved Danbooru origin or media CDN."""
    if not hostname:
        return False
    return hostname.casefold() in DANBOORU_TARGETED_HOSTS


def is_danbooru_targeted_url(url: str) -> bool:
    """Return whether a URL targets the approved Danbooru origin or media CDN."""
    try:
        parsed = urlsplit(url)
    except Exception:
        return False
    return is_danbooru_targeted_host(parsed.hostname)
