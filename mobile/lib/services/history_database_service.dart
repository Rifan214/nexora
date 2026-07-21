import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/download_history_item.dart';

final historyDatabaseServiceProvider = Provider<HistoryDatabaseService>((ref) {
  final service = HistoryDatabaseService();
  ref.onDispose(() {
    unawaited(service.close());
  });
  return service;
});

class HistoryDatabaseService {
  static const _databaseName = 'nexora_history.db';
  static const _databaseVersion = 1;
  static const _tableName = 'download_history';

  Database? _database;

  Future<List<DownloadHistoryItem>> loadHistory() async {
    final database = await _open();
    final rows = await database.query(
      _tableName,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(DownloadHistoryItem.fromDatabase).toList();
  }

  Future<void> saveHistoryItem(DownloadHistoryItem item) async {
    final database = await _open();
    await database.insert(
      _tableName,
      item.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteHistoryItem(String id) async {
    final database = await _open();
    await database.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null) {
      await database.close();
    }
  }

  Future<Database> _open() async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return existingDatabase;
    }

    final databaseDirectory = await getDatabasesPath();
    final databasePath = path.join(databaseDirectory, _databaseName);
    final database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            thumbnail TEXT,
            media_type TEXT NOT NULL,
            selected_quality TEXT,
            local_file_path TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL,
            duration_seconds INTEGER
          )
        ''');
      },
    );
    _database = database;
    return database;
  }
}
