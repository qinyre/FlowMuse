# HarmonyOS 最近白板服务卡片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 FlowMuse 鸿蒙端增加一个会同步最近白板标题/更新时间的桌面服务卡片，点击后恢复最近白板，不可恢复时回退资料库。

**Architecture:** 复用现有 `local_settings` 保存最近白板快照，Flutter 通过 `flow_muse/service_widget` MethodChannel 把快照推送给 ArkTS；ArkTS 侧实现动态 ArkTS 服务卡片、`FormExtensionAbility`、Preferences 持久化和 `formProvider.updateForm()` 刷新。卡片点击通过官方 `postCardAction(... action: 'router' ...)` 拉起现有 `EntryAbility`，Flutter 启动后读取待处理 action 和最近白板快照，再用现有 `go_router` 跳转到 `/whiteboard/:noteId` 或 `/library`。

**Tech Stack:** Flutter、Dart、Riverpod、go_router、MethodChannel、HarmonyOS Form Kit、ArkTS、Preferences（`@kit.ArkData`）、`formProvider.updateForm()`、`postCardAction(router)`。

## Global Constraints

- 共享 Dart 代码禁止 `Platform.is*`；OHOS 差异必须通过条件导入或 MethodChannel 收敛。
- 最近白板快照只允许包含 `noteId`、`title`、`updatedAt`；禁止写入 token、`ownerKey`、`roomKey`、协作明文、外部 URI 或文件内容。
- 必须继续复用 `local_settings` 表保存 `service_widget.lastWhiteboard`，不新增 SQLite schema、不新增 Dart/ArkTS 第三方依赖。
- HarmonyOS 卡片实现必须参考本地官方 guide：
  - `D:\Program\HarmonyOS\harmonyos-guides\应用框架\Form Kit（卡片开发服务）\arkts-ui.md`
  - `D:\Program\HarmonyOS\harmonyos-guides\应用框架\Form Kit（卡片开发服务）\ArkTS卡片开发（推荐）\arkts-ui-widget-configuration.md`
  - `D:\Program\HarmonyOS\harmonyos-guides\应用框架\Form Kit（卡片开发服务）\ArkTS卡片开发（推荐）\ArkTS卡片提供方开发指导\ArkTS卡片页面交互\arkts-ui-widget-event-router.md`
  - `D:\Program\HarmonyOS\harmonyos-guides\应用框架\Form Kit（卡片开发服务）\ArkTS卡片开发（推荐）\ArkTS卡片提供方开发指导\ArkTS卡片页面刷新\arkts-ui-widget-update-by-status.md`
  - `D:\Program\HarmonyOS\harmonyos-guides\基础入门\开发基础知识\应用配置文件\module-configuration-file.md`
- `FormExtensionAbility` 不常驻后台；卡片刷新必须通过 `formProvider.updateForm()` 或 `onUpdateForm()` 完成，不做长时间任务。
- `module.json5` 中 `type: form` 的 `extensionAbilities` 必须包含 `metadata.name = "ohos.extension.form"` 且 `resource` 指向 profile 文件。
- 卡片首版只做一个动态 ArkTS 卡片，默认 `2*2`，只显示一条最近白板信息；不做缩略图、不做协作状态、不做卡片内写操作。
- Dart 调服务卡片通道失败时必须静默降级，白板打开/保存流程不能被中断。
- 涉及 `ohos/`、`module.json5`、`FormExtensionAbility` 或 Channel 注册的改动，必须运行 `cd FlowMuse-App && rtk flutter build hap`；卡片不能调试，需用预览器 + 真机/模拟器手验。

---

### Task 1: 最近白板快照持久化

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_snapshot.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_store.dart`
- Create: `FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart`

**Interfaces:**
- Produces: `class RecentWhiteboardSnapshot { const RecentWhiteboardSnapshot({required String noteId, required String title, required int updatedAt}); Map<String, Object?> toJson(); static RecentWhiteboardSnapshot? tryParse(String? raw); }`
- Produces: `class RecentWhiteboardStore { Future<void> record({required String noteId, required String title, required DateTime updatedAt}); Future<RecentWhiteboardSnapshot?> read(); }`
- Produces: `String resolveRecentWhiteboardLocation(RecentWhiteboardSnapshot? snapshot, Iterable<NoteItem> notes, {String fallback = AppRoutes.library})`

- [ ] **Step 1: Write the failing tests**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart -r expanded`
Expected: FAIL because `recent_whiteboard_snapshot.dart` and `recent_whiteboard_store.dart` do not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_snapshot.dart
import 'dart:convert';

