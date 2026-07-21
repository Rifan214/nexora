from pydantic import BaseModel, Field


class AvailableQuality(BaseModel):
    """A playable quality option intended for display in the client UI."""

    label: str = Field(..., min_length=1, description="User-friendly quality label")
    height: int = Field(..., gt=0, description="Video height in pixels")
    extension: str = Field(..., min_length=1, description="Selected video container or extension")
    estimated_filesize: int | None = Field(
        default=None,
        ge=0,
        description="Estimated completed file size in bytes when yt-dlp provides enough data",
    )


class AudioOption(BaseModel):
    """A client-safe audio download option."""

    label: str = Field(..., min_length=1, description="User-friendly audio format label")
    extension: str = Field(..., min_length=1, description="Downloaded audio file extension")


class MediaMetadata(BaseModel):
    platform: str = Field(..., min_length=1, description="Detected platform from yt-dlp")
    title: str = Field(..., min_length=1, description="Media title")
    uploader: str | None = Field(default=None, description="Uploader or channel name")
    uploader_url: str | None = Field(default=None, description="Uploader URL if available")
    thumbnail_url: str | None = Field(default=None, description="Thumbnail URL if available")
    duration_seconds: int | None = Field(default=None, ge=0, description="Duration in seconds")
    webpage_url: str = Field(..., min_length=1, description="Canonical webpage URL")
    extractor: str = Field(..., min_length=1, description="yt-dlp extractor name")
    extractor_key: str = Field(..., min_length=1, description="yt-dlp extractor key")
    upload_date: str | None = Field(default=None, description="Upload date in YYYYMMDD format if available")
    view_count: int | None = Field(default=None, ge=0, description="View count if available")
    like_count: int | None = Field(default=None, ge=0, description="Like count if available")
    description: str | None = Field(default=None, description="Media description if available")
    video_qualities: list[AvailableQuality] = Field(
        default_factory=list,
        description="Playable video quality options selected by the backend",
    )
    audio_options: list[AudioOption] = Field(
        default_factory=list,
        description="Client-safe audio download options available for this media",
    )
