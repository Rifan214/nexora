import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/utils/tiktok_cookie_parser.dart';

void main() {
  group('TikTokCookieParser Tests', () {
    test('1. Netscape standard parses sessionid and sid_tt from .tiktok.com', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\ttok_sessionid_std\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsid_tt\tsid_tt_std\n';

      final result = TikTokCookieParser.parse(netscape);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'tok_sessionid_std');
      expect(result.sidTt, 'sid_tt_std');
    });

    test('2. Netscape with #HttpOnly_ parses correctly', () {
      const netscapeHttpOnly =
          '# Netscape HTTP Cookie File\n'
          '#HttpOnly_.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\ttok_httponly_flag\n'
          '#HttpOnly_.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsid_tt\tsid_tt_flag\n';

      final result = TikTokCookieParser.parse(netscapeHttpOnly);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'tok_httponly_flag');
      expect(result.sidTt, 'sid_tt_flag');
    });

    test('3. JSON export parses array of cookie objects', () {
      const jsonInput = '''
[
  {
    "domain": ".tiktok.com",
    "name": "sessionid",
    "value": "sessionid_json_123",
    "path": "/",
    "secure": true,
    "httpOnly": true
  },
  {
    "domain": ".tiktok.com",
    "name": "sid_tt",
    "value": "sid_tt_json_456",
    "path": "/",
    "secure": true,
    "httpOnly": false
  }
]
''';

      final result = TikTokCookieParser.parse(jsonInput);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'sessionid_json_123');
      expect(result.sidTt, 'sid_tt_json_456');
    });

    test('4. Raw Cookie header parses semi-colon separated cookies', () {
      const rawHeader =
          'Cookie: ttwid=123; sessionid=sessionid_raw_hdr; sid_tt=sid_tt_raw_hdr; msToken=abc';

      final result = TikTokCookieParser.parse(rawHeader);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'sessionid_raw_hdr');
      expect(result.sidTt, 'sid_tt_raw_hdr');
    });

    test('5. Mixed TikTok + X cookies isolates TikTok credentials and ignores others', () {
      const mixedInput = '''
# Netscape HTTP Cookie File
.x.com\tTRUE\t/\tTRUE\t1790000000\tauth_token\tx_auth_token_ignored
.twitter.com\tTRUE\t/\tTRUE\t1790000000\tct0\tx_ct0_ignored
.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\ttiktok_valid_sessionid
.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsid_tt\ttiktok_valid_sid_tt
.youtube.com\tTRUE\t/\tTRUE\t1790000000\tVISITOR_INFO1_LIVE\tyt_cookie_ignored
''';

      final result = TikTokCookieParser.parse(mixedInput);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'tiktok_valid_sessionid');
      expect(result.sidTt, 'tiktok_valid_sid_tt');
    });

    test('6. Supports sessionid_ss alias when sessionid is absent', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid_ss\ttok_sessionid_ss_val\n';

      final result = TikTokCookieParser.parse(netscape);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'tok_sessionid_ss_val');
      expect(result.sidTt, isNull);
    });

    test('7. Optional sid_tt can be omitted', () {
      const netscape =
          '# Netscape HTTP Cookie File\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\ttok_only_sessionid\n';

      final result = TikTokCookieParser.parse(netscape);
      expect(result.isValid, isTrue);
      expect(result.sessionid, 'tok_only_sessionid');
      expect(result.sidTt, isNull);
    });

    test('8. Missing sessionid throws FormatException without leaking credentials', () {
      const invalidInput =
          '# Netscape HTTP Cookie File\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsid_tt\tonly_sid_tt_present\n';

      expect(
        () => TikTokCookieParser.parse(invalidInput),
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
        () => TikTokCookieParser.parse('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('10. Sensitive tokens are masked in toString()', () {
      const creds = TikTokCookieCredentials(
        sessionid: 'secret_sessionid_12345',
        sidTt: 'secret_sid_tt_67890',
      );
      expect(creds.toString(), equals('TikTokCookieCredentials([PROTECTED])'));
      expect(creds.toString(), isNot(contains('secret_sessionid_12345')));
      expect(creds.toString(), isNot(contains('secret_sid_tt_67890')));
    });

    test('11. tryParse returns null on invalid input', () {
      expect(TikTokCookieParser.tryParse('invalid junk text'), isNull);
      expect(TikTokCookieParser.tryParse(''), isNull);
      expect(TikTokCookieParser.tryParse(null), isNull);
    });
  });
}
