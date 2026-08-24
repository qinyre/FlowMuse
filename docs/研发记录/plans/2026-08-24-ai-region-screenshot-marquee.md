# AI 手动框选截图（Region Capture）执行计划

> 分支：`feature/ai-visual-attachment`（在 AI 视觉附件功能之上迭代）
> 定位：把「选区截图」从"捕获选中元素包围盒"升级为"点击后像系统截图工具一样手动拖矩形框选"。
> 核心决策（已与项目方确认）：**统一走应用内方案（方案 B），不做鸿蒙原生截屏增强**；交互与 4.12 节既有"选区截图"语义平滑替换，PDF 页 chip、快捷指令、被动捕获链路保持不变。

## 0. 事实基线（撰写本文时逐行核实）

| 主题 | 事实 | 位置 |
|---|---|---|
| 页面结构 | `Scaffold > body: SafeArea(bottom:false) > MarkdrawEditor(...)`，**无 Stack** | `whiteboard_page.dart:2014-2018` |
| AI 面板挂载 | 根 Overlay `OverlayEntry`，builder 用 `MediaQuery.sizeOf` 定位的 `Positioned + Material + AiAgentPanel` | `whiteboard_page.dart:604-654` |
| 面板 chips | 「选区截图」chip 现走 `_captureAndApply(capture: widget.onCaptureSelection!, scene: _AiCaptureScene.manual)`，**直接捕获选中元素** | `ai_agent_dialog.dart:798-816` |
| 面板新参数插点 | `AiAgentPanel` 构造参数列表（chip 区上方无其他依赖） | `ai_agent_dialog.dart:80-95` |
| 捕获管线 | `captureSelectionAttachment(controller)`：守卫(选中且含非文本)→`ExportBounds.compute`→`prewarmRegionImages`→`exportRegionPng`→`normalizeAttachmentPng`→`AiVisualAttachment` | `visual_attachment_capture.dart:96-131` |
| 导出能力 | `exportRegionPng(Rect sceneBounds)` 任意场景矩形；`prewarmRegionImages(Rect)` 任意矩形且失败计数 | `markdraw_controller.dart:5646,5714` |
| 坐标换算 | `ViewportState.screenToScenePrecise(Offset)`（非量化噪声版） | `viewport_state.dart:45-50` |
| 导出/校验限制 | 最长边 ≤1568px、≤3 张、单张 ≤4MiB、PNG 魔数+chunk 纯净性 | `ai_visual_attachment.dart:4-6`；`visual_attachment_capture.dart:12` |
| 面板空态提示 | 手动 chip 捕获返回 null → `_attachmentNotice = '当前选区没有可截图的视觉内容'`（内联，非错误容器） | `ai_agent_dialog.dart:353-357` |
| 已有 marquee 视觉 | 仅 select_tool 内部自绘（`SelectionRenderer.drawMarquee`），**不以组件资产暴露**；本方案自绘虚线+回形遮罩，不依赖 | `selection_renderer.dart:217-226` |
| 测试基础设施 | `test/features/whiteboard/ai_assistant/` 平铺 4 文件；widget 测试用 fake repository + Completer 范式 | `ai_agent_dialog_test.dart` |
| barrel | `ViewportState` 经 `editor_core/markdraw.dart:30` 导出，ai_assistant 可经 `flow_muse_whiteboard_editor.dart` 导入 | 已核实 |

## 1. 需求

1. **仅修改「选区截图」chip 行为**：点击进入"截图模式"——AI 面板暂时隐藏（保持状态），画布上方出现全屏遮罩层；用户用手指/手写笔拖动一个矩形框；松手即框选区生成附件并加入附件条，面板恢复原状。
2. **框选范围 = 用户画出的任意矩形**，与"元素是否被选中"无关；可框住空白背景区域（导出为背景色）。
3. **截图模式期间屏蔽一切画布输入**（不可平移/缩放/编辑），保证图与所见一致。
4. **取消**：截图模式工具栏提供「取消」按钮；无矩形或矩形过小（<16 逻辑像素宽或高）时不触发导出，模式保留供重新框选。
5. **错误语义**：与现有手动链路一致——捕获失败走错误容器（`_error`），用户取消不提示、静默返回。
6. **不破坏既有链路**：开面板被动捕获、快捷指令刷新、PDF 页 chip、文字上下文快照、附件条增删/上限、追问重发、清除对话全部保持原有行为；`showAiAgentDialog` 不传新参数时零回归。

