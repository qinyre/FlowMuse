# Issue #31 工具栏触控笔点击：诊断与修复计划

## Context

- 任务：触控笔点选白板工具时偶发第一次未成功，接续此前两次修复。分析与本计划由 GPT-6 Astra（medium）完成，代码与回归测试由 GPT-5.6 Luna（xhigh）严格按本计划实施。
- 勘察基线：分支 `fix/toolbar-stylus-double-tap`，HEAD `c1c00ff`；此前 `36bbb38` 将 Tooltip 长按改为 manual，`c1c00ff` 将编辑器提示替换为 `HoverTooltip`。
- 已读根 AGENTS、`.agent/conventions.md`、`.agent/architecture.md`、ADR-005/008、需求 §4.1、架构约束、既有 stylus-touch-pan 计划及 issue #31 排障文档。`rg --files -g AGENTS.md` 未发现嵌套指令。
- 工作区已有用户修改：`FlowMuse-App/tool/vendor/path_provider_ohos/ohos/BuildProfile.ets`、同目录 `oh-package-lock.json5`；不得覆盖、格式化或纳入本次业务修复。
- 父任务已跑现有悬停和压感语义测试，13/13 通过；全量基线检查由父任务统一完成。

## 需求与范围

1. 合法的一次笔尖点击执行目标动作一次，鼠标、手指、键盘与无障碍激活不退化。
2. 取消、移出、滚动与禁用状态不得误触发；不可用“down 就执行”掩盖点击取消。
3. 继续保留既有 HoverTooltip 的提示与穿透；不再全编辑器替换控件。
4. 保留画笔产品语义：首次选择打开笔型面板；已有笔型时从其他工具回到上次笔型；已处于画笔时再次点击打开笔盒。这是需求明确行为，不是漏点。
5. 不改场景模型、协议、数据库、画笔滤波、原生/SDK/vendor 或全应用手势参数。

## 证据与根因边界

### 已证明的代码链

| 环节 | 已核对内容 | 对判断的含义 |
| --- | --- | --- |
| 入口 | DesktopToolbar、CompactToolbar 的按钮共同使用 StudioRailIconButton；均位于 SingleChildScrollView 中 | 必须在真实滚动祖先内测，孤立按钮通过不能代表工具栏通过 |
| 调色/图形条目 | toolbar_palette_buttons.dart 同样复用 StudioRailIconButton，经 showAnchoredPopupMenu/showMenu 打开 | 需要真实 PopupRoute 测试；外部点击被模态 barrier 消耗属菜单机制，不能误称笔尖丢失 |
| 点击 | StudioRailIconButton：HoverTooltip → Material → Ink → InkWell.onTap | 当前仅依赖标准 TapGestureRecognizer；未看到业务防抖、延迟或第一次工具切换丢弃 |
| 工具切换 | switchTool 同步更新 activeToolType 并 notifyListeners；只读模式/智能排版草稿有明确禁止条件 | 测试必须断言 controller 状态及按钮选中状态，不能只数 callback |
| 画布 | EditorCanvas 的 Listener 与工具栏是 Stack 的不同子树 | InputPolicySelector、压感和笔迹滤波不在按钮点击链路，不应改这些模块 |
| 提示 | HoverTooltip 气泡已包 IgnorePointer，全局 down 只隐藏气泡 | 原来的“气泡遮挡”不能直接解释这次剩余失败 |

### 本机 Flutter SDK 的反证

已读 `F:/Environment/flutter/packages/flutter/lib/src/gestures/{events,tap,converter}.dart`：

- `computeHitSlop(stylus/invertedStylus)` 使用 `gestureSettings.touchSlop ?? kTouchSlop`，默认 18 logical px；只有 mouse 是 1 px。禁止以“触控笔默认 1px 太敏感”为理由改阈值。
- TapGestureRecognizer 的 down 要求可识别的按钮组合，move 的 `buttons != down.buttons` 会取消；但 converter 已为 stylus/invertedStylus 的零 buttons down/move 补 primary。不能把人工构造的 `buttons: 0` 直接注入 widget 所得失败当成真机证据。
- 鸿蒙 SDK 的 `ohos_touch_processor.cpp` 正常笔尖 down/move 设置 contact 位。本次不能以猜测写 engine/vendor 补丁。
- 当前没有用户失败时的原始事件轨迹，无法唯一证明剩余真机根因。前两轮的测试只证明各自机制，不证明此次用户失败由该机制产生。

### 待验证假设（按优先级）

