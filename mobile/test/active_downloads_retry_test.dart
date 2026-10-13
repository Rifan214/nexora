import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/completed_file_download.dart';
import 'package:nexora/models/download_history_item.dart';
import 'package:nexora/models/download_job.dart';
import 'package:nexora/models/job_update.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/active_downloads_provider.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/history_repository.dart';
import 'package:nexora/repositories/media_repository.dart';

class MockMediaRepository implements MediaRepository {
  final List<Map<String, dynamic>> createDownloadJobCalls = [];
  final List<Map<String, dynamic>> downloadArtifactCalls = [];
  final List<Map<String, dynamic>> saveFileCalls = [];
  final List<String> deletedFiles = [];
  final Set<String> existingFiles = {};

  DownloadJobData? nextDownloadJob;
  ApiException? createDownloadJobError;
  ApiException? downloadArtifactError;
  ApiException? saveFileError;

  StreamController<JobUpdate>? jobUpdatesController;

  @override
  Future<DownloadJobData> createDownloadJob({
    required String mediaUrl,
    required MediaDownloadType mediaType,
    VideoQuality? videoQuality,
    Map<String, dynamic>? headers,
  }) async {
    createDownloadJobCalls.add({
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'videoQuality': videoQuality,
      'headers': headers,
    });
    if (createDownloadJobError != null) {
      throw createDownloadJobError!;
    }
    return nextDownloadJob ??
        DownloadJobData(
          jobId: 'job-new-${createDownloadJobCalls.length}',
        );
  }

