import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final shareReceiverServiceProvider = Provider<ShareReceiverService>((ref) {
  return const ShareReceiverService();
});

class ShareReceiverService {
  const ShareReceiverService({
    MethodChannel methodChannel = const MethodChannel('com.example.nexora/share_receiver'),
    EventChannel eventChannel = const EventChannel('com.example.nexora/share_receiver_events'),
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  /// Retrieves initial shared text from cold start, if any.
  Future<String?> getInitialSharedText() async {
    try {
      final text = await _methodChannel.invokeMethod<String>('getInitialSharedText');
      if (text == null || text.trim().isEmpty) {
        return null;
      }
      return text.trim();
    } on PlatformException {
      return null;
    }
  }

  /// Broadcast stream of shared text arriving while app is running (warm/background).
  Stream<String> get sharedTextStream {
    return _eventChannel
        .receiveBroadcastStream()
        .where((event) => event != null)
        .map((event) => event.toString().trim())
        .where((text) => text.isNotEmpty);
  }
}
