from __future__ import annotations

import logging
from pathlib import Path

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
from app.services.tiktok_auth_providers import (
    GuestTikTokAuthProvider,
    ServiceAccountTikTokAuthProvider,
    UserSessionTikTokAuthProvider,
)
from app.utils.storage import get_temp_storage_dir

_TIKTOK_URL = "https://www.tiktok.com/@user/video/7123456789012345678"
_SESSIONID = "secret-sessionid-123"
_SID_TT = "secret-sid-tt-xyz"


@pytest.fixture(autouse=True)
def clear_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_TIKTOK_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _write_cookie_file(
    path: Path,
    *,
    include_sessionid: bool = True,
    include_sid_tt: bool = True,
    malformed: bool = False,
) -> Path:
    if malformed:
        path.write_text("NOT A NETSCAPE COOKIE FILE", encoding="utf-8")
        return path

    lines = ["# Netscape HTTP Cookie File"]
    if include_sessionid:
        lines.append(f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\t{_SESSIONID}")
    if include_sid_tt:
        lines.append(f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsid_tt\t{_SID_TT}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def _fake_tiktok_info() -> dict:
    return {
        "id": "7123456789012345678",
        "title": "TikTok Video Title",
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
                "url": "https://example.test/tiktok.mp4",
            },
        ],
    }


# ==============================================================================
# 1. Guest Provider Tests
# ==============================================================================

def test_guest_provider_is_available_without_credentials() -> None:
    provider = GuestTikTokAuthProvider()
    assert provider.is_available() is True
    assert provider.source == TikTokAuthSource.GUEST

    session = provider.get_session()
    assert session.authenticated is False
    assert session.source == TikTokAuthSource.GUEST
    assert session.status == TikTokAuthStatus.AVAILABLE
    assert provider.get_cookie_file() is None


def test_guest_context_has_authenticated_false() -> None:
    manager = TikTokAuthManager()
    guest_context = manager.build_context(TikTokAuthSource.GUEST)
    assert guest_context.authenticated is False
    assert guest_context.source == TikTokAuthSource.GUEST
    assert guest_context.status == TikTokAuthStatus.AVAILABLE
    assert "sessionid" not in guest_context.metadata
    assert "sid_tt" not in guest_context.metadata
    assert repr(guest_context) == "TikTokAuthContext(source='guest', authenticated=False, status='available')"


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
            return _fake_tiktok_info()

        def process_ie_result(self, info: dict, *, download: bool) -> dict:
            outtmpl = self.options["outtmpl"].replace("%(ext)s", "mp4")
            Path(outtmpl).write_bytes(b"guest-worker-data")
            return info

    monkeypatch.setattr(media_service_module, "YoutubeDL", _CaptureYoutubeDL)
    job = job_manager.create_job(
        media_url=_TIKTOK_URL,
        platform="tiktok",
        format_id="download_addr-0",
        output_type="video",
    )
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.mp4"

    try:
        service._download_job_background(
            job.job_id,
            _TIKTOK_URL,
            "download_addr-0",
            "video",
            _fake_tiktok_info(),
            authenticated=False,
        )
        assert _CaptureYoutubeDL.instances
        assert _CaptureYoutubeDL.instances[0].options.get("cookiefile") is None
    finally:
        downloaded_file.unlink(missing_ok=True)
        resume_manager.delete(job.job_id)


# ==============================================================================
# 2. Service Account Provider Tests
# ==============================================================================

def test_service_account_provider_unavailable_when_unconfigured() -> None:
    provider = ServiceAccountTikTokAuthProvider(cookie_file_path="")
    assert provider.is_available() is False
    assert provider.get_cookie_file() is None

    session = provider.get_session()
    assert session.authenticated is False
    assert session.status == TikTokAuthStatus.UNAVAILABLE


def test_service_account_provider_available_when_cookie_file_valid(tmp_path: Path) -> None:
    cookie_path = _write_cookie_file(tmp_path / "valid.cookies.txt")
    provider = ServiceAccountTikTokAuthProvider(cookie_file_path=cookie_path)

    assert provider.is_available() is True
    assert provider.get_cookie_file() == cookie_path

    session = provider.get_session()
    assert session.authenticated is True
    assert session.status == TikTokAuthStatus.AVAILABLE
    assert session.source == TikTokAuthSource.SERVICE_ACCOUNT


def test_service_account_provider_unavailable_when_cookie_file_missing(tmp_path: Path) -> None:
    missing_path = tmp_path / "nonexistent.cookies.txt"
    provider = ServiceAccountTikTokAuthProvider(cookie_file_path=missing_path)

    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


def test_service_account_provider_unavailable_when_cookie_file_malformed(tmp_path: Path) -> None:
    malformed_path = _write_cookie_file(tmp_path / "malformed.txt", malformed=True)
    provider = ServiceAccountTikTokAuthProvider(cookie_file_path=malformed_path)

    assert provider.is_available() is False
    assert provider.get_cookie_file() is None


# ==============================================================================
# 3. TikTokAuthManager Orchestration & Provider Selection Tests
# ==============================================================================

def test_manager_get_authenticated_provider_prefers_user_session(tmp_path: Path) -> None:
    cookie_path = _write_cookie_file(tmp_path / "svc.cookies.txt")
    manager = TikTokAuthManager(service_account_cookie_file=cookie_path)
    session = manager.user_session_store.create_session(sessionid=_SESSIONID, sid_tt=_SID_TT)

    # When session_id is provided, should return user session provider
    provider = manager.get_authenticated_provider(session_id=session.session_id)
    assert provider is not None
    assert provider.source == TikTokAuthSource.USER_SESSION

    # When no session_id is provided, should fall back to service account provider
    provider_fallback = manager.get_authenticated_provider()
    assert provider_fallback is not None
    assert provider_fallback.source == TikTokAuthSource.SERVICE_ACCOUNT


def test_manager_acquire_and_release_session_lease(tmp_path: Path) -> None:
    manager = TikTokAuthManager()
    session = manager.user_session_store.create_session(sessionid=_SESSIONID, sid_tt=_SID_TT)

    cookie_file = manager.acquire_session_lease(source=TikTokAuthSource.USER_SESSION, session_id=session.session_id)
    assert cookie_file is not None
    assert cookie_file.is_file()
    assert manager.user_session_store._sessions[session.session_id].active_leases == 1

    manager.release_session_lease(source=TikTokAuthSource.USER_SESSION, session_id=session.session_id)
    assert manager.user_session_store._sessions[session.session_id].active_leases == 0
