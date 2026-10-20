import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/settings/repositories/local_backup_repository.dart';
import 'package:flow_muse/features/whiteboard/repositories/whiteboard_scene_repository.dart';
import 'package:flow_muse/shared/storage/scene_content_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('恢复时将 JSON 中的封面字节数组还原为 SQLite BLOB', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE notebooks (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE tags (id TEXT PRIMARY KEY)');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        cover_thumbnail BLOB
      )
    ''');
    await db.execute('CREATE TABLE note_tags (note_id TEXT, tag_id TEXT)');
    await db.execute('CREATE TABLE note_scenes (note_id TEXT, content TEXT)');
    await db.execute('CREATE TABLE local_settings (key TEXT, value TEXT)');
    final repository = LocalBackupRepository(() async => db);
    final payload =
        jsonDecode(
              jsonEncode({
                'version': LocalBackupRepository.version,
                'database': {
                  'notebooks': <Object?>[],
                  'tags': <Object?>[],
                  'notes': [
                    {
                      'id': 'note-1',
                      'cover_thumbnail': Uint8List.fromList([0, 127, 255]),
                    },
                  ],
                  'noteTags': <Object?>[],
                  'noteScenes': <Object?>[],
                  'localSettings': <Object?>[],
                },
              }),
            )
            as Map<String, Object?>;

    await repository.importBackup(payload);

    expect(
      (await db.query('notes')).single['cover_thumbnail'],
      Uint8List.fromList([0, 127, 255]),
    );
  });

  test('大场景备份携带正文，在没有原场景文件的新设备恢复后可打开', () async {
    final sourceDb = await _database();
    final targetDb = await _database();
    final sourceFiles = _SceneFiles();
    final targetFiles = _SceneFiles();
    final content = jsonEncode({'files': 'x' * (2 * 1024 * 1024)});
    final source = SqliteWhiteboardSceneRepository(
      () async => sourceDb,
      sceneContentStore: sourceFiles,
    );
    await source.saveScene('note-1', content);
    final backup =
        jsonDecode(
              jsonEncode(
                await LocalBackupRepository(
                  () async => sourceDb,
                  sceneContentStore: sourceFiles,
                ).exportBackup(),
              ),
            )
            as Map<String, Object?>;
    final rows = (backup['database'] as Map)['noteScenes'] as List;
    expect((rows.single as Map)['content'], content);
    sourceFiles.contents.clear();

    await LocalBackupRepository(
      () async => targetDb,
      sceneContentStore: targetFiles,
    ).importBackup(backup);
    final target = SqliteWhiteboardSceneRepository(
      () async => targetDb,
      sceneContentStore: targetFiles,
    );
    expect(await target.loadScene('note-1'), content);
    expect(
      (await targetDb.query('note_scenes')).single['content'],
      startsWith('@scene-file:'),
    );
  });

  test('缺失场景引用的旧备份拒绝恢复，现有笔记和正文不变', () async {
    final db = await _database();
    await db.insert('notes', {'id': 'existing', 'updated_at': 1});
    await db.insert('note_scenes', {
      'note_id': 'existing',
      'content': 'existing-content',
      'updated_at': 1,
    });
    final repository = LocalBackupRepository(
      () async => db,
      sceneContentStore: _SceneFiles(),
    );
    await expectLater(
      repository.importBackup(
        _backup([
          {'note_id': 'missing', 'content': '@scene-file:missing.scene'},
        ]),
      ),
      throwsFormatException,
    );
    expect((await db.query('notes')).single['id'], 'existing');
    expect(
      (await db.query('note_scenes')).single['content'],
      'existing-content',
    );
  });

  test('导出遇到缺失的场景文件会失败，不生成不完整备份', () async {
    final db = await _database();
    await db.insert('note_scenes', {
      'note_id': 'missing',
      'content': '@scene-file:missing.scene',
      'updated_at': 1,
    });
    await expectLater(
      LocalBackupRepository(
        () async => db,
        sceneContentStore: _SceneFiles(),
      ).exportBackup(),
      throwsFormatException,
    );
  });

  test('恢复事务失败不覆盖原有大场景文件，旧 v2 引用仍可在原设备解析', () async {
    final db = await _database();
    final files = _SceneFiles();
    final original = 'a' * (2 * 1024 * 1024);
    final reference = await files.write('note-1', original);
    await db.insert('notes', {'id': 'note-1', 'updated_at': 1});
    await db.insert('note_scenes', {
      'note_id': 'note-1',
      'content': reference,
      'updated_at': 1,
    });
    final backup = _backup([
      {
        'note_id': 'note-1',
        'content': 'b' * (2 * 1024 * 1024),
        'updated_at': 2,
      },
    ]);
    (backup['database'] as Map)['localSettings'] = 'invalid';
    final repository = LocalBackupRepository(
      () async => db,
      sceneContentStore: files,
    );
    await expectLater(repository.importBackup(backup), throwsFormatException);
    expect((await db.query('note_scenes')).single['content'], reference);
    expect(await files.read(reference), original);

    await repository.importBackup(
      _backup([
        {'note_id': 'note-1', 'content': reference, 'updated_at': 1},
      ]),
    );
    expect(
      await SqliteWhiteboardSceneRepository(
        () async => db,
        sceneContentStore: files,
      ).loadScene('note-1'),
      original,
    );
  });
}

Future<Database> _database() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  addTearDown(db.close);
  for (final sql in [
    'CREATE TABLE notebooks (id TEXT PRIMARY KEY, sort_order INTEGER)',
    'CREATE TABLE tags (id TEXT PRIMARY KEY, sort_order INTEGER)',
    'CREATE TABLE notes (id TEXT PRIMARY KEY, updated_at INTEGER, cover_thumbnail BLOB)',
    'CREATE TABLE note_tags (note_id TEXT, tag_id TEXT)',
    'CREATE TABLE note_scenes (note_id TEXT PRIMARY KEY, content TEXT, updated_at INTEGER)',
    'CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT)',
  ]) {
    await db.execute(sql);
  }
  return db;
}

Map<String, Object?> _backup(List<Map<String, Object?>> scenes) => {
  'version': LocalBackupRepository.version,
  'database': <String, Object?>{
    'notebooks': <Object?>[],
    'tags': <Object?>[],
    'notes': <Object?>[],
    'noteTags': <Object?>[],
    'noteScenes': scenes,
    'localSettings': <Object?>[],
  },
};

class _SceneFiles extends SceneContentStore {
  final contents = <String, String>{};

  @override
  Future<String> write(String noteId, String content) async {
    final reference = '${SceneContentStore.referencePrefix}$noteId.scene';
    contents[reference] = content;
    return reference;
  }

  @override
  Future<String?> read(String reference) async => contents[reference];
}
