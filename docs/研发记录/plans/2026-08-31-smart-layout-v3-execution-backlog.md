# 智能排版 v3 实施任务卡与工程量分解

> 日期：2026-08-31  
> 分支：`feature/smart-layout-v3-refactor`  
> 上位计划：`2026-08-30-smart-layout-v3-architecture-refactor.md`  
> 状态：待 Gate 0 启动；本文件只细化实施，不改变上位架构与质量门禁

## 1. 使用方式

上位计划中的 8 个 Phase、52 个 `V3-xxx` 编号继续作为稳定工作包；本文件用 `V3-xxxA/B/...` 表示可独立领取、实现、验证和审查的叶子任务。共 153 个叶子任务，不按比赛日期、人力数量或日历等待降级。

叶子任务必须满足：

1. 只有一个主要工程目标，不能同时承担互不依赖的协议、算法、UI 和部署改造。
2. 有已满足的直接依赖、确定的输入输出、建议修改边界和可运行的完成证据。
3. 对失败、取消、空输入、旧数据和跨端行为有明确结论；不得把异常路径留给后续 Gate 猜测。
4. 能形成一个独立审查单元。若实现中出现第二个主要目标，停止扩张并新增子任务。
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

每张任务卡只有在以下条件全部满足时才是 `completed`：

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

每个 Gate 都必须运行相对基线的路径审计：默认可修改区逐项映射任务卡，条件式修改逐项核验批准理由，“仅测试”区域的生产 diff 必须为零。路径审计失败与功能测试失败同等阻断。

| 任务范围 | 任务编号 | 所有权解释 |
| --- | --- | --- |
| 核心重构 | V3-100A/B、V3-102A～V3-106C、V3-200A～V3-205C、V3-300A～V3-303C、V3-400A～V3-405B、V3-500A～E、V3-501A～C、V3-502A/B、V3-503A～C、V3-504A～E、V3-505A～G、V3-700A～V3-702B、V3-703B、V3-704A/B | 只拥有智能排版 feature、v3 服务和切流实现；其中 editor 接触仍受最小 gateway 限制 |
| 交付验证 | Phase 0、V3-206A～C、V3-305A/B、V3-406A/B、V3-506A/B、V3-602A/B、V3-603A/B、V3-604A/B、V3-605A～C、V3-606A/B、V3-705A | 只产数据、测试、报告、构建、实验和审计；不能取得被测模块的额外重构权 |
| 兼容验证 | V3-100C、V3-101A～C、V3-304A/B、V3-502C、V3-600A～C、V3-601A/B、V3-703A | 生产实现默认零改动；确需适配时必须使用条件式最小修改流程 |

编号归类只限制所有权，不替代每张任务卡的依赖和完成证据。

## 4. Phase 0：冻结质量协议（13 项）

本阶段不得修改生产排版逻辑。输出是后续所有算法决策的固定裁判。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-000A 失败分类账 | M | 无 | 定义 critical/major/minor、允许关系、禁止模式、反投机案例及最小正反例 | 分类 schema 校验通过；产品/算法/编辑器对同一组样例结论一致 |
| V3-000B 人工 rubric 与锚点样例 | M | V3-000A | 1～5 分 rubric、逐维评分表、每档锚点、分歧处理规则 | 双人试评报告含一致性和仲裁结果，所有失败类可映射 |
| V3-001A FixtureManifest 契约 | M | V3-000A | manifest schema、来源组、授权/脱敏/删除元数据、页面特征、期望产物和版本字段 | positive/negative manifest 均有解析测试；缺少数据边界元数据的真实样本无法进入 runner |
| V3-001B 确定性与 benchmark 环境 | L | V3-001A | 固定字体、DPR、时钟、随机源、Scene/PNG 规范化；冻结主机/OS、warm-up、缓存、并发、P50/P95、峰值内存和超时口径 | 同 fixture 在隔离进程中三次运行一致；benchmark spec 有 hash；V3-002A 前 record/replay 只接受合成数据 |
| V3-001C Runner、受控 replay、报告与 hash | M | V3-001B | 单页/批量 runner、受控网络 replay、分层报告、机器退出码、产物 hash 和失败保留 | 三次运行 hash 一致；故意失败退出非零；未授权/未脱敏/无删除策略的真实录制被机器拒绝 |
| V3-002A 样本清单与数据边界 | S | V3-000B、V3-001A | 样本来源、用户隔离键、授权/脱敏状态、删除流程和禁止用途清单 | 无授权或来源不明样本无法进入 manifest；审计脚本无遗漏 |
| V3-002B 分层抽样与集合隔离 | M | V3-002A | 按来源、内容类型、复杂度、平台特征生成 development/validation/frozen | 同一用户/原稿/派生图不跨集合；分层覆盖报告达预注册要求 |
| V3-002C 双标、仲裁与冻结 | L | V3-002B | 标注手册、双人独立标注、仲裁记录、集合版本和只读冻结清单 | 一致性达标；frozen hash 固定且调参工具拒绝读取 frozen 标签 |
| V3-003A no-op 与 v2 自动基线 | M | V3-001C、V3-002C | 用同一 runner 生成 no-op/v2 的 Scene、PNG、指标、失败分类和资源数据 | 两条基线可重复，缺候选/崩溃/超时不会被记作成功 |
| V3-003B 人工整理基线与总报告 | L | V3-003A | 固定人工任务协议，记录完成时间、修改次数、最终 Scene/PNG，并与前两基线并表 | 盲化编号、操作日志和三基线分层报告齐全，人工结果可重放 |
| V3-004A EvaluationSpec 与阈值预注册 | M | V3-000B、V3-003B | 机器可读 spec 固定聚类单位、估计量/效应量、CI/检验、缺失处理、多重比较、功效、分母、critical=0、非劣/优效阈值、benchmark 预算和停止规则 | spec 有版本、hash 和签字；runner 拒绝未注册指标、未固定分母或 benchmark 环境 |
| V3-004B 统计、rubric 与 golden 变更控制 | M | V3-004A | 只引用 V3-000B rubric 版本；实现 EvaluationSpec、score-human 相关性、golden 审批和变更审计 | 合成结果演练通过/拒绝/数据不足/缺失四种结论；任何 spec/rubric/golden 变化都会改 hash |
| V3-004C Gate 0 证据包 | S | V3-004B | 汇总 rubric、EvaluationSpec、benchmark spec、数据版本、三基线和复现命令并冻结 Gate 0 | 全部引用/hash 可解析；从空报告目录可一条命令重建非人工产物 |

并行边界：`V3-000B` 与 `V3-001A` 可在 `V3-000A` 后并行；数据收集与 runner 实现可并行，但 `V3-002C` 冻结前不得测正式基线。

## 5. Phase 1：Snapshot、分割与会话隔离（22 项）

