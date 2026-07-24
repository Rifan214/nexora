from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import configure_logging
from app.services.cleanup_service import CleanupWorker, get_cleanup_service
from app.services.download_process_manager import get_download_process_manager
from app.services.job_manager import get_job_manager


@asynccontextmanager
async def _lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    cleanup_worker = CleanupWorker(
        cleanup_service=get_cleanup_service(),
        job_manager=get_job_manager(),
        process_manager=get_download_process_manager(),
    )
    await cleanup_worker.start()
    try:
        yield
    finally:
        await cleanup_worker.stop()


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(debug=settings.debug)

    app = FastAPI(
        title=settings.app_name,
        version=settings.api_version,
        debug=settings.debug,
        lifespan=_lifespan,
    )

    if settings.cors_origin_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origin_list,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    register_exception_handlers(app)
    app.include_router(api_router)
    return app


app = create_app()
