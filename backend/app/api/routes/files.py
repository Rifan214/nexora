from __future__ import annotations

from functools import lru_cache
from uuid import UUID

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse

from app.api.dependencies import run_lazy_cleanup
from app.services.download_file_service import DownloadFileService
from app.services.job_manager import JobManager, get_job_manager

router = APIRouter(tags=["files"])


@lru_cache
def get_download_file_service() -> DownloadFileService:
    return DownloadFileService()


@router.get(
    "/files/{job_id}",
    response_class=FileResponse,
    summary="Download a completed media file",
    description="Returns the completed media file as a binary attachment when the download job is complete.",
    dependencies=[Depends(run_lazy_cleanup)],
    responses={
        200: {
            "description": "Binary media file attachment",
            "content": {
                "application/octet-stream": {
                    "schema": {"type": "string", "format": "binary"},
                },
            },
        },
        404: {"description": "Job or downloaded file was not found"},
        409: {"description": "The job has not completed"},
        410: {"description": "The job has expired"},
    },
)
def serve_download_file(
    job_id: UUID,
    job_manager: JobManager = Depends(get_job_manager),
    download_file_service: DownloadFileService = Depends(get_download_file_service),
) -> FileResponse:
    return download_file_service.create_file_response(job_id, job_manager=job_manager)
