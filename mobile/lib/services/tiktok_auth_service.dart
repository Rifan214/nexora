import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
import '../models/tiktok_auth_session.dart';
import 'api_service.dart';

final tikTokAuthServiceProvider = Provider<TikTokAuthService>((ref) {
  return TikTokAuthService(ref.watch(apiServiceProvider));
});

/// Service responsible for managing ephemeral TikTok backend sessions.
///
/// Ensures raw session credentials (sessionid, sid_tt) exist strictly in-memory
/// during registration and are never logged, persisted, or leaked in exceptions.
class TikTokAuthService {
  const TikTokAuthService(this._apiService);

  final ApiService _apiService;

  /// Registers an ephemeral TikTok user session on the backend.
  ///
  /// Transmits [sessionid] and optional [sidTt] directly to the backend over TLS/HTTP.
  /// The backend creates an ephemeral, process-local session and returns only
  /// an opaque `session_id` and non-sensitive expiration metadata.
  Future<TikTokAuthSession> createSession({
    required String sessionid,
    String? sidTt,
  }) async {
    final cleanSessionid = sessionid.trim();
    final cleanSidTt = sidTt?.trim();

    if (cleanSessionid.isEmpty) {
      throw const ApiException('Invalid TikTok authentication credentials.');
    }

    try {
      final payload = <String, dynamic>{
        'sessionid': cleanSessionid,
      };
      if (cleanSidTt != null && cleanSidTt.isNotEmpty) {
        payload['sid_tt'] = cleanSidTt;
      }

      final response = await _apiService.postJson(
        ApiPaths.tikTokAuthSession,
        data: payload,
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return TikTokAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return TikTokAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      throw const ApiException('Unexpected session response from server.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Failed to create ephemeral TikTok session.');
    }
  }

  /// Retrieves the current status and expiration for an existing [sessionId].
  Future<TikTokAuthSession> getSession(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      throw const ApiException('Invalid session identifier.');
    }

    try {
      final response = await _apiService.getJson(
        ApiPaths.tikTokAuthSessionDetail(cleanId),
      );

      final rawData = response['data'];
      if (rawData is Map<String, dynamic>) {
        return TikTokAuthSession.fromJson(rawData);
      }
      if (rawData is Map) {
        return TikTokAuthSession.fromJson(Map<String, dynamic>.from(rawData));
      }

      throw const ApiException('Unexpected session response from server.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Failed to retrieve TikTok session status.');
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
        ApiPaths.tikTokAuthSessionDetail(cleanId),
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
      throw const ApiException('Failed to revoke TikTok session.');
    }
  }
}
