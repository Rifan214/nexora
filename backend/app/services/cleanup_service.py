from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from uuid import UUID

from app.core.config import get_settings
from app.models.job import DownloadJob, JobStatus
from app.services.job_manager import JobManager
from app.utils.storage import find_job_storage_files

logger = logging.getLogger(__name__)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CleanupService:
    def __init__(
        self,
        *,
        temp_file_retention: timedelta | None = None,
        failed_download_retention: timedelta | None = None,
    ) -> None:
        settings = get_settings()
        self._temp_file_retention = (
            temp_file_retention
            if temp_file_retention is not None
            else timedelta(minutes=settings.temp_file_retention_minutes)
        )
        self._failed_download_retention = (
            failed_download_retention
            if failed_download_retention is not None
            else timedelta(minutes=settings.failed_download_retention_minutes)
        )

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
                if self._remove_expired_job(job, job_manager=job_manager):
                    removed_count += 1
            except Exception:
                logger.exception("Cleanup failed job_id=%s", job.job_id)

        return removed_count

    def mark_completed_file_for_expiration(
        self,
        job_id: UUID,
        *,
        job_manager: JobManager,
    ) -> bool:
        """Start the short retention window after FileResponse finishes sending."""
        try:
            job = job_manager.get_job(job_id)
            if job is None:
                logger.warning("Completed file expiration skipped job_id=%s reason=job_not_found", job_id)
                return False
            if job.status is not JobStatus.completed:
                logger.warning(
                    "Completed file expiration skipped job_id=%s reason=job_not_completed status=%s",
                    job_id,
                    job.status,
                )
                return False

            expires_at = _utcnow() + self._temp_file_retention
            scheduled_job = job_manager.schedule_expiration(job_id, expires_at=expires_at)
            if scheduled_job is None:
                logger.warning("Completed file expiration skipped job_id=%s reason=job_not_found", job_id)
                return False

            logger.info(
                "Completed file retention scheduled job_id=%s retention_minutes=%s",
                job_id,
                self._temp_file_retention.total_seconds() / 60,
            )
            return True
        except Exception:
            logger.exception("Failed to schedule completed file cleanup job_id=%s", job_id)
            return False

    def cleanup_failed_download(self, job_id: UUID, *, job_manager: JobManager) -> int:
        """Delete all failed-download artifacts and retain only the job error."""
        logger.info("Cleanup started job_id=%s reason=failed_download", job_id)
        try:
            job = job_manager.get_job(job_id)
            if job is not None and job.status is not JobStatus.failed:
                logger.warning(
                    "Failed file cleanup skipped job_id=%s reason=job_not_failed status=%s",
                    job_id,
                    job.status,
                )
                return 0

            removed_count, deletion_failed = self._remove_storage_files(job_id, reason="failed")
            if job is not None:
                job_manager.schedule_expiration(
                    job_id,
                    expires_at=_utcnow() + self._failed_download_retention,
                )
            logger.info(
                "Failed download cleanup completed job_id=%s removed_files=%s retention_minutes=%s",
                job_id,
                removed_count,
                self._failed_download_retention.total_seconds() / 60,
            )
            if deletion_failed:
                logger.warning("Failed download cleanup incomplete job_id=%s", job_id)
            return removed_count
        except Exception:
            logger.exception("Failed download cleanup error job_id=%s", job_id)
            return 0

    @staticmethod
    def _is_expired_download_job(job: DownloadJob, now: datetime) -> bool:
        if job.status is JobStatus.expired:
            return True
        if job.status not in {JobStatus.completed, JobStatus.failed}:
            return False
        return job.expires_at is not None and job.expires_at <= now

    def _remove_expired_job(self, job: DownloadJob, *, job_manager: JobManager) -> bool:
        _, deletion_failed = self._remove_storage_files(job.job_id, reason="expired")
        if deletion_failed:
            logger.warning("Expired download cleanup incomplete job_id=%s", job.job_id)
            return False

        if job_manager.remove_job(job.job_id):
            logger.info("Expired job removed job_id=%s", job.job_id)
            return True
        return False

    def _remove_storage_files(self, job_id: UUID, *, reason: str) -> tuple[int, bool]:
        file_paths = find_job_storage_files(job_id)
        if not file_paths:
            logger.info("Missing %s file job_id=%s", reason, job_id)
            return 0, False

        removed_count = 0
        deletion_failed = False
        for file_path in file_paths:
            try:
                file_path.unlink()
                removed_count += 1
                logger.info("%s file removed job_id=%s", reason.capitalize(), job_id)
                logger.debug("%s file removed path=%s", reason.capitalize(), file_path)
            except FileNotFoundError:
                logger.info("Missing %s file job_id=%s", reason, job_id)
            except OSError:
                deletion_failed = True
                logger.exception("Failed to remove %s file job_id=%s", reason, job_id)

        return removed_count, deletion_failed


@lru_cache
def get_cleanup_service() -> CleanupService:
    return CleanupService()
