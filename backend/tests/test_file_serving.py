from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.core.exceptions import APIError
from app.services.download_file_service import DownloadFileService
from app.services.job_manager import JobManager, get_job_manager
from app.utils.storage import get_temp_storage_dir


def test_completed_job_returns_attachment_with_title_filename() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=file",
        platform="youtube",
        title="Example / Video\r\n",
    )
    manager.mark_completed(job.job_id, download_url=f"/files/{job.job_id}")
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp4"
    file_path.write_bytes(b"media")
    try:
        response = DownloadFileService().create_file_response(job.job_id, job_manager=manager)

        assert response.media_type == "video/mp4"
        assert response.headers["content-disposition"] == 'attachment; filename="Example Video.mp4"'
        assert job.job_id.hex not in response.headers["content-disposition"]
    finally:
        file_path.unlink(missing_ok=True)


def test_files_endpoint_downloads_completed_job() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=endpoint",
        platform="youtube",
        title="Endpoint Video",
    )
    manager.mark_completed(job.job_id)
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp4"
    file_path.write_bytes(b"endpoint-media")
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager

    try:
        response = TestClient(app).get(f"/files/{job.job_id}")

        assert response.status_code == 200
        assert response.content == b"endpoint-media"
        assert response.headers["content-type"] == "video/mp4"
        assert response.headers["content-disposition"] == 'attachment; filename="Endpoint Video.mp4"'
    finally:
        app.dependency_overrides.clear()
        file_path.unlink(missing_ok=True)


def test_direct_file_service_also_schedules_backend_cleanup() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=direct-service",
        platform="youtube",
    )
    manager.mark_completed(job.job_id)
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp4"
    file_path.write_bytes(b"media")
    try:
        response = DownloadFileService().create_file_response(job.job_id, job_manager=manager)

        assert response.background is not None
        asyncio.run(response.background())
        scheduled_job = manager.get_job(job.job_id)
        assert scheduled_job is not None
        assert scheduled_job.expires_at is not None
    finally:
        file_path.unlink(missing_ok=True)


def test_completed_audio_job_returns_an_mp3_attachment() -> None:
    manager = JobManager()
    job = manager.create_job(
        media_url="https://www.youtube.com/watch?v=audio-file",
        platform="youtube",
        title="Example Audio",
        output_type="audio",
    )
    manager.mark_completed(job.job_id)
    file_path = get_temp_storage_dir() / f"{job.job_id}.mp3"
    file_path.write_bytes(b"mp3-media")
    try:
        response = DownloadFileService().create_file_response(job.job_id, job_manager=manager)

        assert response.media_type == "audio/mpeg"
        assert response.headers["content-disposition"] == 'attachment; filename="Example Audio.mp3"'
    finally:
        file_path.unlink(missing_ok=True)


def test_files_endpoint_missing_job_returns_standardized_response() -> None:
    manager = JobManager()
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager

    try:
        response = TestClient(app).get(f"/files/{uuid4()}")

        assert response.status_code == 404
        payload = response.json()
        assert payload["success"] is False
        assert payload["message"] == "Job not found"
        assert payload["error"]["code"] == "JOB_NOT_FOUND"
    finally:
        app.dependency_overrides.clear()


def test_missing_job_returns_standardized_error() -> None:
    with pytest.raises(APIError) as error:
        DownloadFileService().create_file_response(uuid4(), job_manager=JobManager())

    assert error.value.code == "JOB_NOT_FOUND"
    assert error.value.status_code == 404


def test_completed_job_never_exposes_internal_download_url() -> None:
    manager = JobManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=private-path", platform="youtube")

    completed_job = manager.mark_completed(job.job_id, download_url="E:\\storage\\temp\\private-path.mp4")

    assert completed_job.download_url == f"/files/{job.job_id}"


def test_completed_job_gets_expiration_time() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=45))
    before_completion = datetime.now(timezone.utc)
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=expires-at", platform="youtube")

    completed_job = manager.mark_completed(job.job_id)

    assert completed_job.expires_at is not None
    assert completed_job.expires_at > before_completion
    assert completed_job.expires_at <= datetime.now(timezone.utc) + timedelta(minutes=45, seconds=1)


def test_not_completed_job_returns_standardized_error() -> None:
    manager = JobManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=pending", platform="youtube")

    with pytest.raises(APIError) as error:
        DownloadFileService().create_file_response(job.job_id, job_manager=manager)

    assert error.value.code == "JOB_NOT_COMPLETED"
    assert error.value.status_code == 409


def test_expired_job_returns_standardized_error() -> None:
    manager = JobManager(download_expiration=timedelta(minutes=-1))
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=expired", platform="youtube")
    manager.mark_completed(job.job_id)

    with pytest.raises(APIError) as error:
        DownloadFileService().create_file_response(job.job_id, job_manager=manager)

    assert error.value.code == "JOB_EXPIRED"
    assert error.value.status_code == 410


def test_missing_completed_file_returns_standardized_error() -> None:
    manager = JobManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=missing", platform="youtube")
    manager.mark_completed(job.job_id, download_url=f"/files/{job.job_id}")

    with pytest.raises(APIError) as error:
        DownloadFileService().create_file_response(job.job_id, job_manager=manager)

    assert error.value.code == "DOWNLOAD_FILE_MISSING"
    assert error.value.status_code == 404


@pytest.mark.parametrize(
    ("suffix", "expected_media_type"),
    [(".mp4", "video/mp4"), (".mp3", "audio/mpeg"), (".unknown", "application/octet-stream")],
)
def test_media_type_is_derived_from_the_file_extension(
    suffix: str,
    expected_media_type: str,
) -> None:
    manager = JobManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=mime", platform="youtube", title="Media")
    manager.mark_completed(job.job_id, download_url=f"/files/{job.job_id}")
    file_path = get_temp_storage_dir() / f"{job.job_id}{suffix}"
    file_path.write_bytes(b"media")
    try:
        response = DownloadFileService().create_file_response(job.job_id, job_manager=manager)

        assert response.media_type == expected_media_type
    finally:
        file_path.unlink(missing_ok=True)
