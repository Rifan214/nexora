import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStorageClient {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

class FlutterSecureStorageWrapper implements SecureStorageClient {
  const FlutterSecureStorageWrapper([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String? value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

final xAuthStorageProvider = Provider<XAuthStorage>((ref) {
  return const XAuthStorage();
});

class XAuthStorage {
  const XAuthStorage([
    this._storage = const FlutterSecureStorageWrapper(),
  ]);

  final SecureStorageClient _storage;

  static const _sessionIdKey = 'nexora.x_auth.session_id';
  static const _authTokenKey = 'nexora.x_auth.auth_token';
  static const _ct0Key = 'nexora.x_auth.ct0';

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

  /// Persistently stores the extracted X credentials to encrypted secure storage.
  ///
  /// Rejects empty credentials and guarantees credentials are never leaked
  /// to logs, exception messages, or debug state.
  Future<void> saveCredentials({
    required String authToken,
    required String ct0,
  }) async {
    final cleanToken = authToken.trim();
    final cleanCt0 = ct0.trim();
    if (cleanToken.isEmpty || cleanCt0.isEmpty) {
      await clearCredentials();
      return;
    }
    try {
      await _storage.write(key: _authTokenKey, value: cleanToken);
      await _storage.write(key: _ct0Key, value: cleanCt0);
    } catch (_) {
      // Safe fallback: do not rethrow credentials or leak storage internals
    }
  }

  /// Reads the saved X credentials from secure encrypted storage, if available.
  Future<XStoredCredentials?> readCredentials() async {
    try {
      final token = await _storage.read(key: _authTokenKey);
      final ct0 = await _storage.read(key: _ct0Key);
      final cleanToken = token?.trim();
      final cleanCt0 = ct0?.trim();
      if (cleanToken != null &&
          cleanToken.isNotEmpty &&
          cleanCt0 != null &&
          cleanCt0.isNotEmpty) {
        return XStoredCredentials(
          authToken: cleanToken,
          ct0: cleanCt0,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Removes the persisted credentials from secure encrypted storage.
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _authTokenKey);
      await _storage.delete(key: _ct0Key);
    } catch (_) {
      // Safe fallback
    }
  }
}

/// In-memory representation of persisted X credentials read from secure storage.
///
/// Guaranteed to never expose sensitive values in [toString].
class XStoredCredentials {
  const XStoredCredentials({
    required this.authToken,
    required this.ct0,
  });

  final String authToken;
  final String ct0;

  bool get isValid => authToken.trim().isNotEmpty && ct0.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XStoredCredentials &&
          runtimeType == other.runtimeType &&
          authToken == other.authToken &&
          ct0 == other.ct0;

  @override
  int get hashCode => Object.hash(authToken, ct0);

  @override
  String toString() => 'XStoredCredentials([PROTECTED])';
}
