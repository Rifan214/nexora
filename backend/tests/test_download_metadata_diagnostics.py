from __future__ import annotations

from app.services.download_metadata_diagnostics import (
    build_download_metadata_diagnostic_report,
)


def test_diagnostic_report_redacts_sensitive_download_metadata() -> None:
    report = build_download_metadata_diagnostic_report(
        legacy_info={
            "format_id": "251",
            "protocol": "https",
            "extractor": "youtube",
            "http_headers": {
                "Authorization": "Bearer legacy-secret",
                "Cookie": "SID=legacy-secret",
                "User-Agent": "Nexora",
            },
            "formats": [
                {
                    "format_id": "251",
                    "url": "https://googlevideo.example/media?expire=1&sig=legacy-secret",
                }
            ],
            "requested_downloads": [{"format_id": "251"}],
        },
        snapshot_info={
            "format_id": "18",
            "protocol": "m3u8",
            "extractor": "youtube",
            "http_headers": {
                "Authorization": "Bearer snapshot-secret",
                "Cookie": "SID=snapshot-secret",
                "User-Agent": "Nexora",
            },
            "formats": [
                {
                    "format_id": "18",
                    "url": "https://googlevideo.example/media?expire=2&sig=snapshot-secret",
                }
            ],
            "requested_formats": [{"format_id": "18"}],
            "fragments": [{"url": "https://googlevideo.example/fragment?token=secret"}],
        },
    )

    payload = report.as_log_payload()
    serialized_report = str(payload)

    assert "legacy-secret" not in serialized_report
    assert "snapshot-secret" not in serialized_report
    assert "<redacted>" in report.legacy_json
    assert report.present_only_in_legacy == ["requested_downloads"]
    assert report.present_only_in_snapshot == ["fragments", "requested_formats"]
    assert report.focused_fields["format_id"]["different"] is True
    assert report.focused_fields["protocol"]["different"] is True
    assert report.focused_fields["formats"]["different"] is True
    assert report.focused_fields["requested_downloads"]["different"] is True
    assert report.focused_fields["requested_formats"]["different"] is True
    assert report.focused_fields["__postprocessors"]["different"] is False
    assert "format_id" in report.different_values
    assert "protocol" in report.different_values
