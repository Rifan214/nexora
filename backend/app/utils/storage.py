from __future__ import annotations

from pathlib import Path
from uuid import UUID


def get_storage_root() -> Path:
    return Path(__file__).resolve().parents[2] / "storage"


def get_temp_storage_dir() -> Path:
    temp_dir = get_storage_root() / "temp"
    temp_dir.mkdir(parents=True, exist_ok=True)
    return temp_dir


def build_download_outtmpl(job_id: UUID) -> str:
    return str(get_temp_storage_dir() / f"{job_id}.%(ext)s")
