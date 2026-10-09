from __future__ import annotations

import logging
from functools import lru_cache

from fastapi import APIRouter, Depends, Header

from app.api.dependencies import (
    get_instagram_user_session_store,
    get_tiktok_user_session_store,
    get_x_user_session_store,
    run_lazy_cleanup,
)
from app.core.exceptions import APIError
from app.models.instagram_auth import InstagramAuthStatus
from app.models.job import JobCreateResponse
from app.models.media import MediaMetadata, PlaylistMetadata
from app.models.requests import MediaDownloadRequest, MediaInfoRequest, PlaylistInfoRequest
from app.models.response import APIResponse
from app.models.tiktok_auth import TikTokAuthStatus
from app.models.x_auth import XAuthStatus
from app.services.instagram_user_session_store import (
    EphemeralInstagramUserSessionStore,
    _is_safe_session_id as _is_safe_instagram_session_id,
)
from app.services.media_service import MediaService
from app.services.tiktok_user_session_store import (
    EphemeralTikTokUserSessionStore,
    _is_safe_session_id as _is_safe_tiktok_session_id,
)
from app.services.x_user_session_store import (
    EphemeralXUserSessionStore,
    _is_safe_session_id,
)
from app.utils.platforms import detect_platform_from_url

router = APIRouter(prefix="/media", tags=["media"])
logger = logging.getLogger(__name__)


@lru_cache
def get_media_service() -> MediaService:
    return MediaService()


