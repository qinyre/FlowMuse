# 智能排版 V3 独立识别链路实现规格（Spec）

日期：2026-09-16。状态：**定稿（v4，三轮评审通过）**。本文是实现级规格，从属于同日计划书
`2026-09-16-smart-layout-v3-independent-recognition.md`（已定稿，提交 `e3098da`）。

代码基线：`e3098da`。计划书基线 `d158d7c` 之后仅有计划书自身提交，无代码差异。

修订记录：
- v2 按第一轮评审修订（P1×5、P2×5）。
- v3 按第二轮评审修订——P1×2：A 账本状态/归属一致性（不只集合相等）、B 语义纠错闭环补齐
  （set-relations 现为空操作、preserve 不同步块与账本，均经代码核实）；P2×5：C 嵌套列表协议表达、
  D 识别图只含 target 笔迹、E 400/502 职责划分与部分批次语义、F 字号异常改为诊断不触发复核、
  G 评测区域对齐与错误转换率定义。章节结构与 R1–R9 对应关系不变。
- v4（定稿）：第三轮评审通过（无 P1），并入 3 项 P2 实施备注——P2-1 部分响应数组校验与
  全漏答语义（清理 §3.5"缺区域一律 502"残留表述）、P2-2 降级作用域与只读账本输入、
  P2-3 评测一对多对齐、同分歧义与部分转换。

## 0. 定位与裁决规则

1. 计划书负责目标、边界、验收口径；本 spec 负责字段、签名、规则、流程与测试的落地细节。两者冲突时以计划书为准，发现冲突必须停止并上报，不得自行改口径或改计划书。
2. 计划书 §1.2 冻结边界、§6.1 冻结区、§6.2 可改位置对本 spec 全文有效，不再逐条重复。
3. 本 spec 引用的代码锚点在基线 `e3098da` 核实过（含两轮评审逐条回查后的修正行号与能力核实）；执行时若锚点漂移，先核对再动工。
4. 本文中"必须/禁止"约束在计划书边界内生效；与计划书冲突时按第 1 条处理，不构成独立口径。

## 1. ID、版本与代次体系

| 标识 | 产生方 | 规则 | 生命周期 |
| --- | --- | --- | --- |
| `operationId` | 客户端 pipeline | 每次识别操作一个，UUID v4，≤64 字符。**显式用户纠错视为新操作**：新 `operationId`、新预算、`generation` 递增；自动复核/重分组/重试/结构请求不换操作、共享原预算 | 一次操作（含其全部阶段请求） |
| `requestId` | 客户端 | 每个 HTTP 请求一个，UUID v4，≤128 字符 | 单请求 |
| `sourceId` | Scene | 元素既有 id，不新建、不改写、不限制其字符形态（含 `r:` 前缀） | 永久 |
| `regionId` | 客户端分区层 | 沿用 `regionIdOf`：`r:` + 成员笔画最小 sourceId（`SL/correction/region_correction_patch.dart:3`） | 同成员集合幂等稳定 |
| `unitId` | 客户端装配层 | **显式命名空间前缀**：ink 单元=`ink:<regionId>`；原生文本/图片/保留单元=`native:<sourceId>`。Scene id 无字符约束，不得依赖 `r:` 前缀区分两类单元 | 同上 |
| `generation` | 客户端会话 | 首轮 0，每轮用户显式纠错 +1 | 纠错代次 |
| `groupId`（结构） | 服务端结构阶段 | `g1`、`g2`…仅结构命名空间，客户端只校验唯一性 | 单结构响应 |
| `assetId`（临时区域图） | 客户端资产层 | 会话内自增 `a<n>`，不写入 Scene、不伪造 fileId | 会话内 |
| 评测区域 ID | 评测工具 | `<caseId>/r<n>`，与运行时 regionId 无关（§12） | 数据集内 |

版本与指纹（三元组 + 两指纹，缺一不可，各自含义不同）：

- `sceneRevision{epoch, revision, fingerprint}`：沿 wiring 现有 revision tracker 取值（`SL/session/smart_layout_real_wiring.dart:540-560` 的 `_buildRequest` 捕获模式），表达 Scene 版本。
- `contentFingerprint`（≤64）：本次捕获**内容**指纹——源 id 集合 + 类型 + 几何 + 原生正文的确定性哈希，算法与 `SL/snapshot/deterministic_hash.dart` 同族。不等于 `sceneRevision.fingerprint`（后者是 tracker 的版本指纹），服务端仅回显、客户端回岸逐项比对。

每次异步回岸、生成预览、应用前校验：`operationId + generation + sceneRevision + contentFingerprint` 四元组，任一不匹配即丢弃结果。

## 2. 客户端模块布局：`SL/recognition/`

共 9 个文件，对应计划书 §4.2 的五类职责，不建 interface/factory/strategy 层：

| 文件 | 职责 | 关键导出（签名） |
| --- | --- | --- |
| `recognition_models.dart` | 请求/响应 DTO 与常量 | `schemaVersion = 'recognition-v3/1'`；`RecognitionStage {read, verify, structure}`；各 DTO 类（§3） |
| `recognition_json_reader.dart` | 严格 JSON 解析 | 镜像 `SmartLayoutV3JsonReader` 惯例（实例化见 `SL/protocol/smart_layout_v3_response.dart:14`），错误码表独立（§3.5） |
| `recognition_repository.dart` | HTTP 边界 | `Future<RecognitionResponse> send(RecognitionRequest req, {String? bearerToken, NativeHttpCancelToken? cancelToken, required Duration remainingBudget})`；内部仅调 `SmartLayoutHttpGateway.postJson`（`SL/gateways/smart_layout_http_gateway.dart:90`），`readTimeoutMs = min(45000, remainingBudget.inMilliseconds)`，总计时器到期主动 `cancelToken.cancel()` 在途请求；按 §3.5 映射错误 |
| `source_ledger.dart` | 源账本（识别期准入权威） | `SourceLedger.register/consume/preserve/assertAllSettled`；终态仅本类写入，向 `SemanticAssembly` 单向投影（§6.4），不与 patch 层并行维护终态 |
| `recognition_budget.dart` | 预算值对象 | `RecognitionBudget`（§6.2），含已耗计数与 `canSpend` 断言，测试可注入初值；生命周期规则见 §6.2 末条 |
| `recognition_pipeline.dart` | 状态机与编排 | `RecognitionPipeline.run(RecognitionCapture) → Future<SmartLayoutAnalysisOutcome>`（返回会话层 outcome 新变体，见 §10）/ `.cancel()` / `.state`（§6.1、§6.3） |
| `region_assets.dart` | 区域高清资产 | `RegionAssetBuilder.build(RegionRecord, RecognitionBudget)` → `RegionAsset{assetId, pngBytes, scale, paddingPx, targetSourceIds, contextSourceIds}`（§5） |
| `structure_recovery.dart` | 结构恢复 | **`Future<StructureResult> recover(...)`（异步签名，可能发一次结构请求）**：本地规则优先，触发条件命中才发请求（§7） |
| `semantic_adapter.dart` | 适配语义文档 | `SemanticAssembly assemble(RecognitionSessionResult, {required TextMeasureAdapter measure, required SmartLayoutDesignTokens tokens})`——产出与 `SemanticDocumentAssembler.assemble` 相同的 `SemanticAssembly` 类型（`SL/semantics/semantic_document_assembler.dart:7`），账本字段由识别账本投影生成（§6.4） |

