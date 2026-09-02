# V3-605A：平台矩阵包装入口（Manifest command: platform-build-matrix）。
#
# 职责：跨端 smoke（flutter test，宿主无关）+ 六端构建矩阵
# （可用端实构建，不可用端 release_deferred 如实记录），聚合退出码。
# 产物报告写入 docs/研发记录/evidence/smart-layout-v3/platform/。
#
# 参数：
#   -TaskId            任务 id（当前 V3-605A；报告路径派生用）
#   -FlutterStorageBaseUrl  可选：覆盖 FLUTTER_STORAGE_BASE_URL（本机 CN
#                       镜像对 OHOS fork 引擎 jar 返回 403 时用主站；
#                       详见 evidence/platform/v3-605a-deliverable.json
#                       build_blocker_finding——CLI env 覆盖，零工程改动）。

[CmdletBinding()]
param(
    [string]$TaskId = 'V3-605A',
    [string]$FlutterStorageBaseUrl = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$appDir = Join-Path $repoRoot 'FlowMuse-App'
if ($FlutterStorageBaseUrl) {
    $env:FLUTTER_STORAGE_BASE_URL = $FlutterStorageBaseUrl
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host "[platform-matrix] $Name ..."
    & $Body
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[platform-matrix] $Name 失败（exit $LASTEXITCODE），聚合阻断" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Push-Location $appDir
try {
    Invoke-Step 'cross-platform smoke' {
        & cmd /c "flutter test tool/smart_layout_v3/platform 2>&1"
    }
    Invoke-Step 'platform build matrix' {
        & cmd /c "dart run tool/smart_layout_v3/platform/platform_build_matrix.dart --report ../docs/研发记录/evidence/smart-layout-v3/platform/v3-605a-report.json 2>&1"
    }
} finally {
    Pop-Location
}

Write-Host "[platform-matrix] 全部完成（smoke+矩阵）"
exit 0
