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
        description="Video height selected from video_qualities returned by POST /media/info",
        examples=[1080],
    )
    media_type: Literal["video", "audio"] = Field(
        default="video",
        description="Requested media type. Video requires quality_height; audio is converted to MP3.",
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
        description="Deprecated compatibility alias for media_type",
    )

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        return validate_http_url(value)

    @model_validator(mode="after")
    def validate_selection(self) -> "MediaDownloadRequest":
        media_type = self.media_type
        legacy_type_was_supplied = "type" in self.model_fields_set
        media_type_was_supplied = "media_type" in self.model_fields_set
        if legacy_type_was_supplied and media_type_was_supplied and self.type != media_type:
            raise ValueError("media_type and type must match when both are provided")
        if legacy_type_was_supplied:
            media_type = self.type

        has_quality = self.quality_height is not None
        has_legacy_format = self.format_id is not None
        if media_type == "audio":
            if has_quality or has_legacy_format:
                raise ValueError("Audio downloads do not accept quality_height or format_id")
        elif has_quality == has_legacy_format:
            raise ValueError("Provide exactly one of quality_height or format_id for video downloads")

        self.media_type = media_type
        # Keep legacy internal callers that still read request.type working.
        self.type = media_type
        return self
