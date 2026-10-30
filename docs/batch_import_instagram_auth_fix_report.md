# Nexora — Batch Import Authentication Context Propagation Implementation Report

**Document Version:** 1.0.0  
**Date:** 2026-10-30  
**Status:** Completed  
**Final Verdict:** **PASS**  
**Implementer:** Senior Mobile & Backend Systems Debugging Specialist  

---

## 1. Confirmed Root Cause

As documented in [`docs/batch_import_instagram_auth_investigation.md`](file:///e:/CODING%20HYBRID/Nexora/docs/batch_import_instagram_auth_investigation.md), the failure of audience-restricted Instagram URLs during Batch Import was caused by the omission of platform authentication headers in [`mobile/lib/providers/batch_import_provider.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart):

1. **Context Drop in Flutter:** [`BatchImportController.analyzeUrls`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart#L29-L107) invoked `mediaRepositoryProvider.getMediaInfo(url)` without passing `headers: buildAuthHeadersForUrl(ref, url)`.
2. **Missing Headers in Network Payload:** `MediaRepository.getMediaInfo` sent `headers: null` to `POST /media/info`.
3. **Guest Resolution on Server:** FastAPI's `_resolve_instagram_session_context` treated the request as `auth_source="guest", auth_session_id=None`.
4. **Guest Extraction Failure & Aborted Fallback:** yt-dlp failed with `ERROR: [Instagram] <id>: This content isn't available to everyone: It can't be seen by certain audiences.`, mapped to `INSTAGRAM_EXTRACTION_UNAVAILABLE` (HTTP 502). Because `auth_source == "guest"`, the backend only checked for a server-side service account cookie (`NEXORA_INSTAGRAM_AUTH_COOKIE_FILE`). Since the user's credentials were in ephemeral mobile user session storage, `InstagramAuthManager.get_authenticated_provider` returned `None`, and the 502 error was returned to the client.
5. **Download Submission Context Drop:** Similarly, [`BatchImportController.submitSelectedDownloads`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart#L169-L248) invoked `createDownloadJob` without `headers`, which would have caused background download workers to execute as guest even if analysis had succeeded.

---

## 2. Modified Files

| File | Change Description |
|---|---|
| [`mobile/lib/providers/batch_import_provider.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart) | Added import of `platform_auth_headers.dart`. Propagated headers and session invalidation handling to `analyzeUrls()` and `submitSelectedDownloads()`. |
| [`mobile/test/batch_import_auth_propagation_test.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/test/batch_import_auth_propagation_test.dart) | Added focused unit/integration tests covering all 8 required regression scenarios. |
| [`docs/batch_import_instagram_auth_fix_report.md`](file:///e:/CODING%20HYBRID/Nexora/docs/batch_import_instagram_auth_fix_report.md) | Created comprehensive implementation report and test audit. |

*(No backend files were modified; existing FastAPI endpoints `/media/info` and `/media/download` already accept `Instagram-Session-ID`, `TikTok-Session-ID`, and `X-Session-ID`).*

---

## 3. Exact Changes Made to `analyzeUrls()`

In [`mobile/lib/providers/batch_import_provider.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart):

```dart
      try {
        final authHeaders = buildAuthHeadersForUrl(ref, url);
        final metadata = await ref.read(mediaRepositoryProvider).getMediaInfo(
              url,
              headers: authHeaders,
            );
        _updateItem(
          url,
          (item) => item.copyWith(
            status: BatchImportItemStatus.ready,
            metadata: metadata,
            error: null,
          ),
        );
        state = state.copyWith(currentTitle: metadata.title);
      } on ApiException catch (error) {
        await handleSessionInvalidationForUrl(
          ref,
          url,
          message: error.message,
        );
        _updateItem(
          url,
          (item) => item.copyWith(
            status: BatchImportItemStatus.analysisFailed,
            error: error.message,
          ),
        );
      }
```

- Resolved `authHeaders` for each item URL dynamically before calling `getMediaInfo`.
- Passed `headers: authHeaders` to `MediaRepository.getMediaInfo`.
- Preserved existing per-item state transitions and iteration continuity so that a failure on one item does not cancel analysis of remaining batch items.

---

## 4. Exact Changes Made to `submitSelectedDownloads()`

In [`mobile/lib/providers/batch_import_provider.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/batch_import_provider.dart):

```dart
      try {
        final authHeaders = buildAuthHeadersForUrl(ref, metadata.webpageUrl);
        final job = await repository.createDownloadJob(
          mediaUrl: metadata.webpageUrl,
          mediaType: mediaType,
          videoQuality: item.selectedVideoQuality,
          headers: authHeaders,
        );
        activeDownloads.trackDownload(
          jobId: job.jobId,
          metadata: metadata,
          mediaType: mediaType,
          selectedVideoQuality: item.selectedVideoQuality,
        );
        _updateItem(
          item.url,
          (current) => current.copyWith(
            status: BatchImportItemStatus.submitted,
            error: null,
          ),
        );
      } on ApiException catch (error) {
        await handleSessionInvalidationForUrl(
          ref,
          item.url,
          message: error.message,
        );
        _updateItem(
          item.url,
          (current) => current.copyWith(
            status: BatchImportItemStatus.submissionFailed,
            error: error.message,
          ),
        );
      }
```

- Resolved `authHeaders` using the canonical `metadata.webpageUrl`.
- Passed `headers: authHeaders` to `MediaRepository.createDownloadJob`.
- Maintained active download job tracking in [`ActiveDownloadsController`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/providers/active_downloads_provider.dart#L22-L81).

---

## 5. Session Invalidation Handling

Integrated [`handleSessionInvalidationForUrl(ref, url, message: error.message)`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/core/network/platform_auth_headers.dart#L61-L83) into both `analyzeUrls()` and `submitSelectedDownloads()`:

1. **Detection:** When `ApiException` is caught, the utility checks if the error message matches session invalidation markers (`session not found`, `session has expired`, `session is invalid`, or platform-specific session revocation messages).
2. **State Transition:** If an invalidation pattern is detected, the corresponding platform auth provider (`instagramAuthProvider`, `tikTokAuthProvider`, or `xAuthProvider`) transitions to `expired` or `unauthenticated`, clearing the cached session ID from secure storage.
3. **UI Isolation:** The failing batch item transitions to `analysisFailed` or `submissionFailed` with the server error message, while other non-dependent items continue processing cleanly.

---

## 6. Cross-Platform Authentication Compatibility

By reusing [`buildAuthHeadersForUrl(ref, url)`](file:///e:/CODING%20HYBRID/Nexora/mobile/lib/core/network/platform_auth_headers.dart#L41-L59), the batch import controller automatically achieves polymorphic authentication routing across all supported platforms:

- **Instagram URLs (`instagram.com`):** Injects `{'Instagram-Session-ID': ...}` if an active Instagram session exists.
- **TikTok URLs (`tiktok.com`, `vxtiktok.com`):** Injects `{'TikTok-Session-ID': ...}` if an active TikTok session exists.
- **X/Twitter URLs (`twitter.com`, `x.com`):** Injects `{'X-Session-ID': ...}` if an active X session exists.
- **Public/Unauthenticated Platforms (YouTube, etc.):** Returns `null`, ensuring no platform credentials or unrelated headers are ever sent to unsupported platforms.
- **No Cross-Pollination:** Strictly prevents an Instagram session token from being sent to TikTok or X endpoints.

---

## 7. Tests Added or Updated

Created dedicated test suite: [`mobile/test/batch_import_auth_propagation_test.dart`](file:///e:/CODING%20HYBRID/Nexora/mobile/test/batch_import_auth_propagation_test.dart)

| Scenario # | Description | Outcome |
|---|---|---|
| **Scenario 1** | Authenticated Instagram metadata analysis receives `Instagram-Session-ID` header. | **PASS** |
| **Scenario 2** | Three authenticated Instagram URLs all receive `Instagram-Session-ID` and transition to `ready`. | **PASS** |
| **Scenario 3** | Authenticated Instagram download submission propagates `Instagram-Session-ID` to `/media/download`. | **PASS** |
| **Scenario 4** | Mixed-platform batch routes correct headers to Instagram, TikTok, X, and omits for YouTube. | **PASS** |
| **Scenario 5** | Session invalidation during analysis marks only affected item as `analysisFailed` and continues remaining items. | **PASS** |
| **Scenario 6** | Session invalidation during download submission marks item as `submissionFailed` and continues other jobs. | **PASS** |
| **Scenario 7** | Guest/public Instagram without active session sends `null` headers without error. | **PASS** |
| **Scenario 8** | No regression in existing batch behavior (deduplication, quality selection, removal, clearBatch). | **PASS** |

---

## 8. Commands Executed and Actual Results

### 1. Code Formatting
```powershell
dart format mobile/lib/providers/batch_import_provider.dart
```
**Result:**
```text
Formatted mobile/lib/providers/batch_import_provider.dart
Formatted 1 file (1 changed) in 0.11 seconds.
```

### 2. Static Analysis
```powershell
Set-Location mobile; flutter analyze
```
**Result:**
```text
Analyzing mobile...                                             
No issues found! (ran in 27.7s)
```

### 3. Focused Batch Import Test Suite
```powershell
Set-Location mobile; flutter test test/batch_import_auth_propagation_test.dart
```
**Result:**
```text
00:00 +8: All tests passed!
```

### 4. Full Mobile Test Suite Regression Run
```powershell
Set-Location mobile; flutter test
```
**Result:**
```text
00:58 +362: All tests passed!
```

### 5. Backend Instagram Authentication Fallback Verification
```powershell
$env:PYTHONPATH="backend"; py -3.11 -m pytest backend/tests/test_instagram_authenticated_fallback.py -q
```
**Result:**
```text
4 passed, 1 warning in 8.01s
```

---

## 9. Security and Session-Isolation Review

- **Credential Redaction:** No cookie values, Netscape tokens, or session IDs are logged, printed, or exposed in error messages or widget trees.
- **Session ID Propagation Only:** Only the opaque UUID session identifier (`Instagram-Session-ID`) is transmitted over HTTPS headers; raw cookies remain secure inside the backend's RAM-backed `EphemeralInstagramUserSessionStore`.
- **Platform Separation:** Strict domain checking ensures platform session IDs are never leaked to foreign hosts or public media extractors.
- **Least Privilege:** Public content continues to be processed in guest mode without acquiring cookie leases or consuming session rate limits.

---

## 10. Remaining Limitations

None. The fix achieves full authentication parity between Individual Import and Batch Import across Instagram, TikTok, and X/Twitter.

---

## 11. Final Verdict

**PASS** — Implementation is complete, fully verified, adheres strictly to project architecture, and passes all 362 mobile regression tests plus backend regression tests without error.