## 2. 实现方案

### 2.1 关键不变量（跨端基础）

- 截图覆盖层以 **Stack 兄弟节点**放在 `MarkdrawEditor` 同一层（`SafeArea` 内），覆盖层 local 坐标 == 画布 local 坐标，`viewport.screenToScenePrecise` 无需任何换算。**禁止**把覆盖层放进根 Overlay（坐标系不对，且面板同级问题）。
- 期间画布输入屏蔽由覆盖层的 `HitTestBehavior.opaque` 手势层天然完成，**无需**在编辑器侧加"锁定模式"。
- 截图期间视图被冻结：静止不动，松手时一次性读 `controller.editorState.viewport` 计算场景矩形，无竞态窗口。

### 2.2 模块与数据流

```
【面板 chip】 onPressed → widget.onRegionCapture()  (page 级回调，返回 Future<AiVisualAttachment?>)
　　　　↓
【page._startRegionCapture()】 setState(_aiCaptureModeActive=true) → markNeedsBuild(隐藏面板)
　　　　↓  (Completer 挂起)
【RegionCaptureOverlay】(Stack 内) 拖矩形成矩形；onCommit(Rect screenRect) / onCancel()
　　　　↓
【page】 screenRect →(viewport.screenToScenePrecise)→ sceneRect → captureSceneRectAttachment(controller, sceneRect)
　　　　↓  (附件 or 异常)
　　Completer.complete(attachment) / completeError(error) / complete(null 取消)
　　　　↓
【finally】 _aiCaptureModeActive=false → markNeedsBuild(恢复面板)
【面板 chip _addRegionAttachment()】 await 结果：非 null → 加入 _attachments；null → 静默；异常 → _error
```

- **坐标换算为纯函数** `sceneRectFromScreenRect(ViewportState, Rect)`，放 `visual_attachment_capture.dart`（可单测）。
- **捕获管线收敛为私有共享函数** `_renderSceneRectAttachment(controller, sceneRect)`，`captureSelectionAttachment`（元素路径，保留）与新 `captureSceneRectAttachment`（矩形路径）共同复用，避免复制 prewarm/fail/export/normalize 序列。

### 2.3 交互细节

- 覆盖层视觉：矩形外区域半透明黑遮罩（回形），矩形内虚线蓝框（参照 `SelectionRenderer` 配色：边框 `0xFF4A90D9`、填充 `0x114A90D9`、遮罩黑 55%）；顶部工具栏「✕ 取消」+ 引导文案「拖动框选要发送的内容」。
- 松手时矩形宽/高任一 <16 逻辑像素 → 显示内联提示「矩形太小，请重新框选」，保留模式，**不触发** `onCommit`。
- 多指/负值方向：用 `Rect.fromPoints` 归一化；`onTapUp` 无拖动不触发。
- 导出失败（prewarm 失败/export null/归一化超限）→ 异常冒泡，面板错误容器展示既有文案（不改文案）。

### 2.4 关于「截到面板」的说明

截图期间面板隐藏（`Visibility(maintainState: true)`，保持 State 不销毁），因此底图**不会**包含 AI 面板；工具栏（桌面/紧凑工具条、滚动条、缩放控件等）仍在画布 Stack 内会被框入或遮罩——这是"真实画布"语义，与 PDF/封面缩略图一致（非本次改动范围）。

