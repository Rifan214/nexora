import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexora/providers/share_receiver_provider.dart';
import 'package:nexora/services/share_receiver_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannelName = 'com.example.nexora/share_receiver';
  const eventChannelName = 'com.example.nexora/share_receiver_events';

  late List<MethodCall> methodLog;
  String? mockInitialText;
  StreamController<dynamic>? mockEventController;

  setUp(() {
    methodLog = [];
    mockInitialText = null;
    mockEventController = StreamController<dynamic>.broadcast();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), (call) async {
      methodLog.add(call);
      if (call.method == 'getInitialSharedText') {
        return mockInitialText;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel(eventChannelName),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          mockEventController?.stream.listen(
            (event) => events.success(event),
            onError: (error) => events.error(code: 'ERROR', message: error.toString()),
          );
        },
      ),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel(eventChannelName), null);
    mockEventController?.close();
  });

  group('ShareReceiverService direct unit tests', () {
    test('getInitialSharedText returns trimmed string when channel returns text', () async {
      mockInitialText = '  https://youtu.be/sample123  ';
      const service = ShareReceiverService();

      final result = await service.getInitialSharedText();

      expect(result, 'https://youtu.be/sample123');
      expect(methodLog.length, 1);
      expect(methodLog.first.method, 'getInitialSharedText');
    });

    test('getInitialSharedText returns null when channel returns null or whitespace', () async {
      mockInitialText = '   ';
      const service = ShareReceiverService();

      final result = await service.getInitialSharedText();

      expect(result, isNull);
    });

    test('getInitialSharedText handles PlatformException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodChannelName), (call) async {
        throw PlatformException(code: 'UNAVAILABLE', message: 'Failed');
      });

      const service = ShareReceiverService();
      final result = await service.getInitialSharedText();

      expect(result, isNull);
    });

    test('sharedTextStream emits trimmed strings and filters out empty values', () async {
      const service = ShareReceiverService();
      final emitted = <String>[];

      final sub = service.sharedTextStream.listen(emitted.add);

      mockEventController?.add('  https://x.com/post/1  ');
      mockEventController?.add('   '); // should be filtered out
      mockEventController?.add('Check out https://vt.tiktok.com/abc');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emitted, [
        'https://x.com/post/1',
        'Check out https://vt.tiktok.com/abc',
      ]);

      await sub.cancel();
    });
  });

  group('shareReceiverProvider integration tests', () {
    test('cold start: extracts valid URL from initial shared text', () async {
      mockInitialText = 'Watch this: https://youtu.be/coldStart123';

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = <SharedMediaIntentEvent?>[];
      container.listen(
        shareReceiverProvider,
        (_, next) => events.add(next),
        fireImmediately: true,
      );

      // Allow async initial text fetch to complete
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(events.whereType<SharedValidUrlEvent>(), isNotEmpty);
      final lastEvent = events.last as SharedValidUrlEvent;
      expect(lastEvent.url, 'https://youtu.be/coldStart123');
    });

    test('cold start: emits SharedInvalidTextEvent when initial text has no URL', () async {
      mockInitialText = 'Just some text without any link';

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = <SharedMediaIntentEvent?>[];
      container.listen(
        shareReceiverProvider,
        (_, next) => events.add(next),
        fireImmediately: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(events.whereType<SharedInvalidTextEvent>(), isNotEmpty);
      final lastEvent = events.last as SharedInvalidTextEvent;
      expect(lastEvent.rawText, 'Just some text without any link');
    });

    test('warm start: emits SharedValidUrlEvent on stream incoming event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = <SharedMediaIntentEvent?>[];
      container.listen(
        shareReceiverProvider,
        (_, next) => events.add(next),
        fireImmediately: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      mockEventController?.add('https://www.instagram.com/reel/warmStart/');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.whereType<SharedValidUrlEvent>(), isNotEmpty);
      final lastEvent = events.last as SharedValidUrlEvent;
      expect(lastEvent.url, 'https://www.instagram.com/reel/warmStart/');
    });

    test('warm start: emits SharedInvalidTextEvent on stream incoming non-URL text', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = <SharedMediaIntentEvent?>[];
      container.listen(
        shareReceiverProvider,
        (_, next) => events.add(next),
        fireImmediately: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      mockEventController?.add('Non URL warm message');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.whereType<SharedInvalidTextEvent>(), isNotEmpty);
      final lastEvent = events.last as SharedInvalidTextEvent;
      expect(lastEvent.rawText, 'Non URL warm message');
    });

    test('consumeEvent resets provider state to null allowing repeated events', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(shareReceiverProvider.notifier);

      mockEventController?.add('https://youtu.be/repeat1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(shareReceiverProvider), isA<SharedValidUrlEvent>());

      notifier.consumeEvent();
      expect(container.read(shareReceiverProvider), isNull);

      // Emitting again should set state again
      mockEventController?.add('https://youtu.be/repeat1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(shareReceiverProvider), isA<SharedValidUrlEvent>());
    });
  });
}
