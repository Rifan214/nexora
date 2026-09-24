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
from app.models.x_auth import XAuthContext, XAuthSession, XAuthSource, XAuthStatus
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.media_snapshot_cache import MediaSnapshotCache
from app.services.resume_state_manager import ResumeStateManager
from app.services.x_auth_manager import XAuthManager
from app.services.x_auth_providers import UserSessionXAuthProvider
from app.services.x_user_session_store import EphemeralXUserSessionStore
from app.utils.storage import get_temp_storage_dir

_X_URL = "https://x.com/nexora/status/1900000000000000001"
_TOKEN_A = "auth-token-user-A"
_CT0_A = "ct0-user-A"
_TOKEN_B = "auth-token-user-B"
_CT0_B = "ct0-user-B"


@pytest.fixture(autouse=True)
def reset_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_X_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _fake_x_info() -> dict:
    return {
        "id": "1900000000000000001",
        "title": "X User Protected Video",
        "uploader": "nexora_protected",
        "extractor": "Twitter",
        "extractor_key": "Twitter",
        "formats": [
            {
                "format_id": "x-audio",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "aac",
                "abr": 128,
                "url": "https://example.test/audio",
            },
            {
                "format_id": "x-720",
                "width": 1280,
                "height": 720,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "none",
                "url": "https://example.test/video",
            },
        ],
    }


# ==============================================================================
# A. UserSessionXAuthProvider Tests
# ==============================================================================

def test_user_session_provider_unavailable_without_session() -> None:
    store = EphemeralXUserSessionStore()
    provider = UserSessionXAuthProvider(session_store=store)

    assert provider.source == XAuthSource.USER_SESSION
    assert provider.is_available() is False
    assert provider.is_available("nonexistent") is False
    assert provider.get_cookie_file() is None
    assert provider.get_cookie_file("nonexistent") is None

    session = provider.get_session()
    assert session.authenticated is False
    assert session.status == XAuthStatus.UNAVAILABLE


def test_user_session_provider_available_with_valid_session() -> None:
    store = EphemeralXUserSessionStore()
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    provider = UserSessionXAuthProvider(session_store=store)

    assert provider.is_available(session.session_id) is True
    retrieved = provider.get_session(session.session_id)
    assert retrieved.authenticated is True
    assert retrieved.status == XAuthStatus.AVAILABLE
    assert retrieved.source == XAuthSource.USER_SESSION
    assert retrieved.session_id == session.session_id

    cookie_file = provider.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()


def test_user_session_provider_expired_session() -> None:
    clock = datetime(2026, 9, 24, 12, 0, 0, tzinfo=UTC)
    store = EphemeralXUserSessionStore(now=lambda: clock)
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A, ttl_seconds=60)
    provider = UserSessionXAuthProvider(session_store=store)

    assert provider.is_available(session.session_id) is True

    # Advance clock past TTL
    clock += timedelta(seconds=61)
    assert provider.is_available(session.session_id) is False
    retrieved = provider.get_session(session.session_id)
    assert retrieved.authenticated is False
    assert retrieved.status == XAuthStatus.EXPIRED
    assert provider.get_cookie_file(session.session_id) is None


def test_user_session_provider_invalidated_session() -> None:
    store = EphemeralXUserSessionStore()
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    provider = UserSessionXAuthProvider(session_store=store)

    cookie_file = provider.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    provider.invalidate(session.session_id)
    assert provider.is_available(session.session_id) is False
    retrieved = provider.get_session(session.session_id)
    assert retrieved.authenticated is False
    assert retrieved.status == XAuthStatus.INVALID
    assert provider.get_cookie_file(session.session_id) is None
    # Verify ephemeral file was cleaned up on disk
    assert not cookie_file.exists()


# ==============================================================================
# B. Session Store Tests
# ==============================================================================

def test_session_store_create_retrieve_unknown() -> None:
    store = EphemeralXUserSessionStore()

    with pytest.raises(ValueError, match="auth_token and ct0 must be non-empty"):
        store.create_session(auth_token="", ct0=_CT0_A)

    with pytest.raises(ValueError, match="auth_token and ct0 must be non-empty"):
        store.create_session(auth_token=_TOKEN_A, ct0="   ")

    session = store.create_session(
        auth_token=_TOKEN_A,
        ct0=_CT0_A,
        metadata={"user_screen_name": "alice"},
    )
    assert session.session_id is not None
    assert len(session.session_id) == 32  # 16-byte hex
    assert session.metadata.get("user_screen_name") == "alice"
    assert "auth_token" not in session.metadata

    # Retrieve valid
    retrieved = store.get_session(session.session_id)
    assert retrieved.authenticated is True
    assert retrieved.session_id == session.session_id

    # Retrieve unknown
    unknown = store.get_session("totally-unknown-id")
    assert unknown.authenticated is False
    assert unknown.status == XAuthStatus.UNAVAILABLE


