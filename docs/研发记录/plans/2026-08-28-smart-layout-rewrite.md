# 智能排版 v2 重构：模板卡片制（四风格退役）

> 分支：`feature/smart-layout-rewrite`（基于 main e747a15）
> 前史：四风格管线三轮真机证据见 `2026-08-27-smart-layout-design-system.md`（已推送远端，旧分支保留不删）

## Context

四风格自动判定（ppt/mindmap/article/in_place）三轮真机迭代后仍不稳，第三次真机证据
（2026-08-28 截图）：图文并茂页以 55% 置信度掉进 in_place；竖排"先头小子"碎成 3 簇
（一簇进红区、一簇识成"M"、一簇剩"子"）；"图1"拆簇后只剩"图"且被挪到页顶。问题不在
某处实现，而在产品前提——"让 AI 同时决定内容、版式、位置"——版式判定天生不可靠。

用户决定：客户端算法与服务端相关代码全部重写，不在四风格上挣扎。

**澄清结论（2026-08-28 一问一答）**：

1. 产品形态 = **模板卡片**：AI 只做认字+图文配对，不再判风格；识别完成弹出 3 张模板
   缩略卡，用户点选后客户端确定性落位。
2. 转写策略 = **整页 + 低置信裁剪重问**：整页 SoM 截图一次识别保结构；自报把握低的块
   裁出来单独再问一次（上下文隔离，文献公认降幻觉手段）。
3. 模板集合 = **图文讲义 / 要点清单 / 原文整理** 三张（思维导图砍掉，后续版本再议）。

**调研结论（借鉴点）**：

- Gamma 的 checkpoint 流程（outline → theme carousel with live previews）：模板卡
  用**本页真实内容预渲染**的缩略图，所见即所得，避免 Canva 式"生成后才发现不满意"。
- presentations-gen 的固定区域填充："hand-tested templates = predictable layout
  quality"——模板定义固定区域（标题通栏/图注成组/正文分段），按内容类型与优先级填充，
  不需要约束求解器。
- 1998 AAAI 经典论文的五类布局约束（proportion/sequence/orientation/task/style）作为
  模板区域设计的检查框架。
- Set-of-Mark（arXiv 2310.11441）编号引用与裁剪降幻觉（KIE-HVQA, NeurIPS 2025）沿用
  上一轮结论，本轮直接内建。

## 需求

1. AI 职责收窄：输出 `{markIds, role(title|body|caption|figure), text, vertical,
   pairId, confidence}`，**无 style、无 structure、无页面级判定**。
2. 交互流：工具栏触发 → 进度提示 → 识别完成 → **模板选择卡**（3 张真实内容缩略图）
   → 点选 → 确定性落位 → 既有草稿态（拖动微调/红区/校对改字/确认条，全部保留）。
3. 识别层重写（2026-08-28 复审修订：**去会话化**）：
   - 废弃"书写会话分组 → 会话内聚类"两层结构（会话边界是碎簇帮凶："先头小子"
     分四笔写即四个会话四个单字簇）；改为对页内**全部墨迹一次纯几何行列聚类**：
     行带划分（中心 y 聚类）→ 带内按 x 间距分块 → 竖排窄高列检测（高/宽 > 1.5
     整列不拆）→ 杂散过滤（单笔画且 < 8×8pt 剔除）。会话维度不再参与智能排版
     （手写字迹识别独立入口仍用会话，不受影响）。
4. 低置信裁剪重问：confidence < 0.7 的文本块从整页原图裁出（外扩 16pt）调转写端点，
   新结果 confidence 更高才采用；并发 3。
5. 删除四风格全部代码（客户端风格枚举/三引擎/风格分发，服务端 style/structure 字段
   与 recognize+compose 端点）；`template_anchors.dart` 保留（AI 助手插入定位共用）。
6. 回退策略变更：**不再有经典管线回退**——vision/转写失败直接提示重试（经典管线本身
   是四风格的一部分，一并退役）。

## 实现方案

### 服务端

