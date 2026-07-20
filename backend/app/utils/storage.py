from __future__ import annotations

import logging
import mimetypes
import re
from pathlib import Path
from urllib.parse import quote
from uuid import UUID

logger = logging.getLogger(__name__)

_INCOMPLETE_DOWNLOAD_SUFFIXES = {".part", ".ytdl"}
_INVALID_FILENAME_CHARACTERS = re.compile(r'[\x00-\x1f<>:"/\\|?*]+')


def get_storage_root() -> Path:
    return Path(__file__).resolve().parents[2] / "storage"


def get_temp_storage_dir() -> Path:
    temp_dir = get_storage_root() / "temp"
    temp_dir.mkdir(parents=True, exist_ok=True)
    return temp_dir


def build_download_outtmpl(job_id: UUID, *, temp_dir: Path | None = None) -> str:
    destination_dir = temp_dir or get_temp_storage_dir()
    return str(destination_dir / f"{job_id}.%(ext)s")


def find_downloaded_file(job_id: UUID, *, temp_dir: Path | None = None) -> Path | None:
    destination_dir = (temp_dir or get_temp_storage_dir()).resolve()
    candidates: list[Path] = []

    for candidate in destination_dir.glob(f"{job_id}.*"):
        resolved_candidate = candidate.resolve()
        if not resolved_candidate.is_relative_to(destination_dir):
            logger.warning("Unauthorized file access attempt job_id=%s reason=unsafe_storage_candidate", job_id)
            logger.debug("Unsafe file candidate path=%s", resolved_candidate)
            continue

        if (
            not resolved_candidate.is_file()
            or candidate.suffix.casefold() in _INCOMPLETE_DOWNLOAD_SUFFIXES
            or candidate.name.casefold().endswith(".info.json")
        ):
            continue

        candidates.append(resolved_candidate)

    if not candidates:
        return None

    return max(candidates, key=lambda path: path.stat().st_mtime)


def build_download_filename(*, title: str | None, file_path: Path) -> str:
    sanitized_title = _sanitize_filename(title or "")
    extension = file_path.suffix

    if not sanitized_title:
        sanitized_title = "download"

    if extension and not sanitized_title.casefold().endswith(extension.casefold()):
        return f"{sanitized_title}{extension}"
    return sanitized_title


def build_attachment_content_disposition(filename: str) -> str:
    safe_filename = _sanitize_filename(filename) or "download"
    quoted_filename = _quote_header_filename(safe_filename)
    if _is_ascii(safe_filename):
        return f'attachment; filename="{quoted_filename}"'

    fallback_filename = _ascii_filename_fallback(safe_filename)
    quoted_fallback = _quote_header_filename(fallback_filename)
    encoded_filename = quote(safe_filename, safe="")
    return f'attachment; filename="{quoted_fallback}"; filename*=UTF-8\'\'{encoded_filename}'


def guess_media_type(file_path: Path) -> str:
    media_type, _ = mimetypes.guess_type(file_path.name)
    return media_type or "application/octet-stream"


def _sanitize_filename(value: str) -> str:
    sanitized = _INVALID_FILENAME_CHARACTERS.sub(" ", value)
    sanitized = " ".join(sanitized.split())
    return sanitized.strip(". ")


def _quote_header_filename(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _is_ascii(value: str) -> bool:
    try:
        value.encode("ascii")
    except UnicodeEncodeError:
        return False
    return True


def _ascii_filename_fallback(filename: str) -> str:
    original_path = Path(filename)
    suffix = original_path.suffix.encode("ascii", errors="ignore").decode("ascii")
    if suffix == ".":
        suffix = ""
    fallback_stem = original_path.stem.encode("ascii", errors="ignore").decode("ascii")
    fallback_stem = _sanitize_filename(fallback_stem)
    if fallback_stem:
        return f"{fallback_stem}{suffix}"

    if suffix:
        return f"download{suffix}"
    return "download"
