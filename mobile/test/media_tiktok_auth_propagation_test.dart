import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/media_repository.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/device_file_service.dart';
import 'package:nexora/services/tiktok_auth_storage.dart';
import 'package:nexora/services/web_socket_service.dart';

import 'tiktok_auth_storage_test.dart';

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
          'id': 'tt_123',
          'platform': 'tiktok',
          'title': 'Test TikTok Media',
          'webpage_url': data?['url'] ?? '',
          'extractor': 'tiktok',
          'extractor_key': 'TikTok',
          'video_qualities': [
            {'label': '1080p', 'height': 1080, 'extension': 'mp4'},
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
          'job_id': 'job-tt-uuid-1234',
        },
      };
    }

    return {'success': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class MutableTikTokAuthController extends TikTokAuthController {
  MutableTikTokAuthController(this.initialSession);

  final TikTokAuthSession? initialSession;

  @override
  TikTokAuthState build() {
    if (initialSession != null) {
      return TikTokAuthState.authenticated(initialSession!);
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

void main() {
  group('Media TikTok-Session-ID Header Propagation Tests', () {
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

    test('MediaRepository passes TikTok-Session-ID headers to ApiService', () async {
      await mediaRepository.getMediaInfo(
        'https://www.tiktok.com/@creator/video/12345',
        headers: {'TikTok-Session-ID': 'test_tt_token_123'},
      );

      expect(capturingApiService.lastPath, '/media/info');
      expect(capturingApiService.lastHeaders, {'TikTok-Session-ID': 'test_tt_token_123'});
    });

    test('MediaController attaches TikTok-Session-ID when authenticated for TikTok URLs', () async {
      const activeSession = TikTokAuthSession(
        sessionId: 'authenticated_tt_session_888',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          tikTokAuthProvider.overrideWith(() => FakeTikTokAuthController(activeSession)),
        ],
      );

      // Web TikTok URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@user/video/7123456789012345678');

      expect(capturingApiService.lastHeaders, isNotNull);
      expect(capturingApiService.lastHeaders?['TikTok-Session-ID'], 'authenticated_tt_session_888');

      // Short TikTok URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://vt.tiktok.com/ZS123456/');
      expect(capturingApiService.lastHeaders?['TikTok-Session-ID'], 'authenticated_tt_session_888');
    });

    test('MediaController omits TikTok-Session-ID for non-TikTok URLs', () async {
      const activeSession = TikTokAuthSession(
        sessionId: 'authenticated_tt_session_888',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          tikTokAuthProvider.overrideWith(() => FakeTikTokAuthController(activeSession)),
        ],
      );

      // YouTube
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.youtube.com/watch?v=abc123');
      expect(capturingApiService.lastHeaders, isNull);

      // X / Twitter
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/123456');
      expect(capturingApiService.lastHeaders, isNull);

      // Instagram
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.instagram.com/reel/Cx12345/');
      expect(capturingApiService.lastHeaders, isNull);

      // Spoofed domain
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://evil-tiktok.com/@user/video/12345');
      expect(capturingApiService.lastHeaders, isNull);
    });

    test('Isolation: When both X and TikTok are authenticated, headers do not cross-pollinate', () async {
      const xSession = XAuthSession(
        sessionId: 'x_active_session_111',
        status: 'available',
        authenticated: true,
      );
      const ttSession = TikTokAuthSession(
        sessionId: 'tt_active_session_222',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthProvider.overrideWith(() => FakeXAuthController(xSession)),
          tikTokAuthProvider.overrideWith(() => FakeTikTokAuthController(ttSession)),
        ],
      );

      // 1. Request to X/Twitter URL must ONLY have X-Session-ID
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/elonmusk/status/987654321');
      expect(capturingApiService.lastHeaders, {'X-Session-ID': 'x_active_session_111'});
      expect(capturingApiService.lastHeaders?.containsKey('TikTok-Session-ID'), isFalse);

      // 2. Request to TikTok URL must ONLY have TikTok-Session-ID
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@someuser/video/1122334455');
      expect(capturingApiService.lastHeaders, {'TikTok-Session-ID': 'tt_active_session_222'});
      expect(capturingApiService.lastHeaders?.containsKey('X-Session-ID'), isFalse);
    });

    test('MediaController auto-invalidates TikTok session on backend SESSION_NOT_FOUND', () async {
      const activeSession = TikTokAuthSession(
        sessionId: 'dead_tt_session',
        status: 'available',
        authenticated: true,
      );

      final fakeStorage = FakeSecureStorage();
      await fakeStorage.write(
        key: 'nexora.tiktok_auth.session_id',
        value: 'dead_tt_session',
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          tikTokAuthStorageProvider.overrideWithValue(TikTokAuthStorage(fakeStorage)),
          tikTokAuthProvider.overrideWith(() => MutableTikTokAuthController(activeSession)),
        ],
      );

      expect(container.read(tikTokAuthProvider).isAuthenticated, isTrue);

      // Simulate backend response
      capturingApiService.errorToThrow = const ApiException('TikTok authentication session not found');

      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@user/video/12345');

      expect(container.read(tikTokAuthProvider).isAuthenticated, isFalse);
      expect(container.read(tikTokAuthProvider).isUnauthenticated, isTrue);
      expect(await fakeStorage.read(key: 'nexora.tiktok_auth.session_id'), isNull);
    });
  });
}
