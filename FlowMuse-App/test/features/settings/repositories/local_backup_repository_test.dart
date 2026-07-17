import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/settings/repositories/local_backup_repository.dart';
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
}
