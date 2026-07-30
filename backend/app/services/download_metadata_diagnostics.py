from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Mapping
from urllib.parse import parse_qsl, urlsplit, urlunsplit


_FOCUSED_FIELDS = (
    "requested_downloads",
    "requested_formats",
    "formats",
    "format_id",
    "protocol",
    "fragments",
    "extractor",
    "extractor_key",
    "http_headers",
    "__postprocessors",
    "__real_download",
    "__write_download_archive",
    "_filename",
    "filepath",
)
_SENSITIVE_KEY_PARTS = ("authorization", "cookie", "token", "signature", "password")
_SIGNED_URL_QUERY_KEYS = {"expire", "sig", "signature", "lsig", "n", "pot", "token"}


@dataclass(frozen=True)
class DownloadMetadataDiagnosticReport:
    """A redacted comparison of legacy and snapshot yt-dlp inputs."""

    legacy_json: str
    snapshot_json: str
    present_only_in_legacy: list[str]
    present_only_in_snapshot: list[str]
    different_values: dict[str, dict[str, Any]]
    focused_fields: dict[str, dict[str, Any]]

    def as_log_payload(self) -> dict[str, Any]:
        return {
            "legacy_json": self.legacy_json,
            "snapshot_json": self.snapshot_json,
            "present_only_in_legacy": self.present_only_in_legacy,
            "present_only_in_snapshot": self.present_only_in_snapshot,
            "different_values": self.different_values,
            "focused_fields": self.focused_fields,
        }


def build_download_metadata_diagnostic_report(
    *,
    legacy_info: Mapping[str, Any],
    snapshot_info: Mapping[str, Any],
) -> DownloadMetadataDiagnosticReport:
    """Serialize and compare yt-dlp inputs without exposing credentials or signed URLs."""
    legacy = _sanitize(legacy_info)
    snapshot = _sanitize(snapshot_info)
    legacy_keys = set(legacy)
    snapshot_keys = set(snapshot)
    differences: dict[str, dict[str, Any]] = {}
    _collect_differences(legacy, snapshot, path="", output=differences)

    focused_fields = {
        field: {
            "legacy": legacy.get(field, _MISSING),
            "snapshot": snapshot.get(field, _MISSING),
            "different": legacy.get(field, _MISSING) != snapshot.get(field, _MISSING),
        }
        for field in _FOCUSED_FIELDS
    }
    return DownloadMetadataDiagnosticReport(
        legacy_json=json.dumps(legacy, sort_keys=True, separators=(",", ":")),
        snapshot_json=json.dumps(snapshot, sort_keys=True, separators=(",", ":")),
        present_only_in_legacy=sorted(legacy_keys - snapshot_keys),
        present_only_in_snapshot=sorted(snapshot_keys - legacy_keys),
        different_values=differences,
        focused_fields=focused_fields,
    )


_MISSING = "<missing>"


def _collect_differences(
    legacy: Any,
    snapshot: Any,
    *,
    path: str,
    output: dict[str, dict[str, Any]],
) -> None:
    if isinstance(legacy, dict) and isinstance(snapshot, dict):
        for key in sorted(set(legacy) | set(snapshot)):
            child_path = f"{path}.{key}" if path else key
            if key not in legacy:
                output[child_path] = {"legacy": _MISSING, "snapshot": snapshot[key]}
            elif key not in snapshot:
                output[child_path] = {"legacy": legacy[key], "snapshot": _MISSING}
            else:
                _collect_differences(
                    legacy[key],
                    snapshot[key],
                    path=child_path,
                    output=output,
                )
        return

    if legacy != snapshot:
        output[path or "<root>"] = {"legacy": legacy, "snapshot": snapshot}


def _sanitize(value: Any, *, key: str | None = None) -> Any:
    normalized_key = (key or "").casefold()
    if any(part in normalized_key for part in _SENSITIVE_KEY_PARTS):
        return "<redacted>"
    if isinstance(value, Mapping):
        return {
            str(item_key): _sanitize(item_value, key=str(item_key))
            for item_key, item_value in value.items()
        }
    if isinstance(value, (list, tuple, set)):
        return [_sanitize(item, key=key) for item in value]
    if isinstance(value, str):
        return _redact_signed_url(value)
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return "<non-serializable>"


def _redact_signed_url(value: str) -> str:
    try:
        parsed = urlsplit(value)
    except ValueError:
        return value
    if not parsed.scheme or not parsed.netloc:
        return value

    query_keys = {key.casefold() for key, _ in parse_qsl(parsed.query, keep_blank_values=True)}
    if not query_keys.intersection(_SIGNED_URL_QUERY_KEYS):
        return value
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "<redacted>", ""))
