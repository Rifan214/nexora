import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/x_cookie_manager.dart';

class FakeCookieManagerWrapper implements XCookieManagerWrapper {
  final Map<String, List<Cookie>> _cookieStore = {};
  final List<String> deletedCookieCalls = [];
  final List<String> deleteCookiesCalls = [];

  void setCookies(String url, List<Cookie> cookies) {
    _cookieStore[url] = cookies;
  }

  @override
  Future<List<Cookie>> getCookies({required WebUri url}) async {
    return _cookieStore[url.toString()] ?? [];
  }

  @override
  Future<void> deleteCookie({
    required WebUri url,
    required String name,
    String? domain,
  }) async {
    deletedCookieCalls.add('${url.toString()}:$name:$domain');
  }

  @override
  Future<void> deleteCookies({
    required WebUri url,
    String? domain,
  }) async {
    deleteCookiesCalls.add('${url.toString()}:$domain');
  }
}

void main() {
  group('XCookieManagerService Tests', () {
    late FakeCookieManagerWrapper fakeWrapper;
    late XCookieManagerService service;

    setUp(() {
      fakeWrapper = FakeCookieManagerWrapper();
      service = XCookieManagerService(fakeWrapper);
    });

    test('extractSessionCookies returns null when no cookies exist', () async {
      final result = await service.extractSessionCookies();
      expect(result, isNull);
    });

    test('extractSessionCookies fails when only auth_token is present',
        () async {
      fakeWrapper.setCookies('https://x.com', [
        Cookie(name: 'auth_token', value: 'SYNTHETIC_AUTH_TOKEN_ONLY'),
        Cookie(name: 'guest_id', value: 'v1%3A12345'),
      ]);

      final result = await service.extractSessionCookies();
      expect(result, isNull);
    });

    test('extractSessionCookies fails when only ct0 is present', () async {
      fakeWrapper.setCookies('https://x.com', [
        Cookie(name: 'ct0', value: 'SYNTHETIC_CT0_ONLY'),
        Cookie(name: 'personalization_id', value: 'v1_999'),
      ]);

      final result = await service.extractSessionCookies();
      expect(result, isNull);
    });

    test(
        'extractSessionCookies extracts only auth_token and ct0 from full cookie jar',
        () async {
      fakeWrapper.setCookies('https://x.com', [
        Cookie(name: 'guest_id', value: 'guest_id_value'),
        Cookie(name: 'auth_token', value: 'TEST_AUTH_TOKEN_VAL'),
        Cookie(name: 'kdt', value: 'kdt_secret_val'),
        Cookie(name: 'ct0', value: 'TEST_CT0_VAL'),
        Cookie(name: 'twid', value: 'u%3D123456789'),
      ]);

      final result = await service.extractSessionCookies();

      expect(result, isNotNull);
      expect(result!.authToken, 'TEST_AUTH_TOKEN_VAL');
      expect(result.ct0, 'TEST_CT0_VAL');
      expect(result.isValid, isTrue);

      // Verify that other sensitive/internal cookies are never stored in the result
      expect((result as dynamic).authToken, 'TEST_AUTH_TOKEN_VAL');
      expect(result.toString(), isNot(contains('kdt_secret_val')));
      expect(result.toString(), isNot(contains('twid')));
    });

    test('extractSessionCookies falls back to twitter.com if not on x.com',
        () async {
      fakeWrapper.setCookies('https://twitter.com', [
        Cookie(name: 'auth_token', value: 'TWITTER_AUTH_TOKEN'),
        Cookie(name: 'ct0', value: 'TWITTER_CT0'),
      ]);

      final result = await service.extractSessionCookies();

      expect(result, isNotNull);
      expect(result!.authToken, 'TWITTER_AUTH_TOKEN');
      expect(result.ct0, 'TWITTER_CT0');
    });

    test('clearXCookies targets only X and Twitter domains and credentials',
        () async {
      await service.clearXCookies();

      expect(
        fakeWrapper.deletedCookieCalls,
        contains('https://x.com:auth_token:.x.com'),
      );
      expect(
        fakeWrapper.deletedCookieCalls,
        contains('https://x.com:ct0:.x.com'),
      );
      expect(
        fakeWrapper.deletedCookieCalls,
        contains('https://twitter.com:auth_token:.twitter.com'),
      );
      expect(
        fakeWrapper.deletedCookieCalls,
        contains('https://twitter.com:ct0:.twitter.com'),
      );
      expect(
        fakeWrapper.deleteCookiesCalls,
        contains('https://x.com:.x.com'),
      );
      expect(
        fakeWrapper.deleteCookiesCalls,
        contains('https://twitter.com:.twitter.com'),
      );
    });
  });
}
