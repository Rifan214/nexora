from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ResumeState(BaseModel):
    """Persistent download details reserved for future HTTP range support."""

    model_config = ConfigDict(extra="allow")

    schema_version: int = Field(default=1, ge=1)
    job_id: UUID
    source_url: str
    output_path: str
    temporary_file_path: str
    downloaded_bytes: int = Field(default=0, ge=0)
    total_bytes: int | None = Field(default=None, ge=0)
    media_format: str
    extractor: str
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)
