import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexora/core/theme/app_theme.dart';
import 'package:nexora/models/media_metadata.dart';
import 'package:nexora/models/media_state.dart';
import 'package:nexora/providers/media_provider.dart';
import 'package:nexora/providers/share_receiver_provider.dart';
import 'package:nexora/screens/home_screen.dart';
import 'package:nexora/services/share_receiver_service.dart';

class _FakeShareReceiverService extends ShareReceiverService {
  _FakeShareReceiverService() : super();

  @override
  Future<String?> getInitialSharedText() async => null;

  @override
  Stream<String> get sharedTextStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeScreen consumes valid shared URL and enters input', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        shareReceiverServiceProvider.overrideWithValue(_FakeShareReceiverService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);
    expect(tester.widget<TextField>(inputFinder).controller?.text, isEmpty);

    // Simulate incoming shared URL event
    container.read(shareReceiverProvider.notifier).state =
        const SharedValidUrlEvent('https://youtu.be/shared123');

    // Pump to process frame and post-frame callback
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(inputFinder).controller?.text, 'https://youtu.be/shared123');
  });

  testWidgets('HomeScreen shows snackbar on invalid shared content without clearing input', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        shareReceiverServiceProvider.overrideWithValue(_FakeShareReceiverService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'https://existing.url/test');
    await tester.pump();

    // Simulate invalid shared text
    container.read(shareReceiverProvider.notifier).state =
        const SharedInvalidTextEvent('Just some plain message without link');

    await tester.pump();
    await tester.pumpAndSettle();

    // Feedback shown
    expect(find.text('No valid media URL found in shared content'), findsOneWidget);
    // Existing input preserved
    expect(tester.widget<TextField>(inputFinder).controller?.text, 'https://existing.url/test');
  });

  testWidgets('HomeScreen avoids redundant fetch if exact URL is already loaded', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        shareReceiverServiceProvider.overrideWithValue(_FakeShareReceiverService()),
      ],
    );
    addTearDown(container.dispose);

    // Seed MediaSuccess state
    container.read(mediaProvider.notifier).state = const MediaState.success(
      metadata: MediaMetadata(
        platform: 'youtube',
        title: 'Already Loaded Title',
        webpageUrl: 'https://youtu.be/alreadyLoaded',
        extractor: 'youtube',
        extractorKey: 'Youtube',
        videoQualities: [],
        audioOptions: [],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Already Loaded Title'), findsOneWidget);

    // Re-share exact same URL
    container.read(shareReceiverProvider.notifier).state =
        const SharedValidUrlEvent('https://youtu.be/alreadyLoaded');

    await tester.pump();
    await tester.pumpAndSettle();

    // MediaSuccess is preserved and not reset to MediaLoading
    expect(find.text('Already Loaded Title'), findsOneWidget);
    expect(container.read(mediaProvider), isA<MediaSuccess>());
  });
}
