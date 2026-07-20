# Nexora Project Structure

## Root Layout

- `backend/` - FastAPI application and server-side download orchestration.
- `mobile/` - Flutter Android client.
- `docs/` - Project context and architecture notes for future AI-assisted development.
- `docs/CODING_RULES.md` - Mandatory coding rules for all future implementation.

## Backend Structure

- `backend/app/` - Main backend application package.
- `backend/app/api/` - HTTP layer and request/response entry points.
- `backend/app/api/routes/` - Route modules grouped by responsibility.
- `backend/app/api/routes/health.py` - Root health and version endpoints.
- `backend/app/api/routes/media.py` - Media metadata and download-job creation endpoints.
- `backend/app/api/routes/jobs.py` - In-memory job lookup and deletion endpoints.
- `backend/app/api/routes/files.py` - Completed download file serving endpoint.
- `backend/app/api/routes/websockets.py` - WebSocket endpoint for real-time job progress.
- `backend/app/core/` - Shared configuration, constants, and low-level helpers.
- `backend/app/services/` - Download jobs, metadata flow, progress logic, and orchestration.
- `backend/app/services/job_manager.py` - In-memory job registry and lifecycle control.
- `backend/app/services/media_service.py` - yt-dlp metadata extraction and job creation orchestration.
- `backend/app/services/cleanup_service.py` - Lazy cleanup of expired jobs and temporary files.
- `backend/app/services/download_file_service.py` - Safe completed-file response creation.
- `backend/app/services/websocket_manager.py` - WebSocket connection registry and job update broadcaster.
- `backend/app/platforms/` - Platform abstraction layer for media sources.
- `backend/app/platforms/youtube/` - YouTube-specific implementation for V1.
- `backend/app/storage/` - Temporary files, cleanup, and file delivery helpers.
- `backend/app/models/` - Request, response, media, and job contracts used by the API.
- `backend/tests/` - Backend test coverage.
- `backend/scripts/` - Local utility scripts for development and maintenance.

## Mobile Structure

- `mobile/pubspec.yaml` - Flutter application metadata and package configuration.
- `mobile/analysis_options.yaml` - Dart analyzer and lint configuration.
- `mobile/lib/` - Flutter source root.
- `mobile/lib/core/` - Application-wide foundations such as config, networking, routing, and theme.
- `mobile/lib/core/config/` - Centralized runtime configuration.
- `mobile/lib/core/network/` - Reusable HTTP client setup.
- `mobile/lib/core/router/` - GoRouter configuration.
- `mobile/lib/core/theme/` - Material 3 light and dark themes.
- `mobile/lib/models/` - Data models for backend and app state.
- `mobile/lib/services/` - Low-level external integrations.
- `mobile/lib/repositories/` - Data access abstractions above services.
- `mobile/lib/providers/` - Riverpod providers.
- `mobile/lib/screens/` - Top-level app screens.
- `mobile/lib/widgets/` - Shared reusable widgets.
- `mobile/lib/utils/` - General-purpose helpers.
- `mobile/assets/images/` - Image assets such as placeholders and app visuals.
- `mobile/assets/icons/` - Icon assets.
- `mobile/test/` - Flutter tests.

## Naming Convention

- Use lowercase folder names with `kebab-case` only when needed.
- Use `snake_case` for Python files and modules.
- Use `PascalCase` for Dart classes, widgets, and data types.
- Use `camelCase` for Dart variables, methods, and parameters.
- Use versioned backend routes such as `v1` to keep future API changes isolated.
- Keep platform-specific code inside platform folders, not in shared services.
- Keep Flutter code in the foundation folders until feature modules are needed.

## Why This Structure Works

- It keeps the backend small and explicit.
- It isolates YouTube logic so future platforms can be added without rewriting the API.
- It separates API concerns from download orchestration and temporary storage.
- It keeps the Flutter app organized by feature, which is easier to maintain with AI-assisted edits.
- It avoids unnecessary abstraction while still leaving room for future expansion.
