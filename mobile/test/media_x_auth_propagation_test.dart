import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/media_repository.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/services/device_file_service.dart';
import 'package:nexora/services/web_socket_service.dart';
import 'package:nexora/services/x_auth_storage.dart';

import 'x_auth_storage_test.dart';

class CapturingApiService implements ApiService {
  String? lastPath;
  Map<String, dynamic>? lastData;
  Map<String, dynamic>? lastHeaders;
  ApiException? errorToThrow;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) async {
    lastPath = path;
    lastData = data;
    lastHeaders = headers;

    if (errorToThrow != null) {
      throw errorToThrow!;
    }

    if (path.contains('/media/info')) {
      return {
        'success': true,
        'message': 'Success',
        'data': {
          'id': '123',
          'platform': 'twitter',
          'title': 'Test Media',
          'webpage_url': data?['url'] ?? '',
          'extractor': 'twitter',
          'extractor_key': 'Twitter',
          'video_qualities': [
            {'label': '720p', 'height': 720, 'extension': 'mp4'},
          ],
          'audio_options': [
            {'label': 'Original Audio', 'extension': 'mp3'},
          ],
        },
      };
    }

    if (path.contains('/media/download')) {
      return {
        'success': true,
        'message': 'Job created',
        'data': {
          'job_id': 'job-uuid-1234',
        },
      };
    }

    return {'success': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Media X-Session-ID Header Propagation Tests', () {
    late CapturingApiService capturingApiService;
    late MediaRepository mediaRepository;

    setUp(() {
      capturingApiService = CapturingApiService();
      mediaRepository = MediaRepository(
        capturingApiService,
        const WebSocketService(),
        const DeviceFileService(),
      );
    });

    test('MediaRepository.getMediaInfo passes extra headers to ApiService',
        () async {
      await mediaRepository.getMediaInfo(
        'https://x.com/user/status/123',
        headers: {'X-Session-ID': 'test_token_123'},
      );

      expect(capturingApiService.lastPath, '/media/info');
      expect(
          capturingApiService.lastHeaders, {'X-Session-ID': 'test_token_123'});
    });

    test('MediaRepository.createDownloadJob passes extra headers to ApiService',
        () async {
      await mediaRepository.createDownloadJob(
        mediaUrl: 'https://x.com/user/status/123',
        mediaType: MediaDownloadType.video,
        videoQuality:
            const VideoQuality(label: '720p', height: 720, extension: 'mp4'),
        headers: {'X-Session-ID': 'test_token_123'},
      );

      expect(capturingApiService.lastPath, '/media/download');
      expect(
          capturingApiService.lastHeaders, {'X-Session-ID': 'test_token_123'});
    });

    test(
        'MediaController attaches X-Session-ID when authenticated session exists for X URL',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'authenticated_session_999',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthProvider.overrideWith(() => FakeXAuthController(activeSession)),
        ],
      );

      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/12345');

      expect(capturingApiService.lastHeaders, isNotNull);
      expect(capturingApiService.lastHeaders?['X-Session-ID'],
          'authenticated_session_999');

      // Also works for twitter.com domain
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://twitter.com/user/status/67890');
      expect(capturingApiService.lastHeaders?['X-Session-ID'],
          'authenticated_session_999');
    });

    test(
        'MediaController omits X-Session-ID for non-X URLs even when authenticated',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'authenticated_session_999',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthProvider.overrideWith(() => FakeXAuthController(activeSession)),
        ],
      );

      // YouTube URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.youtube.com/watch?v=abc123');
      expect(capturingApiService.lastHeaders, isNull);

      // TikTok URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@user/video/123');
      expect(capturingApiService.lastHeaders, isNull);

      // Reddit URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.reddit.com/r/videos/comments/xyz/test');
      expect(capturingApiService.lastHeaders, isNull);

      // Instagram URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.instagram.com/reel/Cx12345/');
      expect(capturingApiService.lastHeaders, isNull);

      // Facebook URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.facebook.com/watch/?v=123456');
      expect(capturingApiService.lastHeaders, isNull);

      // Vimeo URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://vimeo.com/123456789');
      expect(capturingApiService.lastHeaders, isNull);

      // Arbitrary external URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://example.com/video.mp4');
      expect(capturingApiService.lastHeaders, isNull);
    });

    test('MediaController omits X-Session-ID when unauthenticated', () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          // Default XAuthController is unauthenticated
        ],
      );

      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/12345');
      expect(capturingApiService.lastHeaders, isNull);
    });

    test(
        'MediaController auto-invalidates X session and clears storage on backend 404 SESSION_NOT_FOUND',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'dead_session_after_restart',
        status: 'available',
        authenticated: true,
      );

      final fakeStorage = FakeSecureStorage();
      await fakeStorage.write(
        key: 'nexora.x_auth.session_id',
        value: 'dead_session_after_restart',
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthStorageProvider.overrideWithValue(XAuthStorage(fakeStorage)),
          xAuthProvider.overrideWith(() => MutableXAuthController(activeSession)),
        ],
      );

      // Verify initially authenticated
      expect(container.read(xAuthProvider).isAuthenticated, isTrue);
      expect(await fakeStorage.read(key: 'nexora.x_auth.session_id'),
          'dead_session_after_restart');

      // Simulate backend restart returning 404 SESSION_NOT_FOUND
      capturingApiService.errorToThrow =
          const ApiException('Session not found');

      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/12345');

      // State must transition to unauthenticated and local session cleared
      expect(container.read(xAuthProvider).isAuthenticated, isFalse);
      expect(container.read(xAuthProvider).isUnauthenticated, isTrue);
      expect(await fakeStorage.read(key: 'nexora.x_auth.session_id'), isNull);
    });

    test(
        'MediaController auto-transitions to expired state on backend 401 SESSION_EXPIRED',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'expired_session_123',
        status: 'available',
        authenticated: true,
      );

      final fakeStorage = FakeSecureStorage();
      await fakeStorage.write(
        key: 'nexora.x_auth.session_id',
        value: 'expired_session_123',
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthStorageProvider.overrideWithValue(XAuthStorage(fakeStorage)),
          xAuthProvider.overrideWith(() => MutableXAuthController(activeSession)),
        ],
      );

      // Simulate backend returning 401 SESSION_EXPIRED
      capturingApiService.errorToThrow =
          const ApiException('Session has expired');

      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/12345');

      // State must transition to expired and local storage cleared
      expect(container.read(xAuthProvider).isAuthenticated, isFalse);
      expect(container.read(xAuthProvider).isExpired, isTrue);
      expect(await fakeStorage.read(key: 'nexora.x_auth.session_id'), isNull);
    });
  });
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

class MutableXAuthController extends XAuthController {
  MutableXAuthController(this.initialSession);

  final XAuthSession? initialSession;

  @override
  XAuthState build() {
    if (initialSession != null) {
      return XAuthState.authenticated(initialSession!);
    }
    return const XAuthState.unauthenticated();
  }
}
