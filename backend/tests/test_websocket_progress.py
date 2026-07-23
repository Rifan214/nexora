from __future__ import annotations

import asyncio
import time
from uuid import uuid4

import pytest
from fastapi import status
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import create_app
from app.models.job import JobStatus
from app.services.job_manager import JobManager, get_job_manager
from app.services.websocket_manager import (
    JobWebSocketConnection,
    WebSocketManager,
    get_websocket_manager,
)


def test_websocket_sends_initial_job_state() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=initial", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as websocket:
            message = websocket.receive_json()

            assert message == {
                "job_id": str(job.job_id),
                "status": JobStatus.pending.value,
                "progress": 0,
                "download_url": None,
                "error": None,
            }


def test_websocket_receives_progress_and_completion_updates() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    manager.add_update_listener(websocket_manager.broadcast_job_update)
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=complete", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as websocket:
            websocket.receive_json()

            manager.update_progress(job.job_id, 42)
            progress_message = websocket.receive_json()
            assert progress_message["status"] == JobStatus.processing.value
            assert progress_message["progress"] == 42
            assert progress_message["download_url"] is None
            assert progress_message["error"] is None

            manager.mark_completed(job.job_id)
            completed_message = websocket.receive_json()
            assert completed_message["status"] == JobStatus.completed.value
            assert completed_message["progress"] == 100
            assert completed_message["download_url"] == f"/files/{job.job_id}"
            assert completed_message["error"] is None


def test_websocket_receives_failed_update() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    manager.add_update_listener(websocket_manager.broadcast_job_update)
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=failed", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as websocket:
            websocket.receive_json()

            manager.update_progress(job.job_id, 57)
            websocket.receive_json()
            manager.mark_failed(job.job_id, error_message="Readable error message")
            failed_message = websocket.receive_json()

            assert failed_message == {
                "job_id": str(job.job_id),
                "status": JobStatus.failed.value,
                "progress": 0,
                "download_url": None,
                "error": "Readable error message",
            }


def test_websocket_sends_cancelled_update_then_closes() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    manager.add_update_listener(websocket_manager.broadcast_job_update)
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=cancelled", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as websocket:
            websocket.receive_json()

            manager.mark_cancelling(job.job_id)
            assert websocket.receive_json()["status"] == JobStatus.cancelling.value

            manager.mark_cancelled(job.job_id)
            cancelled_message = websocket.receive_json()
            assert cancelled_message == {
                "job_id": str(job.job_id),
                "status": JobStatus.cancelled.value,
                "progress": 0,
                "download_url": None,
                "error": None,
            }

            with pytest.raises(WebSocketDisconnect) as disconnect:
                websocket.receive_json()

            assert disconnect.value.code == status.WS_1000_NORMAL_CLOSURE

        assert _eventually(lambda: websocket_manager.active_connection_count(job.job_id) == 0)


def test_multiple_websocket_clients_receive_same_job_update() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    manager.add_update_listener(websocket_manager.broadcast_job_update)
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=multiple-clients", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as first_websocket:
            with client.websocket_connect(f"/ws/jobs/{job.job_id}") as second_websocket:
                first_websocket.receive_json()
                second_websocket.receive_json()

                manager.update_progress(job.job_id, 64)

                assert first_websocket.receive_json()["progress"] == 64
                assert second_websocket.receive_json()["progress"] == 64


def test_websocket_disconnect_removes_connection() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    job = manager.create_job(media_url="https://www.youtube.com/watch?v=disconnect", platform="youtube")
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with client.websocket_connect(f"/ws/jobs/{job.job_id}") as websocket:
            websocket.receive_json()
            assert websocket_manager.active_connection_count(job.job_id) == 1

        assert _eventually(lambda: websocket_manager.active_connection_count(job.job_id) == 0)


def test_websocket_missing_job_closes_gracefully() -> None:
    manager = JobManager()
    websocket_manager = WebSocketManager()
    app = _create_test_app(manager=manager, websocket_manager=websocket_manager)

    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect) as disconnect:
            with client.websocket_connect(f"/ws/jobs/{uuid4()}") as websocket:
                websocket.receive_json()

    assert disconnect.value.code == status.WS_1008_POLICY_VIOLATION


def test_websocket_broadcast_failure_removes_broken_connection() -> None:
    manager = WebSocketManager()
    job = JobManager().create_job(media_url="https://www.youtube.com/watch?v=broken-connection", platform="youtube")
    loop = asyncio.new_event_loop()
    loop.close()
    connection = JobWebSocketConnection(
        job_id=job.job_id,
        websocket=object(),
        queue=asyncio.Queue(),
        loop=loop,
    )
    manager._connections[job.job_id] = [connection]

    manager.broadcast_job_update(job)

    assert manager.active_connection_count(job.job_id) == 0


def _create_test_app(*, manager: JobManager, websocket_manager: WebSocketManager):
    app = create_app()
    app.dependency_overrides[get_job_manager] = lambda: manager
    app.dependency_overrides[get_websocket_manager] = lambda: websocket_manager
    return app


def _eventually(predicate) -> bool:
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return predicate()
