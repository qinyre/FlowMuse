# 智能排版 v3 实施任务卡与工程量分解

> 日期：2026-08-31  
> 分支：`feature/smart-layout-v3-refactor`  
> 上位计划：`2026-08-30-smart-layout-v3-architecture-refactor.md`  
> 状态：64/69 项与 Gate 0～5 已完成；本次只把剩余 Phase 7 收缩为比赛交付，不改变目标效果与核心质量门禁

## 1. 使用方式

上位计划中的 8 个 Phase、52 个 `V3-xxx` 编号继续作为稳定工作包；本文件用 `V3-xxxA/B/...` 表示可独立领取、实现和验证的执行任务。Phase 0 已完成的 13 项原样保留，Phase 1～7 从 140 项合并为 56 项，共 69 项；合并只减少交接、重复证据和复审次数，不删目标能力、失败语义或 Gate。

执行分为两条连续的工程线：Phase 0～6 以及 V3-700B～V3-701A 属于 `ai_synthetic_development`，完成核心实现、确定性评测和默认关闭的 v3 入口；V3-700A～V3-705A 属于 `competition_delivery`，只负责本地/演示环境 smoke、合成稳定性、v2 隔离证明和比赛交付审计。剩余任务不依赖真人、真实生产流量、六端设备认证或外部输入；已完成的 AI 盲审证据保持原样，不追加形式化复审。

叶子任务必须满足：

1. 只有一个主要工程目标，不能同时承担互不依赖的协议、算法、UI 和部署改造。
2. 有已满足的直接依赖、确定的输入输出、建议修改边界和可运行的完成证据。
3. 对失败、取消、空输入、旧数据和跨端行为有明确结论；不得把异常路径留给后续 Gate 猜测。
4. 能形成一个内聚的实现与验证单元。只有出现独立回滚边界、不同权限边界或无法由同一组测试判定的第二目标时才拆分。
5. Gate 任务只汇总已经生成的证据，不在 Gate 中临时补生产逻辑。

## 2. 工程量与任务准入

### 2.1 相对工程量

| 级别 | 工程边界 | 允许范围 | 强制拆分条件 |
| --- | --- | --- | --- |
| S | 单一契约、报告、局部适配或 focused test | 通常不超过 2 个主要生产模块；无跨层状态迁移 | 出现新公共模型、跨端差异或第二条用户流程 |
| M | 一个层内的完整能力切片 | 通常 2～4 个主要生产模块，连同对应测试形成闭环 | 同时改客户端与服务端，或需要两套独立验收 |
| L | 一个高风险算法、事务或跨层纵切 | 通常 5～8 个主要生产模块；必须有中间自检和完整回归 | 超过一个纵切、同时占用两个热点文件、或完成证据无法一次判断 |

文件数量只用于暴露范围失控，不把 fixture、golden、生成报告和纯文档计入主要生产模块。不存在 XL：估算超过 L 的任务必须先拆分。

### 2.2 Ready 条件

叶子任务进入 `in_progress` 前必须同时具备：

- 所有直接依赖已完成且证据可读取；
- 输入 fixture、目标接口和失败语义已经冻结；
- 列出实际修改文件及唯一热点文件占用；
- 写出 focused test 命令和预期观察值；
- 明确不修改的相邻能力，避免顺手重构。

### 2.3 Done 条件

每张任务卡只有在以下条件全部满足时才是 `completed`；是否调用独立子代理由风险分级决定，自动化任务不再为流程完整而强制复审：

- 产物已落库，没有关键路径 TODO、临时分支或静默 fallback；
- focused test 先通过，再通过该阶段规定的静态检查和回归；
- 失败/取消/旧格式/空输入至少各有适用的自动化证据；
- 对共享代码完成六端影响检查，没有业务层 `Platform.is*`；
- 相对基线的范围外生产文件 diff 为零；条件式最小修改已记录理由、符号和回归证据；
- 改变协议、架构、数据格式或用户行为时同步相应文档；
- 任务结果能由非作者仅凭命令和报告复核。

## 3. 实现边界与串行热点

- v3 的模型、几何/变换、Patch/Reducer、renderer adapter、协议、算法、状态和 UI 默认全部进入 `FlowMuse-App/lib/features/whiteboard/smart_layout/`；测试镜像源码结构。名称看起来通用不构成下沉理由。
- `editor_core` 只允许复用或增加最小 snapshot/draft/validated-commit gateway，并沿用已有 Scene、`ToolResult/CompoundResult`、History 和 renderer；不得借本项目重建通用几何、事务或渲染框架。
- 服务端 v3 使用独立 analyzer、类型和端点注册；旧 `SmartLayouter`、`vision_layout.go` 仅作为基线和退役对象，不扩展成 v3。
- `markdraw_controller.dart`、`whiteboard_page.dart` 只允许修改智能排版 gateway/入口的最小区域；v3 JSON Schema、feature-local design tokens、评分公式和 golden 审批记录仍是串行热点。
- `NativeHttpClient`、Scene/History、实际 renderer、Excalidraw codec、LWW/reconcile、文档持久化和既有导出只做兼容验证；若稳定接口足够，不得修改实现。
- AI 助手模型/prompt/action/UI、思维导图、SelectTool、数据库 schema、协作协议、全局设计系统、新导出格式和无关平台问题明确不属于本计划。现有调用者只通过稳定智能排版公开入口自然获得 v3，不安排迁移。
- 任何任务若要触及相邻模块，领取前必须证明“现有接口无法完成 v3”，列出精确文件和最小适配；没有第二个真实消费者时，不创建公共抽象或搬迁 helper。

| 文件边界 | 路径/区域 | 执行规则 |
| --- | --- | --- |
| 默认可修改 | `FlowMuse-App/lib/features/whiteboard/smart_layout/**`、服务端新增 v3 analyzer/schema/route、对应 test/fixture/docs | 承载核心重构；新增代码仍受任务卡和 Gate 约束 |
| 条件式最小修改 | `whiteboard_page.dart` 的智能排版入口、`markdraw_controller.dart` 的智能排版 gateway、`smart_layout_document.dart`/serializer/exporter 的 v3 映射、v3 确实需要的平台配置 | 任务卡必须给出现有接口不足的证据、精确行/符号、范围外 diff 和回归；不能整文件重排或顺手清理 |
| 仅测试不主动改生产实现 | `whiteboard/ai_assistant/**`、`select_tool.dart`、`mindmap_tool.dart`、`editor/mindmap/**`、`whiteboard/collaboration/**`、数据库 migrations、全局 tokens、既有 exporter 架构 | 编译或 fixture 失败时先判断是否为 v3 造成；不是则单独记录，不并入本重构 |

