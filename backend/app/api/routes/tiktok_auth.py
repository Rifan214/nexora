from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, status

from app.api.dependencies import get_tiktok_user_session_store
from app.core.exceptions import APIError
from app.models.response import APIResponse
from app.models.tiktok_auth import (
    TikTokAuthStatus,
    TikTokSessionCreateRequest,
    TikTokSessionResponse,
    TikTokSessionRevokeResponse,
)
from app.services.tiktok_user_session_store import (
    EphemeralTikTokUserSessionStore,
    _is_safe_session_id,
)

router = APIRouter(prefix="/auth/tiktok", tags=["tiktok-auth"])
logger = logging.getLogger(__name__)


@router.post(
    "/session",
    response_model=APIResponse[TikTokSessionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Register an ephemeral TikTok user session",
    description=(
        "Registers client-provided TikTok web session credentials (sessionid and optional sid_tt) into "
        "the backend's process-local ephemeral store. Credentials are never written to disk until required "
        "by yt-dlp, and are strictly isolated per session ID. The server generates an opaque 128-bit random "
        "session_id and determines session lifetime."
    ),
    response_model_exclude_none=True,
)
def create_session(
    request: TikTokSessionCreateRequest,
    store: EphemeralTikTokUserSessionStore = Depends(get_tiktok_user_session_store),
) -> APIResponse[TikTokSessionResponse]:
    clean_sessionid = request.sessionid.get_secret_value().strip()
    clean_sid_tt = request.sid_tt.get_secret_value().strip() if request.sid_tt else None

    try:
        session = store.create_session(
            sessionid=clean_sessionid,
            sid_tt=clean_sid_tt,
        )
    except ValueError as exc:
        raise APIError(
            code="INVALID_CREDENTIALS",
            message="Invalid TikTok authentication payload",
            details=str(exc),
            status_code=400,
        )

    logger.info("Created ephemeral TikTok user session session_id=%s", session.session_id)
    return APIResponse.ok(
        message="Ephemeral TikTok session created",
        data=TikTokSessionResponse.from_session(session),
    )


@router.get(
    "/session/{session_id}",
    response_model=APIResponse[TikTokSessionResponse],
    summary="Get ephemeral TikTok user session status",
    description=(
        "Returns safe session status metadata. Never returns credentials or internal filesystem details. "
        "Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def get_session(
    session_id: str,
    store: EphemeralTikTokUserSessionStore = Depends(get_tiktok_user_session_store),
) -> APIResponse[TikTokSessionResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == TikTokAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return APIResponse.ok(
        data=TikTokSessionResponse.from_session(session),
    )


@router.delete(
    "/session/{session_id}",
    response_model=APIResponse[TikTokSessionRevokeResponse],
    summary="Revoke an ephemeral TikTok user session",
    description=(
        "Invalidates the session, purges in-memory credentials, and removes any temporary cookie artifacts "
        "(respecting in-flight worker leases). Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def revoke_session(
    session_id: str,
    store: EphemeralTikTokUserSessionStore = Depends(get_tiktok_user_session_store),
) -> APIResponse[TikTokSessionRevokeResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == TikTokAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="TikTok authentication session not found",
            details="Session not found",
            status_code=404,
        )

    store.invalidate(session_id)

    logger.info("Revoked ephemeral TikTok user session session_id=%s", session_id)
    return APIResponse.ok(
        message="Ephemeral TikTok session revoked",
        data=TikTokSessionRevokeResponse(
            session_id=session_id,
            status=TikTokAuthStatus.INVALID,
            revoked=True,
        ),
    )
