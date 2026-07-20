from __future__ import annotations

import asyncio
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, status

from app.services.job_manager import JobManager, get_job_manager
from app.services.websocket_manager import (
    JobWebSocketConnection,
    WebSocketManager,
    get_websocket_manager,
)

router = APIRouter(tags=["websockets"])
logger = logging.getLogger(__name__)


@router.websocket("/ws/jobs/{job_id}")
async def job_updates_websocket(
    websocket: WebSocket,
    job_id: UUID,
    job_manager: JobManager = Depends(get_job_manager),
    websocket_manager: WebSocketManager = Depends(get_websocket_manager),
) -> None:
    job = job_manager.get_job(job_id)
    if job is None:
        await websocket.accept()
        logger.warning("WebSocket connection rejected job_id=%s reason=job_not_found", job_id)
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Job not found")
        return

    connection = await websocket_manager.connect(job_id=job_id, websocket=websocket)
    try:
        await websocket_manager.send_job_update(connection, job)
        await _relay_job_updates(connection, websocket_manager)
    except WebSocketDisconnect:
        pass
    except asyncio.CancelledError:
        pass
    except Exception:
        logger.exception("WebSocket connection failed job_id=%s", job_id)
    finally:
        websocket_manager.disconnect(connection)


async def _relay_job_updates(
    connection: JobWebSocketConnection,
    websocket_manager: WebSocketManager,
) -> None:
    while True:
        receive_task = asyncio.create_task(connection.websocket.receive())
        update_task = asyncio.create_task(connection.queue.get())
        done_tasks, pending_tasks = await asyncio.wait(
            {receive_task, update_task},
            return_when=asyncio.FIRST_COMPLETED,
        )

        for task in pending_tasks:
            task.cancel()
        if pending_tasks:
            await asyncio.gather(*pending_tasks, return_exceptions=True)

        if receive_task in done_tasks:
            message = receive_task.result()
            if message["type"] == "websocket.disconnect":
                return

        if update_task in done_tasks:
            await websocket_manager.send_message(connection, update_task.result())
