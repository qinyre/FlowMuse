# 触控笔点白板工具栏偶尔需点多次（issue #31）

> 发现日期：2026-09-17
> 发现途径：鸿蒙真机触控笔反馈（第一轮修复无效后复现）+ 框架源码核验 + widget 复现测试
> 性质：前两轮为**框架交互机制缺陷**（Material `Tooltip` 气泡命中不透明）；第三轮确认为
> **结构性缺陷**（点击动作依赖手势竞技场判决，引擎取消指针即永久失效）
> 状态：第三轮已改为触控笔原始指针通道派发（绕开竞技场）；**真机复验待做**（用下方诊断开关）

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
- `flutter test`：本轮全量通过（1681 项）。
- 新增回归：`stylus_hover_tooltip_tap_test.dart`（6 例，含"悬停 A 后点 B 第一下即生效"）；
  点击链路 `studio_rail_icon_button_test.dart`、笔盒语义 `toolbar_pressure_semantics_test.dart`
  同步迁移 finder 后全绿；本轮新增真实工具栏交互回归与输入诊断回归。
- **未做真机验证**：需在鸿蒙真机（触控笔）上复验工具栏 / 选笔 / 选图形三处。

## 本轮复核与诊断

本轮把真实 `DesktopToolbar`、`CompactToolbar`、三种停靠位置、真实滚动祖先、笔盒与图形弹层纳入测试。触控笔悬停相邻按钮后一次点选、700ms 按压、触摸、反向触控笔、移出取消和滚动拖动均保持正确语义；本机没有出现新的“有效点击被吞”失败，因此没有添加手势阈值或绕过 arena 的补丁。

新增 `toolbar_input_diagnostics.dart`，由 `StudioRailIconButton` 接入原始 pointer 与 InkWell 的 `tapDown`、`tapUp`、`tapCancel`、`tap` 阶段。默认编译开关为 `false`，关闭时不注册全局路由、不收集、不输出；只在需要真机复验时用以下命令打开：

```text
flutter run --dart-define=FLOWMUSE_TOOLBAR_INPUT_DIAGNOSTICS=true
```

日志只包含固定控件标识、pointer/device/kind/buttons、相对位移、耗时和阶段，不包含绝对坐标、用户文本、白板内容或协作密钥。`globalDown` 表示按下位置落在按钮边界内；随后有 `down` 表示按钮实际命中；有 `down` 但最终只有 `tapCancel` 表示手势在 arena 或系统取消；有 `globalDown` 而没有 `down` 表示按钮边界内的按下被更上层命中对象拦截。

本机测试覆盖诊断默认关闭、事件阶段、取消和卸载清理。原鸿蒙设备仍需按真机矩阵复验，不能仅凭 widget 测试宣称原现场现象已经消失。

## 第三轮（2026-09-20）：真机症状恶化 → 绕开竞技场的原始指针通道

### 新现象（真机反馈）

前两轮修复（`36bbb38` 改 `triggerMode=manual`、`c1c00ff` 换 `HoverTooltip`）之后真机症状**更重**：
几乎每次都要点好几次，且第一次点击连灰色高亮都不出现。说明前两轮改的都是"气泡吞点击"的
子问题，没有触及真正的机制。

### 本轮排除的假设（均有框架源码/探针证据）

| 假设 | 证据 | 结论 |
|------|------|------|
| `buttons` 不匹配导致 tap 被拒 | `converter.dart` `_synthesiseDownButtons` 对 touch/stylus/invertedStylus 的 down/move 在 `buttons==0` 时合成 `kPrimaryButton` | 排除 |
| 抖动位移越过 slop | `kTouchSlop = 18` 逻辑像素，探针 10px 抖动不触发 `handleEvent` 的 slop 分支 | 排除（≤18px 内不取消） |
| 竞技场里有第二个识别器抢手势 | `debugPrintGestureArenaDiagnostics` 探针：按钮本地竞技场只有 tap 一个成员，Default winner 正常 | 排除 |
| `HoverTooltip` 气泡吞事件 | 气泡包 `IgnorePointer`，本地测试点击透传 | 排除 |
| 应用层代码合成 `PointerCancelEvent` | 全仓无 `cancelPointer` 调用 | 排除 |

### 根因（框架机制，真机引擎差异触发）

点击动作**完全依赖手势竞技场判决**：

1. `BaseTapGestureRecognizer` 的 `deadline = kPressTimeout(100ms)`——`tapDown`（按钮高亮）
   只有在竞技场判赢或超时后才派发；`tap` 只在 `PointerUpEvent` 时派发。
2. `BaseTapGestureRecognizer.handlePrimaryPointer` 收到 `PointerCancelEvent` 时
   `resolve(rejected)` + `_reset()`——**这一次按压被永久取消**，不会再有 tap。
3. `GestureBinding._handlePointerEventImmediately`（`gestures/binding.dart:418-421`）对
   `PointerUpEvent || PointerCancelEvent` 执行 `_hitTests.remove(event.pointer)`：
   cancel 会把该指针的命中路径从缓存里移除，而 `hitTestResult == null` 的事件
   **不派发**（`binding.dart:436-438`）——即**引擎发 cancel 之后，紧随的 up 根本到不了按钮**。

