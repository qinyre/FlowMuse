# FlowMuse Issue #8 协作元素归属聚焦——实现细节执行计划（v5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变共享 Scene、全局 z 序和协作 LWW 语义的前提下，为协作元素记录不可变创建者，并提供按创建者/历史内容的本机聚焦视图（其他元素单遍变淡）。

**Architecture:** 一个共享 Scene + 一条全局 fractional-index z 序不变；归属写入 `customData.flowMuse.collaborationOwner`；聚焦是 WhiteboardPage 纯本地状态，渲染层在原绘制顺序上用连续 saveLayer 区段把非目标元素合成为 0.22 透明度；presence 加密 payload 增加可选 `creatorKey`（服务端零改动）。

**Tech Stack:** Flutter/Dart（共享代码，无平台分支）；已有依赖 `crypto ^3.0.3`、`uuid ^4.5.1`、`cryptography ^2.9.0`（不新增任何依赖）。

**Spec:** [2026-08-25-issue-8-collaboration-ownership-focus.md](./2026-08-25-issue-8-collaboration-ownership-focus.md)（v4 执行计划，本文件是其实现级细化；两份文档随任务一起读）

**实施分支：** `feat/issue-8-collaboration-ownership-focus`（已存在，基线 `origin/main@c40a847`）

---

## 0. 全局约束（每个任务的隐含前提，违反任何一条即任务失败）

1. Scene 仍是唯一文档 SSOT；元素按原 fractional index 顺序各绘制一次。
2. focus 状态不进入 Scene、History、SQLite、导出文件或 Socket 消息。
3. 归属字段（`collaborationOwner`）不参与任何权限/锁定判断，仅用于显示。
4. LWW 的 version/versionNonce 比较规则（`SceneReconciler._shouldKeepLocal`、`ChangeAccumulator._shouldReplace`）不改一行。
5. 所有 `customData` 合并必须深合并、copy-on-write，保留 `brushType`、`pageId`、`pdfBackground`、mindmap `role`、智能排版等全部既有键。
6. 默认（无聚焦）路径不新增任何 `saveLayer`；每个元素最多调用一次 `ElementRenderer.render`。
7. 服务端（`FlowMuse-Server/`）、数据库 schema、平台原生目录（ohos/android/ios/macos/windows/web）零改动；`pubspec.yaml` 零新依赖。
8. 共享 Dart 代码不增加平台分支。
9. 所有日志禁止出现 creatorKey/displayName/userId/元素正文；reconciler 日志只允许 `ownerConflictCount=N ownerBackfillCount=N` 形式的脱敏计数。
10. 外部产物（.markdraw/.excalidraw/.json/.markdrawlib/.excalidrawlib/PNG tEXt/SVG comment/分享文件）不得携带 `collaborationOwner`；内部链路（内存 Scene、本地 SQLite、协作密文、快照）必须保留。
11. 每个任务结束时：本任务新增/修改的 Dart 文件通过 `dart format`；`flutter test` 本任务涉及的测试目录全绿；不混入无关文件 diff。
12. 本地活动湿墨、正在编辑的 overlay、选择框、远端光标、Grid/Page/PDF/shadow 在任何聚焦状态下全亮。
13. 绑定文字（`TextElement.containerId != null`）的归属始终跟随父元素；系统元素（CanvasPage、PDF Background）永远无归属。

## 0.1 命名总表（跨任务一致性契约，实现时必须使用这些精确名称）

| 名称 | 位置 | 类型/签名 |
|---|---|---|
| `CollaborationCreator` | `editor_core/src/core/elements/collaboration_element_owner.dart` | 值对象：`creatorKey`/`displayName`/`isGuest` |
| `readCreator` / `withCreator` / `withoutCreator` | 同上 | `CollaborationCreator? readCreator(Element)` 等 Element 级 |
| `readCreatorFromJson` / `withCreatorInJson` / `withoutCreatorInJson` | 同上 | raw `Map<String, Object?>` 元素 JSON 级 |
| `sanitizeSceneForExternalExport` / `sanitizeDocumentForExternalExport` | `editor_core/src/core/serialization/external_export_sanitizer.dart` | `Scene→Scene` / `MarkdrawDocument→MarkdrawDocument` |
| `creatorKeyForUserId` / `creatorKeyForGuest` / `creatorForIdentity` | `collaboration/services/collaboration_creator_identity.dart` | 见 Task 2 |
| `stampCreatorOnResult` | `editor_core/src/editor/creator_stamping.dart` | `ToolResult stampCreatorOnResult(ToolResult, Scene, CollaborationCreator)` |
| `collaborationFocusAlpha` | `editor_core/src/rendering/collaboration_focus_alpha.dart` | 见 Task 12 |
| `CollaborationFocusTarget` / `CreatorFocus` / `HistoricalFocus` | `whiteboard/views/collaboration_focus_target.dart` | 见 Task 9（v4 §6.1 定义） |
| `onPrepareLocalResult` | `MarkdrawController` 字段 | `ToolResult? Function(ToolResult result, Scene currentScene)?` |
| `localCreatorResolver` | `MarkdrawController` 字段 | `CollaborationCreator? Function()?` |
| `serializeSceneForExternalExport` / `serializeSceneWithAliases` | `MarkdrawController` 方法 | 见 Task 7/8 |
| painter 参数 `focusedCreatorKey` / `focusHistoricalContent` / `locallyHighlightedElementIds` / `localHighlightRevision` | `StaticCanvasPainter` | `String?` / `bool` / `Set<ElementId>` / `int` |
| 湿墨 painter 参数 `socketIdCreatorKeys` / `presenceCreatorRevision` | `RemoteWetInkPainter` | `Map<String, String>` / `int` |
| presence 字段 `creatorKey` | `CollaboratorPresence` + 三类消息工厂 + repository 广播方法 | `String?` 可选参数 |
| `_broadcastIdleState(state, {force})` | `WhiteboardPage` | `force` 绕过 `_lastIdleState == state` 去重 |

## 0.2 相对 v4 文档的代码事实勘误（实测 @c40a847，实现以此为准）

| # | v4 假设 | 实测事实 |
|---|---|---|
| E1 | `_lastIdleState` 去重在 repository | 去重与 `_broadcastIdleState` 都在 `whiteboard_page.dart` L2695-2717；repository 只有 `broadcastIdleStatus` 等无去重方法（L540-558） |
| E2 | `CollaborationIdentity` 为 sealed/变体 | 普通类 + `isGuest` 布尔（`account/models/collaboration_identity.dart` L5-15） |
| E3 | 协作代码在 `lib/features/collaboration/` | 实际在 `lib/features/whiteboard/collaboration/` |
| E4 | presence 解析在 CollaboratorPresence.fromJson | 该类无序列化；三类 presence payload 在 `whiteboard_view_model.dart` `applyPresenceMessage`（L278-329）手工解析 |
| E5 | 游客 join 携带 userId | guest 查询参数只有 `guestName`/`guestAvatarUrl`（socket_io_realtime_transport.dart L148-161） |
| E6 | Avatar Stack 在 MarkdrawEditor 内部构建 badge 列表 | badge 列表在 `WhiteboardPage._collaborationParticipantBadges`（L2568-2585）构建后经 `collaborationParticipants` 参数传入；右上 chrome 行 widget 实为 `_RightChrome`（L1318，实例化点 L857），无 `_ChromeRow` 类 |
| E7 | 协作者 map 在 WhiteboardPage | `WhiteboardState.collaborators`（view_model L53）；Page 只持 `_roomSocketIds` |
| E8 | PNG tEXt 嵌入 Excalidraw JSON | `PngMetadata.embedMarkdrawData` 嵌入 `.markdraw` 文本（png_metadata.dart L91-98）——该格式本就不写 customData；sanitize 仍按要求做纵深防御 |
| E9 | 轻提示有独立 Toast 组件 | 统一 `ScaffoldMessenger.showSnackBar`（markdraw_editor.dart L300-305 范式） |
| E10 | `Element.copyWith` 有 merge 语义 | copyWith 是整体替换（element.dart L156），深合并必须自己做（Task 1 helper） |
| E11 | reconciler 有独立 winner/loser 变量 | 现结构单变量 `chosen`（scene_reconciler.dart L25-29），loser 需从 chosen 反推 |
| E12 | split pane debounce 150ms | 实际 500ms（markdraw_split_pane.dart L65） |
| E13 | 静态层把 CanvasPage 画进元素循环 | CanvasPage 在循环内被 `continue` 跳过（static_canvas_painter.dart L152-154），页底在 L119-131 预循环绘制 |
| E14 | controller 直连 `_editorState.applyResult` 的路径少量 | 精确 14 处（见 Task 5 列表），全部是文本编辑路径 |

## 0.3 任务依赖图与分配指南

```text
T1 owner codec ──┬─→ T5 stamping ──→ T6 reconciler（T6 只依赖 T1）
                 ├─→ T7 外部导出
                 ├─→ T8 sidecar（还需 T5 的 localCreatorResolver）
                 └─→ T12 静态渲染（只依赖 T1）
T2 身份派生 ──→ T3 presence 扩展 ──→ T4 会话身份/补发（依赖 T2/T3）
T4+T5 → T9 focus 状态机（还依赖 T12 无关，但 pill 参数经 markdraw_editor）
T9 → T10 属性面板入口 → T11 头像交互（T11 依赖 T9 的 _toggleCreatorFocus）
T12 → T13 参数穿透/数学 overlay（还消费 T4 的 _socketCreatorKeys 与 T9 的 _focusTarget）
T13 → T14 远端湿墨（构造参数与 EditorCanvas 接线都在 T14 内完成）
全部 → T15 集成/压力 → T16 门禁/文档
```

- 每个任务自包含：实现者只需读本任务 + §0 全局约束 + §0.1 命名总表 + 上游 spec 对应节（任务内注明）。
- 任务按编号顺序执行即可，无环。**并行限制**：T12 可与 T9-T11 并行（接口已在 §0.1 固定）；但 **T13 必须在 T12、T4、T9 全部完成后开始**，**T14 必须在 T13 之后**（RemoteWetInkPainter 的构造参数与接线同在 T14，避免跨任务编译期断裂）。
- 每个任务一个 commit（消息见任务尾）；对应 v4 §15 的 8 提交序列映射在附录 B。

---

# Task 1：创建者值对象、customData codec 与外部 sanitizer（editor_core）

**目标**：建立归属数据的唯一读写入口。不触碰 UI/渲染/协作代码。

**上游 spec**：v4 §4.1、§4.5、§10.3。

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/collaboration_element_owner_test.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/external_export_sanitizer_test.dart`

**Interfaces (Produces，后续任务按此消费):**
```dart
// collaboration_element_owner.dart
class CollaborationCreator {
  const CollaborationCreator({required this.creatorKey, required this.displayName, required this.isGuest});
  static const int schemaVersion = 1;
  final String creatorKey; final String displayName; final bool isGuest;
  Map<String, Object?> toOwnerJson();
  static CollaborationCreator? fromOwnerJson(Object? raw);
}
const String kCollaborationOwnerCustomDataKey = 'collaborationOwner'; // 仅测试与文档用

CollaborationCreator? readCreator(Element element);
Element withCreator(Element element, CollaborationCreator creator);
Element withoutCreator(Element element);

CollaborationCreator? readCreatorFromJson(Map<String, Object?> element);
Map<String, Object?> withCreatorInJson(Map<String, Object?> element, CollaborationCreator creator);
Map<String, Object?> withoutCreatorInJson(Map<String, Object?> element);

// external_export_sanitizer.dart
Scene sanitizeSceneForExternalExport(Scene scene);
MarkdrawDocument sanitizeDocumentForExternalExport(MarkdrawDocument doc);
```

注意：**不要**把 `collaboration_element_owner.dart` 加进 `core/elements/elements.dart` barrel export（避免与 `core/layout/canvas_layout.dart` 形成循环 import）；所有使用方直接 import 该文件路径。

- [ ] **Step 1.1：写失败测试（owner codec）**

新建 `test/features/whiteboard/editor_core/collaboration_element_owner_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = CollaborationCreator(
    creatorKey: 'user:abc',
    displayName: '张三',
    isGuest: false,
  );

  test('withCreator 后 readCreator 往返一致', () {
    final element = RectangleElement(id: const ElementId('r1'), x: 0, y: 0, width: 10, height: 10);
    final stamped = withCreator(element, creator);
    expect(readCreator(stamped)?.creatorKey, 'user:abc');
    expect(readCreator(stamped)?.displayName, '张三');
    expect(readCreator(stamped)?.isGuest, false);
  });

  test('withCreator 深合并保留既有 flowMuse 键（brushType/pageId/pdfBackground/mindmap role/smart-layout）', () {
    final element = RectangleElement(
      id: const ElementId('r2'), x: 0, y: 0, width: 10, height: 10,
      customData: const {
        'flowMuse': {
          'brushType': 'brush',
          'pageId': 'page-1',
          'pdfBackground': true,
          'role': 'mindmap-node',
          'smartLayoutPlan': {'rows': 2},
        },
        'other': {'keep': true},
      },
    );
    final stamped = withCreator(element, creator);
    final flowMuse = stamped.customData!['flowMuse'] as Map;
    expect(flowMuse['brushType'], 'brush');
    expect(flowMuse['pageId'], 'page-1');
    expect(flowMuse['pdfBackground'], true);
    expect(flowMuse['role'], 'mindmap-node');
    expect((flowMuse['smartLayoutPlan'] as Map)['rows'], 2);
    expect(flowMuse['collaborationOwner'], isNotNull);
    expect((stamped.customData!['other'] as Map)['keep'], true);
  });

  test('withCreator 不修改输入元素（copy-on-write）', () {
    final element = RectangleElement(
      id: const ElementId('r3'), x: 0, y: 0, width: 10, height: 10,
      customData: const {
        'flowMuse': {'brushType': 'marker'},
      },
    );
    final before = element.customData.toString();
    withCreator(element, creator);
    expect(element.customData.toString(), before);
    expect(element.customData!['flowMuse']!['collaborationOwner'], isNull);
  });

  test('withoutCreator 只删 collaborationOwner，保留其他键；无 owner 时原样返回', () {
    final element = withCreator(
      RectangleElement(
        id: const ElementId('r4'), x: 0, y: 0, width: 10, height: 10,
        customData: const {
          'flowMuse': {'pageId': 'page-2'},
        },
      ),
      creator,
    );
    final cleared = withoutCreator(element);
    expect(readCreator(cleared), isNull);
    expect((cleared.customData!['flowMuse'] as Map)['pageId'], 'page-2');

    final untouched = RectangleElement(id: const ElementId('r5'), x: 0, y: 0, width: 10, height: 10);
    expect(identical(withoutCreator(untouched), untouched), isTrue);
  });

  test('customData 为 null 时 withCreator 创建完整路径', () {
    final element = RectangleElement(id: const ElementId('r6'), x: 0, y: 0, width: 10, height: 10);
    expect(element.customData, isNull);
    final stamped = withCreator(element, creator);
    expect(readCreator(stamped)?.creatorKey, 'user:abc');
  });

  test('畸形数据安全降级：readCreator 返回 null 而不抛异常', () {
    Element buildWith(Object? owner) => RectangleElement(
      id: const ElementId('r7'), x: 0, y: 0, width: 10, height: 10,
      customData: {'flowMuse': {'collaborationOwner': owner}},
    );
    expect(readCreator(buildWith('not-a-map')), isNull);
    expect(readCreator(buildWith({'creatorKey': 42})), isNull);
    expect(readCreator(buildWith({'creatorKey': 'k', 'displayName': 1, 'isGuest': false, 'version': 1})), isNull);
    expect(readCreator(buildWith(null)), isNull);
    expect(
      readCreator(RectangleElement(
        id: const ElementId('r8'), x: 0, y: 0, width: 10, height: 10,
        customData: const {'flowMuse': 'not-a-map'},
      )),
      isNull,
    );
  });

  test('未知更高 version 仍可读取合法公共字段', () {
    final element = RectangleElement(
      id: const ElementId('r9'), x: 0, y: 0, width: 10, height: 10,
      customData: const {
        'flowMuse': {
          'collaborationOwner': {'version': 99, 'creatorKey': 'guest:room:u', 'displayName': '游客', 'isGuest': true, 'futureField': 'x'},
        },
      },
    );
    expect(readCreator(element)?.creatorKey, 'guest:room:u');
  });

  test('raw JSON 版本行为与 Element 版本一致且不改输入 map', () {
    final raw = <String, Object?>{
      'id': 'e1', 'type': 'rectangle', 'version': 3, 'versionNonce': 7,
      'customData': {
        'flowMuse': {'pageId': 'page-3'},
      },
    };
    final stamped = withCreatorInJson(raw, creator);
    expect(readCreatorFromJson(stamped)?.creatorKey, 'user:abc');
    expect(((stamped['customData'] as Map)['flowMuse'] as Map)['pageId'], 'page-3');
    // 输入不被修改
    expect(((raw['customData'] as Map)['flowMuse'] as Map).containsKey('collaborationOwner'), isFalse);
    final cleared = withoutCreatorInJson(stamped);
    expect(readCreatorFromJson(cleared), isNull);
    expect(((cleared['customData'] as Map)['flowMuse'] as Map)['pageId'], 'page-3');
    // 无 owner 时 withoutCreatorInJson 原样返回同一实例
    expect(identical(withoutCreatorInJson(raw), raw), isTrue);
  });

  test('owner codec 不 import collaboration/account（依赖边界）', () {
    final file = File('lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart');
    final source = file.readAsStringSync();
    expect(source.contains('features/whiteboard/collaboration'), isFalse,
        reason: 'editor_core owner 模块不得依赖 collaboration');
    expect(source.contains('features/account'), isFalse,
        reason: 'editor_core owner 模块不得依赖 account');
  });
}
```

文件头还需 `import 'dart:io';`（最后一个测试用）。若 `RectangleElement` 构造因 required 参数报错，以 `test/features/whiteboard/editor_core/scene_dirty_elements_test.dart` L7-13 的构造范式为准补齐可选参数。

- [ ] **Step 1.2：运行测试确认失败**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/collaboration_element_owner_test.dart
```
预期：编译失败（`collaboration_element_owner.dart` 不存在）。

- [ ] **Step 1.3：实现 collaboration_element_owner.dart**

新建 `lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart`：

```dart
import 'brush_type.dart' show flowMuseCustomDataKey;
import 'element.dart';

/// 协作元素创建者快照。仅用于显示层分组，不是账号 ID，不是权限凭据，
/// 客户端可伪造；禁止用于任何锁定/鉴权判断。
class CollaborationCreator {
  const CollaborationCreator({
    required this.creatorKey,
    required this.displayName,
    required this.isGuest,
  });

  static const int schemaVersion = 1;

  /// 客户端稳定、伪匿名的逻辑分组键，如 `user:<sha256>` 或 `guest:<roomId>:<uuid>`。
  final String creatorKey;

  /// 创建时的显示名快照；创建者离线时作为回退显示。
  final String displayName;

  /// 创建时的身份快照（游客/登录）。
  final bool isGuest;

  Map<String, Object?> toOwnerJson() => <String, Object?>{
        'version': schemaVersion,
        'creatorKey': creatorKey,
        'displayName': displayName,
        'isGuest': isGuest,
      };

  /// 宽松解析：只接受类型完全合法的公共字段；未知高 version 也能读取
  /// （前向兼容）；任何畸形输入返回 null，绝不抛异常。
  static CollaborationCreator? fromOwnerJson(Object? raw) {
    if (raw is! Map) return null;
    final creatorKey = raw['creatorKey'];
    final displayName = raw['displayName'];
    final isGuest = raw['isGuest'];
    final version = raw['version'];
    if (creatorKey is! String || creatorKey.isEmpty) return null;
    if (displayName is! String) return null;
    if (isGuest is! bool) return null;
    if (version is! int || version < 1) return null;
    return CollaborationCreator(
      creatorKey: creatorKey,
      displayName: displayName,
      isGuest: isGuest,
    );
  }
}

/// `customData.flowMuse.collaborationOwner` 的键名（测试与文档引用）。
const String kCollaborationOwnerCustomDataKey = 'collaborationOwner';

CollaborationCreator? readCreator(Element element) {
  final customData = element.customData;
  if (customData == null) return null;
  final flowMuse = customData[flowMuseCustomDataKey];
  if (flowMuse is! Map) return null;
  return CollaborationCreator.fromOwnerJson(flowMuse[kCollaborationOwnerCustomDataKey]);
}

/// 深合并写入 owner：重建 customData 与 flowMuse 两级 Map，只覆盖
/// collaborationOwner 一个键，其余键原样保留。输入元素不被修改。
Element withCreator(Element element, CollaborationCreator creator) {
  final customData = element.customData ?? const <String, Object?>{};
  final merged = _withOwnerInCustomData(customData, creator.toOwnerJson());
  return element.copyWith(customData: merged);
}

/// 只删除 collaborationOwner；flowMuse 中的其他键保留。无 owner 时
/// 返回同一实例（copy-on-write 短路）。
Element withoutCreator(Element element) {
  final customData = element.customData;
  if (customData == null) return element;
  final flowMuseRaw = customData[flowMuseCustomDataKey];
  if (flowMuseRaw is! Map || !flowMuseRaw.containsKey(kCollaborationOwnerCustomDataKey)) {
    return element;
  }
  final merged = Map<String, Object?>.from(customData);
  final flowMuse = Map<String, Object?>.from(flowMuseRaw);
  flowMuse.remove(kCollaborationOwnerCustomDataKey);
  if (flowMuse.isEmpty) {
    merged.remove(flowMuseCustomDataKey);
  } else {
    merged[flowMuseCustomDataKey] = flowMuse;
  }
  return element.copyWith(customData: merged);
}

CollaborationCreator? readCreatorFromJson(Map<String, Object?> element) {
  final customData = element['customData'];
  if (customData is! Map) return null;
  final flowMuse = customData[flowMuseCustomDataKey];
  if (flowMuse is! Map) return null;
  return CollaborationCreator.fromOwnerJson(flowMuse[kCollaborationOwnerCustomDataKey]);
}

/// raw 元素 JSON（协作 reconciler 使用）版本。返回新 Map；已持有相同
/// creatorKey 时返回同一实例（短路，便于 reconciler 不产生无谓新对象）。
Map<String, Object?> withCreatorInJson(
  Map<String, Object?> element,
  CollaborationCreator creator,
) {
  final current = readCreatorFromJson(element);
  if (current != null &&
      current.creatorKey == creator.creatorKey &&
      current.displayName == creator.displayName &&
      current.isGuest == creator.isGuest) {
    return element;
  }
  final customData = element['customData'];
  final base = customData is Map ? Map<String, Object?>.from(customData) : <String, Object?>{};
  final flowMuseRaw = base[flowMuseCustomDataKey];
  final flowMuse = flowMuseRaw is Map ? Map<String, Object?>.from(flowMuseRaw) : <String, Object?>{};
  flowMuse[kCollaborationOwnerCustomDataKey] = creator.toOwnerJson();
  base[flowMuseCustomDataKey] = flowMuse;
  return <String, Object?>{...element, 'customData': base};
}

Map<String, Object?> withoutCreatorInJson(Map<String, Object?> element) {
  final customData = element['customData'];
  if (customData is! Map) return element;
  final flowMuseRaw = customData[flowMuseCustomDataKey];
  if (flowMuseRaw is! Map || !flowMuseRaw.containsKey(kCollaborationOwnerCustomDataKey)) {
    return element;
  }
  final mergedCustomData = Map<String, Object?>.from(customData);
  final flowMuse = Map<String, Object?>.from(flowMuseRaw);
  flowMuse.remove(kCollaborationOwnerCustomDataKey);
  if (flowMuse.isEmpty) {
    mergedCustomData.remove(flowMuseCustomDataKey);
  } else {
    mergedCustomData[flowMuseCustomDataKey] = flowMuse;
  }
  return <String, Object?>{...element, 'customData': mergedCustomData};
}

Map<String, Object?> _withOwnerInCustomData(
  Map<String, Object?> customData,
  Map<String, Object?> ownerJson,
) {
  final merged = Map<String, Object?>.from(customData);
  final flowMuseRaw = merged[flowMuseCustomDataKey];
  final flowMuse = flowMuseRaw is Map ? Map<String, Object?>.from(flowMuseRaw) : <String, Object?>{};
  flowMuse[kCollaborationOwnerCustomDataKey] = ownerJson;
  merged[flowMuseCustomDataKey] = flowMuse;
  return merged;
}
```