- `vision_layout.go` prompt 重写：删 style 判定与 structure 输出段；角色定义保留；
  强调逐块转写质量与低分如实自评（沿用反幻觉条款）。
- `types.go`：`VisionLayoutElement` 不变（已无 box）；`VisionLayoutResponse` 删
  `Style`/`Structure`/`Confidence` 页面级字段。
- 新端点 `POST /api/ink/smart-layout/transcribe`：`{imageBase64, imageMime, hint?}`
  → `{text, confidence}`——无上下文单块转写，prompt 禁止联想、看不清给低分。
- sanitize：删 style 归一与 mindmap 树校验（`sanitizeVisionMindmapStructure` 删），
  保留 markIds 校验/幻觉过滤/title 唯一/文本限长/元素上限。
- 删除 `/api/ink/smart-layout` recognize+compose 端点与 `SmartLayoutLayoutDecision`
  等旧类型（vision+transcribe 两端点替代）。

### 客户端识别层

- `smart_layout_ink_clusterer.dart`：重写为**全页纯几何行列聚类**（与需求第 3 条
  修订一致，废弃会话分组入参）：行带划分（中心 y 聚类）→ 带内按 x 间距分块 →
  竖排窄高列检测（高/宽 > 1.5 整列不拆）→ 杂散过滤（单笔画且 < 8×8pt 剔除）。
- SoM 编号/截图叠加/直查匹配器：沿用现实现（`_drawVisionMarkOverlay`、
  `SmartLayoutVisionMatcher`）。
- 协议模型：`SmartLayoutVisionResponse` 删 style/confidence/mindmapStructure；新增
  `SmartLayoutTranscribeRequest/Response` + 控制器回调 `onTranscribeCrop`。
- 裁剪重问流程：`_recognizeVisionTextBlocks` 产出后，低于阈值的块从 retained 整页
  png 裁剪并发调 `onTranscribeCrop`，择优采用。

### 三个模板落位引擎（新 `smart_layout_template_engine.dart`）

统一输入 `SmartLayoutContent`（title/pairs/looseTexts/looseFigures，现成结构）+
页边界；统一输出 `SmartLayoutPlan`。

1. **handout 图文讲义**：标题通栏置顶居中（大字号）；pairs 网格（图宽 >60% 页宽走
   单列，否则双列，图上图注下）；looseTexts 按阅读序填充剩余区（通栏段落流）；
   looseFigures 依序附后。空间不足：先压间距、再缩字号（下限 12pt），仍不足则 UI
   提示"内容过多，请分页"。
2. **outline 要点清单**：标题置顶；文本项按阅读序排条目列表（圆点 + 固定行距，
   v1 不做层级缩进）；图片等比缩至条目宽 40% 附于原稿最近邻条目右侧，caption 随
   figure。
3. **inplace 原文整理**：文本框以原稿簇并集框中心对齐原位替换、尺寸重测；图/形/
   组不动（moveDeltas 空）。零风险兜底选项。

### 模板选择卡 UI（新 `smart_layout_template_sheet.dart`）

- 识别完成后 bottom sheet 展示 3 张卡：每卡 = 用本页内容按该模板**预落位后离屏渲染
  的缩略图**（复用 `exportRegionPng` painter 基建；渲染失败降级为灰色结构示意图）
  + 模板名。
- 点选 → 按该模板生成 plan → 进入既有草稿态；卡上取消 = 零残留退出。
- 三次预渲染成本：3 次 plan + 3 次小图 toImage（约几十 ms 级），可接受。

### 删除清单（S4 执行）

- 客户端：`SmartLayoutStyle` 枚举、`_layoutPpt`/`_mindmapPlan`/`_legacyPlacementPlan`
  及风格分发、`smart_layout_ppt_engine.dart`、`smart_layout_mindmap_engine.dart`、
  `MindmapStructure`/`SmartLayoutPptStructure` 协议模型、经典管线回调
  （`onSmartLayoutInk`/`onComposeSmartLayout`/`onRecognizeSmartLayoutBlock`）与
  `requestedStyle` 参数、`fabricateResponse` 伪造链路。
