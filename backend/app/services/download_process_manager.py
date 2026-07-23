from __future__ import annotations

import logging
import subprocess
from contextlib import contextmanager
from dataclasses import dataclass, field
from functools import lru_cache
from threading import Event, RLock, Thread, current_thread, local
from typing import Any, Iterator
from uuid import UUID

import yt_dlp.postprocessor.ffmpeg as ffmpeg_module
from yt_dlp.utils import DownloadCancelled

logger = logging.getLogger(__name__)

_ffmpeg_context = local()
_original_ffmpeg_popen = ffmpeg_module.Popen


@dataclass
class _ActiveDownload:
    cancel_event: Event = field(default_factory=Event)
    worker: Thread | None = None
    downloader: Any | None = None
    process: subprocess.Popen | None = None


class DownloadProcessManager:
    """Owns cancellation signals and external processes for active jobs."""

    def __init__(self, *, termination_timeout_seconds: float = 2.0) -> None:
        self._active_downloads: dict[UUID, _ActiveDownload] = {}
        self._termination_timeout_seconds = termination_timeout_seconds
        self._lock = RLock()

    def register_job(self, job_id: UUID, *, worker: Thread | None = None) -> None:
        with self._lock:
            active_download = self._active_downloads.setdefault(job_id, _ActiveDownload())
            if worker is not None:
                active_download.worker = worker

        logger.info("Download process registered job_id=%s", job_id)

    @contextmanager
    def worker_context(self, job_id: UUID) -> Iterator[None]:
        self.register_job(job_id, worker=current_thread())
        previous_binding = getattr(_ffmpeg_context, "binding", None)
        _ffmpeg_context.binding = (self, job_id)
        try:
            yield
        finally:
            if previous_binding is None:
                try:
                    del _ffmpeg_context.binding
                except AttributeError:
                    pass
            else:
                _ffmpeg_context.binding = previous_binding

    def current_job_id(self) -> UUID | None:
        """Return the job bound to the current worker thread, if any."""
        binding = getattr(_ffmpeg_context, "binding", None)
        if binding is None or binding[0] is not self:
            return None
        return binding[1]

    def request_cancellation(self, job_id: UUID) -> bool:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            if active_download is None:
                return False

            active_download.cancel_event.set()
            downloader = active_download.downloader
            process = active_download.process

        logger.info("Download cancellation requested job_id=%s", job_id)
        if process is not None:
            self._terminate_process(job_id, process)
        if downloader is not None:
            self._close_downloader(job_id, downloader)
        return True

    def raise_if_cancelled(self, job_id: UUID) -> None:
        if self.is_cancellation_requested(job_id):
            raise DownloadCancelled("Download cancelled")

    def is_cancellation_requested(self, job_id: UUID) -> bool:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            return active_download is not None and active_download.cancel_event.is_set()

    def attach_subprocess(self, job_id: UUID, process: subprocess.Popen) -> None:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            if active_download is None:
                return

            active_download.process = process
            cancellation_requested = active_download.cancel_event.is_set()

        logger.info("FFmpeg process registered job_id=%s process_id=%s", job_id, process.pid)
        if cancellation_requested:
            self._terminate_process(job_id, process)

    def attach_downloader(self, job_id: UUID, downloader: Any) -> None:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            if active_download is None:
                return
            active_download.downloader = downloader
            cancellation_requested = active_download.cancel_event.is_set()

        logger.info("yt-dlp resource registered job_id=%s", job_id)
        if cancellation_requested:
            self._close_downloader(job_id, downloader)

    def detach_downloader(self, job_id: UUID, downloader: Any) -> None:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            if active_download is None or active_download.downloader is not downloader:
                return
            active_download.downloader = None

        logger.info("yt-dlp resource released job_id=%s", job_id)

    def detach_subprocess(self, job_id: UUID, process: subprocess.Popen) -> None:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            if active_download is None or active_download.process is not process:
                return
            active_download.process = None

        logger.info("FFmpeg process released job_id=%s process_id=%s", job_id, process.pid)

    def finish_job(self, job_id: UUID) -> None:
        with self._lock:
            active_download = self._active_downloads.pop(job_id, None)

        if active_download is None:
            return
        if active_download.process is not None:
            self._terminate_process(job_id, active_download.process)
        if active_download.downloader is not None:
            self._close_downloader(job_id, active_download.downloader)
        logger.info("Download process released job_id=%s", job_id)

    def has_active_job(self, job_id: UUID) -> bool:
        with self._lock:
            return job_id in self._active_downloads

    def has_active_process(self, job_id: UUID) -> bool:
        with self._lock:
            active_download = self._active_downloads.get(job_id)
            return active_download is not None and active_download.process is not None

    def _close_downloader(self, job_id: UUID, downloader: Any) -> None:
        close = getattr(downloader, "close", None)
        if not callable(close):
            return
        try:
            close()
        except Exception:
            logger.exception("yt-dlp resource release failed job_id=%s", job_id)

    def _terminate_process(self, job_id: UUID, process: subprocess.Popen) -> None:
        if process.poll() is not None:
            return

        logger.info("FFmpeg termination started job_id=%s process_id=%s", job_id, process.pid)
        try:
            process.terminate()
        except OSError:
            logger.warning("FFmpeg graceful termination failed job_id=%s process_id=%s", job_id, process.pid)

        if process.poll() is None:
            try:
                process.wait(timeout=self._termination_timeout_seconds)
            except subprocess.TimeoutExpired:
                logger.warning("FFmpeg termination timed out job_id=%s process_id=%s", job_id, process.pid)
            except OSError:
                logger.warning("FFmpeg wait failed job_id=%s process_id=%s", job_id, process.pid)

        if process.poll() is None:
            try:
                process.kill()
                process.wait(timeout=self._termination_timeout_seconds)
            except (OSError, subprocess.TimeoutExpired):
                logger.exception("FFmpeg force termination failed job_id=%s process_id=%s", job_id, process.pid)
            else:
                logger.info("FFmpeg process force-killed job_id=%s process_id=%s", job_id, process.pid)
        elif process.poll() is not None:
            logger.info("FFmpeg process terminated job_id=%s process_id=%s", job_id, process.pid)


class _TrackedFFmpegPopen(_original_ffmpeg_popen):
    """Associates yt-dlp's FFmpeg child with the current download job."""

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._nexora_binding = getattr(_ffmpeg_context, "binding", None)
        if self._nexora_binding is not None:
            manager, job_id = self._nexora_binding
            manager.attach_subprocess(job_id, self)

    def communicate_or_kill(self, *args, **kwargs):
        try:
            return super().communicate_or_kill(*args, **kwargs)
        finally:
            self._release_tracking()

    def __exit__(self, *args):
        try:
            return super().__exit__(*args)
        finally:
            self._release_tracking()

    def _release_tracking(self) -> None:
        binding = self._nexora_binding
        self._nexora_binding = None
        if binding is not None:
            manager, job_id = binding
            manager.detach_subprocess(job_id, self)


# yt-dlp keeps this class in its FFmpeg module. Replacing only that reference
# preserves the download engine while making its child process cancellable.
ffmpeg_module.Popen = _TrackedFFmpegPopen


@lru_cache
def get_download_process_manager() -> DownloadProcessManager:
    return DownloadProcessManager()
