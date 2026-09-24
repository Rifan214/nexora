import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_paths.dart';
import '../models/server_config.dart';

/// Result returned by [ServerConfigService.testConnection].
class ServerConnectionTestResult {
  const ServerConnectionTestResult({
    required this.isSuccess,
    required this.message,
    this.status,
    this.environment,
    this.statusCode,
  });

  final bool isSuccess;
  final String message;
  final String? status;
  final String? environment;
  final int? statusCode;
}

/// Service managing persistent storage and health verification of server configuration.
class ServerConfigService {
  static const _hostKey = 'server_config.host';
  static const _portKey = 'server_config.port';
  static const _isOverrideKey = 'server_config.is_override';

  /// Loads the persisted server configuration, or returns the default.
  Future<ServerConfig> load({SharedPreferences? preferences}) async {
    final storage = preferences ?? await SharedPreferences.getInstance();
    final isOverride = storage.getBool(_isOverrideKey) ?? false;
    final savedHost = storage.getString(_hostKey);
    final savedPort = storage.getInt(_portKey);

    if (isOverride && savedHost != null && savedHost.trim().isNotEmpty) {
      final defaultCfg = ServerConfig.fromDefault();
      return ServerConfig(
        host: savedHost.trim(),
        port: savedPort ?? defaultCfg.port,
        isCustomOverride: true,
        scheme: defaultCfg.scheme,
        wsScheme: defaultCfg.wsScheme,
      );
    }

    return ServerConfig.fromDefault();
  }

  /// Persists a custom server override.
  Future<void> saveOverride({
    required String host,
    required int port,
    SharedPreferences? preferences,
  }) async {
    final storage = preferences ?? await SharedPreferences.getInstance();
    await Future.wait([
      storage.setString(_hostKey, host.trim()),
      storage.setInt(_portKey, port),
      storage.setBool(_isOverrideKey, true),
    ]);
  }

  /// Resets configuration to compile-time defaults.
  Future<void> resetToDefault({SharedPreferences? preferences}) async {
    final storage = preferences ?? await SharedPreferences.getInstance();
    await Future.wait([
      storage.remove(_hostKey),
      storage.remove(_portKey),
      storage.remove(_isOverrideKey),
    ]);
  }

  /// Tests connectivity against the candidate server's `/health` endpoint.
  Future<ServerConnectionTestResult> testConnection(
    String candidateApiBaseUrl, {
    Dio? client,
  }) async {
    final dio = client ??
        Dio(
          BaseOptions(
            baseUrl: candidateApiBaseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            responseType: ResponseType.json,
          ),
        );

    try {
      final response = await dio.get<Object?>(ApiPaths.health);

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final payload = data['data'];
        String? status;
        String? environment;

        if (payload is Map) {
          final payloadMap = Map<String, dynamic>.from(payload);
          status = payloadMap['status'] as String?;
          environment = payloadMap['environment'] as String?;
        }

        final envInfo = environment != null ? ' (env: $environment)' : '';
        return ServerConnectionTestResult(
          isSuccess: true,
          message: 'Connected successfully! Server is healthy$envInfo.',
          status: status,
          environment: environment,
          statusCode: 200,
        );
      }

      return ServerConnectionTestResult(
        isSuccess: false,
        message: 'Server responded with unexpected status (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return _mapDioException(e);
    } catch (e) {
      return ServerConnectionTestResult(
        isSuccess: false,
        message: 'Connection failed: ${e.toString()}',
      );
    } finally {
      if (client == null) {
        dio.close(force: true);
      }
    }
  }

  ServerConnectionTestResult _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ServerConnectionTestResult(
          isSuccess: false,
          message: 'Connection timed out. Check that the server is reachable on this network.',
        );
      case DioExceptionType.connectionError:
        return const ServerConnectionTestResult(
          isSuccess: false,
          message: 'Connection refused. Ensure the backend is running and listening on 0.0.0.0.',
        );
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        return ServerConnectionTestResult(
          isSuccess: false,
          message: 'Server returned HTTP status $status.',
          statusCode: status,
        );
      default:
        return ServerConnectionTestResult(
          isSuccess: false,
          message: e.message?.isNotEmpty == true
              ? e.message!
              : 'Unable to connect to the server.',
        );
    }
  }
}
