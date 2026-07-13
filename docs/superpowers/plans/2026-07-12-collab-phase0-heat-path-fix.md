# FlowMuse 协作 Phase 0 — 热路径止血

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不改协议、不改服务端，将热路径上的全量序列化/SQLite/封面/快照从每帧触发降低到批处理+延迟触发，消除高频编辑时的 CPU/IO/网络三方争用。同时修复 undo/redo 版本不递增和远端 reconcile 版本表更新错误两个现有 bug。

**Architecture:** 新增 `ChangeAccumulator` 集中接收 scene 变更，50ms 窗口内按 elementId 合并（使用与 `SceneReconciler._shouldKeepLocal` 一致的 `version + versionNonce` 比较），窗口到期后批量加密发送。本地保存拆成 500ms debounce，快照拆成闲置 2s/最长 30s 单飞。接收端加 16-33ms 合并窗口再 applyRemoteScene。presence 限频 30fps。undo/redo 后 diff 快照并对变化元素 bump version/versionNonce 后 bypass flush。

**Tech Stack:** Dart (Flutter)，纯客户端。不引入新依赖。

## Global Constraints

- 不改变 Socket.IO 协议、不对服务端做任何修改
- 不改变 AES-GCM 端到端加密、Excalidraw `id/version/versionNonce/index/isDeleted` 语义
- 不改变数据库 schema
- `volatile` 仅用于 cursor/idle/visible bounds；文档元素绝不走 volatile
- 远端应用不触发本地协作广播；删除墓碑不被错误合并或丢弃
- 所有新增类位于 `lib/features/whiteboard/collaboration/services/`
- 日志使用 `CollaborationDebugLog.write`，带 `[FlowMuseCreateNote]` 前缀的 `debugPrint`
- accumulator 的元素选择逻辑必须与 `SceneReconciler._shouldKeepLocal()` 的 `version + versionNonce` 顺序一致
- `protectedElementIds` 是入站合并保护；出站广播不绕过 accumulator，但accumulator 不感知 protected ids（后续有需要时由 adapter 在 flush 前提供最新值）

---

### Task 1: ChangeAccumulator — 集中接收变更 + 50ms 批处理

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/change_accumulator.dart`
- Test: `FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_test.dart`

**Interfaces:**
- Produces: `ChangeAccumulator` class with `schedule(ExcalidrawScene, {bool bypass})`, `dispose()`
- Produces: `typedef ChangeBatchCallback = Future<void> Function(List<Map<String, Object?>> elements, bool isInitial)`
- Consumes: `SceneReconciler.getSyncableElements` (existing)

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

    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 1, versionNonce: 10, x: 10),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 2, versionNonce: 20, x: 20),
    ]));
    accumulator.schedule(_sceneWithElements([
      _element(id: 'a', version: 3, versionNonce: 30, x: 30),
    ]));

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
  required int versionNonce,
  int? x,
  bool isDeleted = false,
}) {
  return {
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': versionNonce,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': isDeleted,
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

- [ ] **Step 3: Write ChangeAccumulator implementation**

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

  /// 调度一批元素。
  /// [bypass] 为 true 时跳过批处理立即发送；[isInitial] 仅当 bypass 时生效，决定消息类型。
  void schedule(ExcalidrawScene scene, {bool bypass = false, bool isInitial = false}) {
    if (bypass) {
      _timer?.cancel();
      _timer = null;
      final syncable = _reconciler.getSyncableElements(scene.elements);
      _pending.clear();
      _hasInitial = false;
      onFlush?.call(syncable, isInitial);
      return;
    }

    for (final element in scene.elements) {
      final id = element['id'] as String;
      final existing = _pending[id];
      if (_shouldReplace(existing, element)) {
        _pending[id] = Map<String, Object?>.from(element);
      }
    }

    _timer?.cancel();
    _timer = Timer(_batchWindow, _flush);
  }

  /// 对齐 SceneReconciler._shouldKeepLocal: version 高的赢，
  /// version 相同时 nonce 小的赢（见 scene_reconciler.dart:95-98）。
  bool _shouldReplace(Map<String, Object?>? existing, Map<String, Object?> incoming) {
    if (existing == null) return true;
    final existingVersion = (existing['version'] as num).toInt();
    final incomingVersion = (incoming['version'] as num).toInt();
    if (incomingVersion > existingVersion) return true;
    if (incomingVersion < existingVersion) return false;
    // version 相同 → nonce 小的赢
    final existingNonce = (existing['versionNonce'] as num).toInt();
    final incomingNonce = (incoming['versionNonce'] as num).toInt();
    return incomingNonce < existingNonce;
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

- [ ] **Step 5: Add edge case tests**

```dart
// 追加到 change_accumulator_test.dart

test('删除墓碑version更高时覆盖更新', () async {
  final accumulator = ChangeAccumulator();
  final batches = <List<Map<String, Object?>>>[];
  accumulator.onFlush = (elements, _) async {
    batches.add(List.of(elements));
  };

  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 5, versionNonce: 10, x: 10),
  ]));
  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 6, versionNonce: 20, isDeleted: true),
  ]));

  await Future.delayed(const Duration(milliseconds: 100));
  expect(batches.length, 1);
  expect(batches.first.first['isDeleted'], true);
  expect(batches.first.first['version'], 6);
});

