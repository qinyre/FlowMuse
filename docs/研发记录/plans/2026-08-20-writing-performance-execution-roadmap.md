# FlowMuse 书写与协作性能执行路线图

> 日期：2026-08-20  
> 状态：批准执行（三方终审无 findings）  
> 上位方案：`2026-08-19-writing-collaboration-performance-optimization.md`

## 1. 目标与原则

把已通过终审的总体方案拆成可独立开发、测试、提交和回滚的任务。先建立真实基线，再做本地分层和协作 live-ink；只有固定门禁触发时才做缓存、笔尖预测或可靠交付设计。

## 2. 计划集合

| 计划 | 文件 | 性质 | 启动条件 | 输出 |
| --- | --- | --- | --- | --- |
| P0 基线 | `2026-08-20-writing-performance-p0-baseline-execution.md` | 必做 | 无 | 旧路径真机基线、协作 CPU 基线、冻结门槛 |
| P1 本地湿墨 | `2026-08-20-writing-performance-p1-local-wet-ink-execution.md` | 必做 | P0 completed | Freedraw 分层和条件优化 |
| P3 协作湿墨 | `2026-08-20-writing-performance-p3-live-ink-v2-execution.md` | 必做 | 见叶子依赖矩阵 | 专用 live 通道、增量协议、远端湿墨 |
| P2 笔尖体验 | `2026-08-20-writing-performance-p2-tip-latency-conditional-execution.md` | 条件 | P1 后物理目标仍失败 | 即时尾段；必要时 Pen Kit stop/go |
| R1 可靠交付 | `2026-08-20-writing-collaboration-r1-reliability-adr-plan.md` | 独立条件项 | 产品批准独立立项 | ADR/POC/故障规格，不直接上线 ACK/outbox |

## 3. 依赖图

```text
P0-0 runner ─┬─→ P0-1 probe ─┬─→ P0-4 基线与冻结门槛 ─→ P1-0 → P1-1 → P1-2
P0-3 fixture ┘               │                                      ├─→ 条件 P1-3/G1/G2
P0-2 timing ─────────────────┤                                      └─→ 条件 P2
P0-3B 协作 CPU 基线 ─────────┘

P0-4 ─→ P3-0A 服务端事件、P3-0B 客户端开关/transport、P3-1 模型
P3-0A + P3-1 ─→ P3-4 安全边界
P1-1 + P3-0B + P3-1 ─→ P3-2 发送端
P3-0B + P3-1 ─→ P3-3A 接收调度
P1-2 + P3-1 + P3-3A ─→ P3-3B 远端画层
全部 P3 叶子 ─→ P3-5 故障与负载

R1 与性能主线无实现依赖，单独审批。
```

P3-0A、P3-0B、P3-1 可在 P0 完成后并行，P3-4 等 P3-0A/P3-1；P3-2 不得在 P1-1 前修改 `FreedrawTool`/Controller，P3-3B 不得在 P1-2 前接入 `EditorCanvas`。

## 4. 执行身份与叶子任务分配

以下身份来自仓库提交记录，是本计划的明确初始分配；项目负责人可在开工前以一次计划变更整体替换，但不得用 `TBD` 开工。每个任务的复核人必须不是作者。

| 身份 | 本计划职责 |
| --- | --- |
| `qinyre` | Flutter 性能、输入和渲染 |
| `Enchograph` | 协作协议、Flutter transport、Go hub |
| `Tiax` | 真机自动化、跨平台回归、负载测试 |
| `任逸青` | 研究记录、验收证据和文档复核 |
| `Hongyu Chen` | 密码边界、可靠性交付和安全复核 |

