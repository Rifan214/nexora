from __future__ import annotations

from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class JobStatus(str, Enum):
    pending = "pending"
    processing = "processing"
    cancelling = "cancelling"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"
    expired = "expired"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class DownloadJob(BaseModel):
    job_id: UUID = Field(default_factory=uuid4, description="Unique job identifier")
    status: JobStatus = Field(default=JobStatus.pending, description="Current job status")
    progress: int = Field(default=0, ge=0, le=100, description="Completion progress percentage")
    created_at: datetime = Field(default_factory=_utcnow, description="Job creation timestamp")
    updated_at: datetime = Field(default_factory=_utcnow, description="Last update timestamp")
    media_url: str = Field(..., min_length=1, description="Source media URL")
    platform: str = Field(..., min_length=1, description="Detected media platform")
    title: str | None = Field(default=None, description="Media title if known")
    format_id: str | None = Field(default=None, description="Requested yt-dlp format identifier")
    output_type: str | None = Field(default=None, description="Requested output type")
    error_message: str | None = Field(default=None, description="Failure reason if any")
    download_url: str | None = Field(default=None, description="Completed file URL if available")
    expires_at: datetime | None = Field(default=None, description="Expiration timestamp if any")


class DownloadJobStatusResponse(BaseModel):
    """Public job state that intentionally excludes the internal yt-dlp selector."""

    job_id: UUID = Field(..., description="Unique job identifier")
    status: JobStatus = Field(..., description="Current job status")
    progress: int = Field(..., ge=0, le=100, description="Completion progress percentage")
    created_at: datetime = Field(..., description="Job creation timestamp")
    updated_at: datetime = Field(..., description="Last update timestamp")
    media_url: str = Field(..., min_length=1, description="Source media URL")
    platform: str = Field(..., min_length=1, description="Detected media platform")
    title: str | None = Field(default=None, description="Media title if known")
    output_type: str | None = Field(default=None, description="Requested output type")
    error_message: str | None = Field(default=None, description="Failure reason if any")
    download_url: str | None = Field(default=None, description="Completed file URL if available")
    expires_at: datetime | None = Field(default=None, description="Expiration timestamp if any")

    @classmethod
    def from_job(cls, job: DownloadJob) -> "DownloadJobStatusResponse":
        return cls(**job.model_dump(exclude={"format_id"}))


class JobUpdateResponse(BaseModel):
    job_id: UUID = Field(..., description="Updated job identifier")


class JobCreateResponse(BaseModel):
    job_id: UUID = Field(..., description="Created job identifier")


class JobDeleteResponse(BaseModel):
    job_id: UUID = Field(..., description="Removed job identifier")
    removed: bool = Field(default=True, description="Whether the job was removed")
