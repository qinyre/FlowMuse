# 智能排版 v3 Agent Execution Manifest

本目录把 69 张实施任务卡转换为 GLM-5.3 Max 可机械执行的状态机。当前 64 项完成状态和 G0～G5 结果原样保留；剩余 5 项已收缩为比赛演示交付，减少外部等待、重复证据和子代理调用，但不降低智能排版效果目标或自动化质量门禁。人工阅读仍以上位架构和任务书为准；实际领取与完成任务时，以 `agent-execution-manifest.json` 和 `AgentExecution.ps1` 的校验结果为准。

## 文件职责

- `agent-execution-manifest.json`：生成产物，包含 69 项任务的执行者类型、依赖、允许路径、精确符号或产物键、命令、退出码、证据路径、提交规则、复审模式和失败回退点。
- `agent-execution-state.json`：运行状态。只由执行工具修改，不作为某张业务任务的实现内容提交；交付审计时再统一固化快照。
- `scripts/smart-layout-v3/AgentExecution.ps1`：唯一规则入口，负责生成、验证、同步、领取、阻断、复审、完成和 Gate 执行。

Manifest 由任务书生成，不能手改。任务书改变后必须重新执行 `Generate`，源码 SHA-256 不一致会使 `Validate` 失败。

当前执行分两条连续工程线：`ai_synthetic_development` 已覆盖核心实现、AI 代理评测、可用平台验证和默认关闭的 v3 入口；`competition_delivery` 从 V3-700A 开始，只完成演示环境 smoke、合成故障注入、v2 隔离证明和最终交付包。剩余任务全部由 agent 执行，不需要外部输入或生产环境。

## GLM-5.3 Max 持续执行循环

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Generate
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Preflight
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Sync
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Next -Actor agent
```

`Next` 返回依赖已满足的 `agent` 任务。没有可执行任务时，它返回结构化的依赖或实现阻断清单。

已经存在完成状态时只能使用普通 `Generate`；禁止使用 `-ForceState`，否则会抹掉任务状态。当前重排必须保留已有的 64 个 completed/commit 和 G0～G5 gate run；生成器发现被删除 ID 仍处于 `completed/in_progress/review_pending` 时会拒绝迁移，而不是静默丢状态。

领取任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Start -TaskId V3-000A -Actor agent
```

执行者必须保存 `Start` 返回的 `executor_run_id`，严格限制在任务的 `allowed_paths` 和 `target_symbols` 内实施，并逐条执行 `commands`。每条命令的文本、开始/结束时间和退出码都写入该任务的 `commands.json`。

若实现、依赖契约或环境失败：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Block -TaskId V3-000A -Reason "可复现的阻断原因"
```

不得用 `Block` 掩盖普通测试失败；普通实现/测试失败按 Manifest 的 `failure_return_to` 返回当前任务继续修复。

## AI 代理评测

`validation_mode=ai_surrogate_panel` 的任务由两个全新、上下文隔离的 GLM-5.3 Max 子代理盲审，第三个独立代理只处理分歧；实现代理不得兼任评审或仲裁。证据必须保存盲化输入、全部 run id、原始结论、一致性统计和仲裁记录，并写明：

```json
{
  "panel_type": "ai_surrogate",
  "human_validation_performed": false,
  "disclosure": "HUMAN_VALIDATION_NOT_PERFORMED"
}
```

AI persona 结果只能作为开发裁判，不得描述为产品签字、原作者研究、第三方真人偏好或真实用户耗时。

## 比赛交付边界

V3-700A～V3-705A 不再声明生产发布，也不读取外部技术输入。Agent 只需要在当前仓库和可用环境内完成：

1. 本地/演示环境端到端 smoke。
2. 固定样本的合成故障注入与稳定性报告。
3. 客户端公开入口和服务端路由的 v2/v3 隔离证明。
4. 比赛演示 runbook、测试索引和最终技术审计。

v2 客户端代码和服务端旧端点原位保留；不得为了“清理完成”扩大迁移或删除范围。不可用平台继续沿用 V3-605A 已记录的 `release_deferred`，不阻断比赛交付。

## 完成证据

`result.json` 最小格式：

```json
{
  "task_id": "V3-000A",
  "run_id": "Start 返回的 executor_run_id",
  "summary": "实际完成结果",
  "changed_paths": ["docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json"],
  "artifacts": [
    {
      "key": "v3_000a_deliverable",
      "path": "docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json",
      "sha256": "文件的 SHA-256 小写值"
    }
  ]
}
```

代码任务没有 `artifact_keys` 时，`artifacts` 可为空数组；报告、数据、Gate 等任务必须逐一提供 Manifest 指定的产物键、真实路径和匹配的 SHA-256。

`commands.json` 最小格式：

```json
{
  "task_id": "V3-000A",
  "runs": [
    {
      "command_id": "artifact-contract",
      "command": "必须与 Manifest 完全一致；报告类任务会实际校验产物存在、非空、路径和 SHA-256",
      "exit_code": 0,
      "started_at_utc": "2026-08-31T00:00:00Z",
      "finished_at_utc": "2026-08-31T00:00:01Z"
    }
  ]
}
```

工具会拒绝缺少命令、命令文本不一致或退出码不在 `expected_exit_codes` 中的证据。

## 风险分级复审与一个任务一个提交

Manifest 的 `review.mode` 有三种：

- `automated`：以 focused commands、产物 hash、allowlist 和专用提交验收，不调用子代理，也不需要 `review.json`。
- `independent`：仅保留在已经完成的高风险协议、算法 oracle、事务、真实入口和阶段终点任务中。V3-700A～V3-705A 不使用此模式。
- `panel_evidence`：效果评测任务自身包含两个隔离盲审代理和条件仲裁；这些 run id 写入任务产物，不再额外调用一个独立复审代理，也不需要通用 `review.json`。

`independent` 任务的 `review.json` 格式：

```json
{
  "task_id": "V3-000A",
  "run_id": "独立复审运行 ID",
  "executor_run_id": "实现运行 ID",
  "model": "glm-5.3",
  "reasoning_effort": "max",
  "verdict": "approved",
  "findings": []
}
```

复审运行 ID 与实现运行 ID 相同会被拒绝。`rejected` 自动退回本任务；修复后应 amend 同一任务提交，不能新增第二个任务提交或把多个任务合并到一个提交。对 `automated` 或 `panel_evidence` 调用 `Review` 会直接返回 `not_required`，不会制造伪复审。

完成前，提交标题必须包含任务 ID，提交中每个路径都必须命中该任务 `allowed_paths`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Review -TaskId <independent-task-id>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Complete -TaskId V3-000A -Commit <commit-sha>
```