## 3. 关键文件

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/features/whiteboard/ai_assistant/repositories/visual_attachment_capture.dart` | 修改 | 新增纯函数 `sceneRectFromScreenRect`；提取共享私有 `_renderSceneRectAttachment`；新增公开 `captureSceneRectAttachment(controller, Rect)` |
| `lib/features/whiteboard/ai_assistant/views/region_capture_overlay.dart` | 新建 | 截图模式覆盖层：遮罩+回形+虚线框绘制、拖框手势状态机、尺寸守卫、取消按钮、内联提示 |
| `lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart` | 修改 | 面板新增 `onRegionCapture` 参数；「选区截图」chip 改走 `_addRegionAttachment()`（wait 后自行加入附件条）；隐私文案补「框选截图」说明 |
| `lib/features/whiteboard/views/whiteboard_page.dart` | 修改 | `MarkdrawEditor` 外包 `Stack` 挂覆盖层；`_aiCaptureModeActive` 状态与「隐藏/恢复面板」；`_startRegionCapture()`/`_handleRegionSelected()`/`_handleRegionCancel()` |
| `test/features/whiteboard/ai_assistant/visual_attachment_capture_test.dart` | 修改 | `sceneRectFromScreenRect` + `captureSceneRectAttachment` 用例 |
| `test/features/whiteboard/ai_assistant/region_capture_overlay_test.dart` | 新建 | 覆盖层手势/视觉/回调/尺寸守卫用例（注入回调，不触发真实渲染管线） |
| `test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart` | 修改 | chip 新行为、`onRegionCapture` 空参零回归、附件加入/取消/错误用例 |
| `docs/项目说明/项目需求.md` | 修改 | 4.12 节更新「框选截图」语义 |
| `README.md` | 修改 | 核心能力清单补一句 |

## 4. 验证方案

1. `cd FlowMuse-App && flutter analyze`——不得新增 error。
2. `flutter test test/features/whiteboard/ai_assistant`——全部通过（含既有 100+ 用例回归）。
3. `flutter test` 全量——无回归。
4. 手动回归（每条必测）：
   - 选中手写笔迹（FreedrawElement）→ 点「选区截图」→ 出现截图模式 → 拖框 → 附件「框选截图」加入附件条并发给模型（用 gpt-4.1-mini 等视觉模型）。
   - **不做任何选中**同样可框选（与旧行为的关键差异）；框到空白区 → 附件为背景色。
   - 截图模式期间平移/缩放/点工具**全部失效**；「✕ 取消」静默退出且无附件。
   - 拖极小矩形 → 内联提示且模式保留。
   - 面板隐藏期间 `_attachments` 不丢；框选完成后面板原样恢复（会话、回复、指令输入框不动）。
   - 快捷指令（「识别/梳理」等）仍按选中元素自动捕获；PDF 页 chip 不变；清除对话清空附件；追问保留附件。
   - 6 端冒烟：Android / iOS / macOS / Windows / Web（CORS 权限同现状）/ 鸿蒙（`flutter build hap` 通过；真机验证交验收，计划内不承诺）。

## 5. 实施步骤（TDD，每步含验证命令）

### T1：捕获层纯函数 + 共享渲染管线

**文件**
- 修改 `lib/features/whiteboard/ai_assistant/repositories/visual_attachment_capture.dart`
- 修改 `test/features/whiteboard/ai_assistant/visual_attachment_capture_test.dart`

1. 在捕获文件新增：

```dart
/// 画布局部（覆盖层 local 坐标）矩形 → 场景矩形。
/// 与画布同层 Stack 时覆盖层 local 坐标即画布 local 坐标（§2.1 不变量）。
Rect sceneRectFromScreenRect(ViewportState viewport, Rect screenRect) {
  final topLeft = viewport.screenToScenePrecise(screenRect.topLeft);
  final bottomRight = viewport.screenToScenePrecise(screenRect.bottomRight);
  return Rect.fromPoints(topLeft, bottomRight);
}
```

2. 提取共享管线并新增公开捕获函数：

```dart
/// 捕获任意场景矩形（框选截图入口）。与 [captureSelectionAttachment] 共享管线。
Future<AiVisualAttachment?> captureSceneRectAttachment(
  MarkdrawController controller,
  Rect sceneRect,
) async {
  if (sceneRect.width < 0.5 || sceneRect.height < 0.5) return null;
  return _renderSceneRectAttachment(controller, sceneRect);
}

