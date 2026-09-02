# V3-705A：比赛交付最终技术审计（CompetitionDeliveryAudit）
#
# 机器可复核的交付审计，四部分：
#   1) 69 张任务卡：状态 / 证据路径（result+commands）/ 提交 SHA 可索引；
#   2) G0～G5 门禁结果存在且 passed；FINAL 复验命令入报告（705A 完成
#      后运行，本审计不冒充其通过）；
#   3) 演示 runbook 命令与 competition/ 证据一一对应；
#   4) 已知边界披露 + 回滚说明 + 不宣称生产发布。
#
# 输出：docs/研发记录/evidence/smart-layout-v3/competition/
#       v3-705a-delivery-audit.json（UTF-8 BOM）。
param(
    [string]$RepoRoot = "",
    [string]$SelfTaskId = "V3-705A"
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $RepoRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
}

function Read-RepoJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "missing file: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$manifest = Read-RepoJson (Join-Path $RepoRoot 'docs/研发记录/plans/smart-layout-v3-agent/agent-execution-manifest.json')
$state = Read-RepoJson (Join-Path $RepoRoot 'docs/研发记录/plans/smart-layout-v3-agent/agent-execution-state.json')
$stateById = @{}
foreach ($item in $state.tasks) { $stateById[$item.id] = $item }

# ---- 1) 任务卡索引 ----
$cards = @()
$cardIssues = @()
foreach ($task in $manifest.tasks) {
    $taskState = $stateById[$task.id]
    $evidenceRoot = Join-Path $RepoRoot $task.evidence.root
    $resultExists = Test-Path -LiteralPath (Join-Path $RepoRoot $task.evidence.result)
    $commandsExists = Test-Path -LiteralPath (Join-Path $RepoRoot $task.evidence.commands)
    $isSelf = $task.id -eq $SelfTaskId
    $completed = $taskState.status -eq 'completed'
    if (-not $isSelf -and -not $completed) {
        $cardIssues += "$($task.id) 状态 $($taskState.status)（非审计自身卡，应为 completed）"
    }
    if ($completed -and -not $resultExists) { $cardIssues += "$($task.id) 缺 result.json" }
    if ($completed -and -not $commandsExists) { $cardIssues += "$($task.id) 缺 commands.json" }
    $cards += [ordered]@{
        id = $task.id
        phase = $task.phase
        title = $task.title
        status = $taskState.status
        commit = $taskState.commit
        evidence_root = $task.evidence.root
        result_exists = $resultExists
        commands_exists = $commandsExists
        is_audit_self = $isSelf
    }
}

# ---- 2) 门禁 ----
$gateIds = @('G0','G1','G2','G3','G4','G5')
$gates = @()
$gateIssues = @()
foreach ($gateId in $gateIds) {
    $gatePath = Join-Path $RepoRoot "docs/研发记录/evidence/smart-layout-v3/gates/$gateId/gate-result.json"
    if (-not (Test-Path -LiteralPath $gatePath)) {
        $gateIssues += "$gateId 缺 gate-result.json"
        $gates += [ordered]@{ id = $gateId; status = 'missing' }
        continue
    }
    $result = Read-RepoJson $gatePath
    $passed = $result.status -eq 'passed'
    if (-not $passed) { $gateIssues += "$gateId status=$($result.status)" }
    $gates += [ordered]@{ id = $gateId; status = $result.status; path = "docs/研发记录/evidence/smart-layout-v3/gates/$gateId/gate-result.json" }
}

