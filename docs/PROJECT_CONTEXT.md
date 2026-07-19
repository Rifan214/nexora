# Nexora Project Context

## Project Summary

- Nexora is a personal Flutter app with a separate FastAPI backend.
- V1 supports YouTube only.
- The app lets the user paste a URL, fetch metadata, choose an output, download the file, and track progress.
- Backend uses yt-dlp and FFmpeg, then stores the result temporarily for Flutter to download.
- No auth, no database, no admin panel, no website frontend.

## Goals

- Keep the codebase simple and maintainable.
- Optimize for fast AI-assisted development.
- Make platform support easy to extend later.
- Avoid overengineering and enterprise-style patterns.
- Prefer readability and clear boundaries.

## Scope

- In scope:
    - YouTube URL validation.
    - Metadata extraction.
    - Thumbnail, title, duration, and format display.
    - Video download.
    - Audio download.
    - Progress tracking.
    - Temporary storage.
    - Automatic cleanup.
    - Flutter file download from the backend.
- Out of scope for V1:
    - Authentication.
    - Accounts.
    - Database.
    - Admin UI.
    - Website frontend.
    - Multi-platform support beyond YouTube.

## Architecture Overview

- Flutter handles UI, user input, and file download.
- FastAPI handles API requests and job orchestration.
- A service layer owns download flow and job state.
- Platform adapters isolate YouTube logic from future platform logic.
- yt-dlp handles extraction and download.
- FFmpeg handles conversion when needed.
- Temporary storage holds completed files until Flutter downloads them.
- Cleanup removes files automatically after a short retention window.

## Technology Stack

- Mobile: Flutter for Android.
- Backend: FastAPI.
- Download engine: yt-dlp.
- Media processing: FFmpeg.
- Storage: local temporary filesystem on the backend.
- Deployment target: Koyeb for the backend.

## Folder Structure

- `flutter_app/` - Flutter mobile app.
- `backend/` - FastAPI backend.
- `backend/app/api/` - HTTP route definitions.
- `backend/app/services/` - Download and job orchestration.
- `backend/app/platforms/` - Platform adapters such as YouTube.
- `backend/app/core/` - Shared settings, constants, and helpers.
- `backend/app/storage/` - Temporary file management and cleanup.
- `backend/tests/` - Backend tests.
- `flutter_app/lib/` - Flutter source code.
- `flutter_app/lib/features/` - UI features and screens.
- `flutter_app/lib/services/` - API client and download logic.
- `flutter_app/test/` - Flutter tests.

## Development Workflow

- Define the behavior before writing code.
- Keep changes small and local.
- Add backend features behind a narrow service boundary.
- Add one platform adapter at a time.
- Validate core flows early with simple tests.
- Prefer polling-based progress if it keeps the implementation simpler.
- Treat temporary storage and cleanup as part of the core flow.

## Coding Principles

- Keep modules small and explicit.
- Prefer simple functions over deep abstractions.
- Use clear naming over clever shortcuts.
- Separate API, service, platform, and storage concerns.
- Avoid premature generalization.
- Make behavior easy for AI tools to read and modify.
- Keep V1 opinionated and narrow.
- Follow the project coding rules in `docs/CODING_RULES.md`.

## API Design Philosophy

- Keep the API minimal and job-based.
- Favor a small number of endpoints with clear responsibilities.
- Use explicit request and response payloads.
- Return stable job states for progress and errors.
- Keep download delivery simple and backend-controlled.
- Design now for future platform adapters, not for future SaaS scale.

## Error Handling Strategy

- Validate input early.
- Return clear, user-facing error messages.
- Distinguish validation, extraction, download, conversion, and storage errors.
- Mark jobs as failed with a reason that the Flutter app can display.
- Clean up partial files on failure.
- Keep retries optional and controlled.
- Log enough detail for debugging without exposing internals to the app.

## Deployment Strategy

- Deploy only the backend to Koyeb.
- Keep the backend stateless aside from temporary local files.
- Assume storage is disposable and may be lost on redeploy.
- Use environment variables for configuration.
- Keep runtime dependencies explicit, including yt-dlp and FFmpeg.
- Design the file retention flow so cleanup works even in short-lived environments.

## Future Expansion

- Add new platform adapters for TikTok, X, Instagram, Facebook, and Vimeo.
- Keep the adapter interface stable so new sources can plug in cleanly.
- Add better format selection if needed later.
- Consider stronger progress delivery only if polling becomes insufficient.
- Consider persistent storage only if the project grows beyond a simple personal tool.
- Keep the architecture lightweight unless real usage proves otherwise.
