# Nexora Backend

FastAPI backend for Nexora.

## Media Quality API

`POST /media/info` returns metadata plus client-safe, playable quality options.
It does not expose raw yt-dlp stream IDs, codecs, or DASH stream details.

```json
{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
}
```

```json
{
  "success": true,
  "message": "Request successful",
  "data": {
    "title": "Example Video",
    "qualities": [
      {
        "label": "360p",
        "height": 360,
        "extension": "mp4",
        "estimated_filesize": 143582129
      },
      {
        "label": "1080p Full HD",
        "height": 1080,
        "extension": "mp4",
        "estimated_filesize": 456123456
      }
    ]
  }
}
```

Create a job by sending a quality height returned by that response:

```json
{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "quality_height": 1080
}
```

The backend validates the requested height again, chooses the best stream, and pairs adaptive video with the best available audio stream. A missing or changed quality returns the standardized `QUALITY_NOT_AVAILABLE` error; the backend never silently downgrades a request.

The previous `format_id` request field remains temporarily accepted for legacy clients but is deprecated. New clients must use `quality_height`.

Adaptive video/audio selectors require yt-dlp's normal merge support. Deployments must make FFmpeg available to yt-dlp for those pairs; this backend does not install or configure FFmpeg.

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
