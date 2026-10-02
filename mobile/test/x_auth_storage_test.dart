import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/x_auth_storage.dart';

class FakeSecureStorage implements SecureStorageClient {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<String?> read({required String key}) async {
    return _data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  Map<String, String> get data => Map.unmodifiable(_data);
}

void main() {
  group('XAuthStorage Tests', () {
    late FakeSecureStorage fakeStorage;
    late XAuthStorage authStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      authStorage = XAuthStorage(fakeStorage);
    });

    test('saveSessionId saves trimmed opaque token under secure namespace',
        () async {
      await authStorage.saveSessionId('  test_session_id_12345  ');

      final saved = await authStorage.readSessionId();
      expect(saved, 'test_session_id_12345');

      final allData = fakeStorage.data;
      expect(allData.keys, contains('nexora.x_auth.session_id'));
      expect(allData['nexora.x_auth.session_id'], 'test_session_id_12345');

      // Ensure no raw non-namespaced credentials or cookies could ever be saved
      expect(allData.containsKey('auth_token'), isFalse);
      expect(allData.containsKey('ct0'), isFalse);
      expect(allData.containsKey('cookie'), isFalse);
    });

    test('saveSessionId with empty string clears the session', () async {
      await authStorage.saveSessionId('valid_id');
      expect(await authStorage.readSessionId(), 'valid_id');

      await authStorage.saveSessionId('   ');
      expect(await authStorage.readSessionId(), isNull);
    });

    test('readSessionId returns null when nothing is stored', () async {
      final value = await authStorage.readSessionId();
      expect(value, isNull);
    });

    test('clearSessionId removes stored session', () async {
      await authStorage.saveSessionId('id_to_clear');
      expect(await authStorage.readSessionId(), 'id_to_clear');

      await authStorage.clearSessionId();
      expect(await authStorage.readSessionId(), isNull);
    });

    // Phase 2 Tests: Credentials Persistence

    test('1. saveCredentials -> readCredentials preserves trimmed credentials',
        () async {
      await authStorage.saveCredentials(
        authToken: '  auth_token_secret_123  ',
        ct0: '  ct0_secret_456  ',
      );

      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds!.isValid, isTrue);
      expect(creds.authToken, 'auth_token_secret_123');
      expect(creds.ct0, 'ct0_secret_456');
    });

    test('2. clearCredentials removes stored credentials from secure storage',
        () async {
      await authStorage.saveCredentials(
        authToken: 'auth_token_val',
        ct0: 'ct0_val',
      );
      expect(await authStorage.readCredentials(), isNotNull);

      await authStorage.clearCredentials();
      expect(await authStorage.readCredentials(), isNull);
      expect(fakeStorage.data.containsKey('nexora.x_auth.auth_token'), isFalse);
      expect(fakeStorage.data.containsKey('nexora.x_auth.ct0'), isFalse);
    });

    test('3. credential keys are correctly namespaced in secure storage',
        () async {
      await authStorage.saveCredentials(
        authToken: 'auth_token_namespaced',
        ct0: 'ct0_namespaced',
      );

      final data = fakeStorage.data;
      expect(data.keys, contains('nexora.x_auth.auth_token'));
      expect(data.keys, contains('nexora.x_auth.ct0'));
      expect(data['nexora.x_auth.auth_token'], 'auth_token_namespaced');
      expect(data['nexora.x_auth.ct0'], 'ct0_namespaced');
    });

    test('4. session ID operations continue to work alongside credentials',
        () async {
      await authStorage.saveSessionId('sess_12345');
      await authStorage.saveCredentials(
        authToken: 'auth_tok',
        ct0: 'ct0_tok',
      );

      expect(await authStorage.readSessionId(), 'sess_12345');
      final creds = await authStorage.readCredentials();
      expect(creds?.authToken, 'auth_tok');
      expect(creds?.ct0, 'ct0_tok');
    });

    test('5. clearSessionId does not delete credentials', () async {
      await authStorage.saveSessionId('sess_to_clear');
      await authStorage.saveCredentials(
        authToken: 'persisted_auth',
        ct0: 'persisted_ct0',
      );

      await authStorage.clearSessionId();

      expect(await authStorage.readSessionId(), isNull);
      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds?.authToken, 'persisted_auth');
      expect(creds?.ct0, 'persisted_ct0');
    });

    test('6. clearCredentials does not delete session ID', () async {
      await authStorage.saveSessionId('persisted_session');
      await authStorage.saveCredentials(
        authToken: 'auth_to_clear',
        ct0: 'ct0_to_clear',
      );

      await authStorage.clearCredentials();

      expect(await authStorage.readCredentials(), isNull);
      expect(await authStorage.readSessionId(), 'persisted_session');
    });

    test('7. empty credentials are rejected and clear stored credentials',
        () async {
      await authStorage.saveCredentials(
        authToken: 'valid_auth',
        ct0: 'valid_ct0',
      );
      expect(await authStorage.readCredentials(), isNotNull);

      // Attempting to save with empty authToken
      await authStorage.saveCredentials(
        authToken: '   ',
        ct0: 'valid_ct0',
      );
      expect(await authStorage.readCredentials(), isNull);

      // Re-seed and attempt to save with empty ct0
      await authStorage.saveCredentials(
        authToken: 'valid_auth',
        ct0: 'valid_ct0',
      );
      expect(await authStorage.readCredentials(), isNotNull);

      await authStorage.saveCredentials(
        authToken: 'valid_auth',
        ct0: '',
      );
      expect(await authStorage.readCredentials(), isNull);
    });

    test('8. XStoredCredentials.toString() hides sensitive credentials', () {
      const creds = XStoredCredentials(
        authToken: 'super_secret_auth_token',
        ct0: 'super_secret_ct0_csrf',
      );

      final str = creds.toString();
      expect(str, 'XStoredCredentials([PROTECTED])');
      expect(str.contains('super_secret_auth_token'), isFalse);
      expect(str.contains('super_secret_ct0_csrf'), isFalse);
    });
  });
}
