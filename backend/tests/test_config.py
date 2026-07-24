from __future__ import annotations

import pytest

from app.core.config import get_settings


@pytest.fixture(autouse=True)
def clear_settings_cache() -> None:
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_download_expiration_minutes_is_read_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DOWNLOAD_EXPIRATION_MINUTES", "7")

    assert get_settings().download_expiration_minutes == 7


def test_file_cleanup_retention_is_read_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TEMP_FILE_RETENTION_MINUTES", "12")
    monkeypatch.setenv("FAILED_DOWNLOAD_RETENTION_MINUTES", "3")

    settings = get_settings()

    assert settings.temp_file_retention_minutes == 12
    assert settings.failed_download_retention_minutes == 3


def test_cleanup_interval_is_read_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CLEANUP_INTERVAL_MINUTES", "9")

    assert get_settings().cleanup_interval_minutes == 9
