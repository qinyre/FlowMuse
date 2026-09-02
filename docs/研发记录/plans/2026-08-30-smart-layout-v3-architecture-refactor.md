# 智能排版 v3 大规模重构总计划：从规则模板改为可评测的语义排版系统

日期：2026-08-30  
分支：`feature/smart-layout-v3-refactor`  
基线：`main@e51ae70`（分支自 6c606f7 新建，2026-08-31 快进并入 main 自然介质笔刷等 26 个提交，无冲突；`markdraw_controller.dart` 现为 7409 行、`whiteboard_page.dart` 3431 行，仅笔刷相关增改，不影响本计划对两文件的结构判断）  
状态：经多轮审查收敛，尚未实施  
执行原则：不按比赛日期或人力容量降级；所有质量、事务、兼容和跨端门禁通过后再切流

## 1. 结论先行

当前智能排版效果差，不是继续调几个阈值、提示词或卡片样式能解决的问题。现有系统把“识别成功、不越界、可以撤销”当成“排版效果好”，但缺少四项基础能力：

1. **可靠的输入结构**：笔迹区域分割、打字文本原文、组/frame/绑定、锁定对象没有形成统一、可审计的页面快照。
2. **足够表达页面意图的语义层**：标题、段落、列表、公式、图文关系、阅读顺序和 unknown 无法稳定进入排版决策。
3. **真正的版面生成与选择**：现有三模板是固定顺序填充，不能根据页面结构组合布局，也没有真实渲染后的质量门禁。
4. **可证明的效果与事务闭环**：缺少真实语料、人工基线、任务实验、像素验证，以及预览/提交/撤销/协作共享同一结果的保证。

v3 不再延续 v2 的规则补丁。重构会替换区域分割、视觉分析协议、语义模型、候选生成、评分、草稿事务和效果评测；旧代码只有通过契约测试后才允许复用。

最终流水线固定为：

```text
Scene
  → PageSnapshot
  → InkRegionSegmenter
  → V3Analyzer
  → SemanticDocument + SemanticCorrection
  → LayoutCompositionPlanner
  → ScenePatchBuilder
  → SceneReducer
  → DraftSceneRenderer
  → HardConstraintValidator
  → LayoutMetrics + Scorer
  → Top 3 `ValidatedCandidate` / NoFeasibleLayout / preserveFallback
  → compare-and-commit
```

评分器不得在真实 `ScenePatch`、Reducer 和 Renderer 之前决定最终推荐。

## 2. 现状批判与根因

### 2.1 架构根因

| 根因 | 当前表现 | 对效果的影响 |
| --- | --- | --- |
| 编排集中在巨型控制器 | 截图、识别、语义兜底、模板、草稿事务集中在 `markdraw_controller.dart` | 每次失败都变成控制器内的新条件分支 |
| 页面状态散落在 UI | 取消、重试、多页、确认、校对由多个 bool/completer/null 组合表达 | 迟到响应、重入和离页状态难以证明正确 |
| 语义模型过浅 | 只有 title/pair/loose text/loose figure | 章节、列表、公式、图组和统一阅读序无法表达 |
| 模板代替排版 | handout/outline/inplace 是固定程序 | 页面叙事被分桶重排，留白、密度和视觉重心靠运气 |
| 变换模型不足 | 主要支持新增、删除和平移 | 图片、文本、组、frame、绑定在缩放后容易失真 |
| 预览和提交不同源 | 草稿可包含完整变化，确认阶段可能重新推导位移 | 用户看到的结果不等于最终结果 |
| 无效果 oracle | 测试主要验证坐标和协议 | 测试全绿仍可能难看、难读、需要大量人工修正 |

### 2.2 算法根因

- 笔迹聚类依赖少量全局阈值，缺少局部尺度、倾斜、列和线状笔画处理。
- VLM 同时承担 OCR、角色和关系，自评分不能代表真实准确率。
- typed text 虽已有原文，角色和关系仍可能被截图误判。
- 标题和图注依赖字数、位置、距离后验补丁。
- 文本不按目标栏宽真实测量；图片不参与受约束等比缩放。
- “放不下”通常直接失败，没有可解释的无解原因和安全保留路径。
- no-op、极端缩小、隐藏文字和大空白都可能骗过简单综合分。

### 2.3 必须继承的既有资产

以下能力优先复用，不重复实现：

- `NativeHttpClient` 与现有取消 token。
- Scene 不可变模型、`ToolResult/CompoundResult`、History、undo/redo。
- `StaticCanvasPainter`、文本 renderer、图片缓存和实际字体解析。
- 现有 frame、bound text、bound arrow、group、LWW/version/versionNonce 语义。
- 范围选择、非模态确认条、核对全文、保留手写、多页跳过和重跑安全。
- `ExcalidrawScene.collaborationHash()`、协作 reconcile、外部导出 sanitizer。
- 既有元素边界、插入定位等几何 helper；若某 helper 被其他功能调用，只固定其行为并保持 API，不在本重构中迁移调用者。

复用前必须用 fixture 证明行为；“已有”不等于“已验证”。

## 3. 目标、非目标与硬约束

### 3.1 目标

