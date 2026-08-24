# 修复：多选（含手写笔迹簇）只显示外层虚线框

> 分支：`feature/fix-group-select-box`
> 定位：框选/多选一组元素（典型是若干**未分组**手写笔画，如"我思/不行"）时，画布给每个成员都画一个蓝色实线小框；需求是**只保留最外层的 union 虚线框 + 手柄**，去掉内部逐元素框。
> 版本：v2（修订）。v1 曾假设"笔迹已分组"，用 `isGroupUnit`/`isCompleteGroupSelection` 判定组合选中——**经现场验证无效**（手写笔画共享 `groupIds` 仅来自 Ctrl+G 或 sketch 导入，默认独立未分组），故回退该机制，改为最简方案。

## 0. 事实基线（本次逐行核实）

| 主题 | 事实 | 位置 |
|---|---|---|
| 手写元素分组方式 | `groupIds` 只通过 `groupElements`（Ctrl+G）或 sketch 序列化导入赋初值；手写/自由绘制**不自动分组** | `group_utils.dart`；`select_tool.dart:1601`；`sketch_line_parser.dart:205+` |
| 多选来源 | "我思/不行" 是若干独立 `FreedrawElement`，经 marquee 框选一并选中，构成普通多选（无共享 groupIds） | `select_tool.dart:505-538` |
| 内层框绘制入口 | painter 以 `elementBounds.isNotEmpty` 判 `isMultiSelect` → 先 `drawElementOutlines` 逐元素画实线框（内层），再 `drawDashedSelectionBox` 画 union 虚线框 + 手柄 | `interactive_canvas_painter.dart:110-145`；`selection_renderer.dart:137-172`(实线)/`174-194`(虚线) |
| 外层虚线框依据 | 虚线绘制依赖 `elementBounds.isNotEmpty`（isMultiSelect 为真）→ 不可清空 elementBounds，否则外层框变实线 | `interactive_canvas_painter.dart:131-145` |
| 远端协作框 | 远端成员逐元素框走独立路径 `RemoteCollaboratorOverlay.selectionBounds`（`_drawRemoteCollaborator`），与本改动无关 | `interactive_canvas_painter.dart:250-296` |
| 手柄命中 | `_hitTestHandle` 只用 overlay 的 bounds/handles/angle，与 elementBounds 无关 | `select_tool.dart:608-630` |
| 现无 painter 测试 | editor_core 下无 `InteractiveCanvasPainter` 层测试；`ViewportState` 可简构（zoom=1, offset=0）便于测试 | `viewport_state.dart:10-13` |

**v1 无效的根因**：`isCompleteGroupSelection` 要求选中集合恰好等于某群组完整成员集；未分组笔画间无共享 `groupIds` → 恒为 false → 逐元素轮廓照旧绘制。**用户的真实诉求与"是否分组"无关**：任何多选都不想要内部逐元素框。

## 1. 需求

1. 多选（marquee / Shift / 点击组合）时只绘制 union 虚线框 + 8 个手柄 + 旋转手柄，**不绘制**逐元素内部实线框。
2. 单选保持不变（单实线框 + 手柄，无 member 框；线段/箭头等例外逻辑不动）。
3. 远端协作指针/成员选中高亮不变。
4. 拖拽/缩放/旋转/属性面板等交互不受影响（纯 overlay 构图层改动）。

## 2. 实现方案

### 2.1 核心改动：去掉本地逐元素轮廓绘制

`interactive_canvas_painter.dart` 中删除多选时调用 `SelectionRenderer.drawElementOutlines(...)` 的分支（现 111-121 行附近）：

```dart
final isMultiSelect = selection!.elementBounds.isNotEmpty; // 保留（虚线框依据）
final hasAngle = selection!.angle != 0.0;

// 已删除：多选时逐个成员的实线轮廓绘制（drawElementOutlines 调用及其 elementBounds 循环）
```

保留：`isMultiSelect` 判定（仍由 `elementBounds.isNotEmpty` 驱动）→ union 虚线框、8 个缩放手柄、旋转手柄照常；`hasAngle` 旋转变换逻辑不变。

