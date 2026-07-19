from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from threading import RLock
from uuid import UUID

from app.models.job import DownloadJob, JobStatus

logger = logging.getLogger(__name__)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class JobManager:
    def __init__(self) -> None:
        self._jobs: dict[UUID, DownloadJob] = {}
        self._lock = RLock()
        self._default_ttl = timedelta(hours=24)

    def create_job(
        self,
        *,
        media_url: str,
        platform: str,
        title: str | None = None,
        format_id: str | None = None,
        output_type: str | None = None,
        expires_at: datetime | None = None,
    ) -> DownloadJob:
        now = _utcnow()
        job = DownloadJob(
            media_url=media_url,
            platform=platform,
            title=title,
            format_id=format_id,
            output_type=output_type,
            expires_at=expires_at or (now + self._default_ttl),
            created_at=now,
            updated_at=now,
        )

        with self._lock:
            self._jobs[job.job_id] = job

        logger.info("Job created job_id=%s platform=%s media_url=%s", job.job_id, job.platform, job.media_url)
        return job

    def get_job(self, job_id: UUID) -> DownloadJob | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return None

            expired_job = self._expire_if_needed(job)
            if expired_job is not job:
                self._jobs[job_id] = expired_job
                return expired_job

            return job

    def update_progress(self, job_id: UUID, progress: int) -> DownloadJob:
        job = self._get_required_job(job_id)
        self._assert_active(job)
        updated_job = job.model_copy(
            update={
                "status": JobStatus.processing,
                "progress": max(0, min(100, progress)),
                "updated_at": _utcnow(),
            }
        )
        return self._store_updated_job(updated_job)

    def update_job_metadata(
        self,
        job_id: UUID,
        *,
        title: str | None = None,
        platform: str | None = None,
        format_id: str | None = None,
        output_type: str | None = None,
    ) -> DownloadJob:
        job = self._get_required_job(job_id)
        self._assert_active(job)
        updated_job = job.model_copy(
            update={
                "title": title if title is not None else job.title,
                "platform": platform if platform is not None else job.platform,
                "format_id": format_id if format_id is not None else job.format_id,
                "output_type": output_type if output_type is not None else job.output_type,
                "updated_at": _utcnow(),
            }
        )
        return self._store_updated_job(updated_job)

    def mark_completed(self, job_id: UUID, *, download_url: str | None = None) -> DownloadJob:
        job = self._get_required_job(job_id)
        self._assert_active(job)
        updated_job = job.model_copy(
            update={
                "status": JobStatus.completed,
                "progress": 100,
                "download_url": download_url,
                "error_message": None,
                "updated_at": _utcnow(),
            }
        )
        return self._store_updated_job(updated_job)

    def mark_failed(self, job_id: UUID, *, error_message: str) -> DownloadJob:
        job = self._get_required_job(job_id)
        self._assert_active(job)
        updated_job = job.model_copy(
            update={
                "status": JobStatus.failed,
                "error_message": error_message,
                "updated_at": _utcnow(),
            }
        )
        return self._store_updated_job(updated_job)

    def remove_job(self, job_id: UUID) -> bool:
        with self._lock:
            removed = self._jobs.pop(job_id, None) is not None

        if removed:
            logger.info("Job removed job_id=%s", job_id)
        return removed

    def _get_required_job(self, job_id: UUID) -> DownloadJob:
        job = self.get_job(job_id)
        if job is None:
            raise KeyError(job_id)
        return job

    def _store_updated_job(self, job: DownloadJob) -> DownloadJob:
        with self._lock:
            self._jobs[job.job_id] = job

        logger.info("Job updated job_id=%s status=%s progress=%s", job.job_id, job.status, job.progress)
        return job

    def _assert_active(self, job: DownloadJob) -> None:
        if job.status in {JobStatus.completed, JobStatus.failed, JobStatus.expired}:
            raise ValueError(f"Job '{job.job_id}' is not active")

    def _expire_if_needed(self, job: DownloadJob) -> DownloadJob:
        if job.expires_at is None or job.expires_at > _utcnow() or job.status == JobStatus.expired:
            return job

        expired_job = job.model_copy(
            update={
                "status": JobStatus.expired,
                "error_message": job.error_message or "Job expired",
                "updated_at": _utcnow(),
            }
        )
        logger.info("Job updated job_id=%s status=%s progress=%s", expired_job.job_id, expired_job.status, expired_job.progress)
        return expired_job


@lru_cache
def get_job_manager() -> JobManager:
    return JobManager()