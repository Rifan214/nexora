from __future__ import annotations

import asyncio
import os
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient

from app.api.dependencies import get_cleanup_service
from app.api.routes.media import get_media_service
from app.main import create_app
from app.models.requests import MediaDownloadRequest
from app.services.cleanup_service import CleanupService, CleanupWorker
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager, get_job_manager
from app.utils.storage import get_temp_storage_dir


def test_cleanup_removes_expired_completed_job_and_file() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=-1))
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=expired-file", platform="youtube")
    manager.mark_completed(job.job_id)
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp4"
    file_path.write_bytes(b"expired-media")

    try:
        removed_count = CleanupService().cleanup_expired_downloads(job_manager=manager)

        assert removed_count == 1
        assert manager.get_job(job.job_id) is None
        assert not file_path.exists()
    finally:
        file_path.unlink(missing_ok=True)


def test_cleanup_removes_expired_completed_job_when_file_is_missing() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=-1))
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=missing-expired-file", platform="youtube")
    manager.mark_completed(job.job_id)

    removed_count = CleanupService().cleanup_expired_downloads(job_manager=manager)

    assert removed_count == 1
    assert manager.get_job(job.job_id) is None


def test_completed_file_gets_short_retention_after_response_is_sent() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=30))
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=served-file",
        platform="youtube",
        title="Served file",
    )
    manager.mark_completed(job.job_id)
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp4"
    file_path.write_bytes(b"served-media")
    cleanup_service = CleanupService(temp_file_retention=timedelta(minutes=12))
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager
    app.dependency_overrides[get_cleanup_service] = lambda: cleanup_service

    before_request = datetime.now(timezone.utc)
    try:
        response = TestClient(app).get(f"/files/{job.job_id}")

        assert response.status_code == 200
        scheduled_job = manager.get_job(job.job_id)
        assert scheduled_job is not None
        assert scheduled_job.expires_at is not None
        assert scheduled_job.expires_at > before_request + timedelta(minutes=11)
        assert scheduled_job.expires_at <= datetime.now(timezone.utc) + timedelta(minutes=12, seconds=1)
    finally:
        app.dependency_overrides.clear()
        file_path.unlink(missing_ok=True)


def test_failed_download_removes_all_job_artifacts_immediately() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=failed-file",
        platform="youtube",
    )
    manager.mark_failed(job.job_id, error_message="Download failed")
    file_paths = [
        get_temp_storage_dir() / f"{job.job_id}.mp4.part",
        get_temp_storage_dir() / f"{job.job_id}.f399.mp4",
        get_temp_storage_dir() / f"{job.job_id}.ytdl",
        get_temp_storage_dir() / f"{job.job_id}.info.json",
    ]
    for file_path in file_paths:
        file_path.write_bytes(b"partial-media")

    try:
        removed_count = CleanupService(failed_download_retention=timedelta(minutes=3)).cleanup_failed_download(
            job.job_id,
            job_manager=manager,
        )

        assert removed_count == len(file_paths)
        assert all(not file_path.exists() for file_path in file_paths)
        failed_job = manager.get_job(job.job_id)
        assert failed_job is not None
        assert failed_job.status.value == "failed"
        assert failed_job.expires_at is not None
    finally:
        for file_path in file_paths:
            file_path.unlink(missing_ok=True)


def test_cleanup_leaves_active_jobs_and_files_untouched() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=30))
    past = datetime.now(timezone.utc) - timedelta(minutes=1)
    pending_job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=pending",
        platform="youtube",
        expires_at=past,
    )
    completed_job = manager.create_job(media_url="https://www.youtube.com/watch?v=active-completed", platform="youtube")
    manager.mark_completed(completed_job.job_id)
    pending_file = get_temp_storage_dir() / f"{pending_job.job_id}.mp4"
    completed_file = get_temp_storage_dir() / f"{completed_job.job_id}.mp4"
    pending_file.write_bytes(b"pending-media")
    completed_file.write_bytes(b"completed-media")

    try:
        removed_count = CleanupService().cleanup_expired_downloads(job_manager=manager)

        assert removed_count == 0
        assert manager.get_job(pending_job.job_id) is not None
        assert manager.get_job(completed_job.job_id) is not None
        assert pending_file.exists()
        assert completed_file.exists()
    finally:
        pending_file.unlink(missing_ok=True)
        completed_file.unlink(missing_ok=True)


def test_cleanup_worker_removes_stale_artifacts_and_preserves_active_files(
    monkeypatch,
) -> None:
    storage_dir = _create_test_storage_dir()
    monkeypatch.setattr("app.services.cleanup_service.get_temp_storage_dir", lambda: storage_dir)
    manager = JobManager()
    process_manager = DownloadProcessManager()
    active_job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=active-artifact",
        platform="youtube",
    )
    process_manager.register_job(active_job.job_id)

    active_file = storage_dir / f"{active_job.job_id}.mp4.part"
    stale_video = storage_dir / "2e198a17-fd24-4988-a720-a5bf6e7f15b2.mp4"
    stale_part = storage_dir / "925ee23d-5ea4-41dc-8c24-93b064ad9d87.webm.part"
    stale_ytdl = storage_dir / "a84587ae-df09-4b9b-a818-a3fd50f64b2f.ytdl"
    stale_metadata = storage_dir / "bf9de4fb-7a20-4260-b438-75a3fda64697.info.json"
    storage_marker = storage_dir / ".gitkeep"
    try:
        for file_path in [
            active_file,
            stale_video,
            stale_part,
            stale_ytdl,
            stale_metadata,
            storage_marker,
        ]:
            file_path.write_bytes(b"temporary-data")

        old_timestamp = (datetime.now(timezone.utc) - timedelta(minutes=31)).timestamp()
        for file_path in [
            active_file,
            stale_video,
            stale_part,
            stale_ytdl,
            stale_metadata,
            storage_marker,
        ]:
            os.utime(file_path, (old_timestamp, old_timestamp))

        worker = CleanupWorker(
            cleanup_service=CleanupService(
                download_expiration=timedelta(minutes=30),
                temp_file_retention=timedelta(minutes=15),
                failed_download_retention=timedelta(minutes=0),
            ),
            job_manager=manager,
            process_manager=process_manager,
            interval=timedelta(minutes=5),
        )

        worker.run_once()

        assert active_file.exists()
        assert not stale_video.exists()
        assert not stale_part.exists()
        assert not stale_ytdl.exists()
        assert not stale_metadata.exists()
        assert storage_marker.exists()
    finally:
        active_file.unlink(missing_ok=True)
        storage_marker.unlink(missing_ok=True)
        storage_dir.rmdir()


