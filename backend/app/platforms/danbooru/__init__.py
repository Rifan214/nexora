from __future__ import annotations

from app.platforms.danbooru.constants import (
    ALLOWED_MEDIA_HOSTS,
    DANBOORU_CDN_HOST,
    DANBOORU_HOST,
    DANBOORU_POST_API_TEMPLATE,
    DANBOORU_TARGETED_HOSTS,
    DANBOORU_USER_AGENT,
    SUPPORTED_VIDEO_EXTENSIONS,
    is_danbooru_targeted_host,
    is_danbooru_targeted_url,
)
from app.platforms.danbooru.exceptions import (
    DanbooruAccessDeniedError,
    DanbooruError,
    DanbooruMalformedResponseError,
    DanbooruNetworkError,
    DanbooruPostNotFoundError,
    DanbooruRateLimitedError,
    DanbooruSecurityError,
    DanbooruServerError,
    DanbooruTimeoutError,
    DanbooruTlsError,
    DanbooruUnsupportedMediaError,
    DanbooruUrlError,
)
from app.platforms.danbooru.extractor import DanbooruExtractor, extract_danbooru_post_id
from app.platforms.danbooru.http_client import HttpDanbooruClient

__all__ = [
    "ALLOWED_MEDIA_HOSTS",
    "DANBOORU_CDN_HOST",
    "DANBOORU_HOST",
    "DANBOORU_POST_API_TEMPLATE",
    "DANBOORU_TARGETED_HOSTS",
    "DANBOORU_USER_AGENT",
    "SUPPORTED_VIDEO_EXTENSIONS",
    "DanbooruAccessDeniedError",
    "DanbooruError",
    "DanbooruExtractor",
    "DanbooruMalformedResponseError",
    "DanbooruNetworkError",
    "DanbooruPostNotFoundError",
    "DanbooruRateLimitedError",
    "DanbooruSecurityError",
    "DanbooruServerError",
    "DanbooruTimeoutError",
    "DanbooruTlsError",
    "DanbooruUnsupportedMediaError",
    "DanbooruUrlError",
    "HttpDanbooruClient",
    "extract_danbooru_post_id",
    "is_danbooru_targeted_host",
    "is_danbooru_targeted_url",
]