实现说明：
- `flowMuseCustomDataKey` 从 `brush_type.dart` 复用（该文件 L111 已有此公开常量），禁止重复定义第二套键名。
- `Rect`/`customData` 中的嵌套 Map 可能是 `Map<String, dynamic>`（codec 浅转换产物），所以一律 `Map<String, Object?>.from(...)` 重建。
- `element.copyWith(customData: ...)` 是整体替换（见勘误 E10），替换值已是完整深合并结果，语义正确。

- [ ] **Step 1.4：运行 owner 测试确认全绿**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/collaboration_element_owner_test.dart
```
预期：9 个测试 PASS。若 `flowMuseCustomDataKey` 非 public，把 brush_type.dart 中该常量声明改为 public（不加新常量）。

- [ ] **Step 1.5：写失败测试（sanitizer）**

新建 `test/features/whiteboard/editor_core/external_export_sanitizer_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/document_section.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/markdraw_document.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = CollaborationCreator(creatorKey: 'user:k', displayName: '李四', isGuest: true);

  test('sanitizeSceneForExternalExport 剥离 owner、保留其他 customData、无 owner 短路', () {
    final scene = Scene()
        .addElement(withCreator(
          RectangleElement(
            id: const ElementId('a'), x: 0, y: 0, width: 1, height: 1,
            customData: const {
              'flowMuse': {'pageId': 'p1'},
            },
          ),
          creator,
        ))
        .addElement(RectangleElement(id: const ElementId('b'), x: 0, y: 0, width: 1, height: 1));
    final sanitized = sanitizeSceneForExternalExport(scene);
    expect(readCreator(sanitized.getElementById(const ElementId('a'))!), isNull);
    expect(
      (sanitized.getElementById(const ElementId('a'))!.customData!['flowMuse'] as Map)['pageId'],
      'p1',
    );
    expect(readCreator(sanitized.getElementById(const ElementId('b'))!), isNull);
    // 全场无 owner 时返回同一实例
    final clean = Scene().addElement(RectangleElement(id: const ElementId('c'), x: 0, y: 0, width: 1, height: 1));
    expect(identical(sanitizeSceneForExternalExport(clean), clean), isTrue);
    // version/versionNonce 不被 bump（upsertRemoteElements 语义）
    final withOwner = withCreator(
      RectangleElement(id: const ElementId('d'), x: 0, y: 0, width: 1, height: 1),
      creator,
    );
    final scene2 = Scene().addElement(withOwner);
    expect(sanitizeSceneForExternalExport(scene2).elements.first.version, withOwner.version);
  });

  test('sanitizeDocumentForExternalExport 剥离 doc 内 owner 并保留其余', () {
    final doc = MarkdrawDocument(
      sections: [
        SketchSection([
          withCreator(RectangleElement(id: const ElementId('e'), x: 0, y: 0, width: 1, height: 1), creator),
          RectangleElement(id: const ElementId('f'), x: 0, y: 0, width: 1, height: 1),
        ]),
      ],
    );
    final sanitized = sanitizeDocumentForExternalExport(doc);
    final elements = sanitized.allElements;
    expect(readCreator(elements[0]), isNull);
    expect(readCreator(elements[1]), isNull);
    expect(sanitized.aliases, doc.aliases);
    // 无 owner 短路返回同一实例
    expect(identical(sanitizeDocumentForExternalExport(sanitized), sanitized), isTrue);
  });
}
```

（`Element.version` 字段若不叫 version，以 element.dart 实际字段名为准调整断言。）

- [ ] **Step 1.6：运行 sanitizer 测试确认失败**（文件不存在，编译失败）

- [ ] **Step 1.7：实现 external_export_sanitizer.dart**

新建 `lib/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart`：

```dart
import '../elements/collaboration_element_owner.dart';
import '../elements/elements.dart';
import '../scene/scene_exports.dart';
import 'document_section.dart';
import 'markdraw_document.dart';

/// 返回剥离 `customData.flowMuse.collaborationOwner` 的 Scene 不可变拷贝。
/// 其他 customData / flowMuse 键全部保留。用于所有外部导出出口；
/// 内部持久化与协作链路禁止调用。
Scene sanitizeSceneForExternalExport(Scene scene) {
  var hasOwner = false;
  for (final element in scene.elements) {
    if (readCreator(element) != null) {
      hasOwner = true;
      break;
    }
  }
  if (!hasOwner) return scene;
  return scene.upsertRemoteElements([
    for (final element in scene.elements) withoutCreator(element),
  ]);
}

/// MarkdrawDocument 级别的同一净化（避免 Scene 往返重建 alias/索引）。
MarkdrawDocument sanitizeDocumentForExternalExport(MarkdrawDocument doc) {
  var hasOwner = false;
  for (final element in doc.allElements) {
    if (readCreator(element) != null) {
      hasOwner = true;
      break;
    }
  }
  if (!hasOwner) return doc;
  final sections = <DocumentSection>[
    for (final section in doc.sections)
      if (section is SketchSection)
        SketchSection([for (final element in section.elements) withoutCreator(element)])
      else
        section,
  ];
  return doc.copyWith(sections: sections);
}
```

说明：`upsertRemoteElements` 替换元素但不 bump version（scene.dart L73-88），正适合纯净化拷贝。

- [ ] **Step 1.8：运行 sanitizer 测试确认全绿**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/external_export_sanitizer_test.dart
```

- [ ] **Step 1.9：format + commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart lib/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart test/features/whiteboard/editor_core/collaboration_element_owner_test.dart test/features/whiteboard/editor_core/external_export_sanitizer_test.dart
git add lib/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart lib/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart test/features/whiteboard/editor_core/
git commit -m "feat: 增加协作元素创建者元数据 codec 与外部导出净化器"
```

---

# Task 2：creatorKey 身份派生（collaboration）

**目标**：实现登录用户跨房间稳定键与游客会话键。纯函数，无 IO。

**上游 spec**：v4 §4.2、§4.3。

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_creator_identity.dart`
- Test: `FlowMuse-App/test/features/whiteboard/collaboration/services/collaboration_creator_identity_test.dart`

**Interfaces (Produces):**
```dart
String creatorKeyForUserId(String userId);            // "user:" + sha256("flowmuse-creator-v1|"+userId) 十六进制全串
String creatorKeyForGuest(String roomId, String sessionUuid); // "guest:" + roomId + ":" + sessionUuid
CollaborationCreator creatorForIdentity({
  required CollaborationIdentity identity,
  required String roomId,
  required String guestSessionId,
});
```

- [ ] **Step 2.1：写失败测试**

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flow_muse/features/account/models/collaboration_identity.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_creator_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('登录用户键跨房间稳定、不含 roomId、不同用户不同', () {
    final k1 = creatorKeyForUserId('user-1');
    final k2 = creatorKeyForUserId('user-1');
    final k3 = creatorKeyForUserId('user-2');
    expect(k1, k2);
    expect(k1.startsWith('user:'), isTrue);
    expect(k1.contains('room'), isFalse);
    expect(k1, isNot(k3));
    expect(
      k1,
      'user:${sha256.convert(utf8.encode('flowmuse-creator-v1|user-1')).toString()}',
    );
  });

  test('游客键 = guest:roomId:sessionUuid；同会话稳定，换会话改变', () {
    expect(creatorKeyForGuest('roomA', 'uuid-1'), 'guest:roomA:uuid-1');
    expect(creatorKeyForGuest('roomA', 'uuid-1'), creatorKeyForGuest('roomA', 'uuid-1'));
    expect(creatorKeyForGuest('roomA', 'uuid-1'), isNot(creatorKeyForGuest('roomA', 'uuid-2')));
    expect(creatorKeyForGuest('roomA', 'uuid-1'), isNot(creatorKeyForGuest('roomB', 'uuid-1')));
  });

  test('creatorForIdentity 按身份选择键并快照名字', () {
    final guest = CollaborationIdentity.guest('游客甲');
    final guestCreator = creatorForIdentity(identity: guest, roomId: 'roomA', guestSessionId: 'uuid-1');
    expect(guestCreator.creatorKey, 'guest:roomA:uuid-1');
    expect(guestCreator.isGuest, isTrue);
    expect(guestCreator.displayName, '游客甲');

    final user = CollaborationIdentity(username: '张三', isGuest: false, userId: 'user-9');
    final userCreator = creatorForIdentity(identity: user, roomId: 'roomB', guestSessionId: 'ignored');
    expect(userCreator.creatorKey, creatorKeyForUserId('user-9'));
    expect(userCreator.isGuest, isFalse);
  });
}
```

- [ ] **Step 2.2：运行确认失败**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/collaboration_creator_identity_test.dart
```

- [ ] **Step 2.3：实现**

新建 `lib/features/whiteboard/collaboration/services/collaboration_creator_identity.dart`：

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../account/models/collaboration_identity.dart';
import '../../editor_core/src/core/elements/collaboration_element_owner.dart';

/// 登录用户 creatorKey：跨房间稳定（不含 roomId），与既有房主 ownerKeyHash
/// 通过固定域前缀隔离。哈希只是避免把 userId 明文写进元素，不构成匿名化。
String creatorKeyForUserId(String userId) {
  final digest = sha256.convert(utf8.encode('flowmuse-creator-v1|$userId'));
  return 'user:${digest.toString()}';
}

/// 游客 creatorKey：绑定房间 + 会话 UUID。Socket 重连期间复用；
/// 完整退出房间后由宿主清除 sessionUuid，再次加入形成新逻辑组。
String creatorKeyForGuest(String roomId, String sessionUuid) =>
    'guest:$roomId:$sessionUuid';

/// 由当前协作身份派生创建者快照。guestSessionId 仅在 identity.isGuest
/// 时使用。
CollaborationCreator creatorForIdentity({
  required CollaborationIdentity identity,
  required String roomId,
  required String guestSessionId,
}) {
  if (identity.isGuest) {
    return CollaborationCreator(
      creatorKey: creatorKeyForGuest(roomId, guestSessionId),
      displayName: identity.username,
      isGuest: true,
    );
  }
  final userId = identity.userId;
  assert(userId != null, '登录身份必须携带 userId');
  return CollaborationCreator(
    creatorKey: creatorKeyForUserId(userId!),
    displayName: identity.username,
    isGuest: false,
  );
}
```

import 路径若与仓库相对路径风格不符（例如仓库统一用 `package:flow_muse/...` 绝对导入），按 `whiteboard_collaboration_adapter.dart` 的既有 import 风格改写，语义不变。

- [ ] **Step 2.4：运行确认全绿 → format → commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/services/collaboration_creator_identity_test.dart
dart format lib/features/whiteboard/collaboration/services/collaboration_creator_identity.dart test/features/whiteboard/collaboration/services/collaboration_creator_identity_test.dart
git add lib/features/whiteboard/collaboration/services/collaboration_creator_identity.dart test/features/whiteboard/collaboration/services/collaboration_creator_identity_test.dart
git commit -m "feat: 增加登录/游客协作创建者稳定身份键派生"
```

---

# Task 3：presence 消息、模型与 repository 的 creatorKey 扩展

**目标**：三类加密 presence 消息携带可选 `creatorKey`；接收端写入 `CollaboratorPresence`。加密路径与服务端零改动。

**上游 spec**：v4 §4.4（规则 1/4/5/7/8/9）。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/models/collaboration_message.dart`（三个工厂 L63-122）
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/models/collaborator_presence.dart`（L3-55）
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`（L516-578 三个广播方法）
- Modify: `FlowMuse-App/lib/features/whiteboard/view_models/whiteboard_view_model.dart`（`applyPresenceMessage` L278-329）
- Test: `FlowMuse-App/test/features/whiteboard/collaboration/models/collaboration_message_test.dart`（扩展既有文件；若不存在则新建）

**Interfaces (Produces):**
```dart
// 三个消息工厂与三个 repository 广播方法都新增可选命名参数：
String? creatorKey
// CollaboratorPresence 新增字段与 copyWith 参数：
final String? creatorKey;
```

- [ ] **Step 3.1：写失败测试**

在 `test/features/whiteboard/collaboration/models/collaboration_message_test.dart` 追加（实测该文件不存在，**新建**，结构如下）：

```dart
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presence creatorKey 扩展', () {
  test('三类 presence 工厂携带 creatorKey 并进入加密前 payload', () {
    final mouse = CollaborationMessage.mouseLocation(
      socketId: 's1', pointer: const {'x': 1.0, 'y': 2.0}, button: 'up',
      selectedElementIds: const {}, username: '张三', creatorKey: 'user:k1',
    );
    expect(mouse.payload['creatorKey'], 'user:k1');

    final idle = CollaborationMessage.idleStatus(
      socketId: 's1', userState: 'active', username: '张三', creatorKey: 'user:k1',
    );
    expect(idle.payload['creatorKey'], 'user:k1');

    final bounds = CollaborationMessage.userVisibleSceneBounds(
      socketId: 's1', username: '张三', sceneBounds: const {'x': 0.0, 'y': 0.0}, creatorKey: 'user:k1',
    );
    expect(bounds.payload['creatorKey'], 'user:k1');
  });

  test('creatorKey 缺省时 payload 不含该键（兼容旧客户端字节形态）', () {
    final idle = CollaborationMessage.idleStatus(
      socketId: 's1', userState: 'active', username: '张三',
    );
    expect(idle.payload.containsKey('creatorKey'), isFalse);
  });

  test('toBytes/fromBytes 往返保留 creatorKey', () {
    final idle = CollaborationMessage.idleStatus(
      socketId: 's1', userState: 'active', username: '张三', creatorKey: 'guest:roomA:u1',
    );
    final restored = CollaborationMessage.fromBytes(idle.toBytes());
    expect(restored.payload['creatorKey'], 'guest:roomA:u1');
  });
});
```

再新建 `test/features/whiteboard/collaboration/models/collaborator_presence_creator_key_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/collaboration/models/collaborator_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CollaboratorPresence 新增可空 creatorKey 并可 copyWith', () {
    const presence = CollaboratorPresence(socketId: 's1', username: '张三');
    expect(presence.creatorKey, isNull);
    final updated = presence.copyWith(creatorKey: 'user:k1');
    expect(updated.creatorKey, 'user:k1');
    expect(updated.socketId, 's1');
    expect(updated.username, '张三');
    // 不传时保留
    expect(presence.copyWith(username: '李四').creatorKey, isNull);
    expect(updated.copyWith(username: '李四').creatorKey, 'user:k1');
  });
}
```

- [ ] **Step 3.2：运行确认失败**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/models/
```

- [ ] **Step 3.3：实现三处修改**

1. `collaboration_message.dart`（三工厂实际位于 L63-122）：三个工厂各做**最小增量修改**——命名参数列表末尾加 `String? creatorKey,`，payload map 末尾追加一行条件项。**禁止重写工厂或改动既有键的写法**（现有 `'userId': userId`、`'avatarUrl': avatarUrl` 是无条件写入，保持原样）。以 idleStatus 为例（只加两行，注释标出）：

```dart
factory CollaborationMessage.idleStatus({
  required String socketId,
  required String userState,
  required String username,
  String? userId,
  String? avatarUrl,
  String? creatorKey,                                   // ← 新增参数
}) {
  return CollaborationMessage(
    type: CollaborationMessageType.idleStatus,
    payload: {
      'socketId': socketId,
      'userState': userState,
      'username': username,
      'userId': userId,                                 // ← 原样保留
      'avatarUrl': avatarUrl,                           // ← 原样保留
      if (creatorKey != null) 'creatorKey': creatorKey, // ← 新增唯一一行
    },
  );
}
```

（注意：`CollaborationMessage` 的构造是公开 const 构造 `const CollaborationMessage({required this.type, required this.payload})`，不存在 `_` 私有构造——上例按实际构造书写。`mouseLocation`/`userVisibleSceneBounds` 两个工厂做完全相同的两行增量。）

2. `collaborator_presence.dart`：构造参数加 `this.creatorKey,`（放在 `isGuest` 之后），字段声明 `final String? creatorKey;`，`copyWith` 加 `String? creatorKey` 参数并透传——注意该类 copyWith 现有风格是非 sentinel 直传（`creatorKey: creatorKey ?? this.creatorKey` 之外的字段都这么写则保持一致；若 copyWith 用的是直接赋值风格，按 `username` 的既有写法照抄）。

3. `collaboration_repository.dart`：`broadcastMouseLocation`（L516）、`broadcastIdleStatus`（L540）、`broadcastVisibleSceneBounds`（L560）三个方法各加 `String? creatorKey` 命名参数并传给对应工厂。不触碰 `_send()` 与加密封装。

4. `whiteboard_view_model.dart` `applyPresenceMessage`：三个分支的 `copyWith(...)` 都追加：

```dart
creatorKey: message.payload['creatorKey'] as String? ??
    _fallbackCreatorKeyFromUserId(message.payload['userId'] as String?),
```

并在 `WhiteboardViewModel` 类内加私有 helper 与 import（`collaboration_creator_identity.dart`）：

```dart
/// 兼容旧客户端：登录用户 presence 缺 creatorKey 时由 userId 本地推导；
/// 游客缺字段时绝不按 username 猜测（返回 null → 禁用聚焦）。
static String? _fallbackCreatorKeyFromUserId(String? userId) =>
    userId == null ? null : creatorKeyForUserId(userId);
```

- [ ] **Step 3.4：运行 models 测试与既有回归**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/
```
预期：新增测试 PASS，既有测试零回归（payload 缺省不含新键保证字节兼容）。

- [ ] **Step 3.5：format → commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/collaboration/models/collaboration_message.dart lib/features/whiteboard/collaboration/models/collaborator_presence.dart lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart lib/features/whiteboard/view_models/whiteboard_view_model.dart test/features/whiteboard/collaboration/models/
git add -A lib/features/whiteboard/collaboration test/features/whiteboard/collaboration lib/features/whiteboard/view_models
git commit -m "feat: 加密协作状态消息可选携带创建者键"
```

---

# Task 4：WhiteboardPage 会话身份、强制补发与重连保持

**目标**：游客 session UUID 生命周期；三类广播携带 creatorKey；首加入/重连/新成员加入三种补发路径。

**上游 spec**：v4 §4.3、§4.4 规则 2/3/6、§5.4。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Test: `FlowMuse-App/test/features/whiteboard/views/whiteboard_page_creator_presence_test.dart`（新建；页面级测试过重时按 Step 4.8 的策略降级为脚本化单测+人工核对清单）

**Interfaces (Produces，本文件内私有，Task 5/9/10 消费):**
```dart
String? _guestCreatorSessionId;                        // 游客会话 UUID（内存态）
String? _currentCreatorKey();                          // 当前 creatorKey（无房间→null）
CollaborationCreator? _currentCreator();               // 当前创建者快照（Task 5/6 消费）
void _broadcastIdleState(String state, {bool force = false});
```

- [ ] **Step 4.1：创建测试文件（源码结构断言）**

新建 `test/features/whiteboard/views/whiteboard_page_creator_presence_test.dart`。本任务只做**源码结构断言**（页面级时序的完整行为验证在 Task 15 双端测试承载）：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // WhiteboardPage 源码路径（测试工作目录 = FlowMuse-App/）
  final page = File('lib/features/whiteboard/views/whiteboard_page.dart');

  test('WhiteboardPage 源码包含 force 补发调用与 session 清理', () {
    final source = page.readAsStringSync();
    // 首加入 / 重连 / 新成员 三处 force 补发（Task 4 Step 4.7 落地后成立）
    expect(
      RegExp(r'_broadcastIdleState\(_lastIdleState \?\? '
              r"'active', force: true\)")
          .hasMatch(source),
      isTrue,
      reason: '必须存在绕过 idle 去重的强制补发调用',
    );
    expect(source.contains('force: true'), isTrue);
    // leave/end 清理 guest 会话（Task 4 Step 4.4 落地后成立）
    expect(source.contains('_guestCreatorSessionId = null;'), isTrue);
  });

  test('newlyJoinedSocketIds 纯函数：单批多次加入返回全部新 socket', () {
    // 该函数在 Step 4.7 中提取为 whiteboard_page.dart 顶层公开函数
    expect(
      newlyJoinedSocketIds(const {}, const {'a', 'b'}),
      {'a', 'b'},
    );
    expect(newlyJoinedSocketIds(const {'a'}, const {'a', 'b'}), {'b'});
    expect(newlyJoinedSocketIds(const {'a', 'b'}, const {'a', 'b'}), isEmpty);
    expect(newlyJoinedSocketIds(const {'a'}, const {'b'}), isEmpty,
        reason: '离开产生的新集合不算"加入"');
  });
}
```

第二个用例需要 `import 'package:flow_muse/features/whiteboard/views/whiteboard_page.dart';`（`newlyJoinedSocketIds` 为顶层公开函数，见 Step 4.7）。此时两个用例均应失败（红）。

- [ ] **Step 4.2：WhiteboardPage 新增状态字段与 import**

`whiteboard_page.dart` 状态区（L111 `_lastIdleState` 附近）新增：

```dart
String? _guestCreatorSessionId;
final Map<String, String> _socketCreatorKeys = {}; // socketId -> creatorKey（Task 9/14 消费）
int _presenceCreatorRevision = 0;
```

文件头新增 import（按既有 import 风格）：

```dart
import 'package:uuid/uuid.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_creator_identity.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
```

- [ ] **Step 4.3：实现 _currentCreatorKey / _currentCreator**

在 `_collaborationIdentity` getter（L2719）附近新增：

```dart
/// 当前操作者 creatorKey。仅在协作房间内非空：本地笔记（activeRoom 为
/// null）不盖章，旧元素保持"历史内容"语义（v4 §0.1 首版范围）。
String? _currentCreatorKey() => _currentCreator()?.creatorKey;

