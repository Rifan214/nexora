from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.core.config import get_settings
from app.core.exceptions import APIError
from app.models.job import JobStatus
from app.models.tiktok_auth import (
    TikTokAuthContext,
    TikTokAuthSession,
    TikTokAuthSource,
    TikTokAuthStatus,
)
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.media_snapshot_cache import MediaSnapshotCache
from app.services.resume_state_manager import ResumeStateManager
from app.services.tiktok_auth_manager import TikTokAuthManager
from app.services.tiktok_auth_providers import UserSessionTikTokAuthProvider
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore
from app.utils.storage import get_temp_storage_dir

_TIKTOK_URL = "https://www.tiktok.com/@user/video/7123456789012345678"
_SESSIONID_A = "sessionid-user-A-value123"
_SID_TT_A = "sid-tt-user-A-value456"
_SESSIONID_B = "sessionid-user-B-value789"
_SID_TT_B = "sid-tt-user-B-value012"


@pytest.fixture(autouse=True)
def reset_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_TIKTOK_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _fake_tiktok_info() -> dict:
    return {
        "id": "7123456789012345678",
        "title": "TikTok User Protected Video",
        "uploader": "tiktok_user",
        "extractor": "TikTok",
        "extractor_key": "TikTok",
        "formats": [
            {
                "format_id": "download_addr-0",
                "width": 1080,
                "height": 1920,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
                "url": "https://example.test/tiktok/video.mp4",
            },
        ],
    }


# ==============================================================================
# A. UserSessionTikTokAuthProvider Tests
# ==============================================================================

def test_user_session_provider_unavailable_without_session() -> None:
    store = EphemeralTikTokUserSessionStore()
    provider = UserSessionTikTokAuthProvider(session_store=store)

    assert provider.source == TikTokAuthSource.USER_SESSION
    assert provider.is_available() is False
    assert provider.is_available("nonexistent") is False
    assert provider.get_cookie_file() is None
    assert provider.get_cookie_file("nonexistent") is None

    session = provider.get_session()
    assert session.authenticated is False
    assert session.status == TikTokAuthStatus.UNAVAILABLE


def test_user_session_provider_available_with_valid_session() -> None:
    store = EphemeralTikTokUserSessionStore()
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)
    provider = UserSessionTikTokAuthProvider(session_store=store)

    assert provider.is_available(session.session_id) is True
    retrieved = provider.get_session(session.session_id)
    assert retrieved.authenticated is True
    assert retrieved.status == TikTokAuthStatus.AVAILABLE
    assert retrieved.source == TikTokAuthSource.USER_SESSION
    assert retrieved.session_id == session.session_id


def test_user_session_provider_cookie_file_generated() -> None:
    store = EphemeralTikTokUserSessionStore()
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)
    provider = UserSessionTikTokAuthProvider(session_store=store)

    cookie_file = provider.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()
    content = cookie_file.read_text(encoding="utf-8")
    assert _SESSIONID_A in content
    assert _SID_TT_A in content
    assert ".tiktok.com" in content


# ==============================================================================
# B. EphemeralTikTokUserSessionStore Lifecycle & Security Tests
# ==============================================================================

def test_store_session_expiration(tmp_path: Path) -> None:
    clock = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path, now=lambda: clock)

    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)
    assert store.is_valid(session.session_id) is True
    cookie_path = store.get_cookie_file(session.session_id)
    assert cookie_path is not None and cookie_path.is_file()

    # Advance clock past TTL
    clock += timedelta(hours=2)
    assert store.is_valid(session.session_id) is False
    assert store.get_cookie_file(session.session_id) is None
    # Expired file removed from disk
    assert not cookie_path.exists()


def test_store_invalidate_removes_file_and_wipes_memory(tmp_path: Path) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)
    cookie_path = store.get_cookie_file(session.session_id)
    assert cookie_path is not None and cookie_path.is_file()

    record = store._sessions[session.session_id]
    assert record.sessionid == _SESSIONID_A

    store.invalidate(session.session_id)
    assert session.session_id not in store._sessions
    assert not cookie_path.exists()
    assert record.sessionid == ""
    assert record.sid_tt is None or record.sid_tt == ""


