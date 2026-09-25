import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/repositories/media_repository.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/device_file_service.dart';
import 'package:nexora/services/web_socket_service.dart';

class CapturingApiService implements ApiService {
  String? lastPath;
  Map<String, dynamic>? lastData;
  Map<String, dynamic>? lastHeaders;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) async {
    lastPath = path;
    lastData = data;
    lastHeaders = headers;

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
