# 智能排版 v3 Agent Execution Manifest

本目录把 153 张实施任务卡转换为 GLM-5.3 Max 可机械执行、可阻断、可复审的状态机。人工阅读仍以上位架构和任务书为准；实际领取与完成任务时，以 `agent-execution-manifest.json` 和 `AgentExecution.ps1` 的校验结果为准。

## 文件职责

- `agent-execution-manifest.json`：生成产物，包含 153 项任务的执行者类型、依赖、允许路径、精确符号或产物键、命令、退出码、外部输入、证据路径、提交规则、复审规则和失败回退点。
- `agent-execution-state.json`：运行状态。只由执行工具修改，不作为某张业务任务的实现内容提交；交付审计时再统一固化快照。
- `scripts/smart-layout-v3/AgentExecution.ps1`：唯一规则入口，负责生成、验证、同步、领取、阻断、复审、完成和 Gate 执行。

Manifest 由任务书生成，不能手改。任务书改变后必须重新执行 `Generate`，源码 SHA-256 不一致会使 `Validate` 失败。

## GLM-5.3 Max 持续执行循环

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Generate
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Preflight
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Sync
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Next -Actor agent
```

`Next` 只返回 `agent` 或已具备外部输入的 `mixed` 任务。没有可执行任务时，它返回结构化的阻断清单，不允许模型猜测输入或伪造通过。

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

## 外部输入与非 Agent 任务

`human`、`environment`、`mixed` 任务所需外部输入必须放在 Manifest 指定的 `required_inputs[].path`。每个输入文件至少是：

```json
{
  "status": "available",
  "provided_at_utc": "2026-08-31T00:00:00Z",
  "reference": "不含密钥和敏感正文的外部记录引用"
}
```

文件不存在、JSON 无效或字段不完整时，`Sync` 自动将任务标记为 `blocked`。输入文件只能保存批准或数据所在位置的引用，严禁写入密钥、token、真实页面正文、OCR 或 prompt。

人工和环境执行者分别使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Next -Actor human
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Start -TaskId V3-000B -Actor human
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Next -Actor environment
```

Agent 不得用 `-Actor human` 或 `-Actor environment` 代替真实外部参与者。

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

## 独立复审与一个任务一个提交

实现运行不得自审。必须新开一个独立的 `glm-5.3`、`max` 推理运行，读取任务、diff、命令证据和产物后写 `review.json`：

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

复审运行 ID 与实现运行 ID 相同会被拒绝。`rejected` 自动退回本任务；修复后应 amend 同一任务提交，不能新增第二个任务提交或把多个任务合并到一个提交。

完成前，提交标题必须包含任务 ID，提交中每个路径都必须命中该任务 `allowed_paths`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Review -TaskId V3-000A
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Complete -TaskId V3-000A -Commit <commit-sha>
```

`Complete` 校验实际 Git commit、路径、证据、命令和独立复审，并生成运行态 `commit.json` 回执。状态文件和该回执是编排器的后提交记录，不得顺手混入下一张任务提交。

## 可执行 Gate

每个 Gate 的 `invoke_command` 已写入 Manifest。默认会先复验其覆盖的所有任务与提交，再真正执行 Gate 命令；任一前置任务未完成、证据不完整、路径越界或命令退出码异常都会非零退出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId G0
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId G5
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId FINAL
```

`-CheckOnly` 只复验任务证据，不运行 Flutter/Go Gate 命令，不能作为正式 Gate 通过证据。正式结果写入 `docs/研发记录/evidence/smart-layout-v3/gates/<GateId>/gate-result.json`。

## 强制执行约束

1. 不直接编辑 Manifest 或 State 绕过工具。
2. 不创建外部输入占位文件冒充批准、数据或环境。
3. 不修改 allowlist 外路径；确需扩边时先修改任务书并重新生成 Manifest。
4. 不跳过 `Review`、不复用实现 run 作为 reviewer run。
5. 不把失败命令记录为成功，不接受缺失证据的文字说明。
6. 一个任务只对应一个最终 commit；一个 commit 不能登记给两个任务。
7. Gate 失败按 `failure_return_to` 回到指定任务，修复并独立复审后重跑。