def _resolve_x_session_context(
    x_session_id: str | None,
    store: EphemeralXUserSessionStore,
) -> tuple[str, str | None]:
    """Validate optional X-Session-ID request header.

    Returns:
        tuple of (auth_source, auth_session_id)
        - If header is absent: ("guest", None)
        - If header is valid: ("user_session", session_id)
        - If header is invalid or expired: raises APIError (401 or 404)
    """
    if not x_session_id:
        return "guest", None

    clean_id = x_session_id.strip()
    if not clean_id:
        return "guest", None

    if not _is_safe_session_id(clean_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(clean_id)
    if session.status == XAuthStatus.EXPIRED or session.is_expired():
        raise APIError(
            code="SESSION_EXPIRED",
            message="X authentication session has expired",
            details="Session has expired",
            status_code=401,
        )

    if session.status == XAuthStatus.INVALID:
        raise APIError(
            code="SESSION_INVALID",
            message="X authentication session has been revoked or is invalid",
            details="Session is invalid",
            status_code=401,
        )

    if session.status != XAuthStatus.AVAILABLE or not session.authenticated:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return "user_session", clean_id


def _resolve_tiktok_session_context(
    tiktok_session_id: str | None,
    store: EphemeralTikTokUserSessionStore,
) -> tuple[str, str | None]:
    """Validate optional TikTok-Session-ID request header.

    Returns:
        tuple of (auth_source, auth_session_id)
        - If header is absent: ("guest", None)
        - If header is valid: ("user_session", session_id)
        - If header is invalid or expired: raises APIError (401 or 404)
    """
    if not tiktok_session_id:
        return "guest", None

    clean_id = tiktok_session_id.strip()
    if not clean_id:
        return "guest", None

    if not _is_safe_tiktok_session_id(clean_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(clean_id)
    if session.status == TikTokAuthStatus.EXPIRED or session.is_expired():
        raise APIError(
            code="SESSION_EXPIRED",
            message="TikTok authentication session has expired",
            details="Session has expired",
            status_code=401,
        )

    if session.status == TikTokAuthStatus.INVALID:
        raise APIError(
            code="SESSION_INVALID",
            message="TikTok authentication session has been revoked or is invalid",
            details="Session is invalid",
            status_code=401,
        )

    if session.status != TikTokAuthStatus.AVAILABLE or not session.authenticated:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return "user_session", clean_id


def _resolve_instagram_session_context(
    instagram_session_id: str | None,
    store: EphemeralInstagramUserSessionStore,
) -> tuple[str, str | None]:
    """Validate optional Instagram-Session-ID request header.

    Returns:
        tuple of (auth_source, auth_session_id)
        - If header is absent: ("guest", None)
        - If header is valid: ("user_session", session_id)
        - If header is invalid or expired: raises APIError (401 or 404)
    """
    if not instagram_session_id:
        return "guest", None

    clean_id = instagram_session_id.strip()
    if not clean_id:
        return "guest", None

    if not _is_safe_instagram_session_id(clean_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(clean_id)
    if session.status == InstagramAuthStatus.EXPIRED or session.is_expired():
        raise APIError(
            code="SESSION_EXPIRED",
            message="Instagram authentication session has expired",
            details="Session has expired",
            status_code=401,
        )

    if session.status == InstagramAuthStatus.INVALID:
        raise APIError(
            code="SESSION_INVALID",
            message="Instagram authentication session has been revoked or is invalid",
            details="Session is invalid",
            status_code=401,
        )

    if session.status != InstagramAuthStatus.AVAILABLE or not session.authenticated:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return "user_session", clean_id


@router.post(
    "/info",
    response_model=APIResponse[MediaMetadata],
    summary="Get media metadata and playable download options",
    description=(
        "Returns UI-friendly video_qualities and audio_options. Raw yt-dlp stream identifiers are never "
        "included in the response. Supports optional X-Session-ID, TikTok-Session-ID, and Instagram-Session-ID headers for authenticated downloads."
    ),
    response_model_exclude_none=True,
)
def media_info(
    request: MediaInfoRequest,
    x_session_id: str | None = Header(default=None, alias="X-Session-ID"),
    tiktok_session_id: str | None = Header(default=None, alias="TikTok-Session-ID"),
    instagram_session_id: str | None = Header(default=None, alias="Instagram-Session-ID"),
    media_service: MediaService = Depends(get_media_service),
    x_store: EphemeralXUserSessionStore = Depends(get_x_user_session_store),
    tiktok_store: EphemeralTikTokUserSessionStore = Depends(get_tiktok_user_session_store),
    instagram_store: EphemeralInstagramUserSessionStore = Depends(get_instagram_user_session_store),
) -> APIResponse[MediaMetadata]:
    logger.info("Incoming media info request url=%s", request.url)
    platform = detect_platform_from_url(request.url)
    if platform == "twitter":
        auth_source, auth_session_id = _resolve_x_session_context(x_session_id, x_store)
    elif platform == "tiktok":
        auth_source, auth_session_id = _resolve_tiktok_session_context(tiktok_session_id, tiktok_store)
    elif platform == "instagram":
        auth_source, auth_session_id = _resolve_instagram_session_context(instagram_session_id, instagram_store)
    else:
        auth_source, auth_session_id = "guest", None

    if auth_session_id:
        metadata = media_service.get_metadata(
            request.url,
            auth_source=auth_source,
            auth_session_id=auth_session_id,
        )
    else:
        metadata = media_service.get_metadata(request.url)
    return APIResponse.ok(data=metadata)


@router.post(
    "/playlist/info",
    response_model=APIResponse[PlaylistMetadata],
    summary="Get lightweight playlist metadata for Batch Import",
    description=(
        "Returns a playlist title and importable item URLs with lightweight display metadata. "
        "This endpoint does not extract formats and does not create download jobs."
    ),
    response_model_exclude_none=True,
)
def playlist_info(
    request: PlaylistInfoRequest,
    media_service: MediaService = Depends(get_media_service),
) -> APIResponse[PlaylistMetadata]:
    logger.info("Incoming playlist info request url=%s", request.url)
    metadata = media_service.get_playlist_metadata(request.url)
    return APIResponse.ok(data=metadata)


@router.post(
    "/download",
    response_model=APIResponse[JobCreateResponse],
    summary="Create a video or audio download job",
    description=(
        "For video downloads, send quality_height from video_qualities. For audio downloads, send "
        "media_type=audio without a quality or format identifier; the backend selects bestaudio and "
        "converts it to MP3 with FFmpeg. The deprecated format_id and type fields remain accepted for "
        "temporary legacy-client compatibility. Supports optional X-Session-ID, TikTok-Session-ID, and Instagram-Session-ID headers for authenticated downloads."
    ),
    response_model_exclude_none=True,
    dependencies=[Depends(run_lazy_cleanup)],
)
def media_download(
    request: MediaDownloadRequest,
    x_session_id: str | None = Header(default=None, alias="X-Session-ID"),
    tiktok_session_id: str | None = Header(default=None, alias="TikTok-Session-ID"),
    instagram_session_id: str | None = Header(default=None, alias="Instagram-Session-ID"),
    media_service: MediaService = Depends(get_media_service),
    x_store: EphemeralXUserSessionStore = Depends(get_x_user_session_store),
    tiktok_store: EphemeralTikTokUserSessionStore = Depends(get_tiktok_user_session_store),
    instagram_store: EphemeralInstagramUserSessionStore = Depends(get_instagram_user_session_store),
) -> APIResponse[JobCreateResponse]:
    logger.info(
        "Incoming media download request url=%s media_type=%s quality_height=%s legacy_format_request=%s",
        request.url,
        request.media_type,
        request.quality_height,
        request.format_id is not None,
    )
    platform = detect_platform_from_url(request.url)
    if platform == "twitter":
        auth_source, auth_session_id = _resolve_x_session_context(x_session_id, x_store)
    elif platform == "tiktok":
        auth_source, auth_session_id = _resolve_tiktok_session_context(tiktok_session_id, tiktok_store)
    elif platform == "instagram":
        auth_source, auth_session_id = _resolve_instagram_session_context(instagram_session_id, instagram_store)
    else:
        auth_source, auth_session_id = "guest", None

    if auth_session_id:
        job = media_service.create_download_job(
            request,
            auth_source=auth_source,
            auth_session_id=auth_session_id,
        )
    else:
        job = media_service.create_download_job(request)
    return APIResponse.ok(data=JobCreateResponse(job_id=job.job_id))
