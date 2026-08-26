# Issue #9：手写转文字默认文本框大小优化（设计稿 v3）

- 日期：2026-08-27（v2 吸收方案三路审查；v3 吸收代码两路对抗审查）
- 关联：[Issue #9 优化手写转文字默认文本框大小](https://github.com/qinyre/FlowMuse/issues/9)
- 状态：实施完成，待视觉验收

## 1. 问题

Issue 原文：手写转文字生成的文本框大小不符合对应文字行数/宽度，生成过于随意；应当根据文字大小动态调整文本框大小以包裹文字。

## 2. 根因分析（v2 修订）

手写转文字两条入口汇合到 `_elementFromRecognizedInk` → `_measuredTextElement`（`markdraw_controller.dart:1468`）：

1. 自动识别：笔迹完成 1 秒空闲 → `_recognizePendingInkSession`（:1256）。
2. 手动转换：选中笔迹 → `convertSelectedInkToText`（:4889）。

缺陷（v2 增补）：

| # | 缺陷 | 位置 |
|---|------|------|
| 1 | 字号固定 20，与手写大小无关 | :1499 `fontSize: anchor?.fontSize ?? 20.0` |
| 2 | 尺寸取 `max(测量文本, 笔迹包围盒)`，只增不减 | :1505-1508 |
| 3 | `verticalAlign` 默认 middle，小字悬在大框中间 | `TextElement` 默认参数 |
| 4 | **sticky 默认字号覆盖**：`applyDefaultStyleToElement`（:963-968）用 `_defaultStyle.fontSize` 无条件覆盖字号，且该值一经设置永久非空（`applyStyleChange` :2579），字号跟随手写会静默失效 | :1503 |
| 5 | **math 渲染与测量基准不符**：math 元素由 `Math.tex` + `ClipRect` 渲染（`editor_canvas.dart:641-685`），latex 源码字符串的 TextPainter 测量值 ≠ 公式渲染尺寸 | :1504 |
| 6 | **源笔迹颜色被丢弃**：转出文本取转换时刻 sticky 颜色，红笔写出黑字 | :1404 只传 text/x/y/w/h |

另记录两个**既有缺陷**（非本次引入，本次不修）：

- 服务端 JIIX 多元素路径坐标为相对系（`myscript.go` `toMyScriptRequest` 发笔画前减去 bounds 原点，`parseRawElements`/`boundsFromRaw` 未加回），多元素识别结果会堆到画布左上角。修复需 Go 环境（本机无），列为后续跟进。
- 智能排版路径 `_textElementFromRecognizedBlock`（:4524-4548）存在同样的 `max(笔迹盒, 测量)` 缺陷，"同板两制"割裂已知，列为后续跟进。

## 3. 方案（v2）

原则：**文本框尺寸由测量后的文本决定（紧包裹）；笔迹包围盒用于推导字号与定位，不再作为横排文本的尺寸下限。**

改动集中在 `_measuredTextElement` 与新增纯函数估算器；竖排模板锚点分支整体保持现状。

### 3.1 字号估算器（新增 `src/recognition/ink_text_sizing.dart`，纯函数）

```dart
/// 由笔迹包围盒与识别文本估算排版字号。
double estimateInkFontSize({
  required double inkWidth,
  required double inkHeight,
  required String text,
  bool math = false,
})
```

- math：`clamp(inkHeight * 0.72, 16, 40)`，与智能排版公式分支（`_fontSizeForRecognizedBlock` :4555）一致。
- 文本：
  - 行数 = 归一化换行（`\r\n`/`\r` → `\n`）后 split；
  - CJK 占比 `r`（CJK = U+2E80–9FFF、U+3040–30FF、U+AC00–D7AF 谚文、U+F900–FAFF、U+20000–3FFFD，按非空白 rune 计）：高度系数 `0.72 + 0.18r`（CJK 字形≈0.9em 近方形，拉丁含升降部≈0.72em）——回应"中文稳定缩小 30%"审查意见；
  - `byHeight = max(inkHeight,1)/行数 × 高度系数`；
  - 宽度兜底 `byWidth`：**仅当文本（忽略空白）恰为单个 CJK 字符**时启用（`byWidth = min(inkWidth, 160)`）——用于"一"等扁平字迹高度触底场景；多字符时宽度含字距噪声不采用（v3 收紧：v2 的"单行 CJK≥0.5"会让扁宽多字文本字号翻倍）；
  - `fontSize = clamp(max(byHeight, byWidth), 12, 400)`（自由画布大标题不被 48 上限截断；宽度兜底单独限幅 160 防退化输入）。

**与智能排版启发式不统一的决策说明**：审查意见建议抽公共函数；本方案刻意不改 `_fontSizeForRecognizedBlock`（A4 分页语境，clamp 12–48 有占位体系依赖），避免本 Issue 波及智能排版行为。差异（CJK 系数、上限）为有意为之，统一化列为后续跟进。

### 3.2 `_measuredTextElement` 重构（v3 修订）

调用链：`_elementFromRecognizedInk` 增参 `inkStyle`（入口先算一次**整组主导色**：累计点数最多的颜色，不透明度取该色加权均值；多元素共享同组颜色——多色会话下切笔前笔迹占优）；文本先做 `\r` 归一化。

1. `fontSize = anchor?.fontSize ?? estimateInkFontSize(...)`；
2. 构造 TextElement（横排宽高仅作占位，竖排沿用旧构造公式）；
3. `applyDefaultStyleToElement` 后**写回** `fontSize`（识别/锚点字号优先于 sticky 默认字号——笔迹高度信息一次性不可再得，回应审查 P1；fontFamily/textAlign 仍取默认样式）与 `inkColor/inkOpacity`（保色）；
4. **竖排分支显式 early return**，保留旧 `max(测量, 构造值)` 语义——回应"伪代码与竖排不动自相矛盾"的 P0；
5. **math 分支**（非竖排）：`width = max(measuredWidth + 4, inkWidth)`，`height = max(measuredHeight, inkHeight, fontSize * 2.4)`——flutter_math display 模式分式可达 ~2.2em，2.4em 余量防 `ClipRect` 裁剪（回应 P0：math 不得按源码测量紧包；v3 宽度补 +4 边缘余量）；
6. **横排文本分支**：`width = max(measuredWidth + 4, 20)`，`height = max(measuredHeight, fontSize × lineHeight)`；`x = inkX`；`y = inkY + (inkHeight − height) / 2`（垂直居中，回应 P2）；
7. **锚点横排**：紧包后复用 `_alignSmartLayoutTextToAnchor`（:4713）对齐（底部贴线），修复"y 直接取 anchor.position.dy 悬空一行"的既有错位——回应 P1。

### 3.2.1 结果应用跳过二次样式化（v3 新增，代码审查 P1）

`applyResult` 在创建工具激活时会对 `AddElementResult` 再套一次默认样式（`_applyDefaultStyleToResult`）。自动识别入口转换时 `freedraw` 工具必处于激活态，写回的识别字号/笔迹色会被 sticky 默认样式**再次覆盖**且无重测量，造成框/字号失配（旧代码被笔迹大框掩盖，紧框后可见）。

修复：`applyResult` 增加可选参数 `applyDefaultStyle`（默认 true 保持既有语义），两条转换入口的应用调用传 `false`——转换产物已在 `_elementFromRecognizedInk` 内定型。回归测试覆盖 freedraw 激活 + sticky 字号/颜色已设置的自动识别链路。

页面归属不受影响：`_attachCurrentPage` 在 `applyDefaultStyleToElement` 内、紧包改尺寸之前执行（仍按笔迹量级定页）。

### 3.3 非目标

- 不改智能排版 `_textElementFromRecognizedBlock`/`_measureSmartLayoutText`（后续跟进，见 §2）。
- 不修服务端 JIIX 相对坐标缺陷（无 Go 环境；后续跟进）。
- 不做转换动效（瞬时替换；字号跟随后大小突变已收敛）。
- 不改自动路径转换后自动选中行为（紧框后观感净改善，验收确认）。
- sticky `textAlign` 仍适用（紧框内不可见，拉伸后按用户默认对齐）。

## 4. 风险与对策（v2）

| 风险 | 对策 |
|------|------|
| math 估算字号变大后公式仍可能超框 | 高度按 2.4em 余量兜底；视觉验收专测分式/根号/上下标 |
| 字号启发式偏差（行距极端、中英混写） | clamp 12–400 兜底；视觉验收覆盖中/英/混写/多行 |
| 紧框中心左移导致跨页笔迹 pageId 变化 | 定页发生在改尺寸之前（§3.2-7），行为不变 |
| 选中/命中变化 | 紧框即命中框，修复"空白大框可点选"怪异；`TextBoundsValidator` 只扩不缩不受影响 |
| 测试字体测量 | 断言用 `TextRenderer.measure` 同源计算期望值，不用魔法数字 |

## 5. 测试与验收（v2）

单测（新增 `test/features/whiteboard/editor_core/ink_to_text_box_sizing_test.dart`，共 15 例）：

估算器纯函数：CJK 大字（系数 0.9）、拉丁（0.72）、两行、扁平"一"（宽度兜底→限幅 160）、极小笔迹（下限 12）、math（16–40）、`\r\n` 归一化。

入口集成（`convertSelectedInkToText` + fake `onRecognizeInk`，经 `applyResult(AddElementResult + SetSelectionResult)` 构造选中笔迹）：

1. 单行大字迹（ink 400×80，"你好"）→ fontSize=72，框宽=measure+4 < 400（不再被笔迹盒撑大），框高=max(measure, 72×1.25)，y 垂直居中，红笔迹保色、不透明度保留。
2. sticky 字号 28 已设置 → 仍取推导字号（写回覆盖）。
3. **自动识别路径**（freedraw 激活 + sticky 字号 28/蓝色 + 红色 pending 笔迹 → pump 1s）→ 字号 72、红色、紧框——钉死 `applyDefaultStyle: false` 修复。
4. math（latex）→ 字号=clamp(inkH×0.72,16,40)，框高 ≥ fontSize×2.4，框宽 ≥ 笔迹宽。
5. 多元素识别结果各自紧包裹。
6. 竖排回归（ancientBook 模板 + smartInkLayoutMode + sticky 字号 28）：字号仍为锚点 61.6、框高 ≥ 字数×88、writingMode=vertical。

视觉验收（网页端）：

- 本地 fake 识别服务（canned 响应：固定文本 + 笔迹包围盒），`flutter run -d chrome --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://127.0.0.1:<port>`。
- 中文/英文/混写各一组：书写 → 1s 自动转换 → 选中框紧贴文字、无大片空白、字号与手写大小相当。
- math 公式（分式/根号/上下标）无裁剪。
- 多行段落一次转换：行数正确、行距自然。
- 转换后双击编辑：框自然撑开、字号延续；Ctrl+Z 撤销还原笔迹。
- 200%/50% 缩放下书写转换（scene 坐标语义）。
- vision-specialist 审图确认。

## 6. 提交计划

1. commit 1：设计文档 v1+v2（本文件）。
2. commit 2：估算器 + `_measuredTextElement` 重构 + 单测。
3. commit 3：代码对抗审查意见修复。
4. commit 4：视觉验收后的调整（如有）。
