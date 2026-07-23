from __future__ import annotations

import sys
import threading
import time
from datetime import timedelta

import pytest
import yt_dlp.postprocessor.ffmpeg as ffmpeg_module
from fastapi.testclient import TestClient

from app.api.dependencies import get_cleanup_service
from app.main import create_app
from app.models.job import JobStatus
from app.services.cleanup_service import CleanupService
from app.services.download_process_manager import (
    DownloadProcessManager,
    get_download_process_manager,
)
from app.services.job_manager import JobManager, get_job_manager
from app.services.media_service import MediaService
from app.utils.storage import get_temp_storage_dir


@pytest.fixture(autouse=True)
def clear_shared_managers() -> None:
    get_job_manager.cache_clear()
    get_download_process_manager.cache_clear()
    yield
    get_job_manager.cache_clear()
    get_download_process_manager.cache_clear()


def test_cancel_endpoint_finalizes_job_without_a_running_worker() -> None:
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    cleanup_service = CleanupService(failed_download_retention=timedelta(minutes=5))
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=cancel-endpoint",
        platform="youtube",
    )
    job_manager.update_progress(job.job_id, 35)
    partial_files = [
        get_temp_storage_dir() / f"{job.job_id}.mp4.part",
        get_temp_storage_dir() / f"{job.job_id}.f399.mp4",
        get_temp_storage_dir() / f"{job.job_id}.ytdl",
    ]
    for partial_file in partial_files:
        partial_file.write_bytes(b"partial")

    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: job_manager
    app.dependency_overrides[get_download_process_manager] = lambda: process_manager
    app.dependency_overrides[get_cleanup_service] = lambda: cleanup_service
    try:
        response = TestClient(app).post(f"/jobs/{job.job_id}/cancel")

        assert response.status_code == 200
        assert response.json()["data"]["status"] == JobStatus.cancelled.value
        assert all(not partial_file.exists() for partial_file in partial_files)
        cancelled_job = job_manager.get_job(job.job_id)
        assert cancelled_job is not None
        assert cancelled_job.status is JobStatus.cancelled
        assert cancelled_job.download_url is None
    finally:
        app.dependency_overrides.clear()
        for partial_file in partial_files:
            partial_file.unlink(missing_ok=True)


def test_cancel_endpoint_marks_registered_worker_as_cancelling() -> None:
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=cancel-worker",
        platform="youtube",
    )
    job_manager.update_progress(job.job_id, 42)
    process_manager.register_job(job.job_id)
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: job_manager
    app.dependency_overrides[get_download_process_manager] = lambda: process_manager

    try:
        response = TestClient(app).post(f"/jobs/{job.job_id}/cancel")

        assert response.status_code == 200
        assert response.json()["data"]["status"] == JobStatus.cancelling.value
        assert process_manager.is_cancellation_requested(job.job_id)
        assert job_manager.get_job(job.job_id).status is JobStatus.cancelling
    finally:
        app.dependency_overrides.clear()
        process_manager.finish_job(job.job_id)


def test_cancel_endpoint_ignores_completed_job() -> None:
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=already-completed",
        platform="youtube",
    )
    job_manager.mark_completed(job.job_id)
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: job_manager
    app.dependency_overrides[get_download_process_manager] = lambda: process_manager

    try:
        response = TestClient(app).post(f"/jobs/{job.job_id}/cancel")

        assert response.status_code == 200
        assert response.json()["data"]["status"] == JobStatus.completed.value
        assert not process_manager.is_cancellation_requested(job.job_id)
    finally:
        app.dependency_overrides.clear()


def test_cancel_endpoint_rejects_failed_job() -> None:
    job_manager = JobManager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=already-failed",
        platform="youtube",
    )
    job_manager.mark_failed(job.job_id, error_message="Download failed")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: job_manager

    try:
        response = TestClient(app).post(f"/jobs/{job.job_id}/cancel")

        assert response.status_code == 409
        assert response.json()["error"]["code"] == "JOB_NOT_CANCELLABLE"
    finally:
        app.dependency_overrides.clear()


def test_cancellation_terminates_tracked_ffmpeg_process() -> None:
    process_manager = DownloadProcessManager(termination_timeout_seconds=1)
    job = JobManager().create_job(
        media_url="https://www.youtube.com/watch?v=ffmpeg-cancel",
        platform="youtube",
    )
    process_manager.register_job(job.job_id)

    try:
        with process_manager.worker_context(job.job_id):
            with ffmpeg_module.Popen(
                [sys.executable, "-c", "import time; time.sleep(30)"],
            ) as process:
                assert process_manager.has_active_process(job.job_id)
                assert process_manager.request_cancellation(job.job_id)
                assert process.wait(timeout=2) is not None

        assert not process_manager.has_active_process(job.job_id)
    finally:
        process_manager.finish_job(job.job_id)

    assert not process_manager.has_active_job(job.job_id)


