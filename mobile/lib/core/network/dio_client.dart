import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/server_config_provider.dart';
import '../config/app_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final serverConfig = ref.watch(effectiveServerConfigProvider);
  final dio = createDioClient(baseUrl: serverConfig.apiBaseUrl);
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

void _defaultLog(Object object) {
  debugPrint(object.toString());
}

Dio createDioClient({
  String? baseUrl,
  void Function(Object object)? logPrint,
  bool enableLogging = kDebugMode,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      responseType: ResponseType.json,
    ),
  );

  if (enableLogging) {
    dio.interceptors.add(
      SanitizedLogInterceptor(
        logPrint: logPrint ?? _defaultLog,
      ),
    );
  }

  return dio;
}

/// A security-hardened logging interceptor that automatically suppresses
/// and redacts sensitive authentication payloads, auth tokens, session tokens,
/// and credentials from debug console outputs.
class SanitizedLogInterceptor extends Interceptor {
  SanitizedLogInterceptor({
    void Function(Object object)? logPrint,
  }) : _log = logPrint ?? _defaultLog;

  final void Function(Object object) _log;

  static const _sensitiveHeaderKeys = {
    'x-session-id',
    'authorization',
    'cookie',
    'set-cookie',
  };

  static const _sensitivePaths = {
    '/auth/x/session',
  };

  static bool isSensitivePath(String path) {
    return _sensitivePaths.any((p) => path.contains(p));
  }

  static Map<String, dynamic> sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = <String, dynamic>{};
    for (final entry in headers.entries) {
      if (_sensitiveHeaderKeys.contains(entry.key.toLowerCase())) {
        sanitized[entry.key] = '[REDACTED]';
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log('*** Request ***');
    _log('uri: ${options.uri}');
    _log('method: ${options.method}');

    if (options.headers.isNotEmpty) {
      _log('headers: ${sanitizeHeaders(options.headers)}');
    }

    if (isSensitivePath(options.path)) {
      _log('data: [REDACTED SENSITIVE AUTH PAYLOAD]');
    } else if (options.data != null) {
      _log('data: ${options.data}');
    }

    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log('*** Response ***');
    _log('uri: ${response.requestOptions.uri}');
    _log('statusCode: ${response.statusCode}');

    if (isSensitivePath(response.requestOptions.path)) {
      // Backend X-Auth responses only return safe metadata, but we sanitize to be cautious
      _log('data: [SAFE AUTH METADATA]');
    } else if (response.data != null) {
      _log('data: ${response.data}');
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log('*** DioException ***:');
    _log('uri: ${err.requestOptions.uri}');
    _log('$err');

    if (err.response != null) {
      _log('statusCode: ${err.response?.statusCode}');
      if (isSensitivePath(err.requestOptions.path)) {
        _log('responseData: [REDACTED SENSITIVE ERROR]');
      } else {
        _log('responseData: ${err.response?.data}');
      }
    }

    handler.next(err);
  }
}
