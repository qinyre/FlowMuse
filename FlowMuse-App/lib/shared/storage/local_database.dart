import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'local_database_path.dart';

class LocalDatabase {
  LocalDatabase._();

  static const databaseName = 'flowmuse_local.db';
  static const databaseVersion = 4;

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
          await _ensureSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          debugPrint(
            '[FlowMuseCreateNote] LocalDatabase.onUpgrade '
            'oldVersion=$oldVersion newVersion=$newVersion',
          );
          // v2→v3: 笔记本和标签表新增封面图片列
          if (oldVersion < 3) {
            await _safeAddColumn(db, 'notebooks', 'cover_image', 'TEXT');
            await _safeAddColumn(db, 'tags', 'cover_image', 'TEXT');
          }
          // 注意：cover_thumbnail 在 v2 的 notes 表中已存在，无需迁移
          await _ensureSchema(db);
        },
        onOpen: (db) async {
          debugPrint('[FlowMuseCreateNote] LocalDatabase.onOpen ensureSchema');
          await _ensureSchema(db);
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

  /// 安全添加列：列已存在时静默跳过，避免迁移崩溃
  static Future<void> _safeAddColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    } catch (_) {
      debugPrint(
        '[FlowMuseCreateNote] _safeAddColumn: skip $table.$column (already exists)',
      );
    }
  }

  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notebooks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        cover_image TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        cover_image TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        kind TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        note_type TEXT NOT NULL,
        page_template TEXT NOT NULL,
        notebook_id TEXT,
        subtitle TEXT,
        cover_thumbnail BLOB,
        deleted_at INTEGER,
        FOREIGN KEY(notebook_id) REFERENCES notebooks(id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_tags (
        note_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY(note_id, tag_id),
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_scenes (
        note_id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS notes_notebook_id_index '
      'ON notes(notebook_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS notes_deleted_at_index ON notes(deleted_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS note_tags_tag_id_index ON note_tags(tag_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS note_scenes_updated_at_index '
      'ON note_scenes(updated_at)',
    );
  }

}