- 服务端：`layoutStyle*` 常量、`SmartLayoutLayoutDecision`、recognize+compose 端点、
  mindmap 树校验。
- 保留：`template_anchors.dart`、草稿态/确认条/红区/校对/GhostPainter、SoM 叠加、
  `smart_layout_move_builder.dart`（handout 移图复用，S3 时评估）。

## 关键文件

| 动作 | 文件 |
| --- | --- |
| 重写 | `FlowMuse-Server/internal/recognition/vision_layout.go`、`types.go`（部分）、`api.go`（端点） |
| 新增 | `FlowMuse-Server` transcribe handler + 测试；`smart_layout_template_engine.dart`、`smart_layout_template_sheet.dart` + 测试 |
| 修改 | `smart_layout_ink_clusterer.dart`（聚合+过滤）、`smart_layout_document.dart`（协议瘦身）、`smart_layout_vision_matcher.dart`（不动）、`markdraw_controller.dart`（流程串联+删风格分发）、`whiteboard_page.dart`/`smart_layout_dialogs.dart`（模板卡接线）、两 toolbar（去 requestedStyle） |
| 删除 | `smart_layout_ppt_engine.dart`、`smart_layout_mindmap_engine.dart`、相关测试文件中风格用例 |
| 不动 | `template_anchors.dart`、`smart_layout_ghost_painter.dart`、草稿态/确认条/校对链路 |

## 验证方案

- 服务端：go test——vision 新 sanitize（无 style）、transcribe 端点成功/失败/空图。
- 客户端单测：
  - clusterer：竖排整列保护保留、邻近单字簇合并、杂散笔画剔除；
  - 三模板几何：标题置顶、图注成组同移动、阅读序、空间压缩下限、inplace 不移图；
  - 裁剪重问：低置信触发/高置信跳过/新结果更优才采用/端点失败用原结果；
  - 模板卡 widget：三卡渲染、点选进草稿态、取消零残留。
- 门禁：go vet/test + flutter analyze 0 error + flutter test 全量。
- 真机验收点：①"先头小子"不再碎（聚合后整体转写或裁剪重问纠正"M"）②三模板卡出
  真实缩略图 ③点选后落位符合模板预期 ④图文页不再掉 in_place（无风格概念了）
  ⑤杂散 √ / 不再出现在方案里。

## 实施步骤（每步可验证、可回退）

- **S1 服务端**：vision 协议去风格 + transcribe 端点 + go 测试绿（旧端点暂留，S4 删）。
- **S2 客户端识别层**：clusterer 聚合/过滤 + 协议模型瘦身 + 裁剪重问 + dart 测试。
- **S3 三模板引擎**：handout/outline/inplace 落位 + 几何单测（不动旧引擎，并存）。
- **S4 串联与删除**：模板选择卡 UI 接线 + 切换主流程 + 删除四风格全部代码（客户端+
  服务端旧端点）+ 测试迁移重写。
- **S5 收尾**：门禁全绿 + 文档同步（接口设计/项目需求/前端架构）+ 中文提交（本地）。

## 执行结果（2026-08-28 全部完成）

- **S1 服务端**：`VisionLayouter` 增加 `Transcribe`；vision prompt 删 style 判定与
  structure 输出段；`sanitizeVisionMindmapStructure`/`sanitizeVisionMindmapNode`/
  `nodeText` 删除；`VisionLayoutResponse` 只剩 `pageId`+`elements`；新增
  `TranscribeRequest/Response` 与 `POST /api/ink/smart-layout/transcribe`（空文本
  → confidence 0，未自报把握默认 0.9，钳制 [0,1]）；vision 相关 go 测试重写
  （风格/mindmap 树用例删除、transcribe 全套新增）；go vet + go test 全绿。
