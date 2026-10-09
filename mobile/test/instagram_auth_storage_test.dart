import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/instagram_auth_storage.dart';
import 'package:nexora/services/x_auth_storage.dart'; // for SecureStorageClient interface

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
  group('InstagramAuthStorage Tests', () {
    late FakeSecureStorage fakeStorage;
    late InstagramAuthStorage authStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      authStorage = InstagramAuthStorage(fakeStorage);
    });

    test('saveSessionId saves trimmed opaque token under secure namespace', () async {
      await authStorage.saveSessionId('  test_ig_session_12345  ');

      final saved = await authStorage.readSessionId();
      expect(saved, 'test_ig_session_12345');

      final allData = fakeStorage.data;
      expect(allData.keys, contains('nexora.instagram_auth.session_id'));
      expect(allData['nexora.instagram_auth.session_id'], 'test_ig_session_12345');

      // Ensure no raw non-namespaced credentials or cookies saved
      expect(allData.containsKey('sessionid'), isFalse);
      expect(allData.containsKey('ds_user_id'), isFalse);
      expect(allData.containsKey('csrftoken'), isFalse);
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

    test('saveCredentials -> readCredentials preserves trimmed credentials with URL-encoding', () async {
      await authStorage.saveCredentials(
        sessionid: '  sess_abc%3A123  ',
        dsUserId: '  12345678  ',
        csrftoken: '  csrf_token_xyz  ',
      );

      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds!.isValid, isTrue);
      expect(creds.sessionid, 'sess_abc%3A123');
      expect(creds.dsUserId, '12345678');
      expect(creds.csrftoken, 'csrf_token_xyz');
    });

    test('saveCredentials without optional companions succeeds', () async {
      await authStorage.saveCredentials(
        sessionid: 'sess_only%3Atoken',
      );

      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds!.isValid, isTrue);
      expect(creds.sessionid, 'sess_only%3Atoken');
      expect(creds.dsUserId, isNull);
      expect(creds.csrftoken, isNull);
    });

    test('clearCredentials removes stored credentials but keeps session ID', () async {
      await authStorage.saveSessionId('active_session_abc');
      await authStorage.saveCredentials(
        sessionid: 'raw_cookie_123',
        dsUserId: '456',
      );

      await authStorage.clearCredentials();

      expect(await authStorage.readCredentials(), isNull);
      expect(await authStorage.readSessionId(), 'active_session_abc');
    });

    test('clearAll removes both session and credentials', () async {
      await authStorage.saveSessionId('active_session_xyz');
      await authStorage.saveCredentials(sessionid: 'raw_cookie_999');

      await authStorage.clearAll();

      expect(await authStorage.readSessionId(), isNull);
      expect(await authStorage.readCredentials(), isNull);
    });
  });
}