1. 真实祖先/路由中的重建或手势竞争，使 down 命中按钮但 tap 被取消。
2. 悬停引起的 overlay 生命周期问题：新菜单/按钮在静止笔尖下出现时，MouseTracker 帧末 enter 调用 `_show`，直接 insert 是否触发构建时序错误；控件移除、路由切换是否产生悬停或 overlay 残留。
3. 实际输入含过阈值位移、按钮位变化、系统 cancel、并发触摸或缺失 down/up。需要事件证据再决定适配策略。
4. 点击到按钮间隙、打开的菜单 barrier，或画笔的既有二阶段语义被当成丢点。必须在测试/真机记录中区分。

## 实现方案与严格门禁

### P1：先补实际交互复现，不先改识别行为

允许新增 `FlowMuse-App/test/features/whiteboard/editor_core/ui/toolbar_stylus_interaction_test.dart`，复用现有测试的 MaterialApp/Scaffold、MarkdrawController、StudioRailIconButton finder。

分别挂载 DesktopToolbar（top/left/right）和 CompactToolbar，使用 ListenableBuilder 监听真实 controller，保持真实 SingleChildScrollView；增加笔盒、图形的真实菜单路径。统一释放 controller 和 TestGesture。

必须覆盖：

- 笔悬停 A 后一笔点击 B、无悬停点击、带小幅往返移动（如 2/6/12px，保持按钮内）、700ms 按压；一次动作成功且只通知一次相应动作。
- mouse/touch/stylus/invertedStylus 的普通点击对照；按钮禁用、cancel、移出/超阈值拖动不得执行。
- 快速从画布结束笔划后切工具、不同按钮连续点选；同一个 stylus device、不同 pointer 生命周期。
- 真实滚动工具栏中的明确拖动滚动（至少远超 slop），不得切工具；触摸滚动保留。
- 打开笔盒选一次笔型、打开形状菜单选一次图形，断言 controller 的结果；笔型首次/恢复/再次打开三种需求分别断言。
- 悬停笔保持静止时替换/移动其下方按钮、打开/关闭菜单、卸载悬停目标；断言 tester.takeException 为空、提示无残留、下一次点击正常。
- 次指针 touch 按住后主笔点击/取消的隔离对照；不直接预设必须绕过 arena。

任何失败先记录：测试名、完整输入序列、基线实际结果、期望产品语义。只修违反有效语义的失败，不能把标准取消/滚动设计误判为缺陷。必须保留修复前失败与修复后通过证据。

### P2：按证据执行最小修复

以下是预先允许的有界分支，实施者不能任意扩大：

**A. 若复现 HoverTooltip 生命周期错误**：仅改 `hover_tooltip.dart`，复用 `shared/utils/ui_lifecycle.dart` 的安全插入工具。状态明确区分待插入和已插入；离开/down/dispose 取消待插入请求，帧后回调校验 mounted 和请求身份；已插入 entry 才 remove，适时 dispose；不能让快速 enter→exit 后的回调重新弹泡。保持 IgnorePointer 和 Semantics，不引入全局延迟或 timer。加针对性回归测试到现有 `stylus_hover_tooltip_tap_test.dart`。

**B. 若复现有效笔尖点击被滚动/按钮识别竞争取消**：先记录 SDK 决策及父 recognizer。只在编辑器 UI 局部复用一个可测试的输入封装（候选 `src/ui/stylus_tap_target.dart`），由 StudioRailIconButton 接入；不复制到每个 toolbar。必须仍参与 gesture arena，并在 up 时确认成功，保留滚动、取消、禁用、键盘、无障碍以及单次派发。没有证据不得改 slop、禁止 stylus 滚动，或添加原始 Listener fallback 二次触发。若需要超出上述范围的新策略，先交回 Astra 更新本计划，再让 Luna 实施。

**C. 若没有违反语义的本地失败**：不虚构修复，执行 P3 可复验诊断；已证明且测试覆盖的生命周期缺陷仍可按 A 修复。报告区分“已修复的代码缺陷”与“尚待真机确认的 issue 根因”。

### P3：补齐真机定位能力（本地无法复现时必须）

允许新增 `src/ui/toolbar_input_diagnostics.dart`，在 StudioRailIconButton 的原始 pointer 和 InkWell tapDown/tapUp/tapCancel/onTap 接入；如需判断 down 是否被遮挡，在该诊断组件挂载期间添加受控全局 route，以目标 render box 边界判断是否落在该按钮范围。不得改变命中、手势竞争与现有 callback。

