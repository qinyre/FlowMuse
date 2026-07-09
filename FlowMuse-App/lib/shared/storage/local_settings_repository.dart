import 'package:sqflite_common/sqlite_api.dart';

import 'local_database.dart';

class LocalSettingsRepository {
  LocalSettingsRepository(this._openDatabase);

  final Future<Database> Function() _openDatabase;

  Future<String?> readString(String key) async {
    final db = await _openDatabase();
    final rows = await db.query(
      'local_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeString(String key, String value) async {
    final db = await _openDatabase();
    await db.insert('local_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool?> readBool(String key) async {
    final value = await readString(key);
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  Future<void> writeBool(String key, bool value) {
    return writeString(key, value ? 'true' : 'false');
  }
}

final defaultLocalSettingsRepository = LocalSettingsRepository(
  LocalDatabase.open,
);
