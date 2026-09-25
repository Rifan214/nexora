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

  /// Save the opaque session identifier to secure encrypted storage.
  ///
  /// Never stores auth_token, ct0, cookies, or any raw credentials.
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
}
