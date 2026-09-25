import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
import '../models/x_auth_session.dart';
import 'api_service.dart';

final xAuthServiceProvider = Provider<XAuthService>((ref) {
  return XAuthService(ref.watch(apiServiceProvider));
});

/// Service responsible for managing ephemeral X/Twitter backend sessions.
///
/// Ensures raw session credentials (auth_token, ct0) exist strictly in-memory
/// during registration and are never logged, persisted, or leaked in exceptions.
class XAuthService {
  const XAuthService(this._apiService);

  final ApiService _apiService;

  /// Registers an ephemeral X user session on the backend.
  ///
  /// Transmits [authToken] and [ct0] directly to the backend over TLS/HTTP.
  /// The backend creates an ephemeral, process-local session and returns only
  /// an opaque `session_id` and non-sensitive expiration metadata.
  Future<XAuthSession> createSession({
    required String authToken,
    required String ct0,
  }) async {
    final cleanToken = authToken.trim();
    final cleanCt0 = ct0.trim();

    if (cleanToken.isEmpty || cleanCt0.isEmpty) {
      throw const ApiException('Invalid X authentication credentials.');
    }

    try {
      final response = await _apiService.postJson(
        ApiPaths.xAuthSession,
        data: {
          'auth_token': cleanToken,
          'ct0': cleanCt0,
        },
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return XAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return XAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      throw const ApiException('Unexpected session response from server.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Failed to create ephemeral X session.');
    }
  }

  /// Retrieves the current status and expiration for an existing [sessionId].
  Future<XAuthSession> getSession(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      throw const ApiException('Invalid session identifier.');
    }

    try {
      final response = await _apiService.getJson(
        ApiPaths.xAuthSessionDetail(cleanId),
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return XAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return XAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      throw const ApiException('Unexpected session response from server.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Failed to retrieve X session status.');
    }
  }

  /// Explicitly revokes and invalidates the session identified by [sessionId].
  Future<bool> deleteSession(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      return true;
    }

    try {
      await _apiService.deleteJson(
        ApiPaths.xAuthSessionDetail(cleanId),
      );
      return true;
    } on ApiException catch (e) {
      // If the session was already removed or expired (404), revocation is complete.
      if (e.message.toLowerCase().contains('not found') ||
          e.message.toLowerCase().contains('404')) {
        return true;
      }
      rethrow;
    } catch (_) {
      throw const ApiException('Failed to revoke X session.');
    }
  }
}
