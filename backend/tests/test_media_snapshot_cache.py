from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

import app.services.media_service as media_service_module
from app.models.requests import MediaDownloadRequest
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.media_snapshot_cache import MediaSnapshotCache
from app.services.queue_manager import QueueManager
from app.utils.storage import get_temp_storage_dir


def _youtube_info() -> dict:
    return {
        "id": "youtube-snapshot",
        "title": "YouTube snapshot",
        "uploader": "Nexora Channel",
        "duration": 120,
        "thumbnail": "https://example.test/thumbnail.jpg",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "subtitles": {"en": []},
        "automatic_captions": {"en": []},
        "formats": [
            {
                "format_id": "18",
                "height": 720,
                "ext": "mp4",
                "vcodec": "avc1",
                "acodec": "mp4a",
            }
        ],
    }


def _tiktok_info() -> dict:
    return {
        "id": "tiktok-snapshot",
        "title": "TikTok snapshot",
        "extractor": "TikTok",
        "extractor_key": "TikTok",
        "formats": [
            {
                "format_id": "0",
                "height": 720,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
            }
        ],
    }


def test_cache_miss_returns_none() -> None:
    cache = MediaSnapshotCache()

    assert cache.get("https://example.test/missing") is None


def test_cache_hit_returns_a_defensive_snapshot_copy() -> None:
    cache = MediaSnapshotCache()
    url = "https://www.youtube.com/watch?v=cache-hit"
    cache.put(url, {"id": "youtube-cache-hit", "formats": []})

    snapshot = cache.get(url)

    assert snapshot is not None
    snapshot.extracted_info["id"] = "modified"
    assert cache.get(url).extracted_info["id"] == "youtube-cache-hit"


def test_cache_expires_entries_after_its_ttl() -> None:
    now = datetime(2026, 7, 30, tzinfo=UTC)
    cache = MediaSnapshotCache(
        ttl_seconds=300,
        now=lambda: now,
    )
    url = "https://www.youtube.com/watch?v=expiration"
    cache.put(url, {"id": "expired", "formats": []})

    now += timedelta(seconds=301)

    assert cache.get(url) is None
    assert len(cache) == 0


def test_cache_evicts_the_least_recently_used_entry_when_full() -> None:
    cache = MediaSnapshotCache(capacity=2)
    cache.put("https://example.test/one", {"id": "one", "formats": []})
    cache.put("https://example.test/two", {"id": "two", "formats": []})
    assert cache.get("https://example.test/one") is not None

    cache.put("https://example.test/three", {"id": "three", "formats": []})

    assert cache.get("https://example.test/one") is not None
    assert cache.get("https://example.test/two") is None
    assert cache.get("https://example.test/three") is not None


@pytest.mark.parametrize(
    ("url", "info"),
    [
        ("https://www.youtube.com/watch?v=snapshot", _youtube_info()),
        ("https://www.tiktok.com/@nexora/video/snapshot", _tiktok_info()),
    ],
)
def test_supported_platforms_reuse_analyzed_snapshots_for_download_jobs(
    monkeypatch: pytest.MonkeyPatch,
    url: str,
    info: dict,
) -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        queue_manager=queue_manager,
    )
    monkeypatch.setattr(service, "_extract_info", lambda _: info)
    service.get_metadata(url)
    monkeypatch.setattr(
        service,
        "_extract_info",
        lambda _: (_ for _ in ()).throw(AssertionError("unexpected re-extraction")),
    )
    threads: list[_FakeThread] = []

    def create_thread(*args, **kwargs):
        thread = _FakeThread(*args, **kwargs)
        threads.append(thread)
        return thread

    monkeypatch.setattr(media_service_module.threading, "Thread", create_thread)
    job = service.create_download_job(
        MediaDownloadRequest(url=url, media_type="video", quality_height=720)
    )

    assert job.title == info["title"]
    assert threads[0].args[4]["id"] == info["id"]


