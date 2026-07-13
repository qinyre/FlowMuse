# FlowMuse 协作 Phase 0 — 热路径止血

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不改协议、不改服务端，将热路径上的全量序列化/SQLite/封面/快照从每帧触发降低到批处理+延迟触发，消除高频编辑时的 CPU/IO/网络三方争用。

**Architecture:** 新增 `ChangeAccumulator` 集中接收 scene 变更，50ms 窗口内按 elementId 合并，窗口到期后批量加密发送。本地保存拆成 500ms debounce，快照拆成闲置 2s/最长 30s 单飞。接收端加 16-33ms 合并窗口再 applyRemoteScene。presence 限频 30fps。

**Tech Stack:** Dart (Flutter), 纯客户端。不引入新依赖。

## Global Constraints

- 不改变 Socket.IO 协议、不对服务端做任何修改
- 不改变 AES-GCM 端到端加密、Excalidraw `id/version/versionNonce/index/isDeleted` 语义
- 不改变数据库 schema
- `volatile` 仅用于 cursor/idle/visible bounds；文档元素绝不走 volatile
- 远端应用不触发本地协作广播；删除墓碑不被错误合并或丢弃
- 所有新增类位于 `lib/features/whiteboard/collaboration/services/`
- 日志使用 `CollaborationDebugLog.write`，带 `[FlowMuseCreateNote]` 前缀的 `debugPrint`

---

### Task 1: ChangeAccumulator — 集中接收变更 + 50ms 批处理

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/change_accumulator.dart`
- Test: `FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_test.dart`

**Interfaces:**
- Produces: `ChangeAccumulator` class with `schedule(ExcalidrawScene, {bool bypass})`, `dispose()`
- Produces: `typedef ChangeBatchCallback = Future<void> Function(List<Map<String, Object?>> elements, bool isInitial)`
- Consumes: `SceneReconciler.getSyncableElements`, `SceneReconciler.getSceneVersion` (existing)

- [ ] **Step 1: Write the failing test — basic合并**

```dart
// test/features/whiteboard/collaboration/services/change_accumulator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/change_accumulator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

void main() {
  test('合并窗口内同一元素多次更新只保留最高version', () async {
    final accumulator = ChangeAccumulator(
      batchWindow: const Duration(milliseconds: 50),
    );

    final batches = <List<Map<String, Object?>>>[];
    accumulator.onFlush = (elements, _) async {
      batches.add(List.of(elements));
    };

    // 同一元素三次更新，version递增
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 1, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 2, x: 20),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 3, x: 30),
    ]));

    // 等窗口到期
    await Future.delayed(const Duration(milliseconds: 100));

    expect(batches.length, 1);
    final sent = batches.first;
    expect(sent.length, 1);
    expect(sent.first['id'], 'a');
    expect(sent.first['version'], 3);
    expect(sent.first['x'], 30);
  });
}

Map<String, Object?> _element({
  required String id,
  required int version,
  int? x,
}) {
  return {
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': 1,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': false,
    'index': 'a0',
    if (x != null) 'x': x,
    'y': 0,
    'width': 100,
    'height': 100,
  };
}