镜像测试目录 `SLT/recognition/`。`smart_layout_real_wiring.dart` 与 `smart_layout_session_view_model.dart` 的改动按 §10 执行。

## 3. 网络协议：`POST /api/ink/smart-layout/recognize/v3`

### 3.1 通用请求字段

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `schemaVersion` | string | 必须 `"recognition-v3/1"`，否则 400 |
| `stage` | enum | `read` / `verify` / `structure` |
| `operationId` | string | 非空，≤64 |
| `requestId` | string | 非空，≤128 |
| `pageId` | string | 非空，≤128 |
| `sceneRevision` | object | `{epoch:int≥0, revision:int≥0, fingerprint:string ≤64}` |
| `contentFingerprint` | string | 非空，≤64（§1 定义） |
| `generation` | int | ≥0 |

### 3.2 stage=read

请求追加 `regions`（1..8 个）：

| 字段 | 约束 |
| --- | --- |
| `regionId` | 非空 ≤64，批内唯一 |
| `imagePngBase64` | 非空；单条 ≤3MiB（Base64 编码后）；**图内只渲染该区域 target 笔迹**（§5.3），contextSourceIds 笔迹不进识别图 |
| `imageScale` | double>0 且有限（像素/页面单位） |
| `contextBefore` / `contextAfter` | 可选，≤200 字符，来自已定稿的相邻区域正文——邻区上下文唯一的传递通道 |

**批量字节口径**：限制对象是**编码后的完整请求 JSON（UTF-8）≤16MiB**，客户端按实际编码大小提前拆批（不只计区域数）；解码后图像尺寸（≤2MP、长边 ≤2048px）是另一层独立安全上限，由服务端校验。不存在 17MiB 口径。

响应 `regions[]` + `missingRegionIds[]`：

| 字段 | 约束 |
| --- | --- |
| `regionId` | 必须回显请求内已存在的 id |
| `status` | `recognized` / `uncertain` / `unreadable` / `nonText` |
| `text` | status=recognized/uncertain 时非空 ≤2000；其余必须缺省或空 |
| `confidence` | 可选 [0,1] 有限数 |
| `diagnostics` | 0..4 条，每条 ≤32 字符 |

**覆盖与部分批次语义**：`regions` 的 id 集合与 `missingRegionIds` 的并集必须恰等于请求集合、交集必须为空；**两个数组各自内部不得重复**（`regions=[a,a]、missing=[b]` 能通过并集/交集检查但非法）。合法的部分响应（模型漏答个别区域、其余可安全归属且由 `missingRegionIds` 完整声明）按 200 返回，客户端把 `missingRegionIds` 对应区域按 `preserve(reason: missingResponse)` 处理，不伪造成功或识别状态；**全部漏答（`regions=[]` 且 `missingRegionIds`=请求全集）是合法 200**，客户端整批保留；并集/交集/去重违规=结果无法安全归属，整批按 502 `invalidProviderResponse` 拒绝。`missingRegionIds` 由服务端从请求集合与合法结果求差生成，不依赖模型可靠声明。禁止为凑齐数组伪造区域结果。

### 3.3 stage=verify

请求 regions 追加：

| 字段 | 约束 |
| --- | --- |
| `originalText` | 可选 ≤2000（初读结果） |
| `originalConfidence` | 可选 [0,1] |
| `reason` | enum：`lowConfidence` / `suspectedMiss` / `maybeNonText` / `brokenNumbering` / `shapeMismatch` |

响应同 3.2（含同样的覆盖与部分批次规则）。

### 3.4 stage=structure

请求追加：

| 字段 | 约束 |
| --- | --- |
| `units`（1..128） | `{unitId(按 §1 命名空间), kind: typed\|ink\|figure\|preserved, text ≤2000, bounds{left,top,width,height} 全有限数, lineHintHeight 可选>0(页面单位，非像素), roleHint 可选 title\|body\|caption\|listItem}`。`text` 仅 typed/ink 单元非空；figure/preserved 单元必须缺省或空 |
| `overviewPngBase64` | 可选，≤3MiB（结构阶段理解整体关系用，是 context 笔迹可见的唯一图像通道） |
| `textFingerprint` | 非空 ≤64（客户端对全部单元 text 计算） |

figure/preserved 单元进入 `units` 的目的：作为图注目标、阅读顺序成员与障碍物——响应的关系引用必须能指向它们。

响应追加：

| 字段 | 约束 |
| --- | --- |
| `readingOrder` | `unitId` 有序数组，必须恰覆盖**全部** units（含 figure/preserved）各一次 |
| `roles` | `{unitId, role: title\|body\|caption\|listItem\|other}`，恰覆盖全部**文本**单元（typed/ink）、不重复；figure/preserved 的角色由 kind 固定映射，不出现在 roles |
| `listGroups` | `{groupId ≤16, members: unitId[] 有序, level: int ≥1, parentUnitId 可选, listType: ordered\|unordered, startNumber 可选 int}`。约束：顶层组（无 parentUnitId）members ≥2；**子组（有 parentUnitId）允许 ≥1（单项子列表合法）**；parentUnitId 必须属于另一 listGroup 的成员；父子引用无环；members 不跨组重复 |
| `captions` | `{captionUnitId, targetUnitId}`，二者必须存在；target 允许 figure/preserved 单元 |
| `warnings` | 0..8 条 ≤200 字符 |

**嵌套列表连续性**：readingOrder 中每个组的"完整列表子树"（成员及递归子组成员）必须构成连续区间——"父项 A → A 的两个子项 → 父项 B"合法，父级组 `[A,B]` 不要求自身成员相邻。原始编号保存在各成员正文文本内（输入只读），组级仅记 `startNumber`。

structure 请求**允许**携带只读正文（units[].text 是输入）；**响应不得产生正文**——`text` 出现在 roles/listGroups/captions 任一结构内归 502 `invalidProviderResponse`（§3.5）。

