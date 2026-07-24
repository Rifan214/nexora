from __future__ import annotations

import asyncio
import logging
from collections import Counter
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from uuid import UUID

from app.core.config import get_settings
from app.models.job import DownloadJob, JobStatus
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.utils.storage import find_job_storage_files, get_temp_storage_dir

logger = logging.getLogger(__name__)

_ACTIVE_JOB_STATUSES = {
    JobStatus.pending,
    JobStatus.processing,
    JobStatus.cancelling,
}
_FINAL_MEDIA_SUFFIXES = {
    ".3gp",
    ".aac",
    ".avi",
    ".flac",
    ".m4a",
    ".mkv",
    ".mov",
    ".mp3",
    ".mp4",
    ".ogg",
    ".opus",
    ".wav",
    ".webm",
}
_STORAGE_MARKER_FILENAMES = {".gitignore", ".gitkeep"}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CleanupService:
    def __init__(
        self,
        *,
        download_expiration: timedelta | None = None,
        temp_file_retention: timedelta | None = None,
        failed_download_retention: timedelta | None = None,
    ) -> None:
        settings = get_settings()
        self._download_expiration = (
            download_expiration
            if download_expiration is not None
            else timedelta(minutes=settings.download_expiration_minutes)
        )
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

    def cleanup_expired_downloads(
        self,
        *,
        job_manager: JobManager,
        process_manager: DownloadProcessManager | None = None,
        log_started: bool = True,
        removed_artifacts: Counter[str] | None = None,
    ) -> int:
        if log_started:
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
                if self._remove_expired_job(
                    job,
                    job_manager=job_manager,
                    process_manager=process_manager,
                    removed_artifacts=removed_artifacts,
                ):
                    removed_count += 1
            except Exception:
                logger.exception("Cleanup failed job_id=%s", job.job_id)

        if log_started:
            logger.info("Cleanup finished expired_jobs_removed=%s", removed_count)
        return removed_count

    def cleanup_orphaned_artifacts(
        self,
        *,
        job_manager: JobManager,
        process_manager: DownloadProcessManager,
    ) -> dict[str, int]:
        """Remove stale files in temporary storage that are not safe to retain."""
        try:
            jobs_by_id = {job.job_id: job for job in job_manager.list_jobs()}
            storage_dir = get_temp_storage_dir().resolve()
            candidates = tuple(storage_dir.iterdir())
        except OSError:
            logger.exception("Cleanup failed while scanning temporary storage")
            return {}
        except Exception:
            logger.exception("Cleanup failed while preparing artifact scan")
            return {}

        now = _utcnow()
        removed_artifacts: Counter[str] = Counter()
        for candidate in candidates:
            resolved_candidate = self._safe_storage_file(candidate, storage_dir=storage_dir)
            if resolved_candidate is None:
                continue

            job_id = self._job_id_from_filename(resolved_candidate)
            job = jobs_by_id.get(job_id) if job_id is not None else None
            if self._is_active_job(job_id, job, process_manager=process_manager):
                continue
            if not self._should_remove_artifact(resolved_candidate, job=job, now=now):
                continue

            if self._remove_storage_path(resolved_candidate, reason="stale artifact"):
                removed_artifacts[self._artifact_kind(resolved_candidate)] += 1

        return dict(removed_artifacts)

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

    def cleanup_cancelled_download(
        self,
        job_id: UUID,
        *,
        job_manager: JobManager,
    ) -> DownloadJob | None:
        """Remove cancellation artifacts before publishing the terminal state."""
        logger.info("Cleanup started job_id=%s reason=cancelled_download", job_id)
        job: DownloadJob | None = None
        try:
            job = job_manager.get_job(job_id)
            if job is not None and job.status not in {
                JobStatus.cancelling,
                JobStatus.cancelled,
            }:
                logger.warning(
                    "Cancelled file cleanup skipped job_id=%s reason=job_not_cancelling status=%s",
                    job_id,
                    job.status,
                )
                return job

            removed_count, deletion_failed = self._remove_storage_files(
                job_id,
                reason="cancelled",
            )
            if job is None:
                return None

            cancelled_job = job_manager.mark_cancelled(job_id)
            job_manager.schedule_expiration(
                job_id,
                expires_at=_utcnow() + self._failed_download_retention,
            )
            logger.info(
                "Cancelled download cleanup completed job_id=%s removed_files=%s",
                job_id,
                removed_count,
            )
            if deletion_failed:
                logger.warning("Cancelled download cleanup incomplete job_id=%s", job_id)
            return cancelled_job
        except Exception:
            logger.exception("Cancelled download cleanup error job_id=%s", job_id)
            return job

    @staticmethod
    def _is_expired_download_job(job: DownloadJob, now: datetime) -> bool:
        if job.status is JobStatus.expired:
            return True
        if job.status not in {
            JobStatus.completed,
            JobStatus.failed,
            JobStatus.cancelled,
        }:
            return False
        return job.expires_at is not None and job.expires_at <= now

    def _remove_expired_job(
        self,
        job: DownloadJob,
        *,
        job_manager: JobManager,
        process_manager: DownloadProcessManager | None = None,
        removed_artifacts: Counter[str] | None = None,
    ) -> bool:
        if self._is_active_job(job.job_id, job, process_manager=process_manager):
            logger.debug("Expired cleanup skipped active job_id=%s", job.job_id)
            return False

        _, deletion_failed = self._remove_storage_files(
            job.job_id,
            reason="expired",
            removed_artifacts=removed_artifacts,
        )
        if deletion_failed:
            logger.warning("Expired download cleanup incomplete job_id=%s", job.job_id)
            return False

        if job_manager.remove_job(job.job_id):
            logger.info("Expired job removed job_id=%s", job.job_id)
            return True
        return False

    def _remove_storage_files(
        self,
        job_id: UUID,
        *,
        reason: str,
        removed_artifacts: Counter[str] | None = None,
    ) -> tuple[int, bool]:
        file_paths = find_job_storage_files(job_id)
        if not file_paths:
            logger.info("Missing %s file job_id=%s", reason, job_id)
            return 0, False

        removed_count = 0
        deletion_failed = False
        for file_path in file_paths:
            if self._remove_storage_path(file_path, reason=reason):
                removed_count += 1
                if removed_artifacts is not None:
                    removed_artifacts[self._artifact_kind(file_path)] += 1
                continue

            if file_path.exists():
                deletion_failed = True

        return removed_count, deletion_failed

    def _should_remove_artifact(
        self,
        file_path: Path,
        *,
        job: DownloadJob | None,
        now: datetime,
    ) -> bool:
        if job is not None:
            if job.status in {JobStatus.failed, JobStatus.cancelled, JobStatus.expired}:
                return True
            if job.status is JobStatus.completed:
                return self._is_temporary_artifact(file_path) or (
                    job.expires_at is not None and job.expires_at <= now
                )
            return False

        return self._file_is_expired(
            file_path,
            retention=self._orphan_retention(file_path),
            now=now,
        )

    def _is_active_job(
        self,
        job_id: UUID | None,
        job: DownloadJob | None,
        *,
        process_manager: DownloadProcessManager | None,
    ) -> bool:
        if job_id is not None and process_manager is not None:
            if process_manager.has_active_job(job_id):
                return True
        return job is not None and job.status in _ACTIVE_JOB_STATUSES

    def _safe_storage_file(self, candidate: Path, *, storage_dir: Path) -> Path | None:
        try:
            if candidate.name.casefold() in _STORAGE_MARKER_FILENAMES:
                return None
            resolved_candidate = candidate.resolve()
            if not resolved_candidate.is_relative_to(storage_dir):
                logger.warning("Cleanup skipped unsafe storage candidate")
                logger.debug("Cleanup unsafe storage candidate path=%s", resolved_candidate)
                return None
            if not resolved_candidate.is_file():
                return None
            return resolved_candidate
        except OSError:
            logger.debug("Cleanup skipped unreadable storage candidate")
            return None

    @staticmethod
    def _job_id_from_filename(file_path: Path) -> UUID | None:
        try:
            return UUID(file_path.name.split(".", maxsplit=1)[0])
        except (ValueError, IndexError):
            return None

    def _orphan_retention(self, file_path: Path) -> timedelta:
        if self._is_temporary_artifact(file_path):
            return self._failed_download_retention
        if file_path.suffix.casefold() in _FINAL_MEDIA_SUFFIXES:
            return self._download_expiration
        return self._temp_file_retention

    @staticmethod
    def _is_temporary_artifact(file_path: Path) -> bool:
        name = file_path.name.casefold()
        return (
            name.endswith(".part")
            or name.endswith(".ytdl")
            or name.endswith(".info.json")
            or name.endswith(".tmp")
            or name.endswith(".temp")
            or ".temp." in name
        )

    @staticmethod
    def _file_is_expired(file_path: Path, *, retention: timedelta, now: datetime) -> bool:
        if retention <= timedelta(0):
            return True
        try:
            modified_at = datetime.fromtimestamp(file_path.stat().st_mtime, tz=timezone.utc)
        except OSError:
            return False
        return modified_at + retention <= now

    @staticmethod
    def _artifact_kind(file_path: Path) -> str:
        name = file_path.name.casefold()
        if name.endswith(".part"):
            return "part"
        if name.endswith(".ytdl"):
            return "ytdl"
        if name.endswith(".info.json"):
            return "metadata"
        suffix = file_path.suffix.casefold().lstrip(".")
        return suffix or "temporary"

    @staticmethod
    def _remove_storage_path(file_path: Path, *, reason: str) -> bool:
        try:
            file_path.unlink()
            logger.debug("%s removed path=%s", reason.capitalize(), file_path)
            return True
        except FileNotFoundError:
            logger.debug("Missing %s file", reason)
            return False
        except OSError:
            logger.warning("Failed to remove %s file", reason, exc_info=True)
            return False


