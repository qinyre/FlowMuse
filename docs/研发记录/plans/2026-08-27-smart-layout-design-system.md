# 智能排版"设计系统化"演进计划（置信度闭环 + 语义规格 + 渲染器参数化）

> 分支：`feature/smart-layout-templates` ｜ 前置：视觉优先管线已落地并真机跑通
> （2026-08-26 计划三轮），本计划为其第四~七轮迭代，用户拍板按推荐方案全量推进。

## Context（含调研结论）

现状与动机：视觉管线端到端可用，但真机暴露三类问题——①转写无质量信号（MyScript
误识被无条件采信，已反转为 VLM 文本优先，但 VLM 也会错，错时用户无从得知也改不了）；
②匹配层覆盖率阈值误伤（左侧"总结"整片落红框）；③四套落位器各自为政，美观靠运气、
新风格边际成本高。用户要求抛开原指令约束，按"AI 做编辑（语义意图）、代码做设计
（几何一致性）、人做终审（低置信校对）"的三权分立思路全面演进。

外部调研结论（本轮新增，标注来源类型）：

- **同类 · PowerPoint Designer**：云端 ML 分析内容 → 与专业设计模板库匹配 → 多候选
  排序推荐。借鉴"不生成几何、选原型"，弃"人工设计资产库"（改为参数化原型）。
  https://support.microsoft.com/en-us/powerpoint/create-professional-slide-layouts-with-designer
- **同类 · Gamma**："弹性卡片块 + 统一设计语言"，结构/文案/版式/主题一次生成。
  借鉴"块为一等公民"；Web flex 模型不适用于画布绝对坐标，仅取概念。
  https://affine.pro/blog/gamma-ai-presentation-maker
- **同类 · Nebo/GoodNotes**：手写转文本后流式重排——佐证"转换结果可编辑"体验方向，
  无直接可搬实现。
- **跨领域 · Slidev/Presenton/think-cell JSON 自动生成**：内容(JSON) 与设计(主题布局
  组件)彻底分离；布局原型是有限集（cover/two-cols/image-right…），原型接受槽位数据
  确定性渲染。→ 本计划"语义规格→渲染器"的直接架构模板。
  https://sli.dev/guide/layout 、https://presenton.ai/ai-presentations/pptx-generation-api
- **跨领域 · Cassowary/Auto Layout**：约束+优先级线性求解。借鉴其"冲突消解按优先级"
  思想（无重叠=硬约束、字号缩放优先于截断、留白均衡=软约束）；**不引入求解器依赖**，
  手写贪心+二分足够（见 ponytail 裁剪）。
  https://en.wikipedia.org/wiki/Cassowary_(software)
- **反面证据 · LayoutGPT**：LLM 直出坐标存在坐标幻觉、泛化差等官方记录失败案例 →
  坚持模型只输出语义级位置意向。https://layoutgpt.github.io/

许可证：本轮不引入任何第三方库（全部自研借鉴思想），无许可义务。

## 需求（澄清结论）

1. 置信度全链路贯穿；草稿态对低置信文本高亮并可就地改字；
2. 匹配层废弃纯覆盖率阈值，改为簇中心点认领；
3. 服务端 vision 输出升级为带语义规格（密度/强调/图位偏好/栏数意向）；
4. 客户端落位收敛到共享设计令牌 + 参数化引擎，四种风格成为参数预设而非独立程序；
5. 草稿态进入后可后台异步精修一轮（限一次、超时静默放弃）；
6. 经典管线保留为回退（服务端不可用/旧版服务端），MyScript 兜底保留（VLM 无文本时）。
7. 交付节奏（checkpoint 确认）：逐轮交付，每轮门禁全绿本地提交，用户鸿蒙真机验收
   后再进下一轮。
8. 就地改字形态（checkpoint 确认）：底部轻量编辑条（非画布内嵌编辑器）。

## 实现方案

### R1 认得准·修得快（confidence 闭环）

- 服务端 `vision_layout.go`：prompt 要求每个元素自报 `"confidence":0-1`（认字把握）；
  sanitize 钳制 [0,1]、缺省 0.9（宽松默认，避免老提示词行为回退）。
- 客户端 `smart_layout_document.dart`：`SmartLayoutVisionElement.confidence`；
  归一化块透传至 fabricate 的 layout 决策外挂映射（index→confidence）。
- 草稿态：`SmartLayoutGhostSpec` 增加 `lowConfidenceRects`（阈值常量 0.6）；
  `smart_layout_ghost_painter.dart` 新增橙色虚线样式。