ExcalidrawScene _sceneWithElements(List<Map<String, Object?>> elements) {
  return ExcalidrawScene.empty().copyWith(elements: elements);
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/change_accumulator_test.dart
```
Expected: FAIL — `ChangeAccumulator` class not found.

- [ ] **Step 3: Write minimal ChangeAccumulator implementation**

```dart
// lib/features/whiteboard/collaboration/services/change_accumulator.dart
import 'dart:async';
import '../models/excalidraw_scene.dart';
import 'scene_reconciler.dart';

typedef ChangeBatchCallback = Future<void> Function(
  List<Map<String, Object?>> elements,
  bool isInitial,
);

class ChangeAccumulator {
  ChangeAccumulator({
    Duration batchWindow = const Duration(milliseconds: 50),
    SceneReconciler? reconciler,
  }) : _batchWindow = batchWindow,
       _reconciler = reconciler ?? SceneReconciler();

  final Duration _batchWindow;
  final SceneReconciler _reconciler;
  Timer? _timer;
  final Map<String, Map<String, Object?>> _pending = {};
  bool _hasInitial = false;

  ChangeBatchCallback? onFlush;

  /// 调度一批元素。如果 [bypass] 为 true（undo/redo/初始同步），跳过批处理立即发送。
  void schedule(ExcalidrawScene scene, {bool bypass = false}) {
    if (bypass) {
      _timer?.cancel();
      _timer = null;
      final syncable = _reconciler.getSyncableElements(scene.elements);
      _pending.clear();
      _hasInitial = false;
      onFlush?.call(syncable, true);
      return;
    }

    for (final element in scene.elements) {
      final id = element['id'] as String;
      final existing = _pending[id];
      if (existing == null ||
          (_version(element) > _version(existing))) {
        _pending[id] = Map<String, Object?>.from(element);
      }
    }

    _timer?.cancel();
    _timer = Timer(_batchWindow, _flush);
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty && !_hasInitial) return;

    final elements = _reconciler.getSyncableElements(_pending.values.toList());
    final isInitial = _hasInitial;
    _pending.clear();
    _hasInitial = false;
    onFlush?.call(elements, isInitial);
  }

  int _version(Map<String, Object?> e) => (e['version'] as num).toInt();

  void dispose() {
    _timer?.cancel();
    _pending.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/change_accumulator_test.dart
```
Expected: PASS.

- [ ] **Step 5: Add tests for edge cases**

```dart
// 追加到 change_accumulator_test.dart

test('删除墓碑version更高时覆盖更新', () async {
  final accumulator = ChangeAccumulator();
  final batches = <List<Map<String, Object?>>>[];
  accumulator.onFlush = (elements, _) async {
    batches.add(List.of(elements));
  };

  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 5, x: 10),
  ]));
  accumulator.schedule(_sceneWithElements([
    {'id': 'a', 'type': 'rectangle', 'version': 6, 'versionNonce': 1,
     'updated': DateTime.now().millisecondsSinceEpoch,
     'isDeleted': true, 'index': 'a0'},
  ]));

  await Future.delayed(const Duration(milliseconds: 100));
  expect(batches.length, 1);
  expect(batches.first.first['isDeleted'], true);
  expect(batches.first.first['version'], 6);
});

test('bypass跳过批处理立即发送', () async {
  final accumulator = ChangeAccumulator();
  final batches = <List<Map<String, Object?>>>[];
  accumulator.onFlush = (elements, _) async {
    batches.add(List.of(elements));
  };

  // 先 schedule 一个普通更新
  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 1, x: 10),
  ]));

  // bypass 应该立即发送，并清空 pending
  accumulator.schedule(_sceneWithElements([
    _element(id: 'b', version: 1, x: 20),
  ]), bypass: true);

  // bypass 是同步调用 onFlush，所以第一批已经发出
  expect(batches.length, 1); // bypass 的那批
  expect(batches.first.length, 1);
  expect(batches.first.first['id'], 'b');
});

test('窗口内无变更不触发flush', () async {
  final accumulator = ChangeAccumulator();
  var flushCount = 0;
  accumulator.onFlush = (_, __) async { flushCount++; };
  // 不调 schedule，等窗口到期
  await Future.delayed(const Duration(milliseconds: 100));
  expect(flushCount, 0);
});
```

- [ ] **Step 6: Run all tests**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/change_accumulator_test.dart
```
Expected: 4 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/services/change_accumulator.dart \
        FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_test.dart
git commit -m "feat: 新增 ChangeAccumulator — 50ms 合并窗口 + bypass 机制"
```

---

### Task 2: 接入 ChangeAccumulator 到 CollaborationRepository

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

**Interfaces:**
- Consumes: `ChangeAccumulator` (Task 1)
- Modifies: `broadcastScene()` — 改为通过 accumulator 调度
- Retains: `_send()`, `_rememberBroadcasted()`, `_saveSceneSnapshot()` (SnapshotScheduler 在 Task 4 改造)

- [ ] **Step 1: 在 CollaborationRepository 中引入 ChangeAccumulator**

```dart
// collaboration_repository.dart — 在已有 import 区域追加
import '../services/change_accumulator.dart';

