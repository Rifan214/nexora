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