### 2.2 依赖项回退（v1 引入，现无用）

- `group_utils.dart`：删除 `isCompleteGroupSelection`。
- `selection_overlay.dart`：删除 `isGroupUnit` 字段、构造参数、`==`/`hashCode` 分支，以及 `elementBounds: isGroupUnit ? const [] : elemBounds` 三元——`elementBounds` 仍按"元素数 > 1"填充（供虚线框判定与潜在复用）。
- `markdraw_controller.dart buildSelectionOverlay()`：恢复为直接 `SelectionOverlay.fromElements(selected, mode: interactionMode)`。

不触边界的：Excalidraw JSON、协作协议、数据库、`SelectionRenderer` 的绘制函数本身、`drawElementOutlines`（保留函数但无调用点——留作后续/复用，或按需删除）。

> 备注：`drawElementOutlines` 保留但不再被本地多选调用；若确认全库无其他引用可一并删除（本计划默认保留，最小 diff）。

## 3. 关键文件

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/features/whiteboard/editor_core/src/rendering/interactive/interactive_canvas_painter.dart` | 修改 | 删除多选时 `drawElementOutlines` 调用；`isMultiSelect` 判定不变 |
| `lib/features/whiteboard/editor_core/src/core/groups/group_utils.dart` | 回退 | 删除 `isCompleteGroupSelection` |
| `lib/features/whiteboard/editor_core/src/rendering/interactive/selection_overlay.dart` | 回退 | 删除 `isGroupUnit` 相关字段/参数/相等性 |
| `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` | 回退 | 恢复 `buildSelectionOverlay` 原样 |
| `test/features/whiteboard/editor_core/selection_overlay_painter_test.dart` | 重写 | 见 §4：painter 多选不画逐元素框 + overlay 契约 |
| `docs/研发记录/plans/2026-08-24-group-selection-box-fix.md` | 修改（即本文件） | 修正后的修复计划 |

## 4. 验证方案

### 自动化

1. `flutter analyze`——不新增 error。
2. `flutter test test/features/whiteboard/editor_core/selection_overlay_painter_test.dart` 通过。用例：
   - **painter 契约（核心）**：构造含 2 个未分组矩形元素的多选 `SelectionOverlay`（`elementBounds` 非空），用 `PictureRecorder`+记录型 Canvas 代理（`noSuchMethod` 转发并统计）执行 `paint`；断言**没有**任何 `drawRect` 命中"元素包围盒 ± padding"的大矩形（即不再画逐元素轮廓），但 union 虚线外框仍产生（存在 4 条以上 `drawLine`）。
   - **overlay 契约**：多选 `fromElements` → `elementBounds` 非空（保证外层走虚线）；单选 → `elementBounds` 为空。
3. `flutter test` 全量——既有用例无回归。

### 手动

4. 复现截图场景：框选"我思/不行"这组笔迹 → **只剩外层一个虚线框 + 手柄**，无内部小实线框。
5. 框选两个独立矩形/文字：同样仅外层虚线框（本次改动的统一语义）。
6. 单选一个元素：仍标准单实线框 + 手柄。
7. 远端协作（如有）：对方选中高亮仍逐元素显示，不受影响。
8. 组合选中（Ctrl+G 后点击）：仍仅外层虚线框（v1 的方案被删除后由同一"不画逐元素框"逻辑覆盖）。

## 5. 实施步骤

1. 回退 `group_utils.dart` / `selection_overlay.dart` / `markdraw_controller.dart` 中 v1 的 `isGroupUnit` 机制。
2. `interactive_canvas_painter.dart` 删除 `drawElementOutlines` 调用。
3. 重写测试文件为 `selection_overlay_painter_test.dart`（先红后绿：先在删调用前写"断言无逐元素框"用例如预期失败，再删调用使其通过）。
4. `flutter analyze` + 目标测试 + 全量 `flutter test`。
5. 手动按 §4 回归第 4-8 条。
