from __future__ import annotations

import html
import json
import logging
import re
from typing import Any
from urllib.parse import urlsplit

from app.platforms.rule34video.constants import (
    RULE34VIDEO_HOST,
    RULE34VIDEO_REFERER,
    RULE34VIDEO_USER_AGENT,
    is_rule34video_host,
)
from app.platforms.rule34video.exceptions import (
    Rule34VideoMalformedResponseError,
    Rule34VideoSecurityError,
    Rule34VideoUnsupportedMediaError,
    Rule34VideoUrlError,
)
from app.platforms.rule34video.http_client import (
    HttpRule34VideoClient,
    sanitize_url_for_logging,
    validate_url_security,
)

logger = logging.getLogger(__name__)

_RULE34VIDEO_MEDIA_PATH = re.compile(r"^/videos?/(?P<video_id>[1-9][0-9]*)(?:/[^/?#&]+)?/?$")
_DOWNLOAD_ANCHOR_PATTERN = re.compile(
    r'<a[^>]+href="(?P<url>[^"]+download=true[^"]*)"[^>]*>(?P<content>.*?)</a>',
    re.DOTALL | re.IGNORECASE,
)
_QUALITY_TEXT_PATTERN = re.compile(
    r"(?:(?P<ext>MP4|WEBM|MKV)\s+)?(?P<quality>\d+)p",
    re.IGNORECASE,
)
_FILESIZE_BADGE_PATTERN = re.compile(
    r'<span[^>]*class=["\'][^"\']*vp-sheet__meta[^"\']*["\'][^>]*>(?P<size>[^<]+)</span>',
    re.IGNORECASE,
)
_FILESIZE_VALUE_PATTERN = re.compile(
    r"(?P<num>\d+(?:\.\d+)?)\s*(?P<unit>GB|MB|KB|B)\b",
    re.IGNORECASE,
)
_ISO_DURATION_PATTERN = re.compile(
    r"^P(?:T(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?)?$",
    re.IGNORECASE,
)


def extract_rule34video_video_id(url: str) -> int | None:
    """Extract numeric video ID from a Rule34Video URL."""
    try:
        parsed = urlsplit(url)
    except Exception:
        return None

    if (parsed.scheme or "").casefold() not in {"http", "https"}:
        return None

    hostname = (parsed.hostname or "").casefold()
    if not is_rule34video_host(hostname):
        return None

    match = _RULE34VIDEO_MEDIA_PATH.fullmatch(parsed.path)
    if not match:
        return None

    try:
        video_id = int(match.group("video_id"))
        return video_id if video_id > 0 else None
    except (ValueError, TypeError):
        return None


def parse_iso8601_duration(duration_str: str | None) -> int | None:
    """Parse ISO 8601 duration string (e.g. PT0H1M52S or PT112S) to integer seconds."""
    if not duration_str:
        return None
    match = _ISO_DURATION_PATTERN.match(duration_str.strip())
    if not match:
        return None
    hours = int(match.group("hours") or 0)
    minutes = int(match.group("minutes") or 0)
    seconds = int(match.group("seconds") or 0)
    total = hours * 3600 + minutes * 60 + seconds
    return total if total > 0 else None


def parse_clock_duration(clock_str: str | None) -> int | None:
    """Parse clock format duration string (e.g. '1:52' or '01:02:03') to integer seconds."""
    if not clock_str:
        return None
    cleaned = clock_str.strip()
    parts = cleaned.split(":")
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return None

    if len(nums) == 1:
        return nums[0] if nums[0] > 0 else None
    elif len(nums) == 2:
        return nums[0] * 60 + nums[1]
    elif len(nums) == 3:
        return nums[0] * 3600 + nums[1] * 60 + nums[2]
    return None


def parse_filesize_bytes(size_str: str | None) -> int | None:
    """Parse human-readable filesize string into integer bytes."""
    if not size_str:
        return None
    match = _FILESIZE_VALUE_PATTERN.search(size_str.strip())
    if not match:
        return None
    num = float(match.group("num"))
    unit = match.group("unit").upper()
    if unit == "GB":
        return int(num * 1024 * 1024 * 1024)
    elif unit == "MB":
        return int(num * 1024 * 1024)
    elif unit == "KB":
        return int(num * 1024)
    elif unit == "B":
        return int(num)
    return None


