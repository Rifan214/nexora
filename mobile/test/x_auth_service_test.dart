import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/services/api_service.dart';
import 'package:nexora/services/x_auth_service.dart';

void main() {
  group('XAuthService Tests', () {
    late Dio mockDio;
    late ApiService apiService;
    late XAuthService authService;

    setUp(() {
      mockDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      apiService = ApiService(mockDio);
      authService = XAuthService(apiService);
    });

    test(
        'createSession successfully sends synthetic credentials and parses response',
        () async {
      RequestOptions? capturedOptions;

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            if (options.path == '/auth/x/session' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'message': 'Ephemeral X session created',
                    'data': {
                      'session_id': '8a014f1c47fad867f55bd200bc7aeedf',
                      'source': 'user_session',
                      'status': 'available',
                      'authenticated': true,
                      'created_at': '2026-09-25T03:00:00.000Z',
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
        authToken: 'TEST_AUTH_TOKEN',
        ct0: 'TEST_CT0',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'POST');
      expect(capturedOptions!.path, '/auth/x/session');
      expect(capturedOptions!.data, {
        'auth_token': 'TEST_AUTH_TOKEN',
        'ct0': 'TEST_CT0',
      });

      expect(session.sessionId, '8a014f1c47fad867f55bd200bc7aeedf');
      expect(session.status, 'available');
      expect(session.authenticated, isTrue);
      expect(session.expiresInSeconds, 3600);
      expect(session.isAvailable, isTrue);
    });

    test('createSession rejects empty credentials before making network call',
        () async {
      expect(
        () => authService.createSession(authToken: '', ct0: 'TEST_CT0'),
        throwsA(isA<ApiException>()),
      );

      expect(
        () =>
            authService.createSession(authToken: 'TEST_AUTH_TOKEN', ct0: '   '),
        throwsA(isA<ApiException>()),
      );
    });

    test('getSession retrieves status for existing session ID', () async {
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/auth/x/session/test_id' &&
                options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'session_id': 'test_id',
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

      final session = await authService.getSession('test_id');
      expect(session.sessionId, 'test_id');
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
            if (options.path == '/auth/x/session/id_to_delete' &&
                options.method == 'DELETE') {
              deleteCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'message': 'Ephemeral X session revoked',
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

    test('deleteSession treats 404 Not Found as success (already revoked)',
        () async {
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