CollaborationCreator? _currentCreator() {
  final room = ref.read(whiteboardViewModelProvider).activeRoom;
  if (room == null) return null;
  final identity = _collaborationIdentity;
  if (identity.isGuest) {
    final sessionId = _guestCreatorSessionId;
    if (sessionId == null) return null;
    return CollaborationCreator(
      creatorKey: creatorKeyForGuest(room.roomId, sessionId),
      displayName: identity.username,
      isGuest: true,
    );
  }
  final userId = identity.userId;
  if (userId == null) return null;
  return CollaborationCreator(
    creatorKey: creatorKeyForUserId(userId),
    displayName: identity.username,
    isGuest: false,
  );
}
```

**解释性裁决（供评审，并在 Task 16.6 落地记录中登记）**：非协作状态不盖章。理由：v4 §0.1 将首版范围限定在"协作中新建的元素"；本地笔记无房间上下文，游客键无法定义；登录用户若未来需要本地笔记归属，可另开任务把 `activeRoom == null` 分支改为按 identity 直接派生。注意这与 v4 R3（登录键跨房间稳定）不冲突：R3 保证的是"房间 A 已盖章元素在房间 B 仍能匹配"，本地笔记阶段**新建**的登录用户元素将无归属（进入协作后归"历史内容"），这是 R3 字面语义的推论空白而非矛盾。本计划选择最小语义。

- [ ] **Step 4.4：guest session UUID 生命周期**

1. `_listenToRoom`（L1631）开头、订阅建立前：

```dart
if (_collaborationIdentity.isGuest && _guestCreatorSessionId == null) {
  _guestCreatorSessionId = const Uuid().v4();
}
```

2. 清理点——找到 `_lastIdleState = null;` 的重置处（L1424 附近的退出流程），在同一函数体内追加：

```dart
_guestCreatorSessionId = null;
_socketCreatorKeys.clear();
_presenceCreatorRevision++;
```

同样在 `_handleRoomEnded`（L1693）的 `_cancelCollaborationStreams()` 之后追加相同四行。若两处最终都经同一私有函数（如 `_cancelCollaborationStreams` 本体），把清理收敛进该函数一次即可——以实际调用图为准，保证 **leave / end / 房主结束 / 页面销毁** 四条路径全部清空。

3. Socket 普通重连（`reconnecting → joined`）**不清** sessionUuid（这正是重连保持的关键）。

- [ ] **Step 4.5：三类广播携带 creatorKey**

修改三个发送函数，追加 `creatorKey: _currentCreatorKey()` 参数：

- `_doBroadcastPointerPresence`（L2634）→ `broadcastMouseLocation(..., creatorKey: _currentCreatorKey())`
- `_broadcastVisibleSceneBounds`（L2656）→ `broadcastVisibleSceneBounds(..., creatorKey: _currentCreatorKey())`
- `_broadcastIdleState`（L2695，改造见 Step 4.6）→ `broadcastIdleStatus(..., creatorKey: _currentCreatorKey())`

- [ ] **Step 4.6：_broadcastIdleState 增加 force**

把 L2695-2717 改为：

```dart
void _broadcastIdleState(String state, {bool force = false}) {
  if (!_canMutateWhiteboard) {
    return;
  }
  if (!force && _lastIdleState == state) {
    return;
  }
  final room = ref.read(whiteboardViewModelProvider).activeRoom;
  if (room == null) {
    return;
  }
  _lastIdleState = state;
  final identity = _collaborationIdentity;
  unawaited(
    _collaborationRepository.broadcastIdleStatus(
      room: room,
      userState: state,
      username: identity.username,
      userId: identity.userId,
      avatarUrl: identity.avatarUrl,
      creatorKey: _currentCreatorKey(),
    ),
  );
}
```

语义：`force: true` 只绕过 `_lastIdleState == state` 的去重短路，`_lastIdleState` 仍照常更新；普通 idle 更新路径（`_markUserActive` 等）不传 force，行为不变。

- [ ] **Step 4.7：三个补发触发点**

1. **首加入**：`_listenToRoom` 函数末尾（函数体结束、L1691 `}` 之前）追加：

```dart
// 首次 start/join 完成点：主动发送一次当前 presence，让已有成员立即
// 拿到 creatorKey，不等待用户移动指针（v4 §4.4 规则 2）。
_broadcastIdleState(_lastIdleState ?? 'active', force: true);
```

2. **重连**：connectionStatus 订阅（L1677-1690）中，在现有 `unawaited(_refreshCollaborationSnapshot(room));` 之后追加：

```dart
if (status == RealtimeConnectionStatus.joined &&
    previous == RealtimeConnectionStatus.reconnecting) {
  unawaited(_refreshCollaborationSnapshot(room));
  _broadcastIdleState(_lastIdleState ?? 'active', force: true); // ← 新增行
}
```

（实现时保持既有 if 结构，只在其块内加一行，不复制整个 if。）

3. **新成员加入**：先在 `whiteboard_page.dart` 文件级（`WhiteboardPage` 类声明之外）提取可单测纯函数：

```dart
/// 计算 roomUsers 批次中的新增 socket 集合（离开方向不产生"加入"）。
/// 公开以便源码级单测（Task 4 Step 4.1）。
Set<String> newlyJoinedSocketIds(Set<String> previous, Set<String> next) =>
    next.difference(previous);
```

然后在 roomUsers 订阅（L1652-1661）中，在 `_roomSocketIds = nextSocketIds;` **之前**（此时 `_roomSocketIds` 仍是旧集合）插入：

```dart
final joinedSocketIds = newlyJoinedSocketIds(_roomSocketIds, nextSocketIds);
```

在 `_roomSocketIds = nextSocketIds;` 之后、`_runAfterStableFrame` 之前追加：

```dart
if (joinedSocketIds.isNotEmpty) {
  // 后加入者触发：本端强制绕过 idle 去重补发一次自身 presence，
  // 使静止的先在线者身份可达（v4 §4.4 规则 3）。单批多人加入只发一次；
  // 含自身 socket 时该发送幂等冗余，无害；只响应加入，不响应离开。
  _broadcastIdleState(_lastIdleState ?? 'active', force: true);
}
```

（departed 循环里同时追加 `_socketCreatorKeys.remove(departed);`。）

- [ ] **Step 4.8：接收端 socket→creatorKey 映射维护**

`_handleCollaborationMessage`（L1891-1920）中，三类 presence 转发给 view model 之后追加：

```dart
if (message.type == CollaborationMessageType.mouseLocation ||
    message.type == CollaborationMessageType.idleStatus ||
    message.type == CollaborationMessageType.userVisibleSceneBounds) {
  final socketId = message.payload['socketId'] as String?;
  final fallbackUserId = message.payload['userId'] as String?;
  final creatorKey =
      message.payload['creatorKey'] as String? ??
      (fallbackUserId == null ? null : creatorKeyForUserId(fallbackUserId));
  if (socketId != null && creatorKey != null) {
    final changed = _socketCreatorKeys[socketId] != creatorKey;
    if (changed) {
      _socketCreatorKeys[socketId] = creatorKey;
      _presenceCreatorRevision++;
    }
  }
}
```

本任务不 setState（渲染层消费发生在 Task 13/14 之后）。Step 4.1 的两个源码/纯函数断言用例在 Step 4.3-4.7 落地后应转为全绿。

- [ ] **Step 4.9：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/views/whiteboard_page_creator_presence_test.dart test/features/whiteboard/collaboration/
dart format lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/views/whiteboard_page_creator_presence_test.dart
git add lib/features/whiteboard/views/whiteboard_page.dart lib/features/whiteboard/view_models/whiteboard_view_model.dart test/features/whiteboard/views/whiteboard_page_creator_presence_test.dart
git commit -m "feat: 协作会话身份生命周期与创建者键补发"
```

---

# Task 5：本地创建/更新归属盖章全链路（stamping + controller 收口 + 宿主接线）

**目标**：所有本地 Add/Update 按 v4 §5.2 表格盖章；14 处 `_editorState.applyResult` 绕过点收口。

**上游 spec**：v4 §5.1、§5.2、§3.1。

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/creator_stamping.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（applyResult L1033-1073 + 14 处直连点）
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（注入回调）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/creator_stamping_test.dart`

**Interfaces:**
- Consumes: Task 1 `readCreator/withCreator/withoutCreator`、`Element.copyWith`、`scene.getElementById`。
- Produces:
```dart
// creator_stamping.dart
ToolResult stampCreatorOnResult(ToolResult result, Scene scene, CollaborationCreator creator);
// MarkdrawController 公开可空字段（宿主注入；null = 不盖章）
ToolResult? Function(ToolResult result, Scene currentScene)? onPrepareLocalResult;
CollaborationCreator? Function()? localCreatorResolver; // Task 8 split pane 用
```

- [ ] **Step 5.1：写失败测试**

新建 `test/features/whiteboard/editor_core/creator_stamping_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/creator_stamping.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = CollaborationCreator(creatorKey: 'user:a', displayName: 'A', isGuest: false);
  const bob = CollaborationCreator(creatorKey: 'user:b', displayName: 'B', isGuest: false);

  RectangleElement rect({String id = 'r', String? frameId, Map<String, Object?>? customData}) =>
      RectangleElement(id: ElementId(id), x: 0, y: 0, width: 5, height: 5, frameId: frameId, customData: customData);

  test('Add 普通元素覆盖为当前 creator（即使传入自带旧 owner）', () {
    final result = AddElementResult(withCreator(rect(), bob));
    final stamped = stampCreatorOnResult(result, Scene(), alice);
    expect(readCreator((stamped as AddElementResult).element)?.creatorKey, 'user:a');
  });

  test('Add 系统元素（page/pdfBackground）不写 owner', () {
    final page = rect(customData: const {
      'flowMuse': {'role': 'page', 'pageId': 'p1'},
    });
    final stamped = stampCreatorOnResult(AddElementResult(page), Scene(), alice);
    expect(readCreator((stamped as AddElementResult).element), isNull);

    final pdf = rect(customData: const {
      'flowMuse': {'pageId': 'p1', 'pdfBackground': true},
    });
    final stampedPdf = stampCreatorOnResult(AddElementResult(pdf), Scene(), alice);
    expect(readCreator((stampedPdf as AddElementResult).element), isNull);
  });

  test('Add 绑定文字：父在同批 CompoundResult 中 → 继承父 owner', () {
    final parent = withCreator(rect(id: 'arrow1'), alice);
    final boundText = TextElement(
      id: const ElementId('t1'), x: 0, y: 0, width: 5, height: 5,
      text: 'label', containerId: 'arrow1',
    );
    final stamped = stampCreatorOnResult(
      CompoundResult([AddElementResult(parent), AddElementResult(boundText)]),
      Scene(),
      bob,
    ) as CompoundResult;
    expect(readCreator((stamped.results[0] as AddElementResult).element)?.creatorKey, 'user:a');
    expect(readCreator((stamped.results[1] as AddElementResult).element)?.creatorKey, 'user:a');
  });

  test('Add 绑定文字：父在当前 Scene 且无 owner → 绑定文字也无 owner', () {
    final scene = Scene().addElement(rect(id: 'arrow2'));
    final boundText = TextElement(
      id: const ElementId('t2'), x: 0, y: 0, width: 5, height: 5,
      text: 'label', containerId: 'arrow2',
    );
    // 传入自带 owner 也要被清掉
    final stamped = stampCreatorOnResult(
      AddElementResult(withCreator(boundText, bob)), scene, bob,
    ) as AddElementResult;
    expect(readCreator(stamped.element), isNull);
  });

  test('Update：Scene 中已有 owner 强制保留，忽略更新对象中的 owner 变化', () {
    final existing = withCreator(rect(id: 'r9'), alice);
    final scene = Scene().addElement(existing);
    final stamped = stampCreatorOnResult(
      UpdateElementResult(withCreator(rect(id: 'r9'), bob)), scene, bob,
    ) as UpdateElementResult;
    expect(readCreator(stamped.element)?.creatorKey, 'user:a');
  });

  test('Update：历史元素（无 owner）继续无 owner，即使更新对象携带 owner', () {
    final scene = Scene().addElement(rect(id: 'r10'));
    final stamped = stampCreatorOnResult(
      UpdateElementResult(withCreator(rect(id: 'r10'), bob)), scene, bob,
    ) as UpdateElementResult;
    expect(readCreator(stamped.element), isNull);
  });

  test('Remove/Selection/Clipboard/Viewport/SwitchTool/SetSmartLayout 不处理', () {
    final untouched = <ToolResult>[
      RemoveElementResult(const ElementId('x')),
      SetSelectionResult({}),
      UpdateViewportResult(const ViewportState(zoom: 1, offset: Offset.zero)),
      SwitchToolResult(ToolType.select),
      SetSmartLayoutResult(null),
    ];
    for (final result in untouched) {
      expect(identical(stampCreatorOnResult(result, Scene(), alice), result), isTrue);
    }
  });
}
```

**编译要点（实测核实）**：`SetSelectionResult`/`SetSmartLayoutResult` 及全部 ToolResult 变体的构造函数**都不是 const**——上面代码不可给它们加 `const` 前缀（`const ElementId(...)` 与 `const ViewportState(...)` 可以，这两个类的构造是 const）。测试文件还需补充三个 import：

```dart
import 'dart:ui' show Offset;
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
```

- [ ] **Step 5.2：运行确认失败**

- [ ] **Step 5.3：实现 creator_stamping.dart**

新建 `lib/features/whiteboard/editor_core/src/editor/creator_stamping.dart`：

```dart
import '../core/elements/collaboration_element_owner.dart';
import '../core/elements/elements.dart';
import '../core/layout/canvas_layout.dart';
import '../core/scene/scene_exports.dart';
import 'tool_result.dart';

/// 对本地用户产生的 [result] 统一执行 v4 §5.2 归属规则：
/// - Add 普通独立元素：无论传入是否自带 owner，覆盖为当前操作者；
/// - Add 绑定文字（TextElement.containerId 非空）：优先同批先新增的父
///   元素，其次当前 Scene 父元素；父无 owner 则绑定文字无 owner；
/// - Add 系统元素（CanvasPage/PDF Background）：清除 owner；
/// - Update：强制保留 Scene 中既有 owner（无则继续无）；
/// - 其余结果类型原样返回。
/// 纯函数，不改输入；与 undo/redo、远端 applyRemote* 无关（它们不经过
/// 本函数）。
ToolResult stampCreatorOnResult(
  ToolResult result,
  Scene scene,
  CollaborationCreator creator,
) {
  final batchCreators = <ElementId, CollaborationCreator>{};
  return _walk(result, scene, creator, batchCreators);
}

ToolResult _walk(
  ToolResult node,
  Scene scene,
  CollaborationCreator creator,
  Map<ElementId, CollaborationCreator> batchCreators,
) {
  switch (node) {
    case AddElementResult(:final element):
      final stamped = _stampAdd(element, scene, batchCreators, creator);
      return identical(stamped, element) ? node : AddElementResult(stamped);
    case UpdateElementResult(:final element):
      final stamped = _stampUpdate(element, scene);
      return identical(stamped, element) ? node : UpdateElementResult(stamped);
    case CompoundResult(:final results):
      // 两遍处理（v4 §5.2："必须能看到同批次先新增的父元素"）：第一遍
      // 处理非绑定文字（父元素），第二遍处理绑定文字——即使绑定文字在
      // 列表中排在父元素之前也能正确继承。非元素结果与嵌套 CompoundResult
      // 原样保留在原位。元素顺序本身不重排（最终场景顺序由 fractional
      // index 决定，重排 Add 无行为差异，但保持原序更稳妥）。
      var changed = false;
      final stampedMap = <ToolResult, ToolResult>{};
      void stampRound(bool boundRound) {
        for (final child in results) {
          if (child is! AddElementResult) continue;
          final isBoundText = child.element is TextElement &&
              (child.element as TextElement).containerId != null;
          if (isBoundText != boundRound) continue;
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        }
      }

      stampRound(false); // 先父元素
      stampRound(true); // 后绑定文字
      for (final child in results) {
        if (child is UpdateElementResult) {
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        } else if (child is CompoundResult) {
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        }
      }
      if (!changed) return node;
      return CompoundResult([
        for (final child in results) stampedMap[child] ?? child,
      ]);
    default:
      return node;
  }
}

Element _stampAdd(
  Element element,
  Scene scene,
  Map<ElementId, CollaborationCreator> batchCreators,
  CollaborationCreator creator,
) {
  if (element.isCanvasPage || element.isPdfBackground) {
    return withoutCreator(element);
  }
  final containerId = element is TextElement ? element.containerId : null;
  if (containerId != null) {
    final parentCreator =
        batchCreators[ElementId(containerId)] ??
        _creatorOfSceneElement(scene, ElementId(containerId));
    if (parentCreator == null) {
      return withoutCreator(element);
    }
    batchCreators[element.id] = parentCreator;
    return withCreator(element, parentCreator);
  }
  batchCreators[element.id] = creator;
  return withCreator(element, creator);
}

Element _stampUpdate(Element element, Scene scene) {
  final existing = scene.getElementById(element.id);
  if (existing == null) return element;
  final existingCreator = readCreator(existing);
  if (existingCreator == null) {
    return withoutCreator(element);
  }
  final incoming = readCreator(element);
  if (incoming != null &&
      incoming.creatorKey == existingCreator.creatorKey &&
      incoming.displayName == existingCreator.displayName &&
      incoming.isGuest == existingCreator.isGuest) {
    return element;
  }
  return withCreator(element, existingCreator);
}

CollaborationCreator? _creatorOfSceneElement(Scene scene, ElementId id) {
  final element = scene.getElementById(id);
  if (element == null) return null;
  return readCreator(element);
}
```

`isCanvasPage`/`isPdfBackground` 来自 `canvas_layout.dart` 的 `FlowMuseElementData` 扩展（L251-257）——`src/editor` 层 import `core/layout` 无循环风险。

- [ ] **Step 5.4：controller 增加 onPrepareLocalResult 并收口 14 处直连点**

1. `MarkdrawController` 公开字段区（`onSceneChanged` 附近）新增：

```dart
/// 宿主注入的本地结果预处理回调（仅本地用户变更经过；远端 applyRemote*、
/// undo/redo、reset 不经过）。执行顺序固定于 default style 之后、系统剪贴板
/// 副作用之前（v4 §5.1）。
ToolResult? Function(ToolResult result, Scene currentScene)? onPrepareLocalResult;

/// 当前本地创建者快照解析器（宿主注入；split pane sidecar 用于新增行盖章，
/// 见 v4 §9.1 规则 3）。null = 无协作上下文，不盖章。
CollaborationCreator? Function()? localCreatorResolver;
```

（需要 import `../core/elements/collaboration_element_owner.dart`。）

2. `applyResult`（L1033-1073）在 `final styled = ...` 之后、`_syncToSystemClipboard(styled);` 之前插入：

```dart
final prepared =
    onPrepareLocalResult?.call(styled, _editorState.scene) ?? styled;
```

并把函数体内后续所有 `styled` 引用（L1041 `_syncToSystemClipboard(styled)`、L1043 `_containsSelectionChange(styled)`、L1047 `_editorState.applyResult(styled)`、L1063 `isSceneChangingResult(styled)`、L1064 `_changedElementsFromResult(styled, ...)`、L1069 `_scheduleInkRecognitionFromResult(styled)`）全部改为 `prepared`。

3. 新增私有 helper（放在 `applyResult` 之后）：

```dart
/// 文本编辑等内部路径的统一收口：经 onPrepareLocalResult 盖章后应用并
/// 替换 _editorState（v4 §5.1：不得只覆盖公开 applyResult）。
EditorState _applyLocalResult(ToolResult? result) {
  final prepared = result == null
      ? null
      : onPrepareLocalResult?.call(result, _editorState.scene) ?? result;
  _editorState = _editorState.applyResult(prepared);
  return _editorState;
}
```

4. 把以下 14 处 `_editorState = _editorState.applyResult(X);` 机械替换为 `_applyLocalResult(X);`（行号为基线参考，以当前代码实际匹配为准；替换模式：赋值语句整体换成 helper 调用，忽略 helper 返回值）：

| 行号（基线） | 所在方法 |
|---|---|
| L1562 | `startTextEditingExisting` |
| L1592、L1597 | `startBoundTextEditing` |
| L1635、L1640 | `startArrowLabelEditing` |
| L1669、L1677、L1682、L1686 | `commitTextEditing` |
| L1713、L1721、L1731、L1736 | `cancelTextEditing` |
| L1814 | `onTextChanged` |

`dart analyze` 应确认替换后不存在剩余的 `_editorState = _editorState.applyResult`（`applyResult` 公开方法内那一处除外——它在 L1047 已改用 prepared）。

- [ ] **Step 5.5：宿主接线（WhiteboardPage）**

`initState` 中创建 controller 之后（`_markdrawController = MarkdrawController();` 在 L139，接线放在其后的初始化区域）：

```dart
// _currentCreator() 已在 Task 4 Step 4.3 于 WhiteboardPage 定义
_markdrawController.onPrepareLocalResult = (result, scene) {
  final creator = _currentCreator();
  if (creator == null) return result;
  return stampCreatorOnResult(result, scene, creator);
};
```

import 增加 `creator_stamping.dart`。`dispose` 中置 null（`_markdrawController.onPrepareLocalResult = null;`）。

- [ ] **Step 5.6：controller 级回归测试**

在 `test/features/whiteboard/editor_core/creator_stamping_test.dart` 追加：

```dart
test('controller.applyResult 经过 onPrepareLocalResult 且顺序在剪贴板副作用之前', () {
  final controller = MarkdrawController();
  final order = <String>[];
  controller.onPrepareLocalResult = (result, scene) {
    order.add('prepare');
    return stampCreatorOnResult(result, scene, alice);
  };
  controller.applyResult(AddElementResult(rect(id: 'via-apply')));
  expect(order, ['prepare']);
  final added = controller.editorState.scene.elements.single;
  expect(readCreator(added)?.creatorKey, 'user:a');
  controller.dispose();
});

test('undo/redo 保留原归属（不重新盖章、不丢 owner）', () {
  final controller = MarkdrawController();
  controller.onPrepareLocalResult = (result, scene) =>
      stampCreatorOnResult(result, scene, alice);
  controller.applyResult(AddElementResult(rect(id: 'undo-1')));
  expect(readCreator(controller.editorState.scene.elements.single)?.creatorKey, 'user:a');
  controller.undo();
  expect(controller.editorState.scene.elements, isEmpty);
  controller.redo();
  final restored = controller.editorState.scene.elements.single;
  expect(readCreator(restored)?.creatorKey, 'user:a',
      reason: 'redo 恢复原元素及其原归属（v4 §3.1）');
  controller.dispose();
});

