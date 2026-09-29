from __future__ import annotations

import json
import logging
import re
from typing import Any

from app.platforms.hanime.crypto import HanimeCryptoError, decrypt_handshake_token
from app.platforms.hanime.http_client import (
    HanimeExtractionError,
    HanimeHandshakeAuthError,
    HanimeHttpClientError,
    HanimeMalformedResponseError,
    HanimeNetworkError,
    HanimeRateLimitError,
    HanimeSecurityError,
    HanimeServerError,
    HttpHanimeClient,
)
from app.platforms.hanime.signature_provider import HanimeSignatureProvider
from app.utils.platforms import is_hanime_media_url, normalize_media_url

logger = logging.getLogger(__name__)


class HanimeUrlError(HanimeExtractionError):
    """Raised when an invalid or unsupported Hanime URL is supplied."""


class HanimeDecryptionFailureError(HanimeExtractionError):
    """Raised when decrypting the handshake token fails."""


class HanimeMalformedPayloadError(HanimeExtractionError):
    """Raised when the decrypted payload structure is invalid."""


class HanimeNoPlayableFormatsError(HanimeExtractionError):
    """Raised when no playable formats are available."""


def parse_iso_duration(duration_str: str | None) -> int | None:
    """Parse an ISO 8601 duration string (e.g. 'PT29M18S', 'PT1H5M') into integer seconds."""
    if not duration_str or not isinstance(duration_str, str):
        return None
    match = re.match(r"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$", duration_str.strip())
    if not match:
        return None
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2) or 0)
    seconds = int(match.group(3) or 0)
    total = hours * 3600 + minutes * 60 + seconds
    return total if total > 0 else None


def _extract_page_metadata(html: str, slug: str) -> dict[str, Any]:
    """Extract metadata (title, thumbnail, duration, id) from Hanime HTML.

    Prefers structured JSON-LD data and falls back to OpenGraph / Astro island props.
    """
    meta: dict[str, Any] = {
        "slug": slug,
        "title": None,
        "description": None,
        "thumbnail": None,
        "duration": None,
        "upload_date": None,
        "video_id": None,
    }

    # 1. Prefer JSON-LD structured data
    for match in re.finditer(r'<script\s+type=["\']application/ld\+json["\']\s*>(.*?)</script>', html, re.DOTALL):
        try:
            ld_data = json.loads(match.group(1))
            if not isinstance(ld_data, dict):
                continue
            if "name" in ld_data or "headline" in ld_data:
                meta["title"] = str(ld_data.get("name") or ld_data.get("headline") or "").strip() or None
            if "description" in ld_data:
                meta["description"] = str(ld_data.get("description") or "").strip() or None
            if "thumbnailUrl" in ld_data:
                meta["thumbnail"] = str(ld_data.get("thumbnailUrl") or "").strip() or None
            elif "image" in ld_data:
                img = ld_data.get("image")
                if isinstance(img, str):
                    meta["thumbnail"] = img.strip() or None
                elif isinstance(img, list) and img and isinstance(img[0], str):
                    meta["thumbnail"] = img[0].strip() or None
            if "duration" in ld_data:
                meta["duration"] = parse_iso_duration(str(ld_data.get("duration") or ""))
            if "uploadDate" in ld_data:
                raw_date = str(ld_data.get("uploadDate") or "").strip()
                digits = re.sub(r"\D", "", raw_date[:10])
                meta["upload_date"] = digits if len(digits) == 8 else (raw_date or None)
            if meta["title"]:
                break
        except Exception:
            continue

    # 2. Fallbacks for missing fields
    if not meta["title"]:
        og_title = re.search(r'<meta\s+property=["\']og:title["\']\s+content=["\']([^"\']+)["\']', html)
        if og_title:
            meta["title"] = og_title.group(1).strip()
        else:
            page_title = re.search(r'<title>([^<]+)</title>', html)
            if page_title:
                clean_title = re.sub(r"\s*-\s*Hanime\.tv.*$", "", page_title.group(1), flags=re.IGNORECASE).strip()
                meta["title"] = clean_title or None

    if not meta["title"]:
        meta["title"] = slug

    if not meta["thumbnail"]:
        og_img = re.search(r'<meta\s+property=["\']og:image["\']\s+content=["\']([^"\']+)["\']', html)
        if og_img:
            meta["thumbnail"] = og_img.group(1).strip()
        else:
            poster_match = re.search(r'"poster_url":\[0,"([^"]+)"\]', html)
            if poster_match:
                meta["thumbnail"] = poster_match.group(1).strip()

    if not meta["description"]:
        og_desc = re.search(r'<meta\s+property=["\']og:description["\']\s+content=["\']([^"\']+)["\']', html)
        if og_desc:
            meta["description"] = og_desc.group(1).strip()

    vid_match = re.search(r'"video_id":\[0,(\d+)\]', html)
    if vid_match:
        meta["video_id"] = vid_match.group(1)
    else:
        meta["video_id"] = slug

    return meta


