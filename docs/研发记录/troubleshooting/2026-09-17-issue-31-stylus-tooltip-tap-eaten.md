# 触控笔点白板工具栏偶尔需点多次（issue #31）

> 发现日期：2026-09-17
> 发现途径：鸿蒙真机触控笔反馈（第一轮修复无效后复现）+ 框架源码核验 + widget 复现测试
> 性质：**框架交互机制缺陷**（Material `Tooltip` 气泡命中不透明），非业务代码逻辑错误
> 状态：已修复（编辑期内统一自绘 `HoverTooltip`），待真机复验

## 现象

- 触控笔（stylus）点白板工具栏按钮，约 40%~50% 概率第一次点击被吞，需点第二下甚至更多下才生效。
- 受影响范围不止工具栏：选笔（笔盒弹层条目）、选图形（图形弹层条目）、属性面板 chips 同样复现。
- **手指触摸不复现**；无其他副作用（不误触发别的功能，单纯"点了没反应"）。
- 第一轮修复（把 `Tooltip` 的 `triggerMode` 改为 `manual`，提交 `36bbb38`）无效。

## 根因链

1. 框架 `MouseTracker` 把 stylus 当作可悬停指针追踪（接受 `mouse` + `stylus`），
   触控笔悬停即触发 `MouseRegion.onEnter` → 弹出 `Tooltip` 气泡。
   **`triggerMode` 与悬停弹出无关**：官方文档明确 "Setting triggerMode to manual will not
   prevent the tooltip from showing when the mouse cursor hovers over it"——这是第一轮修复
   失效的原因。
2. `RawTooltip.build`（`raw_tooltip.dart`）无条件把 child 包进 `_ExclusiveMouseRegion`
   + `Listener(behavior: opaque)`，气泡内容亦然（`_ExclusiveMouseRegion` 默认
   `HitTestBehavior.opaque`）。
3. `_RenderExclusiveMouseRegion.hitTest` 命中后**自加并返回 true**，`_RenderTheater
   .hitTestChildren` 遇到最上层命中的 overlay entry 即停止——落在气泡矩形内的按下事件
   **根本不会派发给下方控件**。
4. 气泡定位 = 锚点中心 + `verticalOffset(24px)`（`positionDependentBox(preferBelow: true)`），
   即气泡紧贴被悬停控件的下方 24px 起。
   组合后果：**纵向堆叠的按钮**（左/右停靠工具栏、属性面板多行 chips、弹层里的条目、
   菜单行）中，上方控件的气泡正好盖住下一个控件的中心 → 第一下被吃；
   笔移开再靠近会再次弹泡 → 表现为"要点好几次"。

## 探针证据（widget 测试，2026-09-17）

用 `tester.createGesture(kind: PointerDeviceKind.stylus)` + `addPointer` + `moveTo` 模拟
"笔悬停 A → 点 B"：

| 布局 | 结果 |
|------|------|
| 横向相邻 32px IconButton 行（撤销/重做/缩放） | 点击正常（气泡在按钮行下方，不盖中心） |
| 纵向堆叠 32px IconButton（面板列表） | **第一次点击被吞**（气泡盖住下一个按钮中心） |
| 横向行 + 下一行控件（多行面板/两行工具栏） | **第一次点击被吞** |

骨架实现见回归测试 `test/features/whiteboard/editor_core/ui/stylus_hover_tooltip_tap_test.dart`
（纵向按钮对复现"悬停 A 后点 B 第一下即生效"）。

## 修复方案

新增自绘 `HoverTooltip`（`lib/features/whiteboard/editor_core/src/ui/hover_tooltip.dart`）：

- 悬停（鼠标/触控笔）仍弹提示气泡，外观复刻 Material 默认样式（桌面 24px / 移动 32px 高）；
- 气泡外包 `IgnorePointer`——**永不参与命中测试**，从根上消除"吞点击"；
- 保留 `Semantics(tooltip:)` 无障碍语义；
- 任意 `PointerDownEvent` 全局收起气泡（与 Material 行为一致）；
- 控件卸载时移除 overlay entry，不泄漏。

编辑器内**所有**悬停提示站点统一改为 `HoverTooltip`：

- 第一轮已改：`studio_rail_icon_button`（工具栏 + 两个弹层全部按钮）、`toggle_chips`
  （属性面板 chips）、`property_panel_content`（对齐按钮）、`theme_buttons`、
  `compact_menu`、`markdraw_editor`、`markdraw_split_pane`；
- 第二轮补齐：`zoom_controls`（撤销/重做/缩放）、`editor_canvas`（属性）、
  `hamburger_menu`（菜单）、`compact_menu`（跟随主题）、`compact_library`（导入/导出素材库）、
  `canvas_background_picker`、`help_button`、`library_panel`（导入/导出/关闭/移除）、
  `link_overlay`、`find_overlay`、`property_panel`（收起属性面板）。
- 约定固化：`.agent/conventions.md` §9.4（编辑器内禁用框架 `Tooltip`，含
  `IconButton(tooltip:)` / `PopupMenuButton(tooltip:)`）。

## 验证

- `flutter analyze`：无 issue。
- `flutter test`：全量通过（1670 例）。
- 新增回归：`stylus_hover_tooltip_tap_test.dart`（6 例，含"悬停 A 后点 B 第一下即生效"）；
  点击链路 `studio_rail_icon_button_test.dart`、笔盒语义 `toolbar_pressure_semantics_test.dart`
  同步迁移 finder 后全绿。
- **未做真机验证**：需在鸿蒙真机（触控笔）上复验工具栏 / 选笔 / 选图形三处。

## 遗留与后续

- `editor_core` 之外仍有 31 处框架 `Tooltip`（白板 feature 内 8 处：AI 助手对话框、
  区域截取、排版面板/模板表、whiteboard_page；其余 feature 23 处）。
  这些同样具备"气泡吞点击"的机制，但布局多为横向行（探针证明当前不受影响）；
  若后续出现同类现象，按同一模式替换为 `HoverTooltip`。
- 若真机复验仍复现，下一步需在输入端加探针日志定位：
  记录 stylus 事件的 down/up 与命中目标（不涉及协作明文/密钥，符合日志脱敏约定）。

## 关联

- 分支：`fix/toolbar-stylus-double-tap`
- 首轮提交：`36bbb38`（`triggerMode: manual`，无效）
- 涉及框架源码：`packages/flutter/lib/src/widgets/raw_tooltip.dart`
  (`_ExclusiveMouseRegion`、`build`、`_RenderTheater.hitTestChildren`)、
  `packages/flutter/lib/src/material/tooltip.dart`（`_defaultVerticalOffset = 24`）