test('CompoundResult 中绑定文字排在父元素之前也能继承父 owner（两遍处理）', () {
  final parent = withCreator(rect(id: 'arrow3'), alice);
  final boundText = TextElement(
    id: const ElementId('t3'), x: 0, y: 0, width: 5, height: 5,
    text: 'label', containerId: 'arrow3',
  );
  final stamped = stampCreatorOnResult(
    CompoundResult([AddElementResult(boundText), AddElementResult(parent)]),
    Scene(),
    bob,
  ) as CompoundResult;
  expect(readCreator((stamped.results[0] as AddElementResult).element)?.creatorKey, 'user:a');
  expect(readCreator((stamped.results[1] as AddElementResult).element)?.creatorKey, 'user:a');
});
```

（`MarkdrawController()` 直接构造与 `controller.undo()/redo()` 均有先例：`test/features/whiteboard/editor_core/scene_dirty_elements_test.dart` 与 `markdraw_controller_test.dart`。若 undo/redo 方法名不同，以 controller 实际 API 为准调整。粘贴/导入/AI/思维导图/流程图/智能排版产物全部经 `AddElementResult`/`CompoundResult` 进入同一条盖章路径——"Add 普通元素覆盖为当前 creator（即使传入自带旧 owner）"用例即其语义等价测试，不再逐功能重复造 fixture。tombstone：`RemoveElementResult` 走 Scene soft-delete（`isDeleted` 标记），customData 随元素快照原样保留、任何任务都不剥离——undo/redo 用例即为该机制的间接断言。）

- [ ] **Step 5.7：运行全部相关测试 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/ test/features/whiteboard/views/
dart format lib/features/whiteboard/editor_core/src/editor/creator_stamping.dart lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/creator_stamping_test.dart
git add lib/features/whiteboard/editor_core/src/editor/creator_stamping.dart lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/creator_stamping_test.dart
git commit -m "feat: 本地元素创建/更新统一盖章并收口直连应用路径"
```

---

# Task 6：reconciler 归属回填、冲突计数与父子规范化

**目标**：LWW winner 确定后做确定性归属修复；不改比较规则；copy-on-write；脱敏日志。

**上游 spec**：v4 §5.3、§5.4。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/services/scene_reconciler.dart`
- Test: `FlowMuse-App/test/features/whiteboard/collaboration/services/scene_reconciler_owner_test.dart`

**Interfaces:**
- Consumes: Task 1 `readCreatorFromJson` / `withCreatorInJson` / `withoutCreatorInJson`。
- Produces: `reconcile` 签名不变；行为新增（回填/规范化/日志）。

- [ ] **Step 6.1：写失败测试**

新建 `test/features/whiteboard/collaboration/services/scene_reconciler_owner_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/collaboration/services/scene_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> el(
  String id, {
  int version = 1,
  int nonce = 1,
  String? ownerKey,
  String ownerName = '张三',
  bool ownerGuest = false,
  String? containerId,
  String type = 'rectangle',
}) {
  return <String, Object?>{
    'id': id,
    'type': type,
    'version': version,
    'versionNonce': nonce,
    'index': 'a$id',
    if (containerId != null) 'containerId': containerId,
    if (ownerKey != null)
      'customData': {
        'flowMuse': {
          'collaborationOwner': {
            'version': 1,
            'creatorKey': ownerKey,
            'displayName': ownerName,
            'isGuest': ownerGuest,
          },
        },
      },
  };
}

List<Map<String, Object?>> deepCopy(List<Map<String, Object?>> input) =>
    [for (final e in input) Map<String, Object?>.from(e)];

void main() {
  final reconciler = SceneReconciler();

  test('winner 有 owner、loser 无 → winner 原样（远端胜出版本更高）', () {
    final local = [el('e1', version: 1, ownerKey: 'user:a')];
    final remote = [el('e1', version: 2)];
    final out = reconciler.reconcile(localElements: local, remoteElements: remote);
    expect(out.first['customData'], isNotNull);
  });

  test('winner 缺 owner、loser 有 → 从 loser 回填且其他 customData 保留', () {
    final local = [el('e1', version: 2)];
    final remote = [
      el('e1', version: 1, ownerKey: 'user:b'),
    ];
    final out = reconciler.reconcile(localElements: local, remoteElements: remote);
    final flowMuse = (out.first['customData'] as Map)['flowMuse'] as Map;
    expect((flowMuse['collaborationOwner'] as Map)['creatorKey'], 'user:b');
  });

  test('双方 owner 不同且都非空 → LWW winner 生效；local/remote 交换后结果一致', () {
    final a = [el('e1', version: 2, nonce: 5, ownerKey: 'user:a')];
    final b = [el('e1', version: 2, nonce: 9, ownerKey: 'user:b')];
    final out1 = reconciler.reconcile(localElements: a, remoteElements: b);
    final out2 = reconciler.reconcile(localElements: b, remoteElements: a);
    final k1 = (((out1.first['customData'] as Map)['flowMuse'] as Map)['collaborationOwner'] as Map)['creatorKey'];
    final k2 = (((out2.first['customData'] as Map)['flowMuse'] as Map)['collaborationOwner'] as Map)['creatorKey'];
    expect(k1, k2, reason: '交换参数后必须收敛到同一 winner owner');
    expect(k1, 'user:a'); // version 相同 nonce 5 < 9 → local(a) 胜
  });

  test('双方都无 owner → 输出无 owner', () {
    final out = reconciler.reconcile(
      localElements: [el('e1', version: 2)],
      remoteElements: [el('e1', version: 1)],
    );
    expect(out.first.containsKey('customData'), isFalse);
  });

  test('回填 copy-on-write：输入列表与嵌套 Map 在 reconcile 后完全不变', () {
    final local = deepCopy([el('e1', version: 2)]);
    final remote = deepCopy([el('e1', version: 1, ownerKey: 'user:b')]);
    final localBefore = local.toString();
    final remoteBefore = remote.toString();
    reconciler.reconcile(localElements: local, remoteElements: remote);
    expect(local.toString(), localBefore);
    expect(remote.toString(), remoteBefore);
  });

  test('父子规范化：绑定文字 owner 跟随结果集父元素（补齐/清除两向）', () {
    // 父赢且带 owner，绑定文字旧数据无 owner → 补齐
    final local = [
      el('parent', version: 2, ownerKey: 'user:a'),
      el('child', version: 1, type: 'text', containerId: 'parent'),
    ];
    final out = reconciler.reconcile(localElements: local, remoteElements: []);
    final child = out.firstWhere((e) => e['id'] == 'child');
    expect(
      (((child['customData'] as Map)['flowMuse'] as Map)['collaborationOwner'] as Map)['creatorKey'],
      'user:a',
    );

    // 父无 owner，绑定文字残留 owner → 清除
    final local2 = [
      el('parent2', version: 2),
      el('child2', version: 1, type: 'text', containerId: 'parent2', ownerKey: 'user:x'),
    ];
    final out2 = reconciler.reconcile(localElements: local2, remoteElements: []);
    final child2 = out2.firstWhere((e) => e['id'] == 'child2');
    expect(child2.containsKey('customData'), isFalse);
  });

  test('规范化不改 version/versionNonce', () {
    final local = [
      el('parent', version: 7, nonce: 3, ownerKey: 'user:a'),
      el('child', version: 9, nonce: 4, type: 'text', containerId: 'parent'),
    ];
    final out = reconciler.reconcile(localElements: local, remoteElements: []);
    final child = out.firstWhere((e) => e['id'] == 'child');
    expect(child['version'], 9);
    expect(child['versionNonce'], 4);
  });

  test('仅本地独有元素不触发回填（无 loser）', () {
    final out = reconciler.reconcile(
      localElements: [el('solo', version: 1, ownerKey: 'user:a')],
      remoteElements: [],
    );
    expect(out.single['id'], 'solo');
  });
}
```

- [ ] **Step 6.2：运行确认失败**（回填/规范化用例 FAIL）

- [ ] **Step 6.3：实现 reconciler 修复**

`scene_reconciler.dart` 修改（保持 `_shouldKeepLocal` 与既有比较逻辑零改动）：

1. import 增加：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';

import 'collaboration_debug_log.dart';
```

2. `reconcile` 主循环中，`result.add(chosen);` 改为 `result.add(_repairOwner(chosen, local, remote, counters));`，并在循环前声明 `final counters = _OwnerRepairCounters();`。

3. 循环 `for (final local in localElements) {...}` 之后、`result.sort(...)` 之前插入：

```dart
final normalized = _normalizeBoundTextOwners(result, counters);
result
  ..clear()
  ..addAll(normalized);
```

4. 代码组织（Dart 类体内不能声明类，且 `_id` 是 `SceneReconciler` 的**实例方法**）：`_repairOwner` 与 `_normalizeBoundTextOwners` 作为**实例方法**加入 `SceneReconciler` 类内（它们调用 `_id`）；`_OwnerRepairCounters` 作为**顶层私有类**放在 `SceneReconciler` 类声明之后（同文件底部，独立于下方代码块的呈现顺序）：

```dart
class _OwnerRepairCounters {
  int conflictCount = 0;
  int backfillCount = 0;
}

/// v4 §5.3：winner 选定后的归属修复。winner 有 owner → 原样（双方都
/// 非空且不同只计数，不改输出）；winner 缺失 → 从 loser 回填。
Map<String, Object?> _repairOwner(
  Map<String, Object?> winner,
  Map<String, Object?>? local,
  Map<String, Object?> remote,
  _OwnerRepairCounters counters,
) {
  final winnerCreator = readCreatorFromJson(winner);
  final loser = identical(winner, local) ? remote : local;
  final loserCreator = loser == null ? null : readCreatorFromJson(loser);
  if (winnerCreator != null) {
    if (loserCreator != null && loserCreator.creatorKey != winnerCreator.creatorKey) {
      counters.conflictCount++;
    }
    return winner;
  }
  if (loserCreator == null) return winner;
  counters.backfillCount++;
  return withCreatorInJson(winner, loserCreator);
}

/// v4 §5.3：结果集父子规范化。containerId 非空的 text 元素 owner 以结果
/// 集中父元素为准（父缺失或无 owner → 清除）。不改 version/versionNonce，
/// 所有客户端面对同一结果集得到相同输出。
List<Map<String, Object?>> _normalizeBoundTextOwners(
  List<Map<String, Object?>> elements,
  _OwnerRepairCounters counters,
) {
  final byId = <String, Map<String, Object?>>{
    for (final element in elements) _id(element): element,
  };
  final output = <Map<String, Object?>>[];
  for (final element in elements) {
    final containerId = element['containerId'];
    if (element['type'] != 'text' || containerId is! String) {
      output.add(element);
      continue;
    }
    final parent = byId[containerId];
    final parentCreator = parent == null ? null : readCreatorFromJson(parent);
    final currentCreator = readCreatorFromJson(element);
    if (parentCreator == null) {
      output.add(currentCreator == null ? element : withoutCreatorInJson(element));
    } else if (currentCreator != null &&
        currentCreator.creatorKey == parentCreator.creatorKey) {
      output.add(element);
    } else {
      output.add(withCreatorInJson(element, parentCreator));
    }
  }
  return output;
}
```

5. `reconcile` 返回前输出脱敏日志（只在有计数时打一行）：

```dart
if (counters.conflictCount > 0 || counters.backfillCount > 0) {
  CollaborationDebugLog.write('scene_reconciler', 'owner_repair', {
    'ownerConflictCount': counters.conflictCount,
    'ownerBackfillCount': counters.backfillCount,
  });
}
```

- [ ] **Step 6.4：运行测试确认全绿 + 既有 reconciler 回归**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/collaboration/
```

- [ ] **Step 6.5：format + commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/collaboration/services/scene_reconciler.dart test/features/whiteboard/collaboration/services/scene_reconciler_owner_test.dart
git add -A lib/features/whiteboard/collaboration test/features/whiteboard/collaboration
git commit -m "fix: LWW合并后确定性回填创建者并规范化绑定文字归属"
```

---

# Task 7：外部导出收口与不可信导入剥离

**目标**：内部/外部序列化双入口；六类外部产物无 owner；外部导入先剥离。

**上游 spec**：v4 §10.1-§10.4、§9.2、§9.3。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（serializeScene 区 L6563-7060）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart`（L39、L47、L79、L105）
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/share_export_coordinator.dart`（L52）
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/imported_document_coordinator.dart`（L26-31）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/external_export_boundary_test.dart`

**Interfaces:**
- Consumes: Task 1 两个 sanitizer。
- Produces:
```dart
// MarkdrawController：
String serializeSceneForExternalExport({DocumentFormat format = DocumentFormat.markdraw, bool includeDeleted = false});
// loadFromContent 增加命名参数：
void loadFromContent(String content, String filename, {bool isExternalImport = false});
// exportPng / exportSvg 内部对传给 Exporter 的 scene 统一 sanitize（签名不变）
// addToLibrary：入库前净化 item 元素（签名不变）
// exportLibraryContent：导出前净化（签名不变）
```

调用点契约（本任务迁移完成后必须成立）：
- **外部**（sanitize）：`markdraw_file_handler.save/saveAs`、`share_export_coordinator.prepareDocument`、controller `exportPng/exportSvg/exportLibraryContent`、`imported_document_coordinator.preview`（输出侧）、`loadFromContent(isExternalImport: true)`。
- **内部**（保留 owner）：`whiteboard_page` L328/L416/L1474/L1502 四处 `serializeScene(format: DocumentFormat.excalidraw)`（本地笔记/PDF 草稿/临时房间保存）、`markdraw_split_pane` L153、协作 adapter `serializeExcalidrawSceneJson`、`applyRemoteContent`。

- [ ] **Step 7.1：写失败测试**

新建 `test/features/whiteboard/editor_core/external_export_boundary_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/io/document_format.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = CollaborationCreator(creatorKey: 'user:z', displayName: '赵六', isGuest: false);

  MarkdrawController buildControllerWithOwnedElement() {
    final controller = MarkdrawController();
    controller.applyResult(AddElementResult(
      withCreator(
        RectangleElement(
          id: const ElementId('ext-1'), x: 0, y: 0, width: 10, height: 10,
          customData: const {
            'flowMuse': {'pageId': 'p1', 'brushType': 'fountainPen'},
          },
        ),
        creator,
      ),
    ));
    return controller;
  }

  test('serializeSceneForExternalExport(excralidraw) 产物无 collaborationOwner，其他 flowMuse 键保留', () {
    final controller = buildControllerWithOwnedElement();
    final json = controller.serializeSceneForExternalExport(format: DocumentFormat.excalidraw);
    expect(json.contains('collaborationOwner'), isFalse);
    expect(json.contains('pageId'), isTrue);
    expect(json.contains('brushType'), isTrue);
    controller.dispose();
  });

  test('内部 serializeScene(excralidraw) 仍保留 owner', () {
    final controller = buildControllerWithOwnedElement();
    final json = controller.serializeScene(format: DocumentFormat.excalidraw);
    expect(json.contains('collaborationOwner'), isTrue);
    controller.dispose();
  });

  test('最终产物断言：exportSvg / exportLibraryContent / exportPng 嵌入数据均无 owner', () async {
    final controller = buildControllerWithOwnedElement();

    // SVG 最终字符串
    final svg = controller.exportSvg(selectedOnly: false);
    expect(svg.contains('collaborationOwner'), isFalse);

    // Library 最终产物（先生成一个 item 再导出）
    controller.addToLibrary();
    final library = controller.exportLibraryContent();
    expect(library.contains('collaborationOwner'), isFalse);

    // PNG tEXt 嵌入数据（最终字节内 base64 解码后断言）
    final png = await controller.exportPng(selectedOnly: false, embedMarkdraw: true);
    expect(png, isNotNull);
    final embedded = PngMetadata.extractTextChunk(png!, 'markdraw');
    expect(embedded, isNotNull);
    final decoded = utf8.decode(base64Decode(embedded!));
    expect(decoded.contains('collaborationOwner'), isFalse);
    controller.dispose();
  });

  test('loadFromContent(isExternalImport: true) 剥离不可信 owner；默认 false 保留', () {
    final controller = buildControllerWithOwnedElement();
    final withOwner = controller.serializeScene(format: DocumentFormat.excalidraw);
    controller.dispose();

    final external = MarkdrawController();
    external.loadFromContent(withOwner, 'a.excalidraw', isExternalImport: true);
    expect(readCreator(external.editorState.scene.elements.single), isNull);
    expect(
      (external.editorState.scene.elements.single.customData!['flowMuse'] as Map)['pageId'],
      'p1',
    );
    external.dispose();

    final internal = MarkdrawController();
    internal.loadFromContent(withOwner, 'a.excalidraw');
    expect(readCreator(internal.editorState.scene.elements.single)?.creatorKey, 'user:z');
    internal.dispose();
  });
}
```

- [ ] **Step 7.2：运行确认失败**

- [ ] **Step 7.3：controller 实现**

1. `serializeScene`（L6563）之后新增（**settings 实参块必须与现有 serializeScene L6563-6576 完全一致**，否则导出文件丢失画布背景/网格/文档名；switch 兜底分支也保持与现有实现一致）：

```dart
/// 外部导出专用：先净化 collaborationOwner 再序列化。文件保存对话框、
/// 系统分享等外部出口只能调用本方法（v4 §10.3）；内部持久化与协作
/// 链路继续调用 [serializeScene]。
String serializeSceneForExternalExport({
  DocumentFormat format = DocumentFormat.markdraw,
  bool includeDeleted = false,
}) {
  final doc = SceneDocumentConverter.sceneToDocument(
    _editorState.scene,
    settings: CanvasSettings(
      background: _canvasBackgroundColor,
      backgroundFollowsTheme: _canvasBackgroundFollowsTheme,
      grid: _gridSize,
      name: _documentName,
    ),
    includeDeleted: includeDeleted,
  );
  final sanitized = sanitizeDocumentForExternalExport(doc);
  return switch (format) {
    DocumentFormat.excalidraw => ExcalidrawJsonCodec.serialize(sanitized),
    _ => DocumentSerializer.serialize(sanitized),
  };
}
```

2. `loadFromContent`（L6598）签名加 `{bool isExternalImport = false}`，在 `final parseResult = ...` 之后、读取 settings 之前插入：

```dart
var document = parseResult.value;
if (isExternalImport) {
  // 外部文件的 collaborationOwner 不可信：打开为本地笔记先剥离
  // （v4 §10.4）。内部本地笔记恢复不走本参数。
  document = sanitizeDocumentForExternalExport(document);
}
```

然后把函数体后续的 `parseResult.value` 引用改为 `document`（共 **5 处**：background、backgroundFollowsTheme、grid、name 四处 settings 读取，以及 `SceneDocumentConverter.documentToScene(parseResult.value)` 入参）。

3. `exportPng`（L6650）：`PngExporter.export(_editorState.scene, ...)` 的第一个实参改为：

```dart
sanitizeSceneForExternalExport(_editorState.scene),
```

4. `exportSvg`（L6676）：`SvgExporter.export(_editorState.scene, ...)` 同样改为 sanitize 后的 scene。

5. `addToLibrary`（L1867-1881）：`LibraryUtils.createFromElements(...)` 返回 item 后、加入 `_libraryItems` 前：

```dart
final sanitizedItem = item.copyWith(
  elements: [for (final e in item.elements) withoutCreator(e)],
);
```

以 `sanitizedItem` 入列表（素材模板不保留协作身份，v4 §9.3）。

6. `exportLibraryContent`（L7053）：序列化前对 `_libraryItems` 逐个做同样的 elements 净化，用净化后的 item 列表构造 `LibraryDocument` 再 `LibraryCodec.serialize` / `ExcalidrawLibCodec.serialize`（双保险，防历史遗留 item 带 owner）。

- [ ] **Step 7.4：调用点迁移**

1. `markdraw_file_handler.dart`：
   - L39（save）：`controller.serializeScene()` → `controller.serializeSceneForExternalExport()`
   - L47（saveAs）：同上（无参默认 markdraw；若该行带 format 参数则透传 format）
   - L79、L105（open 的两个 `controller.loadFromContent(...)`）：追加 `isExternalImport: true`
2. `share_export_coordinator.dart` L52：`controller.serializeScene(format: format)` → `controller.serializeSceneForExternalExport(format: format)`
3. `imported_document_coordinator.dart`：parse 成功分支（L26-31）在 `ExcalidrawJsonCodec.serialize(result.value)` 之前插一行：

```dart
final sanitizedDoc = sanitizeDocumentForExternalExport(result.value);
```

并改 serialize 入参为 `sanitizedDoc`（import `external_export_sanitizer.dart`）。

**明确不改**：`whiteboard_page.dart` 的四处 `serializeScene(format: DocumentFormat.excalidraw)`、`markdraw_split_pane.dart` L153、`whiteboard_collaboration_adapter.dart`、`document_service.dart`（其 `save/convert` 当前无 lib 内调用方传 Scene；在本任务 Step 7.6 的调用点审计中登记结论）。

- [ ] **Step 7.5：运行测试**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/external_export_boundary_test.dart test/features/whiteboard/editor_core/ test/features/whiteboard/share/
```

- [ ] **Step 7.6：调用点审计门禁（写进测试）**

在 `external_export_boundary_test.dart` 追加源码扫描用例与最终产物用例（import 需补 `dart:convert`、`png_metadata.dart`；`extractTextChunk(png, 'markdraw')` 的 keyword 常量值在 png_metadata.dart L20）：

```dart
test('外部出口调用点审计：file handler 与 share 只走外部 API', () {
  final handler = File('lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart').readAsStringSync();
  expect(handler.contains('serializeSceneForExternalExport'), isTrue);
  // 迁移后内部 serializeScene( 调用应为 0 次（serializeSceneForExternalExport(
  // 中 serializeScene 后跟 F 不是 (，不会被该正则误匹配）
  expect(RegExp(r'serializeScene\(').allMatches(handler), isEmpty,
      reason: 'file handler 不得再直接调用内部 serializeScene');

  final share = File('lib/features/whiteboard/share/services/share_export_coordinator.dart').readAsStringSync();
  expect(share.contains('serializeSceneForExternalExport'), isTrue);
  expect(RegExp(r'serializeScene\(').allMatches(share), isEmpty);
});

test('内部链路仍保留 owner：本地笔记保存不走外部 API', () {
  final page = File('lib/features/whiteboard/views/whiteboard_page.dart').readAsStringSync();
  // 四处本地持久化调用是多行写法，用宽松正则匹配
  expect(
    RegExp(r'serializeScene\(\s*format:\s*DocumentFormat\.excalidraw').hasMatch(page),
    isTrue,
    reason: '本地持久化必须继续使用内部 serializeScene',
  );
});