1. 每一页依次形成可检查的快照、区域、语义文档、候选、Patch 和真实渲染结果。
2. segmentation、OCR、role、order、relation、planner、transform、render 可分别测试和归因。
3. typed text 原文 100% 保留；unknown 和未认领对象默认保留原位。
4. 用户可修正区域合并/拆分、角色、阅读序、图注关系和保护对象；修正只局部重算。
5. 支持目标栏宽换行、图片 contain 等比缩放、图文原子块、列表/公式/保留手写块。
6. 所有展示候选先经过真实 Scene 硬门禁，再按可审计指标排序。
7. 预览、确认、History 和协作投影来自同一不可变 `ScenePatch`。
8. 效果由 no-op、v2、AI 专家代理整理三基线和冻结双盲任务实验共同证明。

### 3.2 非目标

- 不训练自有版面生成模型，不让 VLM 返回最终坐标。
- 不引入通用约束求解器、布局 DSL、策略插件系统或一实现接口。
- 不自动裁图，不做 focal point，不做图文环绕。
- 不静默创建页面或跨页搬运内容；只提示用户手工拆页后重试。
- 不提供大量排版参数。只保留三个目标：增强可读性、尽量保留原结构、突出图文展示，以及保留手写模式。
- 不修改 Excalidraw 基础字段、数据库 schema 或协作消息类型。
- 不长期维护 v2/v3 生产双轨；远程 capability 只负责关闭 v3，不回退 v2 算法。

### 3.3 重构范围分层

| 层级 | 本计划包含 | 边界 |
| --- | --- | --- |
| 核心重构 | 智能排版的 Snapshot、分割、v3 分析协议、语义文档、候选生成、真实渲染评分、feature-private Patch/Reducer、Session、排版 UI、服务端 v3 路由与切流 | 可以替换 v2 智能排版实现，但不得借机改造相邻产品能力 |
| 交付与验证 | 数据集/基线、EvaluationSpec、fixture/CI、性能、可用平台 smoke、frozen 实验、演示/回滚和文档 | 可以新增测试、报告和演示配置；不能因为门禁失败就顺手重构范围外模块 |
| 兼容验证 | 现有 Scene/History、渲染器、Excalidraw codec、LWW/reconcile、文档持久化/既有导出、六端壳层，以及任何现有智能排版入口调用者 | 默认只复用稳定接口并补回归；只有 v3 无法正确运行时才做最小适配 |
| 明确不做 | AI 助手模型/prompt/action/UI、思维导图布局、SelectTool 交互、通用 editor 架构、协作协议、数据库 schema、全局设计系统、新导出格式及无关平台问题 | 不创建迁移任务，不清理其代码，不以“共享能力”为由扩大所有权 |

范围执行规则：

1. 新类型和算法默认位于 `features/whiteboard/smart_layout/`；没有第二个真实消费者，不下沉为通用框架。
2. `editor_core` 只允许增加或复用智能排版所需的最小读 Scene、生成 Draft、提交既有事务 gateway；不重写 SelectTool、History、LWW、renderer 或序列化架构。
3. 触及相邻模块时，任务卡必须写明“为何无法通过既有接口完成”、精确文件和回归证据；否则任务保持 blocked 并退回 feature 内实现。
4. 删除 v2 时，发现被其他功能消费的符号就保留原位；本项目不负责迁移该消费者，也不为删除目录制造新的公共抽象。
5. 每个 Gate 审计相对基线的生产文件清单；范围外目录必须零 diff，条件式修改必须能映射到一张任务卡，否则 Gate 失败。

### 3.4 产品与数据硬约束

以下任一发生即阻断发布，不能被平均分抵消：

- 源内容静默丢失、重复消费、错误删除。
- 不可交换 reading order、`caption_of`、keep-together 或关键关系被破坏。
- 正文裁切、ellipsis、不可见或低于 12pt 参考下限。
- 图片被自动裁切或纵横比改变。
- 受保护对象、locked/PDF、group/frame/binding/旋转对象损坏。
- preview 与 commit 不等价，revision 冲突仍产生 Scene/History/广播。
- 取消、离页、旧响应或远端更新污染新会话。

不提供主观忽略分支：无法可靠消费的装饰、噪点和不确定笔画统一进入 `preserved`，避免为了“用户确认”增加状态和 UI。

## 4. 目标架构与关键契约

### 4.1 模块边界

新业务模块位于 `FlowMuse-App/lib/features/whiteboard/smart_layout/`：

| 目录 | 职责 | 禁止 |
| --- | --- | --- |
| `models/` | snapshot、region、semantic、candidate、metrics、state | Widget、HTTP、Scene 写操作 |
| `repositories/` | v3 HTTP、解析、错误翻译、取消 | 布局坐标、Scene 修改 |
| `services/` | snapshot、segmentation、assembler、planner、validator、scorer | UI 状态、SnackBar |
| `view_models/` | Session 状态机和用户动作 | Canvas、协议 JSON 拼装 |
| `views/` | 范围、校对、候选、无解、确认 | 识别规则和布局算法 |

`GeometryKernel`、`SceneTransformContract`、`ScenePatch`、`SceneReducer` 和 `DraftSceneRenderer` 默认是智能排版 feature 内部组件，不因名称看起来通用就迁入 `editor_core`。`editor_core` 只暴露最小 gateway，并复用已有 Scene、`ToolResult/CompoundResult`、History 和 renderer；VLM/OCR/排版目标与 Session 状态不得继续进入 `MarkdrawController`。

### 4.2 页面快照与 SceneRevision

`LayoutPageSnapshot` 至少包含：

