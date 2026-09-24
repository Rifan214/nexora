from __future__ import annotations

import logging
from pathlib import Path

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
from app.services.x_auth_providers import (
    GuestXAuthProvider,
    ServiceAccountXAuthProvider,
    UserSessionXAuthProvider,
)
from app.utils.storage import get_temp_storage_dir

_X_URL = "https://x.com/nexora/status/1900000000000000001"
_AUTH_TOKEN = "secret-auth-token-123"
_CT0 = "secret-ct0-xyz"


@pytest.fixture(autouse=True)
def clear_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_X_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _write_cookie_file(
    path: Path,
    *,
    include_auth_token: bool = True,
    include_ct0: bool = True,
    malformed: bool = False,
) -> Path:
    if malformed:
        path.write_text("NOT A NETSCAPE COOKIE FILE", encoding="utf-8")
        return path

    lines = ["# Netscape HTTP Cookie File"]
    if include_auth_token:
        lines.append(f".x.com\tTRUE\t/\tTRUE\t2147483647\tauth_token\t{_AUTH_TOKEN}")
    if include_ct0:
        lines.append(f".x.com\tTRUE\t/\tTRUE\t2147483647\tct0\t{_CT0}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def _fake_x_info() -> dict:
    return {
        "id": "1900000000000000001",
        "title": "X Video Title",
        "uploader": "nexora",
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
# 1. Guest Provider Tests
# ==============================================================================

def test_guest_provider_is_available_without_credentials() -> None:
    provider = GuestXAuthProvider()
    assert provider.is_available() is True
    assert provider.source == XAuthSource.GUEST

    session = provider.get_session()
    assert session.authenticated is False
    assert session.source == XAuthSource.GUEST
    assert session.status == XAuthStatus.AVAILABLE
    assert provider.get_cookie_file() is None


def test_guest_context_has_authenticated_false() -> None:
    manager = XAuthManager()
    guest_context = manager.build_context(XAuthSource.GUEST)
    assert guest_context.authenticated is False
    assert guest_context.source == XAuthSource.GUEST
    assert guest_context.status == XAuthStatus.AVAILABLE
    assert "auth_token" not in guest_context.metadata
    assert "ct0" not in guest_context.metadata
    # Safe string representation check
    assert repr(guest_context) == "XAuthContext(source='guest', authenticated=False, status='available')"


def test_guest_worker_uses_cookiefile_none(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    resume_manager = ResumeStateManager(storage_dir=tmp_path / "resume")
    service = MediaService(
        process_manager=process_manager,
        job_manager=job_manager,
        resume_state_manager=resume_manager,
    )

    class _CaptureYoutubeDL:
        instances: list["_CaptureYoutubeDL"] = []

        def __init__(self, options: dict) -> None:
            self.options = options
            self.__class__.instances.append(self)

        def __enter__(self) -> "_CaptureYoutubeDL":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def extract_info(self, url: str, *, download: bool, process: bool = True) -> dict:
            return _fake_x_info()

        def process_ie_result(self, info: dict, *, download: bool) -> dict:
            outtmpl = self.options["outtmpl"].replace("%(ext)s", "mp4")
            Path(outtmpl).write_bytes(b"guest-worker-data")
            return info

    monkeypatch.setattr(media_service_module, "YoutubeDL", _CaptureYoutubeDL)
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
            authenticated=False,
        )

        completed = job_manager.get_job(job.job_id)
        assert completed is not None
        assert completed.status is JobStatus.completed
        assert _CaptureYoutubeDL.instances
        for inst in _CaptureYoutubeDL.instances:
            assert inst.options.get("cookiefile") is None
    finally:
        downloaded_file.unlink(missing_ok=True)
        resume_manager.delete(job.job_id)


# ==============================================================================
# 2. Service Account Provider Tests
# ==============================================================================

def test_service_account_unavailable_when_env_empty() -> None:
    provider = ServiceAccountXAuthProvider(cookie_file_path="")
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None

    session = provider.get_session()
    assert session.authenticated is False
    assert session.status == XAuthStatus.UNAVAILABLE


def test_service_account_rejects_missing_file(tmp_path: Path) -> None:
    missing = tmp_path / "does_not_exist.txt"
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(missing))
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


def test_service_account_rejects_malformed_file(tmp_path: Path) -> None:
    bad_file = _write_cookie_file(tmp_path / "bad.txt", malformed=True)
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(bad_file))
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


def test_service_account_rejects_missing_auth_token(tmp_path: Path) -> None:
    no_auth_token = _write_cookie_file(
        tmp_path / "no_auth_token.txt",
        include_auth_token=False,
        include_ct0=True,
    )
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(no_auth_token))
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


def test_service_account_rejects_missing_ct0(tmp_path: Path) -> None:
    no_ct0 = _write_cookie_file(
        tmp_path / "no_ct0.txt",
        include_auth_token=True,
        include_ct0=False,
    )
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(no_ct0))
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


def test_service_account_valid_file_creates_authenticated_context(tmp_path: Path) -> None:
    valid_file = _write_cookie_file(tmp_path / "valid.txt")
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(valid_file))
    assert provider.is_available() is True
    assert provider.get_cookie_file() == valid_file

    session = provider.get_session()
    assert session.authenticated is True
    assert session.status == XAuthStatus.AVAILABLE
    assert session.source == XAuthSource.SERVICE_ACCOUNT


