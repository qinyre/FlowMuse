# 智能排版视觉优先管线实施计划（VLM 看图定版式）

> 分支：`feature/smart-layout-templates`。需求方确认：采用**视觉优先（方案 A）+ 服务端新端点**——
> AI 拿整页截图一次性完成"认字 + 结构理解 + 图文配对 + 风格判定 + 粗位置提议"；
> 客户端校验夹取后交由**现有版式模板**精修落位；现有管线全部保留为回退。

## Context（含调研结论）

多轮实测表明确定性管线的弱点在**级联误差**：聚类 → 逐块 OCR → 分类 → 配对 → 模板，五级串联
每级误差向下游放大（实测案例：竖排旋转识别产出 `√2⊥ / f″(x)≥0` 等垃圾 → 风格误判 in_place →
垃圾原位落地）。调研结论（出处见附录）：0-1000 归一化目标框是 Qwen2-VL（论文）与 Gemini
（官方文档）双重背书的惯例，GUI Agent 领域已生产级验证；但 VLM 坐标只够"粗位置"（
ScreenSpotPro SOTA <40），**正确形态 = VLM 提议角色/文字/配对/粗位置，客户端布局算法精修落位**。
草稿编辑态（预览+拖动+确认）作为最终人工安全网（已上线）。

## 需求（澄清结论）

| # | 结论 |
| --- | --- |
| R1 | 视觉优先：AI 拿整页截图 + 笔记标题，一次调用输出严格 JSON（风格、元素列表[角色/认出文字/原稿位置/目标位置/竖排标记]、图文配对） |
| R2 | 通道：服务端新端点 `POST /api/ink/smart-layout/vision`（复用 FLOWMUSE_AI_* 配置调 VLM，temperature 0，JSON 输出） |
| R3 | 坐标：0-1000 归一化（左上原点，[x1,y1,x2,y2]），客户端钳制后映射页面坐标 |
| R4 | 客户端校验：原稿位置 → 按重叠匹配回场景元素（文字→删笔迹建文本；图/形状/组→平移）；夹取内容区；重叠用现有避碰修复；锁定/组/绑定规则不变 |
| R5 | 竖排：AI 认出竖排文字 → `writingMode:vertical`（渲染分支已有） |
| R6 | 回退：视觉调用失败/JSON 非法/元素过少 → 退回现有模板管线（行为不变） |
| R7 | 交互不变：草稿编辑态（预览+拖动+确认）为最终安全网 |

## 实现方案

### 1. 服务端（FlowMuse-Server）

- `internal/recognition/vision_layout.go`（新）：
  - `VisionLayouter`：调 OpenAI 兼容 chat completions（image_url = 截图 base64 + prompt，
    temperature 0），prompt 显式声明 0-1000 坐标系/角色定义/先分区扫描/禁止发明元素/
    输出 confidence；
  - 解析 + 严格校验（坐标钳制 [0,1000]、角色白名单、文字非空、元素数上限 50）；
- `api.go`：路由 `POST /api/ink/smart-layout/vision`（body 上限沿用 32MB）；
- prompt 要点（原文写入代码）：角色定义（title/caption/body/figure）、
  "先逐区域扫描再统一输出"、输出 schema、竖排文字标注 vertical；
- 测试：`vision_layout_test.go`（fake VLM：合法 JSON/非法 JSON/坐标越界钳制/幻觉过滤）。

### 2. 客户端（FlowMuse-App）

- `smart_layout_document.dart`：`VisionLayoutRequest/VisionLayoutElement/VisionLayoutResponse` 模型；
- `ink_recognition_repository.dart`：`visionLayout(request)` → 新端点；
- 控制器新路径 `buildVisionLayoutPlan(pageId)`：
  1. `exportRegionPng(整页 bounds)`（已有）→ base64；
  2. 调 `visionLayout`；
  3. 归一化坐标 → 页面坐标；**原稿匹配**：文字项 → 按重叠匹配笔迹簇（clusterer）；
     图/形状项 → 按重叠匹配场景元素/组（IoU 最大者，唯一）；
  4. 组装 `SmartLayoutContent`（**复用现有结构层**：title/pairs(AI pairId)/loose）；
  5. 走现有模板（PairFlow/TwoColumn/…）产出 `SmartLayoutPlan`（居中/行距/避碰全继承）；
- 失败回退：vision 异常/元素 <2 → `_planForStyle` 旧管线；
- UI/草稿态/底部条：不变。

## 复用点（ponytail 结论）

复用：`exportRegionPng`、`SmartLayoutInkClusterer`（笔迹簇匹配）、`SmartLayoutContent` +
结构层 builder、PairFlow/TwoColumn/Mindmap/Article/InPlace 模板、`SmartLayoutPlacement`
（重叠修复）、草稿态、底部条、历史链路。
不新增：约束求解、布局库、客户端 AI 直连通道、新交互。
服务端新增 1 个文件 + 1 条路由；客户端新增模型/仓库方法/控制器路径，模板零改动。

## 验证方案

