from __future__ import annotations

from urllib.parse import urlparse


def detect_platform_from_url(url: str) -> str:
    hostname = (urlparse(url).hostname or "").casefold()

    if hostname in {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}:
        return "youtube"
    if hostname.endswith("tiktok.com"):
        return "tiktok"
    if hostname in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"}:
        return "twitter"
    if hostname.endswith("instagram.com"):
        return "instagram"
    if hostname.endswith("facebook.com"):
        return "facebook"
    if hostname.endswith("vimeo.com"):
        return "vimeo"

    return "unknown"