test('ShareExportCoordinator 产物门禁：prepareDocument 只走外部 API（源码断言）', () {
  final share = File('lib/features/whiteboard/share/services/share_export_coordinator.dart').readAsStringSync();
  expect(RegExp(r'serializeScene\(').allMatches(share), isEmpty,
      reason: 'share 的 markdraw/excalidraw 产物经 serializeSceneForExternalExport，最终字节由上一用例的 controller 级断言覆盖');
});
```

**六个序列化入口的全库调用点登记（v4 §10.3 要求，落地为文档登记 + 上面源码门禁）**：

| 入口 | lib 内调用点 | 登记 |
|---|---|---|
| `ExcalidrawJsonCodec.serialize` | document_service.dart L77、markdraw_controller.dart L6579（serializeScene 内部）、imported_document_coordinator.dart L31 | controller=内部保留；document_service 当前 lib 内无调用方（仅 `detectFormat` 被用）→ 登记为"无调用方，无需净化改造，保持观察"；coordinator=外部出口，已在本任务 Step 7.4.3 改为 sanitize 后再 serialize |
| `serializeScene`（controller） | file_handler L39/L47（已迁移外部 API）、split_pane L153、whiteboard_page L328/L416/L1474/L1502、share L52（已迁移外部 API） | split_pane 与 whiteboard_page 四处=内部保留（正确）；迁移后外部文件中该调用为 0（源码门禁锁定） |
| `PngExporter.export` | controller `_renderInkBlockPng` L4336（局部渲染，不落盘）、`exportPng` L6658 | exportPng 已 sanitize scene；ink block 渲染无嵌入、无落盘 → 无需净化 |
| `SvgExporter.export` | controller `exportSvg` L6680 | 已 sanitize（Step 7.3.4） |
| `LibraryCodec.serialize` | document_service L128（无 lib 调用方）、controller `exportLibraryContent` L7059 | exportLibraryContent 已 sanitize（Step 7.3.6） |
| `ExcalidrawLibCodec.serialize` | document_service L130（无 lib 调用方）、controller L7058/7060 | 同上 |

- [ ] **Step 7.7：format + commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart lib/features/whiteboard/share/services/share_export_coordinator.dart lib/features/whiteboard/share/services/imported_document_coordinator.dart test/features/whiteboard/editor_core/external_export_boundary_test.dart
git add lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart lib/features/whiteboard/share/services/share_export_coordinator.dart lib/features/whiteboard/share/services/imported_document_coordinator.dart test/features/whiteboard/editor_core/external_export_boundary_test.dart
git commit -m "fix: 外部导出统一净化创建者元数据并剥离不可信导入"
```

---

# Task 8：`.markdraw` 分屏 sidecar 与重复 alias 防护

**目标**：分屏编辑保归属（按 alias，不按原 UUID）；重复 alias 受控失败。

**上游 spec**：v4 §9.1。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（serializeScene 区）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/markdraw_split_pane_sidecar_test.dart`

**Interfaces:**
- Consumes: Task 1 owner codec、Task 5 `localCreatorResolver`、`SceneDocumentConverter`/`DocumentSerializer`。
- Produces:
```dart
// MarkdrawController：
({String text, Map<String, String> aliases}) serializeSceneWithAliases({
  DocumentFormat format = DocumentFormat.markdraw,
  bool includeDeleted = false,
});
// serializeScene 重构为 serializeSceneWithAliases(...).text 的薄封装（对外行为不变）
// MarkdrawSplitPane 私有状态：Map<String, CollaborationCreator> _aliasCreators
```

- [ ] **Step 8.1：写失败测试**

新建 `test/features/whiteboard/editor_core/markdraw_split_pane_sidecar_test.dart`。由于 sidecar 是 widget 私有状态，测试策略为：**纯函数提取**。把 sidecar 的归属决策提炼成顶层函数放进 split pane 文件并导出，测试直接调用：

```dart
// 在 markdraw_split_pane.dart 中导出（Task 8.3 实现）：
/// v4 §9.1 text→canvas 的归属决策（纯函数，供测试）。
/// 返回新元素列表：alias 命中 sidecar → 恢复；未命中 → localCreator 盖章
/// （null 则无 owner）；绑定文字继承父元素（两遍处理）；系统元素清除。
List<Element> applySidecarOwners({
  required List<Element> parsedElements,
  required Map<String, String> aliasToElementId, // parser 的 aliases
  required Map<String, CollaborationCreator> sidecar, // alias -> creator
  CollaborationCreator? Function()? localCreatorResolver,
})
```

测试：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = CollaborationCreator(creatorKey: 'user:a', displayName: 'A', isGuest: false);
  const bob = CollaborationCreator(creatorKey: 'user:b', displayName: 'B', isGuest: false);

  test('alias 命中 sidecar → 恢复原 owner（元素类型改变也恢复，规则 4）', () {
    final parsed = [RectangleElement(id: const ElementId('new-1'), x: 0, y: 0, width: 1, height: 1)];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect1': 'new-1'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single)?.creatorKey, 'user:a');
  });

  test('alias 未命中（新行/改名/重加）→ 当前操作者', () {
    final parsed = [RectangleElement(id: const ElementId('new-2'), x: 0, y: 0, width: 1, height: 1)];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect9': 'new-2'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single)?.creatorKey, 'user:b');
  });

  test('localCreatorResolver 为 null → 新行无 owner（本地无协作上下文）', () {
    final parsed = [RectangleElement(id: const ElementId('new-3'), x: 0, y: 0, width: 1, height: 1)];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'rect9': 'new-3'},
      sidecar: const {},
    );
    expect(readCreator(out.single), isNull);
  });

  test('绑定文字继承父元素（父在前在后都能正确处理）', () {
    final parsed = [
      TextElement(id: const ElementId('t'), x: 0, y: 0, width: 1, height: 1, text: 'x', containerId: 'new-p'),
      RectangleElement(id: const ElementId('new-p'), x: 0, y: 0, width: 1, height: 1),
    ];
    final out = applySidecarOwners(
      parsedElements: parsed,
      aliasToElementId: {'text1': 't', 'rect1': 'new-p'},
      sidecar: {'rect1': alice},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.firstWhere((e) => e.id == const ElementId('new-p')))!.creatorKey, 'user:a');
    expect(readCreator(out.firstWhere((e) => e.id == const ElementId('t')))!.creatorKey, 'user:a');
  });

  test('系统元素清除 owner', () {
    final parsed = [
      RectangleElement(id: const ElementId('pg'), x: 0, y: 0, width: 1, height: 1, customData: const {
        'flowMuse': {'role': 'page', 'pageId': 'p'},
      }),
    ];
    final out = applySidecarOwners(
      parsedElements: [for (final e in parsed) withCreator(e, alice)],
      aliasToElementId: {},
      sidecar: const {},
      localCreatorResolver: () => bob,
    );
    expect(readCreator(out.single), isNull);
  });

  test('findDuplicateAliasIds：真重复报出，前缀别名（rect1 vs rect11）不误报', () {
    const aliases = {'rect1': 'e1', 'rect11': 'e2', 'text1': 'e3'};
    expect(
      findDuplicateAliasIds('- rect | id=rect1\n- rect | id=rect11\n- text | id=text1', aliases),
      isEmpty,
      reason: 'rect1 不能因 rect11 的存在被误判重复',
    );
    expect(
      findDuplicateAliasIds('- rect | id=rect1\n- rect | id=rect1', aliases),
      ['rect1'],
    );
    expect(findDuplicateAliasIds('', aliases), isEmpty);
  });
}
```

- [ ] **Step 8.2：运行确认失败**

- [ ] **Step 8.3：实现 serializeSceneWithAliases 与 applySidecarOwners**

1. `markdraw_controller.dart`：把 `serializeScene`（L6563-6582）重构为：

```dart
String serializeScene({
  DocumentFormat format = DocumentFormat.markdraw,
  bool includeDeleted = false,
}) {
  return serializeSceneWithAliases(
    format: format,
    includeDeleted: includeDeleted,
  ).text;
}

/// 单次构建 MarkdrawDocument，同时返回序列化文本与 alias→ElementId
/// 映射（split pane sidecar 用；避免重复生成 alias，v4 T4 工作项 1）。
/// settings 实参块与重构前 serializeScene 完全一致（背景/网格/文档名
/// 不丢），switch 兜底分支同样保持一致。
({String text, Map<String, String> aliases}) serializeSceneWithAliases({
  DocumentFormat format = DocumentFormat.markdraw,
  bool includeDeleted = false,
}) {
  final doc = SceneDocumentConverter.sceneToDocument(
    _editorState.scene,
    settings: CanvasSettings(
      background: _canvasBackgroundColor,
      backgroundFollowsTheme: _canvasBackgroundFollowsTheme,
      grid: _gridSize,
      name: _documentName,
    ),
    includeDeleted: includeDeleted,
  );
  final text = switch (format) {
    DocumentFormat.excalidraw => ExcalidrawJsonCodec.serialize(doc),
    _ => DocumentSerializer.serialize(doc),
  };
  return (text: text, aliases: doc.aliases);
}
```

2. `markdraw_split_pane.dart`：
   a. 文件级新增公开纯函数 `applySidecarOwners`（签名见 Step 8.1，实现逻辑）：

```dart
List<Element> applySidecarOwners({
  required List<Element> parsedElements,
  required Map<String, String> aliasToElementId,
  required Map<String, CollaborationCreator> sidecar,
  CollaborationCreator? Function()? localCreatorResolver,
}) {
  final idToAlias = <String, String>{
    for (final entry in aliasToElementId.entries) entry.value: entry.key,
  };
  final resolved = <ElementId, CollaborationCreator?>{};

  // 第一遍：非绑定文字按 alias 决策
  final firstPass = <Element>[
    for (final element in parsedElements)
      _resolveStandalone(element, idToAlias, sidecar, localCreatorResolver, resolved),
  ];

  // 第二遍：绑定文字跟随父（父在前在后均可）
  final byId = <ElementId, Element>{
    for (final element in firstPass) element.id: element,
  };
  return [
    for (final element in firstPass)
      _resolveBoundText(element, byId, resolved),
  ];
}

Element _resolveStandalone(
  Element element,
  Map<String, String> idToAlias,
  Map<String, CollaborationCreator> sidecar,
  CollaborationCreator? Function()? localCreatorResolver,
  Map<ElementId, CollaborationCreator?> resolved,
) {
  if (element.isCanvasPage || element.isPdfBackground) {
    return withoutCreator(element);
  }
  if (element is TextElement && element.containerId != null) {
    return element; // 第二遍处理
  }
  final alias = idToAlias[element.id.value];
  CollaborationCreator? owner;
  if (alias != null && sidecar.containsKey(alias)) {
    owner = sidecar[alias];
  } else {
    owner = localCreatorResolver?.call();
  }
  resolved[element.id] = owner;
  return owner == null ? withoutCreator(element) : withCreator(element, owner);
}

Element _resolveBoundText(
  Element element,
  Map<ElementId, Element> byId,
  Map<ElementId, CollaborationCreator?> resolved,
) {
  final containerId = element is TextElement ? element.containerId : null;
  if (containerId == null) return element;
  final parent = byId[ElementId(containerId)];
  final owner = parent == null ? null : (resolved[parent.id] ?? readCreator(parent));
  return owner == null ? withoutCreator(element) : withCreator(element, owner);
}
```

   b. `_MarkdrawSplitPaneState` 新增字段：`final Map<String, CollaborationCreator> _aliasCreators = {};`

   c. canvas→text（`_syncCanvasToText` L150-159）：`widget.controller.serializeScene()` 改为 `serializeSceneWithAliases()`，并在成功后重建 sidecar：

```dart
final result = widget.controller.serializeSceneWithAliases();
final fullText = result.text;
// ...
_aliasCreators
  ..clear()
  ..addAll({
    for (final entry in result.aliases.entries)
      if (() {
        final element = widget.controller.editorState.scene.getElementById(ElementId(entry.value));
        final creator = element == null ? null : readCreator(element);
        return creator != null;
      }())
        entry.key: readCreator(widget.controller.editorState.scene.getElementById(ElementId(entry.value))!)!,
  });
```

（实现时可先取一次 scene 局部变量消除重复查询；sidecar 只记录有 owner 的 alias。）

   d. text→canvas（`_syncTextToCanvas` L200-248）：重复 alias 检测提取为**文件级公开纯函数**（可单测，v4 §12.5 "duplicate alias 阻止应用"）：

```dart
/// 检测文本中重复出现的 `id=<alias>` 标识。词边界断言防止 `rect1` 误匹配
/// `rect11`（alias 形如 keyword+数字）。返回重复的 alias 列表。
List<String> findDuplicateAliasIds(String text, Map<String, String> aliases) {
  return [
    for (final alias in aliases.keys)
      if (RegExp('id=' + RegExp.escape(alias) + r'(?![0-9A-Za-z_])')
              .allMatches(text)
              .length >
          1)
        alias,
  ];
}
```

在 `DocumentParser.parse(wrapped)` 成功后、`documentToScene` 之前插入：

```dart
final doc = parseResult.value;
final duplicateAliases = findDuplicateAliasIds(wrapped, doc.aliases);
if (duplicateAliases.isNotEmpty) {
  // 受控失败：保留上次成功画布，显示可读错误（v4 §9.1 规则 1）。
  // 复用本文件 L259-263 的既有 SnackBar 范式。
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('文本中存在重复的元素标识：${duplicateAliases.join('、')}，画布保持上次成功状态'),
      duration: const Duration(seconds: 4),
    ),
  );
  _isSyncing = false; // 若外层有同步标志，按既有错误路径的复位方式处理
  return;
}
```

`documentToScene` 之后、`controller.applyScene/replaceScene` 之前应用归属：

```dart
final ownedScene = scene.upsertRemoteElements(
  applySidecarOwners(
    parsedElements: scene.elements,
    aliasToElementId: doc.aliases,
    sidecar: _aliasCreators,
    localCreatorResolver: widget.controller.localCreatorResolver,
  ),
);
```

后续 `applyScene/replaceScene` 改用 `ownedScene`（保持原有的 `replaceScene`/`applyScene` 分支选择逻辑不变）。

- [ ] **Step 8.4：运行测试 + 既有 split pane 回归**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/
```

- [ ] **Step 8.5：format + commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart test/features/whiteboard/editor_core/markdraw_split_pane_sidecar_test.dart
git add lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/editor_core/src/ui/markdraw_split_pane.dart test/features/whiteboard/editor_core/markdraw_split_pane_sidecar_test.dart
git commit -m "fix: 分屏编辑经alias sidecar保留创建者归属并阻断重复标识"
```

---

# Task 9：聚焦目标模型、WhiteboardPage 状态机与顶部 pill

**目标**：none/creator/history 三态本地状态；pill 与退出；生命周期清理；在线名字优先；空态文案；socket→creatorKey 映射 revision。

**上游 spec**：v4 §6.1、§6.4。

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/views/collaboration_focus_target.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（chrome 行加 pill 参数，L1360 区域与 L1380-1391）
- Test: `FlowMuse-App/test/features/whiteboard/views/collaboration_focus_target_test.dart`

**Interfaces:**
- Consumes: Task 4 `_socketCreatorKeys`/`_presenceCreatorRevision`、view model `state.collaborators`。
- Produces:
```dart
// collaboration_focus_target.dart（v4 §6.1 原样）
sealed class CollaborationFocusTarget { const CollaborationFocusTarget(); }
final class CreatorFocus extends CollaborationFocusTarget {
  const CreatorFocus(this.creatorKey, {required this.labelSnapshot, required this.isGuest});
  final String creatorKey; final String labelSnapshot; final bool isGuest;
}
final class HistoricalFocus extends CollaborationFocusTarget { const HistoricalFocus(); }
// WhiteboardPage 私有：CollaborationFocusTarget? _focusTarget;
//                       Map<String, String> _lastKnownCreatorNames;
// MarkdrawEditor 新参数：String? collaborationFocusLabel; VoidCallback? onExitCollaborationFocus;
```

- [ ] **Step 9.1：写失败测试（模型层）**

`test/features/whiteboard/views/collaboration_focus_target_test.dart`（含 Step 9.3.8 追加的源码断言用例，故 import 列表需含 `dart:io`）：

```dart
import 'dart:io';

import 'package:flow_muse/features/whiteboard/views/collaboration_focus_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CreatorFocus 按 creatorKey 值相等比较（禁对象 identity）', () {
    const a = CreatorFocus('user:1', labelSnapshot: '张三', isGuest: false);
    const b = CreatorFocus('user:1', labelSnapshot: '张三改名了', isGuest: false);
    expect(a.creatorKey == b.creatorKey, isTrue); // 判同只看 creatorKey
  });

  test('HistoricalFocus 单例语义', () {
    expect(identical(const HistoricalFocus(), const HistoricalFocus()), isTrue);
  });
}
```

- [ ] **Step 9.2：实现 collaboration_focus_target.dart**

```dart
/// 协作聚焦目标（本机视图态，永不进入 Scene/History/网络）。
/// 判等约定：**消费方**必须按 [CreatorFocus.creatorKey] 字段做值比较
/// （见 WhiteboardPage `_isFocusedOn`），本类刻意不覆写 `==`（避免与
/// labelSnapshot 变化混淆）；禁止依赖对象 identity（v4 §6.1）。
sealed class CollaborationFocusTarget {
  const CollaborationFocusTarget();
}

final class CreatorFocus extends CollaborationFocusTarget {
  const CreatorFocus(
    this.creatorKey, {
    required this.labelSnapshot,
    required this.isGuest,
  });

  final String creatorKey;

  /// 离线回退显示名：在线 presence 出现时持续更新为最后已知在线名，
  /// 离线后回退到该最新快照，不倒退（v4 §6.1）。
  final String labelSnapshot;

  final bool isGuest;
}

final class HistoricalFocus extends CollaborationFocusTarget {
  const HistoricalFocus();
}
```

- [ ] **Step 9.3：WhiteboardPage 状态机**

1. 字段（Task 4 字段旁）：

```dart
CollaborationFocusTarget? _focusTarget;
final Map<String, String> _lastKnownCreatorNames = {}; // creatorKey -> 最后已知在线名
```

2. 核心 API（`_currentCreator` 附近）：

```dart
bool _isFocusedOn(String creatorKey) =>
    _focusTarget is CreatorFocus &&
    (_focusTarget as CreatorFocus).creatorKey == creatorKey;

void _focusCreator(String creatorKey, {required String labelSnapshot, required bool isGuest}) {
  setState(() {
    _focusTarget = CreatorFocus(creatorKey, labelSnapshot: labelSnapshot, isGuest: isGuest);
  });
}

void _focusHistory() {
  setState(() => _focusTarget = const HistoricalFocus());
}

void _exitFocus() {
  if (_focusTarget != null) {
    setState(() => _focusTarget = null);
  }
}

void _toggleCreatorFocus(String creatorKey, {required String labelSnapshot, required bool isGuest}) {
  if (_isFocusedOn(creatorKey)) {
    _exitFocus();
  } else {
    _focusCreator(creatorKey, labelSnapshot: labelSnapshot, isGuest: isGuest);
  }
}
```

3. 在线代表与 pill 文案：

```dart
/// §6.2 代表项选择：active > idle > away，状态相同按 socketId 升序。
CollaboratorPresence? _onlinePresenceFor(String creatorKey) {
  final collaborators = ref.read(whiteboardViewModelProvider).collaborators;
  final candidates = [
    for (final presence in collaborators.values)
      if (presence.creatorKey == creatorKey) presence,
  ]..sort((a, b) {
      int rank(CollaboratorIdleState s) => switch (s) {
            CollaboratorIdleState.active => 0,
            CollaboratorIdleState.idle => 1,
            CollaboratorIdleState.away => 2,
          };
      final byRank = rank(a.idleState).compareTo(rank(b.idleState));
      return byRank != 0 ? byRank : a.socketId.compareTo(b.socketId);
    });
  return candidates.isEmpty ? null : candidates.first;
}

String? _focusPillLabel() {
  final target = _focusTarget;
  if (target == null) return null;
  if (target is HistoricalFocus) {
    return _historyFocusIsEmpty() ? '正在聚焦：历史内容（暂无已提交的历史内容）' : '正在聚焦：历史内容';
  }
  final online = _onlinePresenceFor(target.creatorKey);
  if (online != null) {
    return _creatorFocusIsEmpty(target.creatorKey)
        ? '正在聚焦：${online.username}（该创建者暂无已提交内容）'
        : '正在聚焦：${online.username}';
  }
  final suffix = target.isGuest ? '（历史会话）' : '';
  final base = '正在聚焦：${target.labelSnapshot}$suffix';
  return _creatorFocusIsEmpty(target.creatorKey) ? '$base（该创建者暂无已提交内容）' : base;
}

/// 空态按整个 Scene 的已提交（未删除、非系统）普通元素判断。
bool _creatorFocusIsEmpty(String creatorKey) {
  final scene = _markdrawController.editorState.scene;
  return !scene.activeElements.any((element) =>
      !element.isCanvasPage &&
      !element.isPdfBackground &&
      readCreator(element)?.creatorKey == creatorKey);
}

bool _historyFocusIsEmpty() {
  final scene = _markdrawController.editorState.scene;
  return !scene.activeElements.any((element) =>
      !element.isCanvasPage && !element.isPdfBackground && readCreator(element) == null);
}
```

4. **labelSnapshot 持续刷新**：在 `_handleCollaborationMessage` 中三类 presence 的处理块内（即 Task 4 落地的 `_socketCreatorKeys[socketId] = creatorKey;` 所在 if 块之后）追加：

```dart
final username = message.payload['username'] as String? ?? '';
if (creatorKey != null && username.isNotEmpty) {
  final knownAs = _lastKnownCreatorNames[creatorKey];
  if (knownAs != username) {
    _lastKnownCreatorNames[creatorKey] = username;
    final target = _focusTarget;
    if (target is CreatorFocus &&
        target.creatorKey == creatorKey &&
        target.labelSnapshot != username) {
      setState(() => _focusTarget = CreatorFocus(
            target.creatorKey,
            labelSnapshot: username, // 离线后回退到最新在线名，不倒退
            isGuest: target.isGuest,
          ));
    }
  }
}
```

（该块需要移入 `if (mounted)`/`_runAfterStableFrame` 之外直接同步执行——presence 更新本就在事件流回调内，允许 setState；若 `_handleCollaborationMessage` 运行在非 UI 稳定期，按同文件其他 setState 的既有包裹方式处理。**代表项说明（v4 §6.1）**：`_lastKnownCreatorNames` 记录的是"该 creatorKey 任意 presence 的最后已知名"——重连交叠期可能出现同 key 双 socket 短暂异名，此时**展示层**（pill/属性入口）一律经 `_onlinePresenceFor` 的代表项取名，快照只作为全部离线后的回退，因此不会出现展示混取；快照按时间推进只新不旧，满足"不倒退"。）

