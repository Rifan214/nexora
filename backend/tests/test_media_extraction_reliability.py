from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from yt_dlp.utils import DownloadError

from app.api.routes.media import get_media_service
from app.core.exceptions import APIError
from app.main import create_app
from app.models.requests import MediaDownloadRequest
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.queue_manager import QueueManager


_TIKTOK_URL = "https://www.tiktok.com/@nexora/video/1900000000000000001"
_MIX_FAILURE = "ERROR: [youtube:tab] playlist type is unviewable"


@pytest.mark.parametrize(
    ("playlist_id", "seed_id"),
    [
        ("RDSJeBW8m5Y_I", "SJeBW8m5Y_I"),
        ("RDdQw4w9WgXcQ", "dQw4w9WgXcQ"),
    ],
)
def test_seed_mix_metadata_is_reconstructed_only_after_supported_failure(
    monkeypatch: pytest.MonkeyPatch,
    playlist_id: str,
    seed_id: str,
) -> None:
    service = MediaService()
    original_url = f"https://youtube.com/playlist?list={playlist_id}&playnext=1"
    watch_url = _mix_watch_url(playlist_id, seed_id)
    media_calls: list[str] = []
    playlist_calls: list[str] = []

    def extract_media(url: str) -> dict:
        media_calls.append(url)
        if url == original_url:
            raise DownloadError(_MIX_FAILURE)
        assert url == watch_url
        return _youtube_info(seed_id)

    def extract_playlist(url: str) -> dict:
        playlist_calls.append(url)
        assert url == watch_url
        return _mix_playlist_info(playlist_id, seed_id)

    monkeypatch.setattr(service, "_extract_info", extract_media)
    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    metadata = service.get_metadata(original_url)

    assert metadata.title == "Seed video"
    assert media_calls == [original_url, watch_url]
    assert playlist_calls == [watch_url]
    assert service._snapshot_cache.get(original_url) is not None