def test_active_lease_multiple_acquisitions_and_releases(tmp_path: Path) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)

    # Acquire lease 1
    p1 = store.acquire_lease(session.session_id)
    assert p1 is not None and p1.is_file()
    assert store._sessions[session.session_id].active_leases == 1

    # Acquire lease 2 concurrently
    p2 = store.acquire_lease(session.session_id)
    assert p2 == p1
    assert store._sessions[session.session_id].active_leases == 2

    # Release lease 1: cookie file must remain on disk because lease 2 is still active
    store.release_lease(session.session_id)
    assert store._sessions[session.session_id].active_leases == 1
    assert p1.is_file()

    # Release lease 2: leases drop to 0, session still valid so file stays for next reuse
    store.release_lease(session.session_id)
    assert store._sessions[session.session_id].active_leases == 0
    assert p1.is_file()

    # Invalidate session: since active_leases == 0, file must be unlinked immediately
    store.invalidate(session.session_id)
    assert not p1.exists()


def test_active_lease_double_acquire_invalidate_then_releases(tmp_path: Path) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)

    # Acquire lease twice
    cookie_path = store.acquire_lease(session.session_id)
    assert cookie_path is not None
    store.acquire_lease(session.session_id)
    assert store._sessions[session.session_id].active_leases == 2

    # Invalidate while 2 leases are active
    assert store.invalidate(session.session_id) is True
    assert session.session_id in store._pending_release_records
    assert cookie_path.is_file()

    # Release first lease: 1 lease remains active, file MUST NOT be deleted yet
    store.release_lease(session.session_id)
    assert store._pending_release_records[session.session_id].active_leases == 1
    assert cookie_path.is_file()

    # Release second lease: last lease released, file MUST be deleted and memory wiped
    store.release_lease(session.session_id)
    assert not cookie_path.exists()
    assert session.session_id not in store._pending_release_records


def test_release_lease_no_negative_count(tmp_path: Path) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)

    store.release_lease(session.session_id)
    assert store._sessions[session.session_id].active_leases == 0
    store.release_lease(session.session_id)
    assert store._sessions[session.session_id].active_leases == 0


def test_session_isolation_and_path_traversal(tmp_path: Path) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session_a = store.create_session(sessionid=_SESSIONID_A, sid_tt=_SID_TT_A)
    session_b = store.create_session(sessionid=_SESSIONID_B, sid_tt=_SID_TT_B)

    assert session_a.session_id != session_b.session_id

    file_a = store.get_cookie_file(session_a.session_id)
    file_b = store.get_cookie_file(session_b.session_id)
    assert file_a is not None and file_b is not None
    assert file_a != file_b
    assert _SESSIONID_A in file_a.read_text(encoding="utf-8")
    assert _SESSIONID_B not in file_a.read_text(encoding="utf-8")
    assert _SESSIONID_B in file_b.read_text(encoding="utf-8")
    assert _SESSIONID_A not in file_b.read_text(encoding="utf-8")

    # Invalidate A does not affect B
    store.invalidate(session_a.session_id)
    assert not file_a.exists()
    assert file_b.exists()
    assert store.is_valid(session_b.session_id) is True
    assert store.is_valid(session_a.session_id) is False

    # Path traversal attempts
    for bad_id in (
        "../../etc/passwd",
        "..\\..\\windows\\system32",
        "0123456789abcdef/sub",
        "0123456789abcdef\x00extra",
        "",
        "   ",
        "short",
    ):
        assert store.get_cookie_file(bad_id) is None
        assert store.acquire_lease(bad_id) is None
        assert store.is_valid(bad_id) is False
        assert store.invalidate(bad_id) is False


def test_cleanup_orphaned_cookies(tmp_path: Path) -> None:
    sessions_dir = tmp_path / "tiktok_sessions"
    sessions_dir.mkdir(parents=True)
    orphan1 = sessions_dir / "orphan1.cookies.txt"
    orphan2 = sessions_dir / "orphan2.cookies.txt"
    orphan1.write_text("old junk", encoding="utf-8")
    orphan2.write_text("old junk", encoding="utf-8")

    # Instantiate store with cleanup_on_startup=True
    EphemeralTikTokUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)
    assert not orphan1.exists()
    assert not orphan2.exists()