- **S2 客户端识别层**：`smart_layout_ink_clusterer.dart` 重写为全页纯几何行列聚类
  （杂散过滤 → 竖排候选列（x 重叠 + 纵向紧邻，高/宽闸门 1.5）→ 行带划分 → 带内
  x 间距分块）；`_smartLayoutInkGroups` 去会话化，`_isVerticalWritingPage` 删除；
  新增 `SmartLayoutTranscribeRequest/Response` 协议、仓库 `transcribeCrop`、
  控制器 `onTranscribeCrop` 回调、`_recognizeVisionTextBlocks` 裁剪重问
  （外扩 16pt、延迟解码整页截图、复用并发 worker、`adoptTranscription` 择优、
  `shouldReAskTranscription` 触发 0.7 阈值，常量与 0.6 校对阈值分列）。
- **S3 三模板引擎**：新增 `smart_layout_template_engine.dart`
  （`SmartLayoutTemplateKind` handout/outline/inplace +
  `SmartLayoutTemplateLayoutResult`）；handout 三级压缩（间距 24→12→8、字号
  0.9..0.5 下限 12）；outline 条目 "• " 前缀 + 小图（≤40%）挂靠最近邻条目行右侧
  + 大图通栏；inplace 原位中心替换、图不动；13 个几何单测。
- **S4 串联与删除**：
  - 控制器：`buildSmartLayoutPlan(requestedStyle)` 拆为
    `prepareSmartLayoutTemplates()`（识别+准备，失败抛异常）+
    `buildSmartLayoutPlanForTemplate()`（点选装配，`_attachVisionLowConfidence`
    改 blockId 直查有效把握）；删除 17 个经典管线/四风格函数
    （runGlobalSmartLayout、_planForStyle、_legacyPlacementPlan、_mindmapPlan、
    _buildPptContent、_layoutPairFlow/TwoColumn/_layoutPpt、_visionContext、
    _buildSmartLayoutRequest、_elementsFromSmartLayoutResponse、
    _smartLayoutSceneOccupancy 等）与三个经典回调字段。
  - 协议瘦身：`SmartLayoutStyle`/`SmartLayoutRequest`/`SmartLayoutResponse`/
    `SmartLayoutLayoutDecision`/`SmartLayoutPageDecision`/
    `SmartLayoutComposeRequest`/`SmartLayoutElementRef`/`MindmapStructure(Node)`/
    `SmartLayoutPptStructure(Group)`/`SmartLayoutPageRequest`/
    `SmartLayoutElementRequest` 删除；`SmartLayoutVisionResponse` 只剩 elements；
    `SmartLayoutPlan.style` 改为 `SmartLayoutTemplateKind`；
    `SmartLayoutStructureBuilder` 删除（视觉管线直构 content）。
  - 删除文件：`smart_layout_ppt_engine.dart`、`smart_layout_mindmap_engine.dart`、
    `smart_layout_template.dart`（旧 Template/Context 基建）及两个引擎测试。
  - 接线：`smart_layout_template_sheet.dart`（三卡真实内容缩略图 + 放不下置灰 +
    取消零残留）；`_runSmartLayoutPage` 改为 prepare → 模板卡 → buildForTemplate →
    既有草稿态；仓库删 smartLayout/recognizeSmartLayoutBlock/composeSmartLayout；
    编辑器与两工具栏删经典回调与全局排版回退。
  - 测试迁移：vision 测试重写为 v2（识别准备/三模板/裁剪重问两向/异常两例/
    无内容 null）；repro 测试重写为真机场景回归（4 行手写+形状+大图三模板不误报
    空间不足）；plan/draft/dialogs 测试改用新枚举；新增模板卡 widget 测试 4 例；
    删除 capacity/optimization/placement/content/pairing 五个经典管线测试文件。
- **门禁**：`go vet ./...` + `go test ./...` 全绿；`flutter analyze` 0 error；
  `flutter test` 655/655 全绿。
- **执行偏差记录**：
  1. outline 模板的"图片等比缩至条目宽 40%"调整为"小图（≤40% 宽）原尺寸挂靠
     最近邻条目行右侧、大图通栏"——图片缩放需扩展 move 协议（现仅平移增量），
     v1 不扩协议，所见即所得不受影响（缩略图如实预览原尺寸落位）。
  2. 计划中"协议模型瘦身"从 S2 挪到 S4 与删除同批执行，避免中间态引用悬空。
  3. `SmartLayoutTemplateEngine` 返回独立的 LayoutResult 而非直接产出
     SmartLayoutPlan（账本字段在调用方装配），S4 接入时再合成计划。
