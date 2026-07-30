from __future__ import annotations

import shutil
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app.models.resume_state import ResumeState
from app.services.resume_state_manager import ResumeStateManager
from app.utils.storage import get_temp_storage_dir


def _state(*, job_id=None) -> ResumeState:
    return ResumeState(
        job_id=job_id or uuid4(),
        source_url="https://www.youtube.com/watch?v=resume-state",
        output_path="storage/temp/download.%(ext)s",
        temporary_file_path="storage/temp/download.%(ext)s.part",
        media_format="bestaudio/best",
        extractor="Youtube",
    )


@pytest.fixture
def state_storage_dir() -> Path:
    storage_dir = get_temp_storage_dir() / f"resume-state-test-{uuid4()}"
    storage_dir.mkdir()
    try:
        yield storage_dir
    finally:
        shutil.rmtree(storage_dir, ignore_errors=True)


def test_resume_state_can_be_saved_and_loaded(state_storage_dir: Path) -> None:
    manager = ResumeStateManager(storage_dir=state_storage_dir)
    state = _state()

    manager.save(state)

    assert manager.load(state.job_id) == state
    assert manager.exists(state.job_id) is True


def test_resume_state_progress_updates_persist_across_manager_recreation(state_storage_dir: Path) -> None:
    state = _state()
    ResumeStateManager(storage_dir=state_storage_dir).save(state)

    updated_state = ResumeStateManager(storage_dir=state_storage_dir).update_progress(
        state.job_id,
        downloaded_bytes=512,
        total_bytes=1024,
    )
    reloaded_state = ResumeStateManager(storage_dir=state_storage_dir).load(state.job_id)

    assert updated_state is not None
    assert updated_state.downloaded_bytes == 512
    assert updated_state.total_bytes == 1024
    assert reloaded_state is not None
    assert reloaded_state.downloaded_bytes == 512
    assert reloaded_state.total_bytes == 1024
    assert reloaded_state.updated_at >= state.created_at


def test_resume_state_delete_removes_persisted_file(state_storage_dir: Path) -> None:
    manager = ResumeStateManager(storage_dir=state_storage_dir)
    state = _state()
    manager.save(state)

    assert manager.delete(state.job_id) is True
    assert manager.exists(state.job_id) is False
    assert manager.delete(state.job_id) is False


def test_concurrent_resume_state_progress_updates_leave_valid_state(state_storage_dir: Path) -> None:
    manager = ResumeStateManager(storage_dir=state_storage_dir)
    state = _state()
    manager.save(state)

    with ThreadPoolExecutor(max_workers=8) as executor:
        list(
            executor.map(
                lambda value: manager.update_progress(
                    state.job_id,
                    downloaded_bytes=value,
                    total_bytes=8192,
                ),
                range(0, 8193, 512),
            )
        )

    loaded_state = manager.load(state.job_id)

    assert loaded_state is not None
    assert loaded_state.total_bytes == 8192
    assert 0 <= loaded_state.downloaded_bytes <= 8192
    assert loaded_state.created_at.tzinfo is not None
    assert loaded_state.updated_at <= datetime.now(timezone.utc)