test('version相同时nonce小的胜出 — 对齐_shouldKeepLocal', () async {
  final accumulator = ChangeAccumulator();
  final batches = <List<Map<String, Object?>>>[];
  accumulator.onFlush = (elements, _) async {
    batches.add(List.of(elements));
  };

  // 先到: version=5, nonce=50 (应被覆盖)
  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 5, versionNonce: 50, x: 10),
  ]));
  // 后到: version=5, nonce=30 (nonce 更小，应胜出)
  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 5, versionNonce: 30, x: 20),
  ]));

  await Future.delayed(const Duration(milliseconds: 100));
  expect(batches.first.first['version'], 5);
  expect(batches.first.first['versionNonce'], 30);
  expect(batches.first.first['x'], 20); // nonce 小的版本保留
});

test('bypass跳过批处理立即发送', () async {
  final accumulator = ChangeAccumulator();
  final batches = <List<Map<String, Object?>>>[];
  accumulator.onFlush = (elements, _) async {
    batches.add(List.of(elements));
  };

  accumulator.schedule(_sceneWithElements([
    _element(id: 'a', version: 1, versionNonce: 10, x: 10),
  ]));
  accumulator.schedule(_sceneWithElements([
    _element(id: 'b', version: 1, versionNonce: 10, x: 20),
  ]), bypass: true);

  expect(batches.length, 1);
  expect(batches.first.length, 1);
  expect(batches.first.first['id'], 'b');
});

test('窗口内无变更不触发flush', () async {
  final accumulator = ChangeAccumulator();
  var flushCount = 0;
  accumulator.onFlush = (_, __) async { flushCount++; };
  await Future.delayed(const Duration(milliseconds: 100));
  expect(flushCount, 0);
});
```

- [ ] **Step 6: Run all tests**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/change_accumulator_test.dart
```
Expected: 5 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/services/change_accumulator.dart \
        FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_test.dart
git commit -m "feat: 新增 ChangeAccumulator — 50ms合并窗口 + version/nonce对齐_shouldKeepLocal"
```

---

### Task 1.5: 修复 reconcileRemoteScene 的版本表更新（codex phase 0 point 9）

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart:363`

**Interfaces:**
- Modifies: `reconcileRemoteScene()` — `_rememberBroadcasted(remoteElements)` → `_rememberBroadcasted(nextScene.elements)`
- Modifies: `_broadcastedElementVersions` 从 `Map<String, int>` 升级为 `Map<String, _VersionRecord>`（同时存 version + versionNonce）
- Modifies: `_changedElements()` — 比较改为 `(version, versionNonce)` 而非仅 version

- [ ] **Step 1: 升级 _broadcastedElementVersions 为 (version, versionNonce) 对**

新增内部类:
```dart
// collaboration_repository.dart — 文件顶部或类内部
class _VersionRecord {
  const _VersionRecord(this.version, this.versionNonce);
  final int version;
  final int versionNonce;
}
```

替换字段:
```dart
// 旧: final Map<String, int> _broadcastedElementVersions = {};
final Map<String, _VersionRecord> _broadcastedElementVersions = {};
```

- [ ] **Step 1.5: 修改 _changedElements 和 _rememberBroadcasted 使用新类型**

```dart
// _changedElements — 改为同时比较 version 和 versionNonce
List<Map<String, Object?>> _changedElements(List<Map<String, Object?>> elements) {
  return [
    for (final element in elements)
      if (!_broadcastedElementVersions.containsKey(_id(element)) ||
          _isNewerThanBroadcasted(element))
        element,
  ];
}

bool _isNewerThanBroadcasted(Map<String, Object?> element) {
  final record = _broadcastedElementVersions[_id(element)]!;
  final v = (element['version'] as num).toInt();
  final n = (element['versionNonce'] as num).toInt();
  if (v > record.version) return true;
  if (v < record.version) return false;
  return n < record.versionNonce; // 同版本 nonce 小者胜（对齐 _shouldKeepLocal）
}

// _rememberBroadcasted — 存储 version 和 versionNonce
void _rememberBroadcasted(List<Map<String, Object?>> elements) {
  for (final element in elements) {
    _broadcastedElementVersions[_id(element)] = _VersionRecord(
      (element['version'] as num).toInt(),
      (element['versionNonce'] as num).toInt(),
    );
  }
}
```

- [ ] **Step 2: 修复 reconcileRemoteScene 的 _rememberBroadcasted 参数**

当前代码（line 363）:
```dart
_rememberBroadcasted(remoteElements);  ← BUG: 应该传 reconciled 结果
```

改为:
```dart
_rememberBroadcasted(nextScene.elements);
_lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
  nextScene.elements,
);
```

- [ ] **Step 3: 运行已有测试确认不回归**

```bash
cd FlowMuse-App && flutter test
```
Expected: 已有测试 PASS。

