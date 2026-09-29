import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexora/models/download_job.dart';
import 'package:nexora/models/download_preferences.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/widgets/settings_content.dart';

void main() {
  group('Hanime Metadata & Quality Parsing Tests', () {
    test('parses Hanime MediaInfoResponse with 720p/480p/360p and MP3 audio', () {
      final jsonResponse = {
        'success': true,
        'message': 'Request successful',
        'data': {
          'platform': 'hanime',
          'title': 'Terra Story 1',
          'uploader': 'Hanime Creator',
          'uploader_url': null,
          'thumbnail_url': 'https://webedn.hanime.tv/media/covers/terra-story-1.jpg',
          'duration_seconds': 1757,
          'webpage_url': 'https://hanime.tv/videos/hentai/terra-story-1',
          'extractor': 'hanime',
          'extractor_key': 'Hanime',
          'upload_date': '2024-09-01T00:00:00Z',
          'view_count': 125000,
          'like_count': 4500,
          'description': 'Terra Story Episode 1',
          'video_qualities': [
            {
              'label': '720p',
              'height': 720,
              'extension': 'mp4',
              'estimated_filesize': 250000000,
            },
            {
              'label': '480p',
              'height': 480,
              'extension': 'mp4',
              'estimated_filesize': 140000000,
            },
            {
              'label': '360p',
              'height': 360,
              'extension': 'mp4',
              'estimated_filesize': 80000000,
            },
          ],
          'audio_options': [
            {
              'label': 'MP3',
              'extension': 'mp3',
            },
          ],
        },
      };

      final response = MediaInfoResponse.fromJson(jsonResponse);
      expect(response.success, isTrue);

      final metadata = response.data;
      expect(metadata, isNotNull);
      expect(metadata!.platform, 'hanime');
      expect(metadata.title, 'Terra Story 1');
      expect(metadata.durationSeconds, 1757);
      expect(metadata.thumbnailUrl, contains('terra-story-1.jpg'));
      expect(metadata.webpageUrl, 'https://hanime.tv/videos/hentai/terra-story-1');

      // Quality checks
      expect(metadata.videoQualities, hasLength(3));
      expect(metadata.videoQualities.map((q) => q.height), [720, 480, 360]);
      expect(metadata.videoQualities.map((q) => q.label), ['720p', '480p', '360p']);
      expect(metadata.videoQualities.every((q) => q.extension == 'mp4'), isTrue);

      // Verify promotional 1080p is not present
      expect(metadata.videoQualities.any((q) => q.height == 1080), isFalse);

      // Audio checks
      expect(metadata.audioOptions, hasLength(1));
      expect(metadata.audioOptions.single.label, 'MP3');
      expect(metadata.audioOptions.single.extension, 'mp3');
    });

    test('parses Hanime API error responses safely without leaking internals', () {
      final errorResponse = {
        'success': false,
        'message': 'Invalid Hanime URL',
        'error': {
          'code': 'INVALID_HANIME_URL',
          'details': 'Use a public Hanime video URL in the form https://hanime.tv/videos/hentai/<slug>.',
        },
      };

      final response = MediaInfoResponse.fromJson(errorResponse);
      expect(response.success, isFalse);
      expect(response.data, isNull);
      expect(response.error, isNotNull);
      expect(response.error!.code, 'INVALID_HANIME_URL');
      expect(response.error!.details, contains('https://hanime.tv/videos/hentai/<slug>'));
      // Ensure no raw secrets, AES keys, or tokens in error message
      expect(response.message, isNot(contains('secret')));
      expect(response.message, isNot(contains('token')));
      expect(response.message, isNot(contains('signature')));
    });
  });

  group('Hanime Quality Preference Resolution Tests', () {
    final hanimeMetadata = MediaMetadata(
      platform: 'hanime',
      title: 'Terra Story 1',
      webpageUrl: 'https://hanime.tv/videos/hentai/terra-story-1',
      extractor: 'hanime',
      extractorKey: 'Hanime',
      videoQualities: const [
        VideoQuality(label: '720p', height: 720, extension: 'mp4'),
        VideoQuality(label: '480p', height: 480, extension: 'mp4'),
        VideoQuality(label: '360p', height: 360, extension: 'mp4'),
      ],
      audioOptions: const [
        AudioOption(label: 'MP3', extension: 'mp3'),
      ],
    );

    test('resolves 720p when preference is 720p', () {
      final selection = resolvePreferredMediaSelection(
        hanimeMetadata,
        const DownloadPreferences(videoQuality: VideoQualityPreference.p720),
      );
      expect(selection?.videoQuality?.height, 720);
      expect(selection?.mediaType, MediaDownloadType.video);
    });

    test('falls back to highest available (720p) when preference is 1080p', () {
      final selection = resolvePreferredMediaSelection(
        hanimeMetadata,
        const DownloadPreferences(videoQuality: VideoQualityPreference.p1080),
      );
      // Hanime max is 720p, so 1080p preference gracefully falls back to best available (720p)
      expect(selection?.videoQuality?.height, 720);
      expect(selection?.mediaType, MediaDownloadType.video);
    });

    test('resolves 480p when preference is 480p', () {
      final selection = resolvePreferredMediaSelection(
        hanimeMetadata,
        const DownloadPreferences(videoQuality: VideoQualityPreference.p480),
      );
      expect(selection?.videoQuality?.height, 480);
      expect(selection?.mediaType, MediaDownloadType.video);
    });

    test('resolves best available (720p) under bestAvailable preference', () {
      final selection = resolvePreferredMediaSelection(
        hanimeMetadata,
        const DownloadPreferences(videoQuality: VideoQualityPreference.bestAvailable),
      );
      expect(selection?.videoQuality?.height, 720);
    });

    test('resolves audio selection when preferred download type is audio', () {
      final selection = resolvePreferredMediaSelection(
        hanimeMetadata,
        const DownloadPreferences(
          videoQuality: VideoQualityPreference.askEveryTime,
          audio: AudioPreference.mp3,
        ),
      );
      expect(selection?.mediaType, MediaDownloadType.audio);
    });
  });

  group('Hanime Download Job Request Serialization Tests', () {
    test('serializes Hanime video download request with quality_height', () {
      final request = DownloadJobRequest(
        url: 'https://hanime.tv/videos/hentai/terra-story-1',
        mediaType: MediaDownloadType.video.requestValue,
        qualityHeight: 720,
      );

      final json = request.toJson();
      expect(json['url'], 'https://hanime.tv/videos/hentai/terra-story-1');
      expect(json['media_type'], 'video');
      expect(json['quality_height'], 720);
      expect(json.containsKey('format_id'), isFalse);
    });

    test('serializes Hanime audio download request without quality_height', () {
      final request = DownloadJobRequest(
        url: 'https://hanime.tv/videos/hentai/terra-story-1',
        mediaType: MediaDownloadType.audio.requestValue,
      );

      final json = request.toJson();
      expect(json['url'], 'https://hanime.tv/videos/hentai/terra-story-1');
      expect(json['media_type'], 'audio');
      expect(json.containsKey('quality_height'), isFalse);
    });
  });

  group('Hanime Settings Platform Support UI Test', () {
    testWidgets('renders Hanime in supported platforms list with Available status', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SettingsContent(),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Hanime'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('TikTok'), findsOneWidget);
    });
  });
}
