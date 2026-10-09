from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, status

from app.api.dependencies import get_instagram_user_session_store
from app.core.exceptions import APIError
from app.models.response import APIResponse
from app.models.instagram_auth import (
    InstagramAuthStatus,
    InstagramSessionCreateRequest,
    InstagramSessionResponse,
    InstagramSessionRevokeResponse,
)
from app.services.instagram_user_session_store import (
    EphemeralInstagramUserSessionStore,
    _is_safe_session_id,
)

router = APIRouter(prefix="/auth/instagram", tags=["instagram-auth"])
logger = logging.getLogger(__name__)


@router.post(
    "/session",
    response_model=APIResponse[InstagramSessionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Register an ephemeral Instagram user session",
    description=(
        "Registers client-provided Instagram web session credentials (sessionid and optional ds_user_id/csrftoken) into "
        "the backend's process-local ephemeral store. Credentials are never written to disk until required "
        "by yt-dlp, and are strictly isolated per session ID. The server generates an opaque 128-bit random "
        "session_id and determines session lifetime."
    ),
    response_model_exclude_none=True,
)
def create_session(
    request: InstagramSessionCreateRequest,
    store: EphemeralInstagramUserSessionStore = Depends(get_instagram_user_session_store),
) -> APIResponse[InstagramSessionResponse]:
    clean_sessionid = request.sessionid.get_secret_value().strip()
    clean_ds_user_id = request.ds_user_id.get_secret_value().strip() if request.ds_user_id else None
    clean_csrftoken = request.csrftoken.get_secret_value().strip() if request.csrftoken else None

    try:
        session = store.create_session(
            sessionid=clean_sessionid,
            ds_user_id=clean_ds_user_id,
            csrftoken=clean_csrftoken,
        )
    except ValueError as exc:
        raise APIError(
            code="INVALID_CREDENTIALS",
            message="Invalid Instagram authentication payload",
            details=str(exc),
            status_code=400,
        )

    logger.info("Created ephemeral Instagram user session session_id=%s", session.session_id)
    return APIResponse.ok(
        message="Ephemeral Instagram session created",
        data=InstagramSessionResponse.from_session(session),
    )


@router.get(
    "/session/{session_id}",
    response_model=APIResponse[InstagramSessionResponse],
    summary="Get ephemeral Instagram user session status",
    description=(
        "Returns safe session status metadata. Never returns credentials or internal filesystem details. "
        "Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def get_session(
    session_id: str,
    store: EphemeralInstagramUserSessionStore = Depends(get_instagram_user_session_store),
) -> APIResponse[InstagramSessionResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == InstagramAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return APIResponse.ok(
        data=InstagramSessionResponse.from_session(session),
    )


@router.delete(
    "/session/{session_id}",
    response_model=APIResponse[InstagramSessionRevokeResponse],
    summary="Revoke an ephemeral Instagram user session",
    description=(
        "Invalidates the session, purges in-memory credentials, and removes any temporary cookie artifacts "
        "(respecting in-flight worker leases). Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def revoke_session(
    session_id: str,
    store: EphemeralInstagramUserSessionStore = Depends(get_instagram_user_session_store),
) -> APIResponse[InstagramSessionRevokeResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == InstagramAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="Instagram authentication session not found",
            details="Session not found",
            status_code=404,
        )

    store.invalidate(session_id)

    logger.info("Revoked ephemeral Instagram user session session_id=%s", session_id)
    return APIResponse.ok(
        message="Ephemeral Instagram session revoked",
        data=InstagramSessionRevokeResponse(
            session_id=session_id,
            status=InstagramAuthStatus.INVALID,
            revoked=True,
        ),
    )
