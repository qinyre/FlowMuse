# V3-603A：Go/Schema/Flutter 聚合门禁 runner（合并原 V3-603A~B）。
#
# 目标符号：SmartLayoutGateRunner、ScopeAudit。
# 用途：G5 前置聚合证据——双端（Go Server + Flutter App）独立全绿：
#   go-test / go-vet / schema-conformance-replay / legacy-endpoint-fixtures /
#   dart-format-nonregression / flutter-analyze / smart-layout-focused-tests /
#   golden-job / flutter-all-tests。
# 产出：gates/G5/aggregate-gate-report.json + scope-audit.json（命令逐字可复制）。
#
# 用法（仓库根）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/GateRunner.ps1
#   -ListJobs 只列 job 与 scope 审计（不执行）。
#   -FormatDriftBaseline 冻结基线（当前仓库智能排版作用域 format 漂移上限，
#   历史存量不改写——本门禁只拦新增漂移，与"不新增 analyzer error"同口径）。
#
# 环境要求：go 与 flutter 在 PATH（go 本机不在 PATH 时先 $env:PATH 前置）。

[CmdletBinding()]
param(
    [string]$ReportDir = 'docs/研发记录/evidence/smart-layout-v3/gates/G5',
    [int]$FormatDriftBaseline = 62,
    [switch]$ListJobs
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

class GateJob {
    [string]$Id
    [string]$Command          # 逐字可复制（展示/归档口径）
    [string]$Exe              # 实际执行（Start-Process 参数数组，引用安全）
    [string[]]$Args
    [string]$Cwd              # 仓库相对
    [string]$Scope            # 作用域说明（ScopeAudit 记录）
    [bool]$ReadOnly           # 是否只读（不写仓库文件）
    GateJob([string]$id, [string]$command, [string]$exe, [string[]]$argList,
            [string]$cwd, [string]$scope, [bool]$readOnly) {
        $this.Id = $id; $this.Command = $command; $this.Exe = $exe; $this.Args = $argList
        $this.Cwd = $cwd; $this.Scope = $scope; $this.ReadOnly = $readOnly
    }
}

class ScopeAudit {
    # 双端覆盖：至少一个 Go job 与一个 Flutter job；全部 job 带 scope 说明；
    # 潜在写仓命令必须声明只读形态（format --output=none / golden 不带 --update-goldens）。
    static [hashtable] Audit([GateJob[]]$jobs) {
        $findings = @()
        $goJobs = @($jobs | Where-Object { $_.Cwd -eq 'FlowMuse-Server' })
        $flutterJobs = @($jobs | Where-Object { $_.Cwd -eq 'FlowMuse-App' })
        if ($goJobs.Count -lt 1) { $findings += '缺 Go 端 job（双端门禁要求）' }
        if ($flutterJobs.Count -lt 1) { $findings += '缺 Flutter 端 job（双端门禁要求）' }
        foreach ($job in $jobs) {
            if ([string]::IsNullOrWhiteSpace($job.Scope)) {
                $findings += "job $($job.Id) 缺 scope 说明"
            }
            if ($job.Command -match '--update-goldens') {
                $findings += "job $($job.Id) 携带 --update-goldens（golden 校验必须只读）"
            }
            if ($job.Command -match 'dart format' -and $job.Command -notmatch '--output=none') {
                $findings += "job $($job.Id) dart format 未加 --output=none（必须只读检查）"
            }
        }
        return @{
            passed  = ($findings.Count -eq 0)
            findings = $findings
            ends    = @{
                go     = $goJobs.Count
                flutter = $flutterJobs.Count
            }
            jobs    = @(
                for ($i = 0; $i -lt $jobs.Count; $i++) {
                    @{ id = $jobs[$i].Id; cwd = $jobs[$i].Cwd
                       scope = $jobs[$i].Scope; read_only = $jobs[$i].ReadOnly }
                }
            )
        }
    }
}

class SmartLayoutGateRunner {
    [int]$FormatDriftBaseline

    SmartLayoutGateRunner([int]$formatDriftBaseline) {
        $this.FormatDriftBaseline = $formatDriftBaseline
    }

    [GateJob[]] Jobs() {
        return @(
            [GateJob]::new('go-test', 'go test ./...',
                'go', @('test', './...'), 'FlowMuse-Server',
                'Go 全部包测试（含 smart-layout v3 analyzer/route 与旧端点）', $true)
            [GateJob]::new('go-vet', 'go vet ./...',
                'go', @('vet', './...'), 'FlowMuse-Server',
                'Go 静态检查全部包', $true)
            [GateJob]::new('schema-conformance-replay',
                "go test ./internal/recognition -run 'TestPositiveFixturesRoundTrip|TestNegativeFixturesRejectedWithSameCode|TestSmartLayoutV3ErrorEnvelope|TestParseRejectsMalformedJson' -count=1 -v",
                'go', @('test', './internal/recognition', '-run',
                    'TestPositiveFixturesRoundTrip|TestNegativeFixturesRejectedWithSameCode|TestSmartLayoutV3ErrorEnvelope|TestParseRejectsMalformedJson',
                    '-count=1', '-v'), 'FlowMuse-Server',
                'v3 协议 conformance fixtures 正/负全量重放（Go 与 Dart 同一 fixtures）', $true)
            [GateJob]::new('legacy-endpoint-fixtures',
                "go test ./internal/recognition -run 'TestDecideLayout' -count=1 -v",
                'go', @('test', './internal/recognition', '-run', 'TestDecideLayout', '-count=1', '-v'),
                'FlowMuse-Server',
                '旧端点（v2 decide-layout）fixture 保持绿', $true)
            [GateJob]::new('dart-format-nonregression',
                'dart format --output=none lib/features/whiteboard/smart_layout test/features/whiteboard/smart_layout tool/smart_layout_v3/ci',
                'dart', @('format', '--output=none',
                    'lib/features/whiteboard/smart_layout',
                    'test/features/whiteboard/smart_layout',
                    'tool/smart_layout_v3/ci'), 'FlowMuse-App',
                "智能排版作用域 format 漂移计数（冻结基线 $($this.FormatDriftBaseline)，只拦新增漂移；--output=none 只读）", $true)
            [GateJob]::new('flutter-analyze', 'flutter analyze',
                'flutter', @('analyze'), 'FlowMuse-App',
                'Flutter 全仓 analyze 零诊断（G4 基线，不新增 analyzer error）', $true)
            [GateJob]::new('smart-layout-focused-tests',
                'flutter test test/features/whiteboard/smart_layout',
                'flutter', @('test', 'test/features/whiteboard/smart_layout'), 'FlowMuse-App',
                '智能排版 focused 全目录测试', $true)
            [GateJob]::new('golden-job',
                'flutter test test/features/whiteboard/smart_layout/rendering/draft_scene_renderer_test.dart',
                'flutter', @('test', 'test/features/whiteboard/smart_layout/rendering/draft_scene_renderer_test.dart'),
                'FlowMuse-App',
                '真实渲染 golden 逐字节校验（只读，不带 --update-goldens）', $true)
            [GateJob]::new('flutter-all-tests', 'flutter test',
                'flutter', @('test'), 'FlowMuse-App',
                'Flutter 全仓测试（G5 口径）', $true)
        )
    }

    [object] InvokeJob([GateJob]$job) {
        $repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
        $cwd = Join-Path $repoRoot $job.Cwd
        Write-Host "[gate] $($job.Id) ..."
        $exe = $job.Exe
        if ($exe -in @('flutter', 'dart', 'go')) {
            # 环境显式覆盖优先；否则 PATH 解析（Windows 优先 .bat 形态）。
            $envOverride = if ($exe -eq 'flutter') { $env:FLUTTER_EXE }
                elseif ($exe -eq 'dart') { $env:DART_EXE } else { $env:GO_EXE }
            if ($envOverride) {
                $exe = $envOverride
            } else {
                $resolved = $null
                if ($env:OS -eq 'Windows_NT' -and $exe -ne 'go') {
                    $resolved = Get-Command "$exe.bat" -ErrorAction SilentlyContinue
                }
                if (-not $resolved) { $resolved = Get-Command $exe -ErrorAction SilentlyContinue }
                if ($resolved) { $exe = $resolved.Source }
            }
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tmpOut = [IO.Path]::GetTempFileName()
        $tmpErr = [IO.Path]::GetTempFileName()
        $exitCode = 1
        $output = ''
        Push-Location $cwd
        try {
            $proc = Start-Process -FilePath $exe -ArgumentList $job.Args `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $exitCode = $proc.ExitCode
            $output = [IO.File]::ReadAllText($tmpOut) + [IO.File]::ReadAllText($tmpErr)
        } finally {
            Pop-Location
            Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
        }
        $sw.Stop()

        if ($job.Id -eq 'dart-format-nonregression') {
            # 历史存量漂移不改写：只拦新增（计数超冻结基线才失败）。
            $changed = 0
            if ($output -match '\((\d+) changed\)') { $changed = [int]$Matches[1] }
            $passed = $changed -le $this.FormatDriftBaseline
            return @{
                id = $job.Id; command = $job.Command; cwd = $job.Cwd; scope = $job.Scope
                exit_code = if ($passed) { 0 } else { 1 }; duration_ms = $sw.ElapsedMilliseconds
                note = "format 漂移 $changed 个（基线 $($this.FormatDriftBaseline)，只拦新增）"
            }
        }
        if ($job.Id -eq 'flutter-analyze' -and $exitCode -eq 0 -and $output -notmatch 'No issues found') {
            $exitCode = 1  # analyze 必须零诊断（G4 基线）
        }
        $note = ''
        if ($exitCode -ne 0) {
            $tail = ($output -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -Last 12) -join ' | '
            $note = "失败尾部: $tail"
        }
        return @{
            id = $job.Id; command = $job.Command; cwd = $job.Cwd; scope = $job.Scope
            exit_code = $exitCode; duration_ms = $sw.ElapsedMilliseconds; note = $note
        }
    }

    [hashtable] Run([string]$reportDir) {
        $jobs = $this.Jobs()
        $audit = [ScopeAudit]::Audit($jobs)
        if (-not $audit.passed) {
            throw "ScopeAudit 未通过：$($audit.findings -join '；')"
        }
        $repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
        $flutterVersion = ''
        Push-Location (Join-Path $repoRoot 'FlowMuse-App')
        try {
            $raw = (& cmd /c "flutter --version 2>&1" | Select-Object -First 1) -join ''
            # 控制台码页可能把版本行的非 ASCII 分隔符弄乱：只保留 ASCII。
            $flutterVersion = -join ($raw.ToCharArray() | Where-Object { [int]$_ -lt 128 })
        } finally {
            Pop-Location
        }
        $goVersion = (& cmd /c "go version 2>&1" | Select-Object -First 1) -join ''
        $results = @()
        foreach ($job in $jobs) {
            $results += $this.InvokeJob($job)
            if ($results[-1].exit_code -ne 0) {
                Write-Host "[gate] $($job.Id) 失败，聚合门禁阻断（后续 job 不再执行）" -ForegroundColor Red
                break
            }
        }
        $aggregate = 0
        $failed = @($results | Where-Object { $_.exit_code -ne 0 })
        if ($failed.Count -gt 0) { $aggregate = [Math]::Max(1, $failed[0].exit_code) }
        $report = @{
            schema_version = 1
            gate = 'G5-aggregate'
            generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            environment = @{ flutter = "$flutterVersion"; go = "$goVersion" }
            all_passed = ($failed.Count -eq 0)
            aggregate_exit_code = $aggregate
            format_drift = @{ baseline = $this.FormatDriftBaseline }
            scope_audit = $audit
            jobs = $results
        }
        $dir = Join-Path $repoRoot $reportDir
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $dir 'aggregate-gate-report.json'), ($report | ConvertTo-Json -Depth 6), $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $dir 'scope-audit.json'), ($audit | ConvertTo-Json -Depth 6), $utf8NoBom)
        Write-Host "[gate] all_passed=$($report.all_passed) aggregate_exit_code=$aggregate；报告 $reportDir"
        return $report
    }
}

$runner = [SmartLayoutGateRunner]::new($FormatDriftBaseline)
if ($ListJobs) {
    $audit = [ScopeAudit]::Audit($runner.Jobs())
    $audit | ConvertTo-Json -Depth 6
    if (-not $audit.passed) { exit 1 }
    exit 0
}
$report = $runner.Run($ReportDir)
exit $report.aggregate_exit_code