# ---- 3) 演示 runbook 与 competition 证据 ----
$runbook = @(
    [ordered]@{ step = 'demo-smoke-client'; cwd = 'FlowMuse-App'; command = 'flutter test test/features/whiteboard/smart_layout/rollout'; evidence = 'docs/研发记录/evidence/smart-layout-v3/competition/v3-700a-demo-smoke.json' },
    [ordered]@{ step = 'demo-smoke-server'; cwd = 'FlowMuse-Server'; command = 'go test ./internal/recognition/...'; evidence = 'docs/研发记录/evidence/smart-layout-v3/competition/v3-700a-server-smoke.json' },
    [ordered]@{ step = 'stability-matrix'; cwd = 'FlowMuse-App'; command = 'flutter test test/features/whiteboard/smart_layout/rollout/synthetic_stability_evaluator_test.dart'; evidence = 'docs/研发记录/evidence/smart-layout-v3/competition/v3-702a-stability-report.json' },
    [ordered]@{ step = 'client-isolation'; cwd = 'FlowMuse-App'; command = 'flutter test test/features/whiteboard/smart_layout/v2_client_isolation_matrix_test.dart'; evidence = 'docs/研发记录/evidence/smart-layout-v3/competition/v3-703a-client-isolation.json' },
    [ordered]@{ step = 'route-isolation'; cwd = 'FlowMuse-Server'; command = 'go test ./internal/recognition/ -run RouteIsolation'; evidence = 'docs/研发记录/evidence/smart-layout-v3/competition/v3-704a-route-isolation.json' }
)
$runbookIssues = @()
foreach ($entry in $runbook) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $entry.evidence))) {
        $runbookIssues += "runbook $($entry.step) 缺证据 $($entry.evidence)"
    }
}

# ---- 4) 已知边界 / 回滚 / 生产声明 ----
$knownLimits = @(
    'v3_flow_policy 为 v3 放置语义确定性代表策略，非生产全管线复刻（dev 线限制，606A 披露）',
    'HUMAN_VALIDATION_NOT_PERFORMED：冻结实验未做人工验收（606A 预注册披露）',
    'PRODUCTION_RELEASE_NOT_AUTHORIZED：比赛交付口径，不宣称生产发布完成',
    '平台矩阵：android/web 实构建 built；windows/ohos/ios/macos 比赛版按 release_deferred 记录（605A）',
    '客户端 v2 私有实现原位保留（9 lib+8 测试），不删除不迁移不加兼容 wrapper（703A）',
    '服务端旧端点（6 条路由）仅为比赛版本兼容保留，不做 census、不返 410、不删除（704A）',
    '可观测性为进程内合成指标（LocalSyntheticMetricsSink，零网络）；生产端点不在比赛交付范围（700B）'
)
$rollback = [ordered]@{
    policy = 'SmartLayoutRollbackPolicy（V3-701A）：切流提交 allowlist 机器判定；回滚完整性=残余 diff 为空（恰为逆集）；关闭重开四条检查单'
    kill_switch = 'SmartLayoutKillSwitch 只关不换：类型面无 v2 回退 API；跳闸后入口 disabled（零请求零 Draft）'
    observability_closure = '失败率滑动窗口告警 → onAlert 关闭 kill switch → 重开 disabled（700A 场景 4 可重放）'
}

$audit = [ordered]@{
    task = 'V3-705A'
    kind = 'CompetitionDeliveryAudit'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    task_cards = [ordered]@{
        total = $cards.Count
        completed = @($cards | Where-Object { $_.status -eq 'completed' }).Count
        in_progress_self = @($cards | Where-Object { $_.is_audit_self -and $_.status -ne 'completed' }).Count
        index = $cards
        issues = $cardIssues
    }
    gates = [ordered]@{
        G0_to_G5 = $gates
        issues = $gateIssues
        final_gate = [ordered]@{
            status = 'pending_after_this_task'
            reverify_command = 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId FINAL（需 go 在 PATH）'
        }
    }
    demo_runbook = [ordered]@{ steps = $runbook; issues = $runbookIssues }
    known_limits = $knownLimits
    rollback = $rollback
    production_release_claimed = $false
    all_checks_passed = ($cardIssues.Count -eq 0 -and $gateIssues.Count -eq 0 -and $runbookIssues.Count -eq 0)
}

$outDir = Join-Path $RepoRoot 'docs/研发记录/evidence/smart-layout-v3/competition'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir 'v3-705a-delivery-audit.json'
$json = $audit | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "delivery audit written: $outPath"
Write-Host "cards: $($audit.task_cards.completed)/$($audit.task_cards.total) completed (self in-progress: $($audit.task_cards.in_progress_self)); gates G0-G5 issues: $($gateIssues.Count); runbook issues: $($runbookIssues.Count); all_checks_passed: $($audit.all_checks_passed)"
if (-not $audit.all_checks_passed) { exit 1 }
