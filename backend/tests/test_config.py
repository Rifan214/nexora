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


def test_download_metadata_diagnostics_is_read_from_environment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NEXORA_DOWNLOAD_METADATA_DIAGNOSTICS", "true")

    assert get_settings().download_metadata_diagnostics is True


def test_x_auth_cookie_file_is_disabled_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_X_AUTH_COOKIE_FILE", raising=False)

    assert get_settings().x_auth_cookie_file == ""


def test_x_auth_cookie_file_accepts_an_empty_value(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEXORA_X_AUTH_COOKIE_FILE", "")

    assert get_settings().x_auth_cookie_file == ""


def test_x_auth_cookie_file_is_read_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEXORA_X_AUTH_COOKIE_FILE", "C:/run/secrets/x.cookies.txt")

    assert get_settings().x_auth_cookie_file == "C:/run/secrets/x.cookies.txt"
