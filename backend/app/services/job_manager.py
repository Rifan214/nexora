from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from threading import RLock
from typing import Callable
from uuid import UUID

from app.core.config import get_settings
from app.models.job import DownloadJob, JobStatus

logger = logging.getLogger(__name__)
JobUpdateListener = Callable[[DownloadJob], None]


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def build_job_download_url(job_id: UUID) -> str:
    return f"/files/{job_id}"


class JobManager:
    def __init__(self, *, download_expiration: timedelta | None = None) -> None:
        self._jobs: dict[UUID, DownloadJob] = {}
        self._update_listeners: list[JobUpdateListener] = []
        self._lock = RLock()
        self._download_expiration = (
            download_expiration
            if download_expiration is not None
            else timedelta(minutes=get_settings().download_expiration_minutes)
        )

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
            expires_at=expires_at,
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

    def list_jobs(self) -> list[DownloadJob]:
        with self._lock:
            return list(self._jobs.values())

    def add_update_listener(self, listener: JobUpdateListener) -> None:
        with self._lock:
            if listener not in self._update_listeners:
                self._update_listeners.append(listener)

    def update_progress(self, job_id: UUID, progress: int) -> DownloadJob:
        job = self._get_required_job(job_id)
        self._assert_active(job)
        bounded_progress = max(0, min(99, progress))
        updated_job = job.model_copy(
            update={
                "status": JobStatus.processing,
                "progress": max(job.progress, bounded_progress),
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
        completed_download_url = build_job_download_url(job_id)
        if download_url is not None and download_url != completed_download_url:
            logger.warning("Rejected unsafe completion download URL job_id=%s", job_id)
            logger.debug("Rejected completion download URL job_id=%s download_url=%s", job_id, download_url)

        now = _utcnow()
        updated_job = job.model_copy(
            update={
                "status": JobStatus.completed,
                "progress": 100,
                "download_url": completed_download_url,
                # Safety cap for completed files that are never requested.
                # The file endpoint replaces this with the shorter post-transfer
                # retention window after the response body has been sent.
                "expires_at": now + self._download_expiration,
                "error_message": None,
                "updated_at": now,
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

    def schedule_expiration(self, job_id: UUID, *, expires_at: datetime) -> DownloadJob | None:
        """Update cleanup timing without changing the public job state."""
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return None

            updated_job = job.model_copy(
                update={
                    "expires_at": expires_at,
                    "updated_at": _utcnow(),
                }
            )
            self._jobs[job_id] = updated_job

        logger.info("Job expiration scheduled job_id=%s expires_at=%s", job_id, expires_at)
        return updated_job

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
        self._notify_update_listeners(job)
        return job

    def _notify_update_listeners(self, job: DownloadJob) -> None:
        with self._lock:
            listeners = tuple(self._update_listeners)

        for listener in listeners:
            try:
                listener(job)
            except Exception:
                logger.exception("Job update listener failed job_id=%s", job.job_id)

    def _assert_active(self, job: DownloadJob) -> None:
        if job.status in {JobStatus.completed, JobStatus.failed, JobStatus.expired}:
            raise ValueError(f"Job '{job.job_id}' is not active")

    def _expire_if_needed(self, job: DownloadJob) -> DownloadJob:
        if (
            job.status is not JobStatus.completed
            or job.expires_at is None
            or job.expires_at > _utcnow()
        ):
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
    manager = JobManager()
    from app.services.websocket_manager import get_websocket_manager

    manager.add_update_listener(get_websocket_manager().broadcast_job_update)
    return manager
