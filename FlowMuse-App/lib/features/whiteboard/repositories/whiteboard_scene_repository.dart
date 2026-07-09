import 'package:sqflite_common/sqlite_api.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/storage/local_database.dart';
import '../collaboration/models/excalidraw_scene.dart';

abstract interface class WhiteboardSceneRepository {
  Future<String> loadScene(String noteId);

  Future<void> saveScene(String noteId, String content);
}

class InMemoryWhiteboardSceneRepository implements WhiteboardSceneRepository {
  final Map<String, String> _scenes = {};

  @override
  Future<String> loadScene(String noteId) async {
    return _scenes[noteId] ?? emptyExcalidrawSceneContent;
  }

  @override
  Future<void> saveScene(String noteId, String content) async {
    _scenes[noteId] = content;
  }
}

class SqliteWhiteboardSceneRepository implements WhiteboardSceneRepository {
  SqliteWhiteboardSceneRepository(this._openDatabase);

  final Future<Database> Function() _openDatabase;

  @override
  Future<String> loadScene(String noteId) async {
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardSceneRepository.loadScene start $noteId',
    );
    final db = await _openDatabase();
    final rows = await db.query(
      'note_scenes',
      columns: ['content'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    final raw = rows.isEmpty ? null : rows.first['content'] as String?;
    if (raw == null || raw.isEmpty) {
      debugPrint(
        '[FlowMuseCreateNote] WhiteboardSceneRepository.loadScene empty $noteId',
      );
      return emptyExcalidrawSceneContent;
    }
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardSceneRepository.loadScene hit '
      '$noteId length=${raw.length}',
    );
    return raw;
  }

  @override
  Future<void> saveScene(String noteId, String content) async {
    debugPrint(
      '[FlowMuseCreateNote] WhiteboardSceneRepository.saveScene '
      '$noteId length=${content.length}',
    );
    final db = await _openDatabase();
    await db.insert('note_scenes', {
      'note_id': noteId,
      'content': content,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

final defaultWhiteboardSceneRepository = SqliteWhiteboardSceneRepository(
  LocalDatabase.open,
);
