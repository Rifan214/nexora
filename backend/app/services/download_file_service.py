from __future__ import annotations

import logging
from uuid import UUID

from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from app.core.exceptions import APIError
from app.models.job import JobStatus
from app.services.cleanup_service import CleanupService, get_cleanup_service
from app.services.job_manager import JobManager
from app.utils.storage import (
    build_attachment_content_disposition,
    build_download_filename,
    find_downloaded_file,
    guess_media_type,
)

logger = logging.getLogger(__name__)


class DownloadFileService:
    def create_file_response(
        self,
        job_id: UUID,
        *,
        job_manager: JobManager,
        cleanup_service: CleanupService | None = None,
    ) -> FileResponse:
        logger.info("File requested job_id=%s", job_id)
        job = job_manager.get_job(job_id)
        if job is None:
            logger.warning("Invalid file request job_id=%s reason=job_not_found", job_id)
            raise APIError(
                code="JOB_NOT_FOUND",
                message="Job not found",
                details="The requested download job does not exist",
                status_code=404,
            )

        if job.status is JobStatus.expired:
            logger.warning("Invalid file request job_id=%s reason=job_expired", job_id)
            raise APIError(
                code="JOB_EXPIRED",
                message="Job expired",
                details="The requested download is no longer available",
                status_code=410,
            )

        if job.status is not JobStatus.completed:
            logger.warning("Invalid file request job_id=%s reason=job_not_completed status=%s", job_id, job.status)
            raise APIError(
                code="JOB_NOT_COMPLETED",
                message="Download not ready",
                details="The requested download job has not completed",
                status_code=409,
            )

        file_path = find_downloaded_file(job_id)
        if file_path is None:
            logger.warning("File missing job_id=%s", job_id)
            raise APIError(
                code="DOWNLOAD_FILE_MISSING",
                message="Downloaded file not found",
                details="The completed download file is no longer available",
                status_code=404,
            )

        download_filename = build_download_filename(title=job.title, file_path=file_path)
        media_type = guess_media_type(file_path)
        headers = {"Content-Disposition": build_attachment_content_disposition(download_filename)}
        logger.info("File served job_id=%s filename=%s media_type=%s", job_id, download_filename, media_type)
        cleanup_service = cleanup_service or get_cleanup_service()
        # Starlette runs this task after the file body has been sent.
        background = BackgroundTask(
            cleanup_service.mark_completed_file_for_expiration,
            job_id,
            job_manager=job_manager,
        )
        return FileResponse(path=file_path, media_type=media_type, headers=headers, background=background)