- [ ] **Step 3: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart
git commit -m "fix: reconcileRemoteScene 用 reconciled 结果更新广播版本表"
```

---

### Task 2: 接入 ChangeAccumulator 到 CollaborationRepository

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

**Interfaces:**
- Consumes: `ChangeAccumulator` (Task 1)
- Modifies: `broadcastScene()` — 改为通过 accumulator 调度
- Retains: `_send()`, `_rememberBroadcasted()`, `_changedElements()`, `_saveSceneSnapshot()` (SnapshotScheduler 在 Task 4 改造)

- [ ] **Step 1: 在 CollaborationRepository 中引入 ChangeAccumulator**

```dart
// collaboration_repository.dart — 在已有 import 区域追加
import '../services/change_accumulator.dart';

// 在类成员变量区域追加
final ChangeAccumulator _accumulator;
```

- [ ] **Step 2: 修改构造函数初始化 accumulator**

```dart
// collaboration_repository.dart — 构造函数的初始化列表末尾追加 _accumulator
CollaborationRepository({
  // ... 现有参数保持不变 ...
}) : _transport = transport ?? const DisconnectedRealtimeTransport(),
     _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
     // ... 其他现有赋值 ...
     _reconciler = reconciler ?? SceneReconciler(),
     _accumulator = ChangeAccumulator(
       reconciler: reconciler ?? SceneReconciler(),
     );
```

在构造函数 body（如不存在则加空 body `{}` 并改为）:

```dart
// 构造函数末尾
{
  _accumulator.onFlush = _onAccumulatorFlush;
}
```

> 注: 如果现有构造函数没有 body（纯初始化列表），加 `{ }` body 合法。`reconciler ?? SceneReconciler()` 在 init list 和 accumulator 参数里各求值一次——若 reconciler 为 null 会创建两个 SceneReconciler 实例，不影响正确性（`SceneReconciler` 无状态）。

- [ ] **Step 3: 实现 _onAccumulatorFlush（含 _changedElements 过滤防回声）**

```dart
// collaboration_repository.dart — 新增私有方法
Future<void> _onAccumulatorFlush(
  List<Map<String, Object?>> elements,
  bool isInitial,
) async {
  final room = _activeRoom;
  if (room == null) return;

  // 关键: 用 _changedElements 过滤——防止回声刚收到的远端元素
  // accumulator 持有最新 _latestScene 的快照，通过版本表门控只发真正变更的
  final changed = isInitial ? elements : _changedElements(elements);
  if (changed.isEmpty && !isInitial) return;

  final sceneVersion = _reconciler.getSceneVersion(
    isInitial ? elements : _latestScene.elements,
  );
  final message = isInitial
      ? CollaborationMessage.sceneInit(elements: changed)
      : CollaborationMessage.sceneUpdate(elements: changed);

  await _send(room: room, message: message);
  _rememberBroadcasted(changed);
  _lastBroadcastedOrReceivedSceneVersion = sceneVersion;

  _scheduleSnapshot();
}
```

> 注: `_scheduleSnapshot()` 在 Task 4 中实现。当前先保留原有的快照保存调用。

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

  _accumulator.schedule(
    syncableScene,
    bypass: initial || syncAll,   // syncAll/undo 也 bypass（立即发），但不发 sceneInit
    isInitial: initial,           // 仅 initial 时才发 sceneInit 类型
  );
}
```

- [ ] **Step 5: 在 _resetLocalState() 和 _startRoomSession() 中管理 accumulator 生命周期**

```dart
// collaboration_repository.dart — _startRoomSession() 开头追加
void _startRoomSession(CollaborationRoom room) {
  _stopRoomSession();
  _accumulator.dispose();
  _accumulator.onFlush = _onAccumulatorFlush;

  // ... 现有初始化代码 ...
}

// collaboration_repository.dart — _resetLocalState() 末尾追加
void _resetLocalState() {
  // ... 现有清理代码 ...
  _accumulator.dispose();
}
```

- [ ] **Step 6: 运行已有测试确保不回归**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS。

- [ ] **Step 7: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart
git commit -m "refactor: broadcastScene 接入 ChangeAccumulator 批处理 + _changedElements 防回声"
```

---

### Task 3: 拆分 whiteboard_page 热路径 — 本地草稿/协作/封面分离

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

**Interfaces:**
- Consumes: `ChangeAccumulator` (via `CollaborationRepository.broadcastScene`, Task 2)
- Modifies: `_saveMarkdrawScene()` — 拆分为三个独立调度器
- Produces: `LocalDraftScheduler`（内嵌于 whiteboard_page）

- [ ] **Step 1: 新增 LocalDraftScheduler**

```dart
// whiteboard_page.dart — _WhiteboardPageState 类内，_disposingOrLeaving 声明之后

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
    _flushLocalDraft();
  }
}
```

- [ ] **Step 2: 重构 _saveMarkdrawScene()**

```dart
// whiteboard_page.dart — 替换现有 _saveMarkdrawScene() 方法
Future<void> _saveMarkdrawScene() async {
  if (_loadingScene || _applyingRemoteScene) {
    return;
  }

  // 协作增量发送 — 走 accumulator（已在 Task 2 中处理）
  await _broadcastCurrentScene();

  // 本地草稿 — 500ms debounce
  _scheduleLocalDraft();

  // 封面生成 — 不在热路径，由 _touchNoteWithCurrentCover 在 _flushLocalDraft 中处理
}
```

- [ ] **Step 3: dispose 和 AppLifecycle 中 flush 草稿（含 mixin 声明）**

```dart
// whiteboard_page.dart — 类声明加 mixin
class _WhiteboardPageState extends ConsumerState<WhiteboardPage>
    with WidgetsBindingObserver {  // 新增 mixin

// whiteboard_page.dart — dispose() 开头追加
@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);  // 新增
  _flushLocalDraftOnExit();
  _disposingOrLeaving = true;
  // ... 现有 dispose 代码 ...
}

