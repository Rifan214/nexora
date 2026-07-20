from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from functools import lru_cache
from threading import RLock
from typing import Any
from uuid import UUID

from fastapi import WebSocket

from app.models.job import DownloadJob, JobStatus

logger = logging.getLogger(__name__)

JobUpdateMessage = dict[str, Any]


@dataclass
class JobWebSocketConnection:
    job_id: UUID
    websocket: WebSocket
    queue: asyncio.Queue[JobUpdateMessage]
    loop: asyncio.AbstractEventLoop


class WebSocketManager:
    def __init__(self) -> None:
        self._connections: dict[UUID, list[JobWebSocketConnection]] = {}
        self._lock = RLock()

    async def connect(self, *, job_id: UUID, websocket: WebSocket) -> JobWebSocketConnection:
        await websocket.accept()
        connection = JobWebSocketConnection(
            job_id=job_id,
            websocket=websocket,
            queue=asyncio.Queue(),
            loop=asyncio.get_running_loop(),
        )

        with self._lock:
            self._connections.setdefault(job_id, []).append(connection)
            connection_count = len(self._connections[job_id])

        logger.info("WebSocket client connected job_id=%s active_connections=%s", job_id, connection_count)
        return connection

    def disconnect(self, connection: JobWebSocketConnection) -> None:
        with self._lock:
            connections = self._connections.get(connection.job_id, [])
            removed = any(item is connection for item in connections)
            remaining_connections = [item for item in connections if item is not connection]
            if remaining_connections:
                self._connections[connection.job_id] = remaining_connections
            else:
                self._connections.pop(connection.job_id, None)

        if removed:
            logger.info("WebSocket client disconnected job_id=%s", connection.job_id)

    def broadcast_job_update(self, job: DownloadJob) -> None:
        message = build_job_update_message(job)
        for connection in self._get_connections(job.job_id):
            self._enqueue_update(connection, message)

    async def send_job_update(self, connection: JobWebSocketConnection, job: DownloadJob) -> None:
        await self.send_message(connection, build_job_update_message(job))

    async def send_message(self, connection: JobWebSocketConnection, message: JobUpdateMessage) -> None:
        try:
            await connection.websocket.send_json(message)
            logger.info(
                "WebSocket message sent job_id=%s status=%s progress=%s",
                connection.job_id,
                message["status"],
                message["progress"],
            )
        except Exception:
            logger.exception("WebSocket broadcast failed job_id=%s", connection.job_id)
            self.disconnect(connection)
            raise

    def active_connection_count(self, job_id: UUID) -> int:
        with self._lock:
            return len(self._connections.get(job_id, []))

    def _get_connections(self, job_id: UUID) -> list[JobWebSocketConnection]:
        with self._lock:
            return list(self._connections.get(job_id, []))

    def _enqueue_update(self, connection: JobWebSocketConnection, message: JobUpdateMessage) -> None:
        if connection.loop.is_closed():
            logger.warning("WebSocket broadcast failed job_id=%s reason=closed_event_loop", connection.job_id)
            self.disconnect(connection)
            return

        try:
            connection.loop.call_soon_threadsafe(connection.queue.put_nowait, message)
        except Exception:
            logger.exception("WebSocket broadcast failed job_id=%s", connection.job_id)
            self.disconnect(connection)


def build_job_update_message(job: DownloadJob) -> JobUpdateMessage:
    return {
        "job_id": str(job.job_id),
        "status": job.status.value,
        "progress": 0 if job.status is JobStatus.failed else job.progress,
        "download_url": job.download_url,
        "error": job.error_message if job.status in {JobStatus.failed, JobStatus.expired} else None,
    }


@lru_cache
def get_websocket_manager() -> WebSocketManager:
    return WebSocketManager()
