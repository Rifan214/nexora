from __future__ import annotations

import logging
from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.dependencies import run_lazy_cleanup
from app.core.exceptions import APIError
from app.models.job import DownloadJobStatusResponse, JobDeleteResponse, JobStatus
from app.models.response import APIResponse
from app.services.cleanup_service import CleanupService, get_cleanup_service
from app.services.download_process_manager import (
    DownloadProcessManager,
    get_download_process_manager,
)
from app.services.job_manager import JobManager, get_job_manager

router = APIRouter(tags=["jobs"])
logger = logging.getLogger(__name__)


@router.get(
    "/jobs/{job_id}",
    response_model=APIResponse[DownloadJobStatusResponse],
    summary="Get job status",
    response_model_exclude_none=True,
    dependencies=[Depends(run_lazy_cleanup)],
)
def get_job(job_id: UUID, job_manager: JobManager = Depends(get_job_manager)) -> APIResponse[DownloadJobStatusResponse]:
    job = job_manager.get_job(job_id)
    if job is None:
        raise APIError(
            code="JOB_NOT_FOUND",
            message="Job not found",
            details=f"Job '{job_id}' does not exist",
            status_code=404,
        )

    return APIResponse.ok(data=DownloadJobStatusResponse.from_job(job))


@router.post(
    "/jobs/{job_id}/cancel",
    response_model=APIResponse[DownloadJobStatusResponse],
    summary="Cancel an active download job",
    description="Requests cancellation of an active yt-dlp or FFmpeg operation.",
    response_model_exclude_none=True,
    dependencies=[Depends(run_lazy_cleanup)],
    responses={
        404: {"description": "Job not found"},
        409: {"description": "Job is no longer cancellable"},
    },
)
def cancel_job(
    job_id: UUID,
    job_manager: JobManager = Depends(get_job_manager),
    process_manager: DownloadProcessManager = Depends(get_download_process_manager),
    cleanup_service: CleanupService = Depends(get_cleanup_service),
) -> APIResponse[DownloadJobStatusResponse]:
    job = job_manager.get_job(job_id)
    if job is None:
        logger.warning("Download cancellation rejected job_id=%s reason=job_not_found", job_id)
        raise APIError(
            code="JOB_NOT_FOUND",
            message="Job not found",
            details="The requested download job does not exist",
            status_code=404,
        )

    if job.status is JobStatus.completed:
        logger.info("Download cancellation ignored job_id=%s reason=already_completed", job_id)
        return APIResponse.ok(
            message="Job already completed; cancellation ignored",
            data=DownloadJobStatusResponse.from_job(job),
        )

    if job.status is JobStatus.cancelled:
        return APIResponse.ok(
            message="Job already cancelled",
            data=DownloadJobStatusResponse.from_job(job),
        )

    if job.status in {JobStatus.failed, JobStatus.expired}:
        logger.warning(
            "Download cancellation rejected job_id=%s reason=terminal_status status=%s",
            job_id,
            job.status,
        )
        raise APIError(
            code="JOB_NOT_CANCELLABLE",
            message="Job cannot be cancelled",
            details="Only active download jobs can be cancelled",
            status_code=409,
        )

    try:
        cancelling_job = job_manager.mark_cancelling(job_id)
    except KeyError:
        logger.warning("Download cancellation rejected job_id=%s reason=job_not_found", job_id)
        raise APIError(
            code="JOB_NOT_FOUND",
            message="Job not found",
            details="The requested download job does not exist",
            status_code=404,
        ) from None
    except ValueError:
        latest_job = job_manager.get_job(job_id)
        if latest_job is not None and latest_job.status is JobStatus.completed:
            logger.info("Download cancellation ignored job_id=%s reason=already_completed", job_id)
            return APIResponse.ok(
                message="Job already completed; cancellation ignored",
                data=DownloadJobStatusResponse.from_job(latest_job),
            )
        if latest_job is not None and latest_job.status is JobStatus.cancelled:
            return APIResponse.ok(
                message="Job already cancelled",
                data=DownloadJobStatusResponse.from_job(latest_job),
            )
        logger.warning(
            "Download cancellation rejected job_id=%s reason=terminal_status status=%s",
            job_id,
            latest_job.status if latest_job is not None else "missing",
        )
        raise APIError(
            code="JOB_NOT_CANCELLABLE",
            message="Job cannot be cancelled",
            details="Only active download jobs can be cancelled",
            status_code=409,
        ) from None

    if cancelling_job.status is JobStatus.completed:
        return APIResponse.ok(
            message="Job already completed; cancellation ignored",
            data=DownloadJobStatusResponse.from_job(cancelling_job),
        )

    if not process_manager.request_cancellation(job_id):
        cancelled_job = cleanup_service.cleanup_cancelled_download(
            job_id,
            job_manager=job_manager,
        )
        if cancelled_job is not None:
            cancelling_job = cancelled_job

    message = (
        "Download cancelled"
        if cancelling_job.status is JobStatus.cancelled
        else "Cancellation requested"
    )
    return APIResponse.ok(
        message=message,
        data=DownloadJobStatusResponse.from_job(cancelling_job),
    )


@router.delete(
    "/jobs/{job_id}",
    response_model=APIResponse[JobDeleteResponse],
    summary="Delete job",
    response_model_exclude_none=True,
)
def delete_job(job_id: UUID, job_manager: JobManager = Depends(get_job_manager)) -> APIResponse[JobDeleteResponse]:
    removed = job_manager.remove_job(job_id)
    if not removed:
        raise APIError(
            code="JOB_NOT_FOUND",
            message="Job not found",
            details=f"Job '{job_id}' does not exist",
            status_code=404,
        )

    return APIResponse.ok(message="Job removed", data=JobDeleteResponse(job_id=job_id, removed=True))