| 叶子任务 | 前置 | 估时 | 唯一负责人 | 非作者复核人 |
| --- | --- | ---: | --- | --- |
| P0-0 runner | 无 | 1d | Tiax | qinyre |
| P0-1 probe | P0-0 | 1d | qinyre | Tiax |
| P0-2 timing/report schema | P0-0 | 0.75d | qinyre | Tiax |
| P0-3 fixture | P0-0 | 0.75d | Tiax | qinyre |
| P0-3B 2/5 人协作 CPU 基线 | P0-0/P0-2/P0-3 | 1d | Enchograph | qinyre |
| P0-4 基线与冻结门槛 | P0-0/1/2/3/3B | 0.5d | Tiax | 任逸青 |
| P1-0 开关 | P0-4 | 0.25d | qinyre | Tiax |
| P1-1 活动状态 | P1-0 | 1d | qinyre | Tiax |
| P1-2 本地画层 | P1-1 | 1.5d | qinyre | Tiax |
| P1-3/G1/G2 条件优化判定或实现 | P1-2，同一 fixture/门槛 | 0.25～2d/项 | qinyre | Tiax |
| P1-4 Timer/日志 | P0-4 | 0.5d | Enchograph | qinyre |
| P3-0A 服务端事件 | P0-4 | 0.75d | Enchograph | Hongyu Chen |
| P3-0B 开关/transport/ready | P0-4 | 1d | Enchograph | qinyre |
| P3-1 模型/校验 | P0-4 | 0.75d | Enchograph | Hongyu Chen |
| P3-2 delta sender | P1-1/P3-0B/P3-1 | 1.25d | qinyre | Enchograph |
| P3-3A 接收调度 | P3-0B/P3-1 | 1d | Enchograph | qinyre |
| P3-3B remote store/painter | P1-2/P3-1/P3-3A | 1.5d | qinyre | Tiax |
| P3-4 安全边界 | P3-0A/P3-1 | 1d | Enchograph | Hongyu Chen |
| P3-5 故障/兼容/负载 | 全部 P3 叶子 | 1.5d | Tiax | Enchograph |
| P2-0/1/2 | P1 completed 且门禁触发 | 1.5～2.5d | qinyre | Tiax |
| P2-3 Pen Kit spike | P2-1/2 后仍触发 | ≤2d | Tiax | qinyre |
| R1-0/1 ADR | 独立立项 | 1～1.5d | Hongyu Chen | Enchograph |
| R1-2 POC | ADR 候选要求 | 0.5～2d | Enchograph | Hongyu Chen |
| R1-3/4/5 条件设计 | ADR 选择对应语义 | 1～2d | Hongyu Chen | 任逸青 |

## 5. 实现所有权边界

- `FreedrawTool`/`ActiveFreedrawView` 只拥有当前点列、唯一 `strokeId`、P0 probe 使用的本地 `strokeEpoch` 和活动生命周期；本地 epoch 不进入 wire。Tool 不保存网络窗口或背压状态。
- `LiveInkSender` 独占 `lastSentIndex`、pending、三周期窗口边界和背压；V2 第一版没有 wire sequence。P3-2 是唯一修改发送语义的任务。
- P1-2 独占本地画层接入；P3-3B 只接入远端画层，不重写本地 painter。
- 最终 `SCENE_UPDATE`、AES-GCM、Excalidraw、Presence 的现有格式和语义均不在 P1/P3 修改范围。
- R1 只做决策、试验和规格；ADR 批准前不新增生产 ACK、journal、outbox 或表。

## 6. 通用 PR 门禁

每个任务 PR 必须附：任务 ID、依赖证明、文件清单、自动化测试、正确工作目录下的 `flutter analyze/test` 或 `go test/vet`、性能原始结果、开关/回滚说明、六平台影响，以及协议/安全变更的非作者复核记录。

性能 PR 必须使用 P0 冻结的提交 SHA、runner、fixture、设备/刷新率分类、样本数和 P95 算法；不得回填或修改基线。条件任务未触发标记 `not_triggered`，不是 `completed`。

## 7. 推荐批次

| 批次 | 内容 | 可并行项 |
| --- | --- | --- |
| A | P0 runner/probe/fixture/timing | P0-1、P0-2、P0-3 在 P0-0 后并行 |
| B | P0 协作 CPU 基线与冻结报告 | P0-3B；报告模板可并行 |
| C | P1-0/1/2；P3-0A/0B/1/4 | Flutter 本地链与协议链并行，文件所有权不重叠 |
| D | P1 条件判定；P3-2/3A | P3-2 等待 P1-1；3A 不等待 P1 |
| E | P3-3B，随后 P3-5 | 负载/文档证据并行 |
| F | 仅门禁触发时执行 P2；R1 独立排期 | 不阻塞主线发布 |

## 8. 总体验收

- 五份子计划的文件、命令、依赖、责任人、回滚和 DoD 与本路线图一致；
- 所有真机结论来自真实帧，协作流水线 CPU 结论明确不冒充 UI 帧指标；
- P1/P3 没有重复状态源或跨阶段偷跑；
- P2/R1 未触发时不产生生产实现；
- 三位独立审查 Agent 对代码可行性、成熟方案一致性和执行门禁均返回“无 findings”后，状态才能改为 `批准执行`。

## 9. 当前执行约束（2026-08-20）

- 当前没有可用真机，所有真机 Profile、实际刷新率、高速录像和 stylus-to-photon 证据统一标记 `deferred_device`；不得用 Debug、桌面结果或合成数据冒充。
- runner、probe、报告器、功能实现、单元/Widget/内存 transport/Go 测试及静态检查继续执行。
- P1-3/G1/G2 和 P2 只能由真机数据触发；真机恢复前保持 `not_evaluated`，不做猜测性实现。
- P0/P1/P3 的代码任务按“自动化验证完成、真机证据延期”交付；未来补测只补证据和门禁结论，不重写基线。
- 每个叶子任务使用一个独立 Git 提交，提交标题包含任务 ID。
