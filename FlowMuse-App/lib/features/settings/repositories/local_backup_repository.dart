import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/storage/local_database.dart';
import '../../../shared/storage/scene_content_store.dart';

class LocalBackupRepository {
  LocalBackupRepository(
    this._openDatabase, {
    SceneContentStore? sceneContentStore,
  }) : _sceneContentStore = sceneContentStore ?? SceneContentStore();

  static const version = 2;

  final Future<Database> Function() _openDatabase;
  final SceneContentStore _sceneContentStore;

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
        'noteScenes': [
          for (final row in await db.query('note_scenes'))
            {...row, 'content': await _resolveContent(row['content'])},
        ],
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

    final sceneRows = await _prepareSceneRows(databasePayload['noteScenes']);
    final db = await _openDatabase();
    await db.transaction((txn) async {
      await _clearDatabase(txn);
      await _insertRows(txn, 'notebooks', databasePayload['notebooks']);
      await _insertRows(txn, 'tags', databasePayload['tags']);
      await _insertRows(txn, 'notes', databasePayload['notes']);
      await _insertRows(txn, 'note_tags', databasePayload['noteTags']);
      await _insertRows(txn, 'note_scenes', sceneRows);
      await _insertRows(
        txn,
        'local_settings',
        databasePayload['localSettings'],
      );
    });
  }

  Future<String> _resolveContent(Object? raw) async {
    if (raw is! String) throw const FormatException('备份场景内容格式不正确');
    if (!_sceneContentStore.isReference(raw)) return raw;
    final content = await _sceneContentStore.read(raw);
    if (content == null || _sceneContentStore.isReference(content)) {
      throw const FormatException('白板场景文件缺失或无效，无法完成备份或恢复');
    }
    return content;
  }

  Future<List<Map<String, Object?>>> _prepareSceneRows(Object? rawRows) async {
    if (rawRows is! List) throw const FormatException('备份文件格式不正确');
    final rows = <Map<String, Object?>>[];
    for (final rawRow in rawRows) {
      if (rawRow is! Map || rawRow['note_id'] is! String) {
        throw const FormatException('备份场景格式不正确');
      }
      final content = await _resolveContent(rawRow['content']);
      // Stage under a new name so a failed DB transaction leaves live files intact.
      final stored = content.length > SceneContentStore.inlineContentLimit
          ? await _sceneContentStore.write(
              '${rawRow['note_id']}-restore-${const Uuid().v4()}',
              content,
            )
          : content;
      rows.add({...Map<String, Object?>.from(rawRow), 'content': stored});
    }
    return rows;
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
        for (final entry in rawRow.entries)
          entry.key.toString():
              table == 'notes' &&
                  entry.key == 'cover_thumbnail' &&
                  entry.value is List
              ? Uint8List.fromList((entry.value as List).cast<int>())
              : entry.value,
      });
    }
  }
}

final defaultLocalBackupRepository = LocalBackupRepository(LocalDatabase.open);