def test_cancelled_worker_removes_partial_files_and_finishes_job() -> None:
    process_manager = DownloadProcessManager()
    service = MediaService(process_manager=process_manager)
    job_manager = get_job_manager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=cancelled-worker",
        platform="youtube",
        format_id="18",
        output_type="video",
    )
    partial_file = get_temp_storage_dir() / f"{job.job_id}.mp4.part"
    partial_file.write_bytes(b"partial")
    process_manager.register_job(job.job_id)
    process_manager.request_cancellation(job.job_id)

    try:
        service._download_job_background(job.job_id, job.media_url, "18", "video")

        cancelled_job = job_manager.get_job(job.job_id)
        assert cancelled_job is not None
        assert cancelled_job.status is JobStatus.cancelled
        assert not partial_file.exists()
        assert not process_manager.has_active_job(job.job_id)
    finally:
        partial_file.unlink(missing_ok=True)


def test_cancellation_hook_stops_an_active_yt_dlp_worker(monkeypatch: pytest.MonkeyPatch) -> None:
    entered_download = threading.Event()

    class BlockingYoutubeDL:
        def __init__(self, options: dict) -> None:
            self._progress_hook = options.get("progress_hooks", [lambda _: None])[0]

        def __enter__(self) -> "BlockingYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def extract_info(self, _: str, *, download: bool) -> dict:
            if not download:
                return {"title": "Cancelable", "extractor_key": "Youtube"}

            entered_download.set()
            while True:
                self._progress_hook(
                    {
                        "status": "downloading",
                        "downloaded_bytes": 1,
                        "total_bytes": 100,
                    }
                )
                time.sleep(0.01)

    monkeypatch.setattr("app.services.media_service.YoutubeDL", BlockingYoutubeDL)
    process_manager = DownloadProcessManager()
    service = MediaService(process_manager=process_manager)
    job_manager = get_job_manager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=active-cancel",
        platform="youtube",
        format_id="18",
        output_type="video",
    )
    worker = threading.Thread(
        target=service._download_job_background,
        args=(job.job_id, job.media_url, "18", "video"),
    )
    worker.start()

    assert entered_download.wait(timeout=1)
    job_manager.mark_cancelling(job.job_id)
    assert process_manager.request_cancellation(job.job_id)
    worker.join(timeout=2)

    assert not worker.is_alive()
    cancelled_job = job_manager.get_job(job.job_id)
    assert cancelled_job is not None
    assert cancelled_job.status is JobStatus.cancelled
    assert not process_manager.has_active_job(job.job_id)


def test_cancellation_closes_yt_dlp_during_background_probe(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    entered_probe = threading.Event()
    release_probe = threading.Event()
    closed = threading.Event()

    class BlockingProbeYoutubeDL:
        def __init__(self, _: dict) -> None:
            pass

        def __enter__(self) -> "BlockingProbeYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            release_probe.set()

        def close(self) -> None:
            closed.set()
            release_probe.set()

        def extract_info(self, _: str, *, download: bool) -> dict:
            if download:
                raise AssertionError("The probe should be cancelled first")
            entered_probe.set()
            release_probe.wait(timeout=2)
            return {"title": "Cancelled probe", "extractor_key": "Youtube"}

    monkeypatch.setattr("app.services.media_service.YoutubeDL", BlockingProbeYoutubeDL)
    process_manager = DownloadProcessManager()
    service = MediaService(process_manager=process_manager)
    job_manager = get_job_manager()
    job = job_manager.create_job(
        media_url="https://www.youtube.com/watch?v=probe-cancel",
        platform="youtube",
        format_id="18",
        output_type="video",
    )
    worker = threading.Thread(
        target=service._download_job_background,
        args=(job.job_id, job.media_url, "18", "video"),
    )
    worker.start()

    assert entered_probe.wait(timeout=1)
    job_manager.mark_cancelling(job.job_id)
    assert process_manager.request_cancellation(job.job_id)
    assert closed.wait(timeout=1)
    worker.join(timeout=2)

    assert not worker.is_alive()
    cancelled_job = job_manager.get_job(job.job_id)
    assert cancelled_job is not None
    assert cancelled_job.status is JobStatus.cancelled
    assert not process_manager.has_active_job(job.job_id)
