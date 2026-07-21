import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_history_item.dart';
import '../services/history_database_service.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(historyDatabaseServiceProvider));
});

class HistoryRepository {
  const HistoryRepository(this._databaseService);

  final HistoryDatabaseService _databaseService;

  Future<List<DownloadHistoryItem>> loadHistory() {
    return _databaseService.loadHistory();
  }

  Future<void> saveHistoryItem(DownloadHistoryItem item) {
    return _databaseService.saveHistoryItem(item);
  }

  Future<void> deleteHistoryItem(String id) {
    return _databaseService.deleteHistoryItem(id);
  }
}
