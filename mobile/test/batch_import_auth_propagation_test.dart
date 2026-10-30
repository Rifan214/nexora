import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/batch_import.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/active_downloads_provider.dart';
import 'package:nexora/providers/batch_import_provider.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/media_repository.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/device_file_service.dart';
import 'package:nexora/services/web_socket_service.dart';

class RecordedRequest {
  const RecordedRequest({
    required this.path,
    required this.data,
    required this.headers,
  });

  final String path;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? headers;
}

class CapturingApiService implements ApiService {
  final List<RecordedRequest> recordedRequests = [];
  Map<String, ApiException> errorsByUrl = {};
  Map<String, ApiException> downloadErrorsByUrl = {};

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) async {
    recordedRequests.add(
      RecordedRequest(path: path, data: data, headers: headers),
    );

    final url = data?['url'] as String? ?? '';

    if (path.contains('/media/info')) {
      if (errorsByUrl.containsKey(url)) {
        throw errorsByUrl[url]!;
      }

      final detectedPlatform = url.contains('instagram.com')
          ? 'instagram'
          : url.contains('tiktok.com')
              ? 'tiktok'
              : (url.contains('x.com') || url.contains('twitter.com'))
                  ? 'twitter'
                  : 'youtube';

      return {
        'success': true,
        'message': 'Success',
        'data': {
          'id': 'media_${recordedRequests.length}',
          'platform': detectedPlatform,
          'title': 'Test Media for $url',
          'webpage_url': url,
          'extractor': detectedPlatform,
          'extractor_key': detectedPlatform,
          'video_qualities': [
            {'label': '1080p', 'height': 1080, 'extension': 'mp4'},
            {'label': '720p', 'height': 720, 'extension': 'mp4'},
          ],
          'audio_options': [
            {'label': 'Original Audio', 'extension': 'mp3'},
          ],
        },
      };
    }

    if (path.contains('/media/download')) {
      if (downloadErrorsByUrl.containsKey(url)) {
        throw downloadErrorsByUrl[url]!;
      }

      return {
        'success': true,
        'message': 'Job created',
        'data': {
          'job_id': 'job-uuid-${recordedRequests.length}',
        },
      };
    }

    return {'success': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInstagramAuthController extends InstagramAuthController {
  FakeInstagramAuthController(this._session);

  final InstagramAuthSession? _session;
  bool invalidated = false;
  bool wasExpired = false;
  String? invalidationReason;

  @override
  InstagramAuthState build() {
    final session = _session;
    if (session != null) {
      return InstagramAuthState.authenticated(session);
    }
    return const InstagramAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidated = true;
    wasExpired = isExpired;
    invalidationReason = reason;
    if (isExpired) {
      state = InstagramAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const InstagramAuthState.unauthenticated();
    }
  }
}

class FakeTikTokAuthController extends TikTokAuthController {
  FakeTikTokAuthController(this._session);

  final TikTokAuthSession? _session;
  bool invalidated = false;
  bool wasExpired = false;
  String? invalidationReason;

  @override
  TikTokAuthState build() {
    final session = _session;
    if (session != null) {
      return TikTokAuthState.authenticated(session);
    }
    return const TikTokAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidated = true;
    wasExpired = isExpired;
    invalidationReason = reason;
    if (isExpired) {
      state = TikTokAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const TikTokAuthState.unauthenticated();
    }
  }
}

class FakeXAuthController extends XAuthController {
  FakeXAuthController(this._session);

  final XAuthSession? _session;
  bool invalidated = false;
  bool wasExpired = false;
  String? invalidationReason;

  @override
  XAuthState build() {
    final session = _session;
    if (session != null) {
      return XAuthState.authenticated(session);
    }
    return const XAuthState.unauthenticated();
  }

  @override
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    invalidated = true;
    wasExpired = isExpired;
    invalidationReason = reason;
    if (isExpired) {
      state = XAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const XAuthState.unauthenticated();
    }
  }
}

void main() {
  group('BatchImportController Authentication Context Propagation Tests', () {
    late CapturingApiService capturingApiService;
    late MediaRepository mediaRepository;

    const activeInstagramSession = InstagramAuthSession(
      sessionId: 'test_ig_session_uuid_111',
      source: 'user_session',
      status: 'available',
      authenticated: true,
    );

    const activeTikTokSession = TikTokAuthSession(
      sessionId: 'test_tiktok_session_uuid_222',
      source: 'user_session',
      status: 'available',
      authenticated: true,
    );

    const activeXSession = XAuthSession(
      sessionId: 'test_x_session_uuid_333',
      source: 'user_session',
      status: 'available',
      authenticated: true,
    );

    setUp(() {
      capturingApiService = CapturingApiService();
      mediaRepository = MediaRepository(
        capturingApiService,
        const WebSocketService(),
        const DeviceFileService(),
      );
    });

    test(
        'Scenario 1: Authenticated Instagram metadata analysis receives Instagram-Session-ID',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(activeInstagramSession),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);
      await controller.analyzeUrls([
        'https://www.instagram.com/reel/DfCTfXHIReu/',
      ]);

      expect(capturingApiService.recordedRequests.length, 1);
      final request = capturingApiService.recordedRequests.first;
      expect(request.path, '/media/info');
      expect(request.headers,
          {'Instagram-Session-ID': 'test_ig_session_uuid_111'});

      final state = container.read(batchImportProvider);
      expect(state.items.length, 1);
      expect(state.items.first.status, BatchImportItemStatus.ready);
      expect(state.items.first.metadata?.title,
          'Test Media for https://www.instagram.com/reel/DfCTfXHIReu/');
    });

    test(
        'Scenario 2: Three authenticated Instagram URLs all receive Instagram-Session-ID and transition to ready',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(activeInstagramSession),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);
      final urls = [
        'https://www.instagram.com/reel/DfCTfXHIReu/',
        'https://www.instagram.com/reel/DfCTYRboDuS/',
        'https://www.instagram.com/reel/DfCTQNHo2zP/',
      ];

      await controller.analyzeUrls(urls);

      expect(capturingApiService.recordedRequests.length, 3);
      for (final req in capturingApiService.recordedRequests) {
        expect(req.path, '/media/info');
        expect(
            req.headers, {'Instagram-Session-ID': 'test_ig_session_uuid_111'});
      }

      final state = container.read(batchImportProvider);
      expect(state.items.length, 3);
      expect(state.analysisCompletedCount, 3);
      for (final item in state.items) {
        expect(item.status, BatchImportItemStatus.ready);
        expect(item.error, isNull);
        expect(item.metadata, isNotNull);
      }
    });

    test(
        'Scenario 3: Authenticated Instagram download submission propagates Instagram-Session-ID',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(activeInstagramSession),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);
      const url = 'https://www.instagram.com/reel/DfCTfXHIReu/';

      await controller.analyzeUrls([url]);

      final readyItem = container.read(batchImportProvider).items.first;
      expect(readyItem.status, BatchImportItemStatus.ready);

      final videoQuality = readyItem.metadata!.videoQualities.first;
      controller.selectVideoQuality(url, videoQuality);

      await controller.submitSelectedDownloads();

      expect(capturingApiService.recordedRequests.length, 2);
      final downloadReq = capturingApiService.recordedRequests[1];
      expect(downloadReq.path, '/media/download');
      expect(downloadReq.headers,
          {'Instagram-Session-ID': 'test_ig_session_uuid_111'});

      final trackedDownloads = container.read(activeDownloadsProvider);
      expect(trackedDownloads.length, 1);
      expect(trackedDownloads.first.jobId, 'job-uuid-2');
    });

    test(
        'Scenario 4: Mixed-platform batch routes correct headers to matching platform and omits for public platforms',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(activeInstagramSession),
          ),
          tikTokAuthProvider.overrideWith(
            () => FakeTikTokAuthController(activeTikTokSession),
          ),
          xAuthProvider.overrideWith(
            () => FakeXAuthController(activeXSession),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);
      final mixedUrls = [
        'https://www.instagram.com/reel/DfCTfXHIReu/',
        'https://www.tiktok.com/@creator/video/1234567890',
        'https://x.com/nexora_user/status/9876543210',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ];

      await controller.analyzeUrls(mixedUrls);

      expect(capturingApiService.recordedRequests.length, 4);

      // 1. Instagram request
      expect(capturingApiService.recordedRequests[0].headers, {
        'Instagram-Session-ID': 'test_ig_session_uuid_111',
      });
      expect(
          capturingApiService.recordedRequests[0].headers
              ?.containsKey('TikTok-Session-ID'),
          isFalse);
      expect(
          capturingApiService.recordedRequests[0].headers
              ?.containsKey('X-Session-ID'),
          isFalse);

      // 2. TikTok request
      expect(capturingApiService.recordedRequests[1].headers, {
        'TikTok-Session-ID': 'test_tiktok_session_uuid_222',
      });
      expect(
          capturingApiService.recordedRequests[1].headers
              ?.containsKey('Instagram-Session-ID'),
          isFalse);
      expect(
          capturingApiService.recordedRequests[1].headers
              ?.containsKey('X-Session-ID'),
          isFalse);

      // 3. X request
      expect(capturingApiService.recordedRequests[2].headers, {
        'X-Session-ID': 'test_x_session_uuid_333',
      });
      expect(
          capturingApiService.recordedRequests[2].headers
              ?.containsKey('Instagram-Session-ID'),
          isFalse);
      expect(
          capturingApiService.recordedRequests[2].headers
              ?.containsKey('TikTok-Session-ID'),
          isFalse);

      // 4. YouTube request (public, no auth headers)
      expect(capturingApiService.recordedRequests[3].headers, isNull);

      final state = container.read(batchImportProvider);
      expect(
          state.items
              .every((item) => item.status == BatchImportItemStatus.ready),
          isTrue);
    });

    test(
        'Scenario 5: Session invalidation during analysis marks only affected item and invokes handler',
        () async {
      final fakeInstagram = FakeInstagramAuthController(activeInstagramSession);
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(() => fakeInstagram),
        ],
      );

      const failingUrl = 'https://www.instagram.com/reel/DfCTfXHIReu/';
      const passingUrl = 'https://www.instagram.com/reel/DfCTYRboDuS/';

      capturingApiService.errorsByUrl[failingUrl] = const ApiException(
        'Instagram authentication session has expired',
      );

      final controller = container.read(batchImportProvider.notifier);
      await controller.analyzeUrls([failingUrl, passingUrl]);

      expect(fakeInstagram.invalidated, isTrue);
      expect(fakeInstagram.wasExpired, isTrue);

      final state = container.read(batchImportProvider);
      expect(state.items.length, 2);

      // Failing item
      expect(state.items[0].url, failingUrl);
      expect(state.items[0].status, BatchImportItemStatus.analysisFailed);
      expect(
          state.items[0].error, 'Instagram authentication session has expired');

      // Passing item was NOT interrupted by the first item's failure
      expect(state.items[1].url, passingUrl);
      expect(state.items[1].status, BatchImportItemStatus.ready);
      expect(state.items[1].error, isNull);
    });

    test(
        'Scenario 6: Session invalidation during download submission marks item as submissionFailed and continues',
        () async {
      final fakeInstagram = FakeInstagramAuthController(activeInstagramSession);
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(() => fakeInstagram),
        ],
      );

      const failingUrl = 'https://www.instagram.com/reel/DfCTfXHIReu/';
      const passingUrl = 'https://www.instagram.com/reel/DfCTYRboDuS/';

      final controller = container.read(batchImportProvider.notifier);
      await controller.analyzeUrls([failingUrl, passingUrl]);

      final stateAfterAnalysis = container.read(batchImportProvider);
      controller.selectVideoQuality(
        failingUrl,
        stateAfterAnalysis.items[0].metadata!.videoQualities.first,
      );
      controller.selectVideoQuality(
        passingUrl,
        stateAfterAnalysis.items[1].metadata!.videoQualities.first,
      );

      // Set download failure for the first item
      capturingApiService.downloadErrorsByUrl[failingUrl] = const ApiException(
        'Instagram authentication session has been revoked or is invalid',
      );

      await controller.submitSelectedDownloads();

      expect(fakeInstagram.invalidated, isTrue);
      expect(fakeInstagram.wasExpired, isFalse);

      final stateAfterSubmit = container.read(batchImportProvider);
      expect(stateAfterSubmit.items[0].status,
          BatchImportItemStatus.submissionFailed);
      expect(stateAfterSubmit.items[0].error, contains('invalid'));

      expect(stateAfterSubmit.items[1].status, BatchImportItemStatus.submitted);
      expect(stateAfterSubmit.items[1].error, isNull);
    });

    test(
        'Scenario 7: Guest/public Instagram without active session sends null headers',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(null),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);
      await controller.analyzeUrls([
        'https://www.instagram.com/reel/PublicReel123/',
      ]);

      expect(capturingApiService.recordedRequests.length, 1);
      expect(capturingApiService.recordedRequests.first.headers, isNull);

      final state = container.read(batchImportProvider);
      expect(state.items.first.status, BatchImportItemStatus.ready);
    });

    test(
        'Scenario 8: No regression in existing batch behavior (deduplication, quality selection, removal, clearBatch)',
        () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(
            () => FakeInstagramAuthController(null),
          ),
        ],
      );

      final controller = container.read(batchImportProvider.notifier);

      // Normalization and duplicate filtering
      await controller.analyzeUrls([
        '  https://www.instagram.com/reel/TestItem1/  ',
        'https://www.instagram.com/reel/TestItem1/',
        'https://www.instagram.com/reel/TestItem2/',
      ]);

      final state = container.read(batchImportProvider);
      expect(state.items.length, 2);

      // Selection: video quality
      controller.selectVideoQuality(
        state.items[0].url,
        state.items[0].metadata!.videoQualities.first,
      );
      expect(
        container
            .read(batchImportProvider)
            .items[0]
            .selectedVideoQuality
            ?.label,
        '1080p',
      );
      expect(
        container.read(batchImportProvider).items[0].mediaType,
        MediaDownloadType.video,
      );

      // Selection: audio option
      controller.selectAudioOption(
        state.items[0].url,
        state.items[0].metadata!.audioOptions.first,
      );
      expect(
        container.read(batchImportProvider).items[0].selectedAudioOptionLabel,
        'Original Audio',
      );
      expect(
        container.read(batchImportProvider).items[0].mediaType,
        MediaDownloadType.audio,
      );

      // Remove item
      controller.removeItem(state.items[1].url);
      expect(container.read(batchImportProvider).items.length, 1);

      // Clear batch
      controller.clearBatch();
      expect(container.read(batchImportProvider).items, isEmpty);
      expect(container.read(batchImportProvider).hasSession, isFalse);
    });
  });
}
