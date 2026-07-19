from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.utils.validators import validate_http_url


class MediaInfoRequest(BaseModel):
    url: str = Field(
        ...,
        min_length=1,
        description="HTTP or HTTPS media URL",
        examples=["https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
    )

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        return validate_http_url(value)


class MediaDownloadRequest(BaseModel):
    url: str = Field(
        ...,
        min_length=1,
        description="HTTP or HTTPS media URL",
        examples=["https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
    )
    format_id: str = Field(..., min_length=1, description="yt-dlp format identifier")
    type: Literal["video", "audio"] = Field(..., description="Requested output type")

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        return validate_http_url(value)