- 就地改字：草稿态点按任意已生成的文本框（不限低置信）弹出底部轻量编辑条
  （TextField + 确认），实时更新 ghost 内对应文本元素尺寸测量（复用 `_measureText`
  同源逻辑），重排仅影响该块的 fitText 结果，不整页重算。
  **不做画布内嵌编辑器**（工作量与跨端键盘适配不成比例，见 checkpoint 待确认项）。

### R2 匹配对（中心点认领）

- `smart_layout_vision_matcher.dart`：文本项认领条件改为
  "簇中心点 ∈ 框（含 8pt 容差）"，多框命中时取 interArea/min 最大者；
  覆盖率 ≥0.35 作为并列条件保留（或关系），移除一票否决地位。
- 图形单元逻辑不变。失败红区 = 未被任何认领覆盖的簇，语义不变。

### R3 排得美（设计令牌 + 语义规格）

- 服务端 prompt v3 增补语义规格字段：
  - 页级 `"density":"airy|balanced|dense"`、`"figurePlacementHint":"left|right|top"`
  - 元素级 `"emphasis":0|1|2`（0 普通 / 1 次要点 / 2 核心）
  - 校验钳制 + 白名单回落默认值，规则并入既有 sanitize。
- 客户端新建 `smart_layout_design_tokens.dart`（唯一新文件）：
  - 间距刻度（4 的倍数，contentArea 边距/组内距/组间距三档）
  - 字号阶梯（title/h2/body/caption 五档 + emphasis 加成）与 `fitFontSize`
    （放不下先降档、降到底再截断——Cassowary 式优先级的贪心实现）
  - 光学对齐 helper（列左缘对齐容差、行基线整队）
- 四引擎消费 tokens：`_layoutPpt/TwoColumn` 支持 density/emphasis/图位偏好与栏数意向；
  article/in_place/mindmap 引擎接入字号阶梯与间距档（结构不动）。
- 明确不合并引擎：mindmap 是图布局、其余是线性流，强行统一为伪抽象（见裁剪记录）。

### R4 更精一步（异步看图精修一轮）

- 草稿态进入后触发（页面级 flag 常量开关）：后台用当前 plan 渲染缩略截图
  （复用 `exportRegionPng`）调 `/api/ink/smart-layout/vision` 新增 `mode:"critique"`，
  返回有限修正 `{blockId, action: nudge|rescale, delta}` ≤8 条。
- 应用为 v2 草稿前仍过避碰校验；超时 15s 或返回非法 → 静默保留 v1。
- 仅有一轮、不复读。

## 复用点（ponytail 阶梯记录）

- **复用** `exportRegionPng`、`SmartLayoutGhostSpec/Painter` 三类矩形机制（加一类）、
  `_recognizeSmartLayoutBlocksInParallel` 底座、四个落位引擎本体、
  `_legacyPlacementPlan/_mindmapPlan/_visionContext` 装配线、确认条非模态浮层——
  本计划的客户端改动几乎全部是"喂新参数"，不含新管线。
- **不新建**：通用约束求解器（手写贪心够用且零依赖）、文本画布内嵌编辑器
  （轻量编辑条替代）、评测框架（黄金几何断言直接写 flutter_test）。
- **不合并**四个落位引擎为一个大渲染器：同构性不足，抽共享受令牌即可收益到位，
  全量合并是伪抽象。
- 老/新服务端兼容：新增字段全部"缺省即旧行为"，客户端不因服务端未部署而回归。

## 关键文件

| 层 | 文件 |
| --- | --- |
| 服务端 | `FlowMuse-Server/internal/recognition/vision_layout.go`、`types.go`、`api.go`、`vision_layout_test.go` |
| 模型 | `editor_core/src/core/smart_layout/smart_layout_document.dart`、`smart_layout_plan.dart`（GhostSpec） |
| 匹配 | `smart_layout_vision_matcher.dart` |
| 渲染 | 新 `smart_layout_design_tokens.dart`、`smart_layout_ppt_engine.dart`、控制器四处落位装配 |
| UI | `smart_layout_ghost_painter.dart`、`editor_canvas.dart`、`views/whiteboard_page.dart`（编辑条） |
| 测试 | `test/features/whiteboard/editor_core/smart_layout_vision_test.dart` 等 + 新增 matcher/tokens/fit 用例 |

## 验证方案

1. 服务端：`go test ./... && go vet ./...`（vision sanitize 新字段 + critique mode）。
2. 客户端：`flutter analyze` 0 error；`flutter test` 全量绿——R1 confidence 解析/高亮
   spec 断言、R2 matcher 新认领规则用例（含"总结"复现场景）、R3 tokens/fitFontSize
   单测 + ppt 引擎 density/emphasis 几何断言（标题居中放大、无重叠不变量）、
   R4 critique 应用与超时回退。
