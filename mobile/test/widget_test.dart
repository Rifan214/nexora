import 'package:flutter_test/flutter_test.dart';

import 'package:nexora/main.dart';
import 'package:nexora/models/media_metadata.dart';

void main() {
  test('parses quality-based metadata responses', () {
    final qualities = [144, 240, 360, 480, 720, 1080, 1440, 2160]
        .map(
          (height) => {
            'label': height == 1080 ? '1080p Full HD' : '${height}p',
            'height': height,
            'extension': 'mp4',
            'estimated_filesize': height * 100000,
            'video_format_id': 'video-$height',
            'audio_format_id': 'audio',
          },
        )
        .toList();

    final response = MediaInfoResponse.fromJson({
      'success': true,
      'message': 'Request successful',
      'data': {
        'platform': 'youtube',
        'title': 'Example video',
        'webpage_url': 'https://www.youtube.com/watch?v=example',
        'extractor': 'youtube',
        'extractor_key': 'Youtube',
        'qualities': qualities,
      },
    });

    final metadata = response.data;

    expect(metadata, isNotNull);
    expect(metadata!.qualities, hasLength(8));
    expect(metadata.qualities.first.qualityHeight, 144);
    expect(metadata.qualities[5].qualityLabel, '1080p Full HD');
    expect(metadata.qualities.last.estimatedFilesize, 216000000);
  });

  testWidgets('shows the Nexora home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NexoraApp());

    expect(find.text('Nexora'), findsOneWidget);
    expect(find.text('Check Backend'), findsOneWidget);
  });
}
