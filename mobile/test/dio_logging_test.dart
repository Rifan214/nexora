import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/dio_client.dart';

class MockHttpAdapter implements HttpClientAdapter {
  MockHttpAdapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SanitizedLogInterceptor Security Tests', () {
    const syntheticAuthToken = 'SYNTHETIC_AUTH_TOKEN_SECRET_123';
    const syntheticCt0 = 'SYNTHETIC_CT0_SECRET_456';
    const syntheticSessionId = '0123456789abcdef0123456789abcdef';

    test('suppresses raw credentials when POSTing to /auth/x/session',
        () async {
      final logs = <String>[];

      final dio = createDioClient(
        baseUrl: 'http://127.0.0.1:8000',
        logPrint: (msg) => logs.add(msg.toString()),
        enableLogging: true,
      );

      dio.httpClientAdapter = MockHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'success': true,
            'data': {
              'session_id': syntheticSessionId,
              'status': 'available',
            },
          }),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await dio.post(
        '/auth/x/session',
        data: {
          'auth_token': syntheticAuthToken,
          'ct0': syntheticCt0,
        },
      );

      final combinedLogs = logs.join('\n');

      // CRITICAL ASSERTIONS: Secrets must NEVER appear in logs
      expect(combinedLogs, isNot(contains(syntheticAuthToken)));
      expect(combinedLogs, isNot(contains(syntheticCt0)));

      // Assert that redaction placeholder was output instead
      expect(combinedLogs, contains('[REDACTED SENSITIVE AUTH PAYLOAD]'));
      expect(combinedLogs, contains('[SAFE AUTH METADATA]'));
    });

    test('redacts X-Session-ID, Authorization, and Cookie from logged headers',
        () async {
      final logs = <String>[];

      final dio = createDioClient(
        baseUrl: 'http://127.0.0.1:8000',
        logPrint: (msg) => logs.add(msg.toString()),
        enableLogging: true,
      );

      dio.httpClientAdapter = MockHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({'success': true}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await dio.post(
        '/media/info',
        data: {'url': 'https://x.com/user/status/123'},
        options: Options(
          headers: {
            'X-Session-ID': syntheticSessionId,
            'Authorization': 'Bearer secret_token',
            'Cookie': 'auth_token=super_secret',
            'X-Custom-Public': 'normal_value',
          },
        ),
      );

      final combinedLogs = logs.join('\n');

      // Sensitive header values must NEVER be logged
      expect(combinedLogs, isNot(contains(syntheticSessionId)));
      expect(combinedLogs, isNot(contains('secret_token')));
      expect(combinedLogs, isNot(contains('super_secret')));

      // Redacted placeholders should appear
      expect(combinedLogs, contains('X-Session-ID: [REDACTED]'));
      expect(combinedLogs, contains('Authorization: [REDACTED]'));
      expect(combinedLogs, contains('Cookie: [REDACTED]'));

      // Non-sensitive headers should remain intact for debugging
      expect(combinedLogs, contains('X-Custom-Public: normal_value'));
    });

    test(
        'normal non-sensitive endpoints preserve request body logging for debugging',
        () async {
      final logs = <String>[];

      final dio = createDioClient(
        baseUrl: 'http://127.0.0.1:8000',
        logPrint: (msg) => logs.add(msg.toString()),
        enableLogging: true,
      );

      dio.httpClientAdapter = MockHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'success': true,
            'data': {'title': 'Public Video'}
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await dio.post(
        '/media/info',
        data: {'url': 'https://youtube.com/watch?v=123'},
      );

      final combinedLogs = logs.join('\n');
      expect(combinedLogs, contains('https://youtube.com/watch?v=123'));
      expect(combinedLogs, contains('Public Video'));
    });

    test('error on sensitive endpoint does not leak response payload',
        () async {
      final logs = <String>[];

      final dio = createDioClient(
        baseUrl: 'http://127.0.0.1:8000',
        logPrint: (msg) => logs.add(msg.toString()),
        enableLogging: true,
      );

      dio.httpClientAdapter = MockHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'error': {'details': 'Sensitive server error info'},
          }),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      try {
        await dio.post(
          '/auth/x/session',
          data: {'auth_token': syntheticAuthToken, 'ct0': syntheticCt0},
        );
      } catch (_) {}

      final combinedLogs = logs.join('\n');
      expect(combinedLogs, isNot(contains(syntheticAuthToken)));
      expect(combinedLogs, isNot(contains(syntheticCt0)));
      expect(combinedLogs, contains('[REDACTED SENSITIVE ERROR]'));
    });
  });
}