def test_session_store_cleanup_expired_and_clear() -> None:
    clock = datetime(2026, 9, 24, 12, 0, 0, tzinfo=UTC)
    store = EphemeralXUserSessionStore(now=lambda: clock)

    s1 = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A, ttl_seconds=30)
    s2 = store.create_session(auth_token=_TOKEN_B, ct0=_CT0_B, ttl_seconds=300)
    assert len(store) == 2

    # Advance clock past s1
    clock += timedelta(seconds=35)
    evicted = store.cleanup_expired()
    assert evicted == 1
    assert len(store) == 1
    assert store.is_valid(s1.session_id) is False
    assert store.is_valid(s2.session_id) is True

    # Clear for test isolation
    store.clear()
    assert len(store) == 0
    assert store.is_valid(s2.session_id) is False


# ==============================================================================
# C. Session Isolation Tests
# ==============================================================================

def test_session_isolation_between_users() -> None:
    store = EphemeralXUserSessionStore()
    session_a = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    session_b = store.create_session(auth_token=_TOKEN_B, ct0=_CT0_B)

    # Session A cannot be retrieved as Session B
    assert session_a.session_id != session_b.session_id

    file_a = store.get_cookie_file(session_a.session_id)
    file_b = store.get_cookie_file(session_b.session_id)
    assert file_a != file_b
    assert file_a is not None and file_b is not None

    content_a = file_a.read_text(encoding="utf-8")
    content_b = file_b.read_text(encoding="utf-8")
    assert _TOKEN_A in content_a
    assert _TOKEN_A not in content_b
    assert _TOKEN_B in content_b
    assert _TOKEN_B not in content_a

    # Invalidate A does not affect B
    store.invalidate(session_a.session_id)
    assert store.is_valid(session_a.session_id) is False
    assert store.is_valid(session_b.session_id) is True
    assert not file_a.exists()
    assert file_b.exists()


# ==============================================================================
# D. XAuthManager Integration Tests
# ==============================================================================

def test_manager_user_session_explicit_resolution(tmp_path: Path) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    manager = XAuthManager(user_session_store=store)

    # Guest by default
    assert manager.is_authenticated_available() is False

    # Explicit user session
    assert manager.is_authenticated_available(source=XAuthSource.USER_SESSION, session_id=session.session_id) is True
    provider = manager.get_authenticated_provider(source=XAuthSource.USER_SESSION, session_id=session.session_id)
    assert provider is not None
    assert provider.source == XAuthSource.USER_SESSION

    cookie_file = manager.get_cookie_file(source=XAuthSource.USER_SESSION, session_id=session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    # Context construction has session_id without credentials
    context = manager.build_context(source=XAuthSource.USER_SESSION, session_id=session.session_id)
    assert context.authenticated is True
    assert context.source == XAuthSource.USER_SESSION
    assert context.session_id == session.session_id
    assert _TOKEN_A not in repr(context)
    assert _CT0_A not in repr(context)


def test_manager_expired_user_session_does_not_fall_back_silently(tmp_path: Path) -> None:
    # Set up service account cookie
    service_cookie = tmp_path / "service.cookies.txt"
    service_cookie.write_text(
        "# Netscape HTTP Cookie File\n"
        ".x.com\tTRUE\t/\tTRUE\t2147483647\tauth_token\tservice-token\n"
        ".x.com\tTRUE\t/\tTRUE\t2147483647\tct0\tservice-ct0\n",
        encoding="utf-8",
    )

    clock = datetime(2026, 9, 24, 12, 0, 0, tzinfo=UTC)
    store = EphemeralXUserSessionStore(storage_dir=tmp_path, now=lambda: clock)
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A, ttl_seconds=30)
    manager = XAuthManager(
        service_account_cookie_file=str(service_cookie),
        user_session_store=store,
    )

    # While valid, user session is resolved
    assert manager.is_authenticated_available(source=XAuthSource.USER_SESSION, session_id=session.session_id) is True

    # Advance clock past expiration
    clock += timedelta(seconds=35)

    # When user session is requested specifically, it MUST NOT silently fall back to service account or guest
    auth_provider = manager.get_authenticated_provider(
        source=XAuthSource.USER_SESSION,
        session_id=session.session_id,
    )
    assert auth_provider is None
    assert manager.is_authenticated_available(source=XAuthSource.USER_SESSION, session_id=session.session_id) is False

    with pytest.raises(DownloadError, match="Authenticated X session unavailable"):
        manager.require_authenticated_cookie_file(
            source=XAuthSource.USER_SESSION,
            session_id=session.session_id,
        )


