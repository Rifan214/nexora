from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.api.dependencies import get_cleanup_service
from app.api.routes.media import get_media_service
from app.main import create_app
from app.models.requests import MediaDownloadRequest
from app.services.cleanup_service import CleanupService
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
