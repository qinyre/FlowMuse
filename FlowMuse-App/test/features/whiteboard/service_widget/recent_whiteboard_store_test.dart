import 'dart:convert';

import 'package:flow_muse/app/app_router.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/whiteboard/service_widget/recent_whiteboard_store.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openLocalSettingsTestDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE local_settings ('
          'key TEXT PRIMARY KEY, '
          'value TEXT NOT NULL, '
          'updated_at INTEGER NOT NULL'
          ')',
        );
      },
    ),
  );
}

void main() {
  test('记录快照后可重新读出并解析', () async {
    final db = await openLocalSettingsTestDb();
    addTearDown(db.close);
    final store = RecentWhiteboardStore(
      settings: LocalSettingsRepository(() async => db),
    );

    await store.record(
      noteId: 'note-123',
      title: '线代课堂笔记',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1721000000000),
    );

    final rawRows = await db.query(
      'local_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [RecentWhiteboardStore.settingsKey],
      limit: 1,
    );
    final rawJson = jsonDecode(rawRows.single['value']! as String);
    expect((rawJson as Map<String, Object?>).keys.toSet(), {
      'noteId',
      'title',
      'updatedAt',
    });

    final snapshot = await store.read();
    expect(snapshot?.noteId, 'note-123');
    expect(snapshot?.title, '线代课堂笔记');
    expect(snapshot?.updatedAt, 1721000000000);
  });

  test('损坏 JSON 返回 null，路由回退资料库', () async {
    final db = await openLocalSettingsTestDb();
    addTearDown(db.close);
    final settings = LocalSettingsRepository(() async => db);
    await settings.writeString(RecentWhiteboardStore.settingsKey, '{broken');

    final store = RecentWhiteboardStore(settings: settings);
    final snapshot = await store.read();
    expect(snapshot, isNull);
    expect(
      resolveRecentWhiteboardLocation(snapshot, const []),
      AppRoutes.library,
    );
  });

  test('非整数 updatedAt 返回 null', () {
    final snapshot = RecentWhiteboardSnapshot.tryParse(
      '{"noteId":"note-123","title":"线代课堂笔记","updatedAt":1721000000000.5}',
    );

    expect(snapshot, isNull);
  });

  test('存在快照且笔记未删除时跳最近白板，否则回退资料库', () {
    final snapshot = RecentWhiteboardSnapshot(
      noteId: 'note-123',
      title: '线代课堂笔记',
      updatedAt: 1721000000000,
    );

    final activeNotes = [
      NoteItem(
        id: 'note-123',
        title: '线代课堂笔记',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1721000000000),
        kind: LibraryFilter.notes,
        coverColor: Colors.green,
      ),
    ];
    expect(
      resolveRecentWhiteboardLocation(snapshot, activeNotes),
      AppRoutes.whiteboardPath(noteId: 'note-123'),
    );

    final deletedNotes = [
      NoteItem(
        id: 'note-123',
        title: '线代课堂笔记',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1721000000000),
        kind: LibraryFilter.notes,
        coverColor: Colors.green,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(1721000000001),
      ),
    ];
    expect(
      resolveRecentWhiteboardLocation(snapshot, deletedNotes),
      AppRoutes.library,
    );
  });
}