class RecentWhiteboardSnapshot {
  const RecentWhiteboardSnapshot({
    required this.noteId,
    required this.title,
    required this.updatedAt,
  });

  final String noteId;
  final String title;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'noteId': noteId,
    'title': title,
    'updatedAt': updatedAt,
  };

  String toJsonString() => jsonEncode(toJson());

  static RecentWhiteboardSnapshot? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, Object?>) return null;
      final noteId = value['noteId'];
      final title = value['title'];
      final updatedAt = value['updatedAt'];
      if (noteId is! String || title is! String || updatedAt is! num) {
        return null;
      }
      return RecentWhiteboardSnapshot(
        noteId: noteId,
        title: title,
        updatedAt: updatedAt.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
```

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_store.dart
import '../../library/models/note_item.dart';
import '../../../app/app_router.dart';
import '../../../shared/storage/local_settings_repository.dart';
import 'recent_whiteboard_snapshot.dart';

class RecentWhiteboardStore {
  RecentWhiteboardStore({LocalSettingsRepository? settings})
    : _settings = settings ?? defaultLocalSettingsRepository;

  static const settingsKey = 'service_widget.lastWhiteboard';

  final LocalSettingsRepository _settings;

  Future<void> record({
    required String noteId,
    required String title,
    required DateTime updatedAt,
  }) {
    final snapshot = RecentWhiteboardSnapshot(
      noteId: noteId,
      title: title,
      updatedAt: updatedAt.millisecondsSinceEpoch,
    );
    return _settings.writeString(settingsKey, snapshot.toJsonString());
  }

  Future<RecentWhiteboardSnapshot?> read() async {
    final raw = await _settings.readString(settingsKey);
    return RecentWhiteboardSnapshot.tryParse(raw);
  }
}

String resolveRecentWhiteboardLocation(
  RecentWhiteboardSnapshot? snapshot,
  Iterable<NoteItem> notes, {
  String fallback = AppRoutes.library,
}) {
  if (snapshot == null) return fallback;
  for (final note in notes) {
    if (note.id == snapshot.noteId && !note.isDeleted) {
      return AppRoutes.whiteboardPath(noteId: note.id);
    }
  }
  return fallback;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart -r expanded`
Expected: PASS with 3 tests.

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_snapshot.dart FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_store.dart FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart
git commit -m "feat:记录最近白板快照"
```

### Task 2: Flutter ↔ OHOS 服务卡片通道契约

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_ohos.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_stub.dart`
- Create: `FlowMuse-App/test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart`

**Interfaces:**
- Produces: `enum ServiceWidgetLaunchAction { resumeLastWhiteboard }`
- Produces: `class ServiceWidgetChannelOhos { Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot); Future<ServiceWidgetLaunchAction?> takePendingLaunchAction(); void setLaunchListener(VoidCallback onRequested); }`
- Channel name: `flow_muse/service_widget`
- Dart → ArkTS method: `updateLastWhiteboard`
- ArkTS → Dart method: `takePendingLaunchAction`
- ArkTS callback: `onLaunchActionEnqueued`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flow_muse/features/whiteboard/service_widget/recent_whiteboard_snapshot.dart';
import 'package:flow_muse/features/whiteboard/service_widget/service_widget_channel_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/service_widget');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('updateLastWhiteboard 发送精确参数', () async {
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recorded = call;
          return null;
        });

    await const ServiceWidgetChannelOhos().updateLastWhiteboard(
      const RecentWhiteboardSnapshot(
        noteId: 'note-123',
        title: '线代课堂笔记',
        updatedAt: 1721000000000,
      ),
    );

    expect(recorded?.method, 'updateLastWhiteboard');
    expect(recorded?.arguments['noteId'], 'note-123');
    expect(recorded?.arguments['title'], '线代课堂笔记');
    expect(recorded?.arguments['updatedAt'], 1721000000000);
  });

  test('takePendingLaunchAction 识别 resumeLastWhiteboard', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takePendingLaunchAction') {
            return 'resumeLastWhiteboard';
          }
          return null;
        });

    expect(
      await const ServiceWidgetChannelOhos().takePendingLaunchAction(),
      ServiceWidgetLaunchAction.resumeLastWhiteboard,
    );
  });

  test('MissingPluginException 时静默降级', () async {
    expect(
      await const ServiceWidgetChannelOhos().takePendingLaunchAction(),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart -r expanded`
Expected: FAIL because the channel implementation files do not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel.dart
export 'service_widget_channel_stub.dart'
    if (dart.library.io) 'service_widget_channel_ohos.dart';
```

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_stub.dart
import 'package:flutter/widgets.dart';
import 'recent_whiteboard_snapshot.dart';

enum ServiceWidgetLaunchAction { resumeLastWhiteboard }

class ServiceWidgetChannelOhos {
  const ServiceWidgetChannelOhos();

  Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot) async {}

  Future<ServiceWidgetLaunchAction?> takePendingLaunchAction() async => null;

  void setLaunchListener(VoidCallback onRequested) {}
}
```

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_ohos.dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'recent_whiteboard_snapshot.dart';

enum ServiceWidgetLaunchAction { resumeLastWhiteboard }

class ServiceWidgetChannelOhos {
  const ServiceWidgetChannelOhos();

  static const _channel = MethodChannel('flow_muse/service_widget');

  Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>('updateLastWhiteboard', snapshot.toJson());
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<ServiceWidgetLaunchAction?> takePendingLaunchAction() async {
    try {
      final action = await _channel.invokeMethod<String>('takePendingLaunchAction');
      return action == 'resumeLastWhiteboard'
          ? ServiceWidgetLaunchAction.resumeLastWhiteboard
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void setLaunchListener(VoidCallback onRequested) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchActionEnqueued') {
        onRequested();
      }
      return null;
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart -r expanded`
Expected: PASS with 3 tests.

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel.dart FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_ohos.dart FlowMuse-App/lib/features/whiteboard/service_widget/service_widget_channel_stub.dart FlowMuse-App/test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart
git commit -m "feat:定义服务卡片 MethodChannel 契约"
```

### Task 3: 白板保存/启动恢复协调器与 Flutter 接线

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart`
- Modify: `FlowMuse-App/lib/app/flow_muse_app.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Create: `FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart`

**Interfaces:**
- Consumes: `RecentWhiteboardStore.record/read()`
- Consumes: `ServiceWidgetChannelOhos.updateLastWhiteboard()/takePendingLaunchAction()`
- Consumes: `resolveRecentWhiteboardLocation(...)`
- Produces: `class RecentWhiteboardSyncCoordinator { Future<void> syncFromNote(NoteItem note); Future<String?> takePendingResumeLocation(Iterable<NoteItem> notes); }`
- Produces runtime behavior: `FlowMuseApp` cold start / hot start 时能消费 `resumeLastWhiteboard`，`WhiteboardPage` 在打开成功和本地保存成功后触发同步。

- [ ] **Step 1: Write the failing tests**

```dart
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
    expect(first, '/whiteboard/note-123?discardIfUnchanged=true');
    expect(second, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart -r expanded`
Expected: FAIL because `recent_whiteboard_sync_coordinator.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart
import '../../library/models/note_item.dart';
import 'recent_whiteboard_store.dart';
import 'service_widget_channel.dart';

class RecentWhiteboardSyncCoordinator {
  RecentWhiteboardSyncCoordinator({
    RecentWhiteboardStore? store,
    ServiceWidgetChannelOhos? channel,
  }) : store = store ?? RecentWhiteboardStore(),
       _channel = channel ?? const ServiceWidgetChannelOhos();

  final RecentWhiteboardStore store;
  final ServiceWidgetChannelOhos _channel;

  Future<void> syncFromNote(NoteItem note) async {
    await store.record(
      noteId: note.id,
      title: note.title,
      updatedAt: note.updatedAt,
    );
    final snapshot = await store.read();
    if (snapshot != null) {
      await _channel.updateLastWhiteboard(snapshot);
    }
  }

  Future<String?> takePendingResumeLocation(Iterable<NoteItem> notes) async {
    final action = await _channel.takePendingLaunchAction();
    if (action != ServiceWidgetLaunchAction.resumeLastWhiteboard) {
      return null;
    }
    return resolveRecentWhiteboardLocation(await store.read(), notes);
  }
}
```

```dart
// FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart （只展示关键增量）
import '../service_widget/recent_whiteboard_sync_coordinator.dart';

class _WhiteboardPageState extends ConsumerState<WhiteboardPage> {
  final _recentWhiteboardSync = RecentWhiteboardSyncCoordinator();

  Future<void> _openNote() async {
    // ...已有流程...
    final note = _noteById(libraryIndex.notes, noteId);
    // ...加载场景...
    _syncDocumentTitle(note);
    if (note != null) {
      unawaited(_recentWhiteboardSync.syncFromNote(note));
    }
    // ...其余已有逻辑...
  }

  Future<void> _flushLocalDraft() async {
    // ...已有流程...
    await repository.saveScene(widget.noteId, content);
    await _touchNoteWithCurrentCover(widget.noteId);
    final latestIndex = await ref.read(libraryIndexProvider.future);
    final latestNote = _noteById(latestIndex.notes, widget.noteId);
    if (latestNote != null) {
      await _recentWhiteboardSync.syncFromNote(latestNote);
    }
    if (mounted) {
      viewModel.markSaved();
    }
  }
}
```

```dart
// FlowMuse-App/lib/app/flow_muse_app.dart （只展示关键增量）
import '../features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart';
import '../features/whiteboard/service_widget/service_widget_channel.dart';
import '../features/library/repositories/library_repository.dart';

class _FlowMuseAppState extends ConsumerState<FlowMuseApp> {
  bool _consuming = false;
  bool _consumingServiceWidget = false;
  final _recentWhiteboardSync = RecentWhiteboardSyncCoordinator();

  @override
  void initState() {
    super.initState();
    const ExternalDocumentChannelOhos().setEnqueueListener(
      _drainPendingDocuments,
    );
    const ServiceWidgetChannelOhos().setLaunchListener(
      _drainPendingServiceWidgetActions,
    );
    Future.microtask(_drainPendingDocuments);
    Future.microtask(_drainPendingServiceWidgetActions);
  }

  Future<void> _drainPendingServiceWidgetActions() async {
    if (_consumingServiceWidget) return;
    _consumingServiceWidget = true;
    try {
      while (true) {
        final libraryIndex = await ref.read(libraryIndexProvider.future);
        final location = await _recentWhiteboardSync.takePendingResumeLocation(
          libraryIndex.notes,
        );
        if (location == null) break;
        widget._router.go(location);
      }
    } finally {
      _consumingServiceWidget = false;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart -r expanded`
Expected: PASS with 2 tests.

- [ ] **Step 5: Run lightweight regression**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/share/services/share_service_ohos_test.dart test/features/whiteboard/share/services/external_document_ingress_test.dart -r expanded`
Expected: PASS，确认新增通道没有破坏现有 OHOS 通道测试模式。

- [ ] **Step 6: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator.dart FlowMuse-App/lib/app/flow_muse_app.dart FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart
git commit -m "feat:接入最近白板卡片同步与恢复"
```

### Task 4: ArkTS 动态服务卡片、FormExtensionAbility 与启动桥接

**Files:**
- Create: `FlowMuse-App/ohos/entry/src/main/ets/channels/ServiceWidgetChannel.ets`
- Create: `FlowMuse-App/ohos/entry/src/main/ets/entryformability/EntryFormAbility.ets`
- Create: `FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets`
- Create: `FlowMuse-App/ohos/entry/src/main/resources/base/profile/recent_whiteboard_form_config.json`
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/module.json5`
- Modify: `FlowMuse-App/ohos/entry/src/main/resources/base/element/string.json`
- Modify: `FlowMuse-App/ohos/entry/src/main/resources/zh_CN/element/string.json`
- Modify: `FlowMuse-App/ohos/entry/src/main/resources/en_US/element/string.json`

**Interfaces:**
- Consumes Flutter channel contract:
  - `updateLastWhiteboard(noteId, title, updatedAt)`
  - `takePendingLaunchAction() -> 'resumeLastWhiteboard' | null`
  - callback `onLaunchActionEnqueued`
- Produces form binding keys:
  - `appName`
  - `headline`
  - `detail`
  - `buttonText`
- Produces router params payload: `{ action: 'resumeLastWhiteboard' }`
- Guide anchors:
  - Dynamic ArkTS card + router event: `...\arkts-ui-widget-event-router.md`
  - Form state persistence/update: `...\arkts-ui-widget-update-by-status.md`
  - Form config fields: `...\arkts-ui-widget-configuration.md`
  - `extensionAbilities` metadata rule: `...\module-configuration-file.md`

- [ ] **Step 1: Add the smallest failing card scaffold from the official guide**

```json
// FlowMuse-App/ohos/entry/src/main/resources/base/profile/recent_whiteboard_form_config.json
{
  "forms": [
    {
      "name": "recentWhiteboardWidget",
      "displayName": "$string:widget_display_name",
      "description": "$string:widget_desc",
      "src": "./ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets",
      "uiSyntax": "arkts",
      "window": {
        "designWidth": 720,
        "autoDesignWidth": true
      },
      "isDefault": true,
      "updateEnabled": false,
      "defaultDimension": "2*2",
      "supportDimensions": ["2*2"],
      "isDynamic": true
    }
  ]
}
```

```ts
// FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets
let recentWhiteboardStorage = new LocalStorage();

@Entry(recentWhiteboardStorage)
@Component
struct RecentWhiteboardWidgetCard {
  @LocalStorageProp('appName') appName: string = 'FlowMuse';
  @LocalStorageProp('headline') headline: string = '开始你的第一块白板';
  @LocalStorageProp('detail') detail: string = '最近白板';
  @LocalStorageProp('buttonText') buttonText: string = '打开资料库';

  build() {
    Column() {
      Text(this.appName)
      Text(this.headline)
      Text(this.detail)
      Button(this.buttonText)
    }
  }
}
```

```json
// FlowMuse-App/ohos/entry/src/main/module.json5 （先加骨架，下一步补全）
{
  "module": {
    "extensionAbilities": [
      {
        "name": "EntryFormAbility",
        "srcEntry": "./ets/entryformability/EntryFormAbility.ets",
        "description": "$string:EntryFormAbility_desc",
        "label": "$string:EntryFormAbility_label",
        "type": "form",
        "metadata": [
          {
            "name": "ohos.extension.form",
            "resource": "$profile:recent_whiteboard_form_config"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Run HAP build to capture missing wiring**

Run: `cd FlowMuse-App && rtk flutter build hap`
Expected: FAIL with missing ArkTS files / missing strings / channel registration or other build-time wiring errors. Keep the first failing error in the task notes and fix it in the next step.

- [ ] **Step 3: Implement ServiceWidgetChannel, EntryFormAbility, dynamic card, strings, and launch bridge**

```ts
// FlowMuse-App/ohos/entry/src/main/ets/channels/ServiceWidgetChannel.ets
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

const STORE_NAME: string = 'recent_whiteboard_widget';
const SNAPSHOT_KEY: string = 'snapshot';
const FORM_IDS_KEY: string = 'form_ids';

type Snapshot = { noteId: string; title: string; updatedAt: number };

type BindingPayload = {
  appName: string;
  headline: string;
  detail: string;
  buttonText: string;
};

export class ServiceWidgetChannel {
  private static channel: MethodChannel | null = null;
  private static pendingLaunchAction: string | null = null;

  constructor(private readonly context: Context) {}

  register(flutterEngine: FlutterEngine): void {
    const channel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'flow_muse/service_widget'
    );
    ServiceWidgetChannel.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'updateLastWhiteboard') {
          void this.handleUpdate(call.args as Record<string, Object>, result);
          return;
        }
        if (call.method === 'takePendingLaunchAction') {
          result.success(ServiceWidgetChannel.pendingLaunchAction);
          ServiceWidgetChannel.pendingLaunchAction = null;
          return;
        }
        result.notImplemented();
      }
    });
  }

  static enqueueLaunchAction(action: string): void {
    ServiceWidgetChannel.pendingLaunchAction = action;
    ServiceWidgetChannel.channel?.invokeMethod('onLaunchActionEnqueued', null);
  }

  static async buildBindingPayload(context: Context): Promise<BindingPayload> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(SNAPSHOT_KEY, '') as string;
    if (!raw) {
      return {
        appName: 'FlowMuse',
        headline: '开始你的第一块白板',
        detail: '最近白板',
        buttonText: '打开资料库'
      };
    }
    const snapshot = JSON.parse(raw) as Snapshot;
    const date = new Date(snapshot.updatedAt);
    const hh = date.getHours().toString().padStart(2, '0');
    const mm = date.getMinutes().toString().padStart(2, '0');
    return {
      appName: 'FlowMuse',
      headline: snapshot.title,
      detail: `最近白板 · ${hh}:${mm}`,
      buttonText: '继续创作'
    };
  }

  static async rememberFormId(context: Context, formId: string): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(FORM_IDS_KEY, '[]') as string;
    const ids = JSON.parse(raw) as string[];
    if (!ids.includes(formId)) {
      ids.push(formId);
      await store.put(FORM_IDS_KEY, JSON.stringify(ids));
      await store.flush();
    }
  }

  static async removeFormId(context: Context, formId: string): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(FORM_IDS_KEY, '[]') as string;
    const ids = (JSON.parse(raw) as string[]).filter((id) => id !== formId);
    await store.put(FORM_IDS_KEY, JSON.stringify(ids));
    await store.flush();
  }

  static async updateFormById(context: Context, formId: string): Promise<void> {
    const payload = await ServiceWidgetChannel.buildBindingPayload(context);
    const formData = formBindingData.createFormBindingData(payload);
    await formProvider.updateForm(formId, formData);
  }

  private async handleUpdate(
    args: Record<string, Object>,
    result: MethodResult,
  ): Promise<void> {
    try {
      const snapshot: Snapshot = {
        noteId: args.noteId as string,
        title: args.title as string,
        updatedAt: args.updatedAt as number,
      };
      const store = await preferences.getPreferences(this.context, STORE_NAME);
      await store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
      await store.flush();
      const rawIds = await store.get(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(rawIds) as string[];
      for (const formId of ids) {
        await ServiceWidgetChannel.updateFormById(this.context, formId);
      }
      result.success(null);
    } catch (err) {
      result.error('SERVICE_WIDGET_UPDATE_FAILED', JSON.stringify(err as BusinessError), null);
    }
  }
}
```

```ts
// FlowMuse-App/ohos/entry/src/main/ets/entryformability/EntryFormAbility.ets
import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { ServiceWidgetChannel } from '../channels/ServiceWidgetChannel';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY]?.toString();
    if (formId) {
      void ServiceWidgetChannel.rememberFormId(this.context, formId);
    }
    return formBindingData.createFormBindingData({
      appName: 'FlowMuse',
      headline: '开始你的第一块白板',
      detail: '最近白板',
      buttonText: '打开资料库'
    });
  }

  onUpdateForm(formId: string): void {
    void ServiceWidgetChannel.updateFormById(this.context, formId);
  }

  onRemoveForm(formId: string): void {
    void ServiceWidgetChannel.removeFormId(this.context, formId);
  }

  onAcquireFormState(want: Want) {
    return formInfo.FormState.READY;
  }
}
```

```ts
// FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets
let recentWhiteboardStorage = new LocalStorage();

