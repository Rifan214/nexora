from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.models.response import APIResponse
from app.models.system import AppInfo, HealthStatus, VersionInfo

router = APIRouter(tags=["health"])


@router.get("/", response_model=APIResponse[AppInfo], summary="API information", response_model_exclude_none=True)
def api_info(settings: Settings = Depends(get_settings)) -> APIResponse[AppInfo]:
    return APIResponse.ok(
        data=AppInfo(
            name=settings.app_name,
            version=settings.api_version,
            environment=settings.env,
        ),
    )


@router.get("/health", response_model=APIResponse[HealthStatus], summary="Health check", response_model_exclude_none=True)
def health_check(settings: Settings = Depends(get_settings)) -> APIResponse[HealthStatus]:
    return APIResponse.ok(
        data=HealthStatus(
            status="healthy",
            environment=settings.env,
        ),
    )


@router.get("/version", response_model=APIResponse[VersionInfo], summary="API version", response_model_exclude_none=True)
def api_version(settings: Settings = Depends(get_settings)) -> APIResponse[VersionInfo]:
    return APIResponse.ok(
        data=VersionInfo(version=settings.api_version),
    )