- 编译期开关 `const bool.fromEnvironment('FLOWMUSE_TOOLBAR_INPUT_DIAGNOSTICS')`，默认 false；false 路径不注册全局路由，不持续收集或写盘。
- 仅 `debugPrint('[FlowMuseCreateNote] toolbar-input ...')`，允许字段：固定控件标识、事件类型、pointer/device/kind/buttons、相对按下位置的位移、相对时间、down/up/cancel/tap 阶段。禁止屏幕/画布绝对坐标、用户文本、白板内容和任何协作标识/密钥。
- 全局 route 与 pending 状态随 dispose 清理；全局与局部记录必须可区分，用来判别“按钮范围内但未命中”与“已命中后 tap 取消”。不在生产默认路径增加每个移动事件的输出。
- 测试开关开启时的日志字段、取消记录、卸载后不再回调以及开关关闭无日志；测试注入 sink 或受控编译配置，避免生产公开额外 API。
- 未定位真机根因前，不能宣称 issue #31 已彻底解决；交付可执行诊断命令和最短复验步骤。

## 关键文件与允许范围

| 文件 | 处理 |
| --- | --- |
| `.../src/ui/studio_rail_icon_button.dart` | 仅证据支持的点击适配或受控诊断接入 |
| `.../src/ui/hover_tooltip.dart` | 仅 P2-A 复现证明的生命周期修复 |
| `.../src/ui/toolbar_input_diagnostics.dart` | P3 的最小诊断组件；按需新增 |
| `.../src/ui/stylus_tap_target.dart` | 仅 P2-B 门禁通过后按需新增 |
| `.../test/.../ui/toolbar_stylus_interaction_test.dart` | 真实工具栏/菜单回归 |
| `.../test/.../ui/stylus_hover_tooltip_tap_test.dart` | 生命周期回归；保留已有悬停穿透测试 |
| `.../test/.../ui/studio_rail_icon_button_test.dart` | 必要输入回归；修正未经证明的根因表述 |
| `docs/研发记录/troubleshooting/2026-09-17-issue-31-stylus-tooltip-tap-eaten.md` | 把“已修复”改为与本次证据一致的状态，追加确定事实和真机待验边界 |
| 本计划 | 记录实施步骤/结果；新增方案须先由 Astra 修订 |

以上 `.../src/ui` 前缀为 `FlowMuse-App/lib/features/whiteboard/editor_core`；测试前缀为 `FlowMuse-App/test/features/whiteboard/editor_core`。

不修改需求中的笔型交互，不改 DesktopToolbar/CompactToolbar 排布和视觉尺寸，不改 controller 的工具切换契约。若回归暴露必须修改其他文件，实施者先回报证据及拟改文件，不能自行越界。

## 验证方案与验收

1. 先运行新复现测试并保留基线结果，再落业务补丁；格式化仅本次 Dart 文件。
2. 相关测试：`flutter test test/features/whiteboard/editor_core/ui`，补跑本次直接受影响模块测试。
3. 完成 `flutter analyze` 和全量 `flutter test`，历史失败与新增失败分别记录；父任务统一核对日志，不凭历史文档数字报告通过数。
4. 检查 `git diff --check`、工作区差异，用户两个 vendor 文件保持原修改，禁止生成文件混入。
5. 跨端：仅 Flutter 公共 API、不依赖 dart:io/Platform、不改所有 pointer 的 SDK 参数；mouse/touch/keyboard/semantics 回归必须通过。未改原生插件无须伪造 hap 构建证据；若实际为真机提供 HAP，构建和安装结果单独记录。
6. 真机矩阵：目标设备上 top/left/right 工具栏各做“悬停相邻按钮→一次点选”30次，笔盒/图形各20次，分别覆盖普通点击与稍长按压，穿插画布书写→切工具→书写；每次核对选中反馈和实际工具效果。再测手指及鼠标对照、取消和滚动无误触发。保留设备/系统/构建版本和失败事件关联，不记录白板内容。

最终报告必须给出：已证明缺陷、修复范围、回归结果、是否在原失败设备复验、尚未解决的外部依赖。单纯模拟测试通过不能宣称原真机现象消失。若三轮仍无可解释改善，遵守 AGENTS §11 停止盲补，提交诊断事实讨论输入架构边界。

## 实施步骤

- [x] Astra medium 勘察、事实核对与详细计划落盘。
- [x] 按计划完成 P1：真实 DesktopToolbar/CompactToolbar、三种停靠、长按/多指针对照、取消/滚动与笔盒/图形弹层测试通过；本机未复现违反产品语义的丢点。
- [x] P2 门禁结论为不添加猜测性点击适配；按 P3 加入默认关闭的工具栏输入诊断。
- [x] 同步排障文档；相关 UI 测试 42 项与诊断回归 7 项通过，`flutter analyze` 通过，`flutter test` 全量 1681 项通过。
- [x] 父任务核对计划执行边界、跨端影响和用户已有 vendor 修改未被触碰。
- [ ] 真机按矩阵复验或明确标为未执行并提供诊断步骤。