每个 Gate 都必须运行相对基线的路径审计：默认可修改区逐项映射任务卡，条件式修改逐项核验技术理由，“仅测试”区域的生产 diff 必须为零。路径审计失败与功能测试失败同等阻断。

| 任务范围 | 任务编号 | 所有权解释 |
| --- | --- | --- |
| 核心重构 | V3-100A、V3-102A～V3-106A、V3-200A～V3-205A、V3-300A～V3-303A、V3-400A～V3-405A、V3-500A～B、V3-501A～V3-505C、V3-700B～V3-704A | 只拥有智能排版 feature、v3 服务和切流实现；其中 editor 接触仍受最小 gateway 限制 |
| 交付验证 | Phase 0、V3-206A、V3-305A、V3-406A、V3-506A、V3-602A～V3-606A、V3-705A | 只产数据、测试、报告、构建、实验和审计；不能取得被测模块的额外重构权 |
| 兼容验证 | V3-101A、V3-304A、V3-502A、V3-600A～V3-601A、V3-703A | 生产实现默认零改动；确需适配时必须使用条件式最小修改流程 |

编号归类只限制所有权，不替代每张任务卡的依赖和完成证据。

## 4. Phase 0：冻结质量协议（13 项）

本阶段不得修改生产排版逻辑。输出是后续所有算法决策的固定裁判。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-000A 失败分类账 | M | 无 | 定义 critical/major/minor、允许关系、禁止模式、反投机案例及最小正反例 | 分类 schema 校验通过；产品/算法/编辑器对同一组样例结论一致 |
| V3-000B AI 代理 rubric 与锚点样例 | M | V3-000A | 1～5 分 rubric、逐维评分表、每档锚点、分歧处理规则；两个隔离 GLM-5.3 Max 盲审，第三代理只仲裁分歧 | 报告含独立 run id、一致性和仲裁结果，24 个锚点及所有失败类可映射；明确 `ai_surrogate` 且不宣称真人验证 |
| V3-001A FixtureManifest 契约 | M | V3-000A | manifest schema、样本来源与生成种子、页面特征、期望产物和版本字段 | positive/negative manifest 均有解析测试；来源或生成参数不完整的样本无法进入 runner |
| V3-001B 确定性与 benchmark 环境 | L | V3-001A | 固定字体、DPR、时钟、随机源、Scene/PNG 规范化；冻结主机/OS、warm-up、缓存、并发、P50/P95、峰值内存和超时口径 | 同 fixture 在隔离进程中三次运行一致；benchmark spec 有 hash；V3-002A 前 record/replay 只接受合成数据 |
| V3-001C Runner、受控 replay、报告与 hash | M | V3-001B | 单页/批量 runner、受控网络 replay、分层报告、机器退出码、产物 hash 和失败保留 | 三次运行 hash 一致；故意失败退出非零；来源或格式不合规的 fixture 被机器拒绝 |
| V3-002A 合成样本清单与生成边界 | S | V3-000B、V3-001A | 只接收确定性合成样本；记录生成器版本、种子、场景族和派生链 | 来源、生成器版本或种子不可复现的样本无法进入 manifest |
| V3-002B 分层抽样与集合隔离 | M | V3-002A | 按合成场景族、内容类型、复杂度和平台特征生成 development/validation/frozen | 同一生成种子/原稿/派生图不跨集合；分层覆盖报告达预注册要求 |
| V3-002C 双代理盲标、仲裁与冻结 | L | V3-002B | 标注手册、两个隔离 GLM-5.3 Max 独立标注、第三代理仲裁、集合版本和只读冻结清单 | 独立 run id 与盲标输入可审计；一致性达标；frozen hash 固定且调参工具拒绝读取 frozen 标签；标记 AI 代理证据 |
| V3-003A no-op 与 v2 自动基线 | M | V3-001C、V3-002C | 用同一 runner 生成 no-op/v2 的 Scene、PNG、指标、失败分类和资源数据 | 两条基线可重复，缺候选/崩溃/超时不会被记作成功 |
| V3-003B AI 专家代理整理基线与总报告 | L | V3-003A | 两个隔离代理按固定编辑协议生成可接受目标 Scene/PNG、操作步骤和修改次数，并与前两基线并表 | 盲化编号、完整工具日志和三基线分层报告齐全且可重放；仅称 AI surrogate baseline，不声称人工效率 |
| V3-004A EvaluationSpec 与阈值预注册 | M | V3-000B、V3-003B | 机器可读 spec 固定聚类单位、估计量/效应量、CI/检验、缺失处理、多重比较、功效、分母、critical=0、非劣/优效阈值、benchmark 预算和停止规则 | spec 有版本/hash；独立 AI 盲审与仲裁记录齐全；runner 拒绝未注册指标、未固定分母或 benchmark 环境；比赛演示 smoke 由 V3-700A 核验 |
| V3-004B 统计、rubric 与 golden 变更控制 | M | V3-004A | 只引用 V3-000B rubric 版本；实现 EvaluationSpec、score-AI-surrogate 相关性、golden 审批和变更审计 | 合成结果演练通过/拒绝/数据不足/缺失四种结论；任何 spec/rubric/golden 变化都会改 hash；不得外推为 score-human 相关性 |
| V3-004C Gate 0 开发证据包 | S | V3-004B | 汇总 AI rubric、EvaluationSpec、benchmark spec、合成数据版本、三基线和复现命令并冻结开发 Gate 0 | 全部引用/hash 可解析；从空报告目录可一条命令重建；报告明确 `HUMAN_VALIDATION_NOT_PERFORMED`，只表示开发质量门禁通过 |

并行边界：`V3-000B` 与 `V3-001A` 可在 `V3-000A` 后并行；数据收集与 runner 实现可并行，但 `V3-002C` 冻结前不得测正式基线。

