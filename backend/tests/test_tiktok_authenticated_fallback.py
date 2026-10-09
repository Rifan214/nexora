from __future__ import annotations

import logging
from pathlib import Path

import pytest
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.core.config import get_settings
from app.core.exceptions import APIError
from app.models.job import JobStatus
from app.models.tiktok_auth import TikTokAuthSource
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.resume_state_manager import ResumeStateManager
from app.services.tiktok_auth_manager import TikTokAuthManager
from app.services.tiktok_user_session_store import EphemeralTikTokUserSessionStore
from app.utils.storage import get_temp_storage_dir

_TIKTOK_URL = "https://www.tiktok.com/@user/video/7123456789012345678"
_FAKE_SESSIONID = "fake-sessionid-value"
_FAKE_SID_TT = "fake-sid-tt-value"


@pytest.fixture(autouse=True)
def clear_tiktok_auth_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_TIKTOK_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_tiktok_guest_success_does_not_attempt_authenticated_extraction(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_TIKTOK_URL)

    assert metadata.video_qualities
    assert calls == [None]
    assert cookie_file not in calls


def test_tiktok_guest_failure_does_not_retry_when_authentication_is_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    calls = 0

    def extract(_: str) -> dict:
        nonlocal calls
        calls += 1
        raise DownloadError("Log in for access")

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.code == "TIKTOK_LOGIN_REQUIRED"
    assert calls == 1


def test_tiktok_guest_login_required_retries_with_configured_authentication(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        if cookie_file is None:
            raise DownloadError("Log in for access")
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_TIKTOK_URL)

    assert [quality.height for quality in metadata.video_qualities] == [1080]
    assert calls == [None, cookie_file]
    snapshot = service._snapshot_cache.get(_TIKTOK_URL)
    assert snapshot is not None
    assert snapshot.authenticated is True