本阶段只建立可审计输入与生命周期，不实现候选布局。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-100A v3 feature 骨架与依赖边界 | S | V3-004C | 建立五层目录、公开入口和最小导出；不建注册表、插件系统或一实现接口 | 架构/import 测试证明 models/services 不依赖 Widget、HTTP 或 Scene 写入 |
| V3-100B HTTP 最小 gateway | S | V3-100A | 只封装 v3 所需的现有 `NativeHttpClient` 请求、取消和响应端口，不引入第二套 client | fake HTTP gateway 覆盖成功/取消/错误；旧识别 repository 行为不变 |
| V3-100C editor 最小 gateway | M | V3-100A | 只为智能排版 snapshot/revision/draft/validated commit 暴露薄端口，优先包装现有 `MarkdrawController` API | fake gateway 单测通过；旧智能排版公开入口签名不变；未新增通用 editor 抽象 |
| V3-101A SceneRevision 与规范化 fingerprint | M | V3-100C | 从既有 editor change/reconcile 信号形成页面单调 revision，并计算覆盖元素/文件/文档/绑定的 canonical fingerprint | 键顺序和无关序列化差异不改 hash；真实内容变化必改 revision/fingerprint；不修改 History/LWW 语义 |
| V3-101B 本地变化观察接线 | L | V3-101A | 在现有 local edit、undo、redo、load、reset、clear 通知边界更新智能排版 revision，不重排各操作实现 | 每类操作准确递增一次；只读选择/缩放视口不递增；现有 History 测试无改动全绿 |
| V3-101C 远端变化观察与跨端一致性 | L | V3-101B | 从现有 remote reconcile 结果更新智能排版 epoch，生成跨 Dart/平台规范化 fixture；不修改 LWW/reconcile | 相同 Scene 在目标端 fingerprint 一致；远端覆盖和旧包迟到均可检测；协作协议 diff 为零 |
| V3-102A Snapshot 与唯一 SourceCoverageLedger | M | V3-101A | `LayoutPageSnapshot`、对象/笔迹/render asset，以及唯一不可变 ledger；状态只允许 pending/consumed/preserved/ignored-with-user-approval，并记录 approval provenance | 不可变/copy/hash 测试；每个 sourceId 恰有一个状态；无授权 provenance 不能进入 `ignored-with-user-approval` |
| V3-102B 页面提取与 mobility 分类 | M | V3-102A | 按 page 提取 movable/protectedObstacle/background 和 visual bounds/zIndex | locked、PDF、分页底图、页外对象、unknown fixture 分类无歧义 |
| V3-102C 关系、typed text、图片与文件规范化 | L | V3-102B | group/frame/binding、exactText/style、intrinsic image/file refs 写入 snapshot | 嵌套组、旋转、bound text/arrow、裁剪图片和缺文件 fixture 无丢失 |
| V3-103A 笔画特征与局部尺度 | M | V3-102C | 提取局部高度、宽度、方向、密度、时间仅作诊断等确定性特征 | 缩放/平移后的归一化特征满足不变量，空点/单点/异常点安全处理 |
| V3-103B 空间索引、邻接图与连通分量 | L | V3-103A | 复用现有索引或最小实现空间查询，构建非链式邻接与组件 | 与小样本全配对 oracle 等价；3000 笔画不执行 O(N²) 全配对 |
| V3-103C deskew 与列检测 | L | V3-103B | 基于局部方向修正倾斜并识别单栏/多栏/竖排 reading geometry | 倾斜、双栏、错位列和竖排 fixture 的列边界与顺序可解释、可复现 |
| V3-103D line/formula/table/emphasis 分类 | M | V3-103C | 在固定 region graph 上分类正文线、公式、表格线和强调笔画，保留 unknown | 每一类有正反 fixture；unknown 不被强制归类或丢弃；分类不改变 stroke membership |
| V3-103E merge/split 防护与不确定区域 | M | V3-103D | 区域合并/拆分保护、置信状态和默认 preserved 语义 | 高风险误并/误拆反例不丢笔迹；不确定区域不进入自动替换 |
| V3-103F 参数校准与冻结 | L | V3-103E、V3-001C | development 原型、validation 一次选择、参数版本和最差分组报告 | frozen 未被读取；precision/recall、merge/split error 可复现并达 Gate 1 预线 |
| V3-104A RegionCorrectionPatch | M | V3-103E | merge/split correction 值对象、前置 revision、逆操作和合法性检查 | 重复/交叉/失效 patch 被拒绝；apply→inverse 恢复同一 region graph |
| V3-104B region/crop 受影响集 | M | V3-104A | 只计算 region graph、render asset 和 crop 的最小失效集合，输出供后续语义层消费的 source dependency keys | region/crop 局部结果与全量重算等价；无关 region、crop 和 source key 的 ID/hash 保持不变 |
| V3-105A clean/annotated/crop 资产构建 | L | V3-102C | 分离干净页、标注页和高清 crop，保存 page↔pixel 变换与 mark 账本 | 同一 source 在三类资产可追踪；标记不进入 OCR crop；越界 crop 明确裁定 |
| V3-105B codec、资源和取消收口 | M | V3-105A | 统一 image/picture/codec 生命周期、并发上限、取消和异常释放 | 注入导出/编码/取消失败后资源计数归零，无迟到 callback 写状态 |
| V3-106A SmartLayoutSession sealed state | M | V3-100A | 固化状态、允许迁移、stage error、retryable 和 reviewing 往返 | 状态表正反测试覆盖全部边；非法迁移在进入副作用前失败 |
| V3-106B operation 与 continuation 四检 | M | V3-106A、V3-101A | operationId/pageId/revision/disposed/cancel token 守卫和统一 continuation helper | cancel、离页、重入、远端变化、迟到成功/失败均不能污染新 session |
| V3-106C editor gateway 与重入回归 | L | V3-106B、V3-101C | 定义 snapshot、draft、validated commit 所需最小 editor API，替换新增 bool/completer 状态；本阶段不暴露可绕过门禁的 v3 commit | 旧流程快照保持；双击入口、切页、dispose、连续重跑场景自动测试全绿 |

并行边界：revision 主链 `101A→101B→101C` 串行；snapshot 与 session 可在 `101A` 后并行；分割主链串行，资产构建可在 `102C` 后与分割并行。`markdraw_controller.dart` 仅允许 `V3-100C`、`101B/101C`、`106C` 按顺序占用。

## 6. Phase 2：强类型分析与语义纠错（23 项）