/// 共享私有管线：预热 → 导出 → 归一化 → 附件。失败抛 StateError（文案复用现语义）。
Future<AiVisualAttachment?> _renderSceneRectAttachment(
  MarkdrawController controller,
  Rect sceneRect,
) async {
  final failedImages = await controller.prewarmRegionImages(sceneRect);
  if (failedImages > 0) {
    // _failed 集合本会话粘性（image_cache.dart 不清理），"重试"无法兑现，
    // 文案如实指向重开笔记。
    throw StateError('图片解码失败，请重新打开笔记后重试');
  }
  final png = await controller.exportRegionPng(sceneRect);
  if (png == null) throw StateError('截图生成失败，请重试');
  final normalized = await normalizeAttachmentPng(png);
  return AiVisualAttachment(
    sourceLabel: '框选截图',
    mimeType: 'image/png',
    bytes: normalized,
    kind: AiVisualAttachmentKind.selection,
  );
}
```

3. `captureSelectionAttachment` 体内替换为（守卫 + bounds 不变，尾部改调共享管线）：

```dart
  final rect = ui.Rect.fromLTWH(...); // 现 :110-115 原样保留
  return _renderSceneRectAttachment(controller, rect);
```
（即删除其内部 prewarm/failed/export/normalize 五段，消除重复。）

4. 测试用例（追加到既有测试文件，用现有 `MarkdrawController`+`loadScene` 范式；无图片场景返回 0 失败、不触 toImage 假异步问题——导出在 `test()` + `TestWidgetsFlutterBinding.ensureInitialized()` 下已获既有 `export_region_png_test.dart` 背书）：

| # | 用例 | Given / When / Then |
|---|---|---|
| 1 | 纯函数换算（zoom=2, offset=(10,20)） | `sceneRectFromScreenRect(ViewportState(offset: const Offset(10,20), zoom: 2), Rect.fromLTWH(0,0,100,100))` → `Rect.fromLTWH(10,20,50,50)` |
| 2 | 纯函数反向拖拽归一化 | 拖拽方向左上→右下与右上→左下（`Rect.fromLTWH(100,100,-50,-50)` 语义）→ `Rect.fromPoints` 结果宽高均为正且等价 |
| 3 | 非整数换算无量化 | zoom=1.7 时 100×100 矩形 → 结果宽高 ≈ 58.8235294…（`fromPoints`/`moreOrLessEquals` 断言，避免 `screenToScene` 的 round） |
| 4 | 捕获成功（文本元素区域） | controller `loadScene` 含 1 个 `TextElement(0,0,100,50)`；`captureSceneRectAttachment(controller, Rect.fromLTWH(-8,-8,116,66))` → 非 null、PNG 签名、sourceLabel=='框选截图'、kind==selection |
| 5 | 零宽/零高返回 null | `captureSceneRectAttachment(controller, Rect.fromLTWH(0,0,0,10))` → null（不抛）|
| 6 | 损坏图片侦测失败 | 场景含指向损坏 bytes 的 ImageElement（经 `applyResult(AddFileResult/AddElementResult)` 注入，勿用 loadScene，理由同 `export_region_png_test.dart:796` 注）→ `throws StateError('图片解码失败，请重新打开笔记后重试')` |
| 7 | 元素路径回归 | `captureSelectionAttachment` 空选区返回 null 且报错文案不变（既有用例保持通过） |

5. `flutter test test/features/whiteboard/ai_assistant/visual_attachment_capture_test.dart` 全绿；提交 `feat:AI框选截图捕获管线与场景矩形换算`。

### T2：截图模式覆盖层组件

**文件**
- 新建 `lib/features/whiteboard/ai_assistant/views/region_capture_overlay.dart`
- 新建 `test/features/whiteboard/ai_assistant/region_capture_overlay_test.dart`

组件骨架（公开接口 → 测试锚点）：

```dart
/// 截图模式覆盖层。仅做手势/视觉，**不**认识 controller——
/// 坐标换算与导出由调用方（whiteboard_page）执行。
class RegionCaptureOverlay extends StatefulWidget {
  const RegionCaptureOverlay({
    super.key,
    required this.onCommit,   // Rect screenRect → Future<void>；页面负责换算+导出+关闭
    required this.onCancel,   // VoidCallback；页面负责取消+关闭
  });
  final Future<void> Function(Rect screenRect) onCommit;
  final VoidCallback onCancel;
  ...
}
```

内部实现要点：
- `Listener`（`behavior: HitTestBehavior.opaque`）只监听 `PointerDown/Move/Up`：down 记 `_start`；move 更新 `_current` 并 `setState` 重画；up 时 `Rect.fromPoints(start,current)`，若宽或高 <16 则 `setState(_hint='矩形太小，请重新框选')` 不提交，否则 `await widget.onCommit(rect)`（期间 `_committing=true` 禁止重复提交）。
- 视觉：`CustomPaint` 全屏；`_paint`：外区 55% 黑遮罩（`Path.evenOdd` 回形：外矩形路径 + 内矩形路径，`fillType: PathFillType.evenOdd`+`drawPath`）；内矩形 dashed 蓝框（`_dashPath`：边 8 实 6 空，遍历四边绘制）；无矩形时纯遮罩。
- 顶部 `SafeArea` 内一条工具栏：提示文本「拖动框选要发送的内容」+ 若 `_hint!=null` 替换显示 `_hint`；右侧「✕ 取消」`IconButton` → `widget.onCancel()`（`_committing` 期间 `onPressed: null`，与测试用例 5 一致）。
- `_committing || _start == null` 时手势层仍 opaque（防穿透），取消按钮始终可点。

测试用例（`testWidgets`，注入回调断言，不触碰引擎）：

| # | 用例 | Given / When / Then |
|---|---|---|
| 1 | 拖动产生矩形并提交 | `onCommit` 记录；`tester.drag(find.byType(RegionCaptureOverlay), Offset(100,80))` → onCommit 调用 1 次，rect ≈ `Rect.fromLTWH(起点,100,80)`（忽略 down 位移阈值，drag 起点为覆盖层中心） |
| 2 | 反向拖拽归一化 | 自 (50,50) 拖到 (200,150)：onCommit rect 为 `Rect.fromLTWH(50,50,150,100)`（Rect.fromPoints 保证） |
| 3 | 过小矩形不提交并提示 | 拖 8×8 → onCommit 调用 0 次、`find.text('矩形太小，请重新框选')` 出现 |
| 4 | 取消按钮 onCancel | tap ✕ → onCancel 调用 1 次 |
| 5 | 提交期间屏蔽重复与取消 | `onCommit` 返回挂起 Future（Completer）→ 再次拖动不触发第二次调用、✕ 不可点（`_committing` 期间禁用，消除"提交中取消→Completer 已 completed"竞态） |
| 6 | 无输入时仅遮罩 | 无手势 → 无 onCommit/onCancel；`CustomPaint` 存在 |
| 7 | 预提交矩形可见 | 拖动中途 `pump` → 出现虚线框 paint（canary：`find.byType(CustomPaint)` 且不打错）——**只做存在性断言，不做像素级验证** |

运行：`flutter test test/features/whiteboard/ai_assistant/region_capture_overlay_test.dart`；提交 `feat:AI截图模式覆盖层（回形遮罩+拖框提交）`。

### T3：面板接线（chip 行为切换）

**文件**
- 修改 `lib/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart`
- 修改 `test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`

1. `AiAgentPanel` 新增参数（默认 null 零回归）：

```dart
this.onRegionCapture, // Future<AiVisualAttachment?> Function()?
...
final Future<AiVisualAttachment?> Function()? onRegionCapture;
```

`showAiAgentDialog` 不传。

2. 新增私有方法：

```dart
Future<void> _addRegionAttachment() async {
  if (_loading || _applying || _capturing) return;
  if (_attachments.length >= maxAiVisualAttachments) {
    setState(() => _attachmentNotice = '最多添加 $maxAiVisualAttachments 张图片');
    return;
  }
  setState(() {
    _capturing = true;
    _attachmentNotice = null;
  });
  try {
    final attachment = await widget.onRegionCapture!();
    if (attachment != null && mounted) {
      setState(() => _attachments = [..._attachments, attachment]);
    }
  } catch (error) {
    if (mounted) setState(() => _error = _errorMessage(error));
  } finally {
    if (mounted) setState(() => _capturing = false);
  }
}
```

3. 「选区截图」chip 改绑（`:798-816`）：渲染门控扩为 `widget.onCaptureSelection != null || widget.onRegionCapture != null`，`onPressed` 门控不变（`_loading || _applying || _capturing || 满额`），回调改为：

```dart
onPressed: _loading || _applying || _capturing ||
        _attachments.length >= maxAiVisualAttachments
    ? null
    : () => unawaited(
        widget.onRegionCapture != null
            ? _addRegionAttachment()
            : _captureAndApply(
                capture: widget.onCaptureSelection!,
                scene: _AiCaptureScene.manual,
              ),
      ),