class CleanupWorker:
    """Runs the existing cleanup service at startup and on a fixed interval."""

    def __init__(
        self,
        *,
        cleanup_service: CleanupService,
        job_manager: JobManager,
        process_manager: DownloadProcessManager,
        interval: timedelta | None = None,
    ) -> None:
        settings = get_settings()
        self._cleanup_service = cleanup_service
        self._job_manager = job_manager
        self._process_manager = process_manager
        self._interval = interval or timedelta(minutes=settings.cleanup_interval_minutes)
        self._stop_event: asyncio.Event | None = None
        self._task: asyncio.Task[None] | None = None

    async def start(self) -> None:
        if self._task is not None:
            return

        self._stop_event = asyncio.Event()
        await asyncio.to_thread(self.run_once)
        self._task = asyncio.create_task(
            self._run_periodically(),
            name="nexora-cleanup-worker",
        )

    async def stop(self) -> None:
        if self._task is None:
            return

        if self._stop_event is not None:
            self._stop_event.set()
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        finally:
            self._task = None
            self._stop_event = None

    def run_once(self) -> None:
        logger.info("Cleanup started")
        try:
            removed_artifacts: Counter[str] = Counter()
            expired_jobs_removed = self._cleanup_service.cleanup_expired_downloads(
                job_manager=self._job_manager,
                process_manager=self._process_manager,
                log_started=False,
                removed_artifacts=removed_artifacts,
            )
            orphaned_artifacts = self._cleanup_service.cleanup_orphaned_artifacts(
                job_manager=self._job_manager,
                process_manager=self._process_manager,
            )
            removed_artifacts.update(orphaned_artifacts)
            summary = self._format_artifact_summary(removed_artifacts)
            logger.info(
                "Cleanup finished expired_jobs_removed=%s %s",
                expired_jobs_removed,
                summary,
            )
        except Exception:
            logger.exception("Cleanup worker pass failed")

    async def _run_periodically(self) -> None:
        assert self._stop_event is not None
        interval_seconds = self._interval.total_seconds()
        while True:
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=interval_seconds)
                return
            except TimeoutError:
                await asyncio.to_thread(self.run_once)

    @staticmethod
    def _format_artifact_summary(removed_artifacts: Counter[str]) -> str:
        if not removed_artifacts:
            return "removed_files=0"
        parts = [
            f"{artifact_type}={count}"
            for artifact_type, count in sorted(removed_artifacts.items())
        ]
        return f"removed_files={sum(removed_artifacts.values())} " + " ".join(parts)


@lru_cache
def get_cleanup_service() -> CleanupService:
    return CleanupService()