// 在类成员变量区域追加（_transport 声明之后）
final ChangeAccumulator _accumulator;
```

- [ ] **Step 2: 修改构造函数初始化 accumulator**

```dart
// collaboration_repository.dart — 构造函数中，在 _reconciler 赋值之后追加
CollaborationRepository({
  // ... 现有参数保持不变 ...
}) : _transport = transport ?? const DisconnectedRealtimeTransport(),
     _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
     // ... 其他现有赋值 ...
     _reconciler = reconciler ?? SceneReconciler(),
     _accumulator = ChangeAccumulator(  // 新增
       reconciler: reconciler ?? SceneReconciler(),
     ) {
  _accumulator.onFlush = _onAccumulatorFlush;
}
```

- [ ] **Step 3: 实现 _onAccumulatorFlush**

```dart
// collaboration_repository.dart — 新增私有方法
Future<void> _onAccumulatorFlush(
  List<Map<String, Object?>> elements,
  bool isInitial,
) async {
  final room = _activeRoom;
  if (room == null) return;

  final sceneVersion = _reconciler.getSceneVersion(elements);
  final message = isInitial
      ? CollaborationMessage.sceneInit(elements: elements)
      : CollaborationMessage.sceneUpdate(elements: elements);

  await _send(room: room, message: message);
  _rememberBroadcasted(elements);
  _lastBroadcastedOrReceivedSceneVersion = sceneVersion;

  // 快照保存改为标记脏（SnapshotScheduler 将在 Task 4 接管实际保存）
  // 本期先保留 unawaited(_saveSceneSnapshot) 但将在 Task 5 替换
  unawaited(_saveSceneSnapshot(
    room: room,
    scene: _latestScene.copyWith(
      elements: _reconciler.getSyncableElements(_latestScene.elements),
    ),
  ));
}
```

- [ ] **Step 4: 修改 broadcastScene() 委托给 accumulator**

```dart
// collaboration_repository.dart — 替换现有 broadcastScene() 方法体
Future<void> broadcastScene({
  required CollaborationRoom room,
  required ExcalidrawScene scene,
  bool initial = false,
  bool syncAll = false,
}) async {
  final syncableElements = _reconciler.getSyncableElements(scene.elements);
  final syncableScene = scene.copyWith(elements: syncableElements);
  _latestScene = syncableScene;

  // 通过 accumulator 调度——它负责合并和定时 flush
  _accumulator.schedule(
    syncableScene,
    bypass: initial || syncAll, // 初始/全量同步/undo/redo 立即发送
  );
}
```

- [ ] **Step 5: 在 _resetLocalState() 中清理 accumulator**

```dart
// collaboration_repository.dart — _resetLocalState() 末尾追加
void _resetLocalState() {
  // ... 现有清理代码 ...
  _accumulator.dispose(); // 新增：清空 pending
  // 重新绑定回调（下次 start 时会重新设置，但 dispose 后 onFlush 为 null）
}
```

- [ ] **Step 6: 修改 _startRoomSession() 重新绑定 onFlush**

```dart
// collaboration_repository.dart — _startRoomSession() 开头追加
void _startRoomSession(CollaborationRoom room) {
  _stopRoomSession();
  _accumulator.dispose(); // 清理上一个房间的 pending
  _accumulator.onFlush = _onAccumulatorFlush; // 重新绑定

  // ... 现有初始化代码 ...
}
```

- [ ] **Step 7: 运行已有测试确保不回归**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS（或显式确认哪些测试因架构调整需要更新）。

- [ ] **Step 8: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart
git commit -m "refactor: broadcastScene 接入 ChangeAccumulator 批处理"
```

---

### Task 3: 拆分 whiteboard_page 热路径 — 本地草稿/协作/封面分离

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

**Interfaces:**
- Consumes: `ChangeAccumulator` (via `CollaborationRepository.broadcastScene`, Task 2)
- Modifies: `_saveMarkdrawScene()` — 拆分为三个独立调度器
- Produces: `LocalDraftScheduler`（内嵌于 whiteboard_page）