3. 跨端：共享代码无 `Platform.is*`；鸿蒙需重新部署服务端后真机回归
   （潦草字页/图文混排页/导图页三场景），`cd FlowMuse-App && flutter build hap` 过；
   如实记录真机验收范围于 MR。
4. 数据库：无 schema 变更。

## 方案复审（2026-08-27 应用户要求逐轮复核后的修订）

对剩余 R2/R3/R4 重新过了一遍 ponytail 阶梯与真机证据对照，结论：**方向不变，四处修订**——

1. **R1 遗留缺陷（已修，f54b303）**：reviseSmartLayoutDraftText 裸测量宽度会让改字后
   盒子异常变窄、竖排被横排测量破坏 → 对齐创建/引擎规则 max(现值, 测量)，竖排跳过重测。
2. **R2 增补二次合并扫描**：真机"总结"红框也可能是模型漏发元素或逐字拆簇，单纯放宽
   认领不够——主认领完成后，仍未认领簇若与某已认领文本项的并集框重叠 ≥50%，并入该项
   （区域生长，治拆簇）；无任何归属的照旧进红区。
3. **R2 增补跨引擎低置信回填**：legacy/mindmap 引擎重建 id 导致 R1 标注不生效；改为
   按转写文本在 plan.addElements 中匹配首个未占用同文项回填 id（启发式，同文重复时
   单边漏标可接受）。
4. **R3 拆分降险、R4 缓判**：真机暴露的问题全是"认字层"，版式几何尚未被证据指控。
   R3 先做纯客户端设计令牌 + fitFontSize + 引擎接入（零协议变更、独立验收）；服务端
   语义规格字段（density/emphasis/图位偏好）缓判至 R3a 真机反馈后；R4 异步精修维持
   最后且明确可裁。

## 实施步骤（每轮独立可交付、可回退）

- **R1**（commit 分两个）：① 服务端 confidence 字段 + Dart 模型解析 + 透传 → go/dart
  测试绿；② GhostSpec.lowConfidenceRects + painter 橙虚线 + 底部编辑条 + 就地改字
  测试。
- **R2**：matcher 规则改造（中心点认领）+ 二次合并扫描 + 跨引擎低置信回填 + 专题用例
  （含 regression："总/结"两簇应被 caption 认领、拆簇合并）。
- **R3a**：tokens 文件 + fitFontSize 单测；引擎消费接入 + 几何断言（纯客户端，零协议变更）。
- **R3b（缓判）**：服务端语义规格 v3 字段——等 R3a 真机反馈再决定做不做。
- **R4（最后且可裁）**：critique mode 端到端 + 开关 + 超时回退用例（flag 默认关）。
- 每轮结束：门禁全绿 → 本地提交（中文信息）→ 用户真机验收后再进下一轮。

## 执行结果（R1 · 2026-08-27）

- ①服务端：prompt 元素示例加 `confidence`（自评把握、连笔潦草如实低分）；sanitize
  缺省 0.9、越界钳 1；新增用例 TestVisionLayoutElementConfidenceNormalized；go test/vet 绿。
- ②客户端模型：SmartLayoutVisionElement.confidence（fromJson 缺省 0.9 钳 0-1）。
- ③透传链路：_recognizeVisionTextBlocks 返回 (blocks, inkFallbackIndexes)；
  _attachVisionLowConfidence 只保留能在 plan.addElements 中按 id 定位的项
  （PPT 家族引擎 copyWith 保 id → 可定位；legacy/mindmap 内部重建 id → R1 暂不
  标注，已知限制）；Plan 新增 lowConfidenceTexts/lowConfidenceRects/
  withLowConfidenceTexts；GhostSpec.failures 增 lowConfidenceRects；painter 橙
  #F08C00 虚线。
- ④校对闭环：控制器登记草稿低置信 id 清单并暴露 proofreadItems /
  lowConfidenceRects / reviseSmartLayoutDraftText（UpdateElementResult 同 id 原位
  替换、TextRenderer 重测尺寸）；确认条"校对 N 处"按钮（无校对项时隐藏）→
  SmartLayoutProofreadSheet 底部弹层逐项改字保存；关闭后刷新橙框快照。已知限制：
  拖动文本后橙框不跟随（静态快照），待后续按需改实时。
- 门禁：go test/vet 绿；flutter analyze 0 error（48 条历史 info 不变）；vision 定向
  16/16；全量 flutter test 663/663。
- 注意：服务端不重新部署时 VLM 不输出元素级 confidence，客户端按缺省 0.9 处理
  （不会出现橙色标注，功能静默降级）；真机验证前需先部署。

## 文档同步（完成后）

接口设计（confidence/spec 字段与 critique mode）、项目需求第 8 条措辞、前端架构
（design tokens 小节）、ai_usage 日志。