```text
pageId / pageBounds / contentBounds / sceneRevision
objects[]:
  sourceId / memberIds / kind / bounds / visualBounds / rotation
  mobility(movable|protectedObstacle|background)
  groupIds / frameId / bindingRefs / zIndex
  exactText? / textStyle? / imageIntrinsicSize?
inkStrokes[] / renderAssets / sourceCoverage
```

`SceneRevision` 由页面级单调 revision、既有协作变更信号和规范化 fingerprint 组成。通过现有 editor change/reconcile/load/reset 边界观察变化，不重写 History 或 LWW 流程；fingerprint 覆盖元素、文件、文档元数据和绑定，只用于智能排版完整性校验，不替代 CAS。

typed text 始终来自 `exactText`。Snapshot 创建唯一不可变的 `SourceCoverageLedger`；后续 SemanticDocument、LayoutBlock、ScenePatch、Draft Scene 和 metrics 只透传并校验同一 ledger/hash，不创建第二套 source 状态。处理中允许 pending，最终每个源对象只能是 consumed 或 preserved。

### 4.3 笔迹区域分割

首版使用纯 Dart 确定性算法，不训练模型：

- 局部笔画尺度归一化，而不是跨页面固定 pt。
- 空间邻接图和连通分量，而不是只与上一笔链式合并。
- deskew、列检测、line/formula/table/emphasis 分类。
- merge/split 防护和用户 correction patch。
- R-tree 或现有空间索引；禁止 3000 笔画页 O(N²) 全配对。

算法常量是待校准参数，不在计划中伪装成已证明真值。development 用于原型，validation 用于一次参数选择，Gate 1 后冻结；frozen holdout 不得参与调参。独立报告 region precision/recall、merge error、split error 和最差分组。

若区域不确定且用户不修正，原 stroke 保留原位，不自动替换。

### 4.4 v3 分析协议

端点：`POST /api/ink/smart-layout/analyze/v3`。服务端以独立 `V3Analyzer/RegisterV3` 实现，不让旧 `SmartLayouter` 兼任新协议。

协议由 JSON Schema 定义。canonical request 必须关联 `pageId`、`sceneRevision`、`fingerprint`、annotated/clean/crop assets、marks、typed `exactText`、source refs 和 asset hash；服务端不得从图片重建 typed text：

- `nodes[]`：id、sourceRefs、kind、text、level、readingOrder、text/role confidence。
- `relations[]`：from[]、to[]、type、confidence、evidence。
- `unassignedRegions[]`、warnings、schema/model version。
- 明确 one-to-many、many-to-one、split、merge 和 unknown。

sanitize 必须保证引用合法、readingOrder 完整、关系无环、typed text 服务端回填原文、未分配区域进入 preserved。核心协议禁止动态 map 穿透。

Dart/Go 必须消费同一组 positive/negative fixtures；除 handler contract 外，还要启动真实 server/mux 和 `V3Analyzer/RegisterV3`，对完整路径做 synthetic live-route smoke，覆盖 body limit、能力、超时、取消、错误映射和响应 schema。fake provider 不能替代真实路由或客户端—服务端联调证据。

复核必须改变输入或识别路径：总览负责 role/order/relation，高清 crop 负责 OCR/公式；不能原图原提示词原模型重复询问。网络层复用现有 `NativeHttpClient` 和部署基础设施，不在智能排版范围内新增政策、审批或独立安全框架。

### 4.5 语义文档与纠错

`LayoutSemanticDocument` 保存 title、sections、blocks、relations、readingOrder、sourceCoverage、conflicts 和 persistenceVersion，不含最终坐标。

客户端只做可解释校验：引用、顺序补全、关系去环、unknown 保留；禁止“短于 12 字抬标题”等暗规则。

`SemanticCorrection` 支持 role、order、caption relation、region merge/split、preserve/protect。每次修正保存显式 patch；Phase 2 只完成受影响 crop、节点和关系的语义重算，Phase 5 再根据稳定 affected source keys 重跑 planner、patch、renderer、metrics、hard gate 和 scorer。局部最终结果必须与全量重跑深度等价，旧验证候选全部失效。

`SemanticDocument ↔ SmartLayoutDocument` 的版本化持久化映射必须在构建 ScenePatch 前冻结，并覆盖旧版本读取和未知字段。

### 4.6 布局生成

布局器消费统一 `LayoutBlock`：

```text
id / semanticKind / sourceRefs / presentation(transcribed|preserved)
intrinsicSize / minSize / maxSize / preferredAspectRatio
textMeasure(width,fontTier) / canScale / canWrap
keepTogether / keepWithNext / visualWeight
```

先用少量宏观决策生成候选，再确定性流式排版：

- 骨架：single、two-column、main-side、`conservative-layout`。
- 原语：title、heading、paragraph、list、formula、figure-card、side-note、protected-zone、preserve-block。
- 参数只来自冻结 design tokens；完整候选上限 12，最终展示最多 3。
- 生成期仅做 source coverage、关键 relation、最小面积和粗几何等单调硬可行性 preflight；不得读取软分、profile、当前排名或“能否超过当前候选集”。最终门禁必须等待真实 Scene。
- 小 fixture 用全枚举 oracle 验证剪枝没有漏掉任何满足硬可行性的结构。

三个用户目标共用生成器和硬约束，只使用三套固定、可验证的排序 profile。保留手写走同一布局管线的 preserved block。