本阶段让识别结果成为可校验、可纠错、可持久化的语义文档；不得生成最终坐标。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-200A v3 canonical request/response Schema | M | V3-004C | 固定端点 `/api/ink/smart-layout/analyze/v3`；请求关联 page/revision/fingerprint、annotated/clean/crop assets、marks、typed exactText、source refs 和 asset hash；响应、能力、版本、错误码与 HTTP 映射一并定义 | 字段来源映射可追到 Snapshot/asset；typed text 不来自模型；缺字段、错 asset、越界、环、未知枚举和超限均有 negative fixture |
| V3-200B Dart/Go 强类型模型 | L | V3-200A | 两端不可变/强类型 DTO 与容错外层解析；核心协议不穿透动态 map | positive fixture 双端解析等价；所有 negative fixture 同类拒绝且无 panic |
| V3-200C 完整端点与跨端 conformance runner | M | V3-200B | 按完整路径注册 handler contract test，共享 request/response fixtures 和 round-trip diff | Dart→JSON→Go→JSON→Dart 已定义字段无损；asset/source/revision 关联一致；未知字段按 Schema 策略一致忽略或拒绝 |
| V3-201A 独立 V3Analyzer 服务骨架 | L | V3-200C | 独立 analyzer/注册/配置/模型调用，不复用旧 `SmartLayouter` 业务实现 | v2/v3 可独立启停；fake provider 覆盖成功、超时、限流、无效响应 |
| V3-201B strict decode 与 sanitize | L | V3-201A | 引用、基数、readingOrder、关系环、长度、typed text 回填和 unassigned preserved | 恶意/残缺模型响应只能得到已校验文档或稳定错误，不能部分信任 |
| V3-201C 供应方隐私 ADR 与策略版本 | M | V3-201A | 在真实数据进入服务前冻结供应方保留、训练使用、删除能力、地域/子处理方、诊断禁用、consent policy version 和替换/停用条件 | ADR 有审查与版本；任一强制条件未知或不满足时 capability fail closed |
| V3-201D 隐私、日志与传输门禁 | M | V3-201B、V3-201C | TLS/代理配置检查、请求体日志禁用、raw record 默认关闭、指标白名单和诊断访问/删除控制 | 服务端/代理日志扫描无图像、OCR、prompt、token；生产与诊断配置拒绝测试全绿 |
| V3-201E 真实进程 live-route smoke | M | V3-201D | 启动实际 server/mux 与 V3Analyzer/RegisterV3，验证完整路径、body limit、能力、超时、取消、错误映射和响应 schema | synthetic HTTP 成功/失败矩阵通过；旧端点与 v3 可独立启停且路由无串线 |
| V3-202A 总览 role/order/relation 分析 | L | V3-201B、V3-105A | 总览图只产角色、顺序、关系、置信和 evidence，不改 typed text 原文 | typed-only、图文混排、双栏、unknown fixture 的引用和顺序全部合法 |
| V3-202B crop OCR/formula 与冲突合并 | L | V3-202A、V3-105B | 仅对需要项走高清 crop；保存 overview/crop 冲突，不静默择一 | crop 输入确实不同；低置信/公式触发准确；冲突进入文档和校对流程 |
| V3-203A 可取消 AnalysisRepository | M | V3-200C、V3-100B | 复用 `NativeHttpClient`，实现请求、cancel token、错误翻译和重试边界 | 取消真实中断可中断请求；不可中断平台返回后被 operation 守卫丢弃 |
| V3-203B continuation 与网络故障测试 | M | V3-203A、V3-106B | 每个 await 后统一四检，覆盖 timeout/offline/429/5xx/bad schema/late response | 所有故障有稳定 stage/error/retryable；状态更新次数可断言且无泄漏 |
| V3-203C ConsentPolicyGate | M | V3-201C、V3-203A、V3-106B | consent/policy version、接受/撤回状态和 repository 前置拒绝；使用现有本地设置存非敏感同意版本，不改 DB schema | 未同意、已撤回、策略升级或 capability off 时 capture/upload/retry 请求数为 0 |
| V3-203D 客户端—真实服务联调 | M | V3-201E、V3-203B、V3-203C | AnalysisRepository 对真实 synthetic server 验证 request asset/source 映射、能力、取消、错误和日志边界 | 不使用 fake provider；完整成功/拒绝/超时/取消路径可重复，双方 schema/hash 一致 |
| V3-204A LayoutSemanticDocument 与 assembler | M | V3-202B | title/sections/blocks/relations/readingOrder/conflicts 的不可变领域模型和组装器 | 同输入确定性；重复 source、悬空 relation、缺 order 在组装期被处理 |
| V3-204B ledger 投影、unknown 与 conflict | M | V3-204A、V3-102A | SemanticDocument 只引用并校验唯一 SourceCoverageLedger，不复制第二套状态；保存 unknown/conflict 解释 | snapshot→semantic ledger hash/状态守恒；unknown/unassigned 默认 preserved，无法被评分隐藏 |
| V3-204C 持久化版本映射 | L | V3-204B | `SemanticDocument ↔ SmartLayoutDocument` 版本映射、旧版本读取和未知字段保留 | current round-trip 深度等价；旧 fixture 可读；新字段经旧路径不被误删 |
| V3-205A 语义 correction patch | M | V3-204C | role/order/caption relation/preserve/protect patch、revision 前置和 inverse | 每类 patch 有 apply/inverse/非法输入测试，禁止直接原地改文档 |
| V3-205B region correction 与影响图接入 | M | V3-205A、V3-104B | region merge/split 转为语义节点/关系失效集合并保留 correction 历史 | region 改动不触碰无关节点；过期 revision patch 被拒绝且无副作用 |
| V3-205C 局部语义重分析 | L | V3-205B、V3-203D | 只重跑受影响 crop、semantic node 和 relations，输出稳定 affected source keys；不在本阶段引用 candidate/scorer | 语义局部重算与全量语义重算等价；取消/连续修正只提交最后一次 operation |
| V3-206A 分析指标与最差分组报告 | M | V3-103F、V3-202B | segmentation、CER/WER、role/order/relation、校准误差的统一报告 | development/validation 分开；空分组和低样本明确标记，不用总体均值掩盖 |
| V3-206B 语义闭环与纠错收益 | M | V3-204C、V3-205C | round-trip、source coverage、纠错前后指标和局部重算成本报告 | correction 不降低无关分组；持久化重开后语义与 correction 历史一致 |
| V3-206C Gate 1 证据包 | S | V3-206A、V3-206B、V3-201D、V3-203D | 汇总协议、真实路由/联调、consent、隐私 ADR/日志、分析指标、参数冻结和复现命令 | Gate 1 阈值全部机器判定；缺任一策略/hash/live-route 证据时 planner 保持 blocked |

并行边界：协议 `200A→200B→200C` 串行；服务端 analyzer 与客户端 repository 在 `200C` 后并行；总览/crop 与语义 assembler 串行。v3 schema 是本阶段唯一协议真源，修改必须独占。

## 7. Phase 3：测量、几何和变换契约（16 项）

本阶段只交付智能排版 feature 内的真实测量、几何和变换能力，不重构通用 editor、SelectTool 或其他布局功能。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-300A design token 基线与候选值 | M | V3-004C | 从现有 UI/renderer 和 development pilot 提取字号、行距、栏宽、间距、snap、孤行等候选 | 每个值有来源和适用范围；不引入用户可调参数或第二套硬编码 |
| V3-300B 真实文本测量 adapter 与缓存 | L | V3-300A | 复用 TextPainter/font resolver，按 width/fontTier/style 测量并建立有界缓存 | 与实际 renderer 同字体结果一致；缓存 key 完整，失效和上限可测试 |
| V3-300C 边界语种 fixture 与 token 冻结 | M | V3-300B | CJK、长词、emoji、RTL、公式、widow/orphan、缺字体 fixture 和 validation 报告 | 无字符数估算/ellipsis；validation 确认后 token 版本冻结 |
| V3-301A feature-local visual bounds 与保守几何契约 | M | V3-102C | 复用现有 bounds/helper，只补智能排版需要的 AABB/OBB 选择、旋转/线/笔迹/图片可视边界和误差上限 | 与 renderer 采样 oracle 对照；选择 AABB 时提供零漏碰撞证明；未替换全局几何实现 |
| V3-301B 排版碰撞查询与 protected obstacle | L | V3-301A | feature 内实现或薄封装相交、contain、间距、页界和空间查询，接入保护对象 | 旋转、嵌套、零尺寸、页边界 fixture 无漏报；输入对象不可变；无第二消费者不导出公共 kernel |
| V3-301C 零漏检 oracle 与性能 | M | V3-301B | 小场景像素/全配对 oracle、大场景索引 benchmark 和误差报告 | oracle 漏检为 0；3000 笔画/100 块达到预注册本地预算 |
| V3-302A 元素支持矩阵与拒绝条件 | M | V3-301A | 按元素类型列 move/resize/rotate/不支持，覆盖 group/frame/binding/line/freedraw/image | 每个矩阵单元有 fixture 或明确拒绝码，不存在默认“尽量变换” |
| V3-302B 坐标系与传播顺序 | M | V3-302A | 父子坐标、points、rotation、frame clipping、bound text/arrow 重算顺序 | 契约文档和伪场景示例可由测试逐步复现，无循环传播 |
| V3-302C TransformContract conformance fixtures | L | V3-302B | old/new Scene、嵌套组、旋转 frame、绑定链和损坏输入的共享 fixture | 合法场景深度期望一致；未覆盖类型原子拒绝而非部分成功 |
| V3-303A 纯主元素变换器 | L | V3-302C | 无 UI/History 的 move/resize/rotate 主元素变换，输入输出不可变 | identity/inverse/组合不变量及各元素 focused test 通过 |
| V3-303B 统一依赖重算 | L | V3-303A | 主元素完成后统一重算 group/frame/bound text/arrow/points/index/version | 顺序随机化不改变结果；关系双向一致；未知扩展字段保留 |
| V3-303C 原子拒绝与智能排版 gateway 接入 | L | V3-303B、V3-304A | 变换预检、错误目录、全有或全无结果，只接入智能排版 draft gateway | 失败时 Scene/hash/history 均不变；相邻行为快照全绿；Excalidraw round-trip 与 LWW 兼容测试全绿；未导出通用 transform API |
| V3-304A 实际触及 helper 的迁移前快照 | M | V3-004C | 先列出 V3-301～303 确实会修改的既有 helper，只为这些函数及现有调用者固定输入输出快照 | helper allowlist 外文件无改动；快照在修改前落库；相邻产品模块无专项改造 |
| V3-304B 最小适配与相邻行为回归 | M | V3-304A、V3-303C | 优先保持既有 helper/API 原位；只有智能排版无法通过现有接口完成时增加薄 adapter，不迁移其他调用者、不删除共享实现 | allowlist 调用者快照与 focused test 全绿；无公共 wrapper 链、无相邻模块所有权变化 |
| V3-305A 变换矩阵 runner | M | V3-302C、V3-303C、V3-304B | 对 move/resize/rotate/group/frame/binding/line/freedraw/image 批量执行 conformance | 每格输出 pass/reject/unsupported，拒绝原因稳定，零静默跳过 |
| V3-305B Gate 2 证据包 | S | V3-305A、V3-301C | 汇总矩阵、零漏检、性能、兼容和复现命令 | Gate 2 全部机器判定；失败时 ScenePatch 任务保持 blocked |

