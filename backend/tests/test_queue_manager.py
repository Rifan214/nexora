from __future__ import annotations

from uuid import UUID

from app.models.job import JobStatus
from app.services.job_manager import JobManager
from app.services.queue_manager import QueueManager


def test_queue_starts_first_job_and_marks_following_jobs_queued() -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    started: list[UUID] = []

    first = _create_job(job_manager, "first")
    second = _create_job(job_manager, "second")

    queue_manager.enqueue(first.job_id, starter=lambda: started.append(first.job_id))
    queue_manager.enqueue(second.job_id, starter=lambda: started.append(second.job_id))

    assert started == [first.job_id]
    assert queue_manager.has_active_download()
    assert queue_manager.peek() == second.job_id
    assert queue_manager.queue_depth() == 1
    assert job_manager.get_job(second.job_id).status is JobStatus.queued


def test_queue_preserves_fifo_order_and_transitions_queued_job_to_processing() -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    started: list[UUID] = []

    first = _create_job(job_manager, "first")
    second = _create_job(job_manager, "second")
    third = _create_job(job_manager, "third")

    def start(job_id: UUID) -> None:
        started.append(job_id)
        job_manager.update_progress(job_id, 0)

    queue_manager.enqueue(first.job_id, starter=lambda: start(first.job_id))
    queue_manager.enqueue(second.job_id, starter=lambda: start(second.job_id))
    queue_manager.enqueue(third.job_id, starter=lambda: start(third.job_id))

    assert job_manager.get_job(second.job_id).status is JobStatus.queued
    assert job_manager.get_job(third.job_id).status is JobStatus.queued

    job_manager.mark_completed(first.job_id)

    assert started == [first.job_id, second.job_id]
    assert job_manager.get_job(second.job_id).status is JobStatus.processing
    assert job_manager.get_job(third.job_id).status is JobStatus.queued

    job_manager.mark_completed(second.job_id)

    assert started == [first.job_id, second.job_id, third.job_id]
    assert job_manager.get_job(third.job_id).status is JobStatus.processing


def test_failed_active_job_starts_the_next_queued_job() -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    started: list[UUID] = []

    first = _create_job(job_manager, "first")
    second = _create_job(job_manager, "second")

    queue_manager.enqueue(first.job_id, starter=lambda: started.append(first.job_id))
    queue_manager.enqueue(second.job_id, starter=lambda: started.append(second.job_id))
    job_manager.update_progress(first.job_id, 12)

    job_manager.mark_failed(first.job_id, error_message="Download failed")

    assert started == [first.job_id, second.job_id]
    assert queue_manager.has_active_download()


def test_cancelling_a_queued_job_removes_it_without_affecting_the_active_job() -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    started: list[UUID] = []

    first = _create_job(job_manager, "first")
    queued = _create_job(job_manager, "queued")

    queue_manager.enqueue(first.job_id, starter=lambda: started.append(first.job_id))
    queue_manager.enqueue(queued.job_id, starter=lambda: started.append(queued.job_id))

    job_manager.mark_cancelling(queued.job_id)
    job_manager.mark_cancelled(queued.job_id)

    assert job_manager.get_job(queued.job_id).status is JobStatus.cancelled
    assert queue_manager.queue_depth() == 0
    assert queue_manager.has_active_download()

    job_manager.mark_completed(first.job_id)

    assert started == [first.job_id]
    assert not queue_manager.has_active_download()


def test_cancelled_active_job_starts_the_next_queued_job() -> None:
    job_manager = JobManager()
    queue_manager = QueueManager(job_manager=job_manager)
    started: list[UUID] = []

    first = _create_job(job_manager, "first")
    second = _create_job(job_manager, "second")

    queue_manager.enqueue(first.job_id, starter=lambda: started.append(first.job_id))
    queue_manager.enqueue(second.job_id, starter=lambda: started.append(second.job_id))

    job_manager.mark_cancelling(first.job_id)
    job_manager.mark_cancelled(first.job_id)

    assert started == [first.job_id, second.job_id]
    assert queue_manager.has_active_download()


def _create_job(job_manager: JobManager, suffix: str):
    return job_manager.create_job(
        media_url=f"https://www.youtube.com/watch?v={suffix}",
        platform="youtube",
    )