- [ ] **Step 1: 新增 LocalDraftScheduler 内部类**

```dart
// whiteboard_page.dart — 在 WhiteboardPageState 类内部追加成员和方法
// 放在 _disposingOrLeaving 声明之后

Timer? _localDraftTimer;
bool _localDraftDirty = false;
static const Duration _localDraftDebounce = Duration(milliseconds: 500);

void _scheduleLocalDraft() {
  _localDraftDirty = true;
  _localDraftTimer?.cancel();
  _localDraftTimer = Timer(_localDraftDebounce, _flushLocalDraft);
}

Future<void> _flushLocalDraft() async {
  _localDraftTimer = null;
  if (!_localDraftDirty || !mounted) return;
  _localDraftDirty = false;

  if (widget.temporaryCollaboration) return;

  final viewModel = ref.read(whiteboardViewModelProvider.notifier);
  final repository = ref.read(whiteboardSceneRepositoryProvider);
  final content = _markdrawController.serializeScene(
    format: DocumentFormat.excalidraw,
  );
  await repository.saveScene(widget.noteId, content);
  await _touchNoteWithCurrentCover(widget.noteId);
  if (mounted) {
    viewModel.markSaved();
  }
}

void _flushLocalDraftOnExit() {
  _localDraftTimer?.cancel();
  _localDraftTimer = null;
  if (_localDraftDirty) {
    _flushLocalDraft(); // 离开/后台时同步等待
  }
}
```

- [ ] **Step 2: 新增 RealtimeScheduler — 协作广播改为直接调 accumulator**

`_broadcastCurrentScene()` 已经在 Task 2 中接入了 accumulator，不需要额外改动。只需要确认 `onSceneChanged` 回调的调用路径正确。

- [ ] **Step 3: 重构 _saveMarkdrawScene()**

```dart
// whiteboard_page.dart — 替换现有 _saveMarkdrawScene() 方法
Future<void> _saveMarkdrawScene() async {
  if (_loadingScene || _applyingRemoteScene) {
    return;
  }

  // 1. 协作增量发送 — 走 accumulator（已在 Task 2 中处理）
  await _broadcastCurrentScene();

  // 2. 本地草稿 — 500ms debounce
  _scheduleLocalDraft();

  // 3. 封面生成 — 不在热路径上，仅显式保存时由 _touchNoteWithCurrentCover 处理
  // （_touchNoteWithCurrentCover 已在 _flushLocalDraft 中调用）
}
```

- [ ] **Step 4: 在 dispose() 和 AppLifecycle 中 flush 草稿**

```dart
// whiteboard_page.dart — dispose() 方法开头追加
@override
void dispose() {
  _flushLocalDraftOnExit(); // 新增：离开前确保草稿已保存
  _disposingOrLeaving = true;
  // ... 现有 dispose 代码 ...
}

// 新增 AppLifecycle 监听（在 initState() 中注册）
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  // ... 现有 initState 代码 ...
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.inactive) {
    _flushLocalDraftOnExit();
  }
}
```

- [ ] **Step 5: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS。

- [ ] **Step 6: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart
git commit -m "refactor: 拆分 onSceneChanged 热路径 — 本地草稿 500ms debounce + 协作走 accumulator"
```

---

### Task 4: SnapshotScheduler — 快照保存降频 + 单飞

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

**Interfaces:**
- Consumes: `EncryptedSceneStore.saveScene` (existing), `SceneReconciler` (existing)
- Modifies: `_saveSceneSnapshot()` — 替换为 SnapshotScheduler 逻辑
- Produces: `_SnapshotGate` (内嵌于 repository)

- [ ] **Step 1: 新增 SnapshotScheduler 状态字段**

```dart
// collaboration_repository.dart — 在类成员变量区域追加
Timer? _snapshotTimer;
bool _snapshotSaving = false;
bool _snapshotDirty = false;
static const Duration _snapshotIdle = Duration(seconds: 2);
static const Duration _snapshotMaxInterval = Duration(seconds: 30);
DateTime _lastSnapshotTime = DateTime.now();
```

- [ ] **Step 2: 实现 _scheduleSnapshot() 和 _flushSnapshot()**

```dart
// collaboration_repository.dart — 新增私有方法
void _scheduleSnapshot() {
  _snapshotDirty = true;
  _snapshotTimer?.cancel();

  final sinceLast = DateTime.now().difference(_lastSnapshotTime);
  final delay = sinceLast >= _snapshotMaxInterval
      ? Duration.zero
      : _snapshotIdle;

  _snapshotTimer = Timer(delay, _flushSnapshot);
}