5. **生命周期清理**：
   - 与 Task 4 相同的清理函数追加 `_focusTarget = null; _lastKnownCreatorNames.clear();`
   - `initState` 注册 controller 监听（zen/viewMode 清退 + 空态刷新）：

```dart
_markdrawController.addListener(_onControllerNotifyForFocus);
```

```dart
void _onControllerNotifyForFocus() {
  if (!mounted) return;
  if ((_markdrawController.zenMode || _markdrawController.viewMode) && _focusTarget != null) {
    _exitFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出协作者聚焦'), duration: Duration(seconds: 2)),
    );
    return;
  }
  // 聚焦中：目标组内容变化时刷新 pill 空态文案
  if (_focusTarget != null) {
    setState(() {}); // pill 文案在 build 中按 Scene 计算；仅在聚焦期间
    // 付出整页重建成本（未聚焦时本监听零开销），不得在此追加其他工作
  }
}
```

`dispose` 中 `removeListener`。
   
   注意 v4 §6.4：zen/viewMode 清退后**不自动恢复**——`_onControllerNotifyForFocus` 只在从有 focus 变为需清退时动作，退出模式不重建 focus（`_focusTarget` 已为 null，天然满足）。

6. **MarkdrawEditor pill 参数**：`MarkdrawEditor` 新增 `this.collaborationFocusLabel`、`this.onExitCollaborationFocus`（可空）；右上 chrome 行的实际 widget 是 `_RightChrome`（markdraw_editor.dart L1318 起，参数列表 L1319-1342，字段区至 L1365；**注意全文件不存在 `_ChromeRow` 这个类**）——给它加同名字段并在 `_MarkdrawEditorState` 实例化 `_RightChrome` 的位置（L857 附近）透传；build 中 L1388 头像堆叠之后插入：

```dart
if (collaborationFocusLabel != null) ...[
  _StatusPill(label: collaborationFocusLabel!, onTap: onExitCollaborationFocus),
  const SizedBox(width: 8),
],
```

7. **WhiteboardPage build 接线**（L2326 MarkdrawEditor 实例化处）：

```dart
collaborationFocusLabel: _focusPillLabel(),
onExitCollaborationFocus: _exitFocus,
```

8. **focus 纯本地证明测试**（追加到 Task 9.1 测试文件；源码级断言）：

```dart
test('focus 状态不触发 SceneChanged/广播：源码结构断言', () {
  final source = File('lib/features/whiteboard/views/whiteboard_page.dart').readAsStringSync();
  // 用正则截取 _focusCreator 到 _focusHistory 之间的方法体，避免依赖
  // split 顺序的脆弱性
  final match = RegExp(
    r'void _focusCreator\([\s\S]*?\n  \}',
  ).firstMatch(source);
  expect(match, isNotNull, reason: '找不到 _focusCreator 方法');
  final focusBlock = match!.group(0)!;
  expect(focusBlock.contains('broadcast'), isFalse);
  expect(focusBlock.contains('saveScene'), isFalse);
});
```

（结构断言 + Task 15 行为测试双保险。）

- [ ] **Step 9.4：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/views/ test/features/whiteboard/editor_core/
dart format lib/features/whiteboard/views/collaboration_focus_target.dart lib/features/whiteboard/views/whiteboard_page.dart lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart test/features/whiteboard/views/collaboration_focus_target_test.dart
git add lib/features/whiteboard/views/collaboration_focus_target.dart lib/features/whiteboard/views/whiteboard_page.dart lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart test/features/whiteboard/views/collaboration_focus_target_test.dart
git commit -m "feat: 协作者/历史内容本机聚焦状态机与顶部提示"
```

---

# Task 10：属性面板元素入口（创建者/历史内容）

**目标**：单选普通元素时显示归属行与"查看…的内容"动作；桌面与紧凑面板都可用。

**上游 spec**：v4 §6.3。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/property_panel.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/property_panel_content.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/compact_property_panel.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（透传参数 + L989 PropertyPanel 实参）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`（L852 紧凑面板调用透传）
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（resolver 实现 + 传参）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/property_panel_attribution_test.dart`

**Interfaces:**
- Consumes: Task 9 focus API。
- Produces（Dart record，不新增类层级，v4 §6.3）:
```dart
/// PropertyPanel / PropertyPanelContent / showCompactPropertyPanel /
/// MarkdrawEditor / EditorCanvas 的可空命名参数：
({String attributionLabel, String actionLabel, VoidCallback onPressed})? Function(Element element)?
    attributionActionResolver;
```

- [ ] **Step 10.1：写失败测试**

`test/features/whiteboard/editor_core/property_panel_attribution_test.dart`。**实测构造约束**：`PropertyPanelContent` 有 6 个 required 参数（controller/style/elements/isLocked/showFullTextProps/isEditingText），且 `PropertyPanelState.fromElements`（位于 `editor/property_panel_state.dart` L127-132）**直接返回 `ElementStyle`**，没有 `.style` 取值器：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/property_panel_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/property_panel_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('单选元素且 resolver 返回动作时显示归属行；resolver 返回 null 不显示', (tester) async {
    var pressed = 0;
    ({String attributionLabel, String actionLabel, VoidCallback onPressed})? resolver(Element element) {
      return element.id == const ElementId('has-owner')
          ? (attributionLabel: '由 张三 创建', actionLabel: '查看张三的内容', onPressed: () => pressed++)
          : null;
    }

    final element = RectangleElement(id: const ElementId('has-owner'), x: 0, y: 0, width: 10, height: 10);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PropertyPanelContent(
          controller: MarkdrawController(),
          style: PropertyPanelState.fromElements([element]),
          elements: [element],
          isLocked: false,
          showFullTextProps: false,
          isEditingText: false,
          attributionActionResolver: resolver,
        ),
      ),
    ));
    expect(find.text('由 张三 创建'), findsOneWidget);
    expect(find.text('查看张三的内容'), findsOneWidget);
    await tester.tap(find.text('查看张三的内容'));
    await tester.pump();
    expect(pressed, 1);
  });
}
```

（`PropertyPanelContent` 若还有其他 required 参数如 `canvasSize`/`textOnly`，以其实际构造签名为准补齐默认值——以上 6 个是实测必需集。）

- [ ] **Step 10.2：实现面板参数**

1. `PropertyPanelContent`（property_panel_content.dart L17-41）加可空字段 `this.attributionActionResolver`（类型见 Interfaces）。
2. build（L65-91）的非编辑分支 Column 顶部插入归属 section：

```dart
if (elements.length == 1 && attributionActionResolver != null) ...[
  () {
    final action = attributionActionResolver!(elements.first);
    if (action == null) return const SizedBox.shrink();
    return _AttributionSection(
      attributionLabel: action.attributionLabel,
      actionLabel: action.actionLabel,
      onPressed: action.onPressed,
    );
  }(),
],
```

新增私有 widget（同文件底部）：

```dart
class _AttributionSection extends StatelessWidget {
  const _AttributionSection({
    required this.attributionLabel,
    required this.actionLabel,
    required this.onPressed,
  });

  final String attributionLabel;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(attributionLabel, style: Theme.of(context).textTheme.bodySmall)),
          TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.center_focus_strong, size: 16),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
```

3. `PropertyPanel`（property_panel.dart）加同名字段并透传给其内部的 `PropertyPanelContent` 实例化点（property_panel.dart L135 一处；compact 面板的实例化点由下一条单独处理）。
4. `compact_property_panel.dart` 的 `showCompactPropertyPanel(BuildContext, MarkdrawController)` 加可选参数 `({...})? Function(Element)? attributionActionResolver`，透传给内部 `PropertyPanelContent`。
5. `markdraw_editor.dart`：`MarkdrawEditor` 加可空字段 `this.attributionActionResolver`；L989 `PropertyPanel(` 实参追加 `attributionActionResolver: widget.attributionActionResolver`；`EditorCanvas`（L731）实参追加透传。
6. `editor_canvas.dart` L852：`showCompactPropertyPanel(context, controller)` 改为 `showCompactPropertyPanel(context, controller, attributionActionResolver: widget.attributionActionResolver)`；`EditorCanvas` 加同名字段。

- [ ] **Step 10.3：WhiteboardPage resolver**

`_focusPillLabel` 附近：

```dart
/// §6.3 元素入口 resolver：editor_core 不解析 customData，宿主决定文案。
/// 离线回退名用"最后已知在线名"（Task 9 的 _lastKnownCreatorNames，
/// 持续刷新），仅当从未在线过才退到创建时快照（v4 §6.3/§6.1）。
({String attributionLabel, String actionLabel, VoidCallback onPressed})? _attributionFor(
  Element element,
) {
  if (element.isCanvasPage || element.isPdfBackground) return null;
  final creator = readCreator(element);
  if (creator == null) {
    return (
      attributionLabel: '历史内容',
      actionLabel: '查看历史内容',
      onPressed: _focusHistory,
    );
  }
  final online = _onlinePresenceFor(creator.creatorKey);
  final name = online?.username ??
      _lastKnownCreatorNames[creator.creatorKey] ??
      creator.displayName;
  // v4 §6.4：离线游客旧会话的属性入口同样带"（历史会话）"后缀；
  // 同 creatorKey 重新上线后缀消失（online != null 分支自然不带）。
  final suffix = online == null && creator.isGuest ? '（历史会话）' : '';
  return (
    attributionLabel: '由 $name$suffix 创建',
    actionLabel: '查看$name的内容',
    onPressed: () => _toggleCreatorFocus(
      creator.creatorKey,
      labelSnapshot: name,
      isGuest: creator.isGuest,
    ),
  );
}
```

MarkdrawEditor 实例化（L2358 附近）追加：

```dart
attributionActionResolver: _attributionFor,
```

（import：`whiteboard_page.dart` 增加 `canvas_layout.dart` 扩展 getter 所需 import，若尚未引入。）

- [ ] **Step 10.4：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/ test/features/whiteboard/views/
dart format lib/features/whiteboard/editor_core/src/ui/property_panel.dart lib/features/whiteboard/editor_core/src/ui/property_panel_content.dart lib/features/whiteboard/editor_core/src/ui/compact_property_panel.dart lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/property_panel_attribution_test.dart
git add lib/features/whiteboard/editor_core/src/ui/property_panel.dart lib/features/whiteboard/editor_core/src/ui/property_panel_content.dart lib/features/whiteboard/editor_core/src/ui/compact_property_panel.dart lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/property_panel_attribution_test.dart
git commit -m "feat: 属性面板增加创建者归属查看入口"
```

---

# Task 11：参与者头像聚焦交互（badge 扩展、显示层去重、+N 完整列表）

**目标**：头像点击聚焦/退出/切换；旧游客禁用态；creatorKey 显示层去重与代表项；第 6+ 位可聚焦。

**上游 spec**：v4 §6.2。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（badge 类 L168-180、`_ParticipantAvatarStack` L1442-1569、chrome 透传）
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（`_collaborationParticipantBadges` L2565 重写）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/participant_badge_focus_test.dart`

**Interfaces:**
- Consumes: Task 9 `_isFocusedOn`/`_toggleCreatorFocus`、`_onlinePresenceFor`。
- Produces:
```dart
class CollaborationParticipantBadge {
  // 新增可空字段：
  final String? creatorKey;      // null → 禁用聚焦（旧游客）
  final bool focused;            // 当前聚焦于该 creatorKey
  final VoidCallback? onTap;     // null 且 creatorKey==null → 禁用态
}
// _ParticipantAvatarStack：+N overflow 可点击 → showModalBottomSheet 完整列表
```

- [ ] **Step 11.1：写失败测试**

`test/features/whiteboard/editor_core/participant_badge_focus_test.dart`。**实现裁决（不再二选一）**：Task 11.2 将 `_ParticipantAvatarStack` 提升为公开 `ParticipantAvatarStack`（去掉前导下划线并同步 L1389 引用点），测试直接使用它，不引入任何 Harness 类：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('badge 点击触发 onTap；禁用态（无 creatorKey）不触发', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ParticipantAvatarStack(
            participants: [
              CollaborationParticipantBadge(username: 'A', creatorKey: 'user:a', onTap: () => tapped++),
              const CollaborationParticipantBadge(username: '旧游客'),
            ],
          ),
        ),
      ),
    ));
    // A 的头像以 username 文本渲染，find.text('A') 可命中
    expect(find.text('A'), findsWidgets);
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(tapped, 1);

    // 禁用态：旧游客（无 creatorKey、无 onTap）点击无任何效果、不抛异常
    await tester.tap(find.text('旧游客'));
    await tester.pump();
    expect(tapped, 1);
  });
}
```

（`CollaborationParticipantBadge.onTap` 字段在 Step 11.2 才加入——先写本测试，运行确认编译失败即"红"。）

- [ ] **Step 11.2：badge 与 stack 扩展**

1. `CollaborationParticipantBadge`（L168-180）追加字段与构造参数（全部可空/带默认值，向后兼容）：

```dart
final String? creatorKey;
final bool focused;
final VoidCallback? onTap;
```

2. `_ParticipantAvatarStack` → 公开 `ParticipantAvatarStack`（引用点 L1389 同步改名），build 内：
   - `_ParticipantAvatar` 包裹 `Tooltip` + 可点击：`onTap != null` 时用 `InkWell(onTap: participant.onTap, customBorder: const CircleBorder(), child: ...)`；`participant.focused` 时头像外圈加 2px 高亮描边（`Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2)))`）；`creatorKey == null && participant.onTap == null` 时 Tooltip 文案 `'暂不可按归属聚焦'`。
   - `_ParticipantOverflowAvatar` 改为可点击：InkWell → `showModalBottomSheet<void>(context: context, builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [for (final p in participants) ListTile(leading: 头像, title: Text(p.username), subtitle: p.creatorKey == null ? const Text('暂不可按归属聚焦') : null, enabled: p.onTap != null, trailing: p.focused ? const Icon(Icons.check) : null, ...)])))`。列表项点击后先 `Navigator.pop` 再执行 `p.onTap`（避免上下文失效）；**keyless 参与者在完整列表中同样显示禁用态**（`enabled: false` + subtitle '暂不可按归属聚焦'，v4 §6.2）。

3. chrome 透传：无新参数（badge 自带 onTap/focused）。

- [ ] **Step 11.3：WhiteboardPage badges 重写（显示层去重 + 代表项）**

替换 `_collaborationParticipantBadges`（L2565-2578）：

```dart
List<CollaborationParticipantBadge> _collaborationParticipantBadges(
  WhiteboardState state,
  CollaborationIdentity identity,
) {
  final ownCreatorKey = _currentCreatorKey();
  final groups = <String, List<CollaboratorPresence>>{};
  final keyless = <CollaboratorPresence>[];
  for (final presence in state.collaborators.values) {
    final key = presence.creatorKey;
    if (key == null) {
      keyless.add(presence); // 旧游客：仅按 socket 显示，不合并不猜测
      continue;
    }
    if (key == ownCreatorKey) continue; // 当前用户 badge 代表自己的组（含多设备）
    groups.putIfAbsent(key, () => []).add(presence);
  }

  CollaborationParticipantBadge groupBadge(String key, List<CollaboratorPresence> members) {
    final representative = _onlinePresenceFor(key) ?? members.first;
    return CollaborationParticipantBadge(
      username: representative.username,
      avatarUrl: representative.avatarUrl,
      idle: representative.idleState != CollaboratorIdleState.active,
      creatorKey: key,
      focused: _isFocusedOn(key),
      onTap: () => _toggleCreatorFocus(
        key,
        labelSnapshot: representative.username,
        isGuest: representative.isGuest,
      ),
    );
  }

  return [
    CollaborationParticipantBadge(
      username: identity.username,
      avatarUrl: identity.avatarUrl,
      isCurrentUser: true,
      creatorKey: ownCreatorKey,
      focused: ownCreatorKey != null && _isFocusedOn(ownCreatorKey),
      onTap: ownCreatorKey == null
          ? null
          : () => _toggleCreatorFocus(
                ownCreatorKey!,
                labelSnapshot: identity.username,
                isGuest: identity.isGuest,
              ),
    ),
    for (final entry in groups.entries) groupBadge(entry.key, entry.value),
    for (final presence in keyless)
      CollaborationParticipantBadge(
        username: presence.username,
        avatarUrl: presence.avatarUrl,
        idle: presence.idleState != CollaboratorIdleState.active,
        // creatorKey 缺失：显示但禁用按作者聚焦（v4 §6.2）
      ),
  ];
}
```

要点：去重只发生在此显示层；`_socketCreatorKeys` 与 view model 的 `collaborators` map 不删任何 socket（v4 §6.2）。badge 构建读取的是 `_onlinePresenceFor` 的同一代表项，名字/头像不混用其他 Presence。

- [ ] **Step 11.4：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/ test/features/whiteboard/views/
dart format lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/participant_badge_focus_test.dart
git add lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/participant_badge_focus_test.dart
git commit -m "feat: 参与者头像支持按创建者聚焦与完整列表"
```

---

# Task 12：静态画布单遍连续 dim 段渲染

**目标**：原 z 序单遍绘制；非目标连续区段 0.22 合成；无 focus 零新增 saveLayer；Canvas spy 结构化验证。

**上游 spec**：v4 §7.1、§7.2、§7.4。

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/collaboration_focus_alpha.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart`

**Interfaces:**
- Consumes: Task 1 `readCreator`、`canvas_layout.dart` 系统元素 getter。
- Produces:
```dart
// collaboration_focus_alpha.dart
double collaborationFocusAlpha(
  Element element, {
  required String? focusedCreatorKey,
  required bool focusHistoricalContent,
  Set<ElementId> highlightedElementIds = const {},
});
// StaticCanvasPainter 新构造参数：
this.focusedCreatorKey,
this.focusHistoricalContent = false,
this.locallyHighlightedElementIds = const {},
this.localHighlightRevision = 0,
```

- [ ] **Step 12.1：写失败测试**

**先建共享测试工具** `test/features/whiteboard/editor_core/rendering/canvas_spy.dart`（Task 14 的湿墨测试也 import 它）。`Canvas` 是接口，必须显式实现全部抽象成员并转发；下面给出完整实现（flutter 3.x 的 Canvas 成员集，若 SDK 版本差异导致缺成员，按编译器提示补转发即可——转发体不含任何逻辑）：

```dart
import 'dart:ui';

/// test-only Canvas spy：转发真实 Canvas；分开统计几何 draw* 与
/// saveLayer（v4 §7.4），并记录 drawRect 的出现顺序（z 序证据）。
class SpyCanvas implements Canvas {
  SpyCanvas(this._inner);
  final Canvas _inner;

  int saveLayerCount = 0;
  int drawCallCount = 0;
  final List<Rect> rectOrder = [];
  final List<Rect?> saveLayerBounds = [];

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    saveLayerCount++;
    saveLayerBounds.add(bounds);
    _inner.saveLayer(bounds, paint);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    drawCallCount++;
    rectOrder.add(rect);
    _inner.drawRect(rect, paint);
  }

  void _count() => drawCallCount++;

  @override
  void drawPaint(Paint paint) { _count(); _inner.drawPaint(paint); }
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) { _count(); _inner.drawLine(p1, p2, paint); }
  @override
  void drawRRect(RRect rrect, Paint paint) { _count(); _inner.drawRRect(rrect, paint); }
  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) { _count(); _inner.drawDRRect(outer, inner, paint); }
  @override
  void drawOval(Rect rect, Paint paint) { _count(); _inner.drawOval(rect, paint); }
  @override
  void drawCircle(Offset c, double radius, Paint paint) { _count(); _inner.drawCircle(c, radius, paint); }
  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    _count(); _inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }
  @override
  void drawPath(Path path, Paint paint) { _count(); _inner.drawPath(path, paint); }
  @override
  void drawImage(Image image, Offset offset, Paint paint) { _count(); _inner.drawImage(image, offset, paint); }
  @override
  void drawImageRect(Image image, Rect src, Rect dst, Paint paint, {BlendMode? blendMode}) {
    _count(); _inner.drawImageRect(image, src, dst, paint, blendMode: blendMode ?? BlendMode.srcOver);
  }
  @override
  void drawImageNine(Image image, Rect center, Rect dst, Paint paint, {BlendMode? blendMode}) {
    _count(); _inner.drawImageNine(image, center, dst, paint, blendMode: blendMode ?? BlendMode.srcOver);
  }
  @override
  void drawPicture(Picture picture) { _count(); _inner.drawPicture(picture); }
  @override
  void drawParagraph(Paragraph paragraph, Offset offset) { _count(); _inner.drawParagraph(paragraph, offset); }
  @override
  void drawPoints(PointMode pointMode, List<Offset> points, Paint paint) {
    _count(); _inner.drawPoints(pointMode, points, paint);
  }
  @override
  void drawRawPoints(PointMode pointMode, Float32List points, Paint paint) {
    _count(); _inner.drawRawPoints(pointMode, points, paint);
  }
  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    _count(); _inner.drawVertices(vertices, blendMode, paint);
  }
  @override
  void drawAtlas(Image atlas, List<RSTransform> transforms, List<Rect> rects, List<Color>? colors, BlendMode blendMode, Rect? cullRect, Paint paint) {
    _count(); _inner.drawAtlas(atlas, transforms, rects, colors, blendMode, cullRect, paint);
  }
  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
    _count(); _inner.drawShadow(path, color, elevation, transparentOccluder);
  }
  @override
  void drawColor(Color color, BlendMode blendMode) { _count(); _inner.drawColor(color, blendMode); }

  @override
  void save() => _inner.save();
  @override
  void restore() => _inner.restore();
  @override
  int getSaveCount() => _inner.getSaveCount();
  @override
  void translate(double dx, double dy) => _inner.translate(dx, dy);
  @override
  void scale(double sx, [double? sy]) => _inner.scale(sx, sy);
  @override
  void rotate(double radians) => _inner.rotate(radians);
  @override
  void skew(double sx, double sy) => _inner.skew(sx, sy);
  @override
  void transform(Float64List matrix4) => _inner.transform(matrix4);
  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) =>
      _inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => _inner.clipRRect(rrect, doAntiAlias: doAntiAlias);
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => _inner.clipPath(path, doAntiAlias: doAntiAlias);
  @override
  Rect getDestinationClipBounds() => _inner.getDestinationClipBounds();
  @override
  Rect getLocalClipBounds() => _inner.getLocalClipBounds();
}
```

再建测试主体 `test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart`（**注意 `dart:ui` 不加前缀**——正文裸用 Canvas/PictureRecorder；`flutter/rendering.dart` 不导出这些类型；adapter 用 `RoughCanvasAdapter()`，先例见 `test/features/whiteboard/editor_core/pdf_creation_bounds_test.dart` L96）：

```dart
import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';
```

测试主体（同文件）：

```dart
Scene buildScene(List<Element> elements) => elements.fold(Scene(), (s, e) => s.addElement(e));