`conservative-layout` 是仍会改写布局、必须经过完整真实门禁的生成候选。原结构零修改另以 `preserveFallback` 结果类型表达，它不是 `LayoutCandidate`，不进入 scorer、结构配额、合格率或 Top 3。若原场景本身越界、重叠或被障碍占满，fallback 只能解释保留结果，不得宣称通过硬约束，也不得用它降低 no-candidate rate。

### 4.7 文本、图像和设计令牌

文本必须通过编辑器实际 TextPainter/font resolver 在目标宽度测量，覆盖 CJK、长词、emoji、RTL、公式、widow/orphan。禁止字符数估算和省略号掩盖溢出。

图片首版只允许 contain 等比缩放，保留 intrinsic size、orientation 和现有 crop/transform，不做自动裁切。

本计划冻结令牌类别而非拍脑袋数值：字号层级、最小正文、行距、段距、栏沟、页边距、snap、行长、孤行、图文距离、密度目标。具体值由 V3-300 根据设计基线和 development pilot 得出，validation 确认后冻结。

### 4.8 SceneTransform、ScenePatch 与真实门禁

feature-private `SceneTransformContract` 明确智能排版可能触及元素的 move/resize/rotate 支持、坐标系、传播顺序和拒绝条件，覆盖 nested group、frame、bound text、bound arrow、line、freedraw、image、rotated element；它不替换 SelectTool 或其他编辑器变换路径。

所有主元素先变换，再在完整临时 Scene 上统一重算依赖。未覆盖类型拒绝 patch，禁止部分成功。

`ScenePatch` 是智能排版 feature 内的本地不可变事务对象，覆盖：

- element add/update/remove；
- 位置、尺寸、角度、样式、文本、points；
- groupIds、frameId、boundElements、index、version、versionNonce；
- file refs、SmartLayoutDocument、selection intent。

preview 通过 feature 内唯一 reducer 消费 patch；最终提交经最小 editor gateway 转为既有 `ToolResult/CompoundResult` 与 History 事务，不新增通用事务框架，也不得导出“提交任意 patch”的入口。协作只沿用现有元素变化、文件和文档通道，不新增消息类型或修改 reconcile/LWW 规则。

最终候选评估顺序不可改变：

1. ScenePatchBuilder；
2. SceneReducer 得到 Draft Scene；
3. DraftSceneRenderer 实际测量和渲染；
4. 硬约束：coverage、relations、reading order、visual bounds、裁字、比例、group/frame/binding；
5. 软指标：层级、顺序、图文亲和、对齐节奏、密度留白、视觉平衡、改动成本；
6. 反投机否决线；
7. profile 排序、去重和 Top 3。

只有完成上述全链且携带 patch、baseRevision、renderer/metrics/ledger hash 的结果才能封装为 `ValidatedCandidate`。唯一 compare-and-commit 入口只接受它，并在同一临界区复核 revision/fingerprint/hash 后调用同一 reducer；原始 patch、旧轮次候选和过期验证结果在类型/API 层都不能提交。

### 4.9 会话、取消和协作冲突

`SmartLayoutSessionState` 使用 sealed state：

```text
idle → capturing → segmenting → analyzing → generating
     → reviewing(candidates|infeasible) → committing → completed
任意非终态 → failed(stage,retryable) | cancelled
reviewing ↔ generating  // 纠错、换目标、调整排版
```

每次会话携带 operationId、pageId、baseSceneRevision 和 cancellation token。任何 async continuation 更新状态前检查 operation/page/revision/disposed。

Draft 内候选切换、拖动和选择只修改本地 patch，不修改权威 Scene、History、revision 或协作状态。

确认时在同一临界区 compare-and-commit。权威 Scene 被本地/远端修改时零写入、零 History、零广播；先应用远端变化，再判断 patch 写集是否相交，不相交可基于新 revision 重派一次，相交则要求重新分析。

本重构不新增协作 presence 字段，也不重构 LWW/reconcile；冲突安全只在智能排版 gateway 处读取既有变更信号、做 CAS 和本地提示。

## 5. 效果评测与发布门禁

评测采用两条连续工程线。`ai_synthetic_development` 用确定性合成数据和独立 GLM-5.3 Max 代理盲审驱动实现，证明自动契约和 AI 代理裁判下的候选质量；`competition_delivery` 用当前可用环境的端到端 smoke、合成故障注入和隔离测试证明项目可稳定演示。比赛交付不等待六端设备、生产流量、消费者 census 或外部运维输入。

### 5.1 数据集

- development：至少 30 页确定性合成页面，可用于调试。
- validation：至少 30 页，按生成种子/原稿/派生链与 development 隔离，只允许有限次数参数选择。
- frozen holdout：60-72 页合成页面，按场景族聚类；实现者不可查看逐页答案。

覆盖纯手写、纯打字、混合文本、图文交错、长文、列表、公式、形状、组、frame、绑定、锁定、整洁页、散点页、竖排保留模式、装饰线、3000 笔画压力页和当前已知失败页。

validation/frozen 的 region、role、order、relation 由两个上下文隔离的 GLM-5.3 Max 代理盲标，第三个独立代理只仲裁分歧；所有 run id、盲化输入、原始输出和一致性统计留档。该结果标记 `ai_surrogate`，一致性未达门槛的样本不进入开发指标。frozen 每套只允许一次正式判定。

FixtureManifest 固定 Scene、图像、字体、DPR、locale、时钟、随机种子、元素 id/versionNonce、schema/model hash、录制响应、期望 coverage/relations 和 renderer golden。自动测试不访问真实网络。