并行边界：文本测量、feature-local 几何和 `V3-304A` 触及清单/快照可并行；`302A→302B→302C→303A→303B→303C` 是严格串行主链，但 `303C` 接入 gateway 前必须先有 `304A`。`V3-304B` 只允许最小 adapter 与回归，不承担共享几何搬迁或相邻功能清理。

## 8. Phase 4：候选生成与评分契约（22 项）

本阶段决定排版效果上限。候选生成只使用冻结语义、测量和 tokens；VLM 不返回坐标，最终推荐不得在真实 Scene 前产生。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-400A LayoutBlock 与 BlockAssembler | M | V3-206C、V3-300C | 从 semantic node 生成统一 block，携带同一份 `SourceCoverageLedger` 及其 hash，并带 sourceRefs、intrinsic/min/max、presentation、keep/weight | 不新建第二本 ledger；状态和批准来源逐项守恒；typed/transcribed/preserved 明确；同输入确定性 |
| V3-400B 文本与结构原语 | M | V3-400A | title/heading/paragraph/list/section skeleton 原语和真实 measure callback | 多层标题、列表、长段、空文本 fixture 不丢 reading order |
| V3-400C 图像、公式、保留与保护原语 | L | V3-400B | figure-card/formula/side-note/preserve-block/protected-zone 与关系原子性 | 图片 intrinsic/crop/ratio 保留；caption/keep-together 无法拆散；unknown 保留 |
| V3-401A Planner 输入输出与确定性枚举 | M | V3-400C | `LayoutCompositionPlanner` 的决策变量、候选 ID、稳定枚举顺序和错误 | 随机迭代容器不改变输出；同输入候选顺序/hash 一致 |
| V3-401B 四种宏观 skeleton 枚举 | L | V3-401A | single/two-column/main-side/`conservative-layout` 的有限结构组合；后者仍是会改写布局且必须过完整门禁的生成候选 | 每种 skeleton 有适用/拒绝 fixture；`conservative-layout` 不被标作必然合格，也不等于零修改 fallback |
| V3-401C token 参数域、结构配额与上限 | M | V3-401B | 参数仅来自冻结 tokens，按结构保留配额，完整候选最多 12 | 上限前不因枚举顺序饿死某结构；超限结果可解释且确定 |
| V3-401D 硬可行性下界剪枝 | L | V3-401C | 只依据 source coverage、关键 relation、最小面积和粗几何等单调硬可行性下界裁枝；不得读取软分、当前排名或“无法超过当前候选集” | 每条剪枝有硬约束证明、断言与反例；排名和 profile 变化不改变可行结构集合 |
| V3-401E 全枚举 oracle 与可行集等价验证 | L | V3-401D | 小 fixture 测试专用全枚举器和 planner 差分 harness | planner 不丢失任何满足硬可行性的 oracle 结构；误剪枝直接使测试失败 |
| V3-402A reading order 流式放置 | L | V3-401C | 按 semantic order 生成行/栏流，保留不可交换关系 | 顺序 fixture 和 source ledger 一致；无基于短文本的暗标题规则 |
| V3-402B 目标栏宽真实换行 | L | V3-402A、V3-300C | 调真实 measure callback 做 wrap、最小字号和高度计算 | CJK/长词/emoji/RTL 无裁字、省略号或字符估算，重复运行一致 |
| V3-402C keep、列表、章节与公式原子性 | M | V3-402B | keepTogether/keepWithNext、列表项、章节标题、公式的分页内放置约束 | 不可满足时返回原因，不静默拆散关键关系或缩到阈值以下 |
| V3-402D 栏平衡、contain 与障碍绕置 | L | V3-402C、V3-301B | 栏高平衡、页界 contain、protected zone 避让和密度控制 | 双栏/主侧栏/满页障碍 fixture 零硬碰撞，失败原因可追踪 |
| V3-402E figure/preserved block 与确定性回归 | L | V3-402D、V3-400C | 图片等比 contain、caption 栈、保留手写块和综合布局回归 | crop/ratio/绑定不变；preserved 路径和转写路径都通过 golden geometry |
| V3-403A 生成期 preflight 与原因码 | M | V3-402E | 仅检查 source coverage、关键 relation、粗几何和明显不可容纳，并返回稳定原因 | preflight 不调用真实 scorer；所有 reject 可映射用户建议 |
| V3-403B NoFeasibleLayout 与 `preserveFallback` | M | V3-403A | 将原结构零修改结果定义为独立的 `preserveFallback` 结果类型，区分无解、内部错误和可重试分析失败；它不是 `LayoutCandidate` | `preserveFallback` 不进入 scorer、结构配额、合格率或 Top 3；原场景违规时明确说明未通过门禁 |
| V3-404A 指标归一化与硬软边界 | M | V3-403B、V3-004A | 七类软指标的方向、量纲、归一化、缺失值和硬约束隔离 | 任一硬失败不能被软分抵消；指标对构造样例单调且有范围断言 |
| V3-404B 三个目标 profile | M | V3-404A、V3-000B | 可读性、保留结构、图文展示三套固定权重/排序偏好，只引用 Gate 0 冻结的 rubric 版本与 hash | 不复制或改写 rubric；profile 共用生成器/硬约束；每套正反例排序符合人工预期 |
| V3-404C 反投机否决与解释 | M | V3-404B | no-op、极缩、隐藏、巨大留白、重复内容、成本造假的否决线和分解解释 | adversarial fixture 全被拒绝；每个 score 可还原到原始 metrics |
| V3-405A 结构签名与等价去重 | M | V3-401E、V3-402E | 对已经完成流式放置的 placement 建 canonical signature，只删除契约定义的等价结构；结构配额仍唯一归 V3-401C | 平移噪声/ID 差异按契约处理；不同叙事结构不会被误去重；`conservative-layout` 与 `preserveFallback` 不会混淆 |
| V3-405B 真实 Scene metrics 契约 | M | V3-404C、V3-301A | 定义 Renderer 后 coverage/relation/order/visual bounds 等 metrics 输入输出 | 合成 placement 不能直接冒充最终 metrics；缺测量字段 fail closed |
| V3-406A Planner oracle、质量与性能报告 | L | V3-402E、V3-403B、V3-405A | 汇总可行解漏检、无解误判、结构多样性、确定性和本地性能 | validation 全集可重复；最差分组和每种 skeleton 单独报告 |
| V3-406B Gate 3 证据包 | S | V3-406A、V3-404C、V3-405B | 冻结 planner/scorer 契约、参数版本、报告和复现命令 | 所有 Gate 3 条件机器判定；失败不得通过调单张 fixture 权重绕过 |

