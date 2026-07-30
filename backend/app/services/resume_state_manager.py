from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from threading import RLock
from uuid import UUID, uuid4

from app.models.resume_state import ResumeState
from app.utils.storage import get_resume_state_storage_dir

logger = logging.getLogger(__name__)

_STATE_LOCK = RLock()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ResumeStateManager:
    """Atomically persists resumable-download state in temporary storage."""

    def __init__(self, *, storage_dir: Path | None = None) -> None:
        self._storage_dir = storage_dir or get_resume_state_storage_dir()

    def save(self, state: ResumeState) -> ResumeState:
        """Persist a state snapshot without exposing it through the API."""
        with _STATE_LOCK:
            self._storage_dir.mkdir(parents=True, exist_ok=True)
            state_path = self._state_path(state.job_id)
            temporary_path = state_path.with_suffix(f".{uuid4().hex}.tmp")
            try:
                with temporary_path.open("w", encoding="utf-8", newline="\n") as state_file:
                    json.dump(state.model_dump(mode="json"), state_file, separators=(",", ":"))
                temporary_path.replace(state_path)
            finally:
                temporary_path.unlink(missing_ok=True)
            return state

    def load(self, job_id: UUID) -> ResumeState | None:
        with _STATE_LOCK:
            state_path = self._state_path(job_id)
            if not state_path.is_file():
                return None
            try:
                with state_path.open(encoding="utf-8") as state_file:
                    return ResumeState.model_validate(json.load(state_file))
            except (OSError, ValueError, json.JSONDecodeError):
                logger.warning("Resume state could not be loaded job_id=%s", job_id)
                return None

    def delete(self, job_id: UUID) -> bool:
        with _STATE_LOCK:
            state_path = self._state_path(job_id)
            if not state_path.is_file():
                return False
            state_path.unlink()
            return True

    def exists(self, job_id: UUID) -> bool:
        return self.load(job_id) is not None

    def update_progress(
        self,
        job_id: UUID,
        downloaded_bytes: int,
        total_bytes: int | None,
        *,
        output_path: str | None = None,
        temporary_file_path: str | None = None,
    ) -> ResumeState | None:
        """Persist bytes from yt-dlp's existing progress callback."""
        with _STATE_LOCK:
            state = self.load(job_id)
            if state is None:
                return None
            updated_state = state.model_copy(
                update={
                    "downloaded_bytes": max(0, downloaded_bytes),
                    "total_bytes": max(0, total_bytes) if total_bytes is not None else None,
                    "output_path": output_path or state.output_path,
                    "temporary_file_path": temporary_file_path or state.temporary_file_path,
                    "updated_at": _utcnow(),
                }
            )
            return self.save(updated_state)

    def _state_path(self, job_id: UUID) -> Path:
        return self._storage_dir / f"{job_id}.json"


@lru_cache
def get_resume_state_manager() -> ResumeStateManager:
    return ResumeStateManager()
