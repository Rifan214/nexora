from fastapi import APIRouter

from app.api.routes.files import router as files_router
from app.api.routes.jobs import router as jobs_router
from app.api.routes.health import router as health_router
from app.api.routes.media import router as media_router
from app.api.routes.websockets import router as websockets_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(media_router)
api_router.include_router(jobs_router)
api_router.include_router(files_router)
api_router.include_router(websockets_router)