并行边界：BlockAssembler 完成后 planner skeleton 与指标契约可分线推进；`401` 和 `402` 内部均按编号串行。生成期只允许硬可行性剪枝，结构配额唯一归 `V3-401C`；Scorer 不读取未经过真实 Scene 的最终值，`V3-405B` 只冻结契约，不提前实现 Phase 5 extractor。

## 9. Phase 5：ScenePatch、真实预览和用户工作流（28 项）

本阶段把候选变成真实 Scene 事务。固定顺序为 PatchBuilder → Reducer → Renderer → Hard Gate → Score → Top 3，不允许捷径。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-500A feature-private 不可变 ScenePatch | M | V3-305B、V3-403B | 只为智能排版定义 patch identity/baseRevision、element add/update/remove 和操作顺序模型 | patch 不持有可变 Scene；重复 ID、冲突操作和悬空 update 在构建期拒绝；不导出为全编辑器事务框架 |
| V3-500B 字段、关系和版本归一化 | L | V3-500A | 位置/尺寸/角度/style/text/points、group/frame/binding、index/version/versionNonce 完整 delta | 与 TransformContract 一致；双向关系和版本字段无遗漏；未知扩展保留 |
| V3-500C file/document/selection 与 write set | M | V3-500B | file refs、SmartLayoutDocument、selection intent、精确读写集，并透传和校验唯一 `SourceCoverageLedger`/hash | 不创建第二本 ledger；写集覆盖全部副作用；删除仍被引用文件被拒绝；selection 不污染协作数据 |
| V3-500D 校验、深度等价与 fixture codec | M | V3-500C | patch validator、canonical debug codec、deep equality 和正反 fixture | codec 只用于测试/诊断且不成为新持久化格式；非法 patch 零部分结果 |
| V3-500E ScenePatchBuilder | L | V3-500D、V3-402E、V3-303C | 将完整 `LayoutCandidate` 一次性物化为元素/关系/file/document/selection patch，调用 feature-private transform 而不回写 Scene | candidate→patch fixture 覆盖全部原语；构建后不再推导坐标；不支持类型原子失败且 source ledger 守恒 |
| V3-501A 纯 SceneReducer 与操作次序 | L | V3-500E | 无 UI/History/网络副作用地执行 remove→update→add 等固定顺序 | 输入 Scene 不变；同 patch 同结果；失败返回原子 error 不返回半成品 Scene |
| V3-501B 关系、文件、文档与 selection 折叠 | L | V3-501A | 统一重算依赖并生成完整 Draft Scene、files、document、selection result | group/frame/binding/file refs 深度一致；外部导出 sanitizer 边界不被绕过 |
| V3-501C preview adapter 与既有 History bridge | L | V3-501B | preview 调用 feature 内唯一 reducer；最终提交把同次 before/after 转为既有 `ToolResult/CompoundResult` 与 History 操作，不创建新 History 框架 | Draft Scene 可重复生成；既有 undo/redo 精确往返且无重复 push；静态 API 测试证明无旁路 commit |
| V3-502A `ValidatedCandidate` compare-and-commit | M | V3-101C、V3-501C、V3-504D | 唯一 commit 入口只接收 `ValidatedCandidate`，在同一临界区复核 page/baseRevision/fingerprint 和 renderer/metrics hash，再用同一 reducer 写入 Scene/History/broadcast | 原始 patch 或过期验证结果无法调用 commit；冲突后三类副作用计数均为 0；preview 与 commit Scene 深度等价 |
| V3-502B 写集相交与一次重派 | L | V3-502A、V3-500C | 先接纳权威变化；写集不相交时基于新 revision 重派一次，相交要求重分析 | disjoint 仅重派一次且结果重验；第二次变化终止；intersection oracle 覆盖 |
| V3-502C 既有协作通道兼容测试 | L | V3-502B | 只通过现有 adapter 投影元素变化，文件/文档走既有通道；不修改 LWW、消息类型或 reconcile | `_shouldKeepLocal/_shouldReplace` 现有行为不变；old/new client、广播和 reconcile fixture 全绿；协议 diff 为零 |
| V3-503A DraftSceneRenderer harness | L | V3-501C | 复用真实 `StaticCanvasPainter`、字体解析、viewport/page 设置的离屏 renderer | 同一 Draft Scene 与编辑器可见渲染几何一致；不新建简化缩略图算法 |
| V3-503B 文本、图片、公式实际边界 | L | V3-503A、V3-300C | 收集真实文本行盒、裁字、图片尺寸/crop、公式显示盒和缺资产状态 | missing font/file/codec 明确失败或受控降级；不以估算值替代真实边界 |
| V3-503C pixel golden 与资源回收 | M | V3-503B | 按平台维护 golden、差异报告、图片缓存/codec 释放和取消测试 | 同平台稳定；跨平台差异分开审批；连续渲染/取消后资源回到基线 |
| V3-504A 真实 Scene metrics extractor | L | V3-405B、V3-501C、V3-503C | 从 reducer+renderer 结果提取 coverage/relation/order/bounds/密度等原始 metrics，并将同一 `SourceCoverageLedger`/hash 追踪到真实元素和 render box | placement 自报数据不被读取；不新建 ledger；metrics 可追溯到 source/element/render box |
| V3-504B HardConstraintValidator | L | V3-504A | coverage、relations、reading order、裁字、比例、group/frame/binding、页界和跨阶段 source conservation 硬门禁 | 每条硬约束有单独 adversarial fixture；ledger 任一丢失、重复、未批准忽略或 hash 断链均拒绝；失败候选不会进入 scorer |
| V3-504C 反投机、Scorer 与 profile 排序 | L | V3-504B、V3-404C | 应用否决线、归一化指标和固定 profile，生成可解释排序 | 与 V3-404 正反例一致；NaN/缺指标/越界值 fail closed；人工相关性可计算 |
| V3-504D 多样性 Top 3、验证封装与无解解释 | M | V3-504C、V3-405A | 先硬门禁再按 profile 排序、结构多样化并最多展示 3 个；合格项封装为带 patch、baseRevision、renderer/metrics/ledger hash 的 `ValidatedCandidate`，并聚合拒绝原因 | 只有本轮完整门禁产物可成为 `ValidatedCandidate`；不足 3 个不补不合格候选；全部失败返回 `NoFeasibleLayout` 和可操作建议 |
| V3-504E 纠错后的候选与评分重跑 | L | V3-205C、V3-504D | `CorrectionRerunCoordinator` 按稳定 affected source keys 重跑受影响 planner/patch/render/metrics/hard gate/score，最终产出新的完整候选集 | region/role/order/relation 修正的局部结果与全量重跑深度等价；旧 `ValidatedCandidate` 全部失效；用户修正是最终可见操作而非只改语义层 |
| V3-505A Session ViewModel 与用户动作 | L | V3-106C、V3-205C、V3-203C | Riverpod 状态机编排同意/策略、范围、目标、保护/保留、分析、生成、review、commit | UI 不持有业务 bool/completer 组合；未同意或策略失效时 capture/upload transition 不存在；每个动作只触发一个合法 transition |
| V3-505E 同意披露与撤回 UI | M | V3-505A、V3-203C | 展示处理范围、供应方/保留/训练/删除政策版本，记录接受并提供撤回；所有入口共用 `ConsentPolicyGate` | widget 测试证明接受前无截图/上传，撤回立即取消并清理待发数据，策略版本变化要求重新确认 |
| V3-505B 纠错与全文核对 UI | L | V3-505E、V3-504E | region/role/order/relation correction、保护/保留调整和全文核对 | 每次修改触发真实最小重跑并使旧候选失效；全文 source ledger 状态和忽略批准可审计 |
| V3-505F 真实候选比较与选择 UI | L | V3-505E、V3-504D | 展示真实 DraftSceneRenderer 缩略图、评分解释、结构差异和候选选择 | 每张卡对应当前 `ValidatedCandidate`；切换只改本地选择，不写权威 Scene；不得用 fake candidate 作为完成证据 |
| V3-505G 智能排版真实编辑器入口集成 | L | V3-505B、V3-505F、V3-502C | 只将 `whiteboard_page.dart` 的智能排版公开入口和 controller gateway 接入真实 Session/compare-and-commit，先置于非生产内部入口；保持公开调用签名 | 真实 server→候选→选择→commit 自动化通过；无 fake provider；现有调用者继续编译且范围外源码 diff 为零；生产 v2 实现保持到 Phase 7 切流 |
| V3-505C 无解、重试与取消交互 | L | V3-505G、V3-403B | 分阶段错误、建议拆页/修正/保护、重试/取消和 session 状态恢复 | 无 modal 死锁；每种原因有正确建议；取消、重试和离页零残留 |
| V3-505D 键盘、读屏与焦点闭环 | M | V3-505B、V3-505C、V3-505F、V3-505G | 为同意、范围、纠错、候选、无解和确认流程补 Semantics、键盘路径、焦点恢复和状态公告 | widget/semantics 测试覆盖完整无鼠标流程；关闭 sheet 后焦点回到触发点 |
| V3-506A 事务与体验回归矩阵 | L | V3-502C、V3-504E、V3-505D、V3-505G | 从真实智能排版编辑器入口执行 preview=commit、undo/redo、cancel/late、draft 拖动、local/remote conflict、纠错重跑矩阵 | 每个场景验证 Scene/History/revision/broadcast/document/ledger 六类状态，全部自动化；现有公开入口委托 smoke 通过；fake provider 不计 Gate 4 证据 |
| V3-506B Gate 4 证据包 | S | V3-506A | 汇总真实渲染、硬门禁、排名解释、UI 可访问性和事务证据 | Gate 4 机器判定；任何深度不一致或 critical failure 阻断 Phase 6 |