### 5.2 三条基线和分层指标

开发线必须同时对比：no-op 原稿、v2、AI 专家代理整理；AI 基线不产生真人完成时间或真人偏好结论。本计划不增加真人偏好研究或相关审批任务。

| 层 | 指标 |
| --- | --- |
| snapshot | source recall、typed text、group/frame/binding 完整率 |
| segmentation | region P/R、merge/split error、最差分组 |
| analysis | CER/WER、role macro-F1、order pair accuracy、caption relation |
| candidate | 可行解覆盖、无解准确率、no-candidate rate、反投机通过率 |
| layout | 越界、重叠、裁字、字号、比例、对齐、间距、密度 |
| transaction | preview=commit、CAS 零写入、undo/redo、late response、LWW |
| experience | 到可接受结果时间、纠错次数、后续修改、撤销/放弃、盲选偏好 |

### 5.3 开发门禁与比赛交付门禁

Gate 0～5 使用 AI/synthetic 证据决定是否继续实现；下列质量条件中的 rubric/基线/偏好均解释为 AI surrogate。通过后生成默认关闭的比赛候选版本，V3-700A～V3-705A 再完成本地/演示 smoke、合成稳定性、v2 隔离证明和最终交付审计。

所有条件必须同时满足：

1. frozen 中所有 critical error 为 0。
2. typed text 100%；segmentation/OCR/role/order/relation 达 Gate 0 冻结阈值，并报告最差分组。
3. 展示候选硬约束违规为 0；no-candidate 统计包含全部页面，不能用不出结果规避失败。
4. no-op、极缩、隐藏文本、大空白、单对象、全标题化等投机样本不能进入 Top 3。
5. 自动 score 与 AI surrogate rubric 达冻结相关性；否则 scorer 只能过滤，不能标“推荐”。真人相关性属于发布后续证据。
6. 两个独立 AI persona 完成盲评，第三代理仲裁；不得称作目标用户、原作者或第三方真人研究。
7. v3 相对 no-op/v2 减少代理操作步骤和修改次数；相对 AI surrogate baseline 的差距在预注册容忍区间，不推断真人耗时。
8. 整洁页相对 no-op 非劣；frozen v3 对 v2 偏好目标不低于 70%，预注册 95% 区间下界高于 50%。
9. Flutter/Go/协议/兼容/性能全绿；当前可用平台实际构建，其他平台保留 deferred matrix，不阻断比赛交付。

## 6. 任务分解

共 8 个阶段、52 个唯一工作包。任务以 Gate 而非日期推进；每项必须有产物、自动验证和退出条件。配套计划将 Phase 0 已完成的 13 项原样保留，并把后续工作按内聚实现/验证边界合并为 56 项，共 69 个可执行任务；目标能力、硬约束和 Gate 均不减少。本节编号保持为稳定的上层工作包。

### Phase 0：冻结质量协议

#### V3-000 失败分类与 AI 代理 rubric
- 产物：critical/major/minor、允许关系、禁止模式、1-5 分 rubric。
- 退出：两个隔离代理盲评、第三代理仲裁，证据明确非真人评审。

#### V3-001 FixtureManifest 与确定性 runner
- 固定字体、DPR、时钟、随机、规范化 patch 和 benchmark 的主机/OS、warm-up、缓存、并发、P50/P95、峰值内存与超时口径；record/replay 只用合成内容。
- 退出：种子 fixture 连跑三次 hash 一致。

#### V3-002 建立 development/validation/frozen 数据集
- 开发线只使用确定性合成样本，按生成种子/原稿/派生链隔离，完成双代理盲标和仲裁。
- 退出：类别覆盖和标注一致性达标。

#### V3-003 测量 no-op、v2、AI surrogate 整理基线
- 输出分层指标、操作时间、修改次数和最终 Scene/PNG。
- 退出：同一 runner 可重复生成报告。

#### V3-004 预注册阈值、统计和 golden 审批
- 用机器可读 `EvaluationSpec` 冻结估计量/效应量、聚类分析单位、CI/检验、缺失和多重比较、功效、分母、停止规则、benchmark 预算、frozen 一次性使用和 score 相关性门槛；rubric、spec、benchmark 和 golden 全部有版本/hash。
- Gate 0：AI 盲审、仲裁、spec/hash 未冻结不得调 planner/scorer；通过只代表开发质量协议已冻结。

### Phase 1：Snapshot、分割与会话隔离

#### V3-100 建立最小 feature 骨架
- 只建立智能排版 feature 和 HTTP/editor 最小 gateway，不建注册表、插件系统或通用 editor 框架。

#### V3-101 页面级 SceneRevision 与 fingerprint
- 从既有 change/reconcile/load/reset 边界观察 local/remote/undo/redo 变化；不改写 History/LWW，跨端 fingerprint 规范化一致。

#### V3-102 LayoutPageSnapshot
- 区分 movable/protected/background，封装 group/frame/binding、typed text 和全链唯一 `SourceCoverageLedger`。

#### V3-103 InkRegionSegmenter 原型与校准
- 实现局部尺度、deskew、columns、line classification 和空间索引。
- development 调试、validation 选择一次、随后冻结参数。

#### V3-104 Region correction patch
- merge/split 在本阶段只计算受影响 region/crop 集；语义重算归 V3-205，候选与评分重跑归 V3-504。