class Rule34VideoExtractor:
    """Extracts structured metadata and progressive media formats from Rule34Video."""

    def __init__(self, *, http_client: HttpRule34VideoClient | None = None) -> None:
        self._http_client = http_client or HttpRule34VideoClient()

    async def extract(self, url: str) -> dict[str, Any]:
        """Extract metadata and media format dictionary from a Rule34Video URL.

        Args:
            url: Canonical or standard Rule34Video post URL.

        Returns:
            yt-dlp compatible info dictionary with progressive formats.

        Raises:
            Rule34VideoUrlError: If URL or video ID is invalid.
            Rule34VideoNotFoundError: If content returns 404.
            Rule34VideoUnsupportedMediaError: If page has no playable video streams.
            Rule34VideoSecurityError: If media URL origin is untrusted.
        """
        video_id = extract_rule34video_video_id(url)
        if video_id is None:
            raise Rule34VideoUrlError(
                f"Invalid or unsupported Rule34Video URL: '{url}'. "
                "Expected format: https://rule34video.com/video/<id>/<slug>/"
            )

        webpage = await self._http_client.fetch_html(url)
        if not webpage or not webpage.strip():
            raise Rule34VideoMalformedResponseError(
                f"Empty response received from Rule34Video for video {video_id}."
            )

        # 1. Parse JSON-LD metadata
        json_ld = self._parse_json_ld(webpage)

        # 2. Extract title, description, thumbnail, duration, metrics
        title = self._resolve_title(webpage, json_ld, video_id=video_id)
        description = self._resolve_description(webpage, json_ld)
        thumbnail = self._resolve_thumbnail(webpage, json_ld)
        duration = self._resolve_duration(webpage, json_ld)
        view_count, like_count = self._resolve_metrics(webpage, json_ld)
        upload_date = self._resolve_upload_date(json_ld)
        uploader = self._resolve_uploader(webpage)

        # 3. Extract formats from download anchors (primary) and flashvars (secondary)
        anchor_formats = self._parse_download_anchors(webpage)
        flashvar_formats = self._parse_flashvars(webpage)

        # Deduplicate formats by height/quality (prefer anchor formats with explicit filesizes)
        merged_formats_by_height: dict[int, dict[str, Any]] = {}
        for fmt in flashvar_formats:
            h = fmt.get("height")
            if h is not None:
                merged_formats_by_height[h] = fmt

        for fmt in anchor_formats:
            h = fmt.get("height")
            if h is not None:
                merged_formats_by_height[h] = fmt

        formats = sorted(
            merged_formats_by_height.values(),
            key=lambda f: f.get("height") or 0,
            reverse=True,
        )

        if not formats:
            logger.warning("No formats extracted for Rule34Video video_id=%s", video_id)
            raise Rule34VideoUnsupportedMediaError(
                f"No downloadable video formats were found for Rule34Video {video_id}."
            )

        logger.debug(
            "Extracted %d formats for Rule34Video video_id=%s qualities=%s",
            len(formats),
            video_id,
            [f.get("format_id") for f in formats],
        )

        return {
            "id": str(video_id),
            "title": title,
            "description": description,
            "duration": duration,
            "thumbnail": thumbnail,
            "upload_date": upload_date,
            "view_count": view_count,
            "like_count": like_count,
            "uploader": uploader,
            "extractor": "rule34video",
            "extractor_key": "rule34video",
            "webpage_url": url,
            "formats": formats,
        }

    async def resolve_media_format(self, format_item: dict[str, Any]) -> dict[str, Any]:
        """Resolve a single Rule34Video format to its validated final CDN destination and exact filesize."""
        raw_url = format_item.get("url")
        if not raw_url:
            return dict(format_item)

        resolved_url, exact_filesize = await self._http_client.resolve_media_url(raw_url)
        updated = dict(format_item)
        updated["url"] = resolved_url
        if exact_filesize is not None:
            updated["filesize"] = exact_filesize
        return updated

    async def resolve_media_formats_for_selector(
        self,
        download_info: dict[str, Any],
        format_selector: str,
    ) -> dict[str, Any]:
        """Resolve format URLs for the requested format_selector before download begins."""
        info_copy = dict(download_info)
        formats = info_copy.get("formats") or []
        if not formats:
            return info_copy

        matched = any(str(fmt.get("format_id") or "") == format_selector for fmt in formats)
        updated_formats = []
        for fmt in formats:
            fmt_id = str(fmt.get("format_id") or "")
            if fmt_id == format_selector or not matched:
                resolved_fmt = await self.resolve_media_format(fmt)
                updated_formats.append(resolved_fmt)
            else:
                updated_formats.append(dict(fmt))

        info_copy["formats"] = updated_formats
        return info_copy

    def _parse_json_ld(self, html_text: str) -> dict[str, Any] | None:
        """Locate and decode VideoObject schema from JSON-LD script blocks."""
        blocks = re.findall(
            r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
            html_text,
            re.DOTALL | re.IGNORECASE,
        )
        for block in blocks:
            try:
                data = json.loads(block)
                if isinstance(data, dict) and data.get("@type") == "VideoObject":
                    return data
            except Exception:
                continue
        return None

    def _parse_download_anchors(self, html_text: str) -> list[dict[str, Any]]:
        """Extract progressive download URLs and quality metadata from sheet items."""
        formats: list[dict[str, Any]] = []

        for match in _DOWNLOAD_ANCHOR_PATTERN.finditer(html_text):
            raw_url = html.unescape(match.group("url")).strip()
            content = match.group("content")

            # Validate media URL security
            try:
                validate_url_security(raw_url, allow_cdn=True)
            except Rule34VideoSecurityError as exc:
                logger.warning(
                    "Skipping untrusted format URL %s: %s",
                    sanitize_url_for_logging(raw_url),
                    exc,
                )
                continue

            quality_match = _QUALITY_TEXT_PATTERN.search(content)
            if not quality_match:
                continue

            quality_int = int(quality_match.group("quality"))
            ext = (quality_match.group("ext") or "mp4").casefold()

            # Extract filesize badge if present as approximate filesize
            filesize_approx = None
            size_badge_match = _FILESIZE_BADGE_PATTERN.search(content)
            if size_badge_match:
                filesize_approx = parse_filesize_bytes(size_badge_match.group("size"))

            formats.append(
                {
                    "format_id": f"{quality_int}p",
                    "url": raw_url,
                    "ext": ext,
                    "height": quality_int,
                    "filesize": None,
                    "filesize_approx": filesize_approx,
                    "vcodec": "h264",
                    "acodec": "aac",
                    "protocol": "https",
                    "http_headers": {
                        "User-Agent": RULE34VIDEO_USER_AGENT,
                        "Referer": RULE34VIDEO_REFERER,
                    },
                }
            )

        return formats

    def _parse_flashvars(self, html_text: str) -> list[dict[str, Any]]:
        """Extract video streams from KVS player flashvars javascript object."""
        fv_match = re.search(r"var\s+flashvars\s*=\s*(\{.*?\});", html_text, re.DOTALL)
        if not fv_match:
            return []

        fv_text = fv_match.group(1)
        formats: list[dict[str, Any]] = []

        # flashvars format pairs: (video_url, video_url_text), (video_alt_urlN, video_alt_urlN_text)
        url_matches = re.findall(
            r"(?P<key>video_url|video_alt_url\d*)\s*:\s*'(?P<val>[^']+)'",
            fv_text,
        )
        url_dict = dict(url_matches)

        text_matches = re.findall(
            r"(?P<key>video_url_text|video_alt_url\d*_text)\s*:\s*'(?P<val>[^']+)'",
            fv_text,
        )
        text_dict = dict(text_matches)

        for url_key, stream_url in url_dict.items():
            raw_url = html.unescape(stream_url).strip()
            text_key = f"{url_key}_text"
            label = text_dict.get(text_key, "")

            try:
                validate_url_security(raw_url, allow_cdn=True)
            except Rule34VideoSecurityError as exc:
                logger.warning(
                    "Skipping untrusted flashvars URL %s: %s",
                    sanitize_url_for_logging(raw_url),
                    exc,
                )
                continue

            quality_int = None
            q_match = re.search(r"(\d+)p?", label)
            if q_match:
                quality_int = int(q_match.group(1))

            format_id = f"{quality_int}p" if quality_int else (label.lower() or "mp4")

            formats.append(
                {
                    "format_id": format_id,
                    "url": raw_url,
                    "ext": "mp4",
                    "height": quality_int,
                    "filesize": None,
                    "filesize_approx": None,
                    "vcodec": "h264",
                    "acodec": "aac",
                    "protocol": "https",
                    "http_headers": {
                        "User-Agent": RULE34VIDEO_USER_AGENT,
                        "Referer": RULE34VIDEO_REFERER,
                    },
                }
            )

        return formats

    def _resolve_title(
        self,
        html_text: str,
        json_ld: dict[str, Any] | None,
        *,
        video_id: int,
    ) -> str:
        if json_ld and json_ld.get("name"):
            return str(json_ld["name"]).strip()

        fv_title = re.search(r"video_title\s*:\s*'([^']+)'", html_text)
        if fv_title:
            return html.unescape(fv_title.group(1)).strip()

        og_title = re.search(
            r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']',
            html_text,
            re.IGNORECASE,
        )
        if og_title:
            return html.unescape(og_title.group(1)).strip()

        title_tag = re.search(r"<title>([^<]+)</title>", html_text, re.IGNORECASE)
        if title_tag:
            raw = html.unescape(title_tag.group(1)).strip()
            # Clean site suffixes
            cleaned = re.sub(r"\s*-\s*Rule34Video.*$", "", raw, flags=re.IGNORECASE)
            if cleaned:
                return cleaned

        return f"Rule34Video {video_id}"

    def _resolve_description(
        self,
        html_text: str,
        json_ld: dict[str, Any] | None,
    ) -> str:
        if json_ld and json_ld.get("description"):
            return str(json_ld["description"]).strip()

        og_desc = re.search(
            r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']',
            html_text,
            re.IGNORECASE,
        )
        if og_desc:
            return html.unescape(og_desc.group(1)).strip()

        return ""

    def _resolve_thumbnail(
        self,
        html_text: str,
        json_ld: dict[str, Any] | None,
    ) -> str | None:
        if json_ld and json_ld.get("thumbnailUrl"):
            thumb = json_ld["thumbnailUrl"]
            if isinstance(thumb, list) and thumb:
                return str(thumb[0]).strip()
            elif isinstance(thumb, str):
                return thumb.strip()

        fv_preview = re.search(r"preview_url\s*:\s*'([^']+)'", html_text)
        if fv_preview:
            return html.unescape(fv_preview.group(1)).strip()

        og_img = re.search(
            r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']',
            html_text,
            re.IGNORECASE,
        )
        if og_img:
            return html.unescape(og_img.group(1)).strip()

        return None

    def _resolve_duration(
        self,
        html_text: str,
        json_ld: dict[str, Any] | None,
    ) -> int | None:
        if json_ld and json_ld.get("duration"):
            dur = parse_iso8601_duration(str(json_ld["duration"]))
            if dur is not None:
                return dur

        clock_match = re.search(
            r'class=["\'][^"\']*icon-clock[^"\']*["\'][^>]*></i>\s*<span>((?:\d+:?)+)</span>',
            html_text,
            re.IGNORECASE,
        )
        if clock_match:
            return parse_clock_duration(clock_match.group(1))

        return None

    def _resolve_metrics(
        self,
        html_text: str,
        json_ld: dict[str, Any] | None,
    ) -> tuple[int | None, int | None]:
        view_count: int | None = None
        like_count: int | None = None

        if json_ld and isinstance(json_ld.get("interactionStatistic"), list):
            for stat in json_ld["interactionStatistic"]:
                if not isinstance(stat, dict):
                    continue
                itype = str(stat.get("interactionType") or "").casefold()
                count_val = stat.get("userInteractionCount")
                try:
                    if "watchaction" in itype and count_val is not None:
                        view_count = int(count_val)
                    elif "likeaction" in itype and count_val is not None:
                        like_count = int(count_val)
                except (ValueError, TypeError):
                    pass

        if view_count is None:
            view_match = re.search(
                r'class=["\'][^"\']*icon-eye[^"\']*["\'][^>]*></i>\s*<span>([ \d,]+)</span>',
                html_text,
                re.IGNORECASE,
            )
            if view_match:
                raw_views = re.sub(r"[\s,]", "", view_match.group(1))
                try:
                    view_count = int(raw_views)
                except ValueError:
                    pass

        if like_count is None:
            like_match = re.search(
                r'class=["\'][^"\']*voters\s+count[^"\']*["\'][^>]*>([ \d,]+)</span>',
                html_text,
                re.IGNORECASE,
            )
            if like_match:
                raw_likes = re.sub(r"[\s,]", "", like_match.group(1))
                try:
                    like_count = int(raw_likes)
                except ValueError:
                    pass

        return view_count, like_count

    def _resolve_upload_date(self, json_ld: dict[str, Any] | None) -> str | None:
        if json_ld and json_ld.get("uploadDate"):
            raw_date = str(json_ld["uploadDate"]).strip()
            # Canonicalize YYYY-MM-DD to YYYYMMDD if needed by yt-dlp conventions
            cleaned = raw_date.replace("-", "")[:8]
            return cleaned if len(cleaned) == 8 and cleaned.isdigit() else raw_date
        return None

    def _resolve_uploader(self, html_text: str) -> str:
        # Check models / uploader in flashvars or HTML
        fv_model = re.search(r"video_models\s*:\s*'([^']+)'", html_text)
        if fv_model and fv_model.group(1).strip():
            return html.unescape(fv_model.group(1)).strip()

        uploader_match = re.search(
            r'Uploaded By:.*?class=["\']name["\'][^>]*>([^<]+)<',
            html_text,
            re.DOTALL | re.IGNORECASE,
        )
        if uploader_match:
            return html.unescape(uploader_match.group(1)).strip()

        return "Rule34Video"