并行边界：feature-private Patch/Reducer 主链严格串行；Renderer 可在 `501C` 后推进，commit API 必须等待 `504D`。UI 可用 fake Session 做早期 widget 开发，但 `505B/505F/505G/506A` 的完成证据必须来自真实 analyzer、候选和智能排版编辑器入口。`markdraw_controller.dart` 和 `whiteboard_page.dart` 仅由 `V3-505G` 修改智能排版相关区域；所有其他入口和相邻产品模块不占用、不改造。

## 10. Phase 6：完整验证（16 项）

本阶段只验证 v3 对既有格式、协作、导出和平台的兼容，不取得这些系统的重构所有权。若发现 v3 缺陷，退回对应叶子任务；若发现无关既有缺陷，单独记录并保持 Gate blocked，不塞进本计划修复。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-600A Excalidraw codec 兼容矩阵 | M | V3-506B | 用现有 reader/writer 覆盖 v3 会产生的元素类型、旧 Scene 读取、新 Scene 写入、未知字段和删除保留 | `.markdraw/.excalidraw/json` round-trip 无关键字段丢失，ParseWarning 行为一致；codec 架构与基础字段无改动 |
| V3-600B 既有协作语义兼容矩阵 | L | V3-600A、V3-502C | 用 fixture 验证双端 LWW、index/versionNonce、group/frame/binding、文件和文档并发，不修改协作实现 | 两端收敛到同一 canonical Scene；冲突不覆盖无关编辑；协议、LWW/reconcile 生产 diff 为零 |
| V3-600C 既有 hash/sanitizer 边界验证 | M | V3-600B | 验证 collaborationHash、内部保留/外部剥离、未知 `flowMuse` 键和选择状态；仅在 v3 新字段映射缺失时最小补充 | 内部 SQLite/密文保留合法元数据；所有现有外部出口剥离归属且不误删其他键；未重构 sanitizer |
| V3-601A v3 文档映射与重开兼容 | L | V3-204C、V3-501C、V3-600A | 只实现 `SmartLayoutDocument` 新版本映射，并用既有持久化路径验证旧 Scene 读取、新 Scene 写入、重开、undo/redo/reconcile | 多版本 fixture 重开后 Scene/SemanticDocument/source ledger 深度一致；数据库 schema 与序列化框架不变 |
| V3-601B 既有 Markdown/LaTeX 出口兼容 | M | V3-601A、V3-600C | 复用现有 exporter 验证 title/section/list/formula/figure/caption/unknown；仅补 v3 文档字段映射，不新增格式或 importer | 现有支持范围内字符转义、顺序和关系 fixture 全绿；导出不泄露内部、归属或隐私字段；exporter 架构无改造 |
| V3-602A 可复制 CI 环境 | M | V3-001C、V3-506B | 固定 runner、字体、fixture server、网络 replay、缓存和工作目录 | 新 clone 按文档可运行；无本机绝对路径、个人服务或未声明字体依赖 |
| V3-602B 报告、退出码与证据归档 | S | V3-602A | CI job 的机器报告、失败产物、退出码、版本元数据和保留规则 | 故意破坏 fixture 能阻断 job 并保留足够诊断，不保存 raw 用户内容 |
| V3-603A Go、Schema 与双端 round-trip 门禁 | M | V3-200C、V3-602A | `go test ./...`、`go vet ./...`、schema conformance 和协议 replay job | 服务端独立运行全绿；旧端点 fixture 仍通过直到退役任务开始 |
| V3-603B Flutter 静态检查与测试聚合 | S | V3-603A | format check、`flutter analyze`、focused/all tests 与 golden job | 不新增 analyzer error；所有任务命令从仓库文档可复制执行 |
| V3-604A 大页性能与算法压力 | L | V3-406B、V3-506B、V3-602A | 3000 笔画、100 block、长页、多候选的阶段耗时、复杂度和峰值报告 | 达预注册预算；报告可归因 snapshot/segment/planner/render/score 阶段 |
| V3-604B PNG、取消、离页与资源压力 | L | V3-604A、V3-105B、V3-503C | 连续截图/crop/render、并发取消、切页/dispose、失败注入和内存趋势测试 | 资源回到容差内；无 handle/codec/timer/request 泄漏和迟到状态写入 |
| V3-605A Android/iOS/macOS/Windows/Web 构建 | L | V3-603B | 在匹配 runner 验证包含 v3 的五平台 release/profile 构建，记录产物 hash 和智能排版相关差异 | 五端全部成功；无关既有构建问题单列、不并入本任务实现；本机不支持的平台转交匹配 runner且不得计完成 |
| V3-605B OHOS HAP 与智能排版原生边界 | M | V3-605A | `flutter build hap` 并验证 v3 实际使用的 NativeHttp/字体/图片/文件能力 | HAP 成功；没有误提交生成文件；只允许智能排版所需最小适配，不重构 OHOS 平台层 |
| V3-605C 六平台 smoke 与设备证据 | L | V3-605B | 入口→分析→候选→纠错→commit→undo→reopen 的六端清单和录制证据 | 每端使用实际 renderer；真机项标设备/系统/构建，不用桌面模拟冒充 |
| V3-606A frozen 原作者任务与第三方盲评 | L | V3-004C、V3-600C、V3-601B、V3-602B、V3-603B、V3-604B、V3-605C | 在兼容、既有导出回归、证据归档、全门禁、性能和六端全部完成后，一次性执行 frozen、原作者整理任务、第三方视觉双盲和原始评分 | 输入证据 hash 全冻结；分组和顺序按预注册；frozen 不回流调参；critical 个案逐一审计 |
| V3-606B 效果统计与 Gate 5 | M | V3-606A | 对 no-op/v2/人工基线做优效/非劣、操作成本和 score-human 相关性结论 | §5.3 全条件机器判定；数据不足、失败和拒绝不会被排除后重算 |

