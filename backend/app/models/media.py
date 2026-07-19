from pydantic import BaseModel, Field


class MediaFormat(BaseModel):
    format_id: str = Field(..., min_length=1, description="yt-dlp format identifier")
    extension: str = Field(..., min_length=1, description="Container or file extension")
    resolution: str | None = Field(default=None, description="Video resolution or quality label")
    fps: int | None = Field(default=None, ge=0, description="Frame rate if available")
    filesize: int | None = Field(default=None, ge=0, description="File size in bytes if available")
    video_codec: str | None = Field(default=None, description="Video codec if available")
    audio_codec: str | None = Field(default=None, description="Audio codec if available")


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
    formats: list[MediaFormat] = Field(default_factory=list, description="Available downloadable formats")


class DownloadJobSummary(BaseModel):
    job_id: str = Field(..., min_length=1, description="Download job identifier")
    media_url: str = Field(..., min_length=1, description="Source media URL")
    format_id: str = Field(..., min_length=1, description="yt-dlp format identifier")
    type: str = Field(..., min_length=1, description="Requested output type")
    status: str = Field(..., min_length=1, description="Current job status")