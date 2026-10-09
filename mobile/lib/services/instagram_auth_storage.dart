import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'x_auth_storage.dart';

final instagramAuthStorageProvider = Provider<InstagramAuthStorage>((ref) {
  return const InstagramAuthStorage();
});

class InstagramAuthStorage {
  const InstagramAuthStorage([
    this._storage = const FlutterSecureStorageWrapper(),
  ]);

  final SecureStorageClient _storage;

  static const _sessionIdKey = 'nexora.instagram_auth.session_id';
  static const _sessionidKey = 'nexora.instagram_auth.sessionid';
  static const _dsUserIdKey = 'nexora.instagram_auth.ds_user_id';
  static const _csrftokenKey = 'nexora.instagram_auth.csrftoken';

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

  /// Persistently stores extracted Instagram credentials to encrypted secure storage.
  ///
  /// Rejects empty credentials and guarantees credentials are never leaked
  /// to logs, exception messages, or debug state.
  Future<void> saveCredentials({
    required String sessionid,
    String? dsUserId,
    String? csrftoken,
  }) async {
    final cleanSessionid = sessionid.trim();
    final cleanDsUserId = dsUserId?.trim();
    final cleanCsrftoken = csrftoken?.trim();
    if (cleanSessionid.isEmpty) {
      await clearCredentials();
      return;
    }
    try {
      await _storage.write(key: _sessionidKey, value: cleanSessionid);
      if (cleanDsUserId != null && cleanDsUserId.isNotEmpty) {
        await _storage.write(key: _dsUserIdKey, value: cleanDsUserId);
      } else {
        await _storage.delete(key: _dsUserIdKey);
      }
      if (cleanCsrftoken != null && cleanCsrftoken.isNotEmpty) {
        await _storage.write(key: _csrftokenKey, value: cleanCsrftoken);
      } else {
        await _storage.delete(key: _csrftokenKey);
      }
    } catch (_) {
      // Safe fallback: do not rethrow credentials or leak storage internals
    }
  }

  /// Reads saved Instagram credentials from secure encrypted storage, if available.
  Future<InstagramStoredCredentials?> readCredentials() async {
    try {
      final sessionid = await _storage.read(key: _sessionidKey);
      final dsUserId = await _storage.read(key: _dsUserIdKey);
      final csrftoken = await _storage.read(key: _csrftokenKey);
      final cleanSessionid = sessionid?.trim();
      final cleanDsUserId = dsUserId?.trim();
      final cleanCsrftoken = csrftoken?.trim();
      if (cleanSessionid != null && cleanSessionid.isNotEmpty) {
        return InstagramStoredCredentials(
          sessionid: cleanSessionid,
          dsUserId: (cleanDsUserId != null && cleanDsUserId.isNotEmpty) ? cleanDsUserId : null,
          csrftoken: (cleanCsrftoken != null && cleanCsrftoken.isNotEmpty) ? cleanCsrftoken : null,
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
      await _storage.delete(key: _dsUserIdKey);
      await _storage.delete(key: _csrftokenKey);
    } catch (_) {
      // Safe fallback
    }
  }

  /// Removes both session identifier and credentials from secure encrypted storage.
  Future<void> clearAll() async {
    await clearSessionId();
    await clearCredentials();
  }
}

/// In-memory representation of persisted Instagram credentials read from secure storage.
///
/// Guaranteed to never expose sensitive values in [toString].
class InstagramStoredCredentials {
  const InstagramStoredCredentials({
    required this.sessionid,
    this.dsUserId,
    this.csrftoken,
  });

  final String sessionid;
  final String? dsUserId;
  final String? csrftoken;

  bool get isValid => sessionid.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstagramStoredCredentials &&
          runtimeType == other.runtimeType &&
          sessionid == other.sessionid &&
          dsUserId == other.dsUserId &&
          csrftoken == other.csrftoken;

  @override
  int get hashCode => Object.hash(sessionid, dsUserId, csrftoken);

  @override
  String toString() => 'InstagramStoredCredentials([PROTECTED])';
}