## 5. Phase 1：Snapshot、分割与会话隔离（8 项）

本阶段只建立可审计输入与生命周期，不实现候选布局。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-100A feature 骨架与最小 gateways | M | V3-004C | 合并原 V3-100A～C：建立 feature 五层边界，薄封装现有 HTTP/editor API、取消、snapshot/revision/draft/validated commit；不引入第二套 client、注册表或通用 editor 抽象 | 架构/import 与 fake gateway 测试全绿；旧公开入口签名和旧 repository 行为不变 |
| V3-101A SceneRevision、fingerprint 与变化接线 | M | V3-100A | 合并原 V3-101A～C：覆盖本地 edit/undo/redo/load/reset/clear 与远端 reconcile，形成单调 revision/epoch 和 canonical fingerprint | 内容变化准确递增，视口/选择不递增；跨端 hash 一致；不修改 History、LWW 或协作协议 |
| V3-102A 完整 Snapshot 与唯一 SourceCoverageLedger | M | V3-101A | 合并原 V3-102A～C：不可变页面快照、mobility/protected 分类、关系、exactText/style、图片/file refs 和唯一 ledger | 每个 sourceId 最终只能 consumed 或 preserved；嵌套组、旋转、绑定、裁剪图片、缺文件和 unknown fixture 无丢失，不提供主观忽略分支 |
| V3-103A 笔画特征、空间图与 reading geometry | L | V3-102A | 合并原 V3-103A～C：确定性局部特征、空间索引/邻接/组件、deskew、单/多栏和竖排 geometry | 小样本与全配对 oracle 等价；3000 笔画不跑 O(N²)；缩放/平移、倾斜和多栏不变量可复现 |
| V3-103B 区域分类、防误并拆与参数冻结 | L | V3-103A、V3-001C | 合并原 V3-103D～F：line/formula/table/emphasis/unknown 分类、merge/split 防护、置信/preserved 语义及 development→validation 参数冻结 | 不改变 stroke membership；高风险反例不丢笔迹；frozen 不参与调参；最差分组达到 Gate 1 预线 |
| V3-104A RegionCorrectionPatch 与最小受影响集 | M | V3-103B | 合并原 V3-104A～B：可逆 merge/split patch、revision 前置、合法性和 region/render asset/crop/source keys 失效计算 | apply→inverse 恢复同一图；过期/交叉 patch 被拒；局部结果与全量等价且无关 ID/hash 不变 |
| V3-105A clean/annotated/crop 资产与资源生命周期 | M | V3-102A | 合并原 V3-105A～B：构建三类资产、page↔pixel 变换与 mark 账本，并统一 codec、并发、取消和异常释放 | source 可追踪、标记不入 OCR crop；越界明确；所有失败注入后资源归零且无迟到写入 |
| V3-106A Session 状态、continuation 守卫与重入 | M | V3-100A、V3-101A | 合并原 V3-106A～C：sealed state、合法迁移、operation/page/revision/disposed/cancel 四检、最小 editor API 与重入回归 | 非法迁移在副作用前失败；取消/离页/远端变化/迟到回调不污染新 session；不暴露绕过门禁的 commit |

并行边界：`V3-101A` 后 snapshot 与 session 可并行；`V3-102A` 后分割与资产可并行；`V3-103A→103B→104A` 串行。合并任务内部按原子检查点提交到同一任务 commit，不再拆成多次领取和复审。

## 6. Phase 2：强类型分析与语义纠错（8 项）

本阶段让识别结果成为可校验、可纠错、可持久化的语义文档；不得生成最终坐标。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-200A canonical 协议、双端模型与 conformance | L | V3-004C | 合并原 V3-200A～C：冻结 v3 schema/端点/错误映射，完成 Dart/Go 强类型 DTO、negative fixtures、完整 handler 与双端 round-trip runner | 字段可追溯；typed text 不来自模型；正例无损，缺失/越界/环/超限/未知枚举双端同类拒绝且无 panic |
| V3-201A V3Analyzer、strict decode 与 sanitize | L | V3-200A | 合并原 V3-201A～B：独立 analyzer/配置/provider 调用，严格验证引用、基数、order、关系环、长度、typed text 回填和 preserved | v2/v3 独立启停；超时/限流/恶意或残缺响应只能产生完整已校验文档或稳定错误，绝不部分信任 |
| V3-201B v3 路由、传输健壮性与 live-route | L | V3-201A | 注册真实 server/mux 路由，接通现有 HTTP 基础设施，完成请求大小限制、超时、取消、稳定错误映射和 synthetic live-route smoke | 完整路径、限额、取消、超时和错误映射通过；旧端点不串线；不新增供应方政策、同意或审批系统 |
| V3-202A overview/crop 分析与冲突合并 | L | V3-201A、V3-105A | 合并原 V3-202A～B：overview 只产 role/order/relation/evidence，必要时走高清 crop OCR/formula，并保留冲突 | typed exactText 不被模型改写；低置信触发准确；overview/crop 冲突进入文档而非静默择一 |
| V3-203A Repository、取消重试与真实联调 | L | V3-200A、V3-100A、V3-106A、V3-201B | 合并原 V3-203A～D：复用 NativeHttpClient，统一取消、有限重试和 operation/page/revision/disposed 四检，并与真实 synthetic server 联调 | capability off 时请求数为0；timeout/offline/429/5xx/bad schema/late response 不污染状态；双方 hash 一致 |
| V3-204A SemanticDocument、ledger 与持久化映射 | M | V3-202A、V3-102A | 合并原 V3-204A～C：不可变语义文档、唯一 ledger 投影、unknown/conflict、版本映射和旧版本读取 | source 状态/hash 守恒；unknown 默认 preserved；current round-trip 深度等价，旧 fixture 可读且新字段不误删 |
| V3-205A 可逆语义纠错与局部重分析 | L | V3-204A、V3-104A、V3-203A | 合并原 V3-205A～C：role/order/relation/preserve/protect patch、region 影响图、稳定 source keys 和局部重分析 | apply/inverse 完整；过期 revision 零副作用；局部与全量等价；连续修正只提交最后一次 operation |
| V3-206A Gate 1 指标、闭环与证据包 | M | V3-103B、V3-201B、V3-202A、V3-203A、V3-204A、V3-205A | 合并原 V3-206A～C：分析/校准/最差分组、纠错收益、round-trip、错误路径、live-route 和复现证据 | development/validation 分离；低样本明确；Gate 1 全部机器判定；缺 schema/hash/live-route 时 planner 保持 blocked |