### 3.5 通用响应与错误

响应外壳回填表（服务端从请求回填，不依赖模型回显；客户端回岸逐项比对，不匹配按过期响应丢弃）：

| 回填字段 | 来源 |
| --- | --- |
| `schemaVersion` / `stage` | 请求同值 |
| `operationId` / `requestId` / `pageId` / `generation` | 请求同值 |
| `sceneRevision` / `contentFingerprint` | 请求同值 |
| `textFingerprint`（仅 structure） | 请求同值 |

**错误职责划分**：400 仅限**客户端请求不合法**（请求 schema、请求内 ID 重复、上限、请求几何/枚举非法）；**上游非法输出**（引用不存在的 id、覆盖声明不完整或数组含重复、structure 响应带正文、模型输出枚举非法）统一归 502 `invalidProviderResponse`；**可安全归属且由 `missingRegionIds` 完整声明的漏答不是错误**，按 §3.2 以 200 部分响应返回。错误体统一 `{"error":{"code","message","retryable"}}`：

| 状态 | code | retryable |
| --- | --- | --- |
| 400 | `invalidSchema` / `duplicateId`（请求内）/ `limitExceeded` / `textTooLong` / `badGeometry`（请求） | false |
| 401/403 | `auth` | false |
| 429 | `busy` | true |
| 503 | `unconfigured` | false |
| 502/504 | `providerTimeout` | true |
| 502 | `providerError`（provider 传输层/5xx） | true |
| 502 | `invalidProviderResponse`（模型输出解析、结构校验失败、覆盖声明不完整或数组含重复） | **false** |
| 500 | `internal` | false |

客户端 repository 将 `SmartLayoutHttpException` 与错误体映射为 `RecognitionException{kind, retryable}`；`retryable=true` 且预算允许时按 §6.2 重试一次。解析失败类（`invalidProviderResponse`）不重试；其整批语义见 §3.2——不可归属即整批无效，客户端不凭空恢复"其余成功区域"。

### 3.6 双端校验清单（编号供测试引用）

- R-01 请求内 regionId/unitId 重复；
- R-02 响应引用请求中不存在的 regionId/unitId（→502）；
- R-03 status 越枚举；text 超长或与 status 矛盾（nonText/unreadable 带非空 text、recognized 带空 text）（模型侧→502）；
- R-04 `regions ∪ missingRegionIds ≠ 请求集合`、交集非空，或任一数组内部含重复 id（→502 整批拒绝）；
- R-05 confidence 非有限数或越 [0,1]；bounds 含 NaN/Inf/负宽高；
- R-06 readingOrder 缺员、重复或未覆盖 figure/preserved；
- R-07 roles 未恰覆盖文本单元或包含 figure/preserved；
- R-08 listGroups 成员跨组重复、level/startNumber 非法、parentUnitId 悬空或成环、顶层组成员 <2；
- R-09 captions 悬空引用或自指；
- R-10 structure 响应携带正文字段（→502）；
- R-11 请求 regions/units 为空或超上限（→400）；响应 `regions=[]` 仅当 `missingRegionIds` 恰为请求全集（否则按 R-04 拒绝）；
- R-12 回填字段与请求不一致（operationId/generation/指纹/textFingerprint）。

请求侧问题服务端 400、客户端发送前自检；模型输出侧问题服务端 sanitize 后 502、客户端解析时同样校验（双保险）。非法结果不得进入可应用状态。

## 4. 服务端包：`FlowMuse-Server/internal/layoutrecognitionv3/`

文件与职责（镜像旧包 `V3Analyzer`/`RegisterSmartLayoutV3` 的结构惯例，见 `internal/recognition/smart_layout_v3.go:84,243`）：

| 文件 | 职责 |
| --- | --- |
| `dto.go` | 请求/响应 wire 结构体与常量 |
| `validate.go` | §3.6 入站校验 + 出站 sanitize：对模型输出先做覆盖/枚举/引用校验，不可归属修正的按 §3.5 归 502；可归属的个别缺失按 `missingRegionIds` 显式传递（§3.2），不伪造状态 |
| `provider.go` | `RecognitionProvider` 接口 `Complete(ctx, ProviderRequest) (string, error)`；默认实现 `OpenAICompatProvider`：std `net/http` 直连 chat/completions，多模态 image 内容（base64 data URL），超时与取消走 ctx；不 import 旧包算法 |
| `prompts.go` | `BuildReadPrompt/BuildVerifyPrompt/BuildStructurePrompt` 纯函数，单测锚定输出 |
| `handler.go` | `RecognitionHandler{provider, limits}`；`RegisterRecognitionV3(mux, handler)` 注册 `/api/ink/smart-layout/recognize/v3`；in-flight 信号量闸（容量 4），满则 429 |
| `limits.go` | 请求上限：编码后 JSON 体 ≤16MiB、批 regions ≤8、units ≤128、单图 base64 ≤3MiB、解码尺寸 ≤2MP/长边 2048、text ≤2000 runes |