def test_cleanup_worker_runs_an_immediate_startup_pass(monkeypatch) -> None:
    storage_dir = _create_test_storage_dir()
    monkeypatch.setattr("app.services.cleanup_service.get_temp_storage_dir", lambda: storage_dir)
    stale_part = storage_dir / "9f1bf076-dd9b-4f49-a676-0f0e04b51adb.mp4.part"
    try:
        stale_part.write_bytes(b"partial-download")

        worker = CleanupWorker(
            cleanup_service=CleanupService(failed_download_retention=timedelta(minutes=0)),
            job_manager=JobManager(),
            process_manager=DownloadProcessManager(),
            interval=timedelta(minutes=5),
        )

        async def start_and_stop_worker() -> None:
            await worker.start()
            await worker.stop()

        asyncio.run(start_and_stop_worker())

        assert not stale_part.exists()
    finally:
        stale_part.unlink(missing_ok=True)
        storage_dir.rmdir()


def test_jobs_endpoint_runs_lazy_cleanup_before_returning_job() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=30))
    expired_job = _create_expired_completed_job(manager)
    active_job = manager.create_job(media_url="https://www.youtube.com/watch?v=active-job", platform="youtube")
    expired_file = get_temp_storage_dir() / f"{expired_job.job_id}.mp4"
    expired_file.write_bytes(b"expired-media")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager

    try:
        response = TestClient(app).get(f"/jobs/{active_job.job_id}")

        assert response.status_code == 200
        assert manager.get_job(expired_job.job_id) is None
        assert not expired_file.exists()
    finally:
        app.dependency_overrides.clear()
        expired_file.unlink(missing_ok=True)


def test_files_endpoint_runs_lazy_cleanup_before_serving_file() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=30))
    expired_job = _create_expired_completed_job(manager)
    active_job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=active-file",
        platform="youtube",
        title="Active File",
    )
    manager.mark_completed(active_job.job_id)
    expired_file = get_temp_storage_dir() / f"{expired_job.job_id}.mp4"
    active_file = get_temp_storage_dir() / f"{active_job.job_id}.mp4"
    expired_file.write_bytes(b"expired-media")
    active_file.write_bytes(b"active-media")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager

    try:
        response = TestClient(app).get(f"/files/{active_job.job_id}")

        assert response.status_code == 200
        assert response.content == b"active-media"
        assert manager.get_job(expired_job.job_id) is None
        assert not expired_file.exists()
    finally:
        app.dependency_overrides.clear()
        expired_file.unlink(missing_ok=True)
        active_file.unlink(missing_ok=True)


def test_media_download_endpoint_runs_lazy_cleanup_before_creating_job() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=30))
    expired_job = _create_expired_completed_job(manager)
    expired_file = get_temp_storage_dir() / f"{expired_job.job_id}.mp4"
    expired_file.write_bytes(b"expired-media")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager
    app.dependency_overrides[get_media_service] = lambda: _FakeMediaService(manager)

    try:
        response = TestClient(app).post(
            "/media/download",
            json={
                "url": "https://www.youtube.com/watch?v=new-job",
                "format_id": "18",
                "type": "video",
            },
        )

        assert response.status_code == 200
        assert manager.get_job(expired_job.job_id) is None
        assert not expired_file.exists()
    finally:
        app.dependency_overrides.clear()
        expired_file.unlink(missing_ok=True)


def test_lazy_cleanup_failure_does_not_interrupt_request() -> None:
    manager = JobManager()
    active_job = manager.create_job(media_url="https://www.youtube.com/watch?v=cleanup-error", platform="youtube")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager
    app.dependency_overrides[get_cleanup_service] = lambda: _FailingCleanupService()

    try:
        response = TestClient(app).get(f"/jobs/{active_job.job_id}")

        assert response.status_code == 200
    finally:
        app.dependency_overrides.clear()


def _create_expired_completed_job(manager: JobManager):
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=expired", platform="youtube")
    completed_job = manager.mark_completed(job.job_id)
    expired_job = completed_job.model_copy(update={"expires_at": datetime.now(timezone.utc) - timedelta(minutes=1)})
    manager._jobs[job.job_id] = expired_job
    return expired_job


def _create_test_storage_dir():
    storage_dir = get_temp_storage_dir() / f"cleanup-test-{uuid4()}"
    storage_dir.mkdir()
    return storage_dir


class _FakeMediaService:
    def __init__(self, manager: JobManager) -> None:
        self._manager = manager

    def create_download_job(self, request: MediaDownloadRequest):
        return self._manager.create_job(
            media_url=request.url,
            platform="youtube",
            format_id=request.format_id,
            output_type=request.type,
        )


class _FailingCleanupService:
    def cleanup_expired_downloads(self, *, job_manager: JobManager) -> int:
        raise RuntimeError("cleanup failed")
