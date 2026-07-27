# Nexora

Nexora is a Flutter and FastAPI application for downloading supported online media to a device. Version 1.0 supports YouTube video and MP3 downloads.

## Features

- Media metadata extraction
- Playback-friendly video quality selection
- Video and MP3 downloads
- Live download progress over WebSocket
- Download cancellation
- Automatic local file save and file opening
- Persistent local download history
- Automatic backend temporary-file cleanup
- Material 3 Flutter interface

## Tech Stack

- **Frontend:** Flutter, Dart, Material 3, Riverpod, Dio
- **Backend:** Python, FastAPI, Uvicorn, Pydantic Settings
- **Media:** yt-dlp and FFmpeg
- **Local storage:** SQLite, `path_provider`, `open_filex`

## Project Structure

```text
Nexora/
├── backend/       # FastAPI application, services, and tests
├── mobile/        # Flutter application
├── docs/          # Project documentation
└── README.md
```

## Requirements

- Python 3.12+
- Flutter SDK with Dart `>=3.6.0 <4.0.0`
- FFmpeg available on the backend machine's `PATH`
- Android emulator or device

## Getting Started

### Backend

```bash
cd backend
python -m venv .venv
```

Activate the environment, install dependencies, copy `.env.example` to `.env`, then start the API:

```bash
python -m pip install -e ".[dev]"
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Flutter

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=NEXORA_API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=NEXORA_WS_BASE_URL=ws://10.0.2.2:8000
```

Use the backend machine's LAN address instead of `10.0.2.2` when running on a physical device.

## Current Limitations

- YouTube is the only supported platform in version 1.0.
- One active download is supported at a time.
- Playlists are not supported.
- Active backend jobs do not resume after a backend restart.

## Roadmap

- Multiple concurrent downloads
- Download queue management
- Additional supported platforms
- Retry controls for failed downloads

## License

MIT License. Add a `LICENSE` file before distribution.