并行边界：`V3-200A→201A→201B` 冻结服务主链；`V3-202A` 与客户端 `V3-203A` 在各自依赖满足后并行，随后 `204A→205A→206A` 收口。v3 schema 仍是唯一协议真源。

## 7. Phase 3：测量、几何和变换契约（6 项）

本阶段只交付智能排版 feature 内的真实测量、几何和变换能力，不重构通用 editor、SelectTool 或其他布局功能。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-300A design tokens、真实测量与边界语种冻结 | L | V3-004C | 合并原 V3-300A～C：从现有 renderer 提取 tokens，复用 TextPainter/font resolver 和有界缓存，覆盖 CJK/长词/emoji/RTL/公式/widow-orphan/缺字体 | 无字符数估算或 ellipsis；测量与真实 renderer 一致；缓存 key/失效/上限可测；validation 后 token 版本冻结 |
| V3-301A feature-local 几何、碰撞与零漏检 oracle | L | V3-102A | 合并原 V3-301A～C：复用 bounds/helper，完成 AABB/OBB、相交/contain/间距/页界/保护对象和空间查询 | renderer oracle 漏检为0；旋转/嵌套/零尺寸无漏报；3000 笔画/100块达预算；不导出通用 kernel |
| V3-302A TransformContract、支持矩阵与 conformance | L | V3-301A | 合并原 V3-302A～C：元素 move/resize/rotate/拒绝矩阵、父子坐标与传播顺序、old/new Scene/嵌套组/旋转 frame/绑定链 fixtures | 每格有 fixture 或稳定拒绝码；合法场景深度一致；未知类型原子拒绝，不存在“尽量变换” |
| V3-304A helper 迁移前快照与最小适配边界 | M | V3-004C | 合并原 V3-304A～B：先冻结实际触及 helper 及调用者快照，只在现有接口确实不足时增加 feature-private 薄 adapter | allowlist 外零改动；快照先于适配；相邻调用者回归全绿，无公共 wrapper 链或所有权迁移 |
| V3-303A 原子 Scene 变换、依赖重算与 gateway 接入 | L | V3-302A、V3-304A | 合并原 V3-303A～C：不可变主元素变换、统一 group/frame/bound text/arrow/points/index/version 重算、全有或全无预检及 draft gateway 接入 | identity/inverse/组合成立；关系双向一致；失败时 Scene/hash/history 不变；Excalidraw/LWW 回归全绿且不导出通用 API |
| V3-305A Gate 2 变换矩阵、性能与证据包 | M | V3-300A、V3-301A、V3-302A、V3-303A、V3-304A | 合并原 V3-305A～B：批量执行元素/关系矩阵，汇总零漏检、性能、兼容和复现命令 | 每格 pass/reject/unsupported 且零静默跳过；Gate 2 机器判定，失败时 Patch 阶段保持 blocked |

并行边界：`V3-300A`、`301A` 和 `304A` 可并行；`302A→303A` 串行并等待迁移快照；`305A` 统一收口。不得承担共享几何搬迁或相邻功能清理。

## 8. Phase 4：候选生成与评分契约（9 项）

本阶段决定排版效果上限。候选生成只使用冻结语义、测量和 tokens；VLM 不返回坐标，最终推荐不得在真实 Scene 前产生。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-400A LayoutBlock、文本/图像/保留原语 | L | V3-206A、V3-300A | 合并原 V3-400A～C：从语义节点组装 block，透传唯一 ledger/sourceRefs，覆盖标题、段落、列表、section、figure、formula、preserve/protected 和关系原子性 | ledger/sourceRefs 守恒；typed/transcribed/preserved 明确；真实 measure callback 接入；图片比例、caption/keep-together 和 unknown 不丢失 |
| V3-401A Planner 契约、skeleton、token 域与结构配额 | L | V3-400A | 合并原 V3-401A～C：确定性候选 ID/顺序，枚举 single/two-column/main-side/conservative-layout，参数只来自冻结 tokens，结构配额下最多12项 | 每种结构有适用/拒绝 fixture；顺序/hash 稳定；上限不饿死结构；conservative-layout 不是零修改 fallback |
| V3-401B 硬下界剪枝与全枚举 oracle | L | V3-401A | 合并原 V3-401D～E：剪枝只读单调硬可行下界，使用小 fixture 全枚举差分证明可行集等价 | 不读取软分/排名/profile；每条剪枝有证明与反例；误剪任何硬可行结构直接失败 |
| V3-402A reading flow、真实换行与关系原子性 | L | V3-400A、V3-401A、V3-300A、V3-301A | 合并原 V3-402A～C：按语义顺序放置，调用真实测量完成 wrap/高度/最小字号，保持 keep/list/section/formula 原子性 | CJK/长词/emoji/RTL 无裁字、估算或省略；不可满足时返回原因，不静默拆关系或缩小越线 |
| V3-402B 栏平衡、contain、障碍、figure/preserved 回归 | L | V3-402A | 合并原 V3-402D～E：栏高平衡、页界 contain、protected 绕置、密度控制、图片等比/caption 栈和 preserved 路径 | 综合 fixture 零硬碰撞；crop/ratio/绑定不变；转写与保留路径通过 golden geometry，结果确定 |
| V3-403A preflight、NoFeasibleLayout 与 preserveFallback | M | V3-402B | 合并原 V3-403A～B：生成期只做硬 preflight，稳定区分无解、内部错误、可重试失败和零修改 preserveFallback | preflight 不调用 scorer；reject 可映射建议；fallback 不进 scorer、结构配额、合格率或 Top3 |
| V3-404A 指标边界、三 profiles 与反投机解释 | L | V3-403A、V3-004A、V3-000B | 合并原 V3-404A～C：冻结七类软指标、硬软隔离、三个目标 profile、no-op/极缩/隐藏/留白/重复/成本造假否决和可解释分解 | 硬失败不能被软分抵消；指标单调有界；profile 共用生成器/硬约束；adversarial fixtures 全拒绝且 score 可还原 |
| V3-405A placement 去重与真实 Scene metrics 契约 | M | V3-401B、V3-402B、V3-404A、V3-301A | 合并原 V3-405A～B：在完整 placement 上建结构签名，并定义 Renderer 后 coverage/relation/order/visual-bounds metrics | 仅删契约等价结构；叙事结构不误合并；fallback 不混淆；合成 placement 不能冒充最终 metrics，缺字段 fail closed |
| V3-406A Gate 3 Planner oracle、质量性能与证据包 | M | V3-402B、V3-403A、V3-404A、V3-405A | 合并原 V3-406A～B：汇总漏解、误判、结构多样性、确定性、最差分组、性能、契约版本和复现命令 | validation 可重复；各 skeleton 单独报告；Gate 3 机器判定，禁止靠单张 fixture 调权重绕过 |

