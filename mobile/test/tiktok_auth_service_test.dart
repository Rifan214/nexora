import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/tiktok_auth_service.dart';

void main() {
  group('TikTokAuthService Tests', () {
    late Dio mockDio;
    late ApiService apiService;
    late TikTokAuthService authService;

    setUp(() {
      mockDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      apiService = ApiService(mockDio);
      authService = TikTokAuthService(apiService);
    });

    test('createSession successfully sends credentials and parses response', () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/tiktok/session' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'message': 'Ephemeral TikTok session created',
                    'data': {
                      'session_id': 'tt_8a014f1c47fad867f55bd200bc7aeedf',
                      'source': 'user_session',
                      'status': 'available',
                      'authenticated': true,
                      'created_at': '2026-10-09T03:00:00.000Z',
                      'expires_at': DateTime.now()
                          .toUtc()
                          .add(const Duration(hours: 1))
                          .toIso8601String(),
                      'expires_in_seconds': 3600,
                    },
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final session = await authService.createSession(
        sessionid: 'TEST_SESSIONID',
        sidTt: 'TEST_SID_TT',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'POST');
      expect(capturedOptions!.path, '/auth/tiktok/session');
      expect(capturedOptions!.data, {
        'sessionid': 'TEST_SESSIONID',
        'sid_tt': 'TEST_SID_TT',
      });

      expect(session.sessionId, 'tt_8a014f1c47fad867f55bd200bc7aeedf');
      expect(session.status, 'available');
      expect(session.authenticated, isTrue);
      expect(session.expiresInSeconds, 3600);
      expect(session.isAvailable, isTrue);
    });

    test('createSession without optional sid_tt omits it from request payload', () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/tiktok/session' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'message': 'Ephemeral TikTok session created',
                    'data': {
                      'session_id': 'tt_session_no_sid',
                      'source': 'user_session',
                      'status': 'available',
                      'authenticated': true,
                      'expires_in_seconds': 3600,
                    },
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final session = await authService.createSession(
        sessionid: 'TEST_SESSIONID_ONLY',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.data, {
        'sessionid': 'TEST_SESSIONID_ONLY',
      });
      expect(session.sessionId, 'tt_session_no_sid');
    });

    test('createSession rejects empty sessionid before making network call', () async {
      expect(
        () => authService.createSession(sessionid: ''),
        throwsA(isA<ApiException>()),
      );

      expect(
        () => authService.createSession(sessionid: '   '),
        throwsA(isA<ApiException>()),
      );
    });

    test('getSession retrieves status for existing session ID', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/auth/tiktok/session/test_tt_id' &&
                options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'session_id': 'test_tt_id',
                      'source': 'user_session',
                      'status': 'available',
                      'authenticated': true,
                      'expires_in_seconds': 1800,
                    },
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final session = await authService.getSession('test_tt_id');
      expect(session.sessionId, 'test_tt_id');
      expect(session.status, 'available');
      expect(session.authenticated, isTrue);
      expect(session.expiresInSeconds, 1800);
    });

    test('getSession rejects empty session ID', () async {
      expect(
        () => authService.getSession('   '),
        throwsA(isA<ApiException>()),
      );
    });

    test('deleteSession successfully sends DELETE request', () async {
      var deleteCalled = false;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/auth/tiktok/session/id_to_delete' &&
                options.method == 'DELETE') {
              deleteCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'message': 'Ephemeral TikTok session revoked',
                    'data': {
                      'session_id': 'id_to_delete',
                      'status': 'invalid',
                      'revoked': true,
                    },
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final result = await authService.deleteSession('id_to_delete');
      expect(result, isTrue);
      expect(deleteCalled, isTrue);
    });

    test('deleteSession treats 404 Not Found as success (already revoked)', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 404,
                  data: {
                    'success': false,
                    'error': {
                      'code': 'SESSION_NOT_FOUND',
                      'details': 'Session not found'
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final result = await authService.deleteSession('already_revoked_id');
      expect(result, isTrue);
    });
  });
}
