import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_history_item.dart';
import '../repositories/history_repository.dart';

final downloadHistoryProvider =
    AsyncNotifierProvider<DownloadHistoryController, List<DownloadHistoryItem>>(
      DownloadHistoryController.new,
    );

class DownloadHistoryController extends AsyncNotifier<List<DownloadHistoryItem>> {
  @override
  FutureOr<List<DownloadHistoryItem>> build() {
    return ref.read(historyRepositoryProvider).loadHistory();
  }

  Future<void> addCompletedDownload(DownloadHistoryItem item) async {
    await _saveAndReload(() {
      return ref.read(historyRepositoryProvider).saveHistoryItem(item);
    });
  }

  Future<void> deleteHistoryItem(String id) async {
    await _saveAndReload(() {
      return ref.read(historyRepositoryProvider).deleteHistoryItem(id);
    });
  }

  Future<void> _saveAndReload(Future<void> Function() operation) async {
    final previousItems = state.valueOrNull;

    try {
      await operation();
      final items = await ref.read(historyRepositoryProvider).loadHistory();
      state = AsyncValue.data(items);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Unable to update download history: $error');
      }
      if (previousItems != null) {
        state = AsyncValue.data(previousItems);
        return;
      }
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}