并行边界：BlockAssembler 后 `401` 与 flow 前置可分线；`401A→401B`、`402A→402B→403A` 串行，`404A/405A` 在依赖满足后汇合到 `406A`。生成期只允许硬可行性剪枝；Scorer 不读取未经过真实 Scene 的最终值。

## 9. Phase 5：ScenePatch、真实预览和用户工作流（11 项）

本阶段把候选变成真实 Scene 事务。固定顺序为 PatchBuilder → Reducer → Renderer → Hard Gate → Score → Top 3，不允许捷径。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-500A ScenePatch 模型、归一化与完整 write set | L | V3-305A、V3-403A | 合并原 V3-500A～C：feature-private 不可变 patch、baseRevision、add/update/remove 顺序、字段/关系/version delta、file/document/selection、精确读写集和唯一 ledger | 不持有可变 Scene；冲突/悬空操作拒绝；关系/version 无遗漏；写集覆盖全部副作用且不建立通用事务框架 |
| V3-500B Patch 校验、fixture codec 与 ScenePatchBuilder | L | V3-500A、V3-402B、V3-303A | 合并原 V3-500D～E：validator/deep equality/debug codec，并将完整 candidate 一次物化为元素/关系/file/document/selection patch | codec 仅测试诊断；非法 patch 零部分结果；构建后不再推导坐标；不支持类型原子失败且 ledger 守恒 |
| V3-501A SceneReducer、preview 与既有 History bridge | L | V3-500B | 合并原 V3-501A～C：纯 reducer 固定操作序，折叠关系/file/document/selection，preview 与最终提交共用 reducer 并桥接现有 History | 输入不可变、失败原子；Draft 可重放；undo/redo 精确且无重复 push；无旁路 commit 或新 History 框架 |
| V3-503A 真实 DraftSceneRenderer、边界、golden 与资源 | L | V3-501A、V3-300A | 合并原 V3-503A～C：复用真实 painter/font/viewport，采集文本/图片/公式边界，维护平台 golden 和 codec/cache 释放 | 与编辑器渲染几何一致；缺资源明确失败/降级；不使用估算缩略图；连续渲染/取消后资源归零 |
| V3-504A 真实 metrics 与 HardConstraintValidator | L | V3-405A、V3-501A、V3-503A | 合并原 V3-504A～B：从 reducer+renderer 提取可追溯 metrics，并验证 coverage/relation/order/裁字/比例/group/frame/binding/页界和 ledger 守恒 | 不读取 placement 自报；每条硬约束有 adversarial fixture；丢失、重复、非 consumed/preserved 状态或 hash 断链全部 fail closed |
| V3-504B Scorer、Top3、ValidatedCandidate 与纠错重跑 | L | V3-504A、V3-404A、V3-205A、V3-401B | 合并原 V3-504C～E：反投机/profile 排序、多样性 Top3、验证封装、无解解释，并按 affected keys 重跑 planner→patch→render→gate→score | 只有本轮完整门禁可生成 ValidatedCandidate；不足3不补；局部重跑与全量等价；旧候选失效；NaN/缺指标拒绝 |
| V3-502A compare-and-commit、冲突重派与协作兼容 | L | V3-101A、V3-501A、V3-500A、V3-504B | 合并原 V3-502A～C：唯一 commit 入口复核 revision/fingerprint/render/metrics hash，处理写集相交和最多一次重派，并走现有协作通道 | 原始 patch/过期候选不可提交；冲突零 Scene/History/broadcast 副作用；preview=commit；LWW/消息/reconcile 协议 diff 为零 |
| V3-505A Session ViewModel 与用户操作编排 | L | V3-106A、V3-205A、V3-203A | Riverpod 状态机编排范围选择、保护、分析、生成、review、commit、取消和重试；不引入额外策略门禁或确认流程 | UI 不持有业务 bool/completer；取消立即终止当前 operation 并清理 draft；重复点击、重试和状态恢复确定 |
| V3-505B 纠错核对与真实候选比较 | L | V3-505A、V3-504B | 合并原 V3-505B/F：region/role/order/relation 修正、全文 ledger 核对、真实 renderer 缩略图、评分解释、结构差异和候选选择 | 修正触发真实最小重跑并使旧候选失效；每张卡绑定当前 ValidatedCandidate；切换候选不写权威 Scene |
| V3-505C 真实入口、错误取消与可访问性闭环 | L | V3-505B、V3-502A、V3-403A | 合并原 V3-505G/C/D：保持公开签名接入真实 Session/commit，完成无解/重试/取消/离页、Semantics、键盘和焦点恢复 | 真实 server→候选→commit 自动化通过；无 fake provider；零 modal 死锁/残留；无鼠标流程完整；范围外源码 diff 为零 |
| V3-506A Gate 4 事务体验矩阵与证据包 | L | V3-502A、V3-504B、V3-505C | 合并原 V3-506A～B：从真实入口覆盖 preview=commit、undo/redo、cancel/late、draft、local/remote conflict、纠错重跑及渲染/排名/a11y 证据 | Scene/History/revision/broadcast/document/ledger 六态一致；Gate 4 机器判定，任何 critical/deep mismatch 阻断 Phase 6 |

并行边界：`500A→500B→501A` 严格串行；Renderer 在 `501A` 后推进，commit 等待 `504B`；UI 可早期使用 fake Session，但 `505B/505C/506A` 的完成证据必须来自真实 analyzer、候选和编辑器入口。热点 editor 文件只由 `V3-505C` 修改智能排版区域。

