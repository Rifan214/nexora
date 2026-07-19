import logging
from functools import lru_cache

from fastapi import APIRouter, Depends

from app.models.job import JobCreateResponse
from app.models.media import MediaMetadata
from app.models.requests import MediaDownloadRequest, MediaInfoRequest
from app.models.response import APIResponse
from app.services.media_service import MediaService

router = APIRouter(prefix="/media", tags=["media"])
logger = logging.getLogger(__name__)


@lru_cache
def get_media_service() -> MediaService:
    return MediaService()


@router.post(
    "/info",
    response_model=APIResponse[MediaMetadata],
    summary="Prepare media metadata lookup",
    response_model_exclude_none=True,
)
def media_info(
    request: MediaInfoRequest,
    media_service: MediaService = Depends(get_media_service),
) -> APIResponse[MediaMetadata]:
    logger.info("Incoming media info request url=%s", request.url)
    metadata = media_service.get_metadata(request.url)
    return APIResponse.ok(data=metadata)


@router.post(
    "/download",
    response_model=APIResponse[JobCreateResponse],
    summary="Create download job",
    response_model_exclude_none=True,
)
def media_download(
    request: MediaDownloadRequest,
    media_service: MediaService = Depends(get_media_service),
) -> APIResponse[JobCreateResponse]:
    logger.info(
        "Incoming media download request url=%s format_id=%s type=%s",
        request.url,
        request.format_id,
        request.type,
    )
    job = media_service.create_download_job(request)
    return APIResponse.ok(data=JobCreateResponse(job_id=job.job_id))