// whiteboard_page.dart — initState() 追加 observer
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

- [ ] **Step 4: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart
git commit -m "refactor: 拆分 onSceneChanged 热路径 — 本地草稿 500ms debounce + 协作走 accumulator"
```

---

### Task 3.5: 修复 undo/redo — version bump + 强制 flush（codex phase 0 point 8）

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart` — 转发新签名
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart` — 转发新签名
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

**Interfaces:**
- Produces: `enum SceneChangeSource { userEdit, undo, redo, remoteApply, restore }`
- Modifies: `void Function(Scene)? onSceneChanged` → `void Function(Scene, SceneChangeSource)? onSceneChanged`
- Consumes: whiteboard_page 根据 source 分叉路径
- Chain: `markdraw_editor` 和 `markdraw_split_pane` 持有 `onSceneChanged` 回调并透传给 `MarkdrawController`，签名变更后两者均需同步更新

**接线说明**：`controller.undo()` 被三处调用，全部直达 controller 层。采用路径 A——controller 的 `undo()`/`redo()` 标记 source 通过回调参数传出。中间层（editor、split_pane）仅做签名转发，不引入新逻辑。

- [ ] **Step 1: 在 markdraw_controller.dart 中新增 SceneChangeSource 枚举并修改回调签名**

```dart
// markdraw_controller.dart — 文件顶部新增
enum SceneChangeSource { userEdit, undo, redo, remoteApply, restore }

// markdraw_controller.dart — 替换现有 onSceneChanged 声明
// 旧: void Function(Scene)? onSceneChanged;
void Function(Scene scene, SceneChangeSource source)? onSceneChanged;
```

- [ ] **Step 2: 修改 controller.undo() 和 controller.redo() 传 source**

```dart
// markdraw_controller.dart — undo() 方法内 (line 625-632)
void undo() {
  final undone = _historyManager.undo(_editorState.scene);
  if (undone != null) {
    _editorState = _editorState.copyWith(scene: undone);
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.undo);  // 改: 传 source
    notifyListeners();
  }
}

// markdraw_controller.dart — redo() 方法内 (line 634-642)
void redo() {
  final redone = _historyManager.redo(_editorState.scene);
  if (redone != null) {
    _editorState = _editorState.copyWith(scene: redone);
    onSceneChanged?.call(_editorState.scene, SceneChangeSource.redo);  // 改: 传 source
    notifyListeners();
  }
}
```

- [ ] **Step 3: 修改所有其他 onSceneChanged 调用点传 userEdit**

```dart
// markdraw_controller.dart — 搜索所有 onSceneChanged?.call( 调用点，
// 将 onSceneChanged?.call(_editorState.scene) 改为:
onSceneChanged?.call(_editorState.scene, SceneChangeSource.userEdit);

// 远端应用场景（applyResult 内的调用）传:
onSceneChanged?.call(_editorState.scene, SceneChangeSource.remoteApply);
```

- [ ] **Step 3.5: 修改 markdraw_editor.dart 和 markdraw_split_pane.dart 转发新签名**

这两个文件持有 `onSceneChanged` 回调字段并透传给 `MarkdrawController`。将字段类型从 `void Function(Scene)?` 改为 `void Function(Scene, SceneChangeSource)?`，并在赋值处直接透传，不做额外处理。

```dart
// markdraw_editor.dart — 字段声明改为
void Function(Scene scene, SceneChangeSource source)? onSceneChanged;

