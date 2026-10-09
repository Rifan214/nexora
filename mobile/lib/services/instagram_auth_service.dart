import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
import '../models/instagram_auth_session.dart';
import 'api_service.dart';

final instagramAuthServiceProvider = Provider<InstagramAuthService>((ref) {
  return InstagramAuthService(ref.watch(apiServiceProvider));
});

/// Service responsible for managing ephemeral Instagram backend sessions.
///
/// Ensures raw session credentials (sessionid, ds_user_id, csrftoken) exist strictly in-memory
/// during registration and are never logged, persisted, or leaked in exceptions.
class InstagramAuthService {
  const InstagramAuthService(this._apiService);

  final ApiService _apiService;

  /// Registers an ephemeral Instagram user session on the backend.
  ///
  /// Transmits [sessionid] and optional [dsUserId]/[csrftoken] directly to the backend over TLS/HTTP.
  /// The backend creates an ephemeral, process-local session and returns only
  /// an opaque `session_id` and non-sensitive expiration metadata.
  Future<InstagramAuthSession> createSession({
    required String sessionid,
    String? dsUserId,
    String? csrftoken,
  }) async {
    final cleanSessionid = sessionid.trim();
    final cleanDsUserId = dsUserId?.trim();
    final cleanCsrftoken = csrftoken?.trim();

    if (cleanSessionid.isEmpty) {
      throw const ApiException('Invalid Instagram authentication credentials.');
    }

    try {
      final payload = <String, dynamic>{
        'sessionid': cleanSessionid,
      };
      if (cleanDsUserId != null && cleanDsUserId.isNotEmpty) {
        payload['ds_user_id'] = cleanDsUserId;
      }
      if (cleanCsrftoken != null && cleanCsrftoken.isNotEmpty) {
        payload['csrftoken'] = cleanCsrftoken;
      }

      final response = await _apiService.postJson(
        ApiPaths.instagramAuthSession,
        data: payload,
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return InstagramAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return InstagramAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      throw const ApiException('Unexpected session response from server.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Failed to connect Instagram account. Verify network connection and server status.',
      );
    }
  }

  /// Fetches status metadata for an existing session by opaque [sessionId].
  Future<InstagramAuthSession?> getSession(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      return null;
    }

    try {
      final response = await _apiService.getJson(
        ApiPaths.instagramAuthSessionDetail(cleanId),
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return InstagramAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return InstagramAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      return null;
    } on ApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') ||
          msg.contains('expired') ||
          msg.contains('404')) {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Revokes an active session on the backend.
  Future<bool> revokeSession(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      return false;
    }

    try {
      final response = await _apiService.deleteJson(
        ApiPaths.instagramAuthSessionDetail(cleanId),
      );

      final rawData = response['data'];
      if (rawData is Map) {
        return rawData['revoked'] as bool? ?? true;
      }
      return true;
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('not found')) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Alias for revokeSession.
  Future<bool> deleteSession(String sessionId) => revokeSession(sessionId);
}
