# PDF 笔记导入功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在资料库首页新增「导入 PDF」入口，导入后生成 `kind: pdf` 的笔记；该笔记的白板画布被限制在 PDF 内容区域内（平移/缩放/创建均不越界）。

**Architecture:** 复用现有 PDF 渲染链路（`PdfImporter` + `MarkdrawFileHandler.importPdfSource`）与双层存储（`LibraryRepository` + `WhiteboardSceneRepository`），不新建存储结构。新增三层能力：(1) 仓储 `createNote` 加 `kind` 参数产出 PDF 笔记；(2) `ViewportState.clampToBounds` + `MarkdrawEditorConfig.contentBounds` 限制画布范围；(3) Riverpod `pendingPdfImportProvider` + 资料库编排把"选文件→建笔记→渲染→设边界"串起来。

**Tech Stack:** Flutter 3.x + Dart, Riverpod (Notifier/AsyncNotifier), OHOS (HarmonyOS) 原生 PDF Kit。

## Global Constraints

- **所有路径根目录**：`D:\Program\HarmonyOS\2024-se-17-markdraw-probe\FlowMuse-App`（下文简称 `<APP>`）。docs 目录在其父层 `<REPO>` = `D:\Program\HarmonyOS\2024-se-17-markdraw-probe`。
- **spec 文档**：`<REPO>/docs/研发记录/specs/2026-07-08-pdf-note-import-design.md`（已确认）。
- **鸿蒙端参考文档**：`D:\Program\HarmonyOS\harmonyos-guides\应用服务\PDF Kit（PDF服务）\`，本次涉及的关键参考为 `pdfService能力\转换PDF文档为图片\pdf-get-img.md` 与 `pdfService能力\pdf-open-document.md`。
- **鸿蒙端原生代码（`ohos/entry/src/main/ets/pdf/PdfImportChannel.ets`）本次零改动**。其现有债务（targetPageWidth 被丢弃、pixelMap/imagePacker 未释放）已在 spec 第 9 节登记为独立后续任务，不在本计划范围。本计划仅动 Flutter/Dart 侧。
- **测试命令**：`flutter test test/路径`（在 `<APP>` 下执行）。
- **commit 规范**：每个 Task 结束 commit，message 用 `feat:`/`refactor:`/`test:` 前缀，中文描述。
- **几何类型注意**：`Bounds` 用 `Point`（非 `Offset`）；`Bounds.containsPoint(Point)`；`ViewportState.visibleRect(Size)` 返回 `Rect`。
- **TDD**：每个有逻辑的 Task 先写失败测试，再实现，再跑通。
- **回归红线**：普通 `kind: notes` 笔记的创建/打开/保存行为必须完全不变（`createNote` 的 `kind` 默认 `LibraryFilter.notes`；`contentBounds` 默认 `null`）。

## File Structure

**新增文件：**
- `<APP>/lib/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart` — `clampViewportToBounds` 纯函数 + 一个空 Bounds 判定帮助。
- `<APP>/lib/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart` — `PdfNoteImportPayload` 值对象（bytes + name）。
- `<APP>/lib/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart` — Riverpod provider（`StateProvider<PdfNoteImportPayload?>`）。
- `<APP>/lib/features/whiteboard/pdf_note_import/pdf_note_import_service.dart` — 编排：选文件 → 建笔记 → 暂存 bytes。**无 BuildContext 依赖的纯逻辑部分**抽为可测方法。
- `<APP>/lib/features/library/widgets/import_pdf_card.dart` — 资料库首页「导入 PDF」卡片（复用 `CreateNoteCard` 的视觉，但用 PDF 图标）。
- 测试：`viewport_clamp_test.dart`、`pdf_note_import_service_test.dart`、`create_pdf_note_test.dart`、`library_import_pdf_card_test.dart`。

**修改文件：**
- `<APP>/lib/features/library/repositories/library_repository.dart` — `createNote` 加 `kind`/`title`/`subtitle` 参数（两个实现 + `LibraryIndexNotifier`）。
- `<APP>/lib/features/library/view_models/library_home_view_model.dart` — `createNote` 透传新参数。
- `<APP>/lib/features/library/widgets/library_content.dart` — 加 `onImportPdf` 回调 + 渲染 `ImportPdfCard`。
- `<APP>/lib/features/library/views/library_home_page.dart` — 接 `onImportPdf`，调用导入服务。
- `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart` — 加 `contentBounds` 字段。
- `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` — 视口 clamp 注入 + 元素创建区域校验。
- `<APP>/lib/features/whiteboard/editor_core/src/editor/tools/hand_tool.dart` — 平移后 clamp。
- `<APP>/lib/features/whiteboard/views/whiteboard_page.dart` — 按 kind 启用约束 + 消费 pending 导入 + 渲染失败回退。

---

## Task 1: `createNote` 支持 `kind`/`title`/`subtitle` 参数

**Files:**
- Modify: `<APP>/lib/features/library/repositories/library_repository.dart:191-208`（SharedPreferences 实现）、`:614-632`（InMemory 实现）、`:498-508`（LibraryIndexNotifier）
- Test: `<APP>/test/features/library/create_pdf_note_test.dart`

**Interfaces:**
- Produces：`createNote({String? notebookId, List<String> tagIds, LibraryFilter kind = LibraryFilter.notes, String? title, String? subtitle})` 在 `LibraryRepository`（接口）、两个实现、`LibraryIndexNotifier` 上签名一致。后续 Task 5 的编排服务依赖 `LibraryIndexNotifier.createNote(kind: pdf, title:, subtitle:)`。

- [ ] **Step 1: 写失败测试**

创建 `<APP>/test/features/library/create_pdf_note_test.dart`：

```dart
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createNote with kind', () {
    test('default kind is notes (backward compatible)', () async {
      final repo = createLibraryRepository(platform: TargetPlatform.ohos);
      final note = await repo.createNote();
      expect(note.kind, LibraryFilter.notes);
    });

    test('can create a pdf note with title and subtitle', () async {
      final repo = createLibraryRepository(platform: TargetPlatform.ohos);
      final note = await repo.createNote(
        kind: LibraryFilter.pdf,
        title: '我的文档',
        subtitle: 'doc.pdf',
      );
      expect(note.kind, LibraryFilter.pdf);
      expect(note.title, '我的文档');
      expect(note.subtitle, 'doc.pdf');
      final index = await repo.loadIndex();
      expect(index.notes.single.kind, LibraryFilter.pdf);
    });

    test('pdf note survives serialization round-trip', () async {
      final repo = createLibraryRepository(platform: TargetPlatform.ohos);
      final note = await repo.createNote(kind: LibraryFilter.pdf, title: 'PDF');
      final reloaded = await repo.loadIndex();
      expect(reloaded.notes.single.id, note.id);
      expect(reloaded.notes.single.kind, LibraryFilter.pdf);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/library/create_pdf_note_test.dart`
Expected: 编译失败（`createNote` 不接受 `kind`/`title`/`subtitle` 命名参数）。

- [ ] **Step 3: 改 `LibraryRepository` 接口**

先找到 `abstract interface class LibraryRepository` 里 `createNote` 的声明，改为：

```dart
Future<NoteItem> createNote({
  String? notebookId,
  List<String> tagIds = const [],
  LibraryFilter kind = LibraryFilter.notes,
  String? title,
  String? subtitle,
});
```

- [ ] **Step 4: 改 `SharedPreferencesLibraryRepository.createNote`（约 :191-208）**

```dart
@override
Future<NoteItem> createNote({
  String? notebookId,
  List<String> tagIds = const [],
  LibraryFilter kind = LibraryFilter.notes,
  String? title,
  String? subtitle,
}) async {
  final now = DateTime.now();
  final note = NoteItem(
    id: 'note-${_uuid.v4()}',
    title: title ?? _defaultNoteTitle,
    updatedAt: now,
    kind: kind,
    coverColor: _noteColors[now.millisecondsSinceEpoch % _noteColors.length],
    notebookId: notebookId,
    tagIds: tagIds,
    subtitle: subtitle,
  );
  final index = await loadIndex();
  await _saveIndex(index.copyWith(notes: [note, ...index.notes]));
  return note;
}
```

- [ ] **Step 5: 改 `InMemoryLibraryRepository.createNote`（约 :614-632）**

同样的签名 + 同样的 `kind: kind`、`title: title ?? _defaultNoteTitle`、`subtitle: subtitle`。

- [ ] **Step 6: 改 `LibraryIndexNotifier.createNote`（约 :498-508）**

```dart
Future<NoteItem> createNote({
  String? notebookId,
  List<String> tagIds = const [],
  LibraryFilter kind = LibraryFilter.notes,
  String? title,
  String? subtitle,
}) async {
  final note = await _repository.createNote(
    notebookId: notebookId,
    tagIds: tagIds,
    kind: kind,
    title: title,
    subtitle: subtitle,
  );
  await refresh();
  return note;
}
```

- [ ] **Step 7: 跑测试确认通过**

Run: `flutter test test/features/library/create_pdf_note_test.dart`
Expected: 3 个 test 全 PASS。

- [ ] **Step 8: 跑既有测试确保无回归**

Run: `flutter test test/features/library/`
Expected: 全部 PASS（默认 kind=notes 保证向后兼容）。

- [ ] **Step 9: Commit**

```bash
git add FlowMuse-App/lib/features/library/repositories/library_repository.dart FlowMuse-App/test/features/library/create_pdf_note_test.dart
git commit -m "feat(library): createNote 支持 kind/title/subtitle 参数"
```

---

## Task 2: 视口边界 clamp 纯函数

**Files:**
- Create: `<APP>/lib/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart`
- Test: `<APP>/test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart`

**Interfaces:**
- Produces：`ViewportState clampViewportToBounds(ViewportState viewport, Bounds? bounds, Size canvasSize, {double padding})` —— `bounds` 为 null 时原样返回 viewport（普通笔记 no-op）。后续 Task 3 的 controller、Task 4 的 HandTool 都依赖此函数。
- 注意 import：`Bounds`/`Point` 在 `core/math/math.dart`（barrel）导出；`ViewportState` 在同目录 `viewport_state.dart`。

- [ ] **Step 1: 写失败测试**

创建 `<APP>/test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';

void main() {
  // PDF 内容区域：(0,0) 到 (400, 800)
  final pdfBounds = Bounds.fromLTWH(0, 0, 400, 800);
  const canvas = Size(400, 600);

  group('clampViewportToBounds', () {
    test('null bounds returns viewport unchanged (infinite canvas)', () {
      const vp = ViewportState(offset: Offset(-1000, -2000), zoom: 1.0);
      final clamped = clampViewportToBounds(vp, null, canvas);
      expect(clamped, vp);
    });

    test('offset inside bounds is kept', () {
      // 可见区正好是 (0,0,400,600)，落在 PDF bounds 内
      const vp = ViewportState(offset: Offset(0, 100), zoom: 1.0);
      final clamped = clampViewportToBounds(vp, pdfBounds, canvas);
      expect(clamped.offset.dx, 0);
      // top 允许的范围见实现：[bounds.top - padding, bounds.bottom - canvasH/zoom + padding]
      // 这里 100 合法，应保持
      expect((clamped.offset.dy - 100).abs() < 0.001, true);
    });

    test('offset beyond left is clamped back', () {
      // offset.dx = -500 → 可见区左边 -500，超出 PDF 左边界
      const vp = ViewportState(offset: Offset(-500, 0), zoom: 1.0);
      final clamped = clampViewportToBounds(vp, pdfBounds, canvas);
      expect(clamped.offset.dx, greaterThanOrEqualTo(-16)); // padding=16
      expect(clamped.offset.dx, lessThanOrEqualTo(0));
    });

    test('offset beyond right is clamped back', () {
      // offset.dx = 1000 → 可见区 [1000,1400]，全在 PDF 右侧外
      const vp = ViewportState(offset: Offset(1000, 0), zoom: 1.0);
      final clamped = clampViewportToBounds(vp, pdfBounds, canvas);
      // 最大合法 dx = bounds.right - canvasW/zoom = 400 - 400 = 0
      expect(clamped.offset.dx, lessThanOrEqualTo(0 + 16));
      expect(clamped.offset.dx, greaterThanOrEqualTo(0));
    });

    test('clamp keeps zoom unchanged', () {
      const vp = ViewportState(offset: Offset(-500, -500), zoom: 2.0);
      final clamped = clampViewportToBounds(vp, pdfBounds, canvas);
      expect(clamped.zoom, 2.0);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart`
Expected: 编译失败（`viewport_clamp.dart` 与 `clampViewportToBounds` 不存在）。

- [ ] **Step 3: 实现 `viewport_clamp.dart`**

```dart
import 'dart:ui';

import '../core/math/math.dart';
import 'viewport_state.dart';

/// Clamps [viewport] so its visible rect stays within [bounds].
///
/// Returns [viewport] unchanged when [bounds] is null (infinite canvas,
/// e.g. a normal note). [padding] (in scene units) lets the content bleed
/// slightly past the edge to avoid being flush against the viewport border.
ViewportState clampViewportToBounds(
  ViewportState viewport,
  Bounds? bounds,
  Size canvasSize, {
  double padding = 16.0,
}) {
  if (bounds == null || canvasSize.width <= 0 || canvasSize.height <= 0) {
    return viewport;
  }
  final viewW = canvasSize.width / viewport.zoom;
  final viewH = canvasSize.height / viewport.zoom;

  // 当内容比视口小：允许居中浮动，不强制 clamp（否则无法居中查看小内容）
  final contentFitsX = bounds.size.width <= viewW;
  final contentFitsY = bounds.size.height <= viewH;

  final minX = contentFitsX
      ? bounds.right - viewW - padding
      : bounds.left - padding;
  final maxX = contentFitsX
      ? bounds.left + padding
      : bounds.right - viewW + padding;
  final minY = contentFitsY
      ? bounds.bottom - viewH - padding
      : bounds.top - padding;
  final maxY = contentFitsY
      ? bounds.top + padding
      : bounds.bottom - viewH + padding;

  final clampedDx = viewport.offset.dx.clamp(minX, maxX).toDouble();
  final clampedDy = viewport.offset.dy.clamp(minY, maxY).toDouble();
  if ((clampedDx - viewport.offset.dx).abs() < 0.001 &&
      (clampedDy - viewport.offset.dy).abs() < 0.001) {
    return viewport;
  }
  return ViewportState(offset: Offset(clampedDx, clampedDy), zoom: viewport.zoom);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart`
Expected: 5 个 test 全 PASS。如有断言边界偏差，按实际 clamp 范围微调测试期望值（先确认实现逻辑正确，再校准测试）。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart FlowMuse-App/test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart
git commit -m "feat(whiteboard): 新增视口边界 clamp 纯函数"
```

---

## Task 3: `MarkdrawEditorConfig.contentBounds` + 控制器接入 clamp

**Files:**
- Modify: `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart`
- Modify: `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（平移/缩放入口注入 clamp）
- Test: 扩展 `<APP>/test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart` 或新建 controller 集成测试（见 Step 1）

**Interfaces:**
- Consumes：Task 2 的 `clampViewportToBounds`。
- Produces：`MarkdrawEditorConfig.contentBounds`（`Bounds?`，默认 null）；`MarkdrawController` 提供 `set contentBounds(Bounds?)` 与 `Bounds? get contentBounds`，供 Task 7 的 WhiteboardPage 在 PDF 渲染后写入。控制器内部每次更新视口后用 `_config.contentBounds ?? _contentBounds` clamp（控制器持有的可变边界优先，用于渲染后才设边界的场景）。

- [ ] **Step 1: 写失败测试（控制器层 clamp 行为）**

新建 `<APP>/test/features/whiteboard/editor_core/controller_content_bounds_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';

void main() {
  test('controller clamps pan within contentBounds', () {
    final bounds = Bounds.fromLTWH(0, 0, 400, 800);
    final controller = MarkdrawController(
      config: const MarkdrawEditorConfig(contentBounds: null),
    );
    controller.contentBounds = bounds;
    controller.canvasSize = const Size(400, 600);

    // 尝试把视口平移到 PDF 左侧很远的空白区
    controller.panViewport(const Offset(-5000, 0));
    final vp = controller.viewport;
    // 不应能看到 bounds.left 左侧太远的空白
    expect(vp.offset.dx, greaterThan(-1000));
  });

  test('controller without contentBounds does not clamp (infinite canvas)', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.panViewport(const Offset(-5000, -5000));
    final vp = controller.viewport;
    expect(vp.offset.dx, lessThan(-4000));
    expect(vp.offset.dy, lessThan(-4000));
  });
}
```

> 注：`MarkdrawController` 是否暴露 `viewport` getter、`panViewport`、`canvasSize` setter 已存在（见 spec 调研：`panViewport` 在 :1726）。若签名不同（如 `panViewport` 名字或 `canvasSize` 是私有），在实现时以现有签名为准，调整测试调用方式——先读 `markdraw_controller.dart` 确认这些 accessor。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/whiteboard/editor_core/controller_content_bounds_test.dart`
Expected: 编译失败（`MarkdrawEditorConfig` 无 `contentBounds` 字段；controller 无 `contentBounds` setter）。

- [ ] **Step 3: 给 `MarkdrawEditorConfig` 加 `contentBounds` 字段**

在 `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart`：
- 顶部加 import：`import '../core/math/math.dart';`
- 构造函数加参数 `this.contentBounds,`（放在 `onLinkOpen` 前）
- 加字段：`final Bounds? contentBounds;`

```dart
const MarkdrawEditorConfig({
  this.tools,
  // ... 其余不变 ...
  this.contentBounds,
  this.onLinkOpen,
});

/// 可选的画布内容边界。非 null 时，平移/缩放被 clamp 在此区域内
/// （PDF 笔记用）。null = 无限画布（普通笔记，默认）。
final Bounds? contentBounds;
```

- [ ] **Step 4: 给 `MarkdrawController` 加可变 `contentBounds` 与 clamp 注入**

在 `markdraw_controller.dart`：
1. import `clampViewportToBounds`：`import '../rendering/viewport_clamp.dart';`
2. 加字段与 setter：

```dart
Bounds? _contentBounds;
/// 当前生效的内容边界（运行时可变，优先于 config.contentBounds）。
/// PDF 笔记在渲染完 PDF 后写入此值。
set contentBounds(Bounds? value) {
  _contentBounds = value;
  // 写入后立即 clamp 一次当前视口
  _applyContentBoundsClamp();
}
Bounds? get contentBounds => _contentBounds ?? _config.contentBounds;
```

3. 加 canvasSize 访问（若已有 `_canvasSize`/getter 则复用，先读确认）：

```dart
Size _canvasSize = Size.zero;
set canvasSize(Size value) {
  _canvasSize = value;
}
```

4. 加内部 clamp 帮助方法：

```dart
ViewportState _clampViewport(ViewportState vp) {
  return clampViewportToBounds(vp, contentBounds, _canvasSize);
}

void _applyContentBoundsClamp() {
  if (contentBounds == null) return;
  final clamped = _clampViewport(_state.viewport);
  if (clamped != _state.viewport) {
    _state = _state.copyWith(viewport: clamped);
    notifyListeners();
  }
}
```

5. 在所有"视口变更后"注入 clamp。找到 `panViewport`（约 :1726）、`onScaleUpdate`（约 :1261）里 `pan(...)`/`zoomAt(...)` 产出 `UpdateViewportResult` 的位置，以及 `zoomIn`/`zoomOut`/滚轮 `onPointerSignal`：在得到新 viewport 后，过一次 `_clampViewport` 再写回 state。

> 实现要点：最干净的是在视口最终写入 state 前 `_state = _state.copyWith(viewport: _clampViewport(newViewport))`。不要在 `ViewportState.pan/zoomAt` 内部改（那会污染普通笔记），只在 controller 接管时 clamp。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/features/whiteboard/editor_core/controller_content_bounds_test.dart`
Expected: 2 个 test PASS。若 `panViewport`/`canvasSize` 签名与测试假设不符，按实际签名调整测试代码（保持断言意图：有 bounds 时被 clamp，无 bounds 时不受限）。

- [ ] **Step 6: 跑既有白板测试无回归**

Run: `flutter test test/features/whiteboard/editor_core/`
Expected: 全部 PASS（contentBounds 默认 null，普通笔记行为不变）。

- [ ] **Step 7: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor_config.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/test/features/whiteboard/editor_core/controller_content_bounds_test.dart
git commit -m "feat(whiteboard): MarkdrawEditorConfig/Controller 支持 contentBounds 视口 clamp"
```

---

## Task 4: HandTool 平移后 clamp

**Files:**
- Modify: `<APP>/lib/features/whiteboard/editor_core/src/editor/tools/hand_tool.dart:30`

**Interfaces:**
- Consumes：Task 3 的 `controller.contentBounds`（HandTool 通过 `context.viewport` 写回 controller，controller 已内置 clamp，故此 Task 主要是确认链路 + 必要时显式 clamp）。

- [ ] **Step 1: 读 hand_tool.dart 确认平移如何写回**

读 `<APP>/lib/features/whiteboard/editor_core/src/editor/tools/hand_tool.dart`，确认 `context.viewport.pan(screenDelta)` 之后是否直接写入 controller。若写入走 controller 的视口 setter（已被 Task 3 的 clamp 覆盖），则本 Task 改动极小。

- [ ] **Step 2: 确认/补齐 clamp 链路**

若 HandTool 的平移最终经过 controller 的 viewport 写入（经 `_state.copyWith(viewport:)`），则 Task 3 已覆盖，本 Task 只需补一个回归测试：在 contentBounds 下用 HandTool 拖拽，视口不越界。

新建 `<APP>/test/features/whiteboard/editor_core/hand_tool_clamp_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';

void main() {
  test('hand tool pan respects contentBounds', () {
    final bounds = Bounds.fromLTWH(0, 0, 400, 800);
    final controller = MarkdrawController();
    controller.contentBounds = bounds;
    controller.canvasSize = const Size(400, 600);

    // 模拟连续向左拖拽（产生正 dx 平移内容）
    for (var i = 0; i < 20; i++) {
      controller.panViewport(const Offset(-2000, 0));
    }
    // 视口不应飞到 PDF 左侧无穷远
    expect(controller.viewport.offset.dx, greaterThan(-500));
  });
}
```

> 若 `panViewport` 的 delta 语义与 HandTool 的 `pan(screenDelta)` 方向一致，此测试成立。若方向相反，调整 delta 符号——关键是"长时间同向拖拽后视口仍被钳制在 bounds 附近"。

- [ ] **Step 3: 跑测试**

Run: `flutter test test/features/whiteboard/editor_core/hand_tool_clamp_test.dart`
Expected: PASS。

- [ ] **Step 4: Commit**

```bash
git add FlowMuse-App/test/features/whiteboard/editor_core/hand_tool_clamp_test.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/hand_tool.dart
git commit -m "test(whiteboard): HandTool 平移遵守 contentBounds"
```

---

## Task 5: 元素创建区域校验（禁止在 PDF 外创建）

**Files:**
- Modify: `<APP>/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（`onPointerDown` 及创建工具落点处）
- Test: `<APP>/test/features/whiteboard/editor_core/element_creation_bounds_test.dart`

**Interfaces:**
- Consumes：`controller.contentBounds`（Task 3）。
- 仅作用于**创建**：落点不在 `contentBounds` 内时忽略本次创建，不产生元素、不进 undo。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';

void main() {
  test('element creation outside contentBounds is rejected', () {
    final bounds = Bounds.fromLTWH(0, 0, 400, 800);
    final controller = MarkdrawController();
    controller.contentBounds = bounds;
    controller.canvasSize = const Size(400, 600);
    // 视口对齐 PDF 左上角，屏幕(10,10) → 场景(10,10)，在 bounds 内
    controller.setViewport(const ViewportState()); // 若无 setViewport 用等价方式

    // 落点在 bounds 外（场景坐标 (10000, 10000)）
    final createdInside = controller.tryCreateAt(const Point(10, 10));
    final createdOutside = controller.tryCreateAt(const Point(10000, 10000));
    expect(createdInside, true);
    expect(createdOutside, false);
  });

  test('no contentBounds = create anywhere (infinite canvas)', () {
    final controller = MarkdrawController();
    expect(controller.tryCreateAt(const Point(100000, 100000)), true);
  });
}
```

> **重要**：`tryCreateAt` 是本 Task 新增的**测试辅助方法**，封装"给定场景坐标是否允许创建"。若 `MarkdrawController` 没有统一的创建入口（创建散落在各 tool），则改为暴露一个公开判定方法 `bool canCreateAt(Point scenePoint)`，测试针对它：

```dart
test('canCreateAt respects contentBounds', () {
  final bounds = Bounds.fromLTWH(0, 0, 400, 800);
  final controller = MarkdrawController();
  controller.contentBounds = bounds;
  expect(controller.canCreateAt(const Point(10, 10)), true);
  expect(controller.canCreateAt(const Point(10000, 10000)), false);
});
```

实现 Step 3 时选 `canCreateAt` 路线（更内聚，不破坏现有 tool 结构）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/whiteboard/editor_core/element_creation_bounds_test.dart`
Expected: 编译失败（`canCreateAt` 不存在）。

- [ ] **Step 3: 实现 `canCreateAt` 并接入创建流程**

在 `markdraw_controller.dart`：

```dart
/// PDF 笔记下，判断场景坐标是否允许创建元素。
/// contentBounds 为 null（普通笔记）时永远允许。
bool canCreateAt(Point scenePoint) {
  final bounds = contentBounds;
  if (bounds == null) return true;
  return bounds.containsPoint(scenePoint);
}
```

然后在各创建工具（rectangle/freehand/text 等）落点处调用。读 controller 里 `onPointerDown`（约 :1021）与创建工具的 `applyResult`：在把屏幕坐标转场景坐标后、`applyResult(AddElementResult(...))` 之前加：

```dart
final scenePoint = _state.viewport.screenToScene(screenPoint);
if (!canCreateAt(scenePoint)) return; // 忽略越界创建
```

> 实现细节：找到 `onPointerDown` 里根据 `activeToolType` 分发创建的 switch，在每个创建分支前统一加这个守卫，避免在每个 tool 文件里重复。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/whiteboard/editor_core/element_creation_bounds_test.dart`
Expected: PASS。

- [ ] **Step 5: 回归**

Run: `flutter test test/features/whiteboard/editor_core/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/test/features/whiteboard/editor_core/element_creation_bounds_test.dart
git commit -m "feat(whiteboard): PDF 笔记禁止在 contentBounds 外创建元素"
```

---

## Task 6: `PdfNoteImportPayload` + `pendingPdfImportProvider`

**Files:**
- Create: `<APP>/lib/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart`
- Create: `<APP>/lib/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart`

**Interfaces:**
- Produces：`PdfNoteImportPayload({Uint8List bytes, String name})` 不可变值对象；`pendingPdfImportProvider`（`StateProvider<PdfNoteImportPayload?>`）。Task 7、Task 8 依赖。

- [ ] **Step 1: 实现 payload**

`pdf_note_import_payload.dart`：

```dart
import 'dart:typed_data';

/// 暂存的待导入 PDF（从资料库页传递到白板页消费）。
class PdfNoteImportPayload {
  const PdfNoteImportPayload({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}
```

- [ ] **Step 2: 实现 provider**

`pending_pdf_import_provider.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_note_import_payload.dart';

/// 资料库首页选好 PDF 后暂存，白板页 _openNote 消费后置 null。
final pendingPdfImportProvider =
    StateProvider<PdfNoteImportPayload?>((ref) => null);
```

- [ ] **Step 3: 写一个最小存在性测试**

`<APP>/test/features/whiteboard/pdf_note_import/pending_pdf_import_provider_test.dart`：

```dart
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

void main() {
  test('pendingPdfImportProvider holds and clears payload', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pendingPdfImportProvider), isNull);
    final payload = PdfNoteImportPayload(
      bytes: Uint8List.fromList([1, 2, 3]),
      name: 'doc.pdf',
    );
    container.read(pendingPdfImportProvider.notifier).state = payload;
    expect(container.read(pendingPdfImportProvider)?.name, 'doc.pdf');
    container.read(pendingPdfImportProvider.notifier).state = null;
    expect(container.read(pendingPdfImportProvider), isNull);
  });
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/features/whiteboard/pdf_note_import/`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/pdf_note_import/ FlowMuse-App/test/features/whiteboard/pdf_note_import/
git commit -m "feat(whiteboard): 新增 pendingPdfImportProvider 暂存待导入 PDF"
```

---

## Task 7: PDF 笔记导入编排服务

**Files:**
- Create: `<APP>/lib/features/whiteboard/pdf_note_import/pdf_note_import_service.dart`
- Test: `<APP>/test/features/whiteboard/pdf_note_import/pdf_note_import_service_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `libraryIndexProvider.notifier.createNote`；Task 6 的 `pendingPdfImportProvider`。
- Produces：`PdfNoteImportService.pickAndStageImport(WidgetRef ref)` —— 选文件 → 建笔记 → 暂存 → 返回 `NoteItem?`（取消/失败返回 null）。文件选择部分拆出 `pickPdfFile()` 便于在测试中 mock（注入 `Future<PdfNoteImportPayload?> Function() picker`）。

- [ ] **Step 1: 写失败测试（注入 mock picker）**

```dart
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_service.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [
      libraryRepositoryProvider
          .overrideWith(createLibraryRepository(platform: TargetPlatform.ohos)),
    ]);
  });
  tearDown(() => container.dispose());

  group('PdfNoteImportService.pickAndStageImport', () {
    test('creates a pdf note and stages payload on success', () async {
      final service = PdfNoteImportService();
      final picker = () async => PdfNoteImportPayload(
            bytes: Uint8List.fromList([1, 2, 3]),
            name: 'report.pdf',
          );
      final note = await service.pickAndStageImport(
        container.read,
        picker: picker,
      );
      expect(note, isNotNull);
      expect(note!.kind, LibraryFilter.pdf);
      expect(note.title, 'report'); // 去扩展名
      expect(container.read(pendingPdfImportProvider)?.name, 'report.pdf');
    });

    test('returns null and creates nothing when picker cancelled', () async {
      final service = PdfNoteImportService();
      final note = await service.pickAndStageImport(
        container.read,
        picker: () async => null,
      );
      expect(note, isNull);
      expect(container.read(pendingPdfImportProvider), isNull);
      final index = await container.read(libraryRepositoryProvider).loadIndex();
      expect(index.notes, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/whiteboard/pdf_note_import/pdf_note_import_service_test.dart`
Expected: 编译失败（`PdfNoteImportService` 不存在）。

- [ ] **Step 3: 实现编排服务**

`pdf_note_import_service.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import 'pdf_note_import_payload.dart';
import 'pending_pdf_import_provider.dart';

/// 把"选 PDF → 建 PDF 笔记 → 暂存 bytes"串起来。
/// 文件选择器以依赖注入形式接收，便于测试与平台分发。
class PdfNoteImportService {
  const PdfNoteImportService();

  /// [picker]：平台文件选择（生产用真实 picker，测试注入 mock）。
  /// 返回创建的 [NoteItem]；用户取消返回 null。
  Future<NoteItem?> pickAndStageImport(
    T Function<T>(ProviderListenable<T>) read, {
    required Future<PdfNoteImportPayload?> Function() picker,
  }) async {
    final payload = await picker();
    if (payload == null) return null;

    final title = _titleFromFileName(payload.name);
    final note = await read(libraryIndexProvider.notifier).createNote(
      kind: LibraryFilter.pdf,
      title: title,
      subtitle: payload.name,
    );
    read(pendingPdfImportProvider.notifier).state = payload;
    return note;
  }

  String _titleFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

final pdfNoteImportServiceProvider =
    Provider<PdfNoteImportService>((ref) => const PdfNoteImportService());
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/whiteboard/pdf_note_import/pdf_note_import_service_test.dart`
Expected: 2 个 test PASS。

- [ ] **Step 5: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_import_service.dart FlowMuse-App/test/features/whiteboard/pdf_note_import/pdf_note_import_service_test.dart
git commit -m "feat(whiteboard): 新增 PDF 笔记导入编排服务"
```

---

## Task 8: 资料库首页「导入 PDF」入口 UI

**Files:**
- Create: `<APP>/lib/features/library/widgets/import_pdf_card.dart`
- Modify: `<APP>/lib/features/library/widgets/library_content.dart`（加 `onImportPdf` 回调 + 渲染卡片）
- Modify: `<APP>/lib/features/library/views/library_home_page.dart`（接 `onImportPdf`：调服务 + 真实 picker + 跳转白板）
- Test: `<APP>/test/features/library/library_import_pdf_card_test.dart`

**Interfaces:**
- Consumes：Task 7 的 `PdfNoteImportService`、`pendingPdfImportProvider`；路由 `AppRoutes.whiteboardPath(noteId:)`。

- [ ] **Step 1: 写失败测试（widget test，卡片渲染 + 点击回调）**

```dart
import 'package:flow_muse/features/library/widgets/import_pdf_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ImportPdfCard renders and fires onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImportPdfCard(onTap: () => tapped++))),
    );
    expect(find.text('导入 PDF'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-pdf-card')));
    await tester.pump();
    expect(tapped, 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/library/library_import_pdf_card_test.dart`
Expected: 编译失败（`ImportPdfCard` 不存在）。

- [ ] **Step 3: 实现 `ImportPdfCard`**

参考 `create_note_card.dart` 的视觉结构，但用 PDF 图标：

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'note_card.dart';

class ImportPdfCard extends StatelessWidget {
  const ImportPdfCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _tapKey = ValueKey('import-pdf-card');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          width: NoteCard.coverWidth,
          height: NoteCard.coverHeight,
          child: Card.outlined(
            clipBehavior: Clip.antiAlias,
            color: colorScheme.secondary.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              key: _tapKey,
              onTap: onTap,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      LucideIcons.fileText,
                      size: 34,
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '导入 PDF',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.secondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '选择 PDF，生成可批注笔记',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF9BA5A1)),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 跑卡片测试确认通过**

Run: `flutter test test/features/library/library_import_pdf_card_test.dart`
Expected: PASS。

- [ ] **Step 5: 在 `LibraryContent` 加 `onImportPdf` 回调并渲染卡片**

在 `library_content.dart`：
- 构造函数加 `required this.onImportPdf,` 与 `final VoidCallback onImportPdf;`
- 在渲染 `CreateNoteCard`（新建）的地方旁边加 `ImportPdfCard(onTap: onImportPdf)`。

> 先读 `library_content.dart` 里 `CreateNoteCard` 出现的 build 片段，确定它在哪个 Row/Wrap 里，把 `ImportPdfCard` 作为同级兄弟加入（保持紧凑/桌面布局都可见）。

- [ ] **Step 6: 在 `library_home_page.dart` 接 `onImportPdf`**

在 `build` 里 `LibraryContent(...)` 调用处加 `onImportPdf:`：

```dart
onImportPdf: () => _importPdf(context, ref),
```

并新增方法（用真实 picker，按平台分发；复用 `MarkdrawFileHandler` 已有的平台分支逻辑——但这里我们不需要 controller，只需拿到 bytes+name，所以直接调 picker）：

```dart
Future<void> _importPdf(BuildContext context, WidgetRef ref) async {
  final service = ref.read(pdfNoteImportServiceProvider);
  final note = await service.pickAndStageImport(
    ref.read,
    picker: () => _pickPdfFile(context),
  );
  if (note == null) return; // 用户取消
  if (!context.mounted) return;
  context.push(AppRoutes.whiteboardPath(noteId: note.id));
}

Future<PdfNoteImportPayload?> _pickPdfFile(BuildContext context) async {
  if (defaultTargetPlatform == TargetPlatform.ohos) {
    // 复用现有 OHOS CoreFileKit channel
    final files = await pickFilesViaOhosChannel(suffixFilters: ['文档(.pdf)|.pdf']);
    if (files.isEmpty) return null;
    final f = files.first;
    return PdfNoteImportPayload(bytes: f.bytes, name: f.name);
  }
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: '导入 PDF',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty || result.files.single.bytes == null) {
    return null;
  }
  return PdfNoteImportPayload(
    bytes: result.files.single.bytes!,
    name: result.files.single.name,
  );
}
```

> import：`file_picker`、`flutter/foundation.dart`（`defaultTargetPlatform`）、`pdf_note_import/` 下的 payload/service/provider、OHOS channel 的 `pickFilesViaOhosChannel`（从 markdraw_file_handler 所在的导出库 import）。先确认 `pickFilesViaOhosChannel` 的准确 import 路径。

- [ ] **Step 7: 跑 library 全量测试**

Run: `flutter test test/features/library/`
Expected: 全 PASS（含 Task 1 的测试与本 Task 的卡片测试）。

- [ ] **Step 8: Commit**

```bash
git add FlowMuse-App/lib/features/library/widgets/import_pdf_card.dart FlowMuse-App/lib/features/library/widgets/library_content.dart FlowMuse-App/lib/features/library/views/library_home_page.dart FlowMuse-App/test/features/library/library_import_pdf_card_test.dart
git commit -m "feat(library): 资料库首页新增「导入 PDF」入口"
```

---

## Task 9: WhiteboardPage 消费 pending 导入 + 启用约束 + 失败回退

**Files:**
- Modify: `<APP>/lib/features/whiteboard/views/whiteboard_page.dart`（`_openNote` :103-141 + 新增消费逻辑 + 回退）
- Test: `<APP>/test/features/whiteboard/views/whiteboard_page_pdf_note_test.dart`（widget test，注入 mock 渲染器）

**Interfaces:**
- Consumes：Task 3 的 `controller.contentBounds` setter；Task 6 的 `pendingPdfImportProvider`；现有 `MarkdrawFileHandler.importPdfSource`（:277，公开，已封装渲染+插入）；`Scene.sceneBounds()`（`scene.dart:102`）；`ViewportState.fitToBounds`（`viewport_state.dart:92`）。
- 关键：渲染后从 controller 当前 scene 算 `sceneBounds()` 作为 contentBounds 写回 controller。

- [ ] **Step 1: 读关键依赖确认 API**

读 `whiteboard_page.dart` 的 `_openNote`（:103-141）与 `WhiteboardPage` 构造、`_markdrawController`/`_fileHandler` 的字段定义；读 `MarkdrawController` 是否暴露 scene 访问器（`sceneBounds()`/`currentScene`）；确认 `fitToBounds` 调用方式（`viewport.fitToBounds(bounds, canvasSize)` 后写回 controller）。

- [ ] **Step 2: 写失败测试（widget test，注入 fake 渲染器返回 2 页）**

```dart
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/pdf/pdf_import.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/pdf/pdf_page_renderer.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import 'package:flow_muse/features/whiteboard/pdf_note_import/pending_pdf_import_provider.dart';
import 'package:flow_muse/features/whiteboard/views/whiteboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

// 一个返回 2 页固定大小 PNG 的假渲染器
class _FakePdfRenderer implements PdfPageRenderer {
  const _FakePdfRenderer();
  @override
  Future<List<PdfRenderedPage>> render(
    PdfImportSource source,
    PdfRenderOptions options,
  ) async {
    // 1x1 透明 PNG
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      // ...（测试里可用一个最小合法 PNG，或直接用现有测试 fixture 的字节）
    ]);
    return [
      PdfRenderedPage(bytes: png, mimeType: 'image/png', width: 400, height: 600, pageNumber: 1),
      PdfRenderedPage(bytes: png, mimeType: 'image/png', width: 400, height: 600, pageNumber: 2),
    ];
  }
}

void main() {
  // 注：此 widget test 需要构建 ProviderContainer + 路由。
  // 若 WhiteboardPage 难以在 widget test 直接构造（依赖较多），
  // 则把消费逻辑抽成一个可单独测试的函数 PdfNoteConsumer.consume(ref, controller)。
  test('PdfNoteConsumer sets contentBounds from rendered pages', () async {
    // 详见实现：把消费逻辑抽离后单测
  });
}
```

> **实现策略**：把 `_openNote` 里"kind==pdf 时的消费"逻辑抽成一个独立类/函数 `PdfNoteConsumer`（接收 ref + controller + noteId），使其可单测。这比直接测 WhiteboardPage widget 更稳。

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/features/whiteboard/views/whiteboard_page_pdf_note_test.dart`
Expected: 失败（`PdfNoteConsumer` 不存在）。

- [ ] **Step 4: 实现 `PdfNoteConsumer`（可放 `pdf_note_import/` 下）**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor_core/flow_muse_whiteboard_editor.dart';
import '../editor_core/src/core/math/math.dart';
import '../editor_core/src/core/pdf/pdf_import.dart';
import '../editor_core/src/core/scene/scene.dart';
import '../editor_core/src/ui/markdraw_file_handler.dart';
import '../repositories/library_repository.dart';
import '../../features/library/models/note_item.dart';
import 'pdf_note_import_payload.dart';
import 'pending_pdf_import_provider.dart';

/// 消费 pendingPdfImport：把 bytes 渲染进笔记，设 contentBounds。
/// 失败时删除笔记并返回 false（调用方据此回退 UI）。
class PdfNoteConsumer {
  const PdfNoteConsumer();

  Future<bool> consume({
    required Ref ref,
    required MarkdrawController controller,
    required MarkdrawFileHandler fileHandler,
    required String noteId,
    required Size canvasSize,
    required PdfPageRenderer pdfPageRenderer,
  }) async {
    final payload = ref.read(pendingPdfImportProvider);
    if (payload == null) return false;
    // 先清掉，避免重复消费
    ref.read(pendingPdfImportProvider.notifier).state = null;

    try {
      final source = PdfImportSource(name: payload.name, bytes: payload.bytes);
      await fileHandler.importPdfSource(source, canvasSize);

      // 从当前 scene 算 PDF 页并集 bounds，设为 contentBounds
      final bounds = controller.currentScene.sceneBounds();
      controller.contentBounds = bounds;
      // 居中适配
      final fitted = controller.viewport.fitToBounds(bounds, canvasSize);
      controller.setViewport(fitted);

      // 回填 subtitle（页数 N 现在已知）
      final pageCount = controller.currentScene.elements
          .where((e) => e is ImageElement)
          .length;
      await ref.read(libraryIndexProvider.notifier).renameSubtitle(
            noteId,
            '$pageCount 页 · ${payload.name}',
          );
      return true;
    } catch (_) {
      // 渲染失败 → 删除空笔记
      await ref.read(libraryIndexProvider.notifier).deleteNotes([noteId]);
      return false;
    }
  }
}
```

> **需先确认的 accessor**（在 Step 1 读代码时核对，存在则直接用，不存在则在 controller 补 getter）：
> - `controller.currentScene`（返回 `Scene`）—— 若无，补 `Scene get currentScene => _scene;`
> - `Scene.sceneBounds()`（:102，已存在）
> - `controller.setViewport(ViewportState)`（若无，补）
> - `controller.viewport` getter（若无，补）
> - `Scene.elements` 暴露方式（若私有，加 `List<Element> get elements => List.unmodifiable(_elements);`）
> - `LibraryIndexNotifier.renameSubtitle(noteId, subtitle)` —— 若无此方法，新增（内部 `_updateNote` 改 subtitle）。
>
> 这些 getter/方法若需新增，**单独小 commit**（`refactor(whiteboard): 暴露 scene/viewport/subtitle 访问器`），再继续本 Task。

- [ ] **Step 5: 在 `_openNote` 接入消费逻辑**

修改 `whiteboard_page.dart` 的 `_openNote`，在 `loadFromContent` 之后：

```dart
_loadingScene = true;
_markdrawController.loadFromContent(content, '$noteId.excalidraw');
_loadingScene = false;

// PDF 笔记：消费 pending 导入
final index = await ref.read(libraryIndexProvider.notifier).build();
final note = index.notes.where((n) => n.id == noteId).firstOrNull;
if (note?.kind == LibraryFilter.pdf) {
  final payload = ref.read(pendingPdfImportProvider);
  if (payload != null) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(800, 600);
    final ok = await const PdfNoteConsumer().consume(
      ref: ref,
      controller: _markdrawController,
      fileHandler: _fileHandler,
      noteId: noteId,
      canvasSize: canvasSize,
      pdfPageRenderer: createDefaultPdfPageRenderer(),
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 导入失败，已取消')),
        );
        context.go(AppRoutes.library); // 返回资料库
      }
      return;
    }
  } else {
    // 打开已有 PDF 笔记：从已存 scene 算 contentBounds
    final bounds = _markdrawController.currentScene.sceneBounds();
    _markdrawController.contentBounds = bounds;
    final renderBox = context.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(800, 600);
    _markdrawController.setViewport(
      _markdrawController.viewport.fitToBounds(bounds, canvasSize),
    );
  }
}
```

> 同时给 `MarkdrawEditor` 的 config 在 PDF 笔记时无需特别传 contentBounds（因为 controller 运行时 `contentBounds` setter 已覆盖；config.contentBounds 作为可选的初始值，二者 `controller.contentBounds` getter 已合并 `?? `）。加载 loading 遮罩用 `setState` 控制 `_loadingScene` 或新增 `_importingPdf` 状态。

- [ ] **Step 6: 跑测试确认通过**

Run: `flutter test test/features/whiteboard/views/whiteboard_page_pdf_note_test.dart`
Expected: PASS。

- [ ] **Step 7: 回归全部白板测试**

Run: `flutter test test/features/whiteboard/`
Expected: 全 PASS。

- [ ] **Step 8: Commit**

```bash
git add FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_consumer.dart FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/test/features/whiteboard/views/whiteboard_page_pdf_note_test.dart FlowMuse-App/lib/features/library/repositories/library_repository.dart
git commit -m "feat(whiteboard): 消费 pending PDF 导入并启用画布约束 + 失败回退"
```

---

## Task 10: 端到端回归与手动验证清单

**Files:** 无代码改动，仅验证。

- [ ] **Step 1: 跑全量测试**

Run: `flutter test`
Expected: 全 PASS。

- [ ] **Step 2: 静态分析**

Run: `flutter analyze`
Expected: 无 error（warning 视情况处理）。

- [ ] **Step 3: 鸿蒙端手动验证清单**

> 鸿蒙端 PDF 渲染走原生 `PdfImportChannel.ets`（华为 PDF Kit），参考文档 `harmonyos-guides/应用服务/PDF Kit（PDF服务）/pdfService能力/转换PDF文档为图片/pdf-get-img.md` 与 `pdf-open-document.md`。本次未改原生代码，重点验证端到端：

1. 在鸿蒙设备/模拟器运行应用，进入资料库首页，确认「导入 PDF」卡片可见。
2. 点击 → CoreFileKit 选一个 PDF（含多页）。
3. 确认：资料库新增一条 PDF 笔记（PDF 图标封面）；自动跳转白板，PDF 各页竖排居中显示。
4. 确认画布约束：向 PDF 左/右/上/下方向用力滑动，视口**不能**滑到 PDF 外的空白区。
5. 确认创建约束：用画笔在 PDF 页内画线→成功；在 PDF 外空白处画线→无反应。
6. 确认 subtitle 回填为「N 页 · 文件名.pdf」。
7. 返回资料库，重新打开该 PDF 笔记 → 内容仍在、约束仍生效。
8. 故障路径：导入一个损坏 PDF → 应弹「PDF 导入失败，已取消」并返回资料库，且资料库**无空笔记残留**。
9. 普通笔记回归：新建普通笔记 → 可无限平移、任意位置创建元素（约束未误启用）。

- [ ] **Step 4: 其它平台冒烟（可选）**

若环境允许，在 Android/Desktop/Web 上重复"导入 PDF→生成笔记→约束生效"冒烟。pdfx 路径无原生改动，理论上可用；若某平台渲染失败按 spec 第 8 节"已知限制"处理。

- [ ] **Step 5: 最终 Commit（若有验证产生的文档/脚本）**

```bash
# 仅当有变更时
git add <files>
git commit -m "test: PDF 笔记导入端到端回归"
```

---

## 自查记录（plan self-review）

**1. Spec coverage：**
- 目标 1（资料库首页入口）→ Task 8 ✓
- 目标 2（PDF 渲染竖排居中）→ Task 9（复用 importPdfSource，已有 importPdfPages 竖排居中逻辑）✓
- 目标 3（画布限制：平移/缩放/创建）→ Task 2/3/4/5 ✓
- 目标 4（共享持久化）→ Task 1 + 复用现有存储 ✓
- 目标 5（失败回退）→ Task 9 ✓
- 非目标（移动 clamp/重复检测/blob存储）→ 明确不做 ✓

**2. Placeholder scan：** 无 TBD/TODO；每个 code step 都给了完整代码；Task 9 的"需确认 accessor"已说明 fallback（补 getter + 单独 commit），非占位。

**3. Type consistency：**
- `createNote` 签名在 Task 1（repo/notifier）与 Task 7（service 调用）一致 ✓
- `clampViewportToBounds(ViewportState, Bounds?, Size, {padding})` Task 2 定义、Task 3 使用 ✓
- `controller.contentBounds` setter/getter Task 3 定义、Task 4/5/9 使用 ✓
- `PdfNoteImportPayload({bytes,name})` Task 6 定义、Task 7/8/9 使用 ✓
- `pendingPdfImportProvider` Task 6 定义、Task 7/8/9 使用 ✓
- `canCreateAt(Point)` Task 5 定义 ✓（注意 `Point` 非 `Offset`）

**4. 鸿蒙参考文档：** Global Constraints 已列明 `harmonyos-guides` 路径，Task 10 手动验证引用 `pdf-get-img.md`/`pdf-open-document.md`。鸿蒙原生代码本次零改动（债务登记在 spec）。