Handler 行为：stage 分发 → 入站校验 → 组提示词 → provider 调用（ctx 取消透传）→ 解析模型输出（容忍 ```json 围栏，一次确定性剥离；解析或结构校验失败= `invalidProviderResponse`，**不重试**）→ sanitize → 响应。鉴权沿用既有部署校验，不新增旁路。

提示词骨架（中文，落 `prompts.go` 时按此口径展开）：

- **read**：系统角色=白板手写忠实转写器。规则：只输出图中可见文字（图中只含目标区域笔迹，邻区内容不在图内）；保留原换行（`\n`）与标点；不改写、不纠错、不补全、不润色；编号原样转写；无法辨认的区域输出 `status:"unreadable"`；确定非文字输出 `status:"nonText"`；每个 region 独立判断，不跨 region 拼接语义。输出 JSON 数组。
- **verify**：附原图、`originalText`、`reason`。规则：重新独立读图，图中不可见的内容即使原结果合理也不得保留；输出 `text/confidence`，与原结果一致也必须由图中得出。
- **structure**：输入只含 unit 元数据（id/kind/text/几何摘要/roleHint）+ 可选概览图。规则：只输出角色、阅读顺序、列表分组与层级（含父子挂靠）、图注归属；禁止输出或修改正文；禁止引用不存在的 id；列表按编号连续性与缩进判断，单项可作子列表；不确定的角色用 `other`。输出固定 schema JSON。

配置（`internal/config/config.go` 追加）：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `FLOWMUSE_LAYOUT_V3_BASE_URL` | 空 | 空=包不可用，路由返回 503 `unconfigured` |
| `FLOWMUSE_LAYOUT_V3_API_KEY` | 空 | 同上 |
| `FLOWMUSE_LAYOUT_V3_MODEL` | 空 | 同上 |
| `FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS` | 60 | **整数秒解析**（新增 `envIntSeconds`，`strconv.Atoi`；不得用 `envDuration`——该 helper 走 `time.ParseDuration`（`config.go:141`），裸数字会解析失败回落默认值）。服务端单次 provider 超时；客户端 §6.2 的 45s/剩余时限约束不因此放宽 |

`cmd/flowmuse-collab-server/main.go` 仅追加构造与 `RegisterRecognitionV3`，旧初始化与注册不动（旧 AI layouter 段 `main.go:105-117`）。

## 5. 区域高清资产

1. 输入为 `RegionRecord.bounds`（页面坐标）+ 捕获的 Scene 子集，经隔离的 `DraftSceneRenderer` 实例直接渲染（`SL/rendering/draft_scene_renderer.dart:132` 的 render 能力；独立实例、独立生命周期，不触碰预览渲染）。
2. 缩放目标：局部行高落在 48–96px；单图长边 ≤2048px、总像素 ≤2MP；留白 0.3×局部行高并裁到有效范围。超限先局部分区，不可安全拆分则整块保留原件。
3. **目标与上下文笔迹区分**：`RegionRecord` 显式携带 `targetSourceIds`（本区域待消费正文笔迹）与 `contextSourceIds`（相邻区域的边缘笔迹）。**首版 read/verify 识别图只渲染 target 笔迹**——模型读到的就是目标区域本身，不存在"图里混入邻区文字再靠提示词排除"的问题；邻区上下文的传递通道只有两条：请求的 `contextBefore/contextAfter` 文本字段（read/verify）与结构阶段的概览图（structure）。`contextSourceIds` 仅用于本地归属唯一性断言（同笔迹可以是多张资产的 target 或 context，但只在一个 target 集合中计为待消费）。未来若确需同图视觉上下文，必须显式定义目标标注方式与 provider 传递协议，本版不做。无法可靠区分 target 与 context 时合并区域或整体保留。
4. **小笔迹归属**：句号、小数点、编号点、短横线在分区层生成候选归属（最近文本区域且距离 <0.8×局部行高），禁止按面积小删除；无法确认归属的独立保留。
5. 浅色铅笔判定（笔画颜色亮度阈值，阈值进 `RecognitionBudget` 可注入）命中时，仅对临时资产做一次固定参数对比度增强；原图与笔迹样式不变；不重复发送原图+增强图双份。
6. 坐标变换保留完整闭环：pageBounds ↔ 局部坐标 ↔ 像素坐标；`imageScale` 必须与渲染参数一致并随请求上行；`lineHintHeight` 等尺寸提示统一换算回**页面单位**再进入结构请求。测试覆盖旋转、缩放、负坐标、非零原点、裁剪边缘。
7. 资产索引以 `assetId` 为主键（一笔迹可关联多张临时资产），同时维护 `sourceId → assetId[]` 反向索引供纠错失效使用；原生资产沿用 `fileId|ownerSourceId`（/`|crop`）既有约定。
8. 资产失败按区域隔离：单区域渲染失败该区域 `preserved`，不使整批失败。渲染 image 与临时 asset 在成功/失败/取消路径均释放。

## 6. Pipeline 状态机、预算与账本

### 6.1 状态机

`idle → capturing → proposing → rendering → reading → regrouping → verifying → structuring → assembling → done`

- 终态：`done`（含部分区域保留的"部分完成"）、`failed(kind)`、`cancelled`。
- **顺序约束（计划书 §3.4）**：先做至多一轮区域重分组得到**最终复核区域**，再发复核请求——`regrouping` 在 `verifying` 之前；不先复核再重分组。
- 取消检查点：capture 后、分区后、每张资产生成后、每批请求派发前、每批返回后、结构请求前后、装配前、发布前。检查点间最长不可取消窗口=单次请求（服务端 ctx 取消兜底）。
- `regrouping`（至多一轮）与 `verifying` 仅在下列**复核触发条件**命中时进入：初读置信低于阈值；文本形态区域返回空正文；被判 nonText 但局部笔迹形态像文字；编号断裂且空间上有候选续项；初读结果与区域形态明显不匹配。**结构请求触发条件另见 §7**，两表不混用。
- 总时限到期时主动 `cancelToken.cancel()` 取消在途请求，不只靠轮询检查；已有安全结果形成部分预览。

### 6.2 预算（`RecognitionBudget` 字段表）

| 字段 | 初值（=计划书 §5） |
| --- | --- |
| `overviewMaxEdgePx` | 2048 |
| `regionTargetLineHeightPx` | 48–96 |
| `regionMaxEdgePx` / `regionMaxPixels` | 2048 / 2MP |
| `regionPaddingLineHeight` | 0.3 |
| `batchMaxRegions` / `batchMaxRequestBytes` | 8 / 16MiB（编码后请求 JSON） |
| `firstRoundMaxRegions` | 64 |
| `verifyMaxRegions` / `regroupRounds` | 16 / 1 |
| `localRenderConcurrency` / `networkConcurrency` | 1 / 2 |
| `modelCallBudget` | 16（含拆批、重试、复核、结构） |
| `retryPerRequest` | 1（仅 `retryable=true` 且非 `invalidProviderResponse`） |
| `totalTimeout` / `perRequestTimeout` | 120s / 45s |

执行点：模型调用计数在派发前递减，不足则不发且该批区域保留；总时限用真实计时器（`Stopwatch` + 到期主动取消）约束。**预算生命周期**：一个 `operationId` 一个预算实例；显式用户纠错=新 `operationId`+新预算+`generation+1`；自动复核、重分组、重试、结构请求全部消耗当前操作预算，不刷新。

### 6.3 缓存

会话内 `cacheKey = f(contentFingerprint, 资产字节指纹, 提示词版本, 模型标识)`；命中直接复用结果，不计调用预算。无持久化缓存。

### 6.4 源账本、投影与转换准入

**真值与投影关系**：识别期终态（谁可被哪个 unit 消费、谁保留）的唯一真值是 `SourceLedger`；它向 `SemanticAssembly` **单向投影**——assembly 的 consumed/preserved 与 `sourceId → unitId` 归属由识别账本导出生成，下游（块装配、候选、物化）不得重新决定识别准入。patch/物化层继续消费既有 `SourceCoverageLedger`（快照构造，`SL/patch/smart_layout_scene_patch_builder.dart:30` 持有）；现有 materializer 第 0 步校验（`assembly.ledgerConserved` + `consumed ∪ preserved == 账本源集`，`SL/patch/candidate_patch_materializer.dart:116-137`）保持不动，作为第二道防线——但**集合相等不充分**（"识别账本保留、文档消费"也能过集合检查），因此新增：

1. **候选生成入口三方一致断言**（`runFromSemanticAssembly` 第 0 步之后，fail closed）：① 完整捕获源集合 − 背景剥离集 = 识别账本源集合 = assembly 账本源集合；② **逐源**终态（consume/preserve）一致；③ 每个 consumed 源的归属 unitId 在识别账本与 assembly/块 sourceRefs 间一致。任一违反即候选失败，不得静默取某一方。断言输入是 outcome 的 `recognition` 携带的**独立只读识别账本**——不得用 assembly 自身账目反推一份账本来"自证一致"。
2. **物化后置检查**：删除源 ⊆ 已批准替换集合（识别账本 consume 且 §6.4 准入七条件通过）；保留源未被删除或修改。
3. **单向降级规则与候选作用域**：**首版候选放不下直接淘汰该候选**——候选生成链逐候选放置（`smart_layout_real_wiring.dart:244` 起），不在候选循环中原地修改共享识别账本，避免候选 A 的降级污染候选 B。确需降级时，按完整 unit／必要组合闭包生成**新投影版本**（账本副本 + 块身份 + 障碍物同步）再重新生成候选，不改写已终结账本；禁止 preserve→consume 反向升级——该限制针对**自动处理**，用户显式撤销保留属于新纠错代次，按 §6.4 准入重新验证。降级后重跑守恒与三方断言。
4. **快照范围一致**：`runFromSemanticAssembly` 接收**完整捕获快照**，内部执行与旧入口第 0 步相同的 page-furniture 剥离（background 对象剔除、renderAssets owner 过滤、空页门控，`smart_layout_real_wiring.dart:88` 起），再与识别账本对账；不得接收已剥离的 layoutSnapshot 造成范围不一致。
5. **禁止重复终结**：materializer 终结的是快照侧 `SourceCoverageLedger`；`SemanticAssembly` 携带的账目是识别投影的只读输入，不得对其再次 markConsumed/markPreserved（现有账本禁止重复终结）。

`SourceLedger` 操作：注册（捕获时全量，**范围为排除背景后的识别源集合**，与第 1 条等式口径一致）、`consume(sourceId, unitId)`、`preserve(sourceId, reason)`、`assertAllSettled()`。不变量：每个源恰一次终态；consume 的 unit 必须已登记；发布前覆盖率 100%。reason 为有限枚举（`locked/binding/unreadable/nonText/userKept/budgetExceeded/assetFailed/missingResponse/contextOnly`…），不收自由文本。

**转换准入条件**（`recognized ≠ 可替换`；手写源被列入删除集合必须**同时**满足，物化前再校验一遍）：

1. 区域 status=recognized 且经复核规则未被推翻；
2. 转写正文 trim 后非空、非纯标点；
3. 区域覆盖完整：该 unit 消费的源恰为区域 targetSourceIds 全集，无缺员无越界；
4. 源类型守卫：全部为 FreeDraw 且非高亮笔刷；typed、ImageElement、图形及一切非 FreeDraw 源禁止进入删除集合；
5. 非保护对象：未锁定、无越界绑定；
6. 无未解决冲突（uncertain/复核冲突未消解的按保留处理）；
7. 版本有效：四元组（§1）校验通过且结构结果与正文指纹匹配。

**原生组合单元**（source-preserving 分支，落 `SL/patch/candidate_patch_materializer.dart` 扩展）：成员=group/frame/binding 闭包计算结果，经 `SmartLayoutSceneTransformer` 整体变换且同组只变换一次；闭包越界、含锁定/跨页成员或不完整时整组保留。测试落点见 §11。

## 7. 结构恢复

本地规则（`StructurePolicy` 值对象，阈值可注入）：

1. 有序列表：阅读顺序上连续 ≥2 个**文本**单元，文本匹配编号 `^\d{1,3}[.、)）](?!\d)`（编号分隔符后不得紧跟数字，排除 "1.2" 这类小数）或项目符号 `^[-•·](?![-•·])`，且**左缘 x 方向缩进一致**（容差 0.6×行高；纵向逐行下移不参与判定）。编号连续是强证据；孤立的 "1.2" 不成列表。`level` 由缩进层级差（每 ≥1×行高差进一级）推导，父子挂靠按"子组首个成员的缩进带对应最近上方父项"确定。
2. 标题：位于内容前 25% 纵向区间、局部行高 ≥1.3×正文行高中位数、单行且无句末标点（。！？；）、相邻正文存在落差（≥1.15×）→ `title`；任一不满足一律 `body`。
3. 图注：文本单元紧邻 figure/preserved 单元（同一缩进带、间距 <1 行高）且以 "图/注/Fig" 类起始词开头 → caption 候选；无唯一明确目标不入关系。
4. 原生文本仅绕过 OCR（零 read/verify 请求）；**结构是否需要模型仍按本节触发条件判断**——复杂原生多栏、多列表歧义同样可触发一次结构请求，不存在"全部原生文本必然本地完成"。

结构请求触发条件（任一命中才发，至多一次）：候选列表组 >1 且归属歧义；多栏重叠判定不一致；caption 候选无唯一目标；图文相邻关系冲突。触发时请求体按 §3.4，结果经 §3.6 校验后与本地结果合并：模型只改角色/分组/顺序/层级，正文与几何一律本地值为准；冲突未解标 `uncertain` 保留原件。验证失败回退本地保守结构。

## 8. 语义适配与 #14 字号规格

### 8.1 适配规则（`semantic_adapter.dart` → `SemanticAssembly`）

SemanticRole 真实枚举为 `title/body/caption/figure/formula/list/table/unknown`（`SL/semantics/semantic_document.dart:4-10`，`fromWireName` 未命中回落 `unknown` 且 `unknown → defaultsToPreserved`）。响应角色映射必须显式写死，禁止"同名映射"：

| structure 响应 role / 单元类别 | SemanticRole | 正文落点 |
| --- | --- | --- |
| `title` | `SemanticRole.title` | — |
| `body` | `SemanticRole.body` | — |
| `caption` | `SemanticRole.caption` | — |
| `listItem` | **`SemanticRole.list`** | — |
| `other` | **`SemanticRole.unknown`**（保留语义，不进排版流） | — |
| figure 单元（kind） | `SemanticRole.figure` | — |
| preserved 单元（kind） | `SemanticRole.unknown` | — |
| typed 单元正文 | — | `SemanticBlock.text` |
| ink 单元转写正文 | — | `extras['transcribedText']` |

- listGroup：extras 记 `listGroupId/level/listType/startNumber/parentUnitId`（嵌套挂靠进块元数据），同一**列表子树**的成员在 `orderedBlockIds`（Dart 阅读序字段，`semantic_document.dart:121`）中连续，并被 `LayoutBlockAssembler` 与候选校验消费；单项子列表合法。
- captions：extras 记 `captionOf: targetUnitId`，目标存在性在适配时校验。
- 保留/未识别源：生成带原始 bounds 的 preserved 块 + 障碍物身份，进入约束输入；不允许只躺在账本里。
- 适配产物为 `SemanticAssembly`（`semantic_document_assembler.dart:7`），账本字段由识别账本投影（§6.4），由 §10 的新候选链入口直接消费。

### 8.2 字号与行高（承接 #14，禁止旧启发式）

现有 token 实值（`SL/design/smart_layout_design_tokens.dart:90-93`）：`titleFloorSize=28`、`bodySize=20`、`minBodySize=12`、`lineHeight=1.25`。**不存在"正文/小号相邻两档"——12 是可读下限，不是常规档位。**

1. 禁止出现 `块高×0.72` 或 `块高÷行数×系数` 类外框反推；源码门禁测试拦截（镜像 `SLT/design/text_measure_adapter_test.dart:347` 起的门禁写法，新增 `SLT/recognition/sizing_gate_test.dart`）。
2. 首版字号规则：role=title → 28；其余文本单元（body/caption/listItem）→ 20。**源笔迹行高提示（页面单位）不参与选档、不触发复核**——手写原字大不构成识别错误；尺寸差异只作为诊断信息记入区域 diagnostics/警告，不产生状态机回跳。真正的文字/区域形态异常由 §6.1 既定复核触发表处理。
3. 行高=1.25×字号（token 倍数），后续以块组装阶段的实际行度量验证一致性。
4. **宽度相关测量全部留在既有块组装/放置阶段**（`LayoutBlockAssembler` 的 `TextMeasureAdapter` 路径）：适配阶段不存在候选栏宽，不做栏宽测量，避免"适配器测一次、组装又覆盖一次"。放不下时候选失败或保留原件；禁止无限缩小字号或裁字；`minBodySize=12` 仅作为组装阶段的极端下限校验，不作为选档输入。
5. 预览、patch、最终元素消费同一份字号与测量结果。
6. R6 回归集：单行/多行、合并后行数变化、中英混排、超高离群笔画、同字号不同裁剪留白、不同缩放/DPI——同一文字输出字号不因外框、截图倍率、区域合并而失控。

## 9. Correction / rerun 集成

1. intent 分流：merge/split 构造 `RegionCorrectionPatch`（现有 `CorrectionPatchApplier.apply/affectedSources`，`SL/correction/correction_patch_applier.dart:91,110`）——**分区纠错，触发受影响区域重识别**（§9.5）；role/order/relation/preserve 走 `SemanticCorrectionPatch`（`SL/correction/semantic_correction.dart:28-101`）——**语义纠错，不发 OCR 请求**。
2. **语义纠错闭环（R6/R7 补齐，权限依据=计划书 §4.3.1"所需调整限于现有 V3 correction/validation 接线"）**。现状经核实存在缺口，不得当作已接通：
   - `SetSemanticRelationsPatch` 目前是空操作（仅版本递增不写关系，`semantic_correction.dart:261` 的 `SetSemanticRelationsPatch() => bumped`）——R6 修复为真正写入图注/列表关系并校验目标存在；
   - `PreserveSemanticSourcesPatch` 目前只在文档 consumed/preserved 列表间搬移 id，不同步块角色、障碍物身份与 assembly 账本——R6 补齐为：应用 patch → 更新块角色/障碍物 → 按 §6.4 重建一致 assembly（含账本重投影与三方断言）→ 重跑候选；
   - 该分支的完整链：校验语义 patch（revision/目标存在性）→ 应用关系/角色/保留决定 → 重建 assembly → 候选重跑。逆操作同链，不得绕过替换准入。
3. **影响集合成为 before+after+完整资产索引**（仅分区纠错）：现有 `affectedSources()` 只遍历 before 状态的既有区域（merge 成员键、split 目标区域），不含 split 产生的新区域 id，且 `assetByStrokeId` 每笔迹仅单资产元组。新 correctionHandler 必须：(a) 经 `apply` 得到校验通过的 after 状态（被拒的 patch 不发布新上下文、不重跑）；(b) 影响区域 = before 受触区域 ∪ after 新建区域，笔画 = 前后成员并集；(c) 资产失效集来自会话资产索引（§5.7 的 `sourceId → assetId[]` 反向索引，含多临时资产），原生部分沿用 `affectedSources` 结果。不得单独依赖 `AffectedSourceSet.isEmpty`（该实现不检查 `cropKeys`）判空，包装层自做四集合完整性断言。
4. 会话在纠错调用开始时捕获**不可变**的 `RecognitionCorrectionContext{generation, operationId, affected, assetIndex, regionRecords}`；异步过程中不得反复读取可被下一次纠错覆盖的共享字段；发布新候选前校验代次。
5. `_rerunCandidateChain` 闭包消费该上下文（协调器 `CorrectionRerunCoordinator` 单参链签名不动，`SL/validation/correction_rerun_coordinator.dart:44-58`，包装层负责传递完整上下文）。
6. 重跑语义：显式纠错=新 `operationId`+新预算+`generation+1`（§6.2）；旧候选全失效（协调器已保证）→ 分区纠错重识别受影响区域 / 语义纠错按 §9.2 重建 assembly → 全页账本与覆盖校验 → 新候选走完整校验评分。未触区域仅在成员集合指纹、源内容指纹、识别配置指纹一致时复用。
7. `regionIdOf` 稳定但合并/拆分可能复用同一最小 ID：结果有效性判断必须同时校验成员集合指纹与分区 revision，不得只比 regionId 字符串。
8. **ViewModel 发布代次守卫**：`completeGenerationFromValidated` 的两个调用点（`SL/session/smart_layout_session_view_model.dart:485` 正常完成、`:633` 纠错重跑完成）发布前必须校验"捕获时 generation == 当前会话 generation"；旧代次重跑即使返回空数组也不得清空较新代候选。仅在 pipeline 内丢弃旧响应不够。

## 10. 会话接线与用户可见状态（R7）

`smart_layout_real_wiring.dart` 改动清单：

| 位置 | 改动 |
| --- | --- |
| `analysisRunner`（`:511-513`） | `useVisionAnalysis` 分支改调 `pipeline.run(capture)`，capture 复用 `_buildRequest` 的快照/revision 捕获模式 |
| `onCancelAnalysis`（`:516`） | 改调 `pipeline.cancel()`（新独立取消信号） |
| `_analyzeWithVision`（`:594`） | 退役删除；`_adaptVisionPreparation`（`:714`）同步退役 |
| `_lastResponse`（`:462`） | 移除，替换为 `RecognitionSessionState`（含 generation、区域状态、部分完成信息、纠错上下文） |
| `correctionHandler`（`:520` 起）/ `rerunChain`（`:526-527`） | 按 §9 接完整校正上下文，移除空 key 与旧响应重放占位 |

**类型连接（不造假 response）**：现状为 `analysisRunner → Future<SmartLayoutAnalysisOutcome>`，成功变体 `SmartLayoutAnalysisSucceeded` 携带 `SmartLayoutV3Response`，VM 在 `case SmartLayoutAnalysisSucceeded()`（`smart_layout_session_view_model.dart:457-461`）调 `candidateChain(response, ticket)`，`SmartLayoutRealCandidateChain.run({baseScene, snapshot, response, measure, tokens, profile, transcribedTextByRegion})`（`smart_layout_real_wiring.dart:79-131`）内部自建语义装配。改为：

1. 新增 outcome 变体 `SmartLayoutRecognitionSucceeded{semantic: SemanticAssembly, recognition: RecognitionSessionResult, correctionContext}`——**落在现有 sealed outcome 所在的同一 Dart library**，VM 补分支；
2. `SmartLayoutRealCandidateChain` 新增直接入口 `runFromSemanticAssembly({baseScene, snapshot(完整捕获快照), semantic, recognition(只读识别账本，取自 outcome 的 RecognitionSessionResult), measure, tokens, profile})`——**内部执行与旧入口相同的第 0 步 page-furniture 剥离与空页门控（wiring:88 起）**，再按 §6.4 做三方一致断言（断言输入即 `recognition` 携带的独立只读账本），复用 `run()` 第 1 步之后的全部管线，跳过 response→语义装配段；旧 `run(response)` 入口原样保留（服务 analyze/v3 实验/测试路径）；
3. VM 增加对新变体的分支并调新依赖 `candidateChainFromDocument`（V3 定位明确的宿主增量，属计划书 §6.2 共享宿主条款；同时落实 §9.8 的发布代次守卫）；
4. `transcribedTextByRegion` 语义由 recognition 结果携带进 `SemanticAssembly`（ink 正文在 extras，§8.1），不再单独传 map。

面板状态枚举（映射 pipeline 状态机 + 区域计数）：`idle / 正在准备 / 正在识别 / 正在重分组 / 正在复核 / 正在恢复结构 / 正在生成排版 / 部分完成(保留 n 区, 原因) / 失败(原因) / 已取消`。使用现有面板，不新增向导。V3 失败保留原内容并显示原因，不回退 V1。

## 11. 测试矩阵（按 R 分组，文件落 `SLT/recognition/` 与服务端包内）

| R | 测试文件 | 覆盖 |
| --- | --- | --- |
| R1 | `dto_json_test.dart` | §3.6 R-01..R-12 ×成功/失败样例；两端同源样例文件双向消费；含**原生元素 id 以 `r:` 开头**的命名空间冲突用例（§1）、`missingRegionIds` 部分批次样例（合法缺失/全漏答/数组内重复/覆盖违规） |
| R2 | `region_assets_test.dart`、`source_ledger_test.dart` | 缩放目标/上限/留白/浅色增强单次/逐区域失败隔离/资产释放；target/context 区分（**邻区文字不重复进入正文**）、小笔迹归属、单笔迹多资产索引；账本不变量、覆盖率、转换准入七条件 |
| R3 | `handler_stage_test.go`、`validate_test.go`、`prompts_test.go`、`limits_test.go`、`route_test.go`、`config_test.go` | stage 分发、注入 provider 协议全过、`invalidProviderResponse` 不重试、部分批次 sanitize（缺失显式传递/不可归属整批拒）、配置缺失 503、整数秒解析、新旧路由并存、in-flight 429、16MiB/3MiB/2MP 上限 |
| R4 | `pipeline_state_test.dart`、`pipeline_cancel_test.dart`、`budget_test.dart`、`repository_test.dart` | 状态机全迁移（含 regrouping 先于 verifying）、每个取消检查点、总时限主动取消在途、预算耗尽保留源、重试仅一次且排除解析失败、预算生命周期（纠错换操作/自动不刷新）、错误映射、`missingRegionIds` 客户端保留语义 |
| R5 | `structure_local_rules_test.dart`、`structure_merge_test.dart` | §7 规则逐条（含 "1.2" 小数排除、x 向缩进、标题四证据、嵌套挂靠）、复核触发与结构触发表分离、冲突保留、编号/换行/标点对比 |
| R6 | `semantic_adapter_test.dart`、`sizing_gate_test.dart`、`ledger_consistency_test.dart`、`correction_context_test.dart`、`semantic_correction_closure_test.dart`、`materializer_replacement_guard_test.dart`、`native_composition_closure_test.dart`、`apply_undo_reopen_test.dart`、`partial_success_test.dart`、`screenshot_list_layout_test.dart` | §8.1 映射表与嵌套子树连续；§8.2 六条回归与门禁；**§6.4 三方一致断言三反例：源集合同但状态相反、consume 归属 unitId 错配、完整快照未剥离背景**；§9 影响集/代次/迟到响应；**语义纠错闭环三用例：图注改绑确实生效、保留后原件不动、逆操作恢复且不绕过替换准入**；转换准入（非 FreeDraw 禁替换、锁定/绑定保护、覆盖完整）；组合单元闭包/单次变换/越界保留；应用/撤销/保存重开（扩展现有 `patch_invariant`/`candidate_patch_materializer` 测试口径）；部分成功语义；截图场景最终布局（一标题一列表不拆列） |
| R7 | `wiring_v3_entry_test.dart`、`vm_generation_guard_test.dart` | 新 outcome 变体走 `runFromSemanticAssembly`（含第 0 步过滤）、旧入口不受影响、旧 `run(response)` 仍可用、状态展示、失败不隐式回退；§9.8 两处发布点代次守卫（旧代空数组不清空新代） |
| R8 | 隔离矩阵扩充 | 按计划书 R8：`v2_client_isolation_matrix_test.dart` 补 URL 检查（现端点扫描见 `:110`）、取消 token 独立、配置互不覆盖 |
| R9 | `recognition_eval_test.dart`（工具自检） | §12 契约（含区域对齐五情形：sourceRefs 命中、IoU 回退、未对齐、一对多合并只计一次、同分歧义单列） |

全量命令按计划书 §9 执行，不做额外口径。真实 provider/实机验证归 R9，不以 mock 通过替代。

## 12. 评测工具契约（细化计划书 §8.3）

位置 `scripts/smart-layout-v3/recognition_eval.dart`，纯 Dart 标准库。

```
dart run scripts/smart-layout-v3/recognition_eval.dart --self-test
dart run scripts/smart-layout-v3/recognition_eval.dart \
  --truth <cases.jsonl> --v1 <predictions-v1.jsonl> --v3 <predictions-v3.jsonl> \
  --out <results/report.json>