1. Go：`vision_layout_test.go`（fake VLM server）+ `go test ./... && go vet ./...`。
2. Flutter：归一化换算/元素匹配/夹取/回退单测；既有 547 例全量回归；`flutter analyze` 0 error。
3. 手动验收：同页（相册/总结/照片+图）重测——期望标题置顶居中、竖排说明在图侧保持竖排、
   图文相邻、无垃圾文本；AI 失效时自动回退旧管线。

## 实施步骤

1. Go：类型 + VisionLayouter + 路由 + 测试。
2. Dart：模型 + repository 方法 + 单测。
3. 控制器：`buildVisionLayoutPlan`（匹配/夹取/组装）+ 单测。
4. 接线：`_runSmartLayoutPage` 优先 vision、失败回退 + 全量门禁。
5. 文档同步（接口设计.md + 项目需求.md + 本计划执行结果）+ 提交（不推送）。

## 执行结果（2026-08-26）

全部完成，边界较计划有两处明确收窄/增强：

- **服务端**：`internal/recognition/vision_layout.go`（VisionLayouter + 0-1000 坐标钳制、角色白名单、
  幻觉过滤、title 去重、元素 ≤50）；路由 `POST /api/ink/smart-layout/vision`（HTTPAPI 增加
  `WithVisionLayouter` 注入）；`vision_layout_test.go` 9 例（合法 JSON/坐标越界钳制/幻觉丢弃/
  非法 JSON 报错/端点校验）。`go test ./... && go vet ./...` 通过。
- **客户端**：`SmartLayoutVisionRequest/Element/Response` 模型（smart_layout_document.dart，fromJson
  双重钳制+倒置交换）；repository `visionSmartLayout()`；纯函数匹配器 `SmartLayoutVisionMatcher`
  （新文件 smart_layout_vision_matcher.dart：文本按"簇在框内覆盖率 ≥0.35"认领、图形按
  interArea/min ≥0.4 唯一匹配）；控制器 `_tryBuildVisionLayoutPlan`（截图 → VLM → 匹配 → 组装
  SmartLayoutContent → 复用 PairFlow/TwoColumn），未接线/截图失败/接口异常/风格非 ppt/
  匹配项 <2/落位空间不足 六种情况均自动回退经典管线。
- **附带修复**：`_layoutTwoColumn` 原先不放置 `content.title`（经典管线 ppt 无配对时标题丢失），
  已对齐 pairFlow 的"置顶居中放大"处理并有回归测试。
- **验收**：flutter analyze 0 error；flutter test 全量 642/642 通过（含新增 vision 测试 10 例）。

## 第二轮：接管全部风格 + 文字转写走 MyScript（同日需求追加）

需求方确认两点调整：

1. **vision 管线接管全部四种风格**（v1 仅 ppt）：服务端 prompt 增加 mindmap 判据与结构树输出
   （`structure.root`，节点以 `blockIds:["e0"...]` 引用自己的元素下标）；`sanitizeVisionMindmapStructure`
   校验树深 ≤4 / 节点 ≤50 / 文字 ≤100 字 / 引用存在且全局唯一，**校验失败整体回落 in_place**（与
   经典管线 sanitizeLayoutDecision 同语义）。
2. **文字转写统一"MyScript 优先"**：被认领的笔迹簇合并后逐项走 `_recognizeSmartLayoutBlockWithMyScript`
   （公式/手写体识别质量优于 VLM 转写）；失败或环境未配置 MyScript 回调时回退 VLM 转写文本，
   两者皆无则该项进失败红区。

客户端落位完全复用既有机器、模板零改动：ppt→PairFlow/TwoColumn；article/in_place→把合成块
fabricate 成 `SmartLayoutResponse` 后复用 `_legacyPlacementPlan`；mindmap→同样 fabricate 后直接调
现有 `_mindmapPlan`（合成块 id=元素引用 id，节点文字经既有 blockIds 拼接逻辑取 MyScript 文本）。
合成块边界统一为认领笔迹簇并集——in_place 的原位转换语义因此保持不变。

验收：`go test ./... && go vet ./...` 通过；flutter analyze 0 error；flutter test 全量通过
（vision 定向测试扩至 13 例：四风格分发、MyScript 优先/兜底、mindmap 树布局、两栏标题等）。

## 边界与风险

- VLM 坐标为粗位置（客户端模板精修）；小而密集元素可能漏/偏（草稿态人工兜底）；
- 潦草手写认字错误率仍取决于模型（R6 同前）；
- 服务端需重新部署（新增端点）。

## 附录：调研出处

Qwen2-VL 论文 https://hf-mirror.com/papers/2409.12191 ｜ Qwen2.5-VL 博客
https://qwenlm.github.io/blog/qwen2.5-vl/ ｜ Gemini spatial understanding
https://ai.google.dev/gemini-api/docs/spatial-understanding ｜ 方舟 Visual grounding /
Structured output（docs.byteplus.com/en/docs/modelark/1616136、1568221）｜ UI-TARS
https://hf-mirror.com/papers/2501.12326 ｜ OmniDocBench
https://hf-mirror.com/papers/2412.07626 ｜ pdfminer https://euske.github.io/pdfminer/
