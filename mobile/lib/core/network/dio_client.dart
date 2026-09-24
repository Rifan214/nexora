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

Dio createDioClient({String? baseUrl}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      responseType: ResponseType.json,
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
  }

  return dio;
}