```

**区域身份与对齐**：真值区域使用独立评测 ID（`<caseId>/r<n>`，与运行时 regionId 无关——不同管线分区/合并/拆分后 ID 不天然对应），并携带 `sourceRefs`（构成该区域的原始源 id，可得时）与 `bounds`。预测区域同样携带 `sourceRefs` 与 `bounds`。对齐规则：`sourceRefs` Jaccard ≥0.5 优先，回退 `bounds` IoU ≥0.5；多预测区域对齐同一真值区域时合并正文后计算；未对齐的预测区域计为多余（错误）、未对齐的真值区域计为漏识别；**覆盖率分母=真值区域数**，不按预测区域数计。

**一对多与歧义裁决**：允许真值行提供 `explicitAlignment`（预测区域 → 真值区域的显式对齐，R9 采集时人工标注）。无显式对齐时：一个合并预测跨多个真值区域（如预测 `{a,b}` 对真值 `{a}`、`{b}`，Jaccard 并列 0.5）——**正文只计一次**（对齐预测按 bounds 左上角即阅读序排序后合并），该组真值区域仅当**整组完整转换**（全部对齐预测 converted 且合并正文无转写错误）才各计转换成功，否则各计未完整转换（合并正文有误时同时计入错误转换率）；同一真值对应多个预测且仅部分 converted → 按未完整转换计；多匹配同分且无显式对齐 → 记为**歧义项单列报告**，不静默择一、不重复计数。不开发通用匹配引擎。R9 自检覆盖五种情形：sourceRefs 命中、IoU 回退、未对齐、一对多合并只计一次、同分歧义单列。

真值行：`{caseId, split: dev|holdout, sourceRef, contentFingerprint, referenceText, reviewStatus: unreviewed|aiDraft|humanVerified, uncertainRanges[{start,end}]（referenceText 的 code point 偏移，左闭右开）, regions[{evalRegionId, referenceText, legible:bool, sourceRefs[], bounds}], expect{title?, orderedLists[[itemText,...],...]}}`。

预测行：`{caseId, contentFingerprint, pipeline: v1|v3, model, recognizedText, converted, preserved, regions[{evalRegionId(对齐结果)/null, regionId(运行时), recognizedText, status, converted, sourceRefs[], bounds}], structure{orderedLists[[itemText,...],...]}}`。指纹不匹配按无效行报错退出 2。

指标定义：

- 语料级 CER=Σ编辑距离/Σ参考长度（code point 计数，保留标点为主指标，去标点另列）；缺预测按空预测计删除并单独报数；空参考单独计错、不除零丢弃。
- **区域级**（按对齐后真值区域计）：可辨识区域转换覆盖率 = 对齐且 converted∧legible 的真值区域数 / legible 真值区域数（首版目标 ≥90% 按此口径）；**错误转换率 = 已转换真值区域中规范化后存在转写错误（编辑距离 >0）的占比**；`CER>20%` 另名**严重错误转换率**单列（关键数字错漏如"20 字错 1 个数字、CER 5%"计入错误转换率，不被阈值掩盖）。
- **精确匹配**（落实计划 §8.3）：关键数字/编号逐字符精确匹配、列表项数、条目顺序——与 `expect.orderedLists` 逐项比对；区分"识别正确但转换/排版错误"（regions 对而 structure 错）与"识别错误"。
- **分别统计**：实际被转换内容与全部可辨识内容两套口径都出（未识别不得从总体样本消失）。
- 汇总：dev/holdout 分开 + 总体三份；**阈值判定只认 holdout**。逐页+汇总双输出。
- 退出码：0=humanVerified 数据齐全且既定阈值通过；1=有效评测未达阈值；2=输入非法/真值未齐。自检用例：全对、替换/插入/删除、空参考、Unicode（含增补平面）、缺预测、重复 caseId、区域对齐三情形（sourceRefs 命中/IoU 回退/未对齐）。

## 13. 提交切分（每 R 一个主提交）

R1 `feat: V3识别DTO与校验契约` → R2 `feat: 区域分区与高清资产` → R3 `feat: recognize/v3服务端接口` → R4 `feat: V3识别pipeline与独立取消` → R5 `feat: 复核与结构恢复` → R6 `feat: 识别结果接入V3文档(#14字号重构)` → R7 `feat: V3入口切换至独立识别` → R8 `test: V1/V3隔离回归收口` → R9 `feat: 识别评测工具与真实对照`。修复追加不另起编号。

## 14. 评审检查清单（给评审代理）

1. §3 协议字段/错误表与计划书 §4.1 的约束逐条对得上？400/502 职责划分（请求侧/模型输出侧）与部分批次语义是否闭环？
2. §2 文件清单是否越出计划书 §4.2 "仅按职责必要拆文件"？
3. §4 服务端是否触碰冻结区（import 旧算法/改旧路由/复用旧 handler 作后备）？
4. §5 资产规格与计划书 §3.3 八条一一对应？read/verify 图只含 target 笔迹、上下文走文本字段/概览图是否成立？
5. §6.2 预算表数值与计划书 §5 全量一致？字节口径、预算生命周期、重试排除项是否闭环？
6. §6.4 是否做到"单向投影 + 逐源状态/归属三方断言 + 单向降级 + 物化后置检查 + 快照范围一致 + 禁止重复终结"六点齐全？
7. §7 是否引入计划书外的正文改写能力（不应有任何）？复核触发与结构触发两表是否分离？
8. §8.2 是否彻底排除外框反推字号与状态机回跳？token 实值（28/20/12/1.25）与测量阶段（留在块组装）是否可执行？
9. §9 语义纠错闭环是否补齐 set-relations 空操作与 preserve 不同步两缺口？分区/语义两类纠错的路径与预算语义是否分离？VM 两个发布点代次守卫是否落实？
10. §10 类型连接是否做到"不造假 response + 新入口保留第 0 步过滤"？
11. §11 测试矩阵覆盖计划书 §8.2 必过条件每一行？§6.4 三反例、语义纠错三用例、嵌套/单项子列表、部分批次、区域对齐是否都有落点？
12. §12 与计划书 §8.3 的工具/退出码/口径一致？区域对齐与错误转换率定义是否可由数据 schema 直接计算？