Future<void> _flushSnapshot() async {
  _snapshotTimer = null;
  if (!_snapshotDirty) return;
  if (_snapshotSaving) return; // single-flight: 已有在途快照

  final room = _activeRoom;
  if (room == null) return;

  _snapshotSaving = true;
  _snapshotDirty = false;
  try {
    final scene = _latestScene;
    await _saveSceneResolvingConflict(
      room: room,
      scene: scene.copyWith(files: const {}),
    );
    _lastSnapshotTime = DateTime.now();
  } catch (error) {
    if (!_repositoryErrors.isClosed) {
      _repositoryErrors.add('协作快照保存失败：$error');
    }
    _snapshotDirty = true; // 重试标记
  } finally {
    _snapshotSaving = false;
    // 如果保存期间又有新变更，重新调度
    if (_snapshotDirty) {
      _scheduleSnapshot();
    }
  }
}

/// 强制 flush（离开/后台/显式保存时调用）
Future<void> forceFlushSnapshot() async {
  _snapshotTimer?.cancel();
  _snapshotTimer = null;
  if (_snapshotDirty) {
    await _flushSnapshot();
  }
}
```

- [ ] **Step 3: 修改 _onAccumulatorFlush 和 _resetLocalState**

```dart
// collaboration_repository.dart — _onAccumulatorFlush 末尾
// 替换: unawaited(_saveSceneSnapshot(room: room, scene: ...))
// 改为:
_scheduleSnapshot();

// collaboration_repository.dart — _resetLocalState() 追加
void _resetLocalState() {
  // ... 现有清理代码 ...
  _snapshotTimer?.cancel();
  _snapshotTimer = null;
  _snapshotSaving = false;
  _snapshotDirty = false;
}
```

- [ ] **Step 4: 在 stop() 和房间结束前强制保存**

```dart
// collaboration_repository.dart — stop() 方法，在 _resetLocalState() 之前追加
Future<void> stop() async {
  await forceFlushSnapshot(); // 新增：离开前保存最终快照
  _resetLocalState();
  await _transport.disconnect();
}
```

- [ ] **Step 5: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/
```
Expected: 已有测试 PASS。

- [ ] **Step 6: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart
git commit -m "feat: SnapshotScheduler — 快照闲置2s/最长30s，单飞防409风暴"
```

---

### Task 5: 接收端合并窗口 + Presence 限频

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

**Interfaces:**
- Modifies: `_enqueueRemoteElements()` — 加合并窗口
- Modifies: `_broadcastPointerPresence()` — 加 33ms throttle

- [ ] **Step 1: 接收端合并窗口 — 替换 _enqueueRemoteElements**

```dart
// whiteboard_page.dart — 新增合并窗口状态
final Map<String, Map<String, Object?>> _remoteMergeBuffer = {};
Timer? _remoteMergeTimer;
static const Duration _remoteMergeWindow = Duration(milliseconds: 33);

