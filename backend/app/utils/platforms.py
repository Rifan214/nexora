from __future__ import annotations

import re
from urllib.parse import urlparse, urlsplit, urlunsplit


_X_HOSTNAMES = frozenset({"x.com", "www.x.com", "twitter.com", "www.twitter.com"})
_X_STATUS_PATH = re.compile(r"^/[A-Za-z0-9_]+/status/[0-9]+/?$")
_INSTAGRAM_HOSTNAMES = frozenset({"instagram.com", "www.instagram.com", "m.instagram.com"})
_INSTAGRAM_MEDIA_PATH = re.compile(r"^(?:/[A-Za-z0-9_.]+)?/(?:p|tv|reels?)/[A-Za-z0-9_-]+/?$")
_FACEBOOK_HOSTNAMES = frozenset({"facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com", "l.facebook.com", "fb.watch"})
_FB_WATCH_PATH = re.compile(r"^/[A-Za-z0-9_-]+/?$")
_FACEBOOK_MEDIA_PATH_PATTERNS = (
    re.compile(r"^/(?:reel|reels)/[A-Za-z0-9_-]+/?$"),
    re.compile(r"^(?:/[A-Za-z0-9_.]+)?/videos/(?:[A-Za-z0-9_.]+/)?(?:\d+|pfbid[A-Za-z0-9]+)/?$"),
    re.compile(r"^(?:/[A-Za-z0-9_.]+)?/posts/(?:\d+|pfbid[A-Za-z0-9]+)/?$"),
    re.compile(r"^/share/(?:v|r)/[A-Za-z0-9_-]+/?$"),
    re.compile(r"^/watch(?:/live)?/?$"),
    re.compile(r"^/(?:video|story|permalink)\.php$"),
    re.compile(r"^/groups/[^/]+/(?:permalink|posts)/(?:[\da-f]+/)?(?:\d+|pfbid[A-Za-z0-9]+)/?$"),
)
_FACEBOOK_TRACKING_PREFIXES = (
    "fbclid",
    "mibextid",
    "ref",
    "__cft__",
    "__tn__",
    "fref",
    "set",
    "notif_t",
    "paipv",
    "rdid",
)
_REDDIT_HOSTNAMES = frozenset(
    {
        "reddit.com",
        "www.reddit.com",
        "old.reddit.com",
        "new.reddit.com",
        "sh.reddit.com",
        "m.reddit.com",
        "nm.reddit.com",
        "np.reddit.com",
        "www.redditmedia.com",
        "redditmedia.com",
        "redd.it",
        "v.redd.it",
    }
)
_REDDIT_SHORT_HOSTNAMES = frozenset({"redd.it", "v.redd.it"})
_REDDIT_SHORT_PATH = re.compile(r"^/[A-Za-z0-9_-]+/?$")
_REDDIT_MEDIA_PATH_PATTERNS = (
    re.compile(r"^/r/[^/]+/comments/[A-Za-z0-9_-]+(?:/[^/?#&]+)?/?$"),
    re.compile(r"^/comments/[A-Za-z0-9_-]+(?:/[^/?#&]+)?/?$"),
    re.compile(r"^/(?:user|u)/[^/]+/comments/[A-Za-z0-9_-]+(?:/[^/?#&]+)?/?$"),
    re.compile(r"^/r/[^/]+/s/[A-Za-z0-9_-]+/?$"),
)
_REDDIT_TRACKING_PREFIXES = (
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_name",
    "utm_term",
    "utm_content",
    "context",
    "ref",
    "ref_source",
    "rdt",
    "share_id",
)


def _is_facebook_tracking_param(key: str) -> bool:
    k = key.casefold()
    return any(
        k == prefix or k.startswith(f"{prefix}[") or k.startswith(f"{prefix}_")
        for prefix in _FACEBOOK_TRACKING_PREFIXES
    )


def _is_reddit_tracking_param(key: str) -> bool:
    k = key.casefold()
    return any(
        k == prefix or k.startswith(f"{prefix}_")
        for prefix in _REDDIT_TRACKING_PREFIXES
    )


_HANIME_HOSTNAMES = frozenset({"hanime.tv", "www.hanime.tv"})
_HANIME_MEDIA_PATH = re.compile(r"^/videos/hentai/([A-Za-z0-9_-]+)/?$")
_HANIME_TRACKING_PREFIXES = (
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_name",
    "utm_term",
    "utm_content",
    "ref",
    "share_id",
)


def _is_hanime_tracking_param(key: str) -> bool:
    k = key.casefold()
    return any(
        k == prefix or k.startswith(f"{prefix}_")
        for prefix in _HANIME_TRACKING_PREFIXES
    )


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
    if hostname in _FACEBOOK_HOSTNAMES or hostname.endswith(".facebook.com") or hostname == "fb.watch":
        return "facebook"
    if hostname in _REDDIT_HOSTNAMES or hostname.endswith(".reddit.com") or hostname.endswith(".redditmedia.com"):
        return "reddit"
    if is_hanime_media_url(url):
        return "hanime"
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