`Complete` 校验实际 Git commit、路径、证据、命令和该任务要求的复审模式，并生成运行态 `commit.json` 回执。状态文件和该回执是编排器的后提交记录，不得顺手混入下一张任务提交。

仍维持一个执行任务一个最终 commit，但后续只有 56 个任务，不再为同一上层工作包拆出多次提交。任务内修复、测试和复审驳回应 amend 到该任务提交。

## 临时脚本与证据节流

- 会长期复用的 generator、validator、runner 必须放进任务 `allowed_paths`，由正式测试覆盖并随任务提交。
- `%TEMP%` 或其他临时目录中的 Python/PowerShell 只允许只读分析或抛弃式数据转换，禁止直接批量修改仓库源码；任务完成后清理。
- 每项只维护 Manifest 指定的一套 `result.json`、`commands.json` 和条件式 `review.json`；不得生成 `result2.json`、`result3.json` 或为每轮自检复制整份证据。
- 同一组无状态检查在任务完成前运行一次并记录最终结果；失败时保留必要诊断，不为相同成功重复消耗 token。

## 可执行 Gate

每个 Gate 的 `invoke_command` 已写入 Manifest。默认会先复验其覆盖的所有任务与提交，再真正执行 Gate 命令；任一前置任务未完成、证据不完整、路径越界或命令退出码异常都会非零退出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId G0
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId G5
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId FINAL
```

`-CheckOnly` 只复验任务证据，不运行 Flutter/Go Gate 命令，不能作为正式 Gate 通过证据。正式结果写入 `docs/研发记录/evidence/smart-layout-v3/gates/<GateId>/gate-result.json`。

G0～G5 是 development Gate；V3-700A～V3-705A 完成并通过 FINAL 后可声明 `competition_delivery_complete`。已有 AI/synthetic 与 release-deferred 边界保留，不追加生产认证。

## 强制执行约束

1. 不直接编辑 Manifest 或 State 绕过工具。
2. 不创建生产或真人证据占位文件；比赛任务只使用仓库内可复验的自动化证据。
3. 不修改 allowlist 外路径；确需扩边时先修改任务书并重新生成 Manifest。
4. `independent` 任务不得跳过 `Review` 或复用实现 run；`automated`/`panel_evidence` 不得为形式完整额外派通用复审代理。
5. 不把失败命令记录为成功，不接受缺失证据的文字说明。
6. 一个任务只对应一个最终 commit；一个 commit 不能登记给两个任务。
7. Gate 失败按 `failure_return_to` 回到指定任务；修复后只执行该任务声明的复审模式，再重跑 Gate。
