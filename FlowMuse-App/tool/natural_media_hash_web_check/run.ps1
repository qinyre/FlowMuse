# tool/natural_media_hash_web_check/run.ps1
# §3.3 种子跨端门禁（Windows）：dart2js 编译 + node 实跑冻结向量。
# 用法：在 FlowMuse-App 目录下执行  powershell -File tool/natural_media_hash_web_check/run.ps1
# 退出码 0 = 通过。产物写入 build/natural_media_hash_web_check/。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # FlowMuse-App
$outDir = Join-Path $root 'build/natural_media_hash_web_check'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir 'nm_hash_check.js'

Write-Host '[1/2] dart compile js ...'
dart compile js -o $out (Join-Path $PSScriptRoot 'main.dart')
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host '[2/2] node run (V8) ...'
node $out
if ($LASTEXITCODE -ne 0) {
  Write-Host 'FAILED: frozen seed vectors drifted on dart2js/V8'
  exit 1
}
exit 0