```

即：**chip 优先走用户手势模式（`_addRegionAttachment`）**；当 `onRegionCapture == null`（`showAiAgentDialog` 旧调用方）时回退既有元素捕获路径——这是零回归锚点。

> 边界：`captureSelectionAttachment` 不再被 chip 调用，但**仍被**开面板被动捕获与快捷指令使用（`AiAgentPanel` 仍收到页面传的 `onCaptureSelection`，见 T4）；T1 的回归用例 7 锁定。

4. 隐私文案（`:952-958` 处）在既有文案中补充：「框选截图包含框内全部可见内容」，其余字样不动。

5. 测试增补：

| # | 用例 | Given / When / Then |
|---|---|---|
| 1 | 不传 `onRegionCapture` 与旧相机回调时 chip 仍渲染且走旧路径 | 现有 `_openDialog`（既有 fake 回调）→ 点「选区截图」→ 行为同改前（既有用例全部保持通过，零回归锚点） |
| 2 | 传 `onRegionCapture` 后点击 → 附件加入 | fake 返回 `AiVisualAttachment('框选截图',+PNG 基准字节)` → tap chip → pumpAndSettle → Image.memory 出现、'框选截图' 标签、隐私文案计数 '1 张' |
| 3 | 返回 null 静默 | fake 返回 null → tap → 无附件、无 notice、无 error |
| 4 | 抛错走错误容器 | fake 抛 `StateError('请先在画布选中要发送的内容')`→ tap → `_error` 容器含文案 |
| 5 | 满额禁用 | 先注满 3 张 → chip `onPressed == null` |
| 6 | 追问重发不变 | 附件随 `repository.run(attachments:)` 发送（既有用例保持，`_FakeAiAgentRepository` 同步） |

运行：`flutter test test/features/whiteboard/ai_assistant/ai_agent_dialog_test.dart`；提交 `feat:AI面板选区截图改为框选截图模式入口`。

### T4：白板页接线（覆盖层 + 面板隐藏交互）

**文件**
- 修改 `lib/features/whiteboard/views/whiteboard_page.dart`

1. 新增状态字段（page 类内，`_aiPanelEntry` 旁）：

```dart
bool _aiCaptureModeActive = false;
Future<AiVisualAttachment?>? _regionCaptureCompleterFuture;
Completer<AiVisualAttachment?>? _regionCaptureCompleter;
```

2. `_toggleAiAgent` 的 `AiAgentPanel(...)` 构造（`:628-644`）新增：

```dart
onRegionCapture: () => _startRegionCapture(),
```

3. 面板条目 builder 包裹 `Visibility`（`:618-645` 处 `Positioned` 内）：

```dart
child: Visibility(
  visible: !_aiCaptureModeActive,
  maintainState: true,
  maintainAnimation: true,
  child: Material(...AiAgentPanel...),
),
```

4. body 包 Stack（`:2016-2018`）：

```dart
body: SafeArea(
  bottom: false,
  child: Stack(
    children: [
      MarkdrawEditor(...),  // 现参数原样（含 controller）
      if (_aiCaptureModeActive)
        RegionCaptureOverlay(
          onCommit: _handleRegionSelected,
          onCancel: _handleRegionCancel,
        ),
    ],
  ),
),
```

5. 新增页面方法：

```dart
Future<AiVisualAttachment?> _startRegionCapture() async {
  if (_aiCaptureModeActive || _regionCaptureCompleter != null) return null;
  final completer = Completer<AiVisualAttachment?>();
  _regionCaptureCompleter = completer;
  setState(() => _aiCaptureModeActive = true);
  _aiPanelEntry?.markNeedsBuild();
  try {
    return await completer.future;
  } finally {
    _regionCaptureCompleter = null;
    if (mounted) setState(() => _aiCaptureModeActive = false);
    _aiPanelEntry?.markNeedsBuild();
  }
}