- **文档同步**：接口设计（智能排版整节重写 + transcribe 端点）、项目需求
  （条目 8 改模板卡片制）、前端架构（白板内核新增智能排版段）。
- **真机验收范围（未做，需真机复验）**：本改动未在真机验证；需按验证方案真机
  验收点复核——①跨会话竖排"先头小子"整列识别 ②三模板卡真实缩略图 ③点选后
  落位符合模板预期 ④图文页无风格误判问题（已无风格概念）⑤杂散笔画不再出现在
  方案里 ⑥裁剪重问对低把握块的纠正效果。

## 修复记录：SoM 编号标签泄漏（2026-08-28 晚）

真机验收发现正文出现 "m9"、"m13大"、"m6三月" 一类垃圾文本。根因：**SoM 编号徽章画在
簇框左上角内侧、直接压在手迹上，弱 VLM 把徽章当手写内容抄进了 text**；裁剪重问裁的
也是同一张带标记截图，重问结果同样被污染；未自报把握默认 0.9（≥ 重问阈值 0.7）又让
垃圾文本直通正文、绕过复核。五处修复：

| 修复 | 位置 | 内容 |
| --- | --- | --- |
| A 徽章外移 | `markdraw_controller.dart` | 徽章悬在簇框左上角上方（间隙 2px 不遮笔迹；顶部不足退框下方、贴边回框内，横向贴边内收）；导出区外扩约 28px 余量。落位抽成 `visionMarkLabelRect` 纯函数 |
| B prompt 禁令 | `vision_layout.go` | vision/transcribe 提示词均明确"外框与编号是系统叠加的标注，严禁出现在 text / 严禁转写进结果" |
| C 回显剥离 | `vision_layout.go` | sanitize 剥离 text 里的编号回显：纯回显（"m9"、"m9，m10"，编号可为编造）→ 空文本、把握 0，**保留元素**（markIds 仍有效）交客户端重问救回；前缀回显（"m6三月"）→ 剥成"三月"、把握压 0.5。开头非本页真实编号不动（防误伤"m3u8"类正文；真实编号开头的正文被误剥也能被重问救回）。transcribe 纯回显视为未认出 |
| D 干净裁剪 | `markdraw_controller.dart` | 双导出：无标记干净截图专供裁剪重问；带标记截图只发 vision |
| E 置信度降档 | `vision_layout.go` + 模型 | 未自报把握默认 0.9 → 0.5（低于重问阈值 0.7，强制复核）；择优新增"重问与原文一致 → 采信原文并把把握提升到新值"（两次独立读一致即清除存疑橙框） |

**验证**：`go vet` + `go test ./...` 全绿（新增回显剥离 7 例、vision 端到端回显 1 例、
transcribe 纯回显 1 例、prompt 禁令 1 例，缺省置信度用例改 0.5）；`flutter analyze`
0 error（unused_element 告警与 main 基线一致，为 v2 重构遗留孤儿函数，另行清理）；
`flutter test` 662/662（新增徽章落位 4 例；干净裁剪 1 例——解码 base64 PNG 扫描徽章红
像素，断言"徽章只在 VLM 整页图、裁剪图干净"；择优同文本语义 3 例拆分）。

**未处理项**：role/pairId 误判（该页明明有"图1""图2"题注却"标题 0 处、图文 0 组"）
——按决策不做 prompt few-shot 强化与几何兜底配对，pairId 缺失时题注按松散文本参与
模板落位，功能不阻断；如后续验收仍频繁误判再议。

**真机验收（待做）**：在上一节六项之外加验——⑦正文不再出现 m+数字 编号；⑧低把握块
被橙色标出并可校对；⑨"先头小子"类低把握字经重问纠正。依赖服务端重新部署
（vision sanitize/prompt 已变）。
