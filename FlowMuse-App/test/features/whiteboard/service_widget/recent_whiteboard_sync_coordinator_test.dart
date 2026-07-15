import 'package:flow_muse/app/app_router.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/whiteboard/service_widget/recent_whiteboard_store.dart';
import 'package:flow_muse/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/service_widget');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('syncFromNote 同时写本地快照并通知鸿蒙卡片', () async {
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recorded = call;
          return null;
        });

    final db = await openLocalSettingsTestDb();
    addTearDown(db.close);
    final coordinator = RecentWhiteboardSyncCoordinator(
      store: RecentWhiteboardStore(
        settings: LocalSettingsRepository(() async => db),
      ),
    );

    final note = NoteItem(
      id: 'note-123',
      title: '线代课堂笔记',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1721000000000),
      kind: LibraryFilter.notes,
      coverColor: Colors.green,
    );

    await coordinator.syncFromNote(note);

    expect(recorded?.method, 'updateLastWhiteboard');
    expect(recorded?.arguments['noteId'], 'note-123');
    expect(
      (await coordinator.store.read())?.title,
      '线代课堂笔记',
    );
  });

  test('takePendingResumeLocation 根据待处理 action 返回路由或 null', () async {
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

    var takeCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takePendingLaunchAction') {
            takeCount += 1;
            return takeCount == 1 ? 'resumeLastWhiteboard' : null;
          }
          return null;
        });

    final coordinator = RecentWhiteboardSyncCoordinator(store: store);
    final notes = [
      NoteItem(
        id: 'note-123',
        title: '线代课堂笔记',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1721000000000),
        kind: LibraryFilter.notes,
        coverColor: Colors.green,
      ),
    ];

    final first = await coordinator.takePendingResumeLocation(notes);
    final second = await coordinator.takePendingResumeLocation(notes);
    expect(first, AppRoutes.whiteboardPath(noteId: 'note-123'));
    expect(second, isNull);
  });
}