def test_service_account_never_exposes_raw_cookie_values(
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    valid_file = _write_cookie_file(tmp_path / "valid.txt")
    provider = ServiceAccountXAuthProvider(cookie_file_path=str(valid_file))

    caplog.set_level(logging.DEBUG)
    session = provider.get_session()
    # Check session representation
    assert _AUTH_TOKEN not in repr(session)
    assert _CT0 not in repr(session)

    manager = XAuthManager(service_account_provider=provider)
    context = manager.build_context(XAuthSource.SERVICE_ACCOUNT)
    assert _AUTH_TOKEN not in repr(context)
    assert _CT0 not in repr(context)
    assert repr(context) == "XAuthContext(source='service_account', authenticated=True, status='available')"

    logs = "\n".join(rec.getMessage() for rec in caplog.records)
    assert _AUTH_TOKEN not in logs
    assert _CT0 not in logs


# ==============================================================================
# 3. User Session Provider (Extension Point Placeholder) Tests
# ==============================================================================

def test_user_session_provider_is_placeholder() -> None:
    user_provider = UserSessionXAuthProvider()
    assert user_provider.is_available() is False
    assert user_provider.get_cookie_file() is None
    session = user_provider.get_session()
    assert session.source == XAuthSource.USER_SESSION
    assert session.authenticated is False
    assert session.status == XAuthStatus.UNAVAILABLE


# ==============================================================================
# 4. XAuthManager Routing & Fallback Tests
# ==============================================================================

def test_manager_routes_guest_by_default() -> None:
    manager = XAuthManager()
    guest_provider = manager.guest()
    assert guest_provider.is_available() is True
    assert manager.is_authenticated_available() is False
    assert manager.get_authenticated_provider() is None
    assert manager.get_cookie_file() is None


def test_manager_provides_service_account_when_available(tmp_path: Path) -> None:
    valid_file = _write_cookie_file(tmp_path / "valid.txt")
    manager = XAuthManager(service_account_cookie_file=str(valid_file))
    assert manager.is_authenticated_available() is True
    auth_provider = manager.get_authenticated_provider()
    assert auth_provider is not None
    assert auth_provider.source == XAuthSource.SERVICE_ACCOUNT
    assert manager.get_cookie_file() == valid_file


def test_manager_unavailable_service_account_does_not_break_guest(tmp_path: Path) -> None:
    bad_file = _write_cookie_file(tmp_path / "bad.txt", malformed=True)
    manager = XAuthManager(service_account_cookie_file=str(bad_file))
    assert manager.is_authenticated_available() is False
    assert manager.get_authenticated_provider() is None

    # Guest remains fully available
    guest = manager.guest()
    assert guest.is_available() is True
    assert guest.get_session().authenticated is False


# ==============================================================================
# 5. Snapshot Behavior Tests
# ==============================================================================

def test_snapshot_guest_vs_service_account_separation(tmp_path: Path) -> None:
    cache = MediaSnapshotCache()
    valid_file = _write_cookie_file(tmp_path / "valid.txt")
    manager = XAuthManager(service_account_cookie_file=str(valid_file))
    service = MediaService(snapshot_cache=cache, x_auth_manager=manager)

    # 1. Guest snapshot
    info = _fake_x_info()
    cache.put("https://x.com/user/status/1", info, authenticated=False, auth_source="guest")
    guest_snap = cache.get("https://x.com/user/status/1")
    assert guest_snap is not None
    assert guest_snap.authenticated is False
    assert guest_snap.auth_source == "guest"

    # 2. Service account snapshot
    cache.put(
        "https://x.com/user/status/2",
        info,
        authenticated=True,
        auth_source="service_account",
    )
    auth_snap = cache.get("https://x.com/user/status/2")
    assert auth_snap is not None
    assert auth_snap.authenticated is True
    assert auth_snap.auth_source == "service_account"

    # Verify no credential leakage in snapshot
    assert "auth_token" not in auth_snap.extracted_info
    assert "ct0" not in auth_snap.extracted_info


def test_snapshot_invalidation_when_cookie_becomes_unavailable(tmp_path: Path) -> None:
    cookie_path = tmp_path / "removable.txt"
    _write_cookie_file(cookie_path)
    manager = XAuthManager(service_account_cookie_file=str(cookie_path))
    cache = MediaSnapshotCache()
    service = MediaService(snapshot_cache=cache, x_auth_manager=manager)

    url = "https://x.com/user/status/123"
    cache.put(url, _fake_x_info(), authenticated=True, auth_source="service_account")

    # While cookie exists, cached info is returned
    cached = service._get_cached_supported_info(url)
    assert cached is not None
    assert cached[2] is True

    # Remove the cookie file -> next cache lookup must invalidate
    cookie_path.unlink()
    cached_after_unlink = service._get_cached_supported_info(url)
    assert cached_after_unlink is None
    assert cache.get(url) is None


# ==============================================================================
# 6. Worker & Transport Refresh Tests
# ==============================================================================

def test_service_account_worker_and_transport_refresh(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    valid_file = _write_cookie_file(tmp_path / "valid.txt")
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    resume_manager = ResumeStateManager(storage_dir=tmp_path / "resume")
    manager = XAuthManager(service_account_cookie_file=str(valid_file))
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
            Path(outtmpl).write_bytes(b"auth-worker-data")
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
        )

        completed = job_manager.get_job(job.job_id)
        assert completed is not None
        assert completed.status is JobStatus.completed
        assert _CaptureWorkerYoutubeDL.instances
        # Worker options must have the cookie file
        assert all(
            inst.options.get("cookiefile") == str(valid_file)
            for inst in _CaptureWorkerYoutubeDL.instances
        )
        # Transport refresh occurred with download=False, process=False
        assert _CaptureWorkerYoutubeDL.instances[0].refresh_calls == [(_X_URL, False, False)]
    finally:
        downloaded_file.unlink(missing_ok=True)
        resume_manager.delete(job.job_id)
