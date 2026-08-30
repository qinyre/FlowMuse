# 智能排版第四轮 UX 走查修复计划

日期：2026-08-29　分支：`feature/smart-layout-som-echo-fix`
来源：用户真机截图走查（手写 4 句话 + 总结句/标题 + 2 图 + 图注/标签），确认修复除第 7、8、9、19 项外全部 15 项。

## Context

v2 视觉管线（整页截图 + SoM → VLM 认字/配对 → 裁剪重问 → 三模板预落位 → 模板卡 → 草稿态 → 一次提交）已上线，但真机走查暴露一批体验问题。勘察确认的关键事实：

- 图注配对依赖 VLM `pairId`，**无客户端兜底**——走查中配对失败，"图1/图2"与图片分家变成独立正文（走查截图 2/3 可证）。
- 聚类行带分块阈值 `max(1.2×min(h), 28)` 过宽，同行两句被并成一块（"第1句话 第3句话"），破坏阅读顺序。
- 竖排手写被有意转成竖排印刷体（`writingMode:'vertical'`），观感如故障。
- 噪点笔画（<8×8pt）被有意留在页面（clusterer 剔除后不进任何清单），造成"没排干净"。
- 缩略图 `_TemplateThumbnailPainter` 已画真实内容，但字号随缩放变小无下限，不可读。
- 草稿态已可一键撤销（单次 Compound）、低置信橙框 + 校对 sheet 已存在；缺"全文核对"入口与置信度解释文案。
- 进入草稿已有 `_fitViewportToPage`，但只适配页框，不适配内容并集。
- 模板切换需取消重来（成本高）；确认条与左侧属性面板互相遮挡。
- 外部调研：GoodNotes/Notability 均为"替换式"转换，Apple Notes/Nebo 存在"保留手写"需求缺口——"保留手写、仅重排位置"是差异化能力（同类未找到现成方案，自行设计）。

## 需求（15 项 → 3 个工作包）

| # | 问题 | 修复 |
|---|------|------|
| 1 | 图注/标签与图片语义关联丢失 | 客户端几何配对兜底：VLM 未配对的 caption 就近绑图（间距阈值），"图N"模式优先 |
| 2 | 阅读顺序错乱（同行两句并块） | 收紧行带分块间距阈值，同带大间隙拆块；阅读序 top→left 保序 |
| 3 | 识别结果无处核对 | 确认条新增"核对全文"，校对 sheet 支持全部文字项（不只低置信） |
| 4 | 竖排手写→竖排印刷体 | 转写一律横排（聚类/识别阶段仍按竖排列整块识别） |
| 5 | 残留墨迹/空列表项 | 噪点笔画并入 removeIds 随应用删除；纯标点文本块不生成元素、笔迹同噪点处理 |
| 6 | 置信度 74% 不可解释 | 确认条副标题解释橙框含义；有低置信项时"校对"按钮强调 |
| 10 | 排版后视口不适配内容 | 草稿进入视口适配 = 页框 ∪ previewRects 并集 |
| 11 | 缩略图文字不可读 | 缩略图字号下限 + 省略截断；图块灰底 + "图"角标 |
| 12 | 模板无差异说明 | 每张模板卡加一行适用场景说明 |
| 13 | 缩略图与应用结果不一致 | 二者同源（preparation.layouts），随 #15/16 引擎修复自动对齐；缩略图补画图块 |
| 14 | 换模板成本高 | 确认条加模板切换 chips，草稿态直接换模板重建草稿 |
| 15 | 留白失衡 | 引擎修复 + 复现测试断言铺满内容区宽度 |
| 16 | 内容溢出页面边界 | 复现测试断言全部 previewRect ⊆ contentArea，溢出即修 |
| 17 | 手写风格全丢 | "保留手写、仅重排位置"开关：文本块以墨迹整体移动占位，不转印刷体 |
| 18 | 确认条遮挡属性面板 | 草稿态隐藏属性面板（`smartLayoutDraftActive` 已有 getter） |

非目标（用户明确排除）：#7 已保存指示、#8 全选状态、#9 重新识别/取消语义、#19 多页整体排版。服务端 VLM 提示词调优不在本轮（"标题→标题页"类识别误差靠 #3 全文核对让用户可纠）。

## 实现方案

### 工作包 A：引擎与内容装配（items 1/2/4/5/15/16/17-引擎侧）

文件：`smart_layout_ink_clusterer.dart`、`smart_layout_template_engine.dart`、`smart_layout_content.dart`、`markdraw_controller.dart`（3700–3900、4600–4760 区域）、`smart_layout_plan.dart`。

