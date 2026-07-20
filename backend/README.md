# Nexora Backend

FastAPI backend for Nexora.

## Real-Time Job Progress

WebSocket progress updates are available at:

```text
/ws/jobs/{job_id}
```

The connection is accepted only for existing jobs. Missing jobs are closed gracefully with WebSocket close code `1008`.

Messages are JSON job snapshots:

```json
{
  "job_id": "00000000-0000-0000-0000-000000000000",
  "status": "processing",
  "progress": 42,
  "download_url": null,
  "error": null
}
```

REST polling with `GET /jobs/{job_id}` remains supported as a fallback.
