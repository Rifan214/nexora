from __future__ import annotations

from urllib.parse import urlsplit

RULE34VIDEO_HOST = "rule34video.com"
RULE34VIDEO_WWW_HOST = "www.rule34video.com"
RULE34VIDEO_HOSTS = frozenset({RULE34VIDEO_HOST, RULE34VIDEO_WWW_HOST})

ALLOWED_CDN_DOMAIN = "boomio-cdn.com"
ALLOWED_MEDIA_HOSTS = frozenset({RULE34VIDEO_HOST, RULE34VIDEO_WWW_HOST})

# Modern browser User-Agent strictly targeted to Rule34Video and its CDN
RULE34VIDEO_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)
RULE34VIDEO_REFERER = "https://rule34video.com/"

SUPPORTED_VIDEO_EXTENSIONS = frozenset({"mp4", "webm", "mkv"})

MAX_REDIRECT_HOPS = 5

DEFAULT_CONNECT_TIMEOUT = 10.0
DEFAULT_READ_TIMEOUT = 15.0
DEFAULT_WRITE_TIMEOUT = 10.0
DEFAULT_POOL_TIMEOUT = 15.0


def is_rule34video_host(hostname: str | None) -> bool:
    """Return whether a hostname exactly matches an approved Rule34Video origin."""
    if not hostname:
        return False
    return hostname.casefold() in RULE34VIDEO_HOSTS


def is_allowed_rule34video_cdn_host(hostname: str | None) -> bool:
    """Return whether a hostname is an authorized boomio-cdn media host."""
    if not hostname:
        return False
    h = hostname.casefold()
    return h == ALLOWED_CDN_DOMAIN or h.endswith(f".{ALLOWED_CDN_DOMAIN}")


def is_rule34video_targeted_host(hostname: str | None) -> bool:
    """Return whether a hostname is an authorized origin or media CDN host."""
    if not hostname:
        return False
    h = hostname.casefold()
    return h in RULE34VIDEO_HOSTS or is_allowed_rule34video_cdn_host(h)


def is_rule34video_targeted_url(url: str) -> bool:
    """Return whether a URL targets an approved Rule34Video origin or CDN domain."""
    try:
        parsed = urlsplit(url)
    except Exception:
        return False
    return is_rule34video_targeted_host(parsed.hostname)