def test_seed_mix_playlist_preview_uses_the_validated_reconstruction(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    playlist_id = "RDSJeBW8m5Y_I"
    seed_id = "SJeBW8m5Y_I"
    original_url = f"https://youtube.com/playlist?list={playlist_id}&playnext=1"
    watch_url = _mix_watch_url(playlist_id, seed_id)
    calls: list[str] = []

    def extract_playlist(url: str) -> dict:
        calls.append(url)
        if url == original_url:
            raise DownloadError(
                "ERROR: channel/playlist does not exist and the URL redirected to youtube.com home page"
            )
        return _mix_playlist_info(playlist_id, seed_id)

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    metadata = service.get_playlist_metadata(original_url)

    assert metadata.title == "Seed Mix"
    assert metadata.total_count == 2
    assert metadata.items[0].webpage_url.endswith(seed_id)
    assert calls == [original_url, watch_url]


@pytest.mark.parametrize(
    ("playlist_id", "seed_id"),
    [
        ("RDSJeBW8m5Y_I", "SJeBW8m5Y_I"),
        ("RDdQw4w9WgXcQ", "dQw4w9WgXcQ"),
    ],
)
def test_playlist_info_endpoint_reconstructs_valid_seed_mix(
    monkeypatch: pytest.MonkeyPatch,
    playlist_id: str,
    seed_id: str,
) -> None:
    service = MediaService()
    original_url = f"https://youtube.com/playlist?list={playlist_id}&playnext=1"
    watch_url = _mix_watch_url(playlist_id, seed_id)
    calls: list[str] = []

    def extract_playlist(url: str) -> dict:
        calls.append(url)
        if url == original_url:
            raise DownloadError(_MIX_FAILURE)
        assert url == watch_url
        return _mix_playlist_info(playlist_id, seed_id)

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    response = _post_playlist_info(service, original_url)

    assert response.status_code == 200
    assert response.json()["data"]["title"] == "Seed Mix"
    assert response.json()["data"]["total_count"] == 2
    assert response.json()["data"]["items"][0]["webpage_url"].endswith(seed_id)
    assert calls == [original_url, watch_url]


@pytest.mark.parametrize(
    ("url", "playlist_kind"),
    [
        ("https://www.youtube.com/playlist?list=PLnormal", "normal"),
        (
            "https://www.youtube.com/watch?v=SJeBW8m5Y_I"
            "&list=RDSJeBW8m5Y_I&start_radio=1",
            "mix",
        ),
    ],
)
def test_playlist_info_endpoint_leaves_supported_playlist_urls_unchanged(
    monkeypatch: pytest.MonkeyPatch,
    url: str,
    playlist_kind: str,
) -> None:
    service = MediaService()
    calls: list[str] = []
    playlist_info = (
        {
            "_type": "playlist",
            "id": "PLnormal",
            "title": "Normal playlist",
            "extractor": "youtube:tab",
            "extractor_key": "YoutubeTab",
            "entries": [
                {"id": "normal00001", "url": "normal00001", "title": "Normal"}
            ],
        }
        if playlist_kind == "normal"
        else _mix_playlist_info("RDSJeBW8m5Y_I", "SJeBW8m5Y_I")
    )

    def extract_playlist(value: str) -> dict:
        calls.append(value)
        return playlist_info

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    response = _post_playlist_info(service, url)

    assert response.status_code == 200
    assert calls == [url]


def test_playlist_info_endpoint_rejects_invalid_seed_reconstruction_without_cache(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    original_url = "https://www.youtube.com/playlist?list=RDinvalid0001"
    watch_url = _mix_watch_url("RDinvalid0001", "invalid0001")
    calls: list[str] = []

    def extract_playlist(url: str) -> dict:
        calls.append(url)
        if url == original_url:
            raise DownloadError(_MIX_FAILURE)
        return _mix_playlist_info("RDdifferent01", "different01")

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    response = _post_playlist_info(service, original_url)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "YOUTUBE_MIX_UNAVAILABLE"
    assert calls == [original_url, watch_url]
    assert service._snapshot_cache.get(original_url) is None


@pytest.mark.parametrize(
    "playlist_id",
    [
        "RDMM",
        "RDAMVMabcdefghijk",
        "RDCLAK5uy_generated_mix",
        "RDshort",
    ],
)
def test_playlist_info_endpoint_does_not_reconstruct_non_seed_mix_ids(
    monkeypatch: pytest.MonkeyPatch,
    playlist_id: str,
) -> None:
    service = MediaService()
    original_url = f"https://www.youtube.com/playlist?list={playlist_id}"
    calls: list[str] = []

    def extract_playlist(url: str) -> dict:
        calls.append(url)
        raise DownloadError(_MIX_FAILURE)

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)

    response = _post_playlist_info(service, original_url)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "YOUTUBE_MIX_UNAVAILABLE"
    assert calls == [original_url]
    assert service._snapshot_cache.get(original_url) is None


@pytest.mark.parametrize(
    "playlist_id",
    [
        "RDMM",
        "RDAMVMabcdef12345",
        "RDCLAK5uy_example_generated_mix",
        "RDshort",
    ],
)
def test_non_seed_mix_ids_are_never_reconstructed(
    monkeypatch: pytest.MonkeyPatch,
    playlist_id: str,
) -> None:
    service = MediaService()
    url = f"https://www.youtube.com/playlist?list={playlist_id}"
    playlist_calls: list[str] = []

    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(DownloadError(_MIX_FAILURE)),
    )
    monkeypatch.setattr(service, "_extract_playlist_info", lambda value: playlist_calls.append(value))

    with pytest.raises(APIError) as error:
        service.get_metadata(url)

    assert error.value.code == "YOUTUBE_MIX_UNAVAILABLE"
    assert error.value.status_code == 422
    assert playlist_calls == []
    assert service._snapshot_cache.get(url) is None


@pytest.mark.parametrize(
    ("returned_playlist_id", "first_entry_id", "media_id", "has_formats"),
    [
        ("RDwrongseed01", "wrongseed01", "SJeBW8m5Y_I", True),
        ("RDSJeBW8m5Y_I", "different01", "SJeBW8m5Y_I", True),
        ("RDSJeBW8m5Y_I", "SJeBW8m5Y_I", "different01", True),
        ("RDSJeBW8m5Y_I", "SJeBW8m5Y_I", "SJeBW8m5Y_I", False),
    ],
)
def test_invalid_seed_mix_reconstruction_is_rejected_and_not_cached(
    monkeypatch: pytest.MonkeyPatch,
    returned_playlist_id: str,
    first_entry_id: str,
    media_id: str,
    has_formats: bool,
) -> None:
    service = MediaService()
    url = "https://www.youtube.com/playlist?list=RDSJeBW8m5Y_I"
    playlist_info = _mix_playlist_info(returned_playlist_id, first_entry_id)
    media_info = _youtube_info(media_id, formats=None if has_formats else [])

    def extract_media(value: str) -> dict:
        if value == url:
            raise DownloadError(_MIX_FAILURE)
        return media_info

    monkeypatch.setattr(service, "_extract_info", extract_media)
    monkeypatch.setattr(service, "_extract_playlist_info", lambda _: playlist_info)

    with pytest.raises(APIError) as error:
        service.get_metadata(url)

    assert error.value.code == "YOUTUBE_MIX_UNAVAILABLE"
    assert error.value.status_code == 422
    assert service._snapshot_cache.get(url) is None


