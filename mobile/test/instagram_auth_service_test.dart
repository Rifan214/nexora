import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/instagram_auth_service.dart';

void main() {
  group('InstagramAuthService Tests', () {
    late Dio mockDio;
    late ApiService apiService;
    late InstagramAuthService authService;

    setUp(() {
      mockDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      apiService = ApiService(mockDio);
      authService = InstagramAuthService(apiService);
    });

    test('createSession successfully sends credentials and parses response', () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/instagram/session' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'message': 'Ephemeral Instagram session created',
                    'data': {
                      'session_id': 'ig_8a014f1c47fad867f55bd200bc7aeedf',
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
        sessionid: 'TEST_SESSIONID%3A123',
        dsUserId: '12345678',
        csrftoken: 'test_csrf_token',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'POST');
      expect(capturedOptions!.path, '/auth/instagram/session');
      expect(capturedOptions!.data, {
        'sessionid': 'TEST_SESSIONID%3A123',
        'ds_user_id': '12345678',
        'csrftoken': 'test_csrf_token',
      });

      expect(session.sessionId, 'ig_8a014f1c47fad867f55bd200bc7aeedf');
      expect(session.status, 'available');
      expect(session.authenticated, isTrue);
      expect(session.expiresInSeconds, 3600);
      expect(session.isAvailable, isTrue);
    });

    test('createSession without optional companions omits them from request payload', () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/instagram/session' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'message': 'Ephemeral Instagram session created',
                    'data': {
                      'session_id': 'ig_session_no_companions',
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
        sessionid: 'TEST_ONLY_SESSIONID%3A999',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.data, {
        'sessionid': 'TEST_ONLY_SESSIONID%3A999',
      });
      expect(session.sessionId, 'ig_session_no_companions');
      expect(session.isAvailable, isTrue);
    });

    test('getSession returns null when session is not found (404)', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/auth/instagram/session/nonexistent_session_id') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 404,
                    data: {
                      'success': false,
                      'error': {
                        'code': 'INSTAGRAM_SESSION_NOT_FOUND',
                        'message': 'Instagram session not found or expired',
                      },
                    },
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final session = await authService.getSession('nonexistent_session_id');
      expect(session, isNull);
    });

    test('getSession retrieves valid active session', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/auth/instagram/session/valid_ig_id') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'session_id': 'valid_ig_id',
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

      final session = await authService.getSession('valid_ig_id');
      expect(session, isNotNull);
      expect(session!.sessionId, 'valid_ig_id');
      expect(session.isAvailable, isTrue);
    });

    test('deleteSession issues DELETE request successfully', () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/instagram/session/session_to_delete' &&
                options.method == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'message': 'Instagram session deleted successfully',
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      await authService.deleteSession('session_to_delete');
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'DELETE');
      expect(capturedOptions!.path, '/auth/instagram/session/session_to_delete');
    });

    test('deleteSession handles 404 gracefully without rethrowing', () async {
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
                    'error': {'code': 'NOT_FOUND'},
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      // Deleting already expired/deleted session should not crash the app
      await expectLater(
        authService.deleteSession('already_gone'),
        completes,
      );
    });

    test('createSession maps backend error response to ApiException', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 422,
                  data: {
                    'success': false,
                    'error': {
                      'code': 'VALIDATION_ERROR',
                      'message': 'Invalid sessionid format',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      expect(
        () => authService.createSession(sessionid: 'bad'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
