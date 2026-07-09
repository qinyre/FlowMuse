import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'local_database_path.dart';

class LocalDatabase {
  LocalDatabase._();

  static const databaseName = 'flowmuse_local.db';
  static const databaseVersion = 1;

  static Database? _database;

  static Future<Database> open() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final factory = await createLocalDatabaseFactory();
    final directory = await localDatabaseDirectory();
    final databasePath = path.join(directory, databaseName);
    debugPrint('[FlowMuseCreateNote] LocalDatabase.open path=$databasePath');
    final database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: (db) async {
          debugPrint('[FlowMuseCreateNote] LocalDatabase.onConfigure');
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          debugPrint(
            '[FlowMuseCreateNote] LocalDatabase.onCreate version=$version',
          );
          await _createSchema(db);
        },
      ),
    );
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    debugPrint(
      '[FlowMuseCreateNote] LocalDatabase.opened tables=${tables.map((row) => row['name']).join(',')}',
    );
    _database = database;
    return database;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE notebooks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        kind TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        note_type TEXT NOT NULL,
        page_template TEXT NOT NULL,
        notebook_id TEXT,
        subtitle TEXT,
        deleted_at INTEGER,
        FOREIGN KEY(notebook_id) REFERENCES notebooks(id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE note_tags (
        note_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY(note_id, tag_id),
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE note_scenes (
        note_id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE local_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX notes_notebook_id_index ON notes(notebook_id)',
    );
    await db.execute(
      'CREATE INDEX notes_deleted_at_index ON notes(deleted_at)',
    );
    await db.execute(
      'CREATE INDEX note_tags_tag_id_index ON note_tags(tag_id)',
    );
    await db.execute(
      'CREATE INDEX note_scenes_updated_at_index ON note_scenes(updated_at)',
    );
  }
}
