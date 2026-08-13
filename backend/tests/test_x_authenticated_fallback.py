from __future__ import annotations

import logging
from pathlib import Path

import pytest
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.core.config import get_settings
from app.core.exceptions import APIError
from app.models.job import JobStatus
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.resume_state_manager import ResumeStateManager
from app.utils.storage import get_temp_storage_dir


_X_URL = "https://x.com/nexora/status/1900000000000000001"
_FAKE_AUTH_TOKEN = "fake-auth-token-value"
_FAKE_CT0 = "fake-ct0-value"


@pytest.fixture(autouse=True)
def clear_x_auth_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEXORA_X_AUTH_COOKIE_FILE", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_x_guest_success_does_not_attempt_authenticated_extraction(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        return _twitter_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_X_URL)

    assert metadata.video_qualities
    assert calls == [None]
    assert cookie_file not in calls


def test_x_guest_failure_does_not_retry_when_authentication_is_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    calls = 0

    def extract(_: str) -> dict:
        nonlocal calls
        calls += 1
        raise DownloadError("No video could be found in this tweet")

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_X_URL)

    assert error.value.code == "X_MEDIA_NOT_AVAILABLE"
    assert calls == 1


def test_x_guest_no_media_retries_with_configured_authentication(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        if cookie_file is None:
            info = _twitter_info()
            info["formats"] = []
            return info
        return _twitter_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_X_URL)

    assert [quality.height for quality in metadata.video_qualities] == [720]
    assert metadata.audio_options
    assert calls == [None, cookie_file]
    snapshot = service._snapshot_cache.get(_X_URL)
    assert snapshot is not None
    assert snapshot.authenticated is True


def test_x_authenticated_failure_preserves_the_guest_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    calls: list[Path | None] = []

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        calls.append(cookie_file)
        raise DownloadError("No video could be found in this tweet")

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_X_URL)

    assert error.value.code == "X_MEDIA_NOT_AVAILABLE"
    assert calls == [None, cookie_file]


@pytest.mark.parametrize("error_code", ["NETWORK_FAILURE", "METADATA_EXTRACTION_ERROR"])
def test_x_authenticated_fallback_does_not_retry_unrelated_errors(
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
        service.get_metadata(_X_URL)

    assert error.value.code == error_code
    assert calls == 1


@pytest.mark.parametrize(
    ("url", "platform"),
    [
        ("https://www.youtube.com/watch?v=nexora", "youtube"),
        ("https://www.tiktok.com/@nexora/video/1900000000000000001", "tiktok"),
    ],
)
def test_x_authenticated_fallback_never_applies_to_other_platforms(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    url: str,
    platform: str,
) -> None:
    _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()
    cookie_files: list[Path | None] = []
    info = _youtube_info() if platform == "youtube" else _tiktok_info()

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
    monkeypatch.setenv("NEXORA_X_AUTH_COOKIE_FILE", str(missing_path))
    get_settings.cache_clear()
    service = MediaService()
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(DownloadError("No video could be found in this tweet")),
    )
    caplog.set_level(logging.INFO, logger="app.services.media_service")

    with pytest.raises(APIError) as error:
        service.get_metadata(_X_URL)

    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert error.value.code == "X_MEDIA_NOT_AVAILABLE"
    assert "cookie_file_unavailable" in messages
    assert str(missing_path) not in messages


def test_invalid_cookie_file_fails_gracefully(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    invalid_cookie_file = tmp_path / "invalid.cookies.txt"
    invalid_cookie_file.write_text("not a Netscape cookie file", encoding="utf-8")
    monkeypatch.setenv("NEXORA_X_AUTH_COOKIE_FILE", str(invalid_cookie_file))
    get_settings.cache_clear()
    service = MediaService()
    calls = 0

    def extract(_: str) -> dict:
        nonlocal calls
        calls += 1
        raise DownloadError("No video could be found in this tweet")

    monkeypatch.setattr(service, "_extract_info", extract)
    caplog.set_level(logging.INFO, logger="app.services.media_service")

    with pytest.raises(APIError) as error:
        service.get_metadata(_X_URL)

    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert error.value.code == "X_MEDIA_NOT_AVAILABLE"
    assert calls == 1
    assert "cookie_file_unavailable" in messages
    assert str(invalid_cookie_file) not in messages


def test_authenticated_snapshot_and_logs_never_contain_cookie_secrets(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    cookie_file = _configure_cookie_file(monkeypatch, tmp_path)
    service = MediaService()

    def extract(_: str, *, cookie_file: Path | None = None) -> dict:
        if cookie_file is None:
            raise DownloadError("No video could be found in this tweet")
        info = _twitter_info()
        info.update(
            {
                "auth_token": _FAKE_AUTH_TOKEN,
                "ct0": _FAKE_CT0,
                "cookies": f"auth_token={_FAKE_AUTH_TOKEN}",
                "http_headers": {
                    "Authorization": _FAKE_AUTH_TOKEN,
                    "Cookie": _FAKE_CT0,
                    "User-Agent": "safe-test-agent",
                },
            }
        )
        return info

    monkeypatch.setattr(service, "_extract_info", extract)
    caplog.set_level(logging.INFO, logger="app.services.media_service")

    service.get_metadata(_X_URL)

    snapshot = service._snapshot_cache.get(_X_URL)
    assert snapshot is not None
    assert snapshot.authenticated is True
    assert "auth_token" not in snapshot.extracted_info
    assert "ct0" not in snapshot.extracted_info
    assert "cookies" not in snapshot.extracted_info
    assert snapshot.extracted_info["http_headers"] == {"User-Agent": "safe-test-agent"}
    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert _FAKE_AUTH_TOKEN not in messages
    assert _FAKE_CT0 not in messages
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
            _twitter_info(),
            True,
        )

        completed = job_manager.get_job(job.job_id)
        assert completed is not None
        assert completed.status is JobStatus.completed
        assert _WorkerYoutubeDL.instances
        assert all(instance.options["cookiefile"] == str(cookie_file) for instance in _WorkerYoutubeDL.instances)
        assert _WorkerYoutubeDL.instances[0].refresh_calls == [(_X_URL, False, False)]
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

    info = service._extract_info(_X_URL, cookie_file=cookie_file)

    assert info["extractor_key"] == "Twitter"
    assert _MetadataYoutubeDL.instances[0].options["cookiefile"] == str(cookie_file)


def _configure_cookie_file(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    cookie_file = tmp_path / "x-auth.cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        f".x.com\tTRUE\t/\tTRUE\t2147483647\tauth_token\t{_FAKE_AUTH_TOKEN}\n"
        f".x.com\tTRUE\t/\tTRUE\t2147483647\tct0\t{_FAKE_CT0}\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("NEXORA_X_AUTH_COOKIE_FILE", str(cookie_file))
    get_settings.cache_clear()
    return cookie_file


def _twitter_info() -> dict:
    return {
        "id": "1900000000000000001",
        "title": "Authenticated X media",
        "uploader": "Nexora",
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


def _youtube_info() -> dict:
    info = _twitter_info()
    info.update({"extractor": "youtube", "extractor_key": "Youtube"})
    return info


def _tiktok_info() -> dict:
    info = _twitter_info()
    info.update({"extractor": "TikTok", "extractor_key": "TikTok"})
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
        return _twitter_info()

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
        return _twitter_info()