def test_normal_playlist_and_watch_mix_urls_are_unchanged(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService()
    normal_url = "https://www.youtube.com/playlist?list=PLnormal"
    watch_url = _mix_watch_url("RDSJeBW8m5Y_I", "SJeBW8m5Y_I")
    playlist_calls: list[str] = []
    media_calls: list[str] = []

    def extract_playlist(url: str) -> dict:
        playlist_calls.append(url)
        return {
            "_type": "playlist",
            "id": "PLnormal",
            "title": "Normal playlist",
            "extractor": "youtube:tab",
            "extractor_key": "YoutubeTab",
            "entries": [{"id": "normal00001", "url": "normal00001", "title": "Normal"}],
        }

    def extract_media(url: str) -> dict:
        media_calls.append(url)
        return _youtube_info("SJeBW8m5Y_I")

    monkeypatch.setattr(service, "_extract_playlist_info", extract_playlist)
    monkeypatch.setattr(service, "_extract_info", extract_media)

    assert service.get_playlist_metadata(normal_url).title == "Normal playlist"
    assert service.get_metadata(watch_url).title == "Seed video"
    assert playlist_calls == [normal_url]
    assert media_calls == [watch_url]


def test_validated_mix_source_is_reused_by_the_download_worker(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    playlist_id = "RDSJeBW8m5Y_I"
    seed_id = "SJeBW8m5Y_I"
    original_url = f"https://www.youtube.com/playlist?list={playlist_id}"
    watch_url = _mix_watch_url(playlist_id, seed_id)
    job_manager = JobManager()
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=QueueManager(job_manager=job_manager),
    )

    def extract_media(url: str) -> dict:
        if url == original_url:
            raise DownloadError(_MIX_FAILURE)
        return _youtube_info(seed_id)

    started: list[dict] = []
    monkeypatch.setattr(service, "_extract_info", extract_media)
    monkeypatch.setattr(
        service,
        "_extract_playlist_info",
        lambda _: _mix_playlist_info(playlist_id, seed_id),
    )
    monkeypatch.setattr(service, "_start_download_worker", lambda **kwargs: started.append(kwargs))

    service.get_metadata(original_url)
    job = service.create_download_job(
        MediaDownloadRequest(url=original_url, media_type="video", quality_height=360)
    )

    assert job.media_url == watch_url
    assert started[0]["url"] == watch_url


def test_tiktok_transient_failure_retries_until_success_and_caches_result(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sleeps: list[float] = []
    service = MediaService(sleep=sleeps.append, retry_jitter=lambda _low, high: high)
    attempts = 0

    def extract(_: str) -> dict:
        nonlocal attempts
        attempts += 1
        if attempts < 4:
            raise DownloadError("Unable to extract universal data for rehydration")
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_TIKTOK_URL)
    cached_metadata = service.get_metadata(_TIKTOK_URL)

    assert metadata.title == cached_metadata.title == "TikTok video"
    assert attempts == 4
    assert sleeps == pytest.approx([0.3, 0.6, 1.2])
    assert service._snapshot_cache.get(_TIKTOK_URL) is not None


def test_tiktok_first_transient_failure_succeeds_on_second_attempt(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sleeps: list[float] = []
    service = MediaService(sleep=sleeps.append, retry_jitter=lambda *_: 0.0)
    attempts = 0

    def extract(_: str) -> dict:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise DownloadError("Unexpected response from webpage request")
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    metadata = service.get_metadata(_TIKTOK_URL)

    assert metadata.title == "TikTok video"
    assert attempts == 2
    assert sleeps == [0.25]


@pytest.mark.parametrize(
    "message",
    [
        "Unable to extract universal data for rehydration",
        "Unexpected response from webpage request",
        "Unable to extract challenge data",
        "HTTP Error 503: Service Unavailable",
        "The read operation timed out",
    ],
)
def test_tiktok_transient_retry_is_bounded_and_failed_result_is_not_cached(
    monkeypatch: pytest.MonkeyPatch,
    message: str,
) -> None:
    sleeps: list[float] = []
    service = MediaService(sleep=sleeps.append, retry_jitter=lambda *_: 0.0)
    attempts = 0

    def extract(_: str) -> dict:
        nonlocal attempts
        attempts += 1
        raise DownloadError(message)

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.status_code == 502
    assert attempts == 4
    assert sleeps == [0.25, 0.5, 1.0]
    assert service._snapshot_cache.get(_TIKTOK_URL) is None


@pytest.mark.parametrize(
    ("message", "expected_code"),
    [
        ("Private video", "VIDEO_PRIVATE"),
        ("TikTok login required. Sign in to continue", "TIKTOK_LOGIN_REQUIRED"),
        ("This post may not be comfortable for some audiences. Log in for access", "TIKTOK_LOGIN_REQUIRED"),
        ("Use --cookies-from-browser or --cookies for the authentication", "TIKTOK_LOGIN_REQUIRED"),
        ("This video has been removed", "VIDEO_UNAVAILABLE"),
        ("Video unavailable", "VIDEO_UNAVAILABLE"),
    ],
)
def test_tiktok_permanent_failures_are_not_retried(
    monkeypatch: pytest.MonkeyPatch,
    message: str,
    expected_code: str,
) -> None:
    service = MediaService(sleep=lambda _: pytest.fail("unexpected retry"))
    attempts = 0

    def extract(_: str) -> dict:
        nonlocal attempts
        attempts += 1
        raise DownloadError(message)

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.code == expected_code
    assert attempts == 1


def test_tiktok_internal_errors_are_not_retried(monkeypatch: pytest.MonkeyPatch) -> None:
    service = MediaService(sleep=lambda _: pytest.fail("unexpected retry"))
    attempts = 0

    def extract(_: str) -> dict:
        nonlocal attempts
        attempts += 1
        raise RuntimeError("internal test failure")

    monkeypatch.setattr(service, "_extract_info", extract)

    with pytest.raises(APIError) as error:
        service.get_metadata(_TIKTOK_URL)

    assert error.value.code == "METADATA_EXTRACTION_ERROR"
    assert attempts == 1


def test_concurrent_tiktok_requests_share_one_in_flight_extraction(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = MediaService(sleep=lambda _: None, retry_jitter=lambda *_: 0.0)
    extraction_started = threading.Event()
    release_extraction = threading.Event()
    calls = 0
    active = 0
    maximum_active = 0
    state_lock = threading.Lock()

    def extract(_: str) -> dict:
        nonlocal calls, active, maximum_active
        with state_lock:
            calls += 1
            active += 1
            maximum_active = max(maximum_active, active)
        extraction_started.set()
        assert release_extraction.wait(timeout=2)
        with state_lock:
            active -= 1
        return _tiktok_info()

    monkeypatch.setattr(service, "_extract_info", extract)

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(service.get_metadata, _TIKTOK_URL)
        assert extraction_started.wait(timeout=1)
        second = executor.submit(service.get_metadata, _TIKTOK_URL)
        time.sleep(0.05)
        assert calls == 1
        release_extraction.set()
        results = [first.result(timeout=2), second.result(timeout=2)]

    assert [result.title for result in results] == ["TikTok video", "TikTok video"]
    assert calls == 1
    assert maximum_active == 1
    assert service._metadata_extraction_gates == {}


def _mix_watch_url(playlist_id: str, seed_id: str) -> str:
    return (
        f"https://www.youtube.com/watch?v={seed_id}"
        f"&list={playlist_id}&start_radio=1"
    )


def _mix_playlist_info(playlist_id: str, seed_id: str) -> dict:
    return {
        "_type": "playlist",
        "id": playlist_id,
        "title": "Seed Mix",
        "extractor": "youtube:tab",
        "extractor_key": "YoutubeTab",
        "entries": [
            {"id": seed_id, "url": seed_id, "title": "Seed video"},
            {"id": "nextvideo01", "url": "nextvideo01", "title": "Next video"},
        ],
    }


def _youtube_info(video_id: str, *, formats: list[dict] | None = None) -> dict:
    return {
        "id": video_id,
        "title": "Seed video",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "webpage_url": f"https://www.youtube.com/watch?v={video_id}",
        "formats": formats
        if formats is not None
        else [
            {
                "format_id": "18",
                "height": 360,
                "ext": "mp4",
                "vcodec": "avc1.42001E",
                "acodec": "mp4a.40.2",
                "filesize": 10_000,
            }
        ],
    }


def _tiktok_info() -> dict:
    return {
        "id": "1900000000000000001",
        "title": "TikTok video",
        "extractor": "TikTok",
        "extractor_key": "TikTok",
        "webpage_url": _TIKTOK_URL,
        "formats": [
            {
                "format_id": "download",
                "height": 720,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
                "filesize": 20_000,
            }
        ],
    }


def _post_playlist_info(service: MediaService, url: str):
    app = create_app()
    app.dependency_overrides[get_media_service] = lambda: service
    try:
        return TestClient(app).post("/media/playlist/info", json={"url": url})
    finally:
        app.dependency_overrides.clear()