@pytest.mark.parametrize(
    ("platform", "media_type", "format_selector", "expected_refresh"),
    [
        ("youtube", "video", "18", True),
        ("youtube", "audio", "bestaudio/best", True),
        ("tiktok", "video", "0", False),
        ("tiktok", "audio", "bestaudio/best", False),
    ],
)
def test_snapshot_workers_refresh_youtube_transport_info_only(
    monkeypatch: pytest.MonkeyPatch,
    platform: str,
    media_type: str,
    format_selector: str,
    expected_refresh: bool,
) -> None:
    url = (
        "https://www.youtube.com/watch?v=transport"
        if platform == "youtube"
        else "https://www.tiktok.com/@nexora/video/transport"
    )
    cached_info = _youtube_info() if platform == "youtube" else _tiktok_info()
    cached_info["formats"][0]["url"] = "https://cached.example.test/media"
    if platform == "youtube":
        cached_info.update(
            {
                "requested_formats": [{"format_id": "18", "url": "https://expired.example.test/media"}],
                "requested_downloads": [{"filepath": "expired.mp4"}],
                "__real_download": True,
                "_filename": "expired.mp4",
                "filepath": "expired.mp4",
            }
        )
    refreshed_info = _youtube_info()
    refreshed_info["formats"][0]["url"] = "https://fresh.example.test/media"
    job_manager = JobManager()
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
    )
    _RefreshingYoutubeDL.instances = []
    _RefreshingYoutubeDL.refreshed_info = refreshed_info
    monkeypatch.setattr(media_service_module, "YoutubeDL", _RefreshingYoutubeDL)

    job = job_manager.create_job(
        media_url=url,
        platform=platform,
        format_id=format_selector,
        output_type=media_type,
    )
    extension = "mp3" if media_type == "audio" else "mp4"
    downloaded_file = get_temp_storage_dir() / f"{job.job_id}.{extension}"

    try:
        service._download_job_background(
            job.job_id,
            url,
            format_selector,
            media_type,
            cached_info,
        )

        downloader = _RefreshingYoutubeDL.instances[0]
        assert downloader.refresh_calls == ([(url, False, False)] if expected_refresh else [])
        expected_url = (
            "https://fresh.example.test/media"
            if expected_refresh
            else "https://cached.example.test/media"
        )
        assert downloader.processed_info["formats"][0]["url"] == expected_url
        assert downloader.processed_info["title"] == cached_info["title"]
        if media_type == "audio":
            assert downloader.options["postprocessors"] == [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "0",
                }
            ]
        if platform == "youtube":
            assert "requested_formats" not in downloader.processed_info
            assert "requested_downloads" not in downloader.processed_info
            assert downloader.processed_info["uploader"] == "Nexora Channel"
            assert downloader.processed_info["duration"] == 120
            assert downloader.processed_info["thumbnail"] == "https://example.test/thumbnail.jpg"
            assert downloader.processed_info["subtitles"] == {"en": []}
            assert downloader.processed_info["automatic_captions"] == {"en": []}
            assert "requested_formats" in cached_info
            assert "requested_downloads" in cached_info
    finally:
        downloaded_file.unlink(missing_ok=True)


class _FakeThread:
    def __init__(self, *, target, args, daemon, name) -> None:
        self.target = target
        self.args = args
        self.daemon = daemon
        self.name = name

    def start(self) -> None:
        return None


class _RefreshingYoutubeDL:
    instances: list["_RefreshingYoutubeDL"] = []
    refreshed_info: dict = {}

    def __init__(self, options: dict) -> None:
        self.options = options
        self.refresh_calls: list[tuple[str, bool, bool]] = []
        self.processed_info: dict | None = None
        self.instances.append(self)

    def __enter__(self) -> "_RefreshingYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, url: str, *, download: bool, process: bool = True) -> dict:
        self.refresh_calls.append((url, download, process))
        return self.refreshed_info

    def process_ie_result(self, info: dict, *, download: bool) -> dict:
        assert download is True
        self.processed_info = info
        extension = "mp3" if self.options.get("postprocessors") else "mp4"
        output_path = Path(self.options["outtmpl"].replace("%(ext)s", extension))
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(b"downloaded-media")
        return info
