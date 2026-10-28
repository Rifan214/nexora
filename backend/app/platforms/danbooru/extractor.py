from __future__ import annotations

import logging
import re
from typing import Any
from urllib.parse import urlsplit

from app.platforms.danbooru.constants import (
    ALLOWED_MEDIA_HOSTS,
    DANBOORU_HOST,
    DANBOORU_USER_AGENT,
    SUPPORTED_VIDEO_EXTENSIONS,
)
from app.platforms.danbooru.exceptions import (
    DanbooruMalformedResponseError,
    DanbooruPostNotFoundError,
    DanbooruSecurityError,
    DanbooruUnsupportedMediaError,
    DanbooruUrlError,
)
from app.platforms.danbooru.http_client import HttpDanbooruClient

logger = logging.getLogger(__name__)

_DANBOORU_POST_ID_PATTERN = re.compile(r"^/posts/(?P<post_id>[1-9][0-9]*)/?$")


def extract_danbooru_post_id(url: str) -> int | None:
    """Extract numeric post ID from a Danbooru URL.

    Args:
        url: URL string to parse.

    Returns:
        Integer post ID if valid, else None.
    """
    try:
        parsed = urlsplit(url)
    except Exception:
        return None

    if (parsed.scheme or "").casefold() not in {"http", "https"}:
        return None

    hostname = (parsed.hostname or "").casefold()
    if hostname != DANBOORU_HOST:
        return None

    match = _DANBOORU_POST_ID_PATTERN.fullmatch(parsed.path)
    if not match:
        return None

    try:
        post_id = int(match.group("post_id"))
        return post_id if post_id > 0 else None
    except (ValueError, TypeError):
        return None