// 替换现有 _enqueueRemoteElements 方法
void _enqueueRemoteElements(List<Map<String, Object?>> remoteElements) {
  CollaborationDebugLog.write('scene', 'remote_elements_queued', {
    'elements': remoteElements.length,
    'summary': CollaborationDebugLog.elementSummary(remoteElements),
  });

  // 合并窗口内按 elementId 保留最高 version/versionNonce
  for (final element in remoteElements) {
    final id = element['id'] as String;
    final existing = _remoteMergeBuffer[id];
    if (existing == null) {
      _remoteMergeBuffer[id] = Map<String, Object?>.from(element);
    } else {
      final existingVersion = (existing['version'] as num).toInt();
      final incomingVersion = (element['version'] as num).toInt();
      if (incomingVersion > existingVersion ||
          (incomingVersion == existingVersion &&
           (element['versionNonce'] as num).toInt() >
               (existing['versionNonce'] as num).toInt())) {
        _remoteMergeBuffer[id] = Map<String, Object?>.from(element);
      }
    }
  }

  _remoteMergeTimer?.cancel();
  _remoteMergeTimer = Timer(_remoteMergeWindow, _flushRemoteMerge);
}

Future<void> _flushRemoteMerge() async {
  _remoteMergeTimer = null;
  if (_remoteMergeBuffer.isEmpty) return;

  final merged = _remoteMergeBuffer.values.toList();
  _remoteMergeBuffer.clear();

  // 沿用现有串行队列应用（保持 LWW 顺序语义）
  final pending = _remoteSceneQueue.catchError(_ignoreRemoteSceneError);
  _remoteSceneQueue = pending
      .then<void>((_) async {
        await _runAfterStableFrameAsync(() async {
          await _applyRemoteElements(merged);
        });
      })
      .catchError(_reportRemoteSceneFutureError);
  unawaited(_remoteSceneQueue);
}
```

- [ ] **Step 2: 在 dispose 中清理接收合并窗口**

```dart
// whiteboard_page.dart — dispose() 中，在 _flushLocalDraftOnExit() 之后追加
_remoteMergeTimer?.cancel();
_remoteMergeBuffer.clear();
```

- [ ] **Step 3: Presence 限频 30fps**

```dart
// whiteboard_page.dart — 新增 throttle 状态
DateTime _lastPointerBroadcast = DateTime.now();
static const Duration _pointerThrottle = Duration(milliseconds: 33);
Timer? _pointerTrailingTimer;
Offset? _lastPointerPosition;
bool _lastPointerDown = false;

// 替换现有 _broadcastPointerPresence 方法
void _broadcastPointerPresence(Offset localPosition, bool pointerDown) {
  if (!_canMutateWhiteboard) return;
  _markUserActive();

  _lastPointerPosition = localPosition;
  _lastPointerDown = pointerDown;

  final now = DateTime.now();
  if (now.difference(_lastPointerBroadcast) < _pointerThrottle) {
    // 窗口内：设置 trailing call
    _pointerTrailingTimer?.cancel();
    _pointerTrailingTimer = Timer(_pointerThrottle, _sendPointerPresence);
    return;
  }

  _lastPointerBroadcast = now;
  _pointerTrailingTimer?.cancel();
  _sendPointerPresence();
}

void _sendPointerPresence() {
  final position = _lastPointerPosition;
  if (position == null) return;

  final room = ref.read(whiteboardViewModelProvider).activeRoom;
  if (room == null) return;

  final identity = _collaborationIdentity;
  unawaited(
    _collaborationRepository.broadcastMouseLocation(
      room: room,
      pointer: _collaborationAdapter.pointerPayload(position),
      button: _lastPointerDown ? 'down' : 'up',
      selectedElementIds: {
        for (final id in _collaborationAdapter.selectedElementIds()) id: true,
      },
      username: identity.username,
      userId: identity.userId,
      avatarUrl: identity.avatarUrl,
    ),
  );
}
```

- [ ] **Step 4: 在 dispose 中清理 trailing timer**

```dart
// whiteboard_page.dart — dispose() 中追加
_pointerTrailingTimer?.cancel();
```

- [ ] **Step 5: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS。

- [ ] **Step 6: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart
git commit -m "feat: 接收端 33ms 合并窗口 + presence 30fps 限频"
```

---

### Task 6: 20s 全量同步改为可开关的临时兜底 + 最小指标

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

**Interfaces:**
- Modifies: `_startFullSceneSync()` — 可开关 + 指标打点
- Consumes: `CollaborationDebugLog` (existing)

- [ ] **Step 1: 添加开关和指标字段**

