from __future__ import annotations

import logging

from fastapi import Depends

from app.services.cleanup_service import CleanupService, get_cleanup_service
from app.services.job_manager import JobManager, get_job_manager

logger = logging.getLogger(__name__)


def run_lazy_cleanup(
    job_manager: JobManager = Depends(get_job_manager),
    cleanup_service: CleanupService = Depends(get_cleanup_service),
) -> None:
    try:
        cleanup_service.cleanup_expired_downloads(job_manager=job_manager)
    except Exception:
        logger.exception("Lazy cleanup failed")
