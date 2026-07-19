# Nexora Implementation Roadmap

## Milestone 1: Project Bootstrap

- **Objective**
    - Create the backend and mobile project foundations with a working app shell and basic configuration.
- **Files affected**
    - `backend/` project metadata and environment files.
    - `backend/app/core/` for shared configuration structure.
    - `mobile/` project metadata and Flutter app entry files.
    - `mobile/lib/routing/` for initial navigation structure.
    - `mobile/lib/theme/` for initial visual tokens.
- **Expected output**
    - Backend starts successfully.
    - Mobile app launches to a blank shell screen.
    - Project folders and settings are in place.
- **Dependencies**
    - None.
- **Acceptance criteria**
    - Backend can be run locally without errors.
    - Mobile app opens in Android emulator or device.
    - Repository structure matches the documented layout.

## Milestone 2: Shared Contracts and Configuration

- **Objective**
    - Define the core request/response shapes, settings model, and shared naming conventions.
- **Files affected**
    - `backend/app/schemas/`.
    - `backend/app/core/`.
    - `mobile/lib/models/`.
    - `mobile/lib/services/`.
- **Expected output**
    - A stable set of data contracts for metadata, download jobs, progress, and errors.
    - Consistent configuration handling on both backend and mobile.
- **Dependencies**
    - Milestone 1.
- **Acceptance criteria**
    - Data shapes are documented and consistent across both apps.
    - Configuration values can be changed without touching business logic.
    - No business logic is mixed into contract definitions.

## Milestone 3: Mobile UI Shell and Navigation

- **Objective**
    - Build the main Flutter screens and navigation flow without backend integration.
- **Files affected**
    - `mobile/lib/features/home/`.
    - `mobile/lib/features/download/`.
    - `mobile/lib/features/settings/`.
    - `mobile/lib/routing/`.
    - `mobile/lib/theme/`.
- **Expected output**
    - App opens to a clear home screen.
    - Navigation between main screens works.
    - UI structure is ready for data binding.
- **Dependencies**
    - Milestone 1.
- **Acceptance criteria**
    - Screens render without runtime errors.
    - Routes are stable and reachable.
    - UI components follow the planned feature-based layout.

## Milestone 4: Backend Health and Metadata Foundation

- **Objective**
    - Add a minimal backend API surface for health checks and URL/metadata validation.
- **Files affected**
    - `backend/app/api/v1/`.
    - `backend/app/services/`.
    - `backend/app/platforms/youtube/`.
- **Expected output**
    - Backend can verify a YouTube URL and return basic metadata.
    - Health endpoint confirms the service is alive.
- **Dependencies**
    - Milestones 1 and 2.
- **Acceptance criteria**
    - A valid YouTube URL returns structured metadata.
    - Invalid input is rejected cleanly.
    - Backend remains runnable as a standalone service.

## Milestone 5: Mobile to Backend Metadata Flow

- **Objective**
    - Connect the mobile app to the backend for URL submission and metadata display.
- **Files affected**
    - `mobile/lib/features/home/`.
    - `mobile/lib/services/`.
    - `mobile/lib/models/`.
- **Expected output**
    - User can paste a URL in the app and see metadata from the backend.
    - Thumbnail, title, and duration render in the UI.
- **Dependencies**
    - Milestones 2, 3, and 4.
- **Acceptance criteria**
    - A valid URL triggers a backend request and visible result.
    - Error states are shown clearly in the app.
    - No download logic is required yet.

## Milestone 6: Download Job Lifecycle

- **Objective**
    - Implement the core backend job flow for starting, tracking, and completing a download.
- **Files affected**
    - `backend/app/services/`.
    - `backend/app/storage/`.
    - `backend/app/api/v1/`.
    - `backend/app/platforms/youtube/`.
- **Expected output**
    - Backend can create a download job, track progress, and mark completion or failure.
    - Temporary storage is used for completed files.
- **Dependencies**
    - Milestones 2 and 4.
- **Acceptance criteria**
    - A job can move through the expected lifecycle states.
    - Progress is queryable from the backend.
    - Completed files are written to temporary storage.

## Milestone 7: Mobile Download UX

- **Objective**
    - Let the user start a video or audio download and see progress in the app.
- **Files affected**
    - `mobile/lib/features/download/`.
    - `mobile/lib/services/`.
    - `mobile/lib/models/`.
- **Expected output**
    - The app can request a download job and display progress updates.
    - Video and audio download actions are available.
- **Dependencies**
    - Milestones 5 and 6.
- **Acceptance criteria**
    - A download can be started from the UI.
    - Progress updates appear in the app.
    - Success and failure states are visible to the user.

## Milestone 8: File Delivery and Cleanup

- **Objective**
    - Deliver the finished file to Flutter and remove temporary files safely.
- **Files affected**
    - `backend/app/storage/`.
    - `backend/app/services/`.
    - `backend/app/api/v1/`.
    - `mobile/lib/features/download/`.
- **Expected output**
    - Mobile can fetch the completed file from the backend.
    - Temporary files are cleaned automatically after use.
- **Dependencies**
    - Milestones 6 and 7.
- **Acceptance criteria**
    - A completed job can be downloaded successfully.
    - Temporary files do not accumulate indefinitely.
    - Cleanup does not break active downloads.

## Milestone 9: Reliability and Error Handling

- **Objective**
    - Harden the system with clear errors, retries, and predictable failure handling.
- **Files affected**
    - `backend/app/services/`.
    - `backend/app/core/`.
    - `backend/app/api/v1/`.
    - `mobile/lib/services/`.
    - `mobile/lib/features/download/`.
- **Expected output**
    - User-facing failures are clear.
    - Backend handles invalid URLs, extraction problems, and conversion failures cleanly.
- **Dependencies**
    - Milestones 6, 7, and 8.
- **Acceptance criteria**
    - Known failure cases produce stable error messages.
    - Partial files are removed on failure.
    - The app can recover from a failed job without restarting.

## Milestone 10: Deployment Readiness

- **Objective**
    - Prepare the backend for Koyeb deployment and verify the full end-to-end flow.
- **Files affected**
    - `backend/` deployment settings and environment files.
    - `backend/scripts/` for operational helpers.
    - `mobile/lib/services/` for deployment-time backend configuration.
- **Expected output**
    - Backend runs in a deployed environment.
    - Mobile can point to the deployed API and complete a real download.
- **Dependencies**
    - Milestones 1 through 9.
- **Acceptance criteria**
    - Backend can be deployed and reached remotely.
    - The mobile app completes a download against the deployed backend.
    - Temporary storage and cleanup still work in deployment.

## Milestone 11: Future Platform Extension Readiness

- **Objective**
    - Validate that the architecture can accept new platform adapters later without major refactoring.
- **Files affected**
    - `backend/app/platforms/`.
    - `backend/app/services/`.
    - `backend/app/api/v1/`.
- **Expected output**
    - The platform abstraction is stable and ready for future sources like TikTok or Instagram.
- **Dependencies**
    - Milestones 4, 6, and 9.
- **Acceptance criteria**
    - YouTube remains isolated behind the platform layer.
    - Adding a new adapter would not require rewriting the mobile app.
    - The backend API remains platform-neutral where possible.
