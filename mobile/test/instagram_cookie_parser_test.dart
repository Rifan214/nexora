import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/utils/instagram_cookie_parser.dart';

void main() {
  group('InstagramCookieParser Tests', () {
    test('1. Netscape standard parses sessionid, ds_user_id, and csrftoken from .instagram.com', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tig_sessionid_std\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tds_user_id\t123456789\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tcsrftoken\tcsrf_token_std\n';

      final result = InstagramCookieParser.parse(netscape);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'ig_sessionid_std');
      expect(result.dsUserId, '123456789');
      expect(result.csrftoken, 'csrf_token_std');
    });

    test('2. Netscape with #HttpOnly_ parses correctly', () {
      const netscapeHttpOnly =
          '# Netscape HTTP Cookie File\n'
          '#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tig_httponly_session\n'
          '#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t1790000000\tds_user_id\t987654321\n';

      final result = InstagramCookieParser.parse(netscapeHttpOnly);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'ig_httponly_session');
      expect(result.dsUserId, '987654321');
      expect(result.csrftoken, isNull);
    });

    test('3. URL-encoded characters in sessionid (e.g. %3A) are strictly preserved', () {
      const netscapeEncoded =
          '# Netscape HTTP Cookie File\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\t12345678%3Aabcdef12345%3A28%3AAYc\n';

      final result = InstagramCookieParser.parse(netscapeEncoded);
      expect(result.isValid, isTrue);
      expect(result.sessionid, '12345678%3Aabcdef12345%3A28%3AAYc');
    });

    test('4. JSON export parses array of cookie objects', () {
      const jsonInput = '''
[
  {
    "domain": ".instagram.com",
    "name": "sessionid",
    "value": "json_sessionid_val%3Aabc",
    "path": "/",
    "secure": true,
    "httpOnly": true
  },
  {
    "domain": "instagram.com",
    "name": "ds_user_id",
    "value": "555123456",
    "path": "/",
    "secure": true,
    "httpOnly": false
  },
  {
    "domain": "www.instagram.com",
    "name": "csrftoken",
    "value": "csrf_json_val",
    "path": "/",
    "secure": true,
    "httpOnly": false
  }
]
''';

      final result = InstagramCookieParser.parse(jsonInput);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'json_sessionid_val%3Aabc');
      expect(result.dsUserId, '555123456');
      expect(result.csrftoken, 'csrf_json_val');
    });

    test('5. Raw Cookie header parses semi-colon separated cookies', () {
      const rawHeader =
          'Cookie: mid=abc; sessionid=hdr_sessionid%3A999; ds_user_id=111222; csrftoken=hdr_csrf; rur=PRN';

      final result = InstagramCookieParser.parse(rawHeader);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'hdr_sessionid%3A999');
      expect(result.dsUserId, '111222');
      expect(result.csrftoken, 'hdr_csrf');
    });

    test('6. Strict domain validation: rejects evil spoof domains', () {
      const spoofNetscape = '''
# Netscape HTTP Cookie File
evilinstagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tevil_sessionid
notinstagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tnot_sessionid
fakeinstagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tfake_sessionid
''';

      expect(
        () => InstagramCookieParser.parse(spoofNetscape),
        throwsA(isA<FormatException>()),
      );
    });

    test('7. Mixed platform cookies isolates Instagram credentials and discards others', () {
      const mixedInput = '''
# Netscape HTTP Cookie File
.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tx_auth_token_ignored
.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\ttiktok_sessionid_ignored
.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tinstagram_valid_sessionid
.instagram.com\tTRUE\t/\tTRUE\t1790000000\tds_user_id\t123456789
.youtube.com\tTRUE\t/\tTRUE\t1790000000\tVISITOR_INFO1_LIVE\tyt_cookie_ignored
''';

      final result = InstagramCookieParser.parse(mixedInput);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'instagram_valid_sessionid');
      expect(result.dsUserId, '123456789');
    });

    test('8. Missing sessionid throws FormatException without leaking credentials', () {
      const invalidInput =
          '# Netscape HTTP Cookie File\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tds_user_id\t123456789\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tcsrftoken\tcsrf_only\n';

      expect(
        () => InstagramCookieParser.parse(invalidInput),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('sessionid'),
          ),
        ),
      );
    });

    test('9. Empty string throws FormatException', () {
      expect(
        () => InstagramCookieParser.parse('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('10. Sensitive tokens are masked in toString()', () {
      const creds = InstagramCookieCredentials(
        sessionid: 'secret_ig_sessionid_12345',
        dsUserId: '123456789',
        csrftoken: 'secret_csrftoken_9999',
      );
      expect(creds.toString(), equals('InstagramCookieCredentials([PROTECTED])'));
      expect(creds.toString(), isNot(contains('secret_ig_sessionid_12345')));
      expect(creds.toString(), isNot(contains('123456789')));
      expect(creds.toString(), isNot(contains('secret_csrftoken_9999')));
    });

    test('11. tryParse returns null on invalid input', () {
      expect(InstagramCookieParser.tryParse('invalid junk text'), isNull);
      expect(InstagramCookieParser.tryParse(''), isNull);
      expect(InstagramCookieParser.tryParse(null), isNull);
    });
  });
}
