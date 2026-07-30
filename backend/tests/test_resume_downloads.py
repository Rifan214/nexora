from __future__ import annotations

import shutil
from pathlib import Path
from uuid import uuid4

import pytest
from yt_dlp.utils import DownloadError

import app.services.media_service as media_service_module
from app.models.resume_state import ResumeState
from app.services.download_process_manager import DownloadProcessManager
from app.services.job_manager import JobManager
from app.services.media_service import MediaService
from app.services.resume_state_manager import ResumeStateManager
from app.utils.storage import build_download_outtmpl, get_temp_storage_dir


@pytest.fixture
def resume_storage_dir() -> Path:
    storage_dir = get_temp_storage_dir() / f"resume-download-test-{uuid4()}"
    storage_dir.mkdir()
    try:
        yield storage_dir
    finally:
        shutil.rmtree(storage_dir, ignore_errors=True)


def _youtube_info() -> dict:
    return {
        "id": "resume-youtube",
        "title": "Resume test",
        "extractor": "youtube",
        "extractor_key": "Youtube",
        "formats": [{"format_id": "18", "height": 720, "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a"}],
    }


def _resume_state(job_id, *, source_url: str, output_template: str, temporary_path: Path) -> ResumeState:
    return ResumeState(
        job_id=job_id,
        source_url=source_url,
        output_path=str(temporary_path.with_suffix("")),
        temporary_file_path=str(temporary_path),
        downloaded_bytes=4,
        total_bytes=16,
        media_format="18",
        extractor="Youtube",
    )


def test_missing_partial_file_discards_stale_resume_state(resume_storage_dir: Path) -> None:
    source_url = "https://www.youtube.com/watch?v=resume-missing"
    job_id = uuid4()
    output_template = build_download_outtmpl(job_id, temp_dir=resume_storage_dir)
    state_manager = ResumeStateManager(storage_dir=resume_storage_dir / "resume")
    state_manager.save(
        _resume_state(
            job_id,
            source_url=source_url,
            output_template=output_template,
            temporary_path=resume_storage_dir / f"{job_id}.mp4.part",
        )
    )
    service = MediaService(resume_state_manager=state_manager)

    resume_state = service._prepare_resume_state(
        job_id=job_id,
        source_url=source_url,
        output_template=output_template,
        temp_dir=resume_storage_dir,
    )

    assert resume_state is None
    assert state_manager.exists(job_id) is False


def test_invalid_resume_state_discards_partial_artifacts(resume_storage_dir: Path) -> None:
    job_id = uuid4()
    output_template = build_download_outtmpl(job_id, temp_dir=resume_storage_dir)
    partial_file = resume_storage_dir / f"{job_id}.mp4.part"
    partial_file.write_bytes(b"partial")
    state_manager = ResumeStateManager(storage_dir=resume_storage_dir / "resume")
    state_manager.save(
        _resume_state(
            job_id,
            source_url="https://www.youtube.com/watch?v=wrong-source",
            output_template=output_template,
            temporary_path=partial_file,
        )
    )
    service = MediaService(resume_state_manager=state_manager)

    resume_state = service._prepare_resume_state(
        job_id=job_id,
        source_url="https://www.youtube.com/watch?v=expected-source",
        output_template=output_template,
        temp_dir=resume_storage_dir,
    )

    assert resume_state is None
    assert state_manager.exists(job_id) is False
    assert partial_file.exists() is False


@pytest.mark.parametrize("fail_resumed_attempt", [False, True])
def test_resumed_download_completes_or_falls_back_to_full_transfer(
    monkeypatch: pytest.MonkeyPatch,
    resume_storage_dir: Path,
    fail_resumed_attempt: bool,
) -> None:
    source_url = "https://www.youtube.com/watch?v=resume-worker"
    job_manager = JobManager()
    job = job_manager.create_job(media_url=source_url, platform="youtube", format_id="18", output_type="video")
    output_template = build_download_outtmpl(job.job_id, temp_dir=resume_storage_dir)
    partial_file = resume_storage_dir / f"{job.job_id}.mp4.part"
    partial_file.write_bytes(b"partial")
    state_manager = ResumeStateManager(storage_dir=resume_storage_dir / "resume")
    state_manager.save(
        _resume_state(
            job.job_id,
            source_url=source_url,
            output_template=output_template,
            temporary_path=partial_file,
        )
    )
    service = MediaService(
        process_manager=DownloadProcessManager(),
        job_manager=job_manager,
        resume_state_manager=state_manager,
    )
    _ResumeYoutubeDL.instances = []
    _ResumeYoutubeDL.fail_resumed_attempt = fail_resumed_attempt
    monkeypatch.setattr(media_service_module, "YoutubeDL", _ResumeYoutubeDL)
    monkeypatch.setattr(media_service_module, "get_temp_storage_dir", lambda: resume_storage_dir)

    service._download_job_background(job.job_id, source_url, "18", "video", _youtube_info())

    completed_job = job_manager.get_job(job.job_id)
    assert completed_job is not None
    assert completed_job.status.value == "completed"
    assert state_manager.exists(job.job_id) is False
    assert _ResumeYoutubeDL.instances[0].options["continuedl"] is True
    assert len(_ResumeYoutubeDL.instances) == (2 if fail_resumed_attempt else 1)
    if fail_resumed_attempt:
        assert _ResumeYoutubeDL.instances[1].options["continuedl"] is False
        assert partial_file.exists() is False


class _ResumeYoutubeDL:
    instances: list["_ResumeYoutubeDL"] = []
    fail_resumed_attempt = False

    def __init__(self, options: dict) -> None:
        self.options = options
        self.instances.append(self)

    def __enter__(self) -> "_ResumeYoutubeDL":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, _url: str, *, download: bool, process: bool = True) -> dict:
        assert download is False
        assert process is False
        return _youtube_info()

    def process_ie_result(self, info: dict, *, download: bool) -> dict:
        assert download is True
        if self.options["continuedl"] and self.fail_resumed_attempt:
            raise DownloadError("resume rejected")
        self.options["progress_hooks"][0](
            {
                "status": "downloading",
                "downloaded_bytes": 16,
                "total_bytes": 16,
                "filename": self.options["outtmpl"].replace("%(ext)s", "mp4"),
                "tmpfilename": self.options["outtmpl"].replace("%(ext)s", "mp4.part"),
            }
        )
        output_path = Path(self.options["outtmpl"].replace("%(ext)s", "mp4"))
        output_path.write_bytes(b"completed")
        return info
