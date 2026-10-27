from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

AUDIO_ONLY_SUFFIXES = frozenset({".m4a", ".mp3", ".aac", ".flac", ".wav", ".ogg", ".opus", ".wma"})
VIDEO_ONLY_SUFFIXES = frozenset({".mp4", ".mkv", ".webm", ".avi", ".mov", ".flv", ".wmv", ".m4v"})
IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff"})


def _probe_mp4_fallback(file_path: Path) -> list[dict[str, Any]] | None:
    """Fallback parser for ISO-BMFF containers (.mp4, .m4a, .mov) when ffprobe is unavailable.

    Inspects moov -> trak -> mdia -> hdlr and stsd boxes to identify video and audio tracks.
    """
    import struct

    tracks: list[dict[str, Any]] = []
    try:
        with open(file_path, "rb") as f:
            file_size = f.seek(0, 2)
            f.seek(0)

            def read_boxes(start: int, end: int):
                pos = start
                while pos < end - 8:
                    f.seek(pos)
                    header = f.read(8)
                    if len(header) < 8:
                        break
                    size, box_type = struct.unpack(">I4s", header)
                    if size == 1:
                        size_bytes = f.read(8)
                        if len(size_bytes) < 8:
                            break
                        size = struct.unpack(">Q", size_bytes)[0]
                        box_data_start = pos + 16
                    elif size == 0:
                        size = end - pos
                        box_data_start = pos + 8
                    else:
                        box_data_start = pos + 8

                    box_data_end = pos + size
                    if box_type in (b"moov", b"mdia", b"minf", b"stbl"):
                        yield from read_boxes(box_data_start, box_data_end)
                    elif box_type == b"trak":
                        track_info: dict[str, Any] = {}
                        for sub_type, sub_start, _ in read_boxes(box_data_start, box_data_end):
                            if sub_type == b"hdlr":
                                f.seek(sub_start + 8)
                                handler_type = f.read(4)
                                if handler_type == b"vide":
                                    track_info["codec_type"] = "video"
                                elif handler_type == b"soun":
                                    track_info["codec_type"] = "audio"
                            elif sub_type == b"stsd":
                                f.seek(sub_start + 8)
                                entry_hdr = f.read(8)
                                if len(entry_hdr) == 8:
                                    _, fourcc = struct.unpack(">I4s", entry_hdr)
                                    track_info["codec_name"] = fourcc.decode("latin1", errors="replace")
                        if track_info.get("codec_type"):
                            tracks.append(track_info)
                    else:
                        yield box_type, box_data_start, box_data_end

                    if size <= 0:
                        break
                    pos += size

            list(read_boxes(0, min(file_size, 32 * 1024 * 1024)))
        return tracks if tracks else None
    except Exception as exc:
        logger.debug("ISO-BMFF fallback probe failed for %s: %s", file_path, exc)
        return None


def probe_media_streams(file_path: Path) -> list[dict[str, Any]] | None:
    """Probe media streams using ffprobe if available, falling back to container parsing.

    Returns a list of stream dicts with keys such as 'codec_type', 'codec_name',
    'width', 'height', or None if stream information cannot be determined.
    """
    try:
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=index,codec_type,codec_name,width,height",
            "-of",
            "json",
            str(file_path),
        ]
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
        if result.returncode == 0 and result.stdout:
            data = json.loads(result.stdout)
            streams = data.get("streams")
            if isinstance(streams, list):
                return streams
    except (FileNotFoundError, subprocess.SubprocessError, json.JSONDecodeError, OSError) as exc:
        logger.debug("ffprobe stream inspection unavailable for %s: %s", file_path, exc)

    # Fallback for ISO-BMFF / MP4 containers
    suffix = file_path.suffix.casefold()
    if suffix in {".mp4", ".m4a", ".mov", ".m4v"}:
        return _probe_mp4_fallback(file_path)

    return None


def validate_download_artifact(file_path: Path, *, output_type: str) -> None:
    """Validate that the downloaded artifact exists, is non-empty, and matches the requested media type.

    Raises:
        FileNotFoundError: If the file does not exist or is not a file.
        ValueError: If the file is 0 bytes, has an incompatible extension, or lacks required streams.
    """
    if not file_path.is_file():
        raise FileNotFoundError(f"Downloaded artifact {file_path} is missing or not a file")

    if file_path.stat().st_size == 0:
        raise ValueError(f"Downloaded artifact {file_path.name} is empty (0 bytes)")

    suffix = file_path.suffix.casefold()

    if output_type == "video":
        if suffix in AUDIO_ONLY_SUFFIXES:
            raise ValueError(
                f"Artifact {file_path.name} is an audio-only file ({suffix}), but video was requested"
            )
        if suffix in IMAGE_SUFFIXES:
            raise ValueError(
                f"Artifact {file_path.name} is an image file ({suffix}), but video was requested"
            )

        streams = probe_media_streams(file_path)
        if streams is not None:
            has_video_stream = any(s.get("codec_type") == "video" for s in streams)
            if not has_video_stream:
                raise ValueError(
                    f"Artifact {file_path.name} does not contain any video streams"
                )
    elif output_type == "audio":
        if suffix in VIDEO_ONLY_SUFFIXES:
            raise ValueError(
                f"Artifact {file_path.name} is a video container ({suffix}), but audio was requested"
            )
        if suffix in IMAGE_SUFFIXES:
            raise ValueError(
                f"Artifact {file_path.name} is an image file ({suffix}), but audio was requested"
            )

        streams = probe_media_streams(file_path)
        if streams is not None:
            has_audio_stream = any(s.get("codec_type") == "audio" for s in streams)
            if not has_audio_stream:
                raise ValueError(
                    f"Artifact {file_path.name} does not contain any audio streams"
                )