# ==============================================================================
# E. Snapshot Scoping & Isolation Tests
# ==============================================================================

def test_user_session_snapshot_isolation_and_no_credential_leak(tmp_path: Path) -> None:
    cache = MediaSnapshotCache()
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session_a = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    session_b = store.create_session(auth_token=_TOKEN_B, ct0=_CT0_B)

    manager = XAuthManager(user_session_store=store)
    service = MediaService(snapshot_cache=cache, x_auth_manager=manager)

    url = "https://x.com/user/status/999"
    info = _fake_x_info()

    # User A extracts and caches
    cache.put(
        url,
        info,
        authenticated=True,
        auth_source="user_session",
        session_id=session_a.session_id,
    )

    # 1. User A can retrieve User A's snapshot
    cached_a = service._get_cached_supported_info(url, auth_session_id=session_a.session_id)
    assert cached_a is not None
    assert cached_a[2] is True

    # 2. User B cannot retrieve User A's snapshot
    cached_b = service._get_cached_supported_info(url, auth_session_id=session_b.session_id)
    assert cached_b is None

    # 3. Guest cannot retrieve User A's snapshot
    cached_guest = service._get_cached_supported_info(url, auth_session_id=None)
    assert cached_guest is None

    # 4. Invalidation of User A's session invalidates the snapshot on next access
    store.invalidate(session_a.session_id)
    cached_after_invalidate = service._get_cached_supported_info(url, auth_session_id=session_a.session_id)
    assert cached_after_invalidate is None


# ==============================================================================
# F. Worker & Transport Refresh Tests
# ==============================================================================

def test_user_session_worker_uses_correct_cookie_and_no_cross_contamination(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session_a = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)
    session_b = store.create_session(auth_token=_TOKEN_B, ct0=_CT0_B)

    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    resume_manager = ResumeStateManager(storage_dir=tmp_path / "resume")
    manager = XAuthManager(user_session_store=store)
    service = MediaService(
        process_manager=process_manager,
        job_manager=job_manager,
        resume_state_manager=resume_manager,
        x_auth_manager=manager,
    )

    class _CaptureWorkerYoutubeDL:
        instances: list["_CaptureWorkerYoutubeDL"] = []

        def __init__(self, options: dict) -> None:
            self.options = options
            self.refresh_calls: list[tuple[str, bool, bool]] = []
            self.__class__.instances.append(self)

        def __enter__(self) -> "_CaptureWorkerYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def extract_info(self, url: str, *, download: bool, process: bool = True) -> dict:
            self.refresh_calls.append((url, download, process))
            return _fake_x_info()

        def process_ie_result(self, info: dict, *, download: bool) -> dict:
            outtmpl = self.options["outtmpl"].replace("%(ext)s", "mp4")
            Path(outtmpl).write_bytes(b"worker-data")
            return info

    monkeypatch.setattr(media_service_module, "YoutubeDL", _CaptureWorkerYoutubeDL)
    job = job_manager.create_job(
        media_url=_X_URL,
        platform="twitter",
        format_id="x-720+x-audio",
        output_type="video",
    )
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"

    try:
        service._download_job_background(
            job.job_id,
            _X_URL,
            "x-720+x-audio",
            "video",
            _fake_x_info(),
            authenticated=True,
            auth_source="user_session",
            auth_session_id=session_a.session_id,
        )

        completed = job_manager.get_job(job.job_id)
        assert completed is not None
        assert completed.status is JobStatus.completed

        # Verify worker received cookiefile containing Token A and NOT Token B
        cookie_file_path = Path(_CaptureWorkerYoutubeDL.instances[0].options["cookiefile"])
        assert cookie_file_path.is_file()
        content = cookie_file_path.read_text(encoding="utf-8")
        assert _TOKEN_A in content
        assert _TOKEN_B not in content
    finally:
        downloaded_file.unlink(missing_ok=True)
        resume_manager.delete(job.job_id)