#### V3-105 Render asset/crop builder
- clean/annotated/crop 分离，所有 image/picture/codec 异常路径释放。

#### V3-106 Operation 状态机与 editor gateway
- 实现 operationId、cancel、late-response、page/dispose 防线。

### Phase 2：强类型分析与语义纠错

#### V3-200 JSON Schema、错误和能力协议
- 固定完整端点和关联 page/revision/fingerprint、assets/marks/exactText/source refs/hash 的 canonical request；Dart/Go 消费同一 positive/negative fixtures，核心协议无动态 map。

#### V3-201 独立 V3Analyzer 与 strict sanitize
- typed text 回填、引用/基数/环/长度校验；接入现有 HTTP 基础设施，实现请求限制、超时、取消、错误映射与真实 server/mux live-route smoke。

#### V3-202 总览 + crop 分级复核
- 总览做 role/order/relation，crop 做 OCR/formula；保存冲突而不静默择一。

#### V3-203 可取消 AnalysisRepository
- 复用 NativeHttpClient；每个 continuation 四检后才能更新状态，并以真实 synthetic server 完成端到端联调；capability off 时不发请求。

#### V3-204 SemanticDocumentAssembler 与持久化 schema
- 只投影并校验 Snapshot 的唯一 source ledger，unknown/unassigned preserved；冻结 SmartLayoutDocument 版本映射。

#### V3-205 SemanticCorrection
- role/order/relation/region/protect 修改为显式 patch，本阶段只交付局部语义重算和稳定 affected source keys。

#### V3-206 分析层 Gate 1
- 报告 segmentation、CER/WER、role/order/relation、最差分组和校准误差。

### Phase 3：测量、几何和变换契约

#### V3-300 Design tokens 与真实文本测量
- 冻结字号、行距、间距、栏宽、snap、孤行规则和测量缓存。

#### V3-301 GeometryKernel
- 在 smart_layout feature 内复用既有 bounds/helper，只补排版缺失的 visual bounds/OBB 或有证明的保守 AABB；不替换编辑器全局几何实现。

#### V3-302 SceneTransformContract
- 仅列智能排版会触及元素的 move/resize/rotate 坐标系、传播顺序和拒绝条件；不重构 SelectTool。

#### V3-303 智能排版纯场景变换器
- feature 内完成主元素变换后统一重算 group/frame/bound text/arrow/points；不导出为通用 editor API。

#### V3-304 相邻编辑行为防回归
- 只为本次实际触及的既有 helper 固定调用者快照；优先保留 API 或用薄 adapter，禁止迁移 SelectTool、思维导图或其他消费者。

#### V3-305 变换 Gate 2
- move/resize/rotate/group/frame/binding/line/freedraw/image 深度 fixture 全绿。

### Phase 4：候选生成与评分契约

#### V3-400 BlockAssembler 和版面原语
- SemanticDocument → LayoutBlock；实现 skeleton/text/figure/formula/preserved/protected 原语。

#### V3-401 宏观候选 planner
- 有界枚举、唯一结构配额、只基于硬可行性的下界剪枝和测试专用全枚举 oracle；软分与当前排名不得参与剪枝。

#### V3-402 确定性流式排版
- reading order、目标栏宽换行、keep、栏平衡、contain 和保留手写。

#### V3-403 生成期 preflight 与 NoFeasibleLayout
- 只做 coverage/relation/粗几何剪枝；零修改 `preserveFallback` 与会改写布局的 `conservative-layout` 明确分型，前者不冒充候选。

#### V3-404 三个目标 profile 与评分公式
- 共享硬约束和指标，分别冻结排序偏好和反例；只引用 Gate 0 的唯一 rubric 版本，不复制定义。

#### V3-405 结构去重与真实 Scene metrics 契约
- 完成流式 placement 后只去契约定义的等价结构，结构配额仍归 V3-401；不在此阶段选最终 Top 3。

#### V3-406 Planner Gate 3
- 穷举对照、可行解漏检、无解误判、结构多样性和本地性能达标。

### Phase 5：ScenePatch、真实预览和用户工作流

#### V3-500 完整不可变 ScenePatch
- 在 smart_layout feature 内覆盖元素、文件、文档、selection 和排版实际涉及的 Excalidraw 关系/版本字段，不建立全编辑器 Patch 框架。

#### V3-501 纯 SceneReducer
- feature 内 preview 使用唯一 reducer；最终结果通过既有 ToolResult/History gateway 提交，不新建通用 History transaction 框架。

#### V3-502 compare-and-commit
- 唯一提交入口只接受 `ValidatedCandidate`，复核 base revision 与 renderer/metrics/ledger hash；冲突时零 Scene/History/broadcast，写集不相交只重派一次。

#### V3-503 DraftSceneRenderer
- 复用真实 renderer、字体、图片和公式；ScenePatch + pixel golden。

#### V3-504 真实场景硬门禁与最终评分
- Reducer/Renderer 后提取 metrics，先 source 守恒和其他硬约束/否决线，再 profile 排序 Top 3；纠错后重跑受影响 planner 到 scorer 全链并使旧候选失效。

#### V3-505 校对、候选和无解 UI
- 覆盖范围选择、纠错/全文核对、真实候选比较、无解/取消和可访问性，并在 Gate 4 前接入真实智能排版编辑器入口；公开调用签名保持稳定，范围外调用者不改。

