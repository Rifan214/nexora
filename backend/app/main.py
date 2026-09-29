from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import configure_logging
from app.platforms.hanime import get_hanime_signature_provider
from app.services.cleanup_service import CleanupWorker, get_cleanup_service
from app.services.download_process_manager import get_download_process_manager
from app.services.job_manager import get_job_manager


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    cleanup_worker = CleanupWorker(
        cleanup_service=get_cleanup_service(),
        job_manager=get_job_manager(),
        process_manager=get_download_process_manager(),
    )
    await cleanup_worker.start()

    hanime_provider = getattr(app.state, "hanime_signature_provider", None)
    if hanime_provider is None:
        hanime_provider = get_hanime_signature_provider()
        app.state.hanime_signature_provider = hanime_provider

    if hanime_provider.enabled:
        await hanime_provider.start()

    try:
        yield
    finally:
        try:
            if hanime_provider.enabled:
                await hanime_provider.close()
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
