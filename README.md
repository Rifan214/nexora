# Nexora

**Universal Media Downloader**

[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115%2B-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Nexora is a Flutter application and FastAPI backend for downloading supported online media to a device. It extracts media metadata, presents playback-friendly video quality choices or MP3 audio, tracks progress in real time, saves completed files locally, and keeps a local download history.

Version 1.0 currently supports YouTube URLs.

## Features

- Media metadata extraction for supported YouTube URLs
- Smart, playback-compatible video quality selection
- Video downloads with automatically paired audio where required
- MP3 audio-only downloads
- Live download progress over WebSocket
- True cancellation of active backend download and processing work
- Automatic local file save after backend completion
- Open completed files from the application
- Persistent local download history with optional downloaded-file deletion
- Configurable backend temporary-file cleanup
- Material 3 Flutter interface with light and dark themes

## Architecture

```text
Flutter
  |
  v
FastAPI
  |
  v
yt-dlp
  |
  v
FFmpeg
  |
  v
Local Storage
```

The Flutter client communicates with FastAPI through REST for metadata and job creation, then receives job updates through a WebSocket connection. The backend uses yt-dlp to retrieve media and FFmpeg when video/audio streams must be merged or audio is converted to MP3. The client saves completed files to device storage and persists history locally with SQLite.

## Tech Stack

### Backend

- Python 3.12+
- FastAPI
- Uvicorn
- Pydantic Settings
- yt-dlp
- FFmpeg

### Frontend

- Flutter and Dart
- Material 3
- Riverpod
- GoRouter

### Libraries

- Dio for HTTP communication
- `web_socket_channel` for real-time progress
- Freezed and `json_serializable` for models
- SQLite (`sqflite`) for local history
- `path_provider`, `permission_handler`, and `open_filex` for device file handling

## Repository Structure

```text
Nexora/
├── backend/              # FastAPI API, services, and tests
│   ├── app/
│   ├── storage/temp/     # Temporary backend media storage
│   └── .env.example
├── mobile/               # Flutter application
│   └── lib/
│       ├── core/
│       ├── models/
│       ├── providers/
│       ├── repositories/
│       ├── services/
│       ├── screens/
│       └── widgets/
└── docs/                 # Project documentation
```

## Requirements

- Python 3.12 or later
- Flutter SDK compatible with Dart `>=3.6.0 <4.0.0`
- FFmpeg available on the backend machine's `PATH`
- An Android emulator or device for the current device-download workflow

## Installation

### Backend

From the repository root:

```bash
cd backend
python -m venv .venv
```

Activate the environment:

```powershell
# Windows PowerShell
.venv\Scripts\Activate.ps1
```

```bash
# macOS or Linux
source .venv/bin/activate
```

Install the backend and development dependencies:

```bash
python -m pip install -e ".[dev]"
```

Create local configuration from the example:

```powershell
# Windows PowerShell
Copy-Item .env.example .env
```

```bash
# macOS or Linux
cp .env.example .env
```

Start the API:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The health endpoint is available at `http://localhost:8000/health` and interactive API documentation is available at `http://localhost:8000/docs`.

### Flutter

```bash
cd mobile
flutter pub get
```

Pass the reachable backend URLs when launching the app. For an Android emulator running on the same machine as the backend:

```bash
flutter run \
  --dart-define=NEXORA_API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=NEXORA_WS_BASE_URL=ws://10.0.2.2:8000
```

For a physical device, use the backend machine's LAN address instead of `10.0.2.2` and ensure the device can reach the backend port.

## Configuration

Backend configuration is loaded from `backend/.env`. Copy `backend/.env.example` to `backend/.env` and adjust values for the local environment. Do not commit `.env` files or place secrets in them.

| Variable | Purpose | Example default |
| --- | --- | --- |
| `NEXORA_APP_NAME` | API display name | `Nexora Backend` |
| `NEXORA_API_VERSION` | API version exposed by FastAPI | `0.2.0` |
| `NEXORA_ENV` | Runtime environment label | `development` |
| `NEXORA_DEBUG` | Enables backend debug logging | `true` |
| `NEXORA_CORS_ORIGINS` | Comma-separated allowed origins | `http://localhost:3000,http://localhost:4200` |
| `DOWNLOAD_EXPIRATION_MINUTES` | Maximum retention for an unclaimed completed file | `30` |
| `TEMP_FILE_RETENTION_MINUTES` | Grace period after the client retrieves a completed file | `15` |
| `FAILED_DOWNLOAD_RETENTION_MINUTES` | Retention for failed job records | `0` |
| `CLEANUP_INTERVAL_MINUTES` | Background cleanup interval | `5` |

The Flutter app receives its connection settings through `--dart-define` values:

- `NEXORA_API_BASE_URL`
- `NEXORA_WS_BASE_URL`
- `NEXORA_CONNECT_TIMEOUT_SECONDS`
- `NEXORA_RECEIVE_TIMEOUT_SECONDS`
- `NEXORA_SEND_TIMEOUT_SECONDS`

## Usage

```text
Paste URL
  |
  v
Analyze
  |
  v
Choose video quality or MP3
  |
  v
Download
  |
  v
Automatic save to device
  |
  v
History
```

1. Paste a supported YouTube URL into the Download screen.
2. Select **Analyze** to retrieve media metadata.
3. Choose a video quality or the MP3 option.
4. Start the download and follow the unified progress state.
5. When the local save completes, open the file or find it in History.

## Current Limitations

- Version 1.0 supports YouTube URLs only.
- Only one active download is supported at a time.
- Playlists are not supported.
- Active backend jobs are held in memory and do not resume after a backend restart.

## Roadmap

- Multiple concurrent downloads
- Download queue management
- Additional supported platforms
- Retry controls for failed downloads

## License

MIT License. A `LICENSE` file should be added before distribution.
