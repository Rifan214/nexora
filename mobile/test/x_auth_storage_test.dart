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

      // Ensure no raw credentials or cookies could ever be saved
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
  });
}