## 10. Phase 6：完整验证（7 项）

本阶段只验证 v3 对既有格式、协作、导出和平台的兼容，不取得这些系统的重构所有权。若发现 v3 缺陷，退回对应叶子任务；若发现无关既有缺陷，单独记录并保持 Gate blocked，不塞进本计划修复。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-600A codec、协作与 hash 兼容矩阵 | L | V3-506A、V3-502A | 合并原 V3-600A～C：覆盖 Excalidraw reader/writer、old/new Scene、LWW/index/versionNonce、关系/file/document 并发和 collaborationHash | round-trip 无关键字段丢失；双端收敛；冲突不覆盖无关编辑；不重构协议、LWW 或 codec 架构 |
| V3-601A 文档重开与 Markdown/LaTeX 出口兼容 | L | V3-204A、V3-501A、V3-600A | 合并原 V3-601A～B：SmartLayoutDocument 版本映射、旧读新写、重开/undo/redo/reconcile，并复用现有 exporter 验证结构 | 多版本 fixture 深度一致；数据库/序列化框架不变；导出字符、顺序和关系正确，不新增格式或 importer |
| V3-602A 可复制 CI、失败报告与证据归档 | M | V3-001C、V3-506A | 合并原 V3-602A～B：固定 runner/字体/fixture server/replay/cache/workdir，归档机器报告、退出码、版本和失败产物 | 新 clone 可运行且无本机绝对路径；故意破坏能阻断并保留必要诊断 |
| V3-603A Go/Schema/Flutter 聚合门禁 | M | V3-200A、V3-602A | 合并原 V3-603A～B：Go test/vet、schema conformance/replay、Dart format、Flutter analyze/focused/all tests 与 golden job | 双端独立全绿；旧端点 fixture 保持；命令可从仓库复制；不新增 analyzer error |
| V3-604A 大页、渲染、取消与资源压力 | L | V3-406A、V3-506A、V3-602A、V3-105A、V3-503A | 合并原 V3-604A～B：3000笔画/100block/长页/多候选阶段预算，以及连续截图/crop/render、并发取消、离页/dispose、失败注入和内存趋势 | 性能可归因各阶段并达预算；资源回到容差；无 handle/codec/timer/request 泄漏和迟到写入 |
| V3-605A 可用平台构建、OHOS 边界与跨端 smoke | L | V3-603A | 合并原 V3-605A～C：冻结六端配方/hash，当前可用目标实构建，OHOS 可构建则产 HAP，否则记录 deferred，并跑入口→commit→undo→reopen smoke | 可用端全绿；不可用端只记录 runner/设备/恢复命令，不伪造成功；生成文件不入提交；比赛交付不再等待不可用平台 |
| V3-606A frozen AI 双盲、效果统计与 Gate 5 | L | V3-004C、V3-600A、V3-601A、V3-602A、V3-603A、V3-604A、V3-605A | 合并原 V3-606A～B：两个隔离 persona 盲评、分歧才启用仲裁，随后按预注册 spec 计算优效/非劣、操作成本代理和 score-AI 相关性 | frozen 不回流；critical 逐案审计；失败/拒绝不排除；机器判定 Gate 5；结论明确为比赛项目的 AI 合成评测 |

并行边界：兼容、CI 和性能可在 Gate 4 后并行；平台构建等待聚合门禁；frozen 只执行一次并等待所有自动化、性能和平台/deferred 证据完成。

## 11. Phase 7：比赛演示与交付（7 项）

本阶段在开发 Gate 5 通过后启动。V3-700B→V3-701A 已完成默认关闭的入口、回滚和可观测性代码；剩余五项只把现有能力整理成可重复演示、可自动验收的比赛交付包。比赛版本保留 v2 客户端和服务端实现作为参考与回退边界，只证明公开入口和 v3 路由彼此隔离，不做生产流量迁移或破坏性删除。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-700B fail-closed capability 与可观测性预部署 | L | V3-606A | 合并原 V3-700B～D：capability 默认/过期/故障 off、kill switch、版本化指标、dashboard/alert 和本地 synthetic sink | 无可用服务时请求为0；断网/配置故障不回退 v2；合成指标可触发告警与关闭 |
| V3-701A 公开入口默认关闭切换、回滚与关闭行为 | L | V3-700B | 合并原 V3-701A～B：保持签名把内部切到新 Session，默认关闭且服务不可用时不能开启，固化独立切流提交、Git 回滚和会话关闭/重开行为 | 入口代码不可达 v2；调用者源码不迁移；默认关闭零请求/零 Draft；回滚恢复切流前版本且关闭无 Draft/History/广播残留 |
| V3-700A 比赛演示环境启动与端到端 smoke | M | V3-701A | 启动本地或演示环境的 v3 analyzer，复用现有 capability/metrics 本地配置，运行入口→候选→commit→undo→reopen 合成 smoke | 单命令 smoke 全绿；默认关闭、开启、kill switch 和服务故障行为可重复演示；不要求真实生产部署或六端认证 |
| V3-702A 合成稳定性与故障注入结论 | M | V3-700A、V3-701A、V3-700B | 用现有 runner 固定种子重放样本，并注入 offline、timeout、429、5xx、坏 schema、取消和迟到回调，汇总错误率、拒绝率、耗时和 critical | 报告记录样本、seed 和 hash；critical=0；失败样本不排除；不等待生产指标窗口 |
| V3-703A 客户端 v2 隔离与保留说明 | L | V3-702A | 用静态扫描和自动测试证明智能排版公开入口只到达 v3 Session；v2 私有代码原位保留，不做消费者普查、迁移或删除 | 公开入口无 v2 路由符号；新旧相关测试全绿；产出简短隔离矩阵和保留说明，不新增兼容 wrapper |
| V3-704A 服务端旧端点隔离与保留说明 | M | V3-703A | 用路由矩阵和 Go 测试证明旧端点与 v3 端点独立、无路径冲突；旧端点原位保留，不做 census、410 或删除 | v2/v3 路由均可独立测试；v3 smoke 全绿；文档明确旧端点仅为比赛版本兼容保留 |
| V3-705A 比赛交付包与最终技术审计 | M | V3-704A | 同步架构、接口、任务状态、测试结果、演示步骤、已知边界和回滚说明 | 69 张任务卡状态/证据可索引；G0～G5 与 FINAL 可复验；演示可按 runbook 重放；不宣称生产发布完成 |

