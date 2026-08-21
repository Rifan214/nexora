from __future__ import annotations

import re
from urllib.parse import urlparse, urlsplit, urlunsplit


_X_HOSTNAMES = frozenset({"x.com", "www.x.com", "twitter.com", "www.twitter.com"})
_X_STATUS_PATH = re.compile(r"^/[A-Za-z0-9_]+/status/[0-9]+/?$")
_INSTAGRAM_HOSTNAMES = frozenset({"instagram.com", "www.instagram.com", "m.instagram.com"})
_INSTAGRAM_MEDIA_PATH = re.compile(r"^(?:/[A-Za-z0-9_.]+)?/(?:p|tv|reels?)/[A-Za-z0-9_-]+/?$")


def detect_platform_from_url(url: str) -> str:
    hostname = (urlparse(url).hostname or "").casefold()

    if hostname in {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}:
        return "youtube"
    if hostname.endswith("tiktok.com"):
        return "tiktok"
    if hostname in _X_HOSTNAMES:
        return "twitter"
    if hostname in _INSTAGRAM_HOSTNAMES or hostname.endswith(".instagram.com"):
        return "instagram"
    if hostname.endswith("facebook.com"):
        return "facebook"
    if hostname.endswith("vimeo.com"):
        return "vimeo"

    return "unknown"


def is_x_status_url(url: str) -> bool:
    """Return whether a URL addresses a public X/Twitter status post."""
    parsed = urlsplit(url)
    hostname = (parsed.hostname or "").casefold()
    return hostname in _X_HOSTNAMES and _X_STATUS_PATH.fullmatch(parsed.path) is not None


def is_instagram_media_url(url: str) -> bool:
    """Return whether a URL addresses a supported Instagram Reel, Post, or TV item."""
    parsed = urlsplit(url)
    hostname = (parsed.hostname or "").casefold()
    is_ig_host = hostname in _INSTAGRAM_HOSTNAMES or hostname.endswith(".instagram.com")
    return is_ig_host and _INSTAGRAM_MEDIA_PATH.fullmatch(parsed.path) is not None


def normalize_media_url(url: str) -> str:
    """Normalize equivalent supported media URLs into stable cache keys."""
    parsed = urlsplit(url)
    hostname = (parsed.hostname or "").casefold()

    if hostname in _X_HOSTNAMES:
        # X and Twitter status URLs identify the same post. A single canonical host
        # prevents duplicate cache entries and lets retries use the proven source.
        return urlunsplit((parsed.scheme.casefold(), "x.com", parsed.path, parsed.query, ""))

    if hostname in _INSTAGRAM_HOSTNAMES or hostname.endswith(".instagram.com"):
        # Strip tracking query parameters (e.g. ?igsh=...) and use canonical host
        # so repeated requests for the same post share metadata and snapshots.
        match = _INSTAGRAM_MEDIA_PATH.fullmatch(parsed.path)
        if match is not None:
            raw_path = parsed.path.strip("/")
            parts = raw_path.split("/")
            media_id = parts[-1]
            kind = parts[-2].casefold()
            canonical_kind = "reel" if kind in ("reel", "reels") else "p"
            canonical_path = f"/{canonical_kind}/{media_id}/"
        else:
            canonical_path = parsed.path.rstrip("/") + "/"
        return urlunsplit(("https", "www.instagram.com", canonical_path, "", ""))

    return url
