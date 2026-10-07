import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/utils/shared_url_extractor.dart';

void main() {
  group('SharedUrlExtractor tests', () {
    test('returns null for null, empty, and whitespace strings', () {
      expect(SharedUrlExtractor.extractUrl(null), isNull);
      expect(SharedUrlExtractor.extractUrl(''), isNull);
      expect(SharedUrlExtractor.extractUrl('   '), isNull);
      expect(SharedUrlExtractor.extractUrl('\n\t\r'), isNull);
    });

    test('extracts clean YouTube URL', () {
      const input = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('extracts youtu.be short URL', () {
      const input = 'https://youtu.be/dQw4w9WgXcQ';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('extracts YouTube URL embedded in a sentence', () {
      const input = 'Check out this awesome video https://youtu.be/dQw4w9WgXcQ it is great';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('extracts TikTok URL with surrounding text and hashtags', () {
      const input = "Check out user's video! #fyp #viral https://vt.tiktok.com/ZSjX1234/ watch now";
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://vt.tiktok.com/ZSjX1234/',
      );
    });

    test('extracts standard TikTok web URL', () {
      const input = 'https://www.tiktok.com/@creator/video/7123456789012345678?is_from_webapp=1';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://www.tiktok.com/@creator/video/7123456789012345678?is_from_webapp=1',
      );
    });

    test('extracts X (Twitter) URL with tracking query params', () {
      const input = 'Breaking news: https://x.com/flutterdev/status/1234567890?s=20 via @flutterdev';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://x.com/flutterdev/status/1234567890?s=20',
      );
    });

    test('extracts Instagram reel and post URL', () {
      const reel = 'https://www.instagram.com/reel/Cxyz123/?igsh=abcdef';
      expect(
        SharedUrlExtractor.extractUrl(reel),
        'https://www.instagram.com/reel/Cxyz123/?igsh=abcdef',
      );

      const post = 'Look at this photo: https://www.instagram.com/p/Cxyz789/ on Instagram';
      expect(
        SharedUrlExtractor.extractUrl(post),
        'https://www.instagram.com/p/Cxyz789/',
      );
    });

    test('extracts URL across multiple lines', () {
      const input = '''
Awesome tutorial here:
https://www.youtube.com/watch?v=multiLine123
Enjoy watching!
''';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://www.youtube.com/watch?v=multiLine123',
      );
    });

    test('strips trailing punctuation like dots, commas, exclamation marks, semicolons', () {
      expect(
        SharedUrlExtractor.extractUrl('Watch this video https://youtu.be/abc.'),
        'https://youtu.be/abc',
      );
      expect(
        SharedUrlExtractor.extractUrl('Check this link https://youtu.be/abc,'),
        'https://youtu.be/abc',
      );
      expect(
        SharedUrlExtractor.extractUrl('Amazing track https://youtu.be/abc!'),
        'https://youtu.be/abc',
      );
      expect(
        SharedUrlExtractor.extractUrl('First part: https://youtu.be/abc; second part: ...'),
        'https://youtu.be/abc',
      );
      expect(
        SharedUrlExtractor.extractUrl('Link: https://youtu.be/abc>'),
        'https://youtu.be/abc',
      );
      expect(
        SharedUrlExtractor.extractUrl('[Link https://youtu.be/abc]'),
        'https://youtu.be/abc',
      );
    });

    test('strips trailing closing parenthesis when no opening parenthesis exists in candidate', () {
      expect(
        SharedUrlExtractor.extractUrl('(see https://youtu.be/abc)'),
        'https://youtu.be/abc',
      );
    });

    test('preserves legitimate balanced parentheses in URL paths', () {
      expect(
        SharedUrlExtractor.extractUrl('https://example.com/wiki/Title_(1999)'),
        'https://example.com/wiki/Title_(1999)',
      );
    });

    test('accepts http as well as https schemes', () {
      expect(
        SharedUrlExtractor.extractUrl('http://my-local-server.lan/video.mp4'),
        'http://my-local-server.lan/video.mp4',
      );
    });

    test('rejects non-http/https schemes such as ftp, file, or custom schemes', () {
      expect(SharedUrlExtractor.extractUrl('ftp://ftp.example.com/video.mp4'), isNull);
      expect(SharedUrlExtractor.extractUrl('nexora://download?url=123'), isNull);
      expect(SharedUrlExtractor.extractUrl('file:///sdcard/Download/video.mp4'), isNull);
      expect(SharedUrlExtractor.extractUrl('mailto:test@example.com'), isNull);
    });

    test('rejects plain text containing no URLs', () {
      expect(SharedUrlExtractor.extractUrl('Just some text shared from chat'), isNull);
      expect(SharedUrlExtractor.extractUrl('1234567890'), isNull);
      expect(SharedUrlExtractor.extractUrl('Hello, world!'), isNull);
    });

    test('rejects malformed URLs without valid host', () {
      expect(SharedUrlExtractor.extractUrl('http://'), isNull);
      expect(SharedUrlExtractor.extractUrl('https://'), isNull);
      expect(SharedUrlExtractor.extractUrl('https:///no-host-here'), isNull);
    });

    test('extracts the first valid URL when multiple URLs are present in text', () {
      const input = 'First https://youtu.be/firstLink and second https://youtu.be/secondLink';
      expect(
        SharedUrlExtractor.extractUrl(input),
        'https://youtu.be/firstLink',
      );
    });
  });
}
