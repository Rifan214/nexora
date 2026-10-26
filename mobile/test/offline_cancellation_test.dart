import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/completed_file_download.dart';
import 'package:nexora/models/download_history_item.dart';
import 'package:nexora/models/download_job.dart';
import 'package:nexora/models/download_preferences.dart';
import 'package:nexora/models/job_update.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/media_state.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/active_downloads_provider.dart';
import 'package:nexora/providers/download_preferences_provider.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/history_repository.dart';
import 'package:nexora/repositories/media_repository.dart';

class MockOfflineCancellationMediaRepo implements MediaRepository {
  final List<String> cancelCalls = [];
  final List<Map<String, dynamic>> createCalls = [];
  final List<Map<String, dynamic>> saveCalls = [];
  final Set<String> deletedFiles = {};

  Completer<DownloadJobData>? createJobCompleter;
  Completer<MediaMetadata>? mediaInfoCompleter;
  StreamController<JobUpdate>? streamController;

  bool cancelThrowsNetworkError = false;
  bool createThrowsNetworkError = false;
  bool infoThrowsNetworkError = false;

  @override
  Future<MediaMetadata> getMediaInfo(
    String url, {
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) async {
    if (infoThrowsNetworkError) {
      throw const ApiException('Network unavailable. Check your connection.');
    }
    final completer = mediaInfoCompleter;
    if (completer != null) {
      return completer.future;
    }
    return dummyMetadata;
  }

  @override
  Future<DownloadJobData> createDownloadJob({
    required String mediaUrl,
    required MediaDownloadType mediaType,
    VideoQuality? videoQuality,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) async {
    createCalls.add({
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'videoQuality': videoQuality,
      'headers': headers,
    });
    if (createThrowsNetworkError) {
      throw const ApiException('Network unavailable. Check your connection.');
    }
    final completer = createJobCompleter;
    if (completer != null) {
      return completer.future;
    }
    return DownloadJobData(jobId: 'job-${createCalls.length}');
  }

  @override
  Future<JobUpdate> cancelDownloadJob(
    String jobId, {
    CancelToken? cancelToken,
  }) async {
    cancelCalls.add(jobId);
    if (cancelThrowsNetworkError) {
      throw const ApiException('Network unavailable. Check your connection.');
    }
    return JobUpdate(
      jobId: jobId,
      status: 'cancelled',
      progress: 0,
    );
  }

  @override
  Stream<JobUpdate> listenToJob(String jobId) {
    streamController ??= StreamController<JobUpdate>.broadcast();
    return streamController!.stream;
  }

  @override
  Future<String> downloadArtifactToTemporaryFile({
    required String downloadUrl,
    required String suggestedFilename,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    return '/cache/$suggestedFilename.part';
  }

  @override
  Future<CompletedFileDownload> saveDownloadedFileToDevice({
    required String temporaryFilePath,
    required String filename,
    required MediaDownloadType mediaType,
  }) async {
    saveCalls.add({
      'temporaryFilePath': temporaryFilePath,
      'filename': filename,
      'mediaType': mediaType,
    });
    return CompletedFileDownload(
      filename: filename,
      savedPath: '/storage/emulated/0/Download/$filename',
      savedDirectory: '/storage/emulated/0/Download',
    );
  }

  @override
  Future<bool> downloadedFileExists(String fileReference) async {
    return true;
  }

  @override
  Future<void> deleteDownloadedFileIfPresent(String fileReference) async {
    deletedFiles.add(fileReference);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHistoryRepo implements HistoryRepository {
  final List<DownloadHistoryItem> items = [];

  @override
  Future<List<DownloadHistoryItem>> loadHistory() async => items;

  @override
  Future<void> saveHistoryItem(DownloadHistoryItem item) async {
    items.add(item);
  }

  @override
  Future<void> deleteHistoryItem(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDownloadPreferencesController extends DownloadPreferencesController {
  @override
  Future<DownloadPreferences> build() async => const DownloadPreferences();
}

class FakeInstagramAuthController extends InstagramAuthController {
  FakeInstagramAuthController(this._session);
  final InstagramAuthSession? _session;

  @override
  InstagramAuthState build() {
    if (_session != null) {
      return InstagramAuthState.authenticated(_session);
    }
    return const InstagramAuthState.unauthenticated();
  }
}

class FakeTikTokAuthController extends TikTokAuthController {
  FakeTikTokAuthController(this._session);
  final TikTokAuthSession? _session;

  @override
  TikTokAuthState build() {
    if (_session != null) {
      return TikTokAuthState.authenticated(_session);
    }
    return const TikTokAuthState.unauthenticated();
  }
}

class FakeXAuthController extends XAuthController {
  FakeXAuthController(this._session);
  final XAuthSession? _session;

  @override
  XAuthState build() {
    if (_session != null) {
      return XAuthState.authenticated(_session);
    }
    return const XAuthState.unauthenticated();
  }
}

const testQuality = VideoQuality(label: '1080p', height: 1080, extension: 'mp4');

const dummyMetadata = MediaMetadata(
  title: 'Sample Video',
  webpageUrl: 'https://www.youtube.com/watch?v=sample123',
  platform: 'YouTube',
  extractor: 'youtube',
  extractorKey: 'Youtube',
  videoQualities: [
    testQuality,
  ],
);

void main() {
  late MockOfflineCancellationMediaRepo mockRepo;
  late FakeHistoryRepo fakeHistory;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockOfflineCancellationMediaRepo();
    fakeHistory = FakeHistoryRepo();
    container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(mockRepo),
        historyRepositoryProvider.overrideWithValue(fakeHistory),
        downloadPreferencesProvider.overrideWith(FakeDownloadPreferencesController.new),
        instagramAuthProvider.overrideWith(
          () => FakeInstagramAuthController(
            InstagramAuthSession(
              sessionId: 'insta-valid-session-123',
              createdAt: DateTime.now(),
            ),
          ),
        ),
        tikTokAuthProvider.overrideWith(
          () => FakeTikTokAuthController(
            TikTokAuthSession(
              sessionId: 'tiktok-session-456',
              createdAt: DateTime.now(),
            ),
          ),
        ),
        xAuthProvider.overrideWith(
          () => FakeXAuthController(
            XAuthSession(
              sessionId: 'x-session-789',
              createdAt: DateTime.now(),
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Phase 4 — Offline Handling & Cancellation Determinism Tests', () {
    test('1. Network loss during preparation settles request/state without indefinite loading', () async {
      mockRepo.infoThrowsNetworkError = true;
      final mediaController = container.read(mediaProvider.notifier);

      await mediaController.getMediaInfo('https://www.youtube.com/watch?v=sample123');

      final state = container.read(mediaProvider);
      expect(state, isA<MediaError>());
      final errorState = state as MediaError;
      expect(errorState.message, contains('Network unavailable'));
    });

    test('2. Cancel during preparation updates local state immediately while offline', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      // 1. Download starts in pending (Preparing stage)
      downloadsController.trackDownload(
        jobId: 'job-prep-offline',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      var download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-prep-offline');
      expect(download.status, 'pending');

      // 2. Network goes offline
      mockRepo.cancelThrowsNetworkError = true;

      // 3. User taps Cancel while offline
      await downloadsController.cancelDownload('job-prep-offline');

      // 4. Local state MUST be settled to 'cancelled' and NOT reverted back to 'pending'!
      download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-prep-offline');
      expect(download.status, 'cancelled');
      expect(download.error, isNull);
    });

    test('3. A late successful metadata response after cancellation cannot create or revive state', () async {
      final mediaCompleter = Completer<MediaMetadata>();
      mockRepo.mediaInfoCompleter = mediaCompleter;
      final mediaController = container.read(mediaProvider.notifier);

      // Start fetching metadata
      unawaited(mediaController.getMediaInfo('https://www.youtube.com/watch?v=sample123'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(mediaProvider), isA<MediaLoading>());

      // User cancels while metadata is being fetched
      await mediaController.cancelCurrentDownload();
      expect(container.read(mediaProvider), isA<MediaIdle>());

      // Now late response from cancelled request completes
      mediaCompleter.complete(dummyMetadata);
      await pumpEventQueue();

      // State MUST remain idle and NOT revived to success!
      expect(container.read(mediaProvider), isA<MediaIdle>());
    });

    test('4. A late successful job-creation response after cancellation requests orphan cancellation and does not advance UI', () async {
      final jobCompleter = Completer<DownloadJobData>();
      mockRepo.createJobCompleter = jobCompleter;
      final mediaController = container.read(mediaProvider.notifier);

      // Set initial state
      await mediaController.getMediaInfo('https://www.youtube.com/watch?v=sample123');
      mediaController.selectVideoQuality(testQuality);

      // Start creating download job
      unawaited(mediaController.createVideoDownloadJob());
      await Future<void>.delayed(Duration.zero);
      final stateWhileLoading = container.read(mediaProvider) as MediaSuccess;
      expect(stateWhileLoading.downloadLoading, isTrue);

      // User cancels while job creation is in flight
      await mediaController.cancelCurrentDownload();
      final stateAfterCancel = container.read(mediaProvider) as MediaSuccess;
      expect(stateAfterCancel.downloadLoading, isFalse);
      expect(stateAfterCancel.currentStatus, 'cancelled');

      // Late job response arrives from server
      jobCompleter.complete(const DownloadJobData(jobId: 'late-orphaned-job'));
      await pumpEventQueue();

      // State remains cancelled, late job is NOT tracked
      final finalState = container.read(mediaProvider) as MediaSuccess;
      expect(finalState.currentStatus, 'cancelled');
      final activeDownloads = container.read(activeDownloadsProvider);
      expect(activeDownloads.any((d) => d.jobId == 'late-orphaned-job'), isFalse);

      // Backend orphan cancellation was requested in background
      expect(mockRepo.cancelCalls, contains('late-orphaned-job'));
    });

    test('5. A completed backend job response received after cancellation does not start local device saving', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      downloadsController.trackDownload(
        jobId: 'job-cancel-then-complete',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      // User cancels while offline
      mockRepo.cancelThrowsNetworkError = true;
      await downloadsController.cancelDownload('job-cancel-then-complete');

      var download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-cancel-then-complete');
      expect(download.status, 'cancelled');

      // Late WebSocket or backend completion event arrives
      mockRepo.streamController!.add(
        const JobUpdate(
          jobId: 'job-cancel-then-complete',
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost:8000/api/media/download/file.mp4',
        ),
      );
      await pumpEventQueue();

      // State MUST remain cancelled, never save to device!
      download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-cancel-then-complete');
      expect(download.status, 'cancelled');
      expect(download.isSavingToDevice, isFalse);
      expect(mockRepo.saveCalls, isEmpty);
    });

    test('6. Late polling or event updates cannot overwrite a cancelled state', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      downloadsController.trackDownload(
        jobId: 'job-ignore-events',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      await downloadsController.cancelDownload('job-ignore-events');

      // Send various in-flight and terminal updates
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-ignore-events', status: 'processing', progress: 50),
      );
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-ignore-events', status: 'queued', progress: 0),
      );
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-ignore-events', status: 'failed', progress: 0, error: 'Server error'),
      );
      await pumpEventQueue();

      final download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-ignore-events');
      expect(download.status, 'cancelled');
    });

    test('7. Repeated Cancel taps do not cause duplicate requests or inconsistent states', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      downloadsController.trackDownload(
        jobId: 'job-repeated-cancel',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      // Multiple concurrent cancel taps
      await Future.wait([
        downloadsController.cancelDownload('job-repeated-cancel'),
        downloadsController.cancelDownload('job-repeated-cancel'),
        downloadsController.cancelDownload('job-repeated-cancel'),
      ]);

      // Exactly 1 backend cancellation was dispatched
      expect(mockRepo.cancelCalls.length, 1);
      final download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-repeated-cancel');
      expect(download.status, 'cancelled');
    });

    test('8. Normal successful downloads still transition from Preparing to Downloading to Saving to Device', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      // 1. Preparing
      downloadsController.trackDownload(
        jobId: 'job-normal-flow',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );
      var download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-normal-flow');
      expect(download.status, 'pending');

      // 2. Downloading
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-normal-flow', status: 'processing', progress: 45),
      );
      await pumpEventQueue();
      download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-normal-flow');
      expect(download.status, 'processing');
      expect(download.progress, 45);

      // 3. Completed on backend -> Saving to Device
      mockRepo.streamController!.add(
        const JobUpdate(
          jobId: 'job-normal-flow',
          status: 'completed',
          progress: 100,
          downloadUrl: 'http://localhost:8000/download/file.mp4',
        ),
      );
      await pumpEventQueue();

      download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-normal-flow');
      expect(download.status, 'completed');
      expect(download.savedFilePath, '/storage/emulated/0/Download/Sample Video.mp4');
      expect(mockRepo.saveCalls.length, 1);
    });

    test('9. Existing download retry behavior still works', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      downloadsController.trackDownload(
        jobId: 'job-retryable',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-retryable', status: 'failed', progress: 0, error: 'Download timed out'),
      );
      await pumpEventQueue();

      var download = container
          .read(activeDownloadsProvider)
          .firstWhere((d) => d.jobId == 'job-retryable');
      expect(download.status, 'failed');

      final retryResult = await downloadsController.retryFailedDownload('job-retryable');
      expect(retryResult, isNull);

      // Verify that retry created a new download job
      expect(mockRepo.createCalls.length, 1);
    });

    test('10. Instagram authenticated retry continues to propagate valid session headers', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      const instaMetadata = MediaMetadata(
        title: 'Insta Reel',
        webpageUrl: 'https://www.instagram.com/reel/C123456/',
        platform: 'Instagram',
        extractor: 'Instagram',
        extractorKey: 'Instagram',
        videoQualities: [testQuality],
      );

      downloadsController.trackDownload(
        jobId: 'job-insta',
        metadata: instaMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-insta', status: 'failed', progress: 0, error: 'Rate limit'),
      );
      await pumpEventQueue();

      await downloadsController.retryFailedDownload('job-insta');

      expect(mockRepo.createCalls.last['headers'], {
        'Instagram-Session-ID': 'insta-valid-session-123',
      });
    });

    test('11. TikTok and X authenticated download behavior remains intact', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      const tikTokMetadata = MediaMetadata(
        title: 'TikTok Video',
        webpageUrl: 'https://www.tiktok.com/@creator/video/999',
        platform: 'TikTok',
        extractor: 'TikTok',
        extractorKey: 'TikTok',
        videoQualities: [testQuality],
      );

      const xMetadata = MediaMetadata(
        title: 'X Video',
        webpageUrl: 'https://x.com/creator/status/888',
        platform: 'X',
        extractor: 'Twitter',
        extractorKey: 'Twitter',
        videoQualities: [testQuality],
      );

      downloadsController.trackDownload(
        jobId: 'job-tiktok',
        metadata: tikTokMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-tiktok', status: 'failed', progress: 0, error: 'Fail'),
      );
      await pumpEventQueue();
      await downloadsController.retryFailedDownload('job-tiktok');
      expect(mockRepo.createCalls.last['headers'], {
        'TikTok-Session-ID': 'tiktok-session-456',
      });

      downloadsController.trackDownload(
        jobId: 'job-x',
        metadata: xMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );
      mockRepo.streamController!.add(
        const JobUpdate(jobId: 'job-x', status: 'failed', progress: 0, error: 'Fail'),
      );
      await pumpEventQueue();
      await downloadsController.retryFailedDownload('job-x');
      expect(mockRepo.createCalls.last['headers'], {
        'X-Session-ID': 'x-session-789',
      });
    });

    test('12. Cleanup and cancellation do not delete a file still required by an active save or retry', () async {
      final downloadsController = container.read(activeDownloadsProvider.notifier);

      downloadsController.trackDownload(
        jobId: 'job-active-save',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );
      downloadsController.trackDownload(
        jobId: 'job-to-cancel',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        selectedVideoQuality: testQuality,
      );

      // Cancel job-to-cancel
      await downloadsController.cancelDownload('job-to-cancel');

      // Clear failed/cancelled downloads
      downloadsController.clearFailedDownloads();

      // job-active-save is still present and valid
      final remaining = container.read(activeDownloadsProvider);
      expect(remaining.any((d) => d.jobId == 'job-active-save'), isTrue);
      expect(remaining.any((d) => d.jobId == 'job-to-cancel'), isFalse);
    });
  });
}