#### V3-506 事务与体验 Gate 4
- preview=commit、undo/redo、cancel/late、draft 拖动、local/remote 冲突、重跑全绿。

### Phase 6：完整验证

#### V3-600 Excalidraw/协作兼容验证
- 用 old/new reader-writer、双端 LWW、index/versionNonce、group/frame/binding fixture 验证 v3 输出；不修改协议、LWW 或 codec 架构。

#### V3-601 文档持久化与既有导出兼容
- 验证旧 Scene 读取、新 Scene 写入和现有 Markdown/LaTeX 出口；不新增格式、不重构 exporter，只对 v3 新文档映射做最小适配。

#### V3-602 可复制 CI/fixture 矩阵
- 固定 runner、字体、fixture server、报告和退出码。

#### V3-603 Flutter/Go/协议全门禁
- format/analyze/test、Go test/vet、schema、round-trip 全绿。

#### V3-604 性能、资源和压力
- 3000 笔画、100 块、长页、PNG 内存、取消/离页资源释放。

#### V3-605 可用平台构建与冒烟
- 固化 Android、iOS、macOS、Windows、Web、OHOS 构建/设备协议；当前可用目标实际执行，不可用目标写 `release_deferred` 和恢复命令，不顺手修复无关平台问题。比赛交付接受不可用平台的明确边界。

#### V3-606 frozen 双盲任务实验与 Gate 5
- 兼容、既有导出回归、CI、性能和可用平台证据完成后执行；两个隔离 AI persona 盲评、第三代理仲裁、整洁页非劣、AI surrogate baseline 和 score 相关性达到开发门禁。不得冒充原作者或第三方真人。

### Phase 7：比赛演示与交付

#### V3-700 fail-closed capability 与演示环境 smoke
- 无缓存或缓存过期默认 off；服务端确认 v3 可用后才开启。kill switch 关闭入口，不回退 v2。
- capability/kill switch 和观测代码先用合成输入完成；客户端入口可切到 v3 实现但默认关闭。
- V3-700A 在 V3-701A 后启动本地或演示环境，运行入口→候选→commit→undo→reopen smoke，并覆盖 capability off/on、kill switch 和服务故障。
- instrumentation、指标 schema、告警和 kill-switch 信号用合成事件验证，不额外建设生产观测环境。

#### V3-701 客户端 v3 单路切流
- 智能排版公开入口代码走新 Session，保留其稳定调用签名；现有调用者无需迁移，保留整体 Git 回滚点。演示显式开启前 capability 默认 off、请求为 0。

#### V3-702 合成稳定性与故障注入
- 固定样本、种子和 runner，注入 offline、timeout、429、5xx、坏 schema、取消与迟到回调，以错误率、拒绝率、阶段耗时和 critical=0 为证据。

#### V3-703 客户端 v2 隔离与保留
- 静态扫描与自动测试证明公开入口只到达 v3 Session；v2 私有实现原位保留作为比赛项目的参考与回退边界，不做消费者普查、迁移或删除。

#### V3-704 服务端旧端点隔离与保留
- 用路由矩阵和 Go 测试证明旧端点与 v3 端点独立、无路径冲突；旧端点保留，不做消费者 census、410 或实现删除。

#### V3-705 比赛交付包和最终审计
- 同步接口/前端架构/需求、模型使用记录和范围偏差；汇总测试、演示步骤、已知平台边界和回滚点，由机器检查链接与任务状态。

## 7. 依赖关系

```text
000 → 001 → 002 → 003 → 004 (Gate 0)

100 → 101 → 102 → {103 → 104, 105, 106}
200 → {201 → 202, 203(real server integration)} → 204 → 205 → 206 (Gate 1)
                                                   104 ───────┘

300; 304A(touched-helper baseline); 301 → 302 → 303(core)
                 {303(core),304A} → 303(smart-layout integration) → 304B(compatibility check) → 305 (Gate 2)
{206,300,301} → 400 → 401 → 402 → 403 → 404 → 405 → 406 (Gate 3)

{204,305,403} → 500 → 501 → 503
{404,405,501,503} → 504 → 502(validated commit)
{106,203,205,502,504} → 505(real smart-layout entry) → 506 (Gate 4)

{501,506} → {600 → 601, 602 → 603, 604, 605}
{600,601,602,603,604,605} → 606 (development Gate 5)
606 → 700B(capability + observability) → 701(default-off code switch + rollback)
701A → 700A(demo smoke) → 702(fault injection) → 703(client isolation) → 704(server isolation) → 705
```

任务卡中的直接依赖为权威；上图只表达主链。热点文件 `markdraw_controller.dart`、`whiteboard_page.dart`、协议 schema、design tokens、评分公式和 golden 必须单负责人串行。

## 8. 切流与回滚

- capability、观测和入口代码先以默认 off 完成；只在本地或演示环境显式开启。
- 客户端公开入口保持单路 v3；异常时关闭智能排版入口，不自动回退旧算法。
- v2 客户端代码和服务端旧端点原位保留；隔离测试防止公开入口误接旧实现。
- 每个 Gate 对应一个可回退提交边界；不得恢复零散旧类形成第三种混合架构。

## 9. 关键风险与应对