class DanbooruExtractor:
    """Extracts structured metadata and media formats from Danbooru posts."""

    def __init__(self, *, http_client: HttpDanbooruClient | None = None) -> None:
        self._http_client = http_client or HttpDanbooruClient()

    async def extract(self, url: str) -> dict[str, Any]:
        """Extract metadata and media format dictionary from a Danbooru post URL.

        Args:
            url: Canonical or standard Danbooru post URL.

        Returns:
            yt-dlp compatible info dictionary with structured formats.

        Raises:
            DanbooruUrlError: If URL or post ID is invalid.
            DanbooruPostNotFoundError: If post does not exist, is deleted, or banned.
            DanbooruUnsupportedMediaError: If post does not contain video media.
            DanbooruSecurityError: If media URL origin is untrusted.
        """
        post_id = extract_danbooru_post_id(url)
        if post_id is None:
            raise DanbooruUrlError(
                f"Invalid or unsupported Danbooru URL: '{url}'. Expected format: https://danbooru.donmai.us/posts/<id>"
            )

        data = await self._http_client.fetch_post_json(post_id)

        # 1. Validate payload consistency
        raw_id = data.get("id")
        if raw_id is not None:
            try:
                if int(raw_id) != post_id:
                    raise DanbooruMalformedResponseError(
                        f"Danbooru response ID {raw_id} does not match requested post ID {post_id}."
                    )
            except (ValueError, TypeError):
                raise DanbooruMalformedResponseError(f"Danbooru returned invalid post ID: {raw_id}")

        if bool(data.get("is_deleted")):
            raise DanbooruPostNotFoundError(f"Danbooru post {post_id} has been deleted.")

        if bool(data.get("is_banned")):
            raise DanbooruPostNotFoundError(f"Danbooru post {post_id} is unavailable or banned.")

        # 2. Resolve media URL and validate origin
        media_url, file_ext = self._resolve_media_url(data, post_id=post_id)
        self._validate_media_url_security(media_url)

        # 3. Determine media type and verify video stream support
        if not self._is_supported_media_type(file_ext, data):
            raise DanbooruUnsupportedMediaError(
                f"Danbooru post {post_id} media type '{file_ext}' is not a supported video format."
            )

        # 4. Extract dimensions, size, duration
        width = self._extract_int(data.get("image_width"))
        height = self._extract_int(data.get("image_height"))
        file_size = self._extract_int(data.get("file_size"))

        media_asset = data.get("media_asset")
        duration: float | None = None
        if isinstance(media_asset, dict):
            if width is None:
                width = self._extract_int(media_asset.get("image_width"))
            if height is None:
                height = self._extract_int(media_asset.get("image_height"))
            if file_size is None:
                file_size = self._extract_int(media_asset.get("file_size"))
            raw_duration = media_asset.get("duration")
            if raw_duration is not None:
                try:
                    duration = float(raw_duration)
                except (ValueError, TypeError):
                    duration = None

        # 5. Build display metadata
        artist = str(data.get("tag_string_artist") or "").strip()
        if artist:
            title = f"Danbooru Post {post_id} ({artist})"
            uploader = artist
        else:
            title = f"Danbooru Post {post_id}"
            uploader_id = data.get("uploader_id")
            uploader = str(uploader_id) if uploader_id is not None else None

        canonical_webpage_url = f"https://danbooru.donmai.us/posts/{post_id}"
        thumbnail_url = self._resolve_thumbnail_url(data)

        # Format upload date (created_at ISO string e.g. '2026-07-10T15:32:39.456-04:00' -> '20260710')
        upload_date: str | None = None
        created_at = str(data.get("created_at") or "").strip()
        if len(created_at) >= 10 and created_at[4] == "-" and created_at[7] == "-":
            upload_date = created_at[:10].replace("-", "")

        # 6. Assemble format dictionary
        format_id = f"danbooru-{post_id}-video"
        format_dict: dict[str, Any] = {
            "format_id": format_id,
            "url": media_url,
            "ext": file_ext,
            "width": width,
            "height": height,
            "filesize": file_size,
            "vcodec": "h264" if file_ext == "mp4" else file_ext,
            "acodec": "aac" if file_ext == "mp4" else "vorbis",
            "protocol": "https" if media_url.startswith("https") else "http",
            "http_headers": {
                "User-Agent": DANBOORU_USER_AGENT,
                "Referer": canonical_webpage_url,
            },
        }

        # 7. Assemble yt-dlp compatible info dictionary
        info_dict: dict[str, Any] = {
            "id": str(post_id),
            "title": title,
            "description": str(data.get("tag_string") or "").strip() or None,
            "thumbnail": thumbnail_url,
            "duration": int(round(duration)) if duration is not None else None,
            "upload_date": upload_date,
            "uploader": uploader,
            "webpage_url": canonical_webpage_url,
            "extractor": "danbooru",
            "extractor_key": "Danbooru",
            "formats": [format_dict],
            "http_headers": {
                "User-Agent": DANBOORU_USER_AGENT,
                "Referer": canonical_webpage_url,
            },
        }

        return info_dict

    def _resolve_media_url(self, data: dict[str, Any], *, post_id: int) -> tuple[str, str]:
        """Resolve the primary direct media URL and file extension."""
        # 1. Primary: file_url
        candidate_url = data.get("file_url")
        file_ext = str(data.get("file_ext") or "").strip().lower()

        # 2. Fallback: large_file_url
        if not candidate_url:
            candidate_url = data.get("large_file_url")

        # 3. Fallback: search media_asset variants for original stream
        if not candidate_url:
            media_asset = data.get("media_asset")
            if isinstance(media_asset, dict):
                variants = media_asset.get("variants") or []
                for variant in variants:
                    if not isinstance(variant, dict):
                        continue
                    v_type = str(variant.get("type") or "").strip().lower()
                    v_ext = str(variant.get("file_ext") or "").strip().lower()
                    if (v_type == "original" or v_ext in SUPPORTED_VIDEO_EXTENSIONS) and variant.get("url"):
                        candidate_url = variant["url"]
                        if not file_ext:
                            file_ext = v_ext
                        break

        if not candidate_url:
            raise DanbooruUnsupportedMediaError(f"No usable media URL found in Danbooru post {post_id}.")

        media_url = str(candidate_url).strip()
        if not file_ext:
            file_ext = self._infer_extension_from_url(media_url)

        return media_url, file_ext

    @staticmethod
    def _validate_media_url_security(url: str) -> None:
        """Enforce strict host and scheme validation to prevent SSRF and unencrypted endpoints."""
        try:
            parsed = urlsplit(url)
        except Exception as exc:
            raise DanbooruSecurityError(f"Malformed media URL: '{url}'") from exc

        scheme = (parsed.scheme or "").casefold()
        if scheme not in {"https", "http"}:
            raise DanbooruSecurityError(f"Unsupported media URL scheme '{scheme}'. Expected https/http.")

        hostname = (parsed.hostname or "").casefold()
        if hostname not in ALLOWED_MEDIA_HOSTS:
            raise DanbooruSecurityError(
                f"Untrusted media host '{hostname}'. Media must originate from approved Danbooru CDNs."
            )

    @classmethod
    def _is_supported_media_type(cls, file_ext: str, data: dict[str, Any]) -> bool:
        """Check whether the post contains a supported playable video media stream."""
        if file_ext in SUPPORTED_VIDEO_EXTENSIONS:
            return True

        # Check tag strings and media_asset duration for video indicators
        tags = str(data.get("tag_string_meta") or "") + " " + str(data.get("tag_string") or "")
        tags_lower = tags.casefold()
        if "video" in tags_lower or "animated" in tags_lower:
            return True

        media_asset = data.get("media_asset")
        if isinstance(media_asset, dict):
            raw_duration = media_asset.get("duration")
            if raw_duration is not None:
                try:
                    if float(raw_duration) > 0:
                        return True
                except (ValueError, TypeError):
                    pass

        return False

    @staticmethod
    def _resolve_thumbnail_url(data: dict[str, Any]) -> str | None:
        preview_url = data.get("preview_file_url")
        if preview_url:
            url_str = str(preview_url).strip()
            try:
                parsed = urlsplit(url_str)
                if (parsed.hostname or "").casefold() in ALLOWED_MEDIA_HOSTS:
                    return url_str
            except Exception:
                pass

        media_asset = data.get("media_asset")
        if isinstance(media_asset, dict):
            variants = media_asset.get("variants") or []
            for variant in variants:
                if not isinstance(variant, dict):
                    continue
                v_type = str(variant.get("type") or "").strip().lower()
                if v_type in {"180x180", "360x360", "sample"} and variant.get("url"):
                    return str(variant["url"]).strip()

        return None

    @staticmethod
    def _infer_extension_from_url(url: str) -> str:
        try:
            parsed = urlsplit(url)
            path = parsed.path.rstrip("/")
            if "." in path:
                ext = path.rsplit(".", 1)[-1].strip().lower()
                if ext and len(ext) <= 5:
                    return ext
        except Exception:
            pass
        return "mp4"

    @staticmethod
    def _extract_int(value: Any) -> int | None:
        if value is None:
            return None
        try:
            val = int(value)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None
