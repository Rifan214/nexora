from __future__ import annotations

import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

from app.models.instagram_auth import (
    InstagramAuthSource,
    InstagramAuthStatus,
)
from app.services.instagram_user_session_store import (
    EphemeralInstagramUserSessionStore,
    SecurityError,
    _format_netscape_cookie_content,
    _is_safe_session_id,
)

_SYNTHETIC_SESSIONID = "synthetic_instagram_session_12345%3AABC"
_SYNTHETIC_DS_USER_ID = "61234567890"
_SYNTHETIC_CSRFTOKEN = "csrf_token_test_abc"


@pytest.fixture
def store(tmp_path: Path) -> EphemeralInstagramUserSessionStore:
    return EphemeralInstagramUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)


def test_safe_session_id_validation() -> None:
    assert _is_safe_session_id("0123456789abcdef0123456789abcdef") is True
    assert _is_safe_session_id("abcdef1234567890") is True
    assert _is_safe_session_id("") is False
    assert _is_safe_session_id(None) is False
    assert _is_safe_session_id("../traversal") is False
    assert _is_safe_session_id("123;rm -rf /") is False
    assert _is_safe_session_id("short") is False  # Min 16 chars


def test_format_netscape_cookie_content() -> None:
    content = _format_netscape_cookie_content(
        sessionid=_SYNTHETIC_SESSIONID,
        ds_user_id=_SYNTHETIC_DS_USER_ID,
        csrftoken=_SYNTHETIC_CSRFTOKEN,
    )
    assert content.startswith("# Netscape HTTP Cookie File\n")
    assert f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\t{_SYNTHETIC_SESSIONID}\n" in content
    assert f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tds_user_id\t{_SYNTHETIC_DS_USER_ID}\n" in content
    assert f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tcsrftoken\t{_SYNTHETIC_CSRFTOKEN}\n" in content


def test_create_and_get_session(store: EphemeralInstagramUserSessionStore) -> None:
    session = store.create_session(
        sessionid=_SYNTHETIC_SESSIONID,
        ds_user_id=_SYNTHETIC_DS_USER_ID,
        csrftoken=_SYNTHETIC_CSRFTOKEN,
    )
    assert session.session_id is not None
    assert len(session.session_id) == 32
    assert session.source == InstagramAuthSource.USER_SESSION
    assert session.status == InstagramAuthStatus.AVAILABLE
    assert session.authenticated is True
    assert session.expires_at is not None

    retrieved = store.get_session(session.session_id)
    assert retrieved.session_id == session.session_id
    assert retrieved.status == InstagramAuthStatus.AVAILABLE
    assert retrieved.authenticated is True
    assert store.has_session(session.session_id) is True


def test_session_expiry(tmp_path: Path) -> None:
    current_time = datetime(2026, 10, 9, 12, 0, 0, tzinfo=UTC)

    store = EphemeralInstagramUserSessionStore(
        storage_dir=tmp_path,
        now=lambda: current_time,
        cleanup_on_startup=False,
    )

    session = store.create_session(
        sessionid=_SYNTHETIC_SESSIONID,
        ttl_seconds=300,
    )
    assert store.has_session(session.session_id) is True

    # Fast forward beyond TTL (301 seconds later)
    current_time = current_time + timedelta(seconds=301)

    assert store.has_session(session.session_id) is False
    expired_session = store.get_session(session.session_id)
    assert expired_session.status == InstagramAuthStatus.EXPIRED
    assert expired_session.authenticated is False


def test_invalidate_session_zeroes_credentials_and_deletes_file(store: EphemeralInstagramUserSessionStore) -> None:
    session = store.create_session(sessionid=_SYNTHETIC_SESSIONID)
    cookie_file = store.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    store.invalidate(session.session_id)

    # Session is marked INVALID
    revoked = store.get_session(session.session_id)
    assert revoked.status == InstagramAuthStatus.INVALID
    assert revoked.authenticated is False

    # Cookie file is unlinked immediately when no active leases
    assert not cookie_file.is_file()


def test_lease_tracking_protects_cookie_file_mid_flight(store: EphemeralInstagramUserSessionStore) -> None:
    session = store.create_session(sessionid=_SYNTHETIC_SESSIONID)
    cookie_file = store.acquire_session_lease(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    # User revokes session while download worker is using it
    store.invalidate(session.session_id)

    # File must NOT be deleted yet because lease is active
    assert cookie_file.is_file()

    # Release lease -> now file should be cleaned up
    store.release_session_lease(session.session_id)
    assert not cookie_file.is_file()


def test_cookie_file_permissions(store: EphemeralInstagramUserSessionStore) -> None:
    session = store.create_session(sessionid=_SYNTHETIC_SESSIONID)
    cookie_file = store.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    if os.name != "nt":
        file_stat = os.stat(cookie_file)
        # 0600 = owner read/write only
        assert (file_stat.st_mode & 0o777) == 0o600


def test_orphaned_cookie_file_cleanup(tmp_path: Path) -> None:
    ig_dir = tmp_path / "sessions" / "instagram"
    ig_dir.mkdir(parents=True, exist_ok=True)
    orphan = ig_dir / "ig_cookie_old_dead_session.txt"
    orphan.write_text("abandoned cookie data")

    store = EphemeralInstagramUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)
    assert not orphan.exists()
