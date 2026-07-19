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
- `backend/app/core/` - Shared configuration, constants, and low-level helpers.
- `backend/app/services/` - Download jobs, metadata flow, progress logic, and orchestration.
- `backend/app/services/job_manager.py` - In-memory job registry and lifecycle control.
- `backend/app/services/media_service.py` - yt-dlp metadata extraction and job creation orchestration.
- `backend/app/platforms/` - Platform abstraction layer for media sources.
- `backend/app/platforms/youtube/` - YouTube-specific implementation for V1.
- `backend/app/storage/` - Temporary files, cleanup, and file delivery helpers.
- `backend/app/models/` - Request, response, media, and job contracts used by the API.
- `backend/tests/` - Backend test coverage.
- `backend/scripts/` - Local utility scripts for development and maintenance.

## Mobile Structure

- `mobile/lib/` - Flutter source root.
- `mobile/lib/features/` - UI organized by feature instead of by technical layer.
- `mobile/lib/features/home/` - URL input, metadata display, and primary actions.
- `mobile/lib/features/download/` - Progress, job state, and file download handling.
- `mobile/lib/features/settings/` - App preferences and backend configuration if needed later.
- `mobile/lib/services/` - API client and download orchestration from the app side.
- `mobile/lib/models/` - Shared data models for the app.
- `mobile/lib/routing/` - Navigation definitions and route wiring.
- `mobile/lib/theme/` - Colors, typography, and design tokens.
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
- Keep feature-related Flutter code grouped by user-facing feature.

## Why This Structure Works

- It keeps the backend small and explicit.
- It isolates YouTube logic so future platforms can be added without rewriting the API.
- It separates API concerns from download orchestration and temporary storage.
- It keeps the Flutter app organized by feature, which is easier to maintain with AI-assisted edits.
- It avoids unnecessary abstraction while still leaving room for future expansion.