@Entry(recentWhiteboardStorage)
@Component
struct RecentWhiteboardWidgetCard {
  @LocalStorageProp('appName') appName: string = 'FlowMuse';
  @LocalStorageProp('headline') headline: string = '开始你的第一块白板';
  @LocalStorageProp('detail') detail: string = '最近白板';
  @LocalStorageProp('buttonText') buttonText: string = '打开资料库';

  build() {
    Column({ space: 8 }) {
      Text(this.appName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .opacity(0.7)

      Text(this.headline)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.detail)
        .fontSize(12)
        .opacity(0.65)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button(this.buttonText)
        .width('100%')
        .height(32)
        .margin({ top: 8 })
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { action: 'resumeLastWhiteboard' }
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F4F8F4')
  }
}
```

```ts
// FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets （关键增量）
import { ServiceWidgetChannel } from '../channels/ServiceWidgetChannel';

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam)
    if (want?.parameters?.params) {
      const params = JSON.parse(want.parameters.params as string) as Record<string, Object>;
      if (params.action === 'resumeLastWhiteboard') {
        ServiceWidgetChannel.enqueueLaunchAction('resumeLastWhiteboard');
      }
    }
    ExternalDocumentChannel.enqueueWant(want)
    this.enqueueSharedDocuments(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam)
    if (want?.parameters?.params) {
      const params = JSON.parse(want.parameters.params as string) as Record<string, Object>;
      if (params.action === 'resumeLastWhiteboard') {
        ServiceWidgetChannel.enqueueLaunchAction('resumeLastWhiteboard');
      }
    }
    ExternalDocumentChannel.enqueueWant(want)
    this.enqueueSharedDocuments(want)
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    new PdfImportChannel(this.context).register(flutterEngine)
    new FileSaveChannel(this.context).register(flutterEngine)
    new FilePickerChannel(this.context).register(flutterEngine)
    new HttpChannel().register(flutterEngine)
    new SystemShareChannel(this.context).register(flutterEngine)
    new ExternalDocumentChannel().register(flutterEngine)
    new ServiceWidgetChannel(this.context).register(flutterEngine)
  }
}
```

```json
// FlowMuse-App/ohos/entry/src/main/module.json5 （完整增量）
{
  "module": {
    "abilities": [
      {
        "name": "EntryAbility",
        "srcEntry": "./ets/entryability/EntryAbility.ets",
        "description": "$string:EntryAbility_desc",
        "label": "$string:EntryAbility_label",
        "icon": "$media:icon",
        "startWindowIcon": "$media:icon",
        "startWindowBackground": "$color:start_window_background",
        "exported": true,
        "skills": [
          {
            "entities": ["entity.system.home"],
            "actions": ["action.system.home"]
          }
        ]
      }
    ],
    "extensionAbilities": [
      {
        "name": "EntryFormAbility",
        "srcEntry": "./ets/entryformability/EntryFormAbility.ets",
        "description": "$string:EntryFormAbility_desc",
        "label": "$string:EntryFormAbility_label",
        "type": "form",
        "metadata": [
          {
            "name": "ohos.extension.form",
            "resource": "$profile:recent_whiteboard_form_config"
          }
        ]
      }
    ]
  }
}
```

```json
// FlowMuse-App/ohos/entry/src/main/resources/base/element/string.json （增量）
{
  "string": [
    { "name": "EntryFormAbility_desc", "value": "recent whiteboard service widget" },
    { "name": "EntryFormAbility_label", "value": "FlowMuse Widget" },
    { "name": "widget_display_name", "value": "FlowMuse 最近白板" },
    { "name": "widget_desc", "value": "显示最近白板并继续创作" }
  ]
}
```

```json
// FlowMuse-App/ohos/entry/src/main/resources/zh_CN/element/string.json （增量）
{
  "string": [
    { "name": "EntryFormAbility_desc", "value": "最近白板服务卡片" },
    { "name": "EntryFormAbility_label", "value": "FlowMuse 卡片" },
    { "name": "widget_display_name", "value": "FlowMuse 最近白板" },
    { "name": "widget_desc", "value": "显示最近白板并继续创作" }
  ]
}
```

```json
// FlowMuse-App/ohos/entry/src/main/resources/en_US/element/string.json （增量）
{
  "string": [
    { "name": "EntryFormAbility_desc", "value": "recent whiteboard widget" },
    { "name": "EntryFormAbility_label", "value": "FlowMuse Widget" },
    { "name": "widget_display_name", "value": "FlowMuse Recent Board" },
    { "name": "widget_desc", "value": "Resume the latest whiteboard" }
  ]
}
```

- [ ] **Step 4: Run build and preview checks**

Run: `cd FlowMuse-App && rtk flutter build hap`
Expected: PASS and generate HAP without `module.json5` / `FormExtensionAbility` / resource errors.

Run: 在 DevEco Studio 预览 `FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets`
Expected: `2*2` 预览中可看到四个绑定字段，按钮点击代码无语法错误。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/ohos/entry/src/main/ets/channels/ServiceWidgetChannel.ets FlowMuse-App/ohos/entry/src/main/ets/entryformability/EntryFormAbility.ets FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets FlowMuse-App/ohos/entry/src/main/resources/base/profile/recent_whiteboard_form_config.json FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets FlowMuse-App/ohos/entry/src/main/module.json5 FlowMuse-App/ohos/entry/src/main/resources/base/element/string.json FlowMuse-App/ohos/entry/src/main/resources/zh_CN/element/string.json FlowMuse-App/ohos/entry/src/main/resources/en_US/element/string.json
git commit -m "feat:接入鸿蒙最近白板服务卡片"
```

