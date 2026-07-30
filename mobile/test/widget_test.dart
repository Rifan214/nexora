import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexora/main.dart';
import 'package:nexora/models/download_history_item.dart';
import 'package:nexora/models/download_job.dart';
import 'package:nexora/models/batch_import.dart';
import 'package:nexora/models/download_preferences.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/providers/batch_import_provider.dart';
import 'package:nexora/providers/playlist_import_provider.dart';

void main() {
  test('round trips locally persisted download history fields', () {
    final createdAt = DateTime(2026, 7, 21, 10, 30);
    final historyItem = DownloadHistoryItem(
      id: 'history-item-1',
      title: 'Example video',
      thumbnailUrl: 'https://example.com/thumbnail.jpg',
      mediaType: MediaDownloadType.video,
      selectedQuality: '1080p Full HD',
      localFilePath: '/downloads/example-video.mp4',
      createdAt: createdAt,
      durationSeconds: 125,
    );

    final restoredItem = DownloadHistoryItem.fromDatabase(
      historyItem.toDatabase(),
    );

    expect(restoredItem.id, historyItem.id);
    expect(restoredItem.title, historyItem.title);
    expect(restoredItem.thumbnailUrl, historyItem.thumbnailUrl);
    expect(restoredItem.mediaType, MediaDownloadType.video);
    expect(restoredItem.selectedQuality, historyItem.selectedQuality);
    expect(restoredItem.localFilePath, historyItem.localFilePath);
    expect(restoredItem.createdAt, createdAt);
    expect(restoredItem.durationSeconds, 125);
  });

  test('parses final media metadata responses', () {
    final videoQualities = [144, 240, 360, 480, 720, 1080, 1440, 2160]
        .map(
          (height) => {
            'label': height == 1080 ? '1080p Full HD' : '${height}p',
            'height': height,
            'extension': 'mp4',
            'estimated_filesize': height * 100000,
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
        'video_qualities': videoQualities,
        'audio_options': [
          {
            'label': 'MP3',
            'extension': 'mp3',
          },
        ],
      },
    });

    final metadata = response.data;

    expect(metadata, isNotNull);
    expect(metadata!.videoQualities, hasLength(8));
    expect(metadata.videoQualities.first.height, 144);
    expect(metadata.videoQualities[5].label, '1080p Full HD');
    expect(metadata.videoQualities.last.estimatedFilesize, 216000000);
    expect(metadata.audioOptions, hasLength(1));
    expect(metadata.audioOptions.single.label, 'MP3');
    expect(metadata.audioOptions.single.extension, 'mp3');
  });

  test('serializes an audio download request without a video quality', () {
    final request = DownloadJobRequest(
      url: 'https://www.youtube.com/watch?v=example',
      mediaType: MediaDownloadType.audio.requestValue,
    );

    expect(request.toJson(), {
      'url': 'https://www.youtube.com/watch?v=example',
      'media_type': 'audio',
    });
  });

  test('serializes a video download request with its selected quality', () {
    final request = DownloadJobRequest(
      url: 'https://www.youtube.com/watch?v=example',
      mediaType: MediaDownloadType.video.requestValue,
      qualityHeight: 1080,
    );

    expect(request.toJson(), {
      'url': 'https://www.youtube.com/watch?v=example',
      'media_type': 'video',
      'quality_height': 1080,
    });
  });

  test('rejects malformed batch URL lines before analysis', () {
    final result = validateBatchUrlLines([
      'https://www.youtube.com/watch?v=valid',
      'prefix https://www.youtube.com/watch?v=leading-characters',
      'https://www.youtube.com/watch?v=first https://youtu.be/second',
      'https://www.youtube.com/watch?v=valid https://example.com/trailing',
      'ftp://example.com/file',
      'https://',
    ]);

    expect(result.validUrls, ['https://www.youtube.com/watch?v=valid']);
    expect(result.invalidUrls, hasLength(5));
    expect(result.invalidUrls.map((item) => item.lineNumber), [2, 3, 4, 5, 6]);
  });

  test('accepts normal and playlist batch URLs', () {
    final result = validateBatchUrlLines([
      '',
      '  https://youtu.be/example?si=tracking  ',
      'https://www.youtube.com/playlist?list=PLexample&si=tracking',
    ]);

    expect(result.invalidUrls, isEmpty);
    expect(result.validUrls, [
      'https://youtu.be/example?si=tracking',
      'https://www.youtube.com/playlist?list=PLexample&si=tracking',
    ]);
  });

  test('normalizes mixed TikTok and YouTube batch URLs without duplicates', () {
    final urls = normalizeBatchUrls([
      'https://www.tiktok.com/@nexora/video/12345',
      'https://www.youtube.com/watch?v=example',
      'https://www.tiktok.com/@nexora/video/12345',
    ]);

    expect(urls, [
      'https://www.tiktok.com/@nexora/video/12345',
      'https://www.youtube.com/watch?v=example',
    ]);
  });

  test('applies TikTok quality preferences with a best-quality fallback', () {
    final metadata = MediaMetadata(
      platform: 'tiktok',
      title: 'TikTok video',
      webpageUrl: 'https://www.tiktok.com/@nexora/video/12345',
      extractor: 'TikTok',
      extractorKey: 'TikTok',
      videoQualities: const [
        VideoQuality(label: '720p HD', height: 720, extension: 'mp4'),
      ],
    );

    final preferred = resolvePreferredMediaSelection(
      metadata,
      const DownloadPreferences(videoQuality: VideoQualityPreference.p1080),
    );
    final bestAvailable = resolvePreferredMediaSelection(
      metadata,
      const DownloadPreferences(
        videoQuality: VideoQualityPreference.bestAvailable,
      ),
    );

    expect(preferred?.videoQuality?.height, 720);
    expect(bestAvailable?.videoQuality?.height, 720);
  });

  test('retains batch URLs until Clear Batch is requested', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(batchImportProvider.notifier);
    controller.updateUrlInput('https://www.youtube.com/watch?v=batch-item');

    expect(
      container.read(batchImportProvider).urlInput,
      'https://www.youtube.com/watch?v=batch-item',
    );
    expect(container.read(batchImportProvider).hasSession, isTrue);

    controller.clearBatch();

    expect(container.read(batchImportProvider).hasSession, isFalse);
  });

  test('retains playlist URL until the batch workspace is cleared', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(playlistImportProvider.notifier);
    controller.updateUrl('https://www.youtube.com/playlist?list=example');

    expect(
      container.read(playlistImportProvider).url,
      'https://www.youtube.com/playlist?list=example',
    );

    controller.clear();

    expect(container.read(playlistImportProvider).url, isEmpty);
  });

  testWidgets('shows the Nexora home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NexoraApp());

    expect(find.text('Nexora'), findsOneWidget);
    expect(find.text('Ready to fetch.'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
