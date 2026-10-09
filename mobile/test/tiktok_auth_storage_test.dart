import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/tiktok_auth_storage.dart';
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
  group('TikTokAuthStorage Tests', () {
    late FakeSecureStorage fakeStorage;
    late TikTokAuthStorage authStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      authStorage = TikTokAuthStorage(fakeStorage);
    });

    test('saveSessionId saves trimmed opaque token under secure namespace', () async {
      await authStorage.saveSessionId('  test_tiktok_session_12345  ');

      final saved = await authStorage.readSessionId();
      expect(saved, 'test_tiktok_session_12345');

      final allData = fakeStorage.data;
      expect(allData.keys, contains('nexora.tiktok_auth.session_id'));
      expect(allData['nexora.tiktok_auth.session_id'], 'test_tiktok_session_12345');

      // Ensure no raw non-namespaced credentials or cookies saved
      expect(allData.containsKey('sessionid'), isFalse);
      expect(allData.containsKey('sid_tt'), isFalse);
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

    test('saveCredentials -> readCredentials preserves trimmed credentials', () async {
      await authStorage.saveCredentials(
        sessionid: '  sess_abc_123  ',
        sidTt: '  sid_def_456  ',
      );

      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds!.isValid, isTrue);
      expect(creds.sessionid, 'sess_abc_123');
      expect(creds.sidTt, 'sid_def_456');
    });

    test('saveCredentials without optional sidTt succeeds', () async {
      await authStorage.saveCredentials(
        sessionid: 'sess_abc_only',
      );

      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds!.isValid, isTrue);
      expect(creds.sessionid, 'sess_abc_only');
      expect(creds.sidTt, isNull);
    });

    test('clearCredentials removes stored credentials from secure storage', () async {
      await authStorage.saveCredentials(
        sessionid: 'sess_to_clear',
        sidTt: 'sid_to_clear',
      );
      expect(await authStorage.readCredentials(), isNotNull);

      await authStorage.clearCredentials();
      expect(await authStorage.readCredentials(), isNull);
      expect(fakeStorage.data.containsKey('nexora.tiktok_auth.sessionid'), isFalse);
      expect(fakeStorage.data.containsKey('nexora.tiktok_auth.sid_tt'), isFalse);
    });

    test('credential keys are correctly namespaced in secure storage', () async {
      await authStorage.saveCredentials(
        sessionid: 'sess_namespaced',
        sidTt: 'sid_namespaced',
      );

      final data = fakeStorage.data;
      expect(data.keys, contains('nexora.tiktok_auth.sessionid'));
      expect(data.keys, contains('nexora.tiktok_auth.sid_tt'));
      expect(data['nexora.tiktok_auth.sessionid'], 'sess_namespaced');
      expect(data['nexora.tiktok_auth.sid_tt'], 'sid_namespaced');
    });

    test('session ID operations continue to work alongside credentials', () async {
      await authStorage.saveSessionId('sess_id_789');
      await authStorage.saveCredentials(
        sessionid: 'raw_sessionid_val',
        sidTt: 'raw_sidtt_val',
      );

      expect(await authStorage.readSessionId(), 'sess_id_789');
      final creds = await authStorage.readCredentials();
      expect(creds?.sessionid, 'raw_sessionid_val');
      expect(creds?.sidTt, 'raw_sidtt_val');
    });

    test('clearSessionId does not delete credentials', () async {
      await authStorage.saveSessionId('sess_to_clear');
      await authStorage.saveCredentials(
        sessionid: 'persisted_sessionid',
        sidTt: 'persisted_sidtt',
      );

      await authStorage.clearSessionId();

      expect(await authStorage.readSessionId(), isNull);
      final creds = await authStorage.readCredentials();
      expect(creds, isNotNull);
      expect(creds?.sessionid, 'persisted_sessionid');
      expect(creds?.sidTt, 'persisted_sidtt');
    });

    test('clearCredentials does not delete session ID', () async {
      await authStorage.saveSessionId('persisted_session_id');
      await authStorage.saveCredentials(
        sessionid: 'sess_to_clear',
        sidTt: 'sid_to_clear',
      );

      await authStorage.clearCredentials();

      expect(await authStorage.readCredentials(), isNull);
      expect(await authStorage.readSessionId(), 'persisted_session_id');
    });

    test('empty sessionid is rejected and clears stored credentials', () async {
      await authStorage.saveCredentials(
        sessionid: 'valid_sess',
        sidTt: 'valid_sid',
      );
      expect(await authStorage.readCredentials(), isNotNull);

      // Attempting to save with empty sessionid
      await authStorage.saveCredentials(
        sessionid: '   ',
        sidTt: 'valid_sid',
      );
      expect(await authStorage.readCredentials(), isNull);
    });

    test('TikTokStoredCredentials.toString() hides sensitive credentials', () {
      const creds = TikTokStoredCredentials(
        sessionid: 'super_secret_sessionid',
        sidTt: 'super_secret_sid_tt',
      );

      final str = creds.toString();
      expect(str, 'TikTokStoredCredentials([PROTECTED])');
      expect(str.contains('super_secret_sessionid'), isFalse);
      expect(str.contains('super_secret_sid_tt'), isFalse);
    });
  });
}