RectangleElement owned(String id, String key) => withCreator(
      RectangleElement(id: ElementId(id), x: 0, y: 0, width: 10, height: 10),
      CollaborationCreator(creatorKey: key, displayName: key, isGuest: false),
    );

RectangleElement plain(String id) =>
    RectangleElement(id: ElementId(id), x: 0, y: 0, width: 10, height: 10);

StaticCanvasPainter painterFor(
  Scene scene, {
  String? focusedCreatorKey,
  bool history = false,
  Set<ElementId> highlight = const {},
  int revision = 0,
}) =>
    StaticCanvasPainter(
      scene: scene,
      adapter: RoughCanvasAdapter(),
      viewport: const ViewportState(),
      focusedCreatorKey: focusedCreatorKey,
      focusHistoricalContent: history,
      locallyHighlightedElementIds: highlight,
      localHighlightRevision: revision,
    );

void main() {
  test('无 focus：saveLayer = 0，draw-call 数与绘制顺序同基线（z 序证据）', () {
    final scene = buildScene([owned('a', 'user:a'), plain('b'), owned('c', 'user:c')]);
    final baseline = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(baseline, const Size(1000, 1000));
    final focusOff = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(focusOff, const Size(1000, 1000));
    // 纯矩形场景无 frame/箭头标签/pending，基线 saveLayer 必须为 0
    expect(baseline.saveLayerCount, 0);
    expect(focusOff.saveLayerCount, 0, reason: '无 focus 路径零新增 saveLayer');
    expect(focusOff.drawCallCount, baseline.drawCallCount);
    // z 序结构化证据：drawRect 顺序逐一相同
    expect(focusOff.rectOrder, baseline.rectOrder);
    expect(baseline.rectOrder.length, 3);
  });

  test('聚焦不改变绘制顺序：drawRect 顺序与无 focus 完全一致（v4 §7.3）', () {
    final scene = buildScene([owned('a', 'user:a'), plain('b'), owned('c', 'user:a')]);
    final noFocus = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(noFocus, const Size(1000, 1000));
    final focused = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:a').paint(focused, const Size(1000, 1000));
    expect(focused.rectOrder, noFocus.rectOrder,
        reason: '目标元素不得浮到遮挡者上方——绘制顺序不变');
  });

  test('全 dim 且无本地高亮：dim saveLayer = 1', () {
    final scene = buildScene([owned('a', 'user:a'), owned('b', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:other').paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1);
  });

  test('全部目标：dim saveLayer = 0', () {
    final scene = buildScene([owned('a', 'user:a'), owned('b', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:a').paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 0);
  });

  test('交替目标/非目标：saveLayer 数 = 连续 dim 段数（2 段）；元素只画一次', () {
    final scene = buildScene([owned('a', 'user:a'), plain('b'), owned('c', 'user:a'), plain('d')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:a').paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 2);
    // drawCall 数与无 focus 基线一致（每元素最多 render 一次）
    final baseline = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(baseline, const Size(1000, 1000));
    expect(spy.drawCallCount, baseline.drawCallCount);
  });

  test('本地高亮元素全亮并打断 dim 段', () {
    final scene = buildScene([owned('a', 'user:a'), plain('b'), owned('c', 'user:c')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:a', highlight: {const ElementId('b')}).paint(spy, const Size(1000, 1000));
    // a 全亮、b 高亮全亮、c dim → 1 段
    expect(spy.saveLayerCount, 1);
  });

  test('history focus：无 owner 全亮、有 owner 变淡', () {
    final scene = buildScene([plain('old'), owned('new', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, history: true).paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1);
  });

  test('PDF 背景元素始终全亮', () {
    final pdf = RectangleElement(
      id: const ElementId('pdf'), x: 0, y: 0, width: 100, height: 100,
      customData: const {
        'flowMuse': {'pageId': 'p', 'pdfBackground': true},
      },
    );
    final scene = buildScene([pdf, owned('a', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, focusedCreatorKey: 'user:other').paint(spy, const Size(1000, 1000));
    // 只有 a 一个 dim 段；pdf 全亮不参与
    expect(spy.saveLayerCount, 1);
  });

  test('shouldRepaint：focus 标量与（focus 中）revision 触发；无 focus 时仅 revision 变化不触发', () {
    final scene = buildScene([owned('a', 'user:a')]);
    final p0 = painterFor(scene);
    final p1 = painterFor(scene, focusedCreatorKey: 'user:a');
    expect(p0.shouldRepaint(p1), isTrue);

    final f0 = painterFor(scene, focusedCreatorKey: 'user:a', highlight: const {}, revision: 1);
    final f1 = painterFor(scene, focusedCreatorKey: 'user:a', highlight: const {}, revision: 2);
    expect(f0.shouldRepaint(f1), isTrue);

    final n0 = painterFor(scene, revision: 1);
    final n1 = painterFor(scene, revision: 2);
    expect(n0.shouldRepaint(n1), isFalse, reason: '两端都无 focus 时 revision 单独变化不触发重绘');
  });
}
```

（`RoughCanvasAdapter` 经 `rendering/rough/rough.dart` barrel 导出，`const ViewportState()` 使用默认 offset/zoom。）

- [ ] **Step 12.2：运行确认失败**

- [ ] **Step 12.3：实现 collaboration_focus_alpha.dart**

```dart
import '../core/elements/collaboration_element_owner.dart';
import '../core/elements/elements.dart';
import '../core/layout/canvas_layout.dart';

/// v4 §7.1 分类顺序（无 focus → 系统 → 本地高亮 → creator 命中 → history
/// 命中 → 其余 0.22）。静态 painter 与数学 overlay 共用，禁止两处各写一份。
double collaborationFocusAlpha(
  Element element, {
  required String? focusedCreatorKey,
  required bool focusHistoricalContent,
  Set<ElementId> highlightedElementIds = const {},
}) {
  if (focusedCreatorKey == null && !focusHistoricalContent) return 1.0;
  if (element.isCanvasPage || element.isPdfBackground) return 1.0;
  if (highlightedElementIds.contains(element.id)) return 1.0;
  final creator = readCreator(element);
  if (focusedCreatorKey != null) {
    return creator != null && creator.creatorKey == focusedCreatorKey ? 1.0 : 0.22;
  }
  return creator == null ? 1.0 : 0.22;
}
```

- [ ] **Step 12.4：StaticCanvasPainter 实现**

1. 构造参数（L75-92）追加四个（见 Interfaces），`final` 字段同步声明。
2. `_paint` 元素循环（L151-206）改为：

```dart
final focusActive = focusedCreatorKey != null || focusHistoricalContent;
var dimOpen = false;
final dimPaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.22);

for (final element in visible) {
  if (element.isCanvasPage) {
    continue; // 页底在循环前绘制，不参与 dim 机制
  }
  // Skip standalone text that is being edited —— 编辑中的文本由 overlay
  // 全亮绘制；它同时必须打断 dim 段（等价 alpha 1.0）。
  final isEditingSkip = editingElementId != null &&
      element.id == editingElementId &&
      element is core.TextElement;
  if (isEditingSkip) {
    if (dimOpen) {
      canvas.restore();
      dimOpen = false;
    }
    continue;
  }

  final alpha = focusActive
      ? collaborationFocusAlpha(
          element,
          focusedCreatorKey: focusedCreatorKey,
          focusHistoricalContent: focusHistoricalContent,
          highlightedElementIds: locallyHighlightedElementIds,
        )
      : 1.0;
  if (alpha < 1.0 && !dimOpen) {
    canvas.saveLayer(null, dimPaint);
    dimOpen = true;
  } else if (alpha >= 1.0 && dimOpen) {
    canvas.restore();
    dimOpen = false;
  }

  // ↓ 以下 L162-205 原有逻辑原样保留（frame clip save/clip、箭头标签
  //   saveLayer、ElementRenderer.render、_renderBoundText、两次 restore）
}
if (dimOpen) {
  canvas.restore();
}
```

约束（实现自查）：frame clip 与箭头标签的 save/restore 均为单元素内配对，不会被 dim 段的 saveLayer/restore 打乱栈序；previewElement（L209）与 pendingElements（L227）在主循环后全亮，不参与 dim。

3. `shouldRepaint`（L740-757）追加：

```dart
if (oldDelegate.focusedCreatorKey != focusedCreatorKey) return true;
if (oldDelegate.focusHistoricalContent != focusHistoricalContent) return true;
final anyFocus = focusedCreatorKey != null || focusHistoricalContent;
if (anyFocus && oldDelegate.localHighlightRevision != localHighlightRevision) {
  return true;
}
```

- [ ] **Step 12.5：运行测试确认全绿（含既有 rendering 回归）**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/rendering/ test/features/whiteboard/editor_core/
```

- [ ] **Step 12.6：format + commit**

```bash
cd FlowMuse-App
dart format lib/features/whiteboard/editor_core/src/rendering/collaboration_focus_alpha.dart lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart test/features/whiteboard/editor_core/rendering/canvas_spy.dart test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart
git add lib/features/whiteboard/editor_core/src/rendering/collaboration_focus_alpha.dart lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart test/features/whiteboard/editor_core/rendering/canvas_spy.dart test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart
git commit -m "feat: 静态画布按原层级单遍渲染归属聚焦变淡段"
```

---

# Task 13：聚焦参数穿透、本地高亮集合与数学 Overlay

**目标**：WhiteboardPage → MarkdrawEditor → EditorCanvas → Painters 的纯数据通道；EditorCanvas 计算本地高亮集合；数学文字乘 focus alpha。

**上游 spec**：v4 §7.1（前两条）、§8.3、T6 工作项 1/2/5。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（L731 EditorCanvas 实参）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`（构造 L29-36、painter 组装 L305-331/L404-427、`_MathTextOverlay` L519-599）
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`（L2326 实参）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/ui/editor_canvas_focus_test.dart`

**Interfaces:**
- Consumes: Task 12 painter 参数、`collaborationFocusAlpha`；Task 4 `_socketCreatorKeys`/`_presenceCreatorRevision`；Task 9 `_focusTarget`。
- Produces（MarkdrawEditor 与 EditorCanvas 同名可选参数）:
```dart
this.focusedCreatorKey,                 // String?
this.focusHistoricalContent = false,    // bool
this.socketIdCreatorKeys = const {},    // Map<String, String>（只读快照）
this.presenceCreatorRevision = 0,       // int
```

- [ ] **Step 13.1：EditorCanvas 参数与高亮集合**

1. `EditorCanvas` 构造（L29-36）追加上述四参数与字段。
2. `_EditorCanvasState` 新增高亮追踪字段：

```dart
Set<ElementId> _lastHighlightIds = const {};
int _localHighlightRevision = 0;
```

3. build 内（`final paintViewport = _paintViewport();` L291 附近）插入：

```dart
final highlightIds = _computeLocallyHighlightedElementIds();
if (!setEquals(highlightIds, _lastHighlightIds)) {
  _lastHighlightIds = highlightIds;
  _localHighlightRevision++;
}
final immutableHighlightIds = Set.unmodifiable(highlightIds);
```

（`setEquals` 来自 `package:flutter/foundation.dart`。）

```dart
/// §7.1 本地高亮集合：当前选中 + 正在编辑的元素；编辑绑定文字时加入
/// 其父容器/箭头。框选拖动期间元素尚未进入选中集，天然不参与（只有框
/// 选矩形本身全亮，由 InteractiveCanvasPainter 负责）。
Set<ElementId> _computeLocallyHighlightedElementIds() {
  final state = controller.editorState;
  final ids = <ElementId>{...state.selectedIds};
  final editingId = controller.editingTextElementId;
  if (editingId != null) {
    ids.add(editingId);
    final editing = state.scene.getElementById(editingId);
    final containerId = editing is TextElement ? editing.containerId : null;
    if (containerId != null) {
      ids.add(ElementId(containerId));
    }
  }
  return ids;
}
```

4. `StaticCanvasPainter` 实参（L405-427）追加：

```dart
focusedCreatorKey: widget.focusedCreatorKey,
focusHistoricalContent: widget.focusHistoricalContent,
locallyHighlightedElementIds: immutableHighlightIds,
localHighlightRevision: _localHighlightRevision,
```

5. **RemoteWetInkPainter 的四个实参接线不在本任务**——`RemoteWetInkPainter` 的构造参数要到 Task 14 才存在，本任务提前传参会导致编译失败。Task 14 Step 14.2 负责"构造加参 + EditorCanvas L321-328 接线"两件事。

- [ ] **Step 13.2：数学 Overlay**

`_MathTextOverlay`（L519-548）与 `_PositionedMathText`（L550-599）追加参数：

```dart
// _MathTextOverlay 增加字段并透传：
final String? focusedCreatorKey;
final bool focusHistoricalContent;
final Set<ElementId> highlightedElementIds;
```

`_PositionedMathText` build 的颜色行（L563-565）改为：

```dart
final focusAlpha = collaborationFocusAlpha(
  element,
  focusedCreatorKey: focusedCreatorKey,
  focusHistoricalContent: focusHistoricalContent,
  highlightedElementIds: highlightedElementIds,
);
final color = parseColor(element.strokeColor)
    .withValues(alpha: element.opacity * focusAlpha);
```

正在编辑中的数学公式不进 overlay（overlay 收集时已排除正在编辑元素，L527-533 现状保持），编辑态全亮天然成立。**不加** `Opacity` Widget、不套 saveLayer（v4 §8.3）。

- [ ] **Step 13.3：MarkdrawEditor / WhiteboardPage 接线**

1. `MarkdrawEditor` 加四个同名字段；L731 `EditorCanvas(` 实参追加透传（`focusedCreatorKey: widget.focusedCreatorKey, ...`）。
2. `WhiteboardPage` MarkdrawEditor 实例化（L2326 区域）追加：

```dart
focusedCreatorKey: _focusTarget is CreatorFocus ? (_focusTarget as CreatorFocus).creatorKey : null,
focusHistoricalContent: _focusTarget is HistoricalFocus,
socketIdCreatorKeys: Map.unmodifiable(_socketCreatorKeys),
presenceCreatorRevision: _presenceCreatorRevision,
```

- [ ] **Step 13.4：测试**

`test/features/whiteboard/editor_core/ui/editor_canvas_focus_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/collaboration_focus_alpha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = CollaborationCreator(creatorKey: 'user:a', displayName: 'A', isGuest: false);

  test('分类函数：选中/编辑集合命中全亮，绑定文字父在集合中不隐式全亮（只按元素自身 ID 判断）', () {
    final element = withCreator(
      TextElement(id: const ElementId('t1'), x: 0, y: 0, width: 5, height: 5, text: 'x'),
      owner,
    );
    expect(
      collaborationFocusAlpha(element,
          focusedCreatorKey: 'user:b',
          focusHistoricalContent: false,
          highlightedElementIds: const {ElementId('t1')}),
      1.0,
    );
    expect(
      collaborationFocusAlpha(element,
          focusedCreatorKey: 'user:b',
          focusHistoricalContent: false),
      0.22,
    );
  });

  test('无 focus 恒 1.0', () {
    final e = withCreator(RectangleElement(id: const ElementId('r'), x: 0, y: 0, width: 1, height: 1), owner);
    expect(collaborationFocusAlpha(e, focusedCreatorKey: null, focusHistoricalContent: false), 1.0);
  });
}
```

（本任务为参数穿透性重构、不改行为，测试安排在实现之后是刻意的：`collaborationFocusAlpha` 的行为测试即上方两个用例，painter 参数接线的行为由 Task 12 测试回归覆盖。）

- [ ] **Step 13.5：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/ test/features/whiteboard/views/
dart format lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/ui/editor_canvas_focus_test.dart
git add lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart lib/features/whiteboard/views/whiteboard_page.dart test/features/whiteboard/editor_core/ui/editor_canvas_focus_test.dart
git commit -m "feat: 聚焦参数穿透画布层并计算本地高亮集合"
```

---

# Task 14：远端湿墨按创建者分类的临时 alpha 合成

**目标**：senderSocketId → creatorKey → 分类；映射缺失 fail-open 全亮；stroke bounds 临时层不污染几何缓存。

**上游 spec**：v4 §8.1、§8.2。

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`（新增 `kMaxBrushSizeScale` 公开常量）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`（L321-328 RemoteWetInkPainter 实参接线——从 Task 13 移入本任务）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_focus_test.dart`

**Interfaces:**
- Consumes: Task 13 传入的四个参数；`RemoteWetInkRenderCache`/`RemoteWetInkStrokeSnapshot`。
- Produces:
```dart
// RemoteWetInkPainter 新构造参数：
this.focusedCreatorKey, this.focusHistoricalContent = false,
this.socketIdCreatorKeys = const {}, this.presenceCreatorRevision = 0,
// RemoteWetInkRenderCache 新公开方法：
void paintStroke(Canvas canvas, RemoteWetInkStrokeSnapshot snapshot, RoughAdapter adapter);
// paint() 重构为逐 snapshot 调 paintStroke（行为等价）
```

- [ ] **Step 14.1：写失败测试**

`test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_focus_test.dart`。fixture 复用 `remote_wet_ink_painter_test.dart` 文件底部已验证的 `_decoded` 模式（`DecodedLiveInkChunk(senderSocketId:, chunk: LiveInkChunk(strokeId:, startIndex:, points:[LiveInkPoint(x,y,pressure)], style: LiveInkStyle(brushType:, strokeColor:, strokeWidth:, opacity:)))` + `store.apply(...)`），**复制该 helper 到本文件并加 `senderSocketId` 可选参数**；Canvas spy 直接 import Task 12 的 `canvas_spy.dart`（其 `saveLayerBounds` 记录每个 layer 的 bounds）。完整用例：

```dart
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';

DecodedLiveInkChunk _chunk(
  String strokeId,
  String senderSocketId, {
  double strokeWidth = 3,
}) {
  return DecodedLiveInkChunk(
    senderSocketId: senderSocketId,
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: 0,
      points: const [LiveInkPoint(x: 10, y: 10), LiveInkPoint(x: 20, y: 20)],
      style: LiveInkStyle(
        brushType: 'fountainPen',
        strokeColor: '#123456',
        strokeWidth: strokeWidth,
        opacity: 50,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('聚焦下：目标外 stroke 产生 1 个 bounds saveLayer；目标内/未知 sender 全亮 0 层', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() { cache.dispose(); store.dispose(); });
    store.apply(_chunk('x', 's-other'));
    store.apply(_chunk('y', 's-target'));
    store.apply(_chunk('z', 's-unknown'));
    final painter = RemoteWetInkPainter(
      store: store, cache: cache, adapter: RoughCanvasAdapter(), viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {'s-other': 'user:other', 's-target': 'user:a'},
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1, reason: '只有 s-other 的 stroke 被变淡包裹');
    final bounds = spy.saveLayerBounds.single!;
    expect(bounds.width < 1000 || bounds.height < 1000, isTrue, reason: '禁止全屏层');
  });

  test('无聚焦：saveLayer = 0（零新增）', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() { cache.dispose(); store.dispose(); });
    store.apply(_chunk('x', 's-other'));
    final painter = RemoteWetInkPainter(
      store: store, cache: cache, adapter: RoughCanvasAdapter(), viewport: const ViewportState(),
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 0);
  });

  test('粗笔 bounds 余量：highlighter(sizeScale 4.2) 边缘像素不裁切', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() { cache.dispose(); store.dispose(); });
    // highlighter 是 sizeScale 上界（4.2）；粗笔 + 点在 (10,10)-(20,20)
    final chunk = DecodedLiveInkChunk(
      senderSocketId: 's-other',
      chunk: LiveInkChunk(
        strokeId: 'fat',
        startIndex: 0,
        points: const [LiveInkPoint(x: 10, y: 10, pressure: 1.0), LiveInkPoint(x: 20, y: 20, pressure: 1.0)],
        style: const LiveInkStyle(brushType: 'highlighter', strokeColor: '#FFFF00', strokeWidth: 40, opacity: 50),
      ),
    );
    store.apply(chunk);
    final painter = RemoteWetInkPainter(
      store: store, cache: cache, adapter: RoughCanvasAdapter(), viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {'s-other': 'user:other'},
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    final bounds = spy.saveLayerBounds.single!;
    final margin = 40 * 4.2 * 0.5 * 1.3 + 2.0; // 见 Step 14.2 的公式
    expect(bounds.left, lessThanOrEqualTo(10 - 40 * 4.2 * 0.5), reason: '左缘含最大有效线宽半径');
    expect(bounds.right, greaterThanOrEqualTo(20 + 40 * 4.2 * 0.5));
    expect(bounds.width, lessThan(1000));
  });

  test('shouldRepaint：无 focus 时仅 presenceCreatorRevision 变化不触发', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    final cache = RemoteWetInkRenderCache();
    addTearDown(cache.dispose);
    RemoteWetInkPainter painter({int revision = 0}) => RemoteWetInkPainter(
          store: store, cache: cache, adapter: RoughCanvasAdapter(), viewport: const ViewportState(),
          presenceCreatorRevision: revision,
        );
    expect(painter(revision: 1).shouldRepaint(painter(revision: 2)), isFalse,
        reason: '两端都无 focus 时 revision 单独变化不触发重绘');
    RemoteWetInkPainter focusPainter({int revision = 0}) => RemoteWetInkPainter(
          store: store, cache: cache, adapter: RoughCanvasAdapter(), viewport: const ViewportState(),
          focusedCreatorKey: 'user:a', presenceCreatorRevision: revision,
        );
    expect(focusPainter(revision: 1).shouldRepaint(focusPainter(revision: 2)), isTrue);
  });
}
```

（文件头需补 `import 'dart:ui';` 以使用 `Canvas`/`PictureRecorder`；`LiveInkPoint.pressure` 为可空参数——`_chunk` helper 未传即无压感，粗笔用例显式传 `pressure: 1.0`。`DecodedLiveInkChunk` 的 import 来自 `collaboration/models/live_ink_chunk.dart`。`const LiveInkPoint(...)` 若其构造非 const，去掉 const 即可，以该类实际声明为准。）

- [ ] **Step 14.2：实现**

1. `RemoteWetInkRenderCache`：把 `paint`（L84-101）的循环体提取为公开 `paintStroke`，`paint` 变为：

```dart
void paint(Canvas canvas, List<RemoteWetInkStrokeSnapshot> snapshots, RoughAdapter adapter) {
  lastFrameTailPointCount = 0;
  for (final snapshot in snapshots) {
    paintStroke(canvas, snapshot, adapter);
  }
}

/// 单个 stroke 的绘制（含 tail 与簿记）。painter 的聚焦包装在调用侧，
/// 本方法不感知 focus —— 几何缓存 Picture 复用不受 alpha 影响。
void paintStroke(Canvas canvas, RemoteWetInkStrokeSnapshot snapshot, RoughAdapter adapter) {
  final cache = _strokes[snapshot.strokeId];
  cache?.paint(canvas);
  for (final segment in snapshot.tailSegments) {
    lastFrameTailPointCount += segment.points.length;
    _drawSegment(canvas, segment, snapshot, adapter);
  }
  _lastPaintedMaxPointIndex[snapshot.strokeId] = snapshot.maxPointIndex;
  _lastPaintedSnapshots[snapshot.strokeId] = snapshot;
  _markPaintedIndices(snapshot);
}
```

2. `RemoteWetInkPainter`：构造追加四参数；`editor_canvas.dart` 的 `RemoteWetInkPainter` 实参（L321-328）同步接线（Task 13 已在 EditorCanvas 备好 widget 字段）：

```dart
focusedCreatorKey: widget.focusedCreatorKey,
focusHistoricalContent: widget.focusHistoricalContent,
socketIdCreatorKeys: widget.socketIdCreatorKeys,
presenceCreatorRevision: widget.presenceCreatorRevision,
```

`paint`（L144-155）改为：

```dart
@override
void paint(Canvas canvas, Size size) {
  final strokes = store.strokes;
  cache.sync(strokes, adapter);
  if (strokes.isEmpty) return;

  final focusActive = focusedCreatorKey != null || focusHistoricalContent;
  canvas.save();
  canvas.scale(viewport.zoom);
  canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
  _clipToPages(canvas);
  for (final snapshot in strokes) {
    final alpha = focusActive ? _alphaForSnapshot(snapshot) : 1.0;
    if (alpha >= 1.0) {
      cache.paintStroke(canvas, snapshot, adapter);
    } else {
      // §8.2：逐 stroke 临时 alpha 合成，冻结 Picture 几何缓存不受污染。
      // bounds 用实际渲染笔迹包围盒 + 最大有效线宽余量，禁止全屏层。
      canvas.saveLayer(_strokeBounds(snapshot), Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
      cache.paintStroke(canvas, snapshot, adapter);
      canvas.restore();
    }
  }
  canvas.restore();
}

/// §8.1 行为表：映射缺失 fail-open 1.0（宁全亮不错暗）；creator focus
/// 目标外 0.22；history focus 下有主的活动湿墨不属于历史 → 0.22。
double _alphaForSnapshot(RemoteWetInkStrokeSnapshot snapshot) {
  final creatorKey = socketIdCreatorKeys[snapshot.senderSocketId];
  if (creatorKey == null) return 1.0;
  if (focusedCreatorKey != null) {
    return creatorKey == focusedCreatorKey ? 1.0 : 0.22;
  }
  return 0.22;
}

Rect _strokeBounds(RemoteWetInkStrokeSnapshot snapshot) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  void absorb(double x, double y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  void absorbSegmentPoints(Iterable<RemoteWetInkSegment> segments) {
    for (final segment in segments) {
      if (segment.leadingPoint != null) {
        absorb(segment.leadingPoint!.x, segment.leadingPoint!.y);
      }
      for (final point in segment.points) {
        absorb(point.x, point.y);
      }
      if (segment.trailingPoint != null) {
        absorb(segment.trailingPoint!.x, segment.trailingPoint!.y);
      }
    }
  }

  absorbSegmentPoints([
    for (final block in snapshot.frozenBlocks) ...block.segments,
  ]);
  absorbSegmentPoints(snapshot.tailSegments);

  if (minX > maxX || minY > maxY) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  // §8.2 余量按"brush sizeScale 后的最大有效线宽半径"推导：perfect_
  // freehand 的 size 是直径 = strokeWidth × brush.sizeScale（freedraw_
  // renderer.dart L191），最大半径 = strokeWidth × sizeScale / 2。当前
  // 笔型 sizeScale 上界 = highlighter 4.2（freedraw_renderer.dart L304），
  // 再乘 1.3 压感/变粗安全因子 + 2px 抗锯齿边界。禁止退回名义
  // strokeWidth/2（v4 §8.2 明令禁止）。
  final margin = snapshot.style.strokeWidth * kMaxBrushSizeScale * 0.5 * 1.3 + 2.0;
  return Rect.fromLTRB(minX - margin, minY - margin, maxX + margin, maxY + margin);
}
```

其中 `kMaxBrushSizeScale` 为 `freedraw_renderer.dart` 新增的公开常量（放在该文件 `_BrushConfig` 类附近）：

```dart
/// 笔型 sizeScale 上界（highlighter = 4.2），供远端湿墨聚焦层计算
/// bounds 余量。新增笔型若超过该值必须同步上调。
const double kMaxBrushSizeScale = 4.2;
```

（`remote_wet_ink_painter.dart` import `rough/freedraw_renderer.dart` 或经 `rough/rough.dart` barrel；freedraw_renderer 与 painter 同在 rendering 层，无依赖边界问题。）

3. `shouldRepaint`（L171-176）追加：

```dart
if (oldDelegate.focusedCreatorKey != focusedCreatorKey) return true;
if (oldDelegate.focusHistoricalContent != focusHistoricalContent) return true;
final anyFocus = focusedCreatorKey != null || focusHistoricalContent;
if (anyFocus && oldDelegate.presenceCreatorRevision != presenceCreatorRevision) {
  return true;
}
```

（`RemoteWetInkSegment` 的类型名/点字段以 remote_wet_ink_store.dart 实际导出为准——已知 `segment.points`、`leadingPoint`、`trailingPoint`、点带 `x/y/pressure`，被 `_drawSegment` 消费。）

- [ ] **Step 14.3：运行 + format + commit**

```bash
cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/rendering/
dart format lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_focus_test.dart
git add lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_focus_test.dart
git commit -m "feat: 远端湿墨按创建者分类临时合成聚焦透明度"
```

---

# Task 15：双端集成、压力与回归测试收口

**目标**：A/B 双端行为、focus 零网络、1000/5000 结构化压力。

**上游 spec**：v4 §12 全部、§13。

**Files:**
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/collaboration_owner_sync_test.dart`
- Modify: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart`（追加压力用例）

**Interfaces:** Consumes Task 1-14 全部产出；无新生产接口。

- [ ] **Step 15.1：双端集成测试**

新建 `test/features/whiteboard/collaboration/collaboration_owner_sync_test.dart`。脚手架照抄 `collaboration_repository_sync_test.dart` L18-45（单 repository + 裸 peer transport，解密在订阅回调内完成；**不需要第二个 repository**）。完整用例：

```dart
import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ownedElement(String id, String creatorKey, {int version = 1}) {
  return <String, Object?>{
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': 1,
    'index': 'a$id',
    'customData': {
      'flowMuse': {
        'collaborationOwner': {
          'version': 1,
          'creatorKey': creatorKey,
          'displayName': creatorKey,
          'isGuest': false,
        },
      },
    },
  };
}

void main() {
  test('A 广播的元素经加密通道到达 B 且 owner 保留；reconcile 后仍保留', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = ExcalidrawScene.fromJson(const {'elements': []});
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryTransport = MemoryRealtimeTransport(hub: hub, socketId: 'a');
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'b');
    final repository = CollaborationRepository(
      transport: repositoryTransport,
      sceneStore: store,
      crypto: crypto,
    );

    await peerTransport.connect(room.roomId);
    await repository.joinRoom(room: room, localScene: initial);
    final received = <CollaborationMessage>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      received.add(CollaborationMessage.fromBytes(bytes));
    });

    // A 广播带 owner 的元素（等价于 A 创建后经 ChangeAccumulator 发送）
    final owned = _ownedElement('e1', 'user:a', version: 2);
    await repository.broadcastElements(room: room, elements: [owned]);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final elementMessages = received
        .where((m) =>
            m.type == CollaborationMessageType.sceneUpdate ||
            m.type == CollaborationMessageType.sceneInit)
        .toList();
    expect(elementMessages, isNotEmpty);
    expect(elementMessages.first.elements.single['customData'], isNotNull,
        reason: 'owner 随密文正文到达对端（回填语义由 Task 6 reconciler 测试覆盖）');
    await subscription.cancel();
  });

  test('idle presence 携带 creatorKey 且两轮广播（模拟重连前后）键一致', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = ExcalidrawScene.fromJson(const {'elements': []});
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryTransport = MemoryRealtimeTransport(hub: hub, socketId: 'a');
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'b');
    final repository = CollaborationRepository(
      transport: repositoryTransport,
      sceneStore: store,
      crypto: crypto,
    );
    await peerTransport.connect(room.roomId);
    await repository.joinRoom(room: room, localScene: initial);
    final idles = <CollaborationMessage>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      final message = CollaborationMessage.fromBytes(bytes);
      if (message.type == CollaborationMessageType.idleStatus) {
        idles.add(message);
      }
    });

    await repository.broadcastIdleStatus(
      room: room, userState: 'active', username: '张三', creatorKey: 'guest:roomA:uuid-1',
    );
    await repository.broadcastIdleStatus(
      room: room, userState: 'active', username: '张三', creatorKey: 'guest:roomA:uuid-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(idles.length, 2);
    expect(idles.first.payload['creatorKey'], 'guest:roomA:uuid-1');
    expect(idles.last.payload['creatorKey'], idles.first.payload['creatorKey'],
        reason: '同会话重连前后 creatorKey 稳定（v4 §12.2）');
    await subscription.cancel();
  });

  test('focus 不产生网络消息（消息枚举无 focus 相关类型）', () {
    expect(
      CollaborationMessageType.values.map((t) => t.wireName.contains('FOCUS')),
      everyElement(isFalse),
      reason: 'focus 纯本地，永不进入协作协议（v4 §12.2；行为级源码断言见 Task 9）',
    );
  });
}
```

（`ExcalidrawScene.fromJson` 的空场景构造若与上方不符，以 sync test 的 `_scene` helper 实际写法为准照抄；`broadcastElements` 的签名若为位置参数同理。两个核心用例必须完整可运行——它们分别承载 v4 §12.2 的"owner 随密文到达"与"游客重连同键"验收项。）

- [ ] **Step 15.2：压力测试（painter spy）**

在 `static_canvas_painter_focus_test.dart` 追加：

```dart
Scene alternatingScene(int count) {
  var scene = Scene();
  for (var i = 0; i < count; i++) {
    final element = i.isEven
        ? owned('e$i', 'user:a')
        : owned('e$i', 'user:b');
    scene = scene.addElement(element);
  }
  return scene;
}

void stressCase(int count) {
  final scene = alternatingScene(count);
  // 基线（无 focus）：saveLayer 必须为 0
  final baseline = SpyCanvas(Canvas(PictureRecorder()));
  painterFor(scene).paint(baseline, const Size(2000, 2000));
  expect(baseline.saveLayerCount, 0);
  // creator focus 'user:a'：被 dim 的是奇数位（user:b）。每个奇数位元素
  // 被前后偶数位目标元素隔开成独立 dim 段；0..count-1 中奇数索引个数
  // 恒为 count ~/ 2（count 奇偶无关——5001 时为 2500）。
  final focused = SpyCanvas(Canvas(PictureRecorder()));
  painterFor(scene, focusedCreatorKey: 'user:a').paint(focused, const Size(2000, 2000));
  expect(focused.saveLayerCount, count ~/ 2);
  expect(focused.drawCallCount, baseline.drawCallCount, reason: '每元素最多绘制一次');
}

test('1000 元素交替作者', () => stressCase(1000));
test('5000 元素交替作者', () => stressCase(5000), timeout: const Timeout(Duration(minutes: 2)));
test('999 元素交替作者（奇数锁死段数公式）', () => stressCase(999));

test('focus × 跨 owner 多选：高亮打断 dim 段且不增加元素绘制', () {
  final scene = alternatingScene(1000);
  // 高亮奇数位（user:b，即 dim 方向）元素：i % 4 == 1 使约 1/4 的 dim
  // 元素全亮并打断连续段
  final highlight = <ElementId>{
    for (var i = 1; i < 1000; i += 4) ElementId('e$i'),
  };
  final spy = SpyCanvas(Canvas(PictureRecorder()));
  painterFor(scene, focusedCreatorKey: 'user:a', highlight: highlight).paint(spy, const Size(2000, 2000));
  final noHighlight = SpyCanvas(Canvas(PictureRecorder()));
  painterFor(scene, focusedCreatorKey: 'user:a').paint(noHighlight, const Size(2000, 2000));
  expect(spy.saveLayerCount, lessThan(noHighlight.saveLayerCount),
      reason: '高亮移除了部分 dim 元素，段数严格减少');
  expect(spy.drawCallCount, noHighlight.drawCallCount);
});
```

（精确段数断言在 `count ~/ 2` 用例上必须成立——交替序列 dim 段数可解析计算；多选用例用不等式避免脆弱。）

- [ ] **Step 15.3：全量回归 + commit**

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/collaboration test/features/whiteboard/editor_core test/features/whiteboard/views
dart format test/features/whiteboard/collaboration/collaboration_owner_sync_test.dart test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart
git add test/features/whiteboard/collaboration/collaboration_owner_sync_test.dart test/features/whiteboard/editor_core/rendering/static_canvas_painter_focus_test.dart
git commit -m "test: 补齐协作归属双端兼容与结构化压力验收"
```

---

# Task 16：验收门禁执行、ADR 与文档收尾

**目标**：跑全部门禁；登记 ADR；更新需求文档与 Issue 说明。

**上游 spec**：v4 §13、§16、§17。

**Files:**
- Modify: `.agent/decisions.md`（新增 ADR-018）
- Modify: `docs/项目说明/项目需求.md`
- Modify: `docs/研发记录/plans/2026-08-25-issue-8-collaboration-ownership-focus.md`（文末追加实现落地记录段）

- [ ] **Step 16.1：格式门禁（仓库根目录，PowerShell；只约束本分支触碰的 Dart 文件）**

```powershell
$trackedDart = git diff --name-only --diff-filter=ACMRTUXB origin/main -- FlowMuse-App/lib FlowMuse-App/test
$untrackedDart = git ls-files --others --exclude-standard -- FlowMuse-App/lib FlowMuse-App/test
$changedDart = @($trackedDart; $untrackedDart) |
  Where-Object { $_ -and $_.EndsWith('.dart') -and (Test-Path -LiteralPath $_) } |
  Sort-Object -Unique |
  ForEach-Object { (Resolve-Path -LiteralPath $_).Path }
if ($changedDart.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $changedDart
}
```

注意：`$_ -and` 首项空值守卫是 v4 R11 的修复，不得删除（任一侧为 `$null` 时 `@($a; $b)` 会保留 null 导致后续 `EndsWith` 抛错、门禁被跳过）。

- [ ] **Step 16.2：analyze 门禁（machine 格式 multiset 差）**

在 `FlowMuse-App/` 执行 `dart analyze --format=machine > analyze-branch.txt`（基线 42 issues @c40a847：0 error / 17 warning / 25 info；**比对完成后删除 `analyze-branch.txt`**，避免 Task 16.4 的 `git status --short` 出现未跟踪噪声）。比较脚本要求：

1. 反转义 machine 输出的 `file` 字段（`\` 转义）；归一化为相对 `FlowMuse-App/` 的 `/` 分隔路径。
2. 以 `severity|code|file|message` 四元组做 **multiset 计数差**（不是 set、不是总数）：分支相对基线不得出现任何新增条目（error/warning/info 均不得新增）。
3. `dart analyze` 的 exit 2 由比较结果接管，不把"非零"当新增。
4. 诊断的 line/column/length 只用于人工定位，不进门禁键。

（比较脚本落地为一次性 PowerShell/Python 脚本即可，不必入库；若入库放 `.agent/tools/` 并在 ADR-018 中登记一句。）

- [ ] **Step 16.3：测试门禁**

```powershell
cd FlowMuse-App
flutter test test/features/whiteboard/collaboration
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard/views
```

- [ ] **Step 16.4：范围门禁（仓库根目录）**

```powershell
git diff --check
git status --short
git diff -- FlowMuse-Server
git diff -- FlowMuse-App/ohos FlowMuse-App/android FlowMuse-App/ios FlowMuse-App/macos FlowMuse-App/windows FlowMuse-App/web
git diff -- FlowMuse-App/pubspec.yaml
```

预期全部为空 diff（pubspec 零改动）。

- [ ] **Step 16.5：隐私断言（含在 Task 15 测试中的日志扫描如缺则补）**

- 全库 grep：`creatorKey`、`displayName` 不得出现在 `CollaborationDebugLog.write` 的任何调用参数中（reconciler 只写两个计数键）。
- 在 `scene_reconciler_owner_test.dart` 追加：

```dart
test('日志脱敏：owner_repair 只含计数字段', () {
  // CollaborationDebugLog.write 的输出通道是 debugPrint（kDebugMode 下），
  // flutter_test 会把 debugPrint 重定向到 test 输出；用 printLog 捕获或
  // debugPrint = (String? message, {int? wrapWidth}) { captured.add(message ?? ''); }
  // 的方式临时替换后恢复。
  final captured = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => captured.add(message ?? '');
  addTearDown(() => debugPrint = original);
  // 构造一次"双方都非空且不同"的 reconcile 触发 conflict 计数
  SceneReconciler().reconcile(
    localElements: [el('e1', version: 2, nonce: 5, ownerKey: 'user:a')],
    remoteElements: [el('e1', version: 2, nonce: 9, ownerKey: 'user:b')],
  );
  final ownerLogs = captured.where((line) => line.contains('owner_repair')).toList();
  expect(ownerLogs, isNotEmpty);
  for (final line in ownerLogs) {
    expect(RegExp(r'ownerConflictCount=\d+ ownerBackfillCount=\d+').hasMatch(line), isTrue,
        reason: '实际输出形如 [FlowMuseCollab][scene_reconciler][owner_repair] ownerConflictCount=1 ownerBackfillCount=0，计数在方括号外');
    expect(line.contains('user:a'), isFalse);
    expect(line.contains('user:b'), isFalse);
  }
});
```

（`el` helper 复用 Task 6 测试文件中已定义的版本；本用例追加到 `scene_reconciler_owner_test.dart`。）

- [ ] **Step 16.6：ADR-018 与文档**

1. `.agent/decisions.md` 追加（沿用现有 ADR 格式）：

```markdown
## ADR-018 协作创建者元数据经现有加密 presence 可选字段同步

- 状态：已采纳
- 日期：2026-08-XX（实现合入日）
- 背景：Issue #8 需要元素创建者分组视图；游客无稳定 userId，socketId
  重连会变化，若不在加密 payload 中广播稳定 creatorKey，游客头像与湿墨
  无法与重连前元素关联。
- 决策：MOUSE_LOCATION/IDLE_STATUS/USER_VISIBLE_SCENE_BOUNDS 三类消息的
  AES-GCM 正文增加可选 `creatorKey`；不新增消息类型、不改 Socket.IO 事件、
  服务端零改动。归属存于 customData.flowMuse.collaborationOwner（v1 schema），
  仅用于显示，不参与权限。旧客户端忽略新字段；新客户端面对缺字段 presence
  降级（禁用聚焦、湿墨 fail-open）。
- 后果：analyze/format 门禁脚本按 v4 §13 固化（multiset 差 + 空值守卫）。
```

2. `docs/项目说明/项目需求.md`：在协作功能小节追加"协作者归属聚焦"一段（能力描述 + 0.2 不做清单摘要 + 指向两份计划文档）。
3. v4 计划文档文末追加"实现落地记录"：分支、提交序列（附录 B）、门禁结果摘要、真机 Profile 待办（v4 §13 最后一段的人工验证项，合并前完成并回填设备/帧率/dim 段数记录），以及两条**实现裁决登记**：
   - 非协作状态不盖章（activeRoom 为 null 时不写 owner，本地笔记新建元素归"历史内容"）——见 Task 4 Step 4.3 的裁决理由；
   - 远端湿墨 bounds 余量采用 `kMaxBrushSizeScale = 4.2`（highlighter 上界）常量推导，若未来新增更粗笔型需同步上调该常量。

- [ ] **Step 16.7：commit**

```bash
git add .agent/decisions.md docs/
git commit -m "docs: 登记协作归属决策记录与验收说明"
```

---

# 附录 A：验证命令速查（全部任务的公共出口）

| 用途 | 命令（位置） |
|---|---|
| 单任务测试 | `cd FlowMuse-App && flutter test <任务测试文件>` |
| 三个测试目录 | `flutter test test/features/whiteboard/collaboration test/features/whiteboard/editor_core test/features/whiteboard/views` |
| 格式门禁 | 附录见 Task 16.1（PowerShell，仓库根） |
| analyze 门禁 | Task 16.2（machine multiset 差） |
| 范围门禁 | Task 16.4 |

# 附录 B：提交序列 ↔ v4 §15 映射

| 本计划 commit（任务尾） | v4 §15 对应 |
|---|---|
| T1、T2 | 提交 1（元数据与身份键） |
| T3、T4 | 提交 2（加密 presence） |
| T5、T6 | 提交 3（本地编辑与 LWW） |
| T7、T8 | 提交 4（分屏与外部净化） |
| T9、T10、T11 | 提交 5（聚焦交互） |
| T12、T13、T14 | 提交 6（渲染） |
| T15 | 提交 7（测试） |
| T16 | 提交 8（docs） |

任何提交若触碰 `FlowMuse-Server/`、数据库 schema、平台原生目录或引入 CRDT，立即暂停并按 v4 §15 重审范围。

# 附录 C：v4 §16 审查清单 → 本计划任务映射（评审对照用）

| v4 审查项 | 承载任务 |
|---|---|
| 1 onPrepareLocalResult 覆盖与绕过 | T5（14 处收口 + applyResult 顺序） |
| 2 系统元素判定/PDF 全亮 | T5（stamping）、T12（分类函数） |
| 3 登录键跨房间 | T2 |
| 4 游客 presence 补发兼容 | T3、T4 |
| 5 加密正文/服务端零改动 | T3（不改 _send）、T16.4 |
| 6 reconciler 收敛 | T6 |
| 7 creator 非权限 | T1 注释、全局约束 3 |
| 8 单遍 dim 保 z 序/Frame/箭头 | T12 |
| 9 worst-case 证据/无双实现 | T15 压力；fallback 未实现（全局约束 6/11） |
| 10 overlay 行为/revision | T12、T13、T14 |
| 11 sidecar 按 alias/duplicate | T8 |
| 12 内外双入口/绕过审计 | T7（Step 7.6 源码门禁） |
| 13 最终产物验证 | T7 测试 + T15 |
| 14 深合并保键 | T1 测试 |
| 15 focus 完全本地 | T9（源码断言）+ T15 |
| 16 第 6+ 位/禁用态/zen/重进/多设备/空态 | T9、T10、T11 |
| 17 reconciler copy-on-write | T6 测试 |
| 18 format/analyze 门禁 | T16.1/16.2 |
| 19 可删抽象检查 | 各任务接口均为最小面；无 flag/无服务端/无平台代码 |