1. **几何配对兜底**（#1）：`_prepareVisionRecognition` 组装 content 处，VLM 配对后仍未配对的 `role=caption` 文本，按包围盒间距（垂直或水平间隙 ≤ 64pt，取最近）绑到最近图；文本匹配 `^图\s*\d*$` 优先。配对成功进 `FigureTextPair`。
2. **行带分块收紧**（#2）：`_splitBandByGap` 阈值 `max(1.2×min(h), 28)` → `max(0.8×min(h), 20)`（以测试校准为准；与 Go 侧经典管线的对齐注释同步修正，v2 客户端聚类已与经典管线无关）。
3. **横排转写**（#4）：`_textElementFromRecognizedBlock` 不再写 `writingMode:'vertical'`，统一横排测量；竖排信息仅用于聚类阶段。同步校对改字路径（4056–4066 的竖排跳过重测分支可简化）。
4. **噪点/标点清理**（#5）：`_smartLayoutInkGroupsForPage` 收集噪点笔画 id 并入 preparation.removeIds；纯标点/无字母数字汉字文本块不生成元素，其笔迹并入 removeIds。
5. **布局质量复现测试**（#15/16）：按走查场景构造 content（宽图 800×450 + 方图 500×500 + 若干短文本 + 图注），三模板断言：previewRect 两两不交、全部 ⊆ contentArea、文本流占满内容区宽。失败则修引擎（重点排查 `_moveUnit` 的 sourceBounds 一致性与装配路径 `_buildDraftScene`）。
6. **保留手写引擎侧**（#17）：`LayoutUnit` 增加 `keepAsInk` + 文本块的 `memberIds`（该块笔迹 id）；引擎在 keepAsInk 时用 `_moveUnit` 移动墨迹占位（handout：标题居中/图注随图/正文左对齐流；outline：条目行左对齐、无 • 前缀、不做字号放大；inplace：文本墨迹不动）；`SmartLayoutTemplatePreparation` 增加 `layoutsKeepInk`（同一 content 二次引擎调用，无额外 VLM 成本）；`buildSmartLayoutPlanForTemplate(preparation, kind, {keepHandwriting=false})` 选择布局源；keepHandwriting 时该块笔迹从 removeIds 排除、进入 moveDeltas。

### 工作包 B：模板选择卡（items 11/12/13/17-开关）

文件：`smart_layout_template_sheet.dart` + 其测试。

- `_TemplateThumbnailPainter`：字号下限 9、超宽省略；figure/组画灰底圆角块 + "图"角标；保持与落位同一几何源（不重算）。
- 每张卡标题下加一行说明（本地映射）：图文讲义"标题+图文成组，适合讲义式整理"；要点清单"条目清单，图随文走"；原文整理"只转文字，版式不动"。
- 卡片区顶部加"转写为印刷体 / 保留手写笔迹"分段开关：参数 `keepHandwriting` + `onKeepHandwritingChanged`（由页面注入），切换后缩略图切换 `layoutsKeepInk` 源；某模板在该模式下放不下则置灰并提示。

### 工作包 C：草稿态与确认流程（items 3/6/10/14/18）

文件：`smart_layout_dialogs.dart`、`whiteboard_page.dart`、`markdraw_controller.dart`（草稿区域 3400–3600、3990–4075）。

- **全文核对**（#3）：控制器增加草稿全文文本项 getter；确认条在"校对 N 处"旁加"核对全文"次级动作，复用 `SmartLayoutProofreadSheet` 全量模式。
- **置信度文案**（#6）：确认条副标题："有 N 处内容识别把握较低（画布橙框标出），建议校对后应用"；N>0 时校对按钮强调样式；N=0 显示"全部内容识别把握良好"。
- **视口适配**（#10）：`enterSmartLayoutDraft` 的适配框改为页框 ∪ plan.previewRects 并集（新 `_fitViewportToRects`）。
- **模板切换**（#14）：确认条加三模板 chips（当前项高亮、放不下置灰）；点选 → 用缓存 preparation 重建计划（`buildSmartLayoutPlanForTemplate`，保留当前 keepHandwriting 与草稿内拖动不作跨模板保留）→ 重新进入草稿；放不下给 SnackBar。
- **属性面板**（#18）：草稿态（`smartLayoutDraftActive`）隐藏元素属性面板，定位后最小侵入修改。

## 验证方案

- `cd FlowMuse-App && flutter analyze` 无新增 error。
- `flutter test` 全量通过；重点：clusterer/engine/plan/vision/draft/template_sheet/dialogs 各测试文件新增用例。
- 复现测试（走查场景）三模板全绿 = #1/2/15/16 有证据。
- 心智回归：识别→选模板→预览→换模板→校对→应用→撤销；取消路径零残留。
- 跨端自检：改动全部在共享 Dart 层，无 `Platform.is*`；Web/桌面/安卓/鸿蒙行为一致；鸿蒙按惯例本轮不真机验证，如实记录。
- 文档同步：`docs/项目说明/项目需求.md` 智能排版条目补"保留手写开关/全文核对/模板切换"。

## 实施步骤

1. 工作包 A（单代理，先行）→ `flutter analyze` + 引擎相关测试 → 提交推送。
2. 工作包 B ∥ C（两代理并行，文件不相交）→ analyze + 相关测试 → 提交推送。
3. ponytail-review 审全量 diff → 修冗余 → 全量 `flutter test` → 提交推送。