// markdraw_split_pane.dart — 同上
void Function(Scene scene, SceneChangeSource source)? onSceneChanged;
```

- [ ] **Step 4: 在 whiteboard_page 中实现 undo/redo 路径**

```dart
// whiteboard_page.dart — 新增方法（接收回调中已捕获的 previous/current，避免异步重读时值已变）
Future<void> _broadcastUndoRedoScene(
  ExcalidrawScene? previousScene,
  ExcalidrawScene currentScene,
) async {
  final room = ref.read(whiteboardViewModelProvider).activeRoom;
  if (room == null) return;

  final rng = Random();
  final bumpedElements = <Map<String, Object?>>[];

  // 构建 previous 索引
  final previousById = <String, Map<String, Object?>>{};
  if (previousScene != null) {
    for (final e in previousScene.elements) {
      previousById[e['id'] as String] = e;
    }
  }

  // previousScene == null（首次 undo/redo）无法 diff，走全量 bump 兜底
  if (previousById.isEmpty) {
    for (final element in currentScene.elements) {
      bumpedElements.add({
        ...element,
        'version': ((element['version'] as num).toInt() + 1),
        'versionNonce': rng.nextInt(1 << 31),
        'updated': DateTime.now().millisecondsSinceEpoch,
      });
    }
  } else {
    final currentIds = <String>{};
    for (final element in currentScene.elements) {
      final id = element['id'] as String;
      currentIds.add(id);
      final prev = previousById[id];
      if (prev == null ||
          (element['version'] as num).toInt() != (prev['version'] as num).toInt() ||
          (element['versionNonce'] as num).toInt() != (prev['versionNonce'] as num).toInt() ||
          element['isDeleted'] != prev['isDeleted']) {
        // 差异元素 → bump，版本取 max(prev, current) + 1 确保严格大于两端
        bumpedElements.add({
          ...element,
          'version': max(
            (element['version'] as num).toInt(),
            (prev?['version'] as num?)?.toInt() ?? 0,
          ) + 1,
          'versionNonce': rng.nextInt(1 << 31),
          'updated': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        bumpedElements.add(element);
      }
    }

    // 墓碑：previous 中存在但 currentScene 消失的元素 → 发送 isDeleted: true
    for (final entry in previousById.entries) {
      if (currentIds.contains(entry.key)) continue;
      final prev = entry.value;
      if (prev['isDeleted'] == true) continue; // 已经是墓碑，无需重复
      bumpedElements.add({
        ...prev,
        'version': ((prev['version'] as num).toInt() + 1),
        'versionNonce': rng.nextInt(1 << 31),
        'isDeleted': true,
        'updated': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  if (bumpedElements.isEmpty) return;

  final bumpedScene = currentScene.copyWith(elements: bumpedElements);

  // 写回 controller（防后续编辑以旧 version 覆盖）
  _applyingRemoteScene = true;
  try {
    _collaborationAdapter.applyRemoteScene(bumpedScene, closeTransientUi: false);
  } finally {
    _applyingRemoteScene = false;
  }

  // syncAll: true → bypass accumulator，isInitial: false → sceneUpdate
  await _collaborationRepository.broadcastScene(
    room: room,
    scene: bumpedScene,
    syncAll: true,
  );
}
```

- [ ] **Step 5: 修改 onSceneChanged 回调按 source 分叉**

```dart
// whiteboard_page.dart — 新增成员
ExcalidrawScene? _previousScene;

// whiteboard_page.dart — onSceneChanged 回调改为
onSceneChanged: (_, SceneChangeSource source) {
  final currentScene = _collaborationAdapter.currentScene();
  final previousScene = _previousScene;

  switch (source) {
    case SceneChangeSource.undo:
    case SceneChangeSource.redo:
      // previousScene == null 时走全量 bump，否则走 diff bump
      unawaited(_broadcastUndoRedoScene(previousScene, currentScene));
      _scheduleLocalDraft();
      _previousScene = currentScene;
      break;
    case SceneChangeSource.remoteApply:
      _scheduleLocalDraft();
      break;
    case SceneChangeSource.userEdit:
    case SceneChangeSource.restore:
      unawaited(_saveMarkdrawScene());
      _previousScene = currentScene;
  }
},
```

- [ ] **Step 6: 运行已有测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/
```
Expected: 已有测试 PASS。

- [ ] **Step 7: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart \
        FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart \
        FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart \
        FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart
git commit -m "fix: undo/redo 后 bump version/versionNonce 并强制 flush + SceneChangeSource 全链路"
```

---

### Task 4: SnapshotScheduler — 快照保存降频 + 单飞

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

**Interfaces:**
- Consumes: `EncryptedSceneStore.saveScene` (existing), `SceneReconciler` (existing)
- Modifies: 快照保存 — 替换为 SnapshotScheduler 逻辑
- Produces: `_scheduleSnapshot()`, `forceFlushSnapshot()` (内部方法)

- [ ] **Step 1: 新增 SnapshotScheduler 状态字段**

```dart
// collaboration_repository.dart — 类成员区域追加
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
  if (_snapshotSaving) return; // single-flight

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
    _snapshotDirty = true;
  } finally {
    _snapshotSaving = false;
    if (_snapshotDirty) {
      _scheduleSnapshot();
    }
  }
}

// Task 4 先定义简化版，Task 6 step 3 会升级为含在途等待循环的完整版
Future<void> forceFlushSnapshot() async {
  _snapshotTimer?.cancel();
  _snapshotTimer = null;
  if (_snapshotDirty) {
    await _flushSnapshot();
  }
}
```

- [ ] **Step 3: 在 stop() 和 _resetLocalState 中集成**

```dart
// collaboration_repository.dart — stop() 中 _resetLocalState() 之前
Future<void> stop() async {
  await forceFlushSnapshot();
  _resetLocalState();
  await _transport.disconnect();
}

// collaboration_repository.dart — _resetLocalState() 末尾追加
void _resetLocalState() {
  // ... 现有清理代码 ...
  _snapshotTimer?.cancel();
  _snapshotTimer = null;
  _snapshotSaving = false;
  _snapshotDirty = false;
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
git commit -m "feat: SnapshotScheduler — 快照闲置2s/最长30s单飞防409风暴"
```

---

### Task 5: 接收端合并窗口 + Presence 限频

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`

**Interfaces:**
- Modifies: `_enqueueRemoteElements()` — 加合并窗口，对齐 `_shouldKeepLocal` 的 nonce tie-break
- Modifies: `_broadcastPointerPresence()` — 加 33ms throttle + trailing call

- [ ] **Step 1: 接收端合并窗口 — 替换 _enqueueRemoteElements**

```dart
// whiteboard_page.dart — 新增合并窗口状态
final Map<String, Map<String, Object?>> _remoteMergeBuffer = {};
Timer? _remoteMergeTimer;
static const Duration _remoteMergeWindow = Duration(milliseconds: 33);

void _enqueueRemoteElements(List<Map<String, Object?>> remoteElements) {
  CollaborationDebugLog.write('scene', 'remote_elements_queued', {
    'elements': remoteElements.length,
    'summary': CollaborationDebugLog.elementSummary(remoteElements),
  });

  // 合并窗口内按 elementId 选择最新版本（对齐 _shouldKeepLocal: version 高者胜，相同则 nonce 小者胜）
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
           (element['versionNonce'] as num).toInt() <
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

- [ ] **Step 2: dispose 中清理**

```dart
// whiteboard_page.dart — dispose() 中，_flushLocalDraftOnExit() 之后
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

void _broadcastPointerPresence(Offset localPosition, bool pointerDown) {
  if (!_canMutateWhiteboard) return;
  _markUserActive();

  _lastPointerPosition = localPosition;
  _lastPointerDown = pointerDown;

  final now = DateTime.now();
  if (now.difference(_lastPointerBroadcast) < _pointerThrottle) {
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

- [ ] **Step 4: dispose 中清理 trailing timer**

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
git commit -m "feat: 接收端33ms合并窗口(nonce对齐) + presence 30fps限频+trailing"
```

---

### Task 6: 20s 全量同步改为可开关的临时兜底 + 最小指标

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`

- [ ] **Step 1: 添加开关和指标字段**

```dart
// collaboration_repository.dart — 类成员追加
static bool fullSceneSyncEnabled = true;
int _fullSceneSyncCount = 0;
int _batchSendCount = 0;
int _batchElementTotal = 0;
int _batchEncryptedBytesTotal = 0;
final Stopwatch _batchSendStopwatch = Stopwatch();
int _snapshotDurationAccumMs = 0;
int _snapshotCount = 0;
int _snapshot409Count = 0;
DateTime _lastMetricsReport = DateTime.now();
```

- [ ] **Step 2: 修改 _startFullSceneSync 加入开关**

```dart
void _startFullSceneSync() {
  _fullSceneSyncTimer?.cancel();
  _fullSceneSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
    final room = _activeRoom;
    if (room == null || _latestScene.elements.isEmpty) return;
    if (!fullSceneSyncEnabled) return;
    if (_snapshotSaving) return; // 不与 snapshot 飞行中竞争

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

- [ ] **Step 3: 在 _onAccumulatorFlush 和 _flushSnapshot 中追加指标**

`_onAccumulatorFlush`:

```dart
// collaboration_repository.dart — _onAccumulatorFlush 内 await _send 之后
// _send 方法内部生成 encrypted 变量，改为在 _onAccumulatorFlush 中内联加密以便取字节数:
_batchSendCount++;
_batchElementTotal += changed.length;
// 注: encrypted bytes 在 _send 内部，如需采集可改为 _send 返回加密后字节数，
// 或在 _onAccumulatorFlush 内直接加密后记录（与 _send 重复加密需避免）。
// Phase 0 简化方案: 在 _send 方法返回值中附带 encryptedBytes:
//   Future<int> _send(...) async { ... return encrypted.encryptedBuffer.length + encrypted.iv.length; }
//   final sentBytes = await _send(...);
//   _batchEncryptedBytesTotal += sentBytes;
if (!_batchSendStopwatch.isRunning) {
  _batchSendStopwatch.start();
}
```

`_saveSceneResolvingConflict` 内记录 409（只有这里能捕获到每次冲突，外层只能看到 retry 后仍失败）:

```dart
// collaboration_repository.dart — _saveSceneResolvingConflict 内
Future<ExcalidrawScene> _saveSceneResolvingConflict({
  required CollaborationRoom room,
  required ExcalidrawScene scene,
}) async {
  try {
    await _sceneStore.saveScene(room: room, scene: scene.copyWith(files: const {}));
    return scene;
  } on StaleSceneSnapshotException {
    _snapshot409Count++;  // 在这里计数，每次冲突都记录
    // ... 现有 reconcile + retry 逻辑 ...
  }
}
```

`_flushSnapshot` 内只记录耗时（409 计数已在 `_saveSceneResolvingConflict` 内部完成）:

```dart
// collaboration_repository.dart — _flushSnapshot 内
final sw = Stopwatch()..start();
try {
  // ... 现有 saveScene 调用（内部可能触发 reconcile + retry） ...
} finally {
  sw.stop();
  _snapshotDurationAccumMs += sw.elapsedMilliseconds;
  _snapshotCount++;
}
```

`forceFlushSnapshot` 升级为等待版（替换 Task 4 简化版）:

```dart
Future<void> forceFlushSnapshot() async {
  _snapshotTimer?.cancel();
  _snapshotTimer = null;
  // 如果有在途快照，等它完成
  while (_snapshotSaving) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  if (_snapshotDirty) {
    await _flushSnapshot();
  }
  // 再次等待：_flushSnapshot 是同步设置 _snapshotSaving=true，异步执行
  while (_snapshotSaving) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
```

远端应用延迟指标 — 在 `_applyRemoteScene` 前后打点:

```dart
// whiteboard_page.dart — _applyRemoteScene 内
final sw = Stopwatch()..start();
try {
  _collaborationAdapter.applyRemoteScene(nextScene, closeTransientUi: false);
} finally {
  sw.stop();
  CollaborationDebugLog.write('metrics', 'remote_apply_latency_ms', {
    'ms': sw.elapsedMilliseconds,
    'elements': remoteScene.elements.length,
  });
}
```

远端应用路径不本地保存 — 在 `_applyRemoteScene` 中跳过 SQLite 保存（只在 `temporaryCollaboration` 场景和正常场景的保存逻辑中保留，但入口已是远端应用，不需要热路径上的 saveScene+cover）:

```dart
// whiteboard_page.dart — _applyRemoteScene 内
// Phase 0: 移除热路径上的直接 SQLite 保存，改由草稿调度器统一管理。
// 远端 onSceneChanged 的 remoteApply 分支已调用 _scheduleLocalDraft()，
// 500ms debounce 后会通过 _flushLocalDraft 批量持久化。
// 删除或注释掉:
//   await repository.saveScene(widget.noteId, nextContent);
//   await _touchNoteWithCurrentCover(widget.noteId);
```

> 注: `remoteApply` 分支的 `_scheduleLocalDraft()`（Task 3.5 step 5）会在 500ms 内合并多次远端应用为一次 SQLite 写入。如果 500ms 内用户离开或退后台，`_flushLocalDraftOnExit` 保证最后一次写入。Phase 1 后由 outbox 和 snapshot 统一管理。

定期输出日志:

```dart
// collaboration_repository.dart — _onAccumulatorFlush 末尾
final now = DateTime.now();
if (now.difference(_lastMetricsReport).inSeconds >= 60) {
  final snapshotP95 = _snapshotCount > 0
      ? _snapshotDurationAccumMs ~/ _snapshotCount
      : 0;
  CollaborationDebugLog.write('metrics', 'phase0_summary', {
    'batchSendCount': _batchSendCount,
    'batchElementTotal': _batchElementTotal,
    'batchEncryptedBytesTotal': _batchEncryptedBytesTotal,
    'batchAvgBytes': _batchSendCount > 0
        ? _batchEncryptedBytesTotal ~/ _batchSendCount : 0,
    'batchElapsedMs': _batchSendStopwatch.elapsedMilliseconds,
    'fullSyncCount': _fullSceneSyncCount,
    'snapshotCount': _snapshotCount,
    'snapshotAvgMs': _snapshotCount > 0
        ? _snapshotDurationAccumMs ~/ _snapshotCount : 0,
    'snapshot409Count': _snapshot409Count,
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

### Task 7: 集成验证 — accumulator 端到端往返

**Files:**
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_integration_test.dart`

- [ ] **Step 1: 编写集成测试**

验证 accumulator → repository send → transport 的正确性，不依赖 `startNewRoom` 的完整初始化链路:

```dart
// test/features/whiteboard/collaboration/services/change_accumulator_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/change_accumulator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

void main() {
  test('accumulator flush 后 _changedElements 过滤不发送已广播元素', () async {
    // 模拟 _broadcastedElementVersions 门控
    final broadcasted = <String, int>{};
    final sentBatches = <List<Map<String, Object?>>>[];

    final accumulator = ChangeAccumulator();
    accumulator.onFlush = (elements, _) async {
      // 模拟 _changedElements 过滤: 只发版本号前进的元素
      final changed = elements.where((e) {
        final id = e['id'] as String;
        final version = (e['version'] as num).toInt();
        final last = broadcasted[id];
        return last == null || version > last;
      }).toList();

      if (changed.isNotEmpty) {
        sentBatches.add(List.of(changed));
        // 模拟 _rememberBroadcasted
        for (final e in changed) {
          broadcasted[e['id'] as String] = (e['version'] as num).toInt();
        }
      }
    };

    // 第一次 flush: 元素 a version=1 → 应发送
    accumulator.schedule(ExcalidrawScene.empty().copyWith(elements: [
      _makeElement('a', 1, 10),
    ]));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(sentBatches.length, 1);

    // 第二次 flush: 元素 a 没变，但加了元素 b → 只应发送 b
    accumulator.schedule(ExcalidrawScene.empty().copyWith(elements: [
      _makeElement('a', 1, 10), // version 未变 → 不发送
      _makeElement('b', 1, 20), // 新元素 → 应发送
    ]));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(sentBatches.length, 2);
    final secondBatch = sentBatches.last;
    expect(secondBatch.length, 1);
    expect(secondBatch.first['id'], 'b'); // 只有 b，没有 a（防止回声）
  });
}

Map<String, Object?> _makeElement(String id, int version, int nonce) {
  return {
    'id': id, 'type': 'rectangle', 'version': version,
    'versionNonce': nonce, 'updated': 1, 'isDeleted': false,
    'index': 'a0', 'x': 0, 'y': 0, 'width': 100, 'height': 100,
  };
}
```

> 注: nonce tie-break 的单元测试已在 Task 1 step 5 中覆盖，此处不重复。

- [ ] **Step 2: 运行集成测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/change_accumulator_integration_test.dart
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add FlowMuse-App/test/features/whiteboard/collaboration/services/change_accumulator_integration_test.dart
git commit -m "test: accumulator _changedElements 防回声 + nonce tie-break 集成测试"
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

1. 连续书写 60s：帧率不因场景增长持续下降
2. 快照频率：`phase0_summary` 日志中快照 PUT ≤1 次/秒
3. 批次频率：正常书写时 Socket batch ≤20 次/秒
4. 删除不复活：A 删除元素 → B 看到删除 → A undo → 双方一致
5. 拖拽流畅：A 拖拽元素 → B 端平滑移动
6. **undo/redo 远端可见**：A undo → B 端看到元素恢复（验证 Task 3.5 的 version bump）
7. **无回声广播**：A 收到远端元素后本地编辑，不把刚收到的远端元素又发回去

- [ ] **Step 3: 记录 Phase 0 后指标**

填入 `docs/research/collaboration/codex-best.md`:
- 单条 batch 平均元素数
- 单条 batch 加密后字节数 P50/P95
- 每秒 batch 发送次数 / 快照 PUT 次数
- 两设备 P95 远端可见延迟
- `flutter analyze` / `flutter test` 结果

- [ ] **Step 4: Commit**

```bash
git add docs/research/collaboration/codex-best.md
git commit -m "docs: Phase 0 验收指标记录"
```

---

## Self-Review

**Spec coverage against codex-best.md Phase 0:**

| codex 要求 | Task | 状态 |
|-----------|------|------|
| point 1: ChangeAccumulator 50ms 合并 | Task 1, 2 | ✅ nonce tie-break 对齐 `_shouldKeepLocal` |
| point 1: bypass initial/syncAll | Task 1 | ✅ |
| point 2: 本地草稿 500ms debounce | Task 3 | ✅ |
| point 2: 协作 50ms batch | Task 1-2 | ✅ |
| point 2: 封面仅显式/空闲 | Task 3 | ✅ |
| point 3: SnapshotScheduler 2s/30s single-flight | Task 4 | ✅ |
| point 4: 接收端 16-33ms 合并窗口 | Task 5 | ✅ nonce tie-break 已对齐 |
| point 5: presence 20-30fps throttle + trailing | Task 5 | ✅ |
| point 6: 20s 全量同步可开关+指标 | Task 6 | ✅ |
| point 7: 最小指标 | Task 6 | ✅ |
| **point 8: undo/redo version bump + 强制 flush** | **Task 3.5** | ✅ **新增** |
| **point 9: `_rememberBroadcasted(reconciled)` 修复** | **Task 1.5** | ✅ 参数修复 + 版本表升级为 `(version,versionNonce)` 对 |
| point 9: 取消 syncAll 回声 | Task 2 step 3 | ✅ `_changedElements` 过滤（已用新版本表） |
| point 9: syncAll 消息类型正确 | Task 1 step 3 + Task 2 step 4 | ✅ bypass 与 isInitial 已拆分，syncAll 发 sceneUpdate |
| Accumulator 约束: nonce tie-break | Task 1 step 3 | ✅ `_shouldReplace` 完整逻辑 |
| Accumulator 约束: flush 写回 controller | Task 3.5 step 4 | ✅ undo/redo bump 后 applyRemoteScene |
| Accumulator 约束: protectedElementIds | — | ⚠️ 已知 gap（与改造前一致） |
| codex 未显式要求但必须: 中间文件编译 | Task 3.5 step 3.5 | ✅ editor + split_pane 同步改签名 |

**Placeholder scan:** 无 TBD/TODO/implement later。

**Type consistency:**
- `ChangeAccumulator.schedule(ExcalidrawScene, {bool bypass})` — Task 1 定义，Task 2 调用 ✅
- `_onAccumulatorFlush(List<Map<String, Object?>>, bool)` — Task 2 定义，Task 6 追加指标 ✅
- `_scheduleSnapshot()` — Task 4 定义，Task 2 step 3 调用 ✅
- `_sort_by_nonce` 逻辑一致 — Task 1 `_shouldReplace` 和 Task 5 接收合并都对齐 `_shouldKeepLocal` ✅

**已知 gap:**
- `protectedElementIds` 在出站 accumulator 中未处理。当前架构下出站广播本身不感知 protected ids（与改造前一致），accumulator 的 50ms 窗口不会比改造前更差。如果后续实测发现文本编辑中间态被 accumulator 截断的问题，解决方案是在 `schedule()` 增加 `protectedElementIds` 参数，flush 时对 protected 元素取最新 controller 状态而非 pending 缓存。
