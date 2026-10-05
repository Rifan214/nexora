import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/tracked_download.dart';
import 'package:nexora/widgets/download_progress_status.dart';
import 'package:nexora/widgets/downloads_content.dart';

void main() {
  group('friendlyDownloadStatus unit tests', () {
    test('A: pending + 0 returns "Preparing..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'pending',
        backendProgress: 0,
        isSavingToDevice: false,
      );
      expect(status, 'Preparing...');
    });

    test('null or empty backendStatus returns "Preparing..."', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: null,
          backendProgress: 0,
          isSavingToDevice: false,
        ),
        'Preparing...',
      );
      expect(
        friendlyDownloadStatus(
          backendStatus: '   ',
          backendProgress: 0,
          isSavingToDevice: false,
        ),
        'Preparing...',
      );
    });

    test('B: processing + 0 returns "Preparing download..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'processing',
        backendProgress: 0,
        isSavingToDevice: false,
      );
      expect(status, 'Preparing download...');
    });

    test('processing + negative progress returns "Preparing download..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'processing',
        backendProgress: -5,
        isSavingToDevice: false,
      );
      expect(status, 'Preparing download...');
    });

    test('C: processing + 1 returns "Downloading media..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'processing',
        backendProgress: 1,
        isSavingToDevice: false,
      );
      expect(status, 'Downloading media...');
    });

    test('D: processing + 25 returns "Downloading media..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'processing',
        backendProgress: 25,
        isSavingToDevice: false,
      );
      expect(status, 'Downloading media...');
    });

    test('E: processing + 100 returns "Processing media..."', () {
      final status = friendlyDownloadStatus(
        backendStatus: 'processing',
        backendProgress: 100,
        isSavingToDevice: false,
      );
      expect(status, 'Processing media...');
    });

    test('F: isSavingToDevice returns "Saving to device..." regardless of status', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'processing',
          backendProgress: 50,
          isSavingToDevice: true,
        ),
        'Saving to device...',
      );
      expect(
        friendlyDownloadStatus(
          backendStatus: 'completed',
          backendProgress: 100,
          isSavingToDevice: true,
        ),
        'Saving to device...',
      );
    });

    test('G: queued returns "Waiting"', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'queued',
          backendProgress: 0,
          isSavingToDevice: false,
        ),
        'Waiting',
      );
    });

    test('G: cancelling returns "Cancelling..."', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'cancelling',
          backendProgress: 50,
          isSavingToDevice: false,
        ),
        'Cancelling...',
      );
    });

    test('G: cancelled returns "Cancelled"', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'cancelled',
          backendProgress: 50,
          isSavingToDevice: false,
        ),
        'Cancelled',
      );
    });

    test('G: completed returns "Saving to device..."', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'completed',
          backendProgress: 100,
          isSavingToDevice: false,
        ),
        'Saving to device...',
      );
    });

    test('unknown status falls through to "Processing media..."', () {
      expect(
        friendlyDownloadStatus(
          backendStatus: 'some_unknown_status',
          backendProgress: 50,
          isSavingToDevice: false,
        ),
        'Processing media...',
      );
    });
  });

  group('Download percentage visibility widget tests', () {
    const dummyMetadata = MediaMetadata(
      platform: 'youtube',
      title: 'Sample Download Title',
      webpageUrl: 'https://www.youtube.com/watch?v=sample',
      extractor: 'youtube',
      extractorKey: 'Youtube',
      videoQualities: [
        VideoQuality(label: '720p', height: 720, extension: 'mp4'),
      ],
      audioOptions: [],
    );

    testWidgets('preparation (pending, 0%) does not display "0%" text', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const download = TrackedDownload(
        jobId: 'test-job-prep',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        status: 'pending',
        progress: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsContent(
              downloads: const [download],
              onCancelDownload: (_) {},
              onClearCompleted: () {},
              onClearFailed: () {},
              onRetryFailedDownload: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Preparing...'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('preparation (processing, 0%) does not display "0%" text', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const download = TrackedDownload(
        jobId: 'test-job-prep-proc',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        status: 'processing',
        progress: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsContent(
              downloads: const [download],
              onCancelDownload: (_) {},
              onClearCompleted: () {},
              onClearFailed: () {},
              onRetryFailedDownload: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Preparing download...'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('actual download (processing, 25%) displays "25%" text', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const download = TrackedDownload(
        jobId: 'test-job-downloading',
        metadata: dummyMetadata,
        mediaType: MediaDownloadType.video,
        status: 'processing',
        progress: 25,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsContent(
              downloads: const [download],
              onCancelDownload: (_) {},
              onClearCompleted: () {},
              onClearFailed: () {},
              onRetryFailedDownload: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Downloading media...'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });
  });
}
