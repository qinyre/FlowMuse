# PDF 视口边界修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 恢复 PDF 笔记首屏适配第一页，并将所有平移和缩放限制在 PDF 背景整体范围内。

**Architecture:** 将 probe 已验证的显式 `contentBounds + canvasSize` 状态迁移到 main 的 `MarkdrawController`。PDF 生命周期负责从背景元素计算边界，`EditorCanvas` 负责报告真实画布尺寸，controller 统一约束所有 `UpdateViewportResult`。

**Tech Stack:** Flutter、Dart、CustomPainter、flutter_test

## Global Constraints

- 仅 PDF 背景存在时启用边界，普通分页和无界笔记保持原行为。
- 不修改元素模型、序列化字段、协同协议和平台特定代码。
- 画布尺寸变化后只重新 clamp，不跳回第一页。
- 首次导入或重新打开 PDF 时只执行一次第一页适配。

---

### Task 1: 显式 PDF 边界状态

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

**Interfaces:**
- Produces: `Bounds? get contentBounds`
- Produces: `set contentBounds(Bounds? value)`
- Produces: `Size get canvasSize`
- Produces: `set canvasSize(Size value)`

- [ ] **Step 1: 写失败测试**

覆盖设置边界后立即拉回远端视口、PDF 边界下平移受限、无边界画布不受限、尺寸变化不重置当前阅读位置。

- [ ] **Step 2: 验证测试失败**

Run: `flutter test --no-pub test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

Expected: FAIL，因为 main 尚未公开 `contentBounds` 和 `canvasSize`。

- [ ] **Step 3: 实现最小 controller 状态**

在 controller 中加入：

```dart
Bounds? _contentBounds;
Size _canvasSize = Size.zero;

Bounds? get contentBounds => _contentBounds;

set contentBounds(Bounds? value) {
  _contentBounds = value;
  _reclampViewport();
}

Size get canvasSize => _canvasSize;

set canvasSize(Size value) {
  _canvasSize = value;
  _reclampViewport();
}
```

`_constrainPdfViewport` 改为使用显式状态，不再依赖外层 `_lastCanvasSize`。

- [ ] **Step 4: 验证测试通过**

Run: `flutter test --no-pub test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/test/features/whiteboard/editor_core/controller_content_bounds_test.dart
git commit -m "fix: 恢复 PDF 显式视口边界"
```

### Task 2: 接入真实画布尺寸和 PDF 生命周期

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_consumer.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/pdf_import_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `contentBounds` 与 `canvasSize`
- Produces: `PdfNoteConsumer.pdfBackgroundBounds(Scene scene)`
- Produces: `PdfNoteConsumer.fitFirstPageViewport(Scene scene, Size canvasSize)`

- [ ] **Step 1: 写失败测试**

测试 PDF 背景联合边界、第一页适配、重新打开后的边界恢复，以及实际画布尺寸变化后仍保持受限。

- [ ] **Step 2: 验证测试失败**

Run: `flutter test --no-pub test/features/whiteboard/editor_core/pdf_import_controller_test.dart`

Expected: FAIL，因为 consumer 尚未显式配置 controller 边界。

- [ ] **Step 3: 接入真实尺寸与生命周期**

`EditorCanvas` 的 `LayoutBuilder` 每次尺寸变化时执行：

```dart
controller.canvasSize = canvasSize;
```

PDF consumer 和重新打开流程执行：

```dart
controller.canvasSize = canvasSize;
controller.contentBounds = PdfNoteConsumer.pdfBackgroundBounds(
  controller.currentScene,
);
controller.setViewport(
  PdfNoteConsumer.fitFirstPageViewport(controller.currentScene, canvasSize),
);
```

普通笔记打开时执行 `controller.contentBounds = null`。

- [ ] **Step 4: 验证测试通过**

Run: `flutter test --no-pub test/features/whiteboard/editor_core/pdf_import_controller_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_consumer.dart FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/test/features/whiteboard/editor_core/pdf_import_controller_test.dart
git commit -m "fix: 恢复 PDF 首屏与移动范围"
```

### Task 3: 回归验证

**Files:**
- Modify only if verification exposes a defect.

**Interfaces:**
- Consumes: Tasks 1-2 的完整 PDF 视口行为

- [ ] **Step 1: 执行专项测试**

Run:

```bash
flutter test --no-pub \
  test/features/whiteboard/editor_core/controller_content_bounds_test.dart \
  test/features/whiteboard/editor_core/pdf_import_controller_test.dart \
  test/features/whiteboard/editor_core/rendering/viewport_clamp_test.dart \
  test/features/whiteboard/editor_core/pdf_creation_bounds_test.dart
```

Expected: All tests passed。

- [ ] **Step 2: 执行静态检查**

Run: `flutter analyze --no-pub`

Expected: No issues found。

- [ ] **Step 3: 执行 HAP 构建**

Run: `flutter build hap --debug --no-pub`

Expected: 生成 `build/ohos/hap/entry-default-signed.hap`。

- [ ] **Step 4: 检查提交范围**

Run: `git diff --check` 和 `git status --short`

Expected: 不包含 `path_provider_ohos` 构建产物或签名配置。