Future<void> _handleRegionSelected(Rect screenRect) async {
  final completer = _regionCaptureCompleter;
  if (completer == null || completer.isCompleted) return;
  final viewport = _markdrawController.editorState.viewport;
  final sceneRect = sceneRectFromScreenRect(viewport, screenRect);
  try {
    final attachment =
        await captureSceneRectAttachment(_markdrawController, sceneRect);
    completer.complete(attachment);
  } catch (error) {
    completer.completeError(error);
  }
}

void _handleRegionCancel() {
  final completer = _regionCaptureCompleter;
  if (completer != null && !completer.isCompleted) {
    completer.complete(null);
  }
}
```

> 说明：粘贴 `_handleRegionSelected` 中 `try/catch → completeError`——`Completer.completeError` 的异常会在 `_addRegionAttachment` 的 `await` 处抛出并进 `_error` 容器，与手动 chip 现状文案一致。注意：覆盖层「过小矩形」分支不回调 `onCommit`，天然无此路径。

6. 顶部 import 增补 `../ai_assistant/views/region_capture_overlay.dart` 与 `../ai_assistant/repositories/visual_attachment_capture.dart`（既有，无需重复）。

7. **验证方式**：本页无既有 widget 测试基底（已核实），新增页面级测试不在本期范围（成本高、收益低；由 §4 手动回归清单覆盖）。`flutter analyze` 通过即可。

提交：`feat:白板页接入截图模式（覆盖层+面板保持态隐藏）`。

### T5：全量门禁 + 文档同步

1. `cd FlowMuse-App && flutter analyze && flutter test`（全量）。
2. `git diff --check`。
3. 文档同步：
   - `docs/项目说明/项目需求.md` 4.12 节：新增「框选截图」条目——点「选区截图」进入截图模式拖矩形；截图区域为任意矩形（可含空白）；期间画布冻结；取消静默；PDF 页 chip 不变。
   - `README.md` 核心能力清单：「AI 助手可附带选区截图 / PDF 页」→「AI 助手可附带**框选截图**（拖框任取画布矩形）/ PDF 页」。
4. 提交：`docs:同步框选截图需求说明`。

## 6. 提交切分

| 顺序 | 内容 | 提交信息 |
|---|---|---|
| C1 | T1 | `feat:AI框选截图捕获管线与场景矩形换算` |
| C2 | T2 | `feat:AI截图模式覆盖层（回形遮罩+拖框提交）` |
| C3 | T3 | `feat:AI面板选区截图改为框选截图模式入口` |
| C4 | T4 | `feat:白板页接入截图模式（覆盖层+面板保持态隐藏）` |
| C5 | T5 | `docs:同步框选截图需求说明` |

每个 commit 自含可绿测试（其范围内验证命令通过）。

## 7. 风险与已知边界

| 风险 | 影响 | 对策 |
|---|---|---|
| 覆盖层与画布坐标错位（DPR/安全区） | 截图偏移 | 不变量约束：覆盖层必须是 `Stack` 内兄弟节点、同一 `SafeArea`；T4 手动回归第 3 条专门框选画布中心元素校验 |
| 导出时 `toImage` 在某些平台性能 | 偶发延迟 | 既有 `exportRegionPng` 已限 1568px；截图仅单次触发，路径与封面缩略图一致 |
| `Completer` 泄漏 | 模式卡死 | `_startRegionCapture` finally 双重复位（completer 置空 + 模式关闭 + markNeedsBuild）；`_handle*` 均判 `isCompleted` |
| 协作房间中框选瞬间画布被远端修改 | 截图与所见毫秒级偏差 | 接受（与既有 `captureSelectionAttachment` 同一窗口语义，预热只增不删） |
| 截图模式与协作光标/远端指针叠加 | 视觉噪声 | 遮挡即属遮罩语义，不在本期修正 |
| 鸿蒙真机 | 签名与真机行为 | 按 AGENTS.md 5.3：涉及 Platform Channel 才必须 `flutter build hap`；本方案**无新增 Channel**，构建冒烟即可 |