并行边界：兼容矩阵、CI 固化和性能 harness 可在 Gate 4 后并行；平台构建在聚合门禁后推进；frozen 只能执行一次，且必须等待自动化、性能和六端证据完成。

## 11. Phase 7：部署、切流和清理（13 项）

本阶段只在 Gate 5 通过后启动。切流、观察、客户端删除和服务端退役必须是不同回滚边界。

| 任务 | 量级 | 直接依赖 | 工程产物 | 完成证据 |
| --- | --- | --- | --- | --- |
| V3-700A v3 服务部署与安全配置 | M | V3-606B | 部署独立 v3 analyzer、健康检查、TLS、请求体日志关闭、供应方保留/训练/删除配置 | 合成 smoke 通过；配置审计无 raw 记录；v2 生产路径尚未改变 |
| V3-700B fail-closed capability 与 kill switch | M | V3-700A | capability 默认 off、无缓存/过期 off、服务确认后 on、远程关闭入口 | 断网、配置服务故障、缓存过期均显示不可用且不回退 v2 |
| V3-700C 生产前隐私与合成端到端审计 | M | V3-700B | 用合成页面验证网关/代理/模型/指标链和隐私说明/同意入口 | 全链日志扫描无请求体/OCR/prompt；真实页面请求条件全部满足 |
| V3-700D 切流前可观测性就绪 | M | V3-700C、V3-004A | 在生产流量进入前安装字段白名单 instrumentation、版本化指标 schema、dashboard、alert 和 kill-switch 信号，只记录不可逆会话指标 | 合成指标注入能触发 dashboard/alert/关闭信号；日志与指标扫描无图像、OCR、prompt 或 Scene；无观测盲窗 |
| V3-701A 智能排版公开入口 v3 单路切流 | L | V3-700D | 保持公开调用签名，只把智能排版入口内部实现切到新 Session；不迁移或改造调用者 | 静态引用扫描+入口自动化证明生产实现不可达 v2；现有调用者源码无改动 smoke 通过；kill switch 只关闭入口；首个真实会话已有版本化指标 |
| V3-701B 回滚点与关闭行为 | M | V3-701A | 独立切流提交、整体 Git 回滚说明、会话中关闭/重开行为测试 | 回滚恢复切流前版本；关闭时不留 Draft/History/广播残留 |
| V3-702A 生产稳定性指标采集与校验 | M | V3-701B、V3-700D | 使用已就绪的不可逆会话计数、阶段耗时、稳定错误码、拒绝率和 critical 事件生成生产窗口数据，并校验采集完整性 | 不在切流后才创建 instrumentation；指标无图像/OCR/Scene；字段白名单、版本维度和缺报检测完整 |
| V3-702B 预注册稳定性结论 | S | V3-702A | 按 Gate 0 的会话量、错误率、critical=0 规则生成通过/阻断报告 | 不用固定日历等待替代样本量；未达样本量明确为 insufficient |
| V3-703A v2 符号消费者清单与保留边界 | M | V3-702B | 盘点旧目录中的符号及所有生产消费者，标记 smart-layout-private 或 shared-in-place；被相邻功能使用的内容保留原位 | 清单含 `rg` 证据和责任归属；不迁移任何范围外调用者；删除集合只含 v2 私有符号 |
| V3-703B 只删除客户端 v2 私有实现 | L | V3-703A | 删除清单确认私有的旧模板、聚类、vision matcher、旧 UI/状态/测试；共享 helper 和相邻模块原样保留 | `rg` 证明删除项无外部生产引用；全量 Flutter/六端关键构建通过；无机会性清理或新兼容 wrapper |
| V3-704A 不可变消费者 census 与 410 阶段 | M | V3-703B | 生成按端点、客户端版本/来源、unknown、最低版本、410 阶段、采样窗口和归零判定规则分层的不可变 census，并验证仍访问时兼容行为 | census 有数据窗口、查询/hash 和签字；unknown、样本不足或任一受支持版本仍访问时禁止进入删除任务 |
| V3-704B 删除服务端旧实现 | M | V3-704A | 只接收签字的 census/hash；满足归零和最低版本规则后删除旧 routes、types、prompts、tests/config | 删除时重新核验同一 census 条件；`rg` 和路由清单无残留；Go 全门禁及 v3 synthetic smoke 通过 |
| V3-705A 文档与交付审计 | M | V3-704B | 同步需求、前端架构、接口、ADR、数据说明、模型使用记录、任务状态、范围偏差和回滚证据 | 153 张任务卡均有状态/证据；范围外模块生产 diff 有明确为零或最小适配说明；文档不再描述 v2 为当前实现；链接检查通过 |

并行边界：Phase 7 主链默认串行。文档可提前准备 diff，但 `V3-705A` 只能在旧端点实际退役后完成；任何稳定性阻断退回对应实现任务，不在观测代码里打补丁。

## 12. 工程量总览

| Phase | 叶子任务 | S | M | L | 工程判断 |
| --- | ---: | ---: | ---: | ---: | --- |
| 0 质量协议 | 13 | 2 | 8 | 3 | 数据冻结和 runner 是主要成本，禁止为赶进度跳过人工基线 |
| 1 Snapshot/分割/会话 | 22 | 2 | 12 | 8 | HTTP/editor 边界分离；分割、revision 和资源生命周期均为独立主链 |
| 2 分析与语义 | 23 | 1 | 15 | 7 | 双端协议、真实路由、同意策略、strict sanitize 和局部纠错决定可归因性 |
| 3 测量/几何/变换 | 16 | 1 | 9 | 6 | 能力保持 feature-private；相邻 editor 只做 helper 快照和最小 gateway 回归 |
| 4 生成与评分契约 | 22 | 1 | 12 | 9 | 排版效果上限所在，planner/flow/oracle 不得合并成一张任务 |
| 5 Patch/真实预览/UI | 28 | 1 | 8 | 19 | 事务正确性最重，纠错重跑、真实入口、同意和候选 UI 独立验收，commit 只接受完整验证结果 |
| 6 完整验证 | 16 | 2 | 7 | 7 | 六端、资源压力和 frozen 实验是正式工程产物，不是收尾抽查 |
| 7 部署/切流/清理 | 13 | 1 | 10 | 2 | 可观测性先于切流；删除受不可变消费者 census 约束，切流、观察和退役保持独立回滚 |
| **合计** | **153** | **11** | **81** | **61** | 不存在 XL；实际超过 L 的任务在领取前继续拆分 |

S/M/L 只表达相对工程范围，不换算日历或人力。任务数量也不是进度：只有依赖、实现、自动验证和证据都完成才计为 completed。Phase 4/5 的 L 数量较高，执行时优先保证接口冻结和热点文件串行，不通过把事务链重新塞回一个控制器来“降低任务数”。

## 13. 流水线与硬约束覆盖审计

