from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

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
    quality_height: int | None = Field(
        default=None,
        gt=0,
        description="Video height selected from the qualities returned by POST /media/info",
        examples=[1080],
    )
    format_id: str | None = Field(
        default=None,
        min_length=1,
        json_schema_extra={"deprecated": True},
        description="Deprecated raw yt-dlp format identifier for temporary legacy-client compatibility",
    )
    type: Literal["video", "audio"] = Field(
        default="video",
        json_schema_extra={"deprecated": True},
        description="Deprecated legacy output type; quality-based requests always create video downloads",
    )

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        return validate_http_url(value)

    @model_validator(mode="after")
    def validate_selection(self) -> "MediaDownloadRequest":
        has_quality = self.quality_height is not None
        has_legacy_format = self.format_id is not None
        if has_quality == has_legacy_format:
            raise ValueError("Provide exactly one of quality_height or format_id")
        if has_quality and self.type != "video":
            raise ValueError("quality_height is only supported for video downloads")
        return self
