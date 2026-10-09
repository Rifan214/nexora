import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/media_repository.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/device_file_service.dart';
import 'package:nexora/services/web_socket_service.dart';

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
          'id': 'ig_123',
          'platform': 'instagram',
          'title': 'Test Instagram Media',
          'webpage_url': data?['url'] ?? '',
          'extractor': 'instagram',
          'extractor_key': 'Instagram',
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
          'job_id': 'job-ig-uuid-1234',
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

void main() {
  group('Media Instagram-Session-ID Header Propagation Tests', () {
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

    test('MediaRepository passes Instagram-Session-ID headers to ApiService', () async {
      await mediaRepository.getMediaInfo(
        'https://www.instagram.com/reel/C123456789/',
        headers: {'Instagram-Session-ID': 'test_ig_token_123'},
      );

      expect(capturingApiService.lastPath, '/media/info');
      expect(capturingApiService.lastHeaders, {'Instagram-Session-ID': 'test_ig_token_123'});
    });

    test('MediaController attaches Instagram-Session-ID when authenticated for Instagram URLs', () async {
      const activeSession = InstagramAuthSession(
        sessionId: 'authenticated_ig_session_888',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(() => FakeInstagramAuthController(activeSession)),
        ],
      );

      // Web Instagram URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.instagram.com/p/DdE2O2_hi2O/');

      expect(capturingApiService.lastHeaders, isNotNull);
      expect(capturingApiService.lastHeaders?['Instagram-Session-ID'], 'authenticated_ig_session_888');

      // Short / mobile Instagram URL
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://m.instagram.com/reel/DA245678/');
      expect(capturingApiService.lastHeaders?['Instagram-Session-ID'], 'authenticated_ig_session_888');
    });

    test('MediaController omits Instagram-Session-ID for non-Instagram URLs', () async {
      const activeSession = InstagramAuthSession(
        sessionId: 'authenticated_ig_session_888',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          instagramAuthProvider.overrideWith(() => FakeInstagramAuthController(activeSession)),
        ],
      );

      // YouTube
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.youtube.com/watch?v=abc123');
      expect(capturingApiService.lastHeaders, isNull);

      // TikTok
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@user/video/12345');
      expect(capturingApiService.lastHeaders, isNull);

      // X / Twitter
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/user/status/123456');
      expect(capturingApiService.lastHeaders, isNull);
    });

    test('Multi-platform isolation: strictly routes correct headers to matching platform', () async {
      const activeX = XAuthSession(
        sessionId: 'x_active_session_111',
        source: 'user_session',
        status: 'available',
        authenticated: true,
      );
      const activeTT = TikTokAuthSession(
        sessionId: 'tt_active_session_222',
        source: 'user_session',
        status: 'available',
        authenticated: true,
      );
      const activeIG = InstagramAuthSession(
        sessionId: 'ig_active_session_333',
        source: 'user_session',
        status: 'available',
        authenticated: true,
      );

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(capturingApiService),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          xAuthProvider.overrideWith(() => FakeXAuthController(activeX)),
          tikTokAuthProvider.overrideWith(() => FakeTikTokAuthController(activeTT)),
          instagramAuthProvider.overrideWith(() => FakeInstagramAuthController(activeIG)),
        ],
      );

      // 1. Request to Instagram URL must ONLY have Instagram-Session-ID
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.instagram.com/p/DdE2O2_hi2O/');
      expect(capturingApiService.lastHeaders, {'Instagram-Session-ID': 'ig_active_session_333'});
      expect(capturingApiService.lastHeaders?.containsKey('TikTok-Session-ID'), isFalse);
      expect(capturingApiService.lastHeaders?.containsKey('X-Session-ID'), isFalse);

      // 2. Request to TikTok URL must ONLY have TikTok-Session-ID
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.tiktok.com/@creator/video/999');
      expect(capturingApiService.lastHeaders, {'TikTok-Session-ID': 'tt_active_session_222'});
      expect(capturingApiService.lastHeaders?.containsKey('Instagram-Session-ID'), isFalse);

      // 3. Request to X URL must ONLY have X-Session-ID
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://x.com/elonmusk/status/12345');
      expect(capturingApiService.lastHeaders, {'X-Session-ID': 'x_active_session_111'});
      expect(capturingApiService.lastHeaders?.containsKey('Instagram-Session-ID'), isFalse);

      // 4. Request to YouTube must have NO platform auth headers
      await container
          .read(mediaProvider.notifier)
          .getMediaInfo('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(capturingApiService.lastHeaders, isNull);
    });
  });
}