| 风险 | 应对 |
| --- | --- |
| 分割参数过拟合 | 参数先校准后冻结；来源隔离 validation/frozen；报告最差分组 |
| 指标好但页面仍难看 | 用真实 renderer、AI surrogate rubric、操作成本代理、隔离盲审和比赛演示页共同检查 |
| no-op/极缩骗分 | 硬约束、否决线、反投机 fixture、开发期 score-AI-surrogate 相关性；不得写成 score-human |
| 保守 fallback 被当成成功 | fallback 单独标记，不计入合格候选和 no-candidate 成功率 |
| preview/commit 不一致 | 单一 ScenePatch/Reducer、深度等价、一次 History |
| 协作覆盖用户编辑 | revision+epoch+CAS、写集相交检测、LWW fixture |
| kill switch 在故障时失效 | capability 无缓存 fail-closed，缓存过期后明确提示不可用 |
| 公开入口误走旧算法 | 静态扫描、入口测试和 v2/v3 路由隔离；旧实现保留但不可由公开入口到达 |
| 跨端字体和渲染差异 | 共享逻辑无平台判断；规范化 Scene 跨端一致，平台 golden 分开维护 |

## 10. 最终完成定义

核心代码在 Gate 5 与 V3-701A 通过后视为开发完成；V3-700A～V3-705A 满足以下条件后可声明 `competition_delivery_complete`：

1. §5.3 全部发布门禁通过，frozen critical error 为 0。
2. 真实场景硬约束和反投机测试全绿；没有合格候选时明确拒绝。
3. preview/commit/undo/redo/协作/重开深度一致，CAS 冲突零写入。
4. Excalidraw、LWW、old/new reader-writer、既有导出和持久化兼容回归全绿，且未修改其架构或协议。
5. 当前可用平台构建/冒烟完成，不可用平台边界记录清楚且不阻断比赛演示。
6. 客户端公开入口只走 v3，v2 客户端代码与服务端旧端点保持隔离并原位保留。
7. 智能排版校验、协作兼容和跨端同步均有可运行的测试证据。
8. 架构、接口、需求、AI 使用记录和本计划执行结果同步完成。

## 11. 已关闭的计划缺口

| 原缺口 | 本版处理 |
| --- | --- |
| Scorer 位于 ScenePatch 前 | 全文统一为 Patch→Reducer→Renderer→Hard Gate→Score |
| `V3-704` 悬空和复合编号 | 52 个上层工作包全部使用唯一三位编号；叶子任务在配套实施计划中使用 A/B/... 后缀，且经过唯一性与父项覆盖检查 |
| 比赛期限、人力容量、夜间和降档主导架构 | 全部删除，只按 Gate 推进 |
| 一期只做 3 项评分、二期再补质量 | 七项指标和完整 frozen 是开发完成条件；比赛交付只要求当前可用环境 smoke 和明确的 deferred matrix |
| “保守骨架任意页面恒可行” | 分离会改写布局且必须过门禁的 `conservative-layout` 与零修改 `preserveFallback`；后者不是候选 |
| capability 无缓存默认 on | 改为 fail-closed 默认 off |
| presence 扩字段却声称不改协议 | 删除该扩展，复用现有冲突机制 |
| 分割常量未经证据即冻结 | 改为 development/validation 校准后冻结 |
| 多轮审查只有自述结论 | 最终以任务编号检查、Gate 报告和可运行命令为审计证据 |
| 语义纠错停在局部文档 | 新增 Phase 5 纠错重跑协调任务，从 affected source keys 重跑候选、Patch、真实渲染、门禁和评分，并使旧候选失效 |
| 预览 adapter 可绕过真实门禁直接提交 | commit API 只接受带 revision 与 renderer/metrics/ledger hash 的 `ValidatedCandidate`；原始 patch 在类型层不可提交 |
| 生产入口和真实服务只在切流时验证 | Gate 1 加真实 server/mux live-route 与客户端联调，Gate 4 前接真实智能排版编辑器入口；范围外调用者保持不变 |
| 切流后才建立观测 | instrumentation、dashboard、alert 和 kill-switch 信号在切流前用合成事件验收 |
| 比赛阶段强制退役旧端点 | 改为自动证明 v2/v3 路由隔离并保留旧端点，避免无收益的迁移和删除风险 |
| 智能排版重构扩张到 AI 助手、SelectTool 和通用 editor | 新增三层范围；组件默认 feature-private，相邻能力只做最小兼容回归，其他消费者不迁移 |

## 12. 实施第一步

当前 V3-000A 至 V3-701A 共 64 项及 Gate 0～5 已完成。后续从 V3-700A 继续比赛交付，不回滚或重做已完成证据。

Gate 0 通过前不得实现页面专用规则、调整 scorer 权重或把单张截图当成功证据。后续每个阶段都必须回答：**哪一层变好了、最终任务是否减少人工、失败是否被安全拒绝。**

## 13. Agent 执行层

配套实施计划的 69 项执行任务已生成机器可读的 [Agent Execution Manifest](smart-layout-v3-agent/agent-execution-manifest.json)，使用方法和证据格式见 [执行说明](smart-layout-v3-agent/README.md)。该执行层不改变本架构范围，只把任务依赖、路径/符号边界、命令、退出码、必要复审、单任务提交、失败回退和 Gate 变成可机器检查的约束。

`scripts/smart-layout-v3/AgentExecution.ps1` 是唯一状态转换和 Gate 入口。剩余比赛任务不声明外部事实依赖，凭真实代码路径命令、hash 和提交边界验收；V3-700A～V3-705A 均为自动复审模式，不再派通用子代理。已完成的独立复审和效果面板证据保持原样。