并行边界：Phase 7 主链默认串行，避免多个代理同时改演示证据。任何 smoke 或故障注入失败都退回对应任务修复；V3-703A/V3-704A 只证明隔离，不删除旧实现。

## 12. 工程量总览

| Phase | 叶子任务 | S | M | L | 工程判断 |
| --- | ---: | ---: | ---: | ---: | --- |
| 0 质量协议 | 13 | 2 | 8 | 3 | 数据冻结和 runner 是主要成本；已完成的 AI surrogate 盲审证据保持冻结，不追加复审 |
| 1 Snapshot/分割/会话 | 8 | 0 | 6 | 2 | 按 revision、snapshot、分割、资产和 session 五条内聚链合并，仍保留各自测试检查点 |
| 2 分析与语义 | 8 | 0 | 2 | 6 | 双端协议、服务端路由、客户端集成与语义纠错按可独立回滚边界保留 |
| 3 测量/几何/变换 | 6 | 0 | 2 | 4 | feature-private 几何主链与相邻 editor 快照/适配保持分离 |
| 4 生成与评分契约 | 9 | 0 | 3 | 6 | planner 与 flow 各保留两个高风险切片，oracle、fallback、指标和 Gate 分离 |
| 5 Patch/真实预览/UI | 11 | 0 | 0 | 11 | Patch、Reducer、commit、真实 renderer、门禁和三段 UI 纵切分别验收 |
| 6 完整验证 | 7 | 0 | 2 | 5 | 兼容、CI、聚合、压力、平台和 frozen 评测各形成一份可复用证据包 |
| 7 比赛演示/交付 | 7 | 0 | 4 | 3 | 默认关闭入口已完成；剩余任务集中在演示 smoke、故障注入、v2 隔离和最终交付包 |
| **合计** | **69** | **2** | **27** | **40** | Phase 0 完成记录原样保留；后续不再为同一工作包反复领取、提交和复审 |

S/M/L 只表达相对工程范围，不换算日历或人力。任务数量也不是进度：只有依赖、实现、自动验证和证据都完成才计为 completed。合并任务必须在同一任务内按原子检查点逐段自测；若实际出现不同权限、回滚或验收边界，再有证据地拆分，不预先制造叶子任务。

## 13. 流水线与硬约束覆盖审计

| 固定流水线阶段 | 主要任务 | 不允许遗漏或后移的验收 |
| --- | --- | --- |
| SceneRevision / PageSnapshot | V3-101A、V3-102A | files/document/binding 进入 fingerprint；typed text 使用 exactText；source ledger 完整 |
| InkRegionSegmenter / correction | V3-103A～B、V3-104A | 非 O(N²)、不确定区域 preserved、局部重算与全量等价 |
| V3Analyzer / repository | V3-200A、V3-201A～B、V3-202A、V3-203A | 双端强类型、真实 `/api/ink/smart-layout/analyze/v3` 路由、strict decode、真实取消和稳定错误映射 |
| SemanticDocument / correction | V3-204A、V3-205A | unknown/conflict 保留、持久化版本、修正可逆且只失效受影响集 |
| LayoutCompositionPlanner | V3-400A、V3-401A～B、V3-402A～B、V3-403A | 真实文本测量、图片 contain、关系原子性、oracle 防误剪枝、无解不伪装成功 |
| feature-private ScenePatchBuilder | V3-500A～B | candidate 一次物化完整 patch；构建后不再临时推导坐标或关系；不建立全编辑器事务框架 |
| feature-private SceneReducer | V3-501A | preview/commit 同源；失败原子；通过既有 History 可精确 undo/redo |
| DraftSceneRenderer | V3-503A | 复用真实 painter/font/image/formula；平台 golden 分开审批 |
| Hard Gate / Metrics / Scorer / Top 3 | V3-404A、V3-405A、V3-504A～B | 硬失败不能被平均分抵消；真实 Scene 后才评分；纠错后完整重验；反投机；不足 3 个不凑数 |
| Session / compare-and-commit | V3-106A、V3-502A、V3-505A～C、V3-506A | commit 只接收 `ValidatedCandidate`；仅接真实智能排版入口；revision 冲突零 Scene/History/broadcast；取消/离页/迟到零污染；可访问性完整 |
| 评测、平台和比赛交付 | Phase 0、V3-600A～V3-705A | 开发线完成三基线、frozen、可用端构建及 deferred matrix；比赛交付线完成演示 smoke、合成故障注入、v2 隔离证明和最终 runbook |

若新增实现步骤无法映射到上表，应先判断它是否属于未发现的必要职责；属于则新增叶子任务和依赖，不属于则不得作为猜测性抽象进入代码。

## 14. 统一验证命令

每张任务卡选择与改动匹配的 focused 命令，并在阶段 Gate 执行全量命令：

```powershell
cd FlowMuse-App
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test <focused-test-path>
flutter test

cd ..\FlowMuse-Server
go test ./internal/recognition/...
go test ./...
go vet ./...
```

协议任务必须同时运行 Dart/Go fixture conformance；UI 任务必须包含 widget/accessibility 或 pixel golden；共享 editor 任务必须覆盖 Excalidraw round-trip、History 和协作 LWW；OHOS 原生边界任务额外执行：

```powershell
cd FlowMuse-App
flutter build hap
```

单元测试、合成 smoke 与 AI surrogate 只用于比赛项目的工程验收，不延伸为生产或真人结论。所有剩余任务按其 `validation_mode` 生成可复验的自动化证据，不再等待外部文件。

V3-605A 在当前可用主机上真实执行；Windows 无法构建 iOS/macOS 时记录 `release_deferred`、目标 runner、恢复命令和未验证范围。比赛交付接受该平台边界，V3-700A 只在当前可用的本地/演示环境运行端到端 smoke。

## 15. 执行批次与依赖控制