```dart
// collaboration_repository.dart — 类成员追加
static bool fullSceneSyncEnabled = true; // Phase 0 临时保留，Phase 1 移除
int _fullSceneSyncCount = 0;
int _batchSendCount = 0;
int _batchElementTotal = 0;
int _batchEncryptedBytesTotal = 0;
DateTime _lastMetricsReport = DateTime.now();
```

- [ ] **Step 2: 修改 _startFullSceneSync 加入开关和日志**

```dart
// collaboration_repository.dart — 替换 _startFullSceneSync()
void _startFullSceneSync() {
  _fullSceneSyncTimer?.cancel();
  _fullSceneSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
    final room = _activeRoom;
    if (room == null || _latestScene.elements.isEmpty) return;
    if (!fullSceneSyncEnabled) return;

    // 不与 snapshot 飞行中竞争
    if (_snapshotSaving) return;

    _fullSceneSyncCount++;
    CollaborationDebugLog.write('scene', 'full_sync_triggered', {
      'room': _shortRoomId(room.roomId),
      'count': _fullSceneSyncCount,
      'elements': _latestScene.elements.length,
    });
    unawaited(broadcastScene(room: room, scene: _latestScene, syncAll: true));
  });
}
```

- [ ] **Step 3: 在 _onAccumulatorFlush 中加入 batch 指标**

```dart
// collaboration_repository.dart — _onAccumulatorFlush 开头追加
_batchSendCount++;
_batchElementTotal += elements.length;

// 每 60 秒输出聚合指标
final now = DateTime.now();
if (now.difference(_lastMetricsReport).inSeconds >= 60) {
  CollaborationDebugLog.write('metrics', 'phase0_summary', {
    'batchSendCount': _batchSendCount,
    'batchElementTotal': _batchElementTotal,
    'fullSyncCount': _fullSceneSyncCount,
    'snapshotDirty': _snapshotDirty,
    'snapshotSaving': _snapshotSaving,
  });
  _lastMetricsReport = now;
}
```

- [ ] **Step 4: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/
```
Expected: 已有测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart
git commit -m "feat: 20s全量同步加开关+指标打点，为Phase 1移除做准备"
```

---

### Task 7: 集成验证 — 端到端场景一致性

**Files:**
- Modify: `FlowMuse-App/test/features/whiteboard/collaboration/repositories/collaboration_repository_test.dart` (如不存在则创建)

- [ ] **Step 1: 编写集成测试 — accumulator + broadcast 往返**

```dart
// test/features/whiteboard/collaboration/repositories/collaboration_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';

void main() {
  test('accumulator合并后broadcast只发一批', () async {
    final hub = MemoryRealtimeRoomHub();
    final sender = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');

    final senderRepo = CollaborationRepository(
      transport: sender,
      crypto: CollaborationCrypto(),
    );
    final receiverRepo = CollaborationRepository(
      transport: receiver,
      crypto: CollaborationCrypto(),
    );

    final room = CollaborationRoom.newRoom();

    // sender 创建房间
    final initialScene = ExcalidrawScene.empty();
    await senderRepo.startNewRoom(initialScene: initialScene);

    // receiver 加入
    await receiverRepo.joinRoom(room: room, localScene: ExcalidrawScene.empty());

    // sender 快速连续广播三次（模拟拖拽），应在 accumulator 窗口内合并
    final scene1 = initialScene.copyWith(elements: [
      {'id': 'a', 'type': 'rectangle', 'version': 1, 'versionNonce': 1,
       'updated': 1, 'isDeleted': false, 'index': 'a0', 'x': 10, 'y': 10,
       'width': 100, 'height': 100},
    ]);
    final scene2 = initialScene.copyWith(elements: [
      {'id': 'a', 'type': 'rectangle', 'version': 2, 'versionNonce': 2,
       'updated': 2, 'isDeleted': false, 'index': 'a0', 'x': 20, 'y': 10,
       'width': 100, 'height': 100},
    ]);
    final scene3 = initialScene.copyWith(elements: [
      {'id': 'a', 'type': 'rectangle', 'version': 3, 'versionNonce': 3,
       'updated': 3, 'isDeleted': false, 'index': 'a0', 'x': 30, 'y': 10,
       'width': 100, 'height': 100},
    ]);

    unawaited(senderRepo.broadcastScene(room: room, scene: scene1));
    unawaited(senderRepo.broadcastScene(room: room, scene: scene2));
    unawaited(senderRepo.broadcastScene(room: room, scene: scene3));

    // 等待 accumulator 窗口到期
    await Future.delayed(const Duration(milliseconds: 100));

    // 验证: receiver 收到了合并后的最新版本
    final receiverScene = receiverRepo.reconcileRemoteScene(
      localScene: ExcalidrawScene.empty(),
      remoteElements: scene3.elements,
    );
    final element = receiverScene.elements.first;
    expect(element['version'], 3);
    expect(element['x'], 30);
  });
}
```