def test_tiktok_user_session_retries_with_ephemeral_cookie(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    store = EphemeralTikTokUserSessionStore(storage_dir=tmp_path)
    session = store.create_session(sessionid=_FAKE_SESSIONID, sid_tt=_FAKE_SID_TT)
    auth_manager = TikTokAuthManager(user_session_store=store)
    service = MediaService(tiktok_auth_manager=auth_manager)
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        if cookie_file is None:
            raise DownloadError("Log in for access")
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(
        _TIKTOK_URL,
        auth_source="user_session",
        auth_session_id=session.session_id,
    )

    assert [quality.height for quality in metadata.video_qualities] == [1080]
    assert len(calls) == 2
    assert calls[0] is None
    assert calls[1] is not None
    assert calls[1].is_file()
    assert _FAKE_SESSIONID in calls[1].read_text(encoding="utf-8")

    snapshot = service._snapshot_cache.get(_TIKTOK_URL, session_id=session.session_id)
    assert snapshot is not None
    assert snapshot.authenticated is True
    assert snapshot.auth_source == "user_session"
    assert snapshot.session_id == session.session_id


def test_tiktok_authenticated_failure_preserves_the_guest_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        raise DownloadError("Log in for access")

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.code == "TIKTOK_LOGIN_REQUIRED"
    assert calls == [None, cookie_file]


@pytest.mark.parametrize("error_code", ["NETWORK_FAILURE", "METADATA_EXTRACTION_ERROR"])
def test_tiktok_authenticated_fallback_does_not_retry_unrelated_errors(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    error_code: str,
) -> None:
    _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls = 0

    def extract(_: str) -> dict:
        nonlocal calls
        calls += 1
        raise APIError(
            code=error_code,
            message="Unrelated extraction failure",
            details="Unrelated extraction failure",
            status_code=500,
        )

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.code == error_code
    assert calls == 1


@pytest.mark.parametrize(
    ("url", "platform"),
    [
        ("https://www.youtube.com/watch?v=nexora", "youtube"),
        ("https://x.com/nexora/status/1900000000000000001", "twitter"),
    ],
)
def test_tiktok_authenticated_fallback_never_applies_to_other_platforms(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    url: str,
    platform: str,
) -> None:
    _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    cookie_files: list[Path | None] = []
    info = _youtube_info() if platform == "youtube" else _twitter_info()

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        cookie_files.append(cookie_file)
        return info

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(url)

    assert metadata.video_qualities
    assert cookie_files == [None]


def test_missing_cookie_file_fails_gracefully_without_exposing_its_path(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    missing_path = tmp_path / "private" / "missing.cookies.txt"
    monkeypatch.setenv("NEXORA_TIKTOK_AUTH_COOKIE_FILE", str(missing_path))
    get_settings.cache_clear()
    service = MediaService()
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(DownloadError("Log in for access")),
    )
    caplog.set_level(logging.INFO, logger="app.services.media_service")

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert error.value.code == "TIKTOK_LOGIN_REQUIRED"
    assert "cookie_file_unavailable" in messages
    assert str(missing_path) not in messages


def test_authenticated_snapshot_and_logs_never_contain_cookie_secrets(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        if cookie_file is None:
            raise DownloadError("Log in for access")
        info = _tiktok_info()
        info.update(
            {
                "sessionid": _FAKE_SESSIONID,
                "sid_tt": _FAKE_SID_TT,
                "cookies": f"sessionid={_FAKE_SESSIONID}",
                "http_headers": {
                    "Cookie": f"sessionid={_FAKE_SESSIONID}; sid_tt={_FAKE_SID_TT}",
                    "User-Agent": "safe-test-agent",
                },
            }
        )
        return info

    monkeypatch.setattr(service, "_extract_info", extract)
    caplog.set_level(logging.INFO, logger="app.services.media_service")

    service.get_metadata(_TIKTOK_URL)

    snapshot = service._snapshot_cache.get(_TIKTOK_URL)
    assert snapshot is not None
    assert snapshot.authenticated is True
    assert "sessionid" not in snapshot.extracted_info
    assert "sid_tt" not in snapshot.extracted_info
    assert "cookies" not in snapshot.extracted_info
    assert snapshot.extracted_info["http_headers"] == {"User-Agent": "safe-test-agent"}
    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert _FAKE_SESSIONID not in messages
    assert _FAKE_SID_TT not in messages
    assert str(cookie_file) not in messages


def test_authenticated_cookie_configuration_reaches_the_download_worker(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    job_manager = JobManager()
    process_manager = DownloadProcessManager()
    resume_manager = ResumeStateManager(storage_dir=tmp_path / "resume")
    service = MediaService(
        process_manager=process_manager,
        job_manager=job_manager,
        resume_state_manager=resume_manager,
    )
    _WorkerYoutubeDL.instances = []
    monkeypatch.setattr(media_service_module, "YoutubeDL", _WorkerYoutubeDL)
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
            _tiktok_info(),
            True,
        )

        completed = job_manager.get_job(job.job_id)
        assert completed is not None
        assert completed.status is JobStatus.completed
        assert _WorkerYoutubeDL.instances
        assert all(instance.options["cookiefile"] == str(cookie_file) for instance in _WorkerYoutubeDL.instances)
    finally:
        downloaded_file.unlink(missing_ok=True)
        resume_manager.delete(job.job_id)


def test_authenticated_cookie_configuration_reaches_metadata_youtube_dl(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    _MetadataYoutubeDL.instances = []
    monkeypatch.setattr(media_service_module, "YoutubeDL", _MetadataYoutubeDL)

    info = service._extract_info(_TIKTOK_URL, cookie_file=cookie_file)

    assert info["extractor_key"] == "TikTok"
    assert _MetadataYoutubeDL.instances[0].options["cookiefile"] == str(cookie_file)


def _configure_cookie_file(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    cookie_file = tmp_path / "tiktok-auth.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\t{_FAKE_SESSIONID}\n"
        f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsid_tt\t{_FAKE_SID_TT}\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("NEXORA_TIKTOK_AUTH_COOKIE_FILE", str(cookie_file))
    get_settings.cache_clear()
    return cookie_file


def _tiktok_info() -> dict:
    return {
        "id": "7123456789012345678",
        "title": "Authenticated TikTok media",
        "uploader": "Nexora",
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


def _twitter_info() -> dict:
    info = _tiktok_info()
    info.update({"extractor": "Twitter", "extractor_key": "Twitter"})
    return info


def _youtube_info() -> dict:
    info = _tiktok_info()
    info.update({"extractor": "youtube", "extractor_key": "Youtube"})
    return info


class _WorkerYoutubeDL:
    instances: list["_WorkerYoutubeDL"] = []

    def __init__(self, options: dict) -> None:
        self.options = options
        self.refresh_calls: list[tuple[str, bool, bool]] = []
        self.instances.append(self)

    def __enter__(self) -> "_WorkerYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, url: str, *, download: bool, process: bool = True) -> dict:
        self.refresh_calls.append((url, download, process))
        return _tiktok_info()

    def process_ie_result(self, info: dict, *, download: bool) -> dict:
        assert download is True
        output_path = Path(self.options["outtmpl"].replace("%(ext)s", "mp4"))
        output_path.write_bytes(b"authenticated-worker-test")
        return info


class _MetadataYoutubeDL:
    instances: list["_MetadataYoutubeDL"] = []

    def __init__(self, options: dict) -> None:
        self.options = options
        self.instances.append(self)

    def __enter__(self) -> "_MetadataYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, _: str, *, download: bool) -> dict:
        assert download is False
        return _tiktok_info()
