from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, status

from app.api.dependencies import get_x_user_session_store
from app.core.exceptions import APIError
from app.models.response import APIResponse
from app.models.x_auth import (
    XAuthStatus,
    XSessionCreateRequest,
    XSessionResponse,
    XSessionRevokeResponse,
)
from app.services.x_user_session_store import (
    EphemeralXUserSessionStore,
    _is_safe_session_id,
)

router = APIRouter(prefix="/auth/x", tags=["x-auth"])
logger = logging.getLogger(__name__)


@router.post(
    "/session",
    response_model=APIResponse[XSessionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Register an ephemeral X user session",
    description=(
        "Registers client-provided X web session credentials (auth_token and ct0) into the backend's "
        "process-local ephemeral store. Credentials are never written to disk until required by yt-dlp, "
        "and are strictly isolated per session ID. The server generates an opaque 128-bit random session_id "
        "and determines session lifetime."
    ),
    response_model_exclude_none=True,
)
def create_session(
    request: XSessionCreateRequest,
    store: EphemeralXUserSessionStore = Depends(get_x_user_session_store),
) -> APIResponse[XSessionResponse]:
    clean_token = request.auth_token.get_secret_value().strip()
    clean_ct0 = request.ct0.get_secret_value().strip()

    try:
        session = store.create_session(
            auth_token=clean_token,
            ct0=clean_ct0,
        )
    except ValueError as exc:
        raise APIError(
            code="INVALID_CREDENTIALS",
            message="Invalid X authentication payload",
            details=str(exc),
            status_code=400,
        )

    logger.info("Created ephemeral X user session session_id=%s", session.session_id)
    return APIResponse.ok(
        message="Ephemeral X session created",
        data=XSessionResponse.from_session(session),
    )


@router.get(
    "/session/{session_id}",
    response_model=APIResponse[XSessionResponse],
    summary="Get ephemeral X user session status",
    description=(
        "Returns safe session status metadata. Never returns credentials or internal filesystem details. "
        "Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def get_session(
    session_id: str,
    store: EphemeralXUserSessionStore = Depends(get_x_user_session_store),
) -> APIResponse[XSessionResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == XAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    return APIResponse.ok(
        data=XSessionResponse.from_session(session),
    )


@router.delete(
    "/session/{session_id}",
    response_model=APIResponse[XSessionRevokeResponse],
    summary="Revoke an ephemeral X user session",
    description=(
        "Invalidates the session, purges in-memory credentials, and removes any temporary cookie artifacts "
        "(respecting in-flight worker leases). Unknown sessions return 404."
    ),
    response_model_exclude_none=True,
)
def revoke_session(
    session_id: str,
    store: EphemeralXUserSessionStore = Depends(get_x_user_session_store),
) -> APIResponse[XSessionRevokeResponse]:
    if not _is_safe_session_id(session_id):
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    session = store.get_session(session_id)
    if session.status == XAuthStatus.UNAVAILABLE:
        raise APIError(
            code="SESSION_NOT_FOUND",
            message="X authentication session not found",
            details="Session not found",
            status_code=404,
        )

    store.invalidate(session_id)

    logger.info("Revoked ephemeral X user session session_id=%s", session_id)
    return APIResponse.ok(
        message="Ephemeral X session revoked",
        data=XSessionRevokeResponse(
            session_id=session_id,
            status=XAuthStatus.INVALID,
            revoked=True,
        ),
    )
