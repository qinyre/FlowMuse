import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/storage/local_database.dart';

class LocalBackupRepository {
  LocalBackupRepository(this._openDatabase);

  static const version = 2;

  final Future<Database> Function() _openDatabase;

  Future<Map<String, Object?>> exportBackup() async {
    final db = await _openDatabase();
    return {
      'version': version,
      'createdAt': DateTime.now().toIso8601String(),
      'database': {
        'notebooks': await db.query('notebooks', orderBy: 'sort_order ASC'),
        'tags': await db.query('tags', orderBy: 'sort_order ASC'),
        'notes': await db.query('notes', orderBy: 'updated_at DESC'),
        'noteTags': await db.query('note_tags'),
        'noteScenes': await db.query('note_scenes'),
        'localSettings': await db.query('local_settings'),
      },
    };
  }

  Future<void> importBackup(Map<String, Object?> payload) async {
    if (payload['version'] != version) {
      throw const FormatException('备份版本不正确');
    }
    final databasePayload = payload['database'];
    if (databasePayload is! Map) {
      throw const FormatException('备份文件格式不正确');
    }

    final db = await _openDatabase();
    await db.transaction((txn) async {
      await _clearDatabase(txn);
      await _insertRows(txn, 'notebooks', databasePayload['notebooks']);
      await _insertRows(txn, 'tags', databasePayload['tags']);
      await _insertRows(txn, 'notes', databasePayload['notes']);
      await _insertRows(txn, 'note_tags', databasePayload['noteTags']);
      await _insertRows(txn, 'note_scenes', databasePayload['noteScenes']);
      await _insertRows(
        txn,
        'local_settings',
        databasePayload['localSettings'],
      );
    });
  }

  Future<void> _clearDatabase(Transaction txn) async {
    await txn.delete('note_tags');
    await txn.delete('note_scenes');
    await txn.delete('notes');
    await txn.delete('notebooks');
    await txn.delete('tags');
    await txn.delete('local_settings');
  }

  Future<void> _insertRows(
    Transaction txn,
    String table,
    Object? rawRows,
  ) async {
    if (rawRows is! List) {
      throw const FormatException('备份文件格式不正确');
    }
    for (final rawRow in rawRows) {
      if (rawRow is! Map) {
        throw const FormatException('备份文件格式不正确');
      }
      await txn.insert(table, {
        for (final entry in rawRow.entries) entry.key.toString(): entry.value,
      });
    }
  }
}

final defaultLocalBackupRepository = LocalBackupRepository(LocalDatabase.open);