def is_facebook_media_url(url: str) -> bool:
    """Return whether a URL addresses a supported Facebook Watch, Reel, or Video item."""
    parsed = urlsplit(url)
    hostname = (parsed.hostname or "").casefold()
    is_fb_host = hostname in _FACEBOOK_HOSTNAMES or hostname.endswith(".facebook.com")
    if not is_fb_host:
        return False

    if hostname == "fb.watch":
        return _FB_WATCH_PATH.fullmatch(parsed.path) is not None and parsed.path.strip("/") != ""

    path = parsed.path
    if any(pattern.fullmatch(path) is not None for pattern in _FACEBOOK_MEDIA_PATH_PATTERNS):
        if path.rstrip("/") in ("/watch", "/watch/live", "/video.php", "/story.php", "/permalink.php"):
            from urllib.parse import parse_qs

            qs = parse_qs(parsed.query)
            return any(k in qs for k in ("v", "video_id", "story_fbid", "id"))
        return True

    return False


def is_reddit_media_url(url: str) -> bool:
    """Return whether a URL addresses a supported Reddit post, comment, or video item."""
    parsed = urlsplit(url)
    hostname = (parsed.hostname or "").casefold()
    is_reddit_host = (
        hostname in _REDDIT_HOSTNAMES
        or hostname.endswith(".reddit.com")
        or hostname.endswith(".redditmedia.com")
    )
    if not is_reddit_host:
        return False

    if hostname in _REDDIT_SHORT_HOSTNAMES:
        return _REDDIT_SHORT_PATH.fullmatch(parsed.path) is not None and parsed.path.strip("/") != ""

    path = parsed.path
    return any(pattern.fullmatch(path) is not None for pattern in _REDDIT_MEDIA_PATH_PATTERNS)


def is_hanime_media_url(url: str) -> bool:
    """Return whether a URL addresses a supported Hanime video item."""
    try:
        parsed = urlsplit(url)
    except Exception:
        return False
    if parsed.scheme.casefold() != "https":
        return False
    hostname = (parsed.hostname or "").casefold()
    if hostname not in _HANIME_HOSTNAMES:
        return False
    return _HANIME_MEDIA_PATH.fullmatch(parsed.path) is not None


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

    if hostname == "fb.watch":
        return urlunsplit(("https", "fb.watch", parsed.path.rstrip("/") + "/", "", ""))

    if hostname in _FACEBOOK_HOSTNAMES or hostname.endswith(".facebook.com"):
        from urllib.parse import parse_qs, urlencode

        qs = parse_qs(parsed.query, keep_blank_values=False)
        cleaned_query = {
            k: v for k, v in qs.items()
            if not _is_facebook_tracking_param(k)
        }
        encoded_query = urlencode(cleaned_query, doseq=True) if cleaned_query else ""
        canonical_path = parsed.path
        if canonical_path.startswith(("/reel/", "/reels/")):
            parts = canonical_path.strip("/").split("/")
            reel_id = parts[-1]
            canonical_path = f"/reel/{reel_id}/"
            encoded_query = ""
        elif canonical_path.rstrip("/") in ("/watch", "/watch/live"):
            canonical_path = "/watch/"

        return urlunsplit(("https", "www.facebook.com", canonical_path, encoded_query, ""))

    if hostname in _REDDIT_SHORT_HOSTNAMES:
        return urlunsplit(("https", hostname, parsed.path.rstrip("/") + "/", "", ""))

    if hostname in _REDDIT_HOSTNAMES or hostname.endswith(".reddit.com") or hostname.endswith(".redditmedia.com"):
        from urllib.parse import parse_qs, urlencode

        qs = parse_qs(parsed.query, keep_blank_values=False)
        cleaned_query = {
            k: v for k, v in qs.items()
            if not _is_reddit_tracking_param(k)
        }
        encoded_query = urlencode(cleaned_query, doseq=True) if cleaned_query else ""
        canonical_path = parsed.path.rstrip("/") + "/"
        return urlunsplit(("https", "www.reddit.com", canonical_path, encoded_query, ""))

    if hostname in _HANIME_HOSTNAMES:
        match = _HANIME_MEDIA_PATH.fullmatch(parsed.path)
        if match is not None:
            slug = match.group(1)
            canonical_path = f"/videos/hentai/{slug}"
            from urllib.parse import parse_qs, urlencode

            qs = parse_qs(parsed.query, keep_blank_values=False)
            cleaned_query = {
                k: v for k, v in qs.items()
                if not _is_hanime_tracking_param(k)
            }
            encoded_query = urlencode(cleaned_query, doseq=True) if cleaned_query else ""
            return urlunsplit(("https", "hanime.tv", canonical_path, encoded_query, ""))

        canonical_path = parsed.path.rstrip("/")
        return urlunsplit(("https", "hanime.tv", canonical_path, parsed.query, ""))

    return url