### Task 5: 文档同步、全量校验与最终提交

**Files:**
- Modify: `docs/项目说明/项目需求.md`
- Modify: `docs/技术设计/前端架构.md`
- Verify all files changed in Tasks 1-4.

**Interfaces:**
- Consumes completed files from Tasks 1-4.
- Produces updated requirement/architecture docs that describe the card, its data source, and the Flutter ↔ ArkTS boundary.

- [ ] **Step 1: Update user-facing requirements and architecture docs**

```md
<!-- docs/项目说明/项目需求.md 在 4.10 鸿蒙端特有中补一行 -->
| 桌面服务卡片 | 鸿蒙桌面显示最近白板并一键继续创作；无最近白板时回到资料库 |
```

```md
<!-- docs/技术设计/前端架构.md 在跨平台章节补一段 -->
- 服务卡片：鸿蒙通过 `FormExtensionAbility` + ArkTS 动态卡片承载最近白板入口；
  Flutter 侧只负责把 `noteId/title/updatedAt` 通过 `flow_muse/service_widget`
  通道推送给 ArkTS，并在启动时消费 `resumeLastWhiteboard` action。
```

- [ ] **Step 2: Run targeted Dart analysis**

Run: `cd FlowMuse-App && rtk flutter analyze lib/features/whiteboard/service_widget lib/app/flow_muse_app.dart lib/features/whiteboard/views/whiteboard_page.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run targeted tests**

Run: `cd FlowMuse-App && rtk flutter test test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart -r expanded`
Expected: PASS with all new service-widget tests green.

- [ ] **Step 4: Run HAP build again as release gate**

Run: `cd FlowMuse-App && rtk flutter build hap`
Expected: PASS.

- [ ] **Step 5: Manual acceptance checklist**

```text
1. 安装 HAP 后，在鸿蒙桌面把 FlowMuse 卡片加到桌面。
2. 初始状态卡片显示“开始你的第一块白板 / 打开资料库”。
3. 打开任意白板，返回桌面，卡片刷新为真实标题与“最近白板 · HH:MM”。
4. 修改白板并等待/触发本地保存，返回桌面，时间更新。
5. 点击卡片按钮，应用进入对应白板。
6. 删除该白板后再次点击卡片，应用回到资料库，不崩溃、不弹异常。
7. 全程检查日志：不得出现 token、ownerKey、roomKey、场景内容、外部 URI。
```

- [ ] **Step 6: Final commit**

```bash
git add docs/项目说明/项目需求.md docs/技术设计/前端架构.md FlowMuse-App/lib/features/whiteboard/service_widget FlowMuse-App/lib/app/flow_muse_app.dart FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/ohos/entry/src/main/ets/channels/ServiceWidgetChannel.ets FlowMuse-App/ohos/entry/src/main/ets/entryformability/EntryFormAbility.ets FlowMuse-App/ohos/entry/src/main/ets/servicewidget/pages/RecentWhiteboardWidgetCard.ets FlowMuse-App/ohos/entry/src/main/resources/base/profile/recent_whiteboard_form_config.json FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets FlowMuse-App/ohos/entry/src/main/module.json5 FlowMuse-App/ohos/entry/src/main/resources/base/element/string.json FlowMuse-App/ohos/entry/src/main/resources/zh_CN/element/string.json FlowMuse-App/ohos/entry/src/main/resources/en_US/element/string.json FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_store_test.dart FlowMuse-App/test/features/whiteboard/service_widget/service_widget_channel_ohos_test.dart FlowMuse-App/test/features/whiteboard/service_widget/recent_whiteboard_sync_coordinator_test.dart
git commit -m "feat:实现鸿蒙最近白板服务卡片"
```

## Self-Review

- Spec coverage: 任务 1 覆盖最近白板快照持久化；任务 2 覆盖 Flutter ↔ OHOS 通道；任务 3 覆盖白板打开/保存同步与启动恢复；任务 4 覆盖 ArkTS 动态卡片、`FormExtensionAbility`、`module.json5` 与 router 事件；任务 5 覆盖文档、分析、测试、HAP 构建和手验。
- Placeholder scan: 无 `TBD`、`TODO`、"适当处理"、"后续再做" 之类占位描述；每个任务都给了具体文件、命令和代码。
- Type consistency: `RecentWhiteboardSnapshot`、`RecentWhiteboardStore`、`ServiceWidgetChannelOhos`、`RecentWhiteboardSyncCoordinator`、ArkTS `flow_muse/service_widget` 方法名、router `params.action = 'resumeLastWhiteboard'`、卡片绑定键 `appName/headline/detail/buttonText` 在全计划中保持一致。