| 固定流水线阶段 | 主要任务 | 不允许遗漏或后移的验收 |
| --- | --- | --- |
| SceneRevision / PageSnapshot | V3-101A～C、V3-102A～C | files/document/binding 进入 fingerprint；typed text 使用 exactText；source ledger 完整 |
| InkRegionSegmenter / correction | V3-103A～F、V3-104A～B | 非 O(N²)、不确定区域 preserved、局部重算与全量等价 |
| V3Analyzer / repository | V3-200A～C、V3-201A～E、V3-202A～B、V3-203A～D | 双端强类型、真实 `/api/ink/smart-layout/analyze/v3` 路由、strict sanitize、同意策略、真实取消、raw 数据默认不记录 |
| SemanticDocument / correction | V3-204A～C、V3-205A～C | unknown/conflict 保留、持久化版本、修正可逆且只失效受影响集 |
| LayoutCompositionPlanner | V3-400A～C、V3-401A～E、V3-402A～E、V3-403A～B | 真实文本测量、图片 contain、关系原子性、oracle 防误剪枝、无解不伪装成功 |
| feature-private ScenePatchBuilder | V3-500A～E | candidate 一次物化完整 patch；构建后不再临时推导坐标或关系；不建立全编辑器事务框架 |
| feature-private SceneReducer | V3-501A～C | preview/commit 同源；失败原子；通过既有 History 可精确 undo/redo |
| DraftSceneRenderer | V3-503A～C | 复用真实 painter/font/image/formula；平台 golden 分开审批 |
| Hard Gate / Metrics / Scorer / Top 3 | V3-404A～C、V3-405A～B、V3-504A～E | 硬失败不能被平均分抵消；真实 Scene 后才评分；纠错后完整重验；反投机；不足 3 个不凑数 |
| Session / compare-and-commit | V3-106A～C、V3-502A～C、V3-505A～G、V3-506A～B | commit 只接收 `ValidatedCandidate`；仅接真实智能排版入口；revision 冲突零 Scene/History/broadcast；取消/离页/迟到零污染；可访问性完整 |
| 评测、六端和切流 | Phase 0、V3-600A～V3-705A | 三基线、frozen、六端成功、隐私、切流前观测就绪、单路切流、消费者 census 归零后退役 |

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

真机、视觉盲评和人工基线不能用单元测试代替；反之，真机截图也不能代替自动化契约。

平台任务必须在支持该目标的主机和设备上完成。Windows 本地不能构建 iOS/macOS 不是验收结论，任务保持 blocked，转交 macOS runner 后继续；任何“环境不具备”记录都不能替代 Gate 5 的六平台成功证据。

## 15. 执行批次与依赖控制

| 批次 | 启动条件 | 主任务 | 可并行边界 |
| --- | --- | --- | --- |
| A | 无 | Phase 0 | rubric/runner 分线，集合冻结后汇合 |
| B | Gate 0 | Phase 1 | revision、session、snapshot 分线；分割与资产分线 |
| C | Snapshot/协议入口可用 | Phase 2 与 Phase 3 前半 | 服务端 analyzer、客户端 repository、文本测量、几何可并行 |
| D | Gate 1、Gate 2 | Phase 4 | planner 主链与指标契约分线；scorer 不提前读取 placement |
| E | Gate 3 | Phase 5 | Patch/Reducer/Renderer/门禁主链；commit 等待验证封装；纠错、候选 UI 和真实入口分卡汇合 |
| F | Gate 4 | Phase 6 | 兼容、CI、性能并行；六端后执行 frozen |
| G | Gate 5 | Phase 7 | 默认串行，切流/观察/删除/退役各自独立回滚 |

若依赖未满足，任务状态只能是 `blocked`，不能用 mock 结果声称完成；允许用 fake 提前开发的任务，必须在完成证据中包含真实集成测试。

## 16. 任务卡落地模板

领取叶子任务时复制以下字段到 issue/MR：

```text
任务 ID / 标题：
状态：planned | ready | in_progress | blocked | completed
负责人 / 复核人：
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
跨端 / Excalidraw / 协作 / 隐私影响：
文档更新：
回滚方式：
完成证据链接：
```

本文件定义任务；实际 issue/MR 初始化为 `planned`，只有直接依赖的完成证据可读取且通过复核后才可转为 `ready`。状态转换、负责人、复核人和证据链接是 Gate 的机器审计输入。

不得用“代码已写”“测试基本通过”“后续优化”作为完成证据。任务执行中若实际范围超过量级边界，先更新本任务表和依赖，再继续编码。

## 17. 二轮复审缺口关闭映射

| 复审风险 | 关闭任务与约束 |
| --- | --- |
| 局部 correction 过早引用候选，且没有最终重跑 | V3-104B/V3-205C 只产受影响集合；V3-504E 承担 planner→patch→render→gate→score 重跑和全量等价验证 |
| source coverage 多本账、状态含糊 | V3-102A 创建唯一 `SourceCoverageLedger`；V3-204B/V3-400A/V3-500C/V3-504A～B 只透传并校验，忽略必须有用户批准来源 |
| 数据授权、供应方策略、同意和真实服务链缺失 | V3-001A～C、V3-201C～E、V3-203C～D、V3-505E 分别封住采集、服务、repository 和 UI；Gate 1 前已有真实 live-route |
| 迁移前快照晚于生产接入 | V3-304A 前置且 V3-303C 直接依赖它；V3-304B 同时依赖快照和接入实现 |
| 生成期按软排名误剪枝，保守候选/fallback 混淆，去重缺 placement 依赖 | V3-401D～E 只验证硬可行集；V3-401B/V3-403B 明确分型；V3-405A 依赖 V3-402E，结构配额只归 V3-401C |
| 未经真实门禁即可 commit | V3-501C 不导出 commit；V3-504D 封装 `ValidatedCandidate`；V3-502A 是唯一提交入口且直接依赖 V3-504D |
| UI 任务过大且 Gate 4 未接真实智能排版入口 | V3-505B/E/F/G 分拆同意、纠错、候选和真实入口；V3-506A 禁止用 fake provider 作为证据 |
| Gate 5 输入、导出 sanitizer、benchmark/spec 和任务状态不闭合 | V3-601B 依赖 V3-600C；V3-606A 直接依赖兼容/导出/CI 证据；V3-001B/V3-004A～C 冻结 benchmark/EvaluationSpec/hash；任务模板补状态与复核人 |
| 观测晚于切流、旧端点删除条件模糊 | V3-700D 在 V3-701A 前验收 instrumentation；V3-704A～B 以不可变消费者 census/hash 阻断不安全删除 |

本轮未加入临时纵向切片或可丢弃实现。第一批仍只执行 Gate 0 数据、基线和质量协议；新增任务均对应缺失的生产职责或验收闭环。

## 18. Agent Execution Manifest

本任务书的 153 项叶子任务已实例化为 [Agent Execution Manifest](smart-layout-v3-agent/agent-execution-manifest.json)，执行说明见 [smart-layout-v3-agent/README.md](smart-layout-v3-agent/README.md)。Manifest 记录每项任务的 `agent / human / environment / mixed` 分类、允许路径、精确符号或产物键、测试命令、预期退出码、证据路径、独立复审、单任务提交和失败回退点。

统一可执行入口为 `scripts/smart-layout-v3/AgentExecution.ps1`。它从本文件解析任务并校验源文件 SHA-256；任务表发生任何变化后必须重新运行 `-Action Generate`，禁止直接手改生成的 Manifest。`Sync` 会在依赖未完成时保持 `planned`，在外部输入缺失或无效时自动置为 `blocked`，只有依赖和输入均满足时才转为 `ready`。

Gate 0～5 和 FINAL 已改为 Manifest 中的可执行 Gate：正式执行时先验证覆盖任务全部完成、提交与证据匹配、修改路径没有越界，再运行对应 Flutter/Go 命令。任何缺失证据、伪造外部输入、非预期退出码、自审或一个提交复用给多任务均不能转为 `completed`。
