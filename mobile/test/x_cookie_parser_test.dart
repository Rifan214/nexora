import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/utils/x_cookie_parser.dart';

void main() {
  group('XCookieParser Tests', () {
    test('1. Netscape standard parses auth_token and ct0 from .x.com', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\ttoken_netscape_std\n'
          '.x.com\tTRUE\t/\tTRUE\t1790000000\tct0\tct0_netscape_std\n';

      final result = XCookieParser.parse(netscape);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'token_netscape_std');
      expect(result.ct0, 'ct0_netscape_std');
    });

    test('2. Netscape dengan #HttpOnly_ parses correctly without treating as comment', () {
      const netscapeHttpOnly =
          '# Netscape HTTP Cookie File\n'
          '#HttpOnly_.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\ttoken_httponly_flag\n'
          '#HttpOnly_.twitter.com\tTRUE\t/\tTRUE\t1790000000\tct0\tct0_httponly_flag\n';

      final result = XCookieParser.parse(netscapeHttpOnly);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'token_httponly_flag');
      expect(result.ct0, 'ct0_httponly_flag');
    });

    test('3. JSON export parses array of cookie objects', () {
      const jsonInput = '''
[
  {
    "domain": ".x.com",
    "name": "auth_token",
    "value": "token_json_123",
    "path": "/",
    "secure": true,
    "httpOnly": true
  },
  {
    "domain": ".twitter.com",
    "name": "ct0",
    "value": "ct0_json_456",
    "path": "/",
    "secure": true,
    "httpOnly": false
  }
]
''';

      final result = XCookieParser.parse(jsonInput);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'token_json_123');
      expect(result.ct0, 'ct0_json_456');
    });

    test('4. Raw Cookie header parses semi-colon separated cookies', () {
      const rawHeader =
          'Cookie: guest_id=v1%3A123; auth_token=token_raw_hdr; ct0=ct0_raw_hdr; personalization_id="v1_abc="';

      final result = XCookieParser.parse(rawHeader);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'token_raw_hdr');
      expect(result.ct0, 'ct0_raw_hdr');
    });

    test('5. Mixed X + non-X cookies isolates X credentials and ignores others', () {
      const mixedInput = '''
# Netscape HTTP Cookie File
.google.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tgoogle_token_ignored
.youtube.com\tTRUE\t/\tTRUE\t1790000000\tct0\tyoutube_csrf_ignored
.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tx_valid_token
.x.com\tTRUE\t/\tTRUE\t1790000000\ttwid\tu%3D12345678_ignored
.twitter.com\tTRUE\t/\tTRUE\t1790000000\tct0\tx_valid_ct0
.facebook.com\tTRUE\t/\tTRUE\t1790000000\tc_user\tfacebook_user_ignored
''';

      final result = XCookieParser.parse(mixedInput);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'x_valid_token');
      expect(result.ct0, 'x_valid_ct0');
    });

    test('6. Missing auth_token throws FormatException', () {
      const missingAuth =
          '.x.com\tTRUE\t/\tTRUE\t1790000000\tct0\tct0_only_token\n';

      expect(
        () => XCookieParser.parse(missingAuth),
        throwsA(isA<FormatException>()),
      );
      expect(XCookieParser.tryParse(missingAuth), isNull);
    });

    test('7. Missing ct0 throws FormatException', () {
      const missingCt0 =
          '.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tauth_only_token\n';

      expect(
        () => XCookieParser.parse(missingCt0),
        throwsA(isA<FormatException>()),
      );
      expect(XCookieParser.tryParse(missingCt0), isNull);
    });

    test('8. Empty credential values are rejected', () {
      const emptyValues = 'auth_token=  ; ct0=  ;';

      expect(
        () => XCookieParser.parse(emptyValues),
        throwsA(isA<FormatException>()),
      );
      expect(XCookieParser.tryParse(emptyValues), isNull);
    });

    test('9. Twitter domain (.twitter.com) is accepted', () {
      const twitterOnly =
          '.twitter.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\ttwitter_auth\n'
          'api.twitter.com\tTRUE\t/\tTRUE\t1790000000\tct0\ttwitter_ct0\n';

      final result = XCookieParser.parse(twitterOnly);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'twitter_auth');
      expect(result.ct0, 'twitter_ct0');
    });

    test('10. X domain (.x.com) is accepted', () {
      const xOnly =
          'x.com\tFALSE\t/\tTRUE\t1790000000\tauth_token\tx_auth_val\n'
          '.x.com\tTRUE\t/\tTRUE\t1790000000\tct0\tx_ct0_val\n';

      final result = XCookieParser.parse(xOnly);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'x_auth_val');
      expect(result.ct0, 'x_ct0_val');
    });

    test('11. Invalid Netscape rows are skipped gracefully without error', () {
      const malformedNetscape = '''
# Netscape HTTP Cookie File
corrupted_line_without_tabs
too\tfew\tcolumns
.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tvalid_auth_token_here
another_random_line
.x.com\tTRUE\t/\tTRUE\t1790000000\tct0\tvalid_ct0_token_here
''';

      final result = XCookieParser.parse(malformedNetscape);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'valid_auth_token_here');
      expect(result.ct0, 'valid_ct0_token_here');
    });

    test('12. Duplicate cookie names update/resolve safely without crashing', () {
      const duplicates = '''
.twitter.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\ttoken_first
.twitter.com\tTRUE\t/\tTRUE\t1790000000\tct0\tct0_first
.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\ttoken_updated
.x.com\tTRUE\t/\tTRUE\t1790000000\tct0\tct0_updated
''';

      final result = XCookieParser.parse(duplicates);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'token_updated');
      expect(result.ct0, 'ct0_updated');
    });

    test('13. Whitespace around tokens and lines is cleaned properly', () {
      const paddedHeader =
          '   auth_token   =   padded_auth_val   ;   ct0   =   padded_ct0_val   ';

      final result = XCookieParser.parse(paddedHeader);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'padded_auth_val');
      expect(result.ct0, 'padded_ct0_val');
    });

    test('14. Credential values containing special characters are preserved', () {
      const specialChars =
          'auth_token=tok_abc-123_456%2B%3D%3D#special; ct0=csrf_987-xyz~123\$%40';

      final result = XCookieParser.parse(specialChars);
      expect(result.isValid, isTrue);
      expect(result.authToken, 'tok_abc-123_456%2B%3D%3D#special');
      expect(result.ct0, 'csrf_987-xyz~123\$%40');
    });

    test('XCookieCredentials.toString() hides sensitive credentials', () {
      const credentials = XCookieCredentials(
        authToken: 'secret_token_value',
        ct0: 'secret_ct0_value',
      );

      final str = credentials.toString();
      expect(str, 'XCookieCredentials([PROTECTED])');
      expect(str.contains('secret_token_value'), isFalse);
      expect(str.contains('secret_ct0_value'), isFalse);
    });
  });
}