真机触控笔的事件流由 OHOS 引擎产生，按压期间出现 cancel（或取消时机早于竞技场判决）
即命中此链：高亮都没来得及画 → 点一次没用；需要连点多次。手指触摸不走这条路径，故不复现。

### 修复

`StudioRailIconButton`（`editor_core/src/ui/studio_rail_icon_button.dart`）改为 StatefulWidget，
在最外层 `Listener` 上为触控笔（`stylus` / `invertedStylus`）加一条**不经过竞技场**的通道：

- 按下（命中按钮）→ 记录 pointer 与按下位置；
- 移动 → 累计最大位移；抬起**或取消** → 位移 ≤ `kTouchSlop`（与框架同源）即派发动作，
  位移越大（视作拖动）则忽略；
- 结算发生在 `PointerUpEvent` 与 `PointerCancelEvent` 两处——因为 cancel 之后 up 不会派发，
  取消时刻是唯一能救回这次点选的机会；
- 去重：原始通道派发后置 400ms 抑制开关，InkWell 的 tap 若也判赢则只记 `inkTapSuppressed` 不派发；
  下一次按压按下时复位；
- 手指/鼠标**完全不动**（仍走 InkWell 原路径），已有测试证明两者行为不变。

### 验证

- `flutter analyze`：No issues found。
- `flutter test`：**全量 1690 项通过**。本轮新增 9 例
  （`studio_rail_icon_button_stylus_test.dart`），其中"按下后引擎取消指针，抬手仍应生效"
  在修复前实测 `taps=0`（复现吞点击），修复后 `taps=1`；另含"拖动后被取消不生效"守位移容差。
- 既有回归（输入诊断、悬停气泡、真实工具栏/弹层交互、拖动不切换工具、长按/触摸/反向笔）
  全部保持通过。

### 真机复验方法（待做）

```text
flutter run --dart-define=FLOWMUSE_TOOLBAR_INPUT_DIAGNOSTICS=true
```

关注 `studio_rail_icon_button` 的 `source=gesture` 阶段：

| 日志 | 含义 |
|------|------|
| `stage=rawTap` | 引擎正常发 up，原始通道结算（正常路径） |
| `stage=rawCancelTap` | **引擎用 cancel 代替了 up**（本轮根因的现场证据），原始通道救回 |
| `stage=inkTapSuppressed` | InkWell 的 tap 也判赢，被去重挡下（同一次按压不会派发两次） |
| `stage=tap` | 手指/鼠标路径（未走原始通道） |

若真机上仍出现"点了没反应"，看是否有 `source=pointer stage=down` 而无任何 `rawTap`/`rawCancelTap`：
那说明按下事件根本没到按钮（被更上层命中对象拦截），属另一个问题。

### 未覆盖的同根因站点（本轮范围外）

本轮只改 `StudioRailIconButton`，覆盖：桌面/紧凑工具栏全部按钮、笔盒与图形弹层全部条目。
以下编辑器内控件仍是 `IconButton`/`InkWell`/`IconToggleChip`（同样依赖竞技场，触控笔遇到
引擎 cancel 会同样失效，但不在本次反馈范围内）：

- `zoom_controls`（撤销/重做/缩放）、`hamburger_menu`、`help_button`、`theme_buttons`；
- `library_panel` / `compact_library`（素材库）、`compact_menu`、`canvas_background_picker`；
- `find_overlay`、`link_overlay`、`property_panel_content`（属性面板 chips 与按钮）、
  `toggle_chips`（`IconToggleChip`）。

若真机复验显示这些控件也有同类现象，可按同一模式（提取原始指针通道到共用基件）扩展。

## 遗留与后续

- `editor_core` 之外仍有 31 处框架 `Tooltip`（白板 feature 内 8 处：AI 助手对话框、
  区域截取、排版面板/模板表、whiteboard_page；其余 feature 23 处）。
  这些同样具备"气泡吞点击"的机制，但布局多为横向行（探针证明当前不受影响）；
  若后续出现同类现象，按同一模式替换为 `HoverTooltip`。
- 第三轮的原始指针通道目前只落在 `StudioRailIconButton`；若要覆盖其余编辑器控件，
  先按上一节的清单评估，不要在没有真机证据时扩大手势层改动。

## 关联

- 分支：`fix/toolbar-stylus-double-tap`
- 首轮提交：`36bbb38`（`triggerMode: manual`，无效）
- 第二轮提交：`c1c00ff`（自绘 `HoverTooltip`）、`c4ba847`（输入诊断与回归）
- 涉及框架源码：`packages/flutter/lib/src/widgets/raw_tooltip.dart`
  (`_ExclusiveMouseRegion`、`build`、`_RenderTheater.hitTestChildren`)、
  `packages/flutter/lib/src/material/tooltip.dart`（`_defaultVerticalOffset = 24`）
- 第三轮涉及框架源码：`packages/flutter/lib/src/gestures/binding.dart`
  （`_handlePointerEventImmediately`，cancel 移除命中缓存后 up 不再派发）、
  `gestures/tap.dart`（`BaseTapGestureRecognizer`，`deadline=kPressTimeout`、
  cancel → `resolve(rejected)` + `_reset()`）、`gestures/recognizer.dart`
  （slop 检查只在 move 事件上）、`gestures/constants.dart`（`kTouchSlop = 18`）