  @override
  Future<String> downloadArtifactToTemporaryFile({
    required String downloadUrl,
    required String suggestedFilename,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    downloadArtifactCalls.add({
      'downloadUrl': downloadUrl,
      'suggestedFilename': suggestedFilename,
    });
    if (downloadArtifactError != null) {
      throw downloadArtifactError!;
    }
    const tempPath = '/cache/nexora-temp-test.part';
    existingFiles.add(tempPath);
    return tempPath;
  }

  @override
  Future<CompletedFileDownload> saveDownloadedFileToDevice({
    required String temporaryFilePath,
    required String filename,
    required MediaDownloadType mediaType,
  }) async {
    saveFileCalls.add({
      'temporaryFilePath': temporaryFilePath,
      'filename': filename,
      'mediaType': mediaType,
    });
    if (saveFileError != null) {
      throw saveFileError!;
    }
    existingFiles.remove(temporaryFilePath);
    return CompletedFileDownload(
      filename: filename,
      savedPath: '/storage/emulated/0/Download/$filename',
      savedDirectory: '/storage/emulated/0/Download',
    );
  }

  @override
  Future<bool> downloadedFileExists(String fileReference) async {
    return existingFiles.contains(fileReference);
  }

  @override
  Future<void> deleteDownloadedFileIfPresent(String fileReference) async {
    deletedFiles.add(fileReference);
    existingFiles.remove(fileReference);
  }

  @override
  Stream<JobUpdate> listenToJob(String jobId) {
    jobUpdatesController ??= StreamController<JobUpdate>.broadcast();
    return jobUpdatesController!.stream;
  }

  @override
  Future<JobUpdate> cancelDownloadJob(String jobId) async {
    return JobUpdate(
      jobId: jobId,
      status: 'cancelled',
      progress: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHistoryRepository implements HistoryRepository {
  final List<DownloadHistoryItem> items = [];

  @override
  Future<List<DownloadHistoryItem>> loadHistory() async => items;

  @override
  Future<void> saveHistoryItem(DownloadHistoryItem item) async {
    items.add(item);
  }

  @override
  Future<void> deleteHistoryItem(String id) async {
    items.removeWhere((i) => i.id == id);
  }
}

class FakeInstagramAuthController extends InstagramAuthController {
  FakeInstagramAuthController(this._session);

  final InstagramAuthSession? _session;
  int invalidatedCallCount = 0;
  String? lastInvalidatedReason;

  @override
  InstagramAuthState build() {
    if (_session != null) {
      return InstagramAuthState.authenticated(_session);
    }
    return const InstagramAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidatedCallCount++;
    lastInvalidatedReason = reason;
    state = const InstagramAuthState.unauthenticated();
  }
}

class FakeTikTokAuthController extends TikTokAuthController {
  FakeTikTokAuthController(this._session);

  final TikTokAuthSession? _session;
  int invalidatedCallCount = 0;

  @override
  TikTokAuthState build() {
    if (_session != null) {
      return TikTokAuthState.authenticated(_session);
    }
    return const TikTokAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidatedCallCount++;
    state = const TikTokAuthState.unauthenticated();
  }
}

class FakeXAuthController extends XAuthController {
  FakeXAuthController(this._session);

  final XAuthSession? _session;
  int invalidatedCallCount = 0;

  @override
  XAuthState build() {
    if (_session != null) {
      return XAuthState.authenticated(_session);
    }
    return const XAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidatedCallCount++;
    state = const XAuthState.unauthenticated();
  }
}

MediaMetadata _createTestMetadata({
  required String url,
  String title = 'Test Title',
}) {
  return MediaMetadata(
    platform: 'instagram',
    title: title,
    webpageUrl: url,
    extractor: 'instagram',
    extractorKey: 'Instagram',
    videoQualities: const [
      VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
    ],
    audioOptions: const [
      AudioOption(label: 'Original Audio', extension: 'mp3'),
    ],
  );
}

void main() {
  group('Issue A — Saving to Device Retry', () {
    late MockMediaRepository mockRepo;
    late FakeHistoryRepository fakeHistory;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockMediaRepository();
      fakeHistory = FakeHistoryRepository();
      container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(mockRepo),
          historyRepositoryProvider.overrideWithValue(fakeHistory),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'A successful backend download followed by local save failure can retry save without creating a second backend download job',
      () async {
        const tempPath = '/cache/existing_artifact.part';
        mockRepo.existingFiles.add(tempPath);

        final notifier = container.read(activeDownloadsProvider.notifier);
        notifier.trackDownload(
          jobId: 'job-save-fail-1',
          metadata: _createTestMetadata(url: 'https://example.com/video'),
          mediaType: MediaDownloadType.video,
          selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
        );

        // Transition download to completed on backend, but failed in local saving stage:
        final current = container.read(activeDownloadsProvider).first;
        notifier.state = [
          current.copyWith(
            status: 'completed',
            progress: 100,
            downloadUrl: 'http://localhost/files/job-save-fail-1',
            temporaryFilePath: tempPath,
            fileDownloadError: 'Unable to save the downloaded file.',
          ),
        ];

        // Perform retry:
        final retryResult = await notifier.retryFailedDownload('job-save-fail-1');

        expect(retryResult, isNull);
        // Verify NO backend download job was created:
        expect(mockRepo.createDownloadJobCalls, isEmpty);
        // Verify save was called with the existing temporary file:
        expect(mockRepo.saveFileCalls.length, 1);
        expect(mockRepo.saveFileCalls.first['temporaryFilePath'], tempPath);

        // Verify state is now completely saved:
        final updated = container.read(activeDownloadsProvider).first;
        expect(updated.fileDownloadError, isNull);
        expect(updated.savedFilePath, '/storage/emulated/0/Download/Test Title.mp4');
      },
    );

    test('Retry saves an existing valid temporary artifact directly without re-downloading', () async {
      const tempPath = '/cache/valid_local.part';
      mockRepo.existingFiles.add(tempPath);

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-save-valid-1',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost/files/job-save-valid-1',
          temporaryFilePath: tempPath,
          fileDownloadError: 'Permission denied while saving.',
        ),
      ];

      await notifier.retryFailedDownload('job-save-valid-1');

      // downloadArtifactToTemporaryFile should NOT have been called:
      expect(mockRepo.downloadArtifactCalls, isEmpty);
      expect(mockRepo.saveFileCalls.length, 1);
      expect(mockRepo.saveFileCalls.first['temporaryFilePath'], tempPath);
    });

    test('Missing artifact follows intended recovery path: re-downloads from backend if missing locally', () async {
      // Local file does NOT exist in existingFiles:
      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-local-missing',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost/files/job-local-missing',
          temporaryFilePath: '/cache/no_longer_exists.part',
          fileDownloadError: 'temporary download file is missing',
        ),
      ];

      await notifier.retryFailedDownload('job-local-missing');

      // Re-downloaded from backend downloadUrl:
      expect(mockRepo.downloadArtifactCalls.length, 1);
      expect(mockRepo.downloadArtifactCalls.first['downloadUrl'], 'http://localhost/files/job-local-missing');
      // Then saved to device:
      expect(mockRepo.saveFileCalls.length, 1);
      final updated = container.read(activeDownloadsProvider).first;
      expect(updated.savedFilePath, isNotNull);
    });

    test('Missing artifact on backend triggers controlled re-download recovery', () async {
      // Both local and backend artifact missing:
      mockRepo.downloadArtifactError = const ApiException('Backend file not found or expired.');

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-backend-missing',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost/files/job-backend-missing',
          temporaryFilePath: null,
          fileDownloadError: 'temporary download file is missing',
        ),
      ];

      await notifier.retryFailedDownload('job-backend-missing');

      // Must have invoked createDownloadJob for controlled re-download recovery:
      expect(mockRepo.createDownloadJobCalls.length, 1);
      expect(mockRepo.createDownloadJobCalls.first['mediaUrl'], 'https://example.com/video');
      final updated = container.read(activeDownloadsProvider).first;
      expect(updated.status, 'pending');
      expect(updated.error, contains('missing and had to be re-downloaded'));
    });

    test('Cleanup does not delete an artifact while active save/retry still needs it', () async {
      const tempPath = '/cache/keep_for_retry.part';
      mockRepo.existingFiles.add(tempPath);
      mockRepo.saveFileError = const ApiException('Storage error');

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-save-fail-cleanup',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost/files/job-save-fail-cleanup',
          temporaryFilePath: tempPath,
          fileDownloadError: 'Temporary save error',
        ),
      ];

      await notifier.retryFailedDownload('job-save-fail-cleanup');

      // Since save failed, the artifact must NOT have been deleted from disk:
      expect(mockRepo.deletedFiles, isNot(contains(tempPath)));
      final failedState = container.read(activeDownloadsProvider).first;
      expect(failedState.temporaryFilePath, tempPath);

      // Now if user cancels the download, cleanup should delete it:
      notifier.cancelDownload('job-save-fail-cleanup');
      expect(mockRepo.deletedFiles, contains(tempPath));
    });

    test('clearFailedDownloads cleans up temporary files on disk', () {
      const tempPath = '/cache/failed_cleanup.part';
      mockRepo.existingFiles.add(tempPath);

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-failed-clean',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          temporaryFilePath: tempPath,
          error: 'Download error',
        ),
      ];

      notifier.clearFailedDownloads();

      expect(mockRepo.deletedFiles, contains(tempPath));
      expect(container.read(activeDownloadsProvider), isEmpty);
    });

    test('Repeated retry taps do not trigger duplicate concurrent saves or downloads', () async {
      const tempPath = '/cache/concurrent_test.part';
      mockRepo.existingFiles.add(tempPath);

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-concurrent-1',
        metadata: _createTestMetadata(url: 'https://example.com/video'),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost/files/job-concurrent-1',
          temporaryFilePath: tempPath,
          fileDownloadError: 'Save error',
        ),
      ];

      // Fire two retries concurrently:
      final future1 = notifier.retryFailedDownload('job-concurrent-1');
      final future2 = notifier.retryFailedDownload('job-concurrent-1');

      final results = await Future.wait([future1, future2]);

      // Exactly one save should have been triggered:
      expect(mockRepo.saveFileCalls.length, 1);
      // The other invocation should return the guard message:
      expect(results, contains('This download can no longer be retried.'));
    });
  });

  group('Issue B — Authenticated Media Retry', () {
    late MockMediaRepository mockRepo;
    late FakeHistoryRepository fakeHistory;
    late FakeInstagramAuthController fakeIgAuth;
    late FakeTikTokAuthController fakeTtAuth;
    late FakeXAuthController fakeXAuth;
    late ProviderContainer container;

    const igUrl = 'https://www.instagram.com/reel/DdE2O2_hi2O/?obrf=MXY1aHZvMXU4bWZpZQ==';
    const ttUrl = 'https://www.tiktok.com/@user/video/1234567890';
    const xUrl = 'https://x.com/user/status/1234567890';
    const genericUrl = 'https://youtube.com/watch?v=dQw4w9WgXcQ';

    setUp(() {
      mockRepo = MockMediaRepository();
      fakeHistory = FakeHistoryRepository();
      fakeIgAuth = FakeInstagramAuthController(
        InstagramAuthSession(
          sessionId: 'ig-valid-session-test',
          createdAt: DateTime.now(),
        ),
      );
      fakeTtAuth = FakeTikTokAuthController(
        TikTokAuthSession(
          sessionId: 'tt-valid-session-test',
          createdAt: DateTime.now(),
        ),
      );
      fakeXAuth = FakeXAuthController(
        XAuthSession(
          sessionId: 'x-valid-session-test',
          createdAt: DateTime.now(),
        ),
      );

      container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(mockRepo),
          historyRepositoryProvider.overrideWithValue(fakeHistory),
          instagramAuthProvider.overrideWith(() => fakeIgAuth),
          tikTokAuthProvider.overrideWith(() => fakeTtAuth),
          xAuthProvider.overrideWith(() => fakeXAuth),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Retry for an Instagram URL includes the valid current Instagram session header', () async {
      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-ig-fail',
        metadata: _createTestMetadata(url: igUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          error: 'Initial download failure',
        ),
      ];

      final result = await notifier.retryFailedDownload('job-ig-fail');

      expect(result, isNull);
      expect(mockRepo.createDownloadJobCalls.length, 1);
      final lastCall = mockRepo.createDownloadJobCalls.first;
      expect(lastCall['mediaUrl'], igUrl);
      expect(
        lastCall['headers'],
        {'Instagram-Session-ID': 'ig-valid-session-test'},
      );
    });

    test('Non-Instagram retry requests do not receive the Instagram authentication header', () async {
      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-generic-fail',
        metadata: _createTestMetadata(url: genericUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          error: 'Generic download failure',
        ),
      ];

      await notifier.retryFailedDownload('job-generic-fail');

      expect(mockRepo.createDownloadJobCalls.length, 1);
      final lastCall = mockRepo.createDownloadJobCalls.first;
      expect(lastCall['headers'], isNull);
    });

    test('Retry succeeds in a mocked login-required scenario when a valid session exists', () async {
      mockRepo.nextDownloadJob = const DownloadJobData(
        jobId: 'job-ig-authenticated-success',
      );

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-ig-login-req',
        metadata: _createTestMetadata(url: igUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          error: 'Login required',
        ),
      ];

      final result = await notifier.retryFailedDownload('job-ig-login-req');

      expect(result, isNull);
      final list = container.read(activeDownloadsProvider);
      expect(list.length, 1);
      expect(list.first.jobId, 'job-ig-authenticated-success');
      expect(list.first.status, 'pending');
    });

    test('Expired or invalid sessions produce appropriate recoverable authentication error', () async {
      mockRepo.createDownloadJobError = const ApiException('Instagram authentication session has expired.');

      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-ig-expired',
        metadata: _createTestMetadata(url: igUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      final current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          error: 'Initial error',
        ),
      ];

      final result = await notifier.retryFailedDownload('job-ig-expired');

      expect(result, 'Instagram authentication session has expired.');
      // Session invalidation should have been triggered on Instagram auth provider:
      expect(fakeIgAuth.invalidatedCallCount, 1);
      expect(fakeIgAuth.lastInvalidatedReason, 'Instagram authentication session has expired.');

      // State is restored from retrying flag:
      final updated = container.read(activeDownloadsProvider).first;
      expect(updated.isRetrying, false);
    });

    test('TikTok cookie authentication and existing platform download behavior remain unaffected', () async {
      // Test TikTok retry:
      final notifier = container.read(activeDownloadsProvider.notifier);
      notifier.trackDownload(
        jobId: 'job-tt-fail',
        metadata: _createTestMetadata(url: ttUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '1080p', height: 1080, extension: 'mp4'),
      );

      var current = container.read(activeDownloadsProvider).first;
      notifier.state = [
        current.copyWith(
          status: 'failed',
          error: 'Initial TikTok error',
        ),
      ];

      await notifier.retryFailedDownload('job-tt-fail');

      expect(mockRepo.createDownloadJobCalls.length, 1);
      expect(mockRepo.createDownloadJobCalls.first['headers'], {
        'TikTok-Session-ID': 'tt-valid-session-test',
      });

      // Test X retry:
      notifier.trackDownload(
        jobId: 'job-x-fail',
        metadata: _createTestMetadata(url: xUrl),
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: const VideoQuality(label: '720p', height: 720, extension: 'mp4'),
      );

      current = container.read(activeDownloadsProvider).last;
      notifier.state = [
        ...container.read(activeDownloadsProvider).sublist(0, container.read(activeDownloadsProvider).length - 1),
        current.copyWith(
          status: 'failed',
          error: 'Initial X error',
        ),
      ];

      await notifier.retryFailedDownload('job-x-fail');

      expect(mockRepo.createDownloadJobCalls.length, 2);
      expect(mockRepo.createDownloadJobCalls.last['headers'], {
        'X-Session-ID': 'x-valid-session-test',
      });
    });
  });
}
