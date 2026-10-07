import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/share_receiver_service.dart';
import '../utils/shared_url_extractor.dart';

sealed class SharedMediaIntentEvent {
  const SharedMediaIntentEvent();
}

class SharedValidUrlEvent extends SharedMediaIntentEvent {
  const SharedValidUrlEvent(this.url);

  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedValidUrlEvent && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'SharedValidUrlEvent(url: $url)';
}

class SharedInvalidTextEvent extends SharedMediaIntentEvent {
  const SharedInvalidTextEvent(this.rawText);

  final String rawText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedInvalidTextEvent && other.rawText == rawText;

  @override
  int get hashCode => rawText.hashCode;

  @override
  String toString() => 'SharedInvalidTextEvent(rawText: $rawText)';
}

final shareReceiverProvider =
    NotifierProvider<ShareReceiverNotifier, SharedMediaIntentEvent?>(
  ShareReceiverNotifier.new,
);

class ShareReceiverNotifier extends Notifier<SharedMediaIntentEvent?> {
  StreamSubscription<String>? _streamSub;

  @override
  SharedMediaIntentEvent? build() {
    final service = ref.watch(shareReceiverServiceProvider);

    ref.onDispose(() {
      unawaited(_streamSub?.cancel());
      _streamSub = null;
    });

    _listen(service);

    return null;
  }

  void _listen(ShareReceiverService service) {
    _streamSub = service.sharedTextStream.listen((text) {
      _processRawSharedText(text);
    });

    unawaited(_fetchInitialText(service));
  }

  Future<void> _fetchInitialText(ShareReceiverService service) async {
    final initialText = await service.getInitialSharedText();
    if (initialText != null && initialText.isNotEmpty) {
      _processRawSharedText(initialText);
    }
  }

  void _processRawSharedText(String rawText) {
    final url = SharedUrlExtractor.extractUrl(rawText);
    if (url != null) {
      state = SharedValidUrlEvent(url);
    } else {
      if (rawText.trim().isNotEmpty) {
        state = SharedInvalidTextEvent(rawText.trim());
      }
    }
  }

  void consumeEvent() {
    state = null;
  }
}
