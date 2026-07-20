from __future__ import annotations

import logging
from datetime import datetime, timezone

from app.models.job import DownloadJob, JobStatus
from app.services.job_manager import JobManager
from app.utils.storage import find_job_storage_files

logger = logging.getLogger(__name__)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CleanupService:
    def cleanup_expired_downloads(self, *, job_manager: JobManager) -> int:
        logger.info("Cleanup started")

        try:
            jobs = job_manager.list_jobs()
        except Exception:
            logger.exception("Cleanup failed while listing jobs")
            return 0

        removed_count = 0
        now = _utcnow()
        for job in jobs:
            if not self._is_expired_download_job(job, now):
                continue

            try:
                self._remove_expired_job(job, job_manager=job_manager)
                removed_count += 1
            except Exception:
                logger.exception("Cleanup failed job_id=%s", job.job_id)

        return removed_count

    @staticmethod
    def _is_expired_download_job(job: DownloadJob, now: datetime) -> bool:
        if job.status is JobStatus.expired:
            return True
        if job.status is not JobStatus.completed:
            return False
        return job.expires_at is not None and job.expires_at <= now

    def _remove_expired_job(self, job: DownloadJob, *, job_manager: JobManager) -> None:
        file_paths = find_job_storage_files(job.job_id)
        if not file_paths:
            logger.info("Missing expired file job_id=%s", job.job_id)

        for file_path in file_paths:
            try:
                file_path.unlink()
                logger.info("Expired file removed job_id=%s", job.job_id)
                logger.debug("Expired file removed path=%s", file_path)
            except FileNotFoundError:
                logger.info("Missing expired file job_id=%s", job.job_id)

        if job_manager.remove_job(job.job_id):
            logger.info("Expired job removed job_id=%s", job.job_id)