| 批次 | 启动条件 | 主任务 | 可并行边界 |
| --- | --- | --- | --- |
| A | 无 | Phase 0 | rubric/runner 分线，集合冻结后汇合 |
| B | Gate 0 | Phase 1 | revision、session、snapshot 分线；分割与资产分线 |
| C | Snapshot/协议入口可用 | Phase 2 与 Phase 3 前半 | 服务端 analyzer、客户端 repository、文本测量、几何可并行 |
| D | Gate 1、Gate 2 | Phase 4 | planner 主链与指标契约分线；scorer 不提前读取 placement |
| E | Gate 3 | Phase 5 | Patch/Reducer/Renderer/门禁主链；commit 等待验证封装；纠错、候选 UI 和真实入口分卡汇合 |
| F | Gate 4 | Phase 6 | 兼容、CI、性能并行；可用平台实测、不可用平台冻结 release-deferred 协议，再执行 AI frozen |
| G | Gate 5 | Phase 7 | V3-700B→V3-701A 已完成默认关闭代码；随后连续完成演示 smoke、合成稳定性、v2 隔离证明和比赛交付包 |

若依赖未满足，任务保持 `planned`；真实代码路径测试失败时不得用文字或 mock 声称完成。`ai_synthetic_development` 与 `competition_delivery` 均由 Agent 执行，后者只对比赛演示可复现性负责，不依赖真人、设备农场、生产流量或外部事实文件。

## 16. 任务卡落地模板

领取叶子任务时复制以下字段到 issue/MR：

```text
任务 ID / 标题：
状态：planned | ready | in_progress | blocked | completed
负责人：
复审模式：automated | independent | panel_evidence
复核人 / run id（仅 independent）：
量级：S | M | L
范围层级：核心重构 | 交付验证 | 兼容验证
直接依赖及证据：
目标 / 非目标：
输入 / 输出 / 不变量 / 失败语义：
实际修改文件：
热点文件占用：
范围外文件 diff：无 | 最小适配及理由
实现检查点：
focused test 命令与预期：
跨端 / Excalidraw / 协作影响：
文档更新：
回滚方式：
完成证据链接：
```

本文件定义任务；实际 issue/MR 初始化为 `planned`，只有直接依赖的完成证据可读取才可转为 `ready`。`automated` 任务以命令、产物 hash 和提交边界验收，不调用子代理；`independent` 仅用于高风险协议/算法/事务/集成和阶段终点；`panel_evidence` 使用任务自身的双盲与条件仲裁证据，不再叠加独立复审。状态转换、负责人、适用的复核人和证据链接是 Gate 的机器审计输入。

不得用“代码已写”“测试基本通过”“后续优化”作为完成证据。任务执行中若实际范围超过量级边界，先更新本任务表和依赖，再继续编码。

## 17. 二轮复审缺口关闭映射

| 复审风险 | 关闭任务与约束 |
| --- | --- |
| 局部 correction 过早引用候选，且没有最终重跑 | V3-104A/V3-205A 只产受影响集合；V3-504B 承担 planner→patch→render→gate→score 重跑和全量等价验证 |
| source coverage 多本账、状态含糊 | V3-102A 创建唯一 `SourceCoverageLedger`；V3-204A/V3-400A/V3-500A/V3-504A 只透传并校验；所有 source 最终只能 consumed 或 preserved |
| 服务路由与错误链不完整 | V3-201B、V3-203A 验证真实路由、取消、超时、限额、错误映射和 capability off 零请求；不新增供应方政策或同意流程 |
| 迁移前快照晚于生产接入 | V3-304A 前置，V3-303A 直接依赖该快照并完成最小适配回归 |
| 生成期按软排名误剪枝，保守候选/fallback 混淆，去重缺 placement 依赖 | V3-401B 只验证硬可行集；V3-401A/V3-403A 明确分型；V3-405A 依赖 V3-402B，结构配额归 V3-401A |
| 未经真实门禁即可 commit | V3-501A 不导出 commit；V3-504A 封装 `ValidatedCandidate`；V3-502A 是唯一提交入口且直接依赖 V3-504A |
| UI 任务过大且 Gate 4 未接真实智能排版入口 | V3-505A～C 依次闭合会话操作、纠错/候选、真实入口/错误/可访问性；V3-506A 禁止用 fake provider 作为证据 |
| Gate 5 输入、导出兼容、benchmark/spec 和任务状态不闭合 | V3-601A 依赖 V3-600A；V3-606A 直接依赖兼容/导出/CI/性能/平台证据；V3-001B/V3-004A～C 冻结 benchmark/EvaluationSpec/hash；任务模板补复审模式 |
| 比赛项目被生产发布流程拖住 | V3-700B 在 V3-701A 前验收 instrumentation；V3-700A～V3-705A 改为本地演示、合成稳定性和隔离证明，旧实现保留 |

本轮未加入临时纵向切片或可丢弃实现。剩余任务只补齐比赛演示和技术验收闭环，不再引入生产治理职责。

## 18. Agent Execution Manifest

本任务书的 69 项执行任务已实例化为 [Agent Execution Manifest](smart-layout-v3-agent/agent-execution-manifest.json)，执行说明见 [smart-layout-v3-agent/README.md](smart-layout-v3-agent/README.md)。Manifest 记录每项任务的依赖、允许路径、精确符号或产物键、测试命令、预期退出码、证据路径、必要复审、单任务提交和失败回退点；当前执行者均为 agent。

统一可执行入口为 `scripts/smart-layout-v3/AgentExecution.ps1`。它从本文件解析任务并校验源文件 SHA-256；任务表发生任何变化后必须重新运行 `-Action Generate`，禁止直接手改生成的 Manifest。`Sync` 只按已完成依赖把任务从 `planned` 推进到 `ready`，不再读取外部输入。本次重排必须使用普通 `Generate` 保留已有 64 个完成状态和 G0～G5 记录，禁止 `-ForceState`。

Gate 0～5 和 FINAL 已改为 Manifest 中的可执行 Gate：正式执行时先验证覆盖任务全部完成、提交与证据匹配、修改路径没有越界，再运行对应 Flutter/Go 命令。任何缺失必需证据、非预期退出码、在既有 `independent` 任务中自审或一个提交复用给多任务均不能转为 `completed`。剩余五项均为 `automated`，不再调用通用复审子代理；临时目录中的一次性脚本只能做只读分析或抛弃式转换。
