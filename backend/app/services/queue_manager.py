from __future__ import annotations

import logging
from collections import deque
from dataclasses import dataclass
from threading import RLock
from typing import Callable
from uuid import UUID

from app.models.job import DownloadJob, JobStatus
from app.services.job_manager import JobManager, get_job_manager

logger = logging.getLogger(__name__)

DownloadStarter = Callable[[], None]
_TERMINAL_STATUSES = {
    JobStatus.completed,
    JobStatus.failed,
    JobStatus.cancelled,
}


@dataclass(frozen=True)
class _QueuedDownload:
    job_id: UUID
    starter: DownloadStarter


class QueueManager:
    """Schedules download workers while keeping one active slot for V1.1."""

    def __init__(self, *, job_manager: JobManager, max_concurrent_downloads: int = 1) -> None:
        if max_concurrent_downloads < 1:
            raise ValueError("max_concurrent_downloads must be at least one")

        self._job_manager = job_manager
        self._max_concurrent_downloads = max_concurrent_downloads
        self._queued_downloads: deque[_QueuedDownload] = deque()
        self._active_job_ids: set[UUID] = set()
        self._lock = RLock()
        self._job_manager.add_update_listener(self._handle_job_update)

    @property
    def max_concurrent_downloads(self) -> int:
        return self._max_concurrent_downloads

    def enqueue(self, job_id: UUID, *, starter: DownloadStarter) -> None:
        """Start a job immediately when capacity exists, otherwise queue it FIFO."""
        entry = _QueuedDownload(job_id=job_id, starter=starter)
        with self._lock:
            if self._can_start_locked():
                self._active_job_ids.add(job_id)
                start_now = True
            else:
                self._queued_downloads.append(entry)
                self._job_manager.mark_queued(job_id)
                start_now = False

        if start_now:
            logger.info("Queue starting job immediately job_id=%s", job_id)
            self._start_entry(entry)
            return

        logger.info("Job queued job_id=%s queue_depth=%s", job_id, self.queue_depth())

    def dequeue(self) -> UUID | None:
        """Remove and return the next queued job identifier without starting it."""
        with self._lock:
            if not self._queued_downloads:
                return None
            return self._queued_downloads.popleft().job_id

    def peek(self) -> UUID | None:
        with self._lock:
            if not self._queued_downloads:
                return None
            return self._queued_downloads[0].job_id

    def has_active_download(self) -> bool:
        with self._lock:
            return bool(self._active_job_ids)

    def queue_depth(self) -> int:
        with self._lock:
            return len(self._queued_downloads)

    def start_next_if_available(self) -> None:
        """Fill the available active slot using FIFO ordering."""
        while True:
            with self._lock:
                if not self._can_start_locked() or not self._queued_downloads:
                    return
                entry = self._queued_downloads.popleft()

            job = self._job_manager.get_job(entry.job_id)
            if job is None or job.status is not JobStatus.queued:
                logger.debug("Queue skipped unavailable job_id=%s", entry.job_id)
                continue

            with self._lock:
                if not self._can_start_locked():
                    self._queued_downloads.appendleft(entry)
                    return
                self._active_job_ids.add(entry.job_id)

            logger.info("Queue starting next job job_id=%s queue_depth=%s", entry.job_id, self.queue_depth())
            self._start_entry(entry)

    def _handle_job_update(self, job: DownloadJob) -> None:
        if job.status not in _TERMINAL_STATUSES:
            return

        with self._lock:
            was_active = job.job_id in self._active_job_ids
            self._active_job_ids.discard(job.job_id)
            self._queued_downloads = deque(
                entry for entry in self._queued_downloads if entry.job_id != job.job_id
            )

        if was_active:
            logger.info("Queue released active job job_id=%s status=%s", job.job_id, job.status)
            self.start_next_if_available()

    def _start_entry(self, entry: _QueuedDownload) -> None:
        try:
            entry.starter()
        except Exception:
            logger.exception("Queue failed to start job job_id=%s", entry.job_id)
            job = self._job_manager.get_job(entry.job_id)
            if job is not None and job.status in {JobStatus.pending, JobStatus.queued, JobStatus.processing}:
                self._job_manager.mark_failed(
                    entry.job_id,
                    error_message="Unable to start the download worker",
                )

    def _can_start_locked(self) -> bool:
        return len(self._active_job_ids) < self._max_concurrent_downloads


_queue_manager: QueueManager | None = None
_queue_manager_lock = RLock()


def get_queue_manager() -> QueueManager:
    """Return the queue bound to the current in-memory job registry."""
    global _queue_manager

    job_manager = get_job_manager()
    with _queue_manager_lock:
        if _queue_manager is None or _queue_manager._job_manager is not job_manager:
            _queue_manager = QueueManager(job_manager=job_manager, max_concurrent_downloads=1)
        return _queue_manager
