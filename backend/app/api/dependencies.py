from __future__ import annotations

import logging

from typing import TYPE_CHECKING

from fastapi import Depends

from app.services.cleanup_service import CleanupService, get_cleanup_service
from app.services.job_manager import JobManager, get_job_manager

if TYPE_CHECKING:
    from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore
    from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore
    from app.services.x_user_session_store import EphemeralXUserSessionStore

logger = logging.getLogger(__name__)


def run_lazy_cleanup(
    job_manager: JobManager = Depends(get_job_manager),
    cleanup_service: CleanupService = Depends(get_cleanup_service),
) -> None:
    try:
        cleanup_service.cleanup_expired_downloads(job_manager=job_manager)
    except Exception:
        logger.exception("Lazy cleanup failed")


def get_x_user_session_store() -> EphemeralXUserSessionStore:
    from app.api.routes.media import get_media_service

    return get_media_service().x_auth_manager.user_session_store


def get_tiktok_user_session_store() -> EphemeralTikTokUserSessionStore:
    from app.api.routes.media import get_media_service

    return get_media_service().tiktok_auth_manager.user_session_store


def get_instagram_user_session_store() -> EphemeralInstagramUserSessionStore:
    from app.api.routes.media import get_media_service

    return get_media_service().instagram_auth_manager.user_session_store
