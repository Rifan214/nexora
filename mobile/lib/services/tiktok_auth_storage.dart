import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'x_auth_storage.dart';

final tikTokAuthStorageProvider = Provider<TikTokAuthStorage>((ref) {
  return const TikTokAuthStorage();
});

class TikTokAuthStorage {
  const TikTokAuthStorage([
    this._storage = const FlutterSecureStorageWrapper(),
  ]);

  final SecureStorageClient _storage;

  static const _sessionIdKey = 'nexora.tiktok_auth.session_id';
  static const _sessionidKey = 'nexora.tiktok_auth.sessionid';
  static const _sidTtKey = 'nexora.tiktok_auth.sid_tt';

  /// Save the opaque session identifier to secure encrypted storage.
  Future<void> saveSessionId(String sessionId) async {
    final cleanId = sessionId.trim();
    if (cleanId.isEmpty) {
      await clearSessionId();
      return;
    }
    try {
      await _storage.write(key: _sessionIdKey, value: cleanId);
    } catch (_) {
      // Safe fallback: do not rethrow credentials or leak storage internals
    }
  }

  /// Read the saved opaque session identifier if one exists.
  Future<String?> readSessionId() async {
    try {
      final value = await _storage.read(key: _sessionIdKey);
      final trimmed = value?.trim();
      return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    } catch (_) {
      return null;
    }
  }

  /// Remove the session identifier from secure storage.
  Future<void> clearSessionId() async {
    try {
      await _storage.delete(key: _sessionIdKey);
    } catch (_) {
      // Safe fallback
    }
  }

  /// Persistently stores extracted TikTok credentials to encrypted secure storage.
  ///
  /// Rejects empty credentials and guarantees credentials are never leaked
  /// to logs, exception messages, or debug state.
  Future<void> saveCredentials({
    required String sessionid,
    String? sidTt,
  }) async {
    final cleanSessionid = sessionid.trim();
    final cleanSidTt = sidTt?.trim();
    if (cleanSessionid.isEmpty) {
      await clearCredentials();
      return;
    }
    try {
      await _storage.write(key: _sessionidKey, value: cleanSessionid);
      if (cleanSidTt != null && cleanSidTt.isNotEmpty) {
        await _storage.write(key: _sidTtKey, value: cleanSidTt);
      } else {
        await _storage.delete(key: _sidTtKey);
      }
    } catch (_) {
      // Safe fallback: do not rethrow credentials or leak storage internals
    }
  }

  /// Reads saved TikTok credentials from secure encrypted storage, if available.
  Future<TikTokStoredCredentials?> readCredentials() async {
    try {
      final sessionid = await _storage.read(key: _sessionidKey);
      final sidTt = await _storage.read(key: _sidTtKey);
      final cleanSessionid = sessionid?.trim();
      final cleanSidTt = sidTt?.trim();
      if (cleanSessionid != null && cleanSessionid.isNotEmpty) {
        return TikTokStoredCredentials(
          sessionid: cleanSessionid,
          sidTt: (cleanSidTt != null && cleanSidTt.isNotEmpty) ? cleanSidTt : null,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Removes persisted credentials from secure encrypted storage.
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _sessionidKey);
      await _storage.delete(key: _sidTtKey);
    } catch (_) {
      // Safe fallback
    }
  }
}

/// In-memory representation of persisted TikTok credentials read from secure storage.
///
/// Guaranteed to never expose sensitive values in [toString].
class TikTokStoredCredentials {
  const TikTokStoredCredentials({
    required this.sessionid,
    this.sidTt,
  });

  final String sessionid;
  final String? sidTt;

  bool get isValid => sessionid.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TikTokStoredCredentials &&
          runtimeType == other.runtimeType &&
          sessionid == other.sessionid &&
          sidTt == other.sidTt;

  @override
  int get hashCode => Object.hash(sessionid, sidTt);

  @override
  String toString() => 'TikTokStoredCredentials([PROTECTED])';
}
