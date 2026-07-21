import logging
from functools import lru_cache

from fastapi import APIRouter, Depends

from app.api.dependencies import run_lazy_cleanup
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
    summary="Get media metadata and playable quality options",
    description="Returns UI-friendly quality options. Raw yt-dlp stream identifiers are never included in the response.",
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
    summary="Create a quality-based download job",
    description=(
        "Send a quality_height returned by POST /media/info. The backend resolves it to a playable "
        "yt-dlp selector and pairs adaptive video with audio when needed. The deprecated format_id "
        "field is accepted only for temporary legacy-client compatibility."
    ),
    response_model_exclude_none=True,
    dependencies=[Depends(run_lazy_cleanup)],
)
def media_download(
    request: MediaDownloadRequest,
    media_service: MediaService = Depends(get_media_service),
) -> APIResponse[JobCreateResponse]:
    logger.info(
        "Incoming media download request url=%s quality_height=%s legacy_format_request=%s type=%s",
        request.url,
        request.quality_height,
        request.format_id is not None,
        request.type,
    )
    job = media_service.create_download_job(request)
    return APIResponse.ok(data=JobCreateResponse(job_id=job.job_id))
