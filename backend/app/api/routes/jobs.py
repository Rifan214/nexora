from __future__ import annotations

import logging
from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.exceptions import APIError
from app.models.job import DownloadJob, JobDeleteResponse
from app.models.response import APIResponse
from app.services.job_manager import JobManager, get_job_manager

router = APIRouter(tags=["jobs"])
logger = logging.getLogger(__name__)


@router.get(
    "/jobs/{job_id}",
    response_model=APIResponse[DownloadJob],
    summary="Get job status",
    response_model_exclude_none=True,
)
def get_job(job_id: UUID, job_manager: JobManager = Depends(get_job_manager)) -> APIResponse[DownloadJob]:
    job = job_manager.get_job(job_id)
    if job is None:
        raise APIError(
            code="JOB_NOT_FOUND",
            message="Job not found",
            details=f"Job '{job_id}' does not exist",
            status_code=404,
        )

    return APIResponse.ok(data=job)


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