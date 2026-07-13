import 'dart:io';

import 'package:flow_muse/features/whiteboard/repositories/whiteboard_scene_repository.dart';
import 'package:flow_muse/shared/storage/scene_content_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('大场景保存时 SQLite 只保留小型引用', () async {
    final sceneDirectory = await Directory.systemTemp.createTemp(
      'flowmuse-scenes-',
    );
    addTearDown(() => sceneDirectory.delete(recursive: true));
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute('''
      CREATE TABLE note_scenes (
        note_id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    final repository = SqliteWhiteboardSceneRepository(
      () async => database,
      sceneContentStore: SceneContentStore(rootPath: sceneDirectory.path),
    );
    final content = '{"files":"${'x' * (2 * 1024 * 1024)}"}';

    const noteId = 'note-00000000-0000-0000-0000-000000000000';
    await repository.saveScene(noteId, content);

    final row = (await database.query('note_scenes')).single;
    expect((row['content'] as String).length, lessThan(1024 * 1024));
    expect(await repository.loadScene(noteId), content);
  });
}