class HanimeExtractor:
    """High-level Hanime video extractor producing yt-dlp-compatible info_dict."""

    _SLUG_PATTERN = re.compile(r"^https?://(?:www\.)?hanime\.tv/videos/hentai/([A-Za-z0-9_-]+)", re.IGNORECASE)

    def __init__(
        self,
        *,
        http_client: HttpHanimeClient | None = None,
        signature_provider: HanimeSignatureProvider | None = None,
    ) -> None:
        self._http_client = http_client or HttpHanimeClient()
        self._owns_http_client = http_client is None
        self._signature_provider = signature_provider or HanimeSignatureProvider()

    async def close(self) -> None:
        """Release internally managed HTTP client resources."""
        if self._owns_http_client:
            await self._http_client.close()

    async def extract(self, url: str) -> dict[str, Any]:
        """Extract video metadata and playback formats for a Hanime media URL.

        Args:
            url: Hanime video page URL.

        Returns:
            A yt-dlp-compatible info_dict containing video metadata and playable formats.

        Raises:
            HanimeUrlError: If the URL is unsupported or invalid.
            HanimeHttpClientError: On page fetch or network failures.
            HanimeHandshakeAuthError: If handshake fails authentication even after refresh.
            HanimeDecryptionFailureError: If handshake token decryption fails.
            HanimeMalformedPayloadError: If decrypted payload lacks valid format structure.
            HanimeNoPlayableFormatsError: If no playable video formats are available.
        """
        if not is_hanime_media_url(url):
            raise HanimeUrlError(f"Unsupported or invalid Hanime URL: '{url}'")

        normalized_url = normalize_media_url(url)
        slug_match = self._SLUG_PATTERN.search(normalized_url)
        if not slug_match:
            raise HanimeUrlError(f"Could not extract video slug from Hanime URL: '{url}'")

        slug = slug_match.group(1)

        # 1. Fetch page HTML
        html = await self._http_client.get_video_page(normalized_url)

        # 2. Extract page metadata
        metadata = _extract_page_metadata(html, slug)

        # 3. Obtain signature and execute handshake with 1-shot retry on 401/403
        signature = await self._signature_provider.get_signature(force_refresh=False)
        try:
            x_token = await self._http_client.post_handshake(slug=slug, signature=signature)
        except HanimeHandshakeAuthError:
            logger.info("Handshake failed with 401/403; forcing signature refresh and retrying once...")
            signature = await self._signature_provider.get_signature(force_refresh=True)
            x_token = await self._http_client.post_handshake(slug=slug, signature=signature)

        # 4. Decrypt handshake token
        try:
            payload = decrypt_handshake_token(x_token)
        except HanimeCryptoError as exc:
            raise HanimeDecryptionFailureError("Failed to decrypt handshake x-token.") from exc

        if not isinstance(payload, dict):
            raise HanimeMalformedPayloadError("Decrypted handshake payload is not a valid dictionary.")

        raw_sources = payload.get("sources")
        if not isinstance(raw_sources, list):
            raise HanimeMalformedPayloadError("Decrypted handshake payload missing 'sources' list.")

        # 5. Normalize and filter formats
        formats = self._normalize_sources(raw_sources)
        if not formats:
            raise HanimeNoPlayableFormatsError(f"No playable formats available for slug '{slug}'.")

        # 6. Assemble yt-dlp-compatible info_dict
        info_dict: dict[str, Any] = {
            "id": metadata["video_id"],
            "title": metadata["title"],
            "thumbnail": metadata["thumbnail"],
            "duration": metadata["duration"],
            "upload_date": metadata["upload_date"],
            "description": metadata["description"],
            "webpage_url": normalized_url,
            "extractor": "hanime",
            "extractor_key": "Hanime",
            "formats": formats,
            "http_headers": {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/131.0.0.0 Safari/537.36"
                ),
                "Referer": "https://hanime.tv/",
                "Origin": "https://hanime.tv",
            },
        }

        return info_dict

    def _normalize_sources(self, raw_sources: list[Any]) -> list[dict[str, Any]]:
        """Normalize upstream HLS sources into yt-dlp-compatible format dicts.

        Omit empty sources, promotional placeholders (such as 1080p), and unplayable formats.
        """
        formats: list[dict[str, Any]] = []

        for item in raw_sources:
            if not isinstance(item, dict):
                continue

            label = str(item.get("label") or "").strip()
            src = str(item.get("src") or "").strip()
            kind = str(item.get("kind") or "").strip().lower()

            # Exclude empty sources, promotional placeholders, or unplayable 1080p
            if not src or kind == "promotion" or (label.lower() == "1080p" and not src):
                continue

            # Build full URL if relative
            if src.startswith("/"):
                stream_url = f"https://hanime.tv{src}"
            else:
                stream_url = src

            if not stream_url.startswith(("http://", "https://")):
                continue

            height = None
            if item.get("height") is not None:
                try:
                    height = int(item["height"])
                except (ValueError, TypeError):
                    height = None

            width = None
            if item.get("width") is not None:
                try:
                    width = int(item["width"])
                except (ValueError, TypeError):
                    width = None

            format_id = label.lower() if label else (f"{height}p" if height else "hls")

            fmt: dict[str, Any] = {
                "format_id": format_id,
                "url": stream_url,
                "ext": "mp4",
                "protocol": "m3u8_native",
                "height": height,
                "width": width,
                "http_headers": {
                    "User-Agent": (
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/131.0.0.0 Safari/537.36"
                    ),
                    "Referer": "https://hanime.tv/",
                    "Origin": "https://hanime.tv",
                },
            }
            formats.append(fmt)

        return formats