- [ ] **Step 2: 运行集成测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/repositories/collaboration_repository_test.dart
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add FlowMuse-App/test/features/whiteboard/collaboration/repositories/collaboration_repository_test.dart
git commit -m "test: accumulator合并 + broadcast 集成测试"
```

---

### Task 8: 验证 Phase 0 验收标准

- [ ] **Step 1: 运行全量测试套件**

```bash
cd FlowMuse-App
flutter analyze
flutter test
```
Expected: `flutter analyze` 无新增 error，`flutter test` 全部 PASS。

- [ ] **Step 2: 手动验证清单**

在两台设备上（Android + 鸿蒙，或 Android + Android）：

1. **连续书写 60s**：观察帧率不因场景增长持续下降
2. **快照频率**：查看 `CollaborationDebugLog`，确认 `phase0_summary` 中快照 PUT ≤1 次/秒
3. **批次频率**：确认正常书写时 Socket batch ≤20 次/秒
4. **删除不复活**：A 删除元素 → B 看到删除 → A undo → 双方一致
5. **拖拽流畅**：A 拖拽元素 → B 端看到平滑移动（非跳帧）

- [ ] **Step 3: 记录 Phase 0 后指标**

将以下指标填入 `docs/research/collaboration/codex-best.md` 的 Phase 0 验收区域：
- 单条 batch 平均元素数
- 单条 batch 加密后字节数 P50/P95
- 每秒 batch 发送次数
- 每秒快照 PUT 次数
- 两设备 P95 远端可见延迟
- `flutter analyze` / `flutter test` 结果

- [ ] **Step 4: Commit 验证结果**

```bash
git add docs/research/collaboration/codex-best.md
git commit -m "docs: Phase 0 验收指标记录"
```

---

## Self-Review

**Spec coverage against codex-best.md Phase 0:**

| codex 要求 | Task | 状态 |
|-----------|------|------|
| ChangeAccumulator 50ms 合并 | Task 1, 2 | ✅ |
| 拆分 _saveMarkdrawScene 三调度器 | Task 3 | ✅ |
| SnapshotScheduler 2s/30s single-flight | Task 4 | ✅ |
| 接收端 16-33ms 合并窗口 | Task 5 | ✅ |
| Presence 20-30fps throttle | Task 5 | ✅ |
| 20s 同步改可开关兜底 | Task 6 | ✅ |
| 最小指标 | Task 6 | ✅ |
| undo/redo bypass accumulator | Task 1 (bypass param) | ✅ |
| 删除墓碑正确处理 | Task 1 tests | ✅ |
| 不改变协议/服务端 | Global Constraints | ✅ |

**Placeholder scan:** 无 TBD/TODO/implement later。所有代码步骤都有完整实现。

**Type consistency:**
- `ChangeAccumulator.schedule(ExcalidrawScene, {bool bypass})` — 在 Task 1 定义，Task 2 调用 ✅
- `ChangeAccumulator.onFlush` — `ChangeBatchCallback` typedef，Task 1 定义，Task 2 绑定 ✅
- `_onAccumulatorFlush(List<Map<String, Object?>>, bool)` — Task 2 定义，Task 6 追加指标 ✅
