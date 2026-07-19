from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.models.response import APIResponse

logger = logging.getLogger(__name__)


class APIError(Exception):
    def __init__(self, *, code: str, message: str, details: str, status_code: int = 400) -> None:
        self.code = code
        self.message = message
        self.details = details
        self.status_code = status_code
        super().__init__(details)


def _error_response(*, message: str, code: str, details: str, status_code: int) -> JSONResponse:
    payload = APIResponse[Any].fail(message=message, code=code, details=details)
    return JSONResponse(status_code=status_code, content=payload.model_dump(exclude_none=True))


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def api_error_handler(_: Request, exc: APIError) -> JSONResponse:
        logger.warning("API error %s: %s", exc.code, exc.details)
        return _error_response(
            message=exc.message,
            code=exc.code,
            details=exc.details,
            status_code=exc.status_code,
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
        detail = exc.detail if isinstance(exc.detail, str) else "Request could not be completed"
        logger.warning("HTTP error %s: %s", exc.status_code, detail)
        return _error_response(
            message=detail,
            code="HTTP_ERROR",
            details=detail,
            status_code=exc.status_code,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        logger.warning("Validation error: %s", exc.errors())
        payload = APIResponse[Any].fail(
            message="Validation failed",
            code="VALIDATION_ERROR",
            details="One or more request fields are invalid",
        )
        return JSONResponse(status_code=422, content=payload.model_dump(exclude_none=True))

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
        settings = get_settings()
        if settings.debug:
            logger.exception("Unhandled server error")
        else:
            logger.error("Unhandled server error: %s", exc)
        return _error_response(
            message="Something went wrong",
            code="INTERNAL_SERVER_ERROR",
            details="An unexpected error occurred",
            status_code=500,
        )