def test_invalid_user_session_worker_fails_securely(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    resume_manager = ResumeStateManager(storage_dir=tmp_path / "resume")
    manager = XAuthManager(user_session_store=store)
    service = MediaService(
        process_manager=process_manager,
        job_manager=job_manager,
        resume_state_manager=resume_manager,
        x_auth_manager=manager,
    )

    job = job_manager.create_job(
        media_url=_X_URL,
        platform="twitter",
        format_id="x-720+x-audio",
        output_type="video",
    )

    service._download_job_background(
        job.job_id,
        _X_URL,
        "x-720+x-audio",
        "video",
        _fake_x_info(),
        authenticated=True,
        auth_source="user_session",
        auth_session_id="invalid-or-expired-id",
    )

    failed_job = job_manager.get_job(job.job_id)
    assert failed_job is not None
    assert failed_job.status is JobStatus.failed
    assert "Authenticated X session unavailable" in (failed_job.error_message or "")


# ==============================================================================
# G. Security, Permissions, Path Traversal, Lease, and Crash Recovery Tests
# ==============================================================================

def test_path_traversal_session_id_rejected(tmp_path: Path) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)

    traversal_ids = [
        "../../etc/passwd",
        "../cookies",
        "..\\windows\\system32",
        "invalid!token@chars#",
        "",
        "   ",
        "/absolute/path/attempt",
    ]

    for malicious_id in traversal_ids:
        assert store.get_cookie_file(malicious_id) is None
        assert store.acquire_lease(malicious_id) is None
        assert store.invalidate(malicious_id) is False
        session = store.get_session(malicious_id)
        assert session.authenticated is False
        assert session.status == XAuthStatus.UNAVAILABLE

    # Ensure no files or directories were created outside x_sessions
    assert not (tmp_path / "etc").exists()
    assert not (tmp_path / "passwd").exists()


def test_cookie_file_permissions_and_metadata_sanitization(tmp_path: Path) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(
        auth_token="token_secret_123",
        ct0="ct0_secret_456",
        metadata={
            "AUTH_TOKEN": "should_be_stripped_case_insensitively",
            "CT0": "should_be_stripped",
            "Cookie": "should_be_stripped",
            "safe_client": "nexora-mobile",
        },
    )

    # Verify sensitive metadata keys stripped case-insensitively
    assert "AUTH_TOKEN" not in session.metadata
    assert "CT0" not in session.metadata
    assert "Cookie" not in session.metadata
    assert session.metadata.get("safe_client") == "nexora-mobile"

    cookie_file = store.get_cookie_file(session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()

    # On POSIX, file mode should be 0600 (owner read/write only)
    import os
    if os.name == "posix":
        mode = cookie_file.stat().st_mode & 0o777
        assert mode == 0o600

    # Verify _EphemeralSessionRecord repr does not expose raw secrets
    record = store._sessions[session.session_id]
    record_repr = repr(record)
    assert "token_secret_123" not in record_repr
    assert "ct0_secret_456" not in record_repr
    assert session.session_id in record_repr


def test_crash_recovery_startup_orphaned_cookie_cleanup(tmp_path: Path) -> None:
    sessions_dir = tmp_path / "x_sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    stale_file = sessions_dir / "stale_dead_session.cookies.txt"
    stale_file.write_text("old-crash-credentials", encoding="utf-8")
    assert stale_file.is_file()

    # Startup of a new store instance must purge orphaned cookie files
    store = EphemeralXUserSessionStore(storage_dir=tmp_path, cleanup_on_startup=True)
    assert not stale_file.exists()


def test_active_lease_prevents_worker_invalidation_race(tmp_path: Path) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)

    # Worker acquires lease prior to execution
    cookie_path = store.acquire_lease(session.session_id)
    assert cookie_path is not None
    assert cookie_path.is_file()

    # Session is invalidated mid-download
    assert store.invalidate(session.session_id) is True

    # New requests immediately see session as invalid
    assert store.is_valid(session.session_id) is False
    assert store.get_session(session.session_id).status == XAuthStatus.INVALID

    # BUT the cookie file must remain on disk while worker lease is active
    assert cookie_path.is_file()

    # Once worker completes and releases lease, file is deleted and credentials cleared
    store.release_lease(session.session_id)
    assert not cookie_path.exists()


def test_expired_session_with_active_lease_deferred_cleanup(tmp_path: Path) -> None:
    clock = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    store = EphemeralXUserSessionStore(
        storage_dir=tmp_path,
        now=lambda: clock,
        cleanup_on_startup=False,
    )
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A, ttl_seconds=10)

    # Acquire lease while valid
    cookie_path = store.acquire_lease(session.session_id)
    assert cookie_path is not None
    assert cookie_path.is_file()

    # Advance clock past TTL
    clock += timedelta(seconds=20)
    assert store.get_session(session.session_id).status == XAuthStatus.EXPIRED

    # File still intact during worker run
    assert cookie_path.is_file()

    # Worker finishes
    store.release_lease(session.session_id)
    assert not cookie_path.exists()


def test_invalidated_and_expired_records_release_credentials_memory(tmp_path: Path) -> None:
    store = EphemeralXUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(auth_token=_TOKEN_A, ct0=_CT0_A)

    record = store._sessions[session.session_id]
    assert record.auth_token == _TOKEN_A

    store.invalidate(session.session_id)
    # Session popped from active registry
    assert session.session_id not in store._sessions
    # In-memory record credentials wiped
    assert record.auth_token == ""
    assert record.ct0 == ""

