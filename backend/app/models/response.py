from __future__ import annotations

from typing import Any, Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class APIErrorPayload(BaseModel):
    code: str = Field(..., min_length=1)
    details: str = Field(..., min_length=1)


class APIResponse(BaseModel, Generic[T]):
    success: bool
    message: str = Field(..., min_length=1)
    data: T | None = None
    error: APIErrorPayload | None = None

    @classmethod
    def ok(cls, *, message: str = "Request successful", data: T | None = None) -> "APIResponse[T]":
        return cls(success=True, message=message, data=data)

    @classmethod
    def fail(
        cls,
        *,
        message: str,
        code: str,
        details: str,
        data: T | None = None,
    ) -> "APIResponse[T]":
        return cls(
            success=False,
            message=message,
            data=data,
            error=APIErrorPayload(code=code, details=details),
        )