[CmdletBinding()]
param(
    [ValidateSet('Generate', 'Validate', 'Preflight', 'VerifyArtifacts', 'Sync', 'Next', 'Show', 'Start', 'Block', 'Review', 'Complete', 'Gate')]
    [string]$Action = 'Validate',
    [string]$TaskId,
    [string]$GateId,
    [string]$Reason,
    [string]$Commit,
    [ValidateSet('agent', 'human', 'environment')]
    [string]$Actor = 'agent',
    [switch]$ForceState,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
# Git 以 UTF-8 输出非 ASCII 路径（需 core.quotepath=off）；强制以 UTF-8 解码原生命令输出，
# 避免 GBK 控制台把中文路径解码成乱码导致 allowlist/提交校验失败。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:PlanPath = Join-Path $script:RepoRoot 'docs\研发记录\plans\2026-08-31-smart-layout-v3-execution-backlog.md'
$script:ExecutionRoot = Join-Path $script:RepoRoot 'docs\研发记录\plans\smart-layout-v3-agent'
$script:ManifestPath = Join-Path $script:ExecutionRoot 'agent-execution-manifest.json'
$script:StatePath = Join-Path $script:ExecutionRoot 'agent-execution-state.json'
$script:EvidenceRoot = 'docs/研发记录/evidence/smart-layout-v3'
$script:ExecutorModel = 'glm-5.3'
$script:ReasoningEffort = 'max'
$script:ExpectedTaskCount = 69

function Write-JsonFile([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing required file: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
}

function To-RepoPath([string]$Path) { return ($Path -replace '\\', '/').TrimStart('./') }
function Resolve-RepoPath([string]$Path) { return Join-Path $script:RepoRoot ($Path -replace '/', '\') }

function New-Command([string]$Id, [string]$Cwd, [string]$Command) {
    return [ordered]@{ id = $Id; cwd = $Cwd; command = $Command; expected_exit_codes = @(0); required = $true }
}

function New-Profile([string]$Domain, [string[]]$Paths, [string[]]$Symbols, [string[]]$Artifacts, [string]$TestPath = '') {
    return [ordered]@{
        domain = $Domain
        allowed_paths = @($Paths)
        target_symbols = @($Symbols)
        artifact_keys = @($Artifacts)
        focused_test_path = $TestPath
    }
}

function Get-TaskProfile([string]$ParentId, [string]$Id = '') {
    $appRoot = 'FlowMuse-App/lib/features/whiteboard/smart_layout'
    $testRoot = 'FlowMuse-App/test/features/whiteboard/smart_layout'
    $serverRoot = 'FlowMuse-Server/internal/recognition'
    if ($Id -eq 'V3-700A') {
        return New-Profile ops @("$appRoot/rollout/**","$testRoot/rollout/**","$serverRoot/smart_layout_v3*.go",'docs/研发记录/evidence/smart-layout-v3/competition/**') @('SmartLayoutDemoSmoke','SmartLayoutCapability','SmartLayoutKillSwitch') @('demo_smoke_report','synthetic_observability_report')
    }
    switch ($ParentId) {
        'V3-000' { return New-Profile evidence @('docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json') @() @('failure_taxonomy','rubric_anchor_set','adjudication_rules') }
        'V3-001' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/**','docs/研发记录/specs/smart-layout-v3/fixture-manifest.schema.json') @('FixtureManifest','SmartLayoutFixtureRunner','DeterministicExecutionEnvironment') @('fixture_manifest_schema','benchmark_environment_hash','runner_report') }
        'V3-002' { return New-Profile evidence @('docs/研发记录/evidence/smart-layout-v3/datasets/**','FlowMuse-App/tool/smart_layout_v3/dataset/**') @('DatasetAdmissionValidator','AnnotationAgreementCalculator') @('dataset_manifest','authorization_record','annotation_report') }
        'V3-003' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/baseline/**','docs/研发记录/evidence/smart-layout-v3/baseline/**') @('SmartLayoutBaselineRunner','HumanBaselineComparator') @('v2_baseline','human_baseline','failure_cluster_report') }
        'V3-004' { return New-Profile evidence @('docs/研发记录/specs/smart-layout-v3/evaluation-spec.json','docs/研发记录/evidence/smart-layout-v3/gates/G0/**') @('EvaluationSpec','GateZeroEvaluator') @('evaluation_spec','gate_zero_report','gate_zero_signoff') }
        'V3-100' { return New-Profile app @("$appRoot/gateways/**","$testRoot/gateways/**",'FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart','FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart') @('SmartLayoutEditorGateway','SmartLayoutHttpGateway','SmartLayoutPublicEntry') @() 'test/features/whiteboard/smart_layout/gateways' }
        'V3-101' { return New-Profile app @("$appRoot/snapshot/**","$testRoot/snapshot/**") @('SceneRevision','SceneFingerprint','StableElementIdentity') @() 'test/features/whiteboard/smart_layout/snapshot' }
        'V3-102' { return New-Profile app @("$appRoot/snapshot/**","$testRoot/snapshot/**") @('LayoutPageSnapshot','SourceCoverageLedger','SnapshotExtractor') @() 'test/features/whiteboard/smart_layout/snapshot' }
        'V3-103' { return New-Profile app @("$appRoot/segmentation/**","$testRoot/segmentation/**") @('InkRegionSegmenter','RegionSegment','SegmentationPolicy') @() 'test/features/whiteboard/smart_layout/segmentation' }
        'V3-104' { return New-Profile app @("$appRoot/correction/**","$testRoot/correction/**") @('RegionCorrectionPatch','AffectedSourceSet','CorrectionPatchApplier') @() 'test/features/whiteboard/smart_layout/correction' }
        'V3-105' { return New-Profile app @("$appRoot/assets/**","$testRoot/assets/**") @('SmartLayoutRenderAssets','SmartLayoutAssetBuilder','AssetFingerprint') @() 'test/features/whiteboard/smart_layout/assets' }
        'V3-106' { return New-Profile app @("$appRoot/session/**","$testRoot/session/**") @('SmartLayoutSessionState','SmartLayoutOperationGuard','SmartLayoutSessionReducer') @() 'test/features/whiteboard/smart_layout/session' }
        'V3-200' { return New-Profile cross @("$appRoot/protocol/**","$testRoot/protocol/**","$serverRoot/smart_layout_v3_types.go","$serverRoot/smart_layout_v3_types_test.go",'docs/研发记录/specs/smart-layout-v3/protocol/**') @('SmartLayoutV3Request','SmartLayoutV3Response','SmartLayoutV3Error') @('protocol_schema','compatibility_matrix') 'test/features/whiteboard/smart_layout/protocol' }
        'V3-201' { return New-Profile server @("$serverRoot/smart_layout_v3.go","$serverRoot/smart_layout_v3_test.go","$serverRoot/api.go") @('V3Analyzer','RegisterSmartLayoutV3','V3RequestLimits') @() }
        'V3-202' { return New-Profile server @("$serverRoot/smart_layout_v3_overview.go","$serverRoot/smart_layout_v3_crop.go","$serverRoot/smart_layout_v3_analysis_test.go") @('V3OverviewAnalyzer','V3CropAnalyzer','V3AnalysisMerger') @() }
        'V3-203' { return New-Profile app @("$appRoot/analysis/**","$testRoot/analysis/**") @('V3AnalysisRepository','AnalysisOperationGuard','AnalysisRetryPolicy') @() 'test/features/whiteboard/smart_layout/analysis' }
        'V3-204' { return New-Profile app @("$appRoot/semantics/**","$testRoot/semantics/**") @('SemanticDocument','SemanticDocumentAssembler','SemanticReadingOrder') @() 'test/features/whiteboard/smart_layout/semantics' }
        'V3-205' { return New-Profile app @("$appRoot/correction/**","$testRoot/correction/**") @('SemanticCorrectionPatch','SemanticPatchValidator','SemanticRerunScope') @() 'test/features/whiteboard/smart_layout/correction' }
        'V3-206' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/evaluation/**','docs/研发记录/evidence/smart-layout-v3/gates/G1/**') @('RecognitionQualityEvaluator','RecognitionLatencyEvaluator') @('recognition_quality_report','recognition_latency_report','gate_one_report') }
        'V3-300' { return New-Profile app @("$appRoot/design/**","$testRoot/design/**") @('SmartLayoutDesignTokens','TextMeasureAdapter','TextMeasureResult') @() 'test/features/whiteboard/smart_layout/design' }
        'V3-301' { return New-Profile app @("$appRoot/geometry/**","$testRoot/geometry/**") @('SmartLayoutGeometryKernel','LayoutRect','LayoutInsets') @() 'test/features/whiteboard/smart_layout/geometry' }
        'V3-302' { return New-Profile app @("$appRoot/geometry/**","$testRoot/geometry/**") @('SmartLayoutTransformContract','AffineLayoutTransform','TransformInvariant') @() 'test/features/whiteboard/smart_layout/geometry' }
        'V3-303' { return New-Profile app @("$appRoot/geometry/**","$testRoot/geometry/**") @('SmartLayoutSceneTransformer','StrokeTransformAdapter','TextTransformAdapter') @() 'test/features/whiteboard/smart_layout/geometry' }
        'V3-304' { return New-Profile evidence @("$testRoot/compatibility/**",'docs/研发记录/evidence/smart-layout-v3/compatibility/**') @('GeometryCompatibilityFixture','ConditionalAdapterAllowlist') @('geometry_compatibility_report','adapter_allowlist') }
        'V3-305' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/transform/**','docs/研发记录/evidence/smart-layout-v3/gates/G2/**') @('TransformInvariantRunner') @('transform_invariant_report','gate_two_report') }
        'V3-400' { return New-Profile app @("$appRoot/composition/**","$testRoot/composition/**") @('LayoutBlock','LayoutBlockAssembler','BlockRelationship') @() 'test/features/whiteboard/smart_layout/composition' }
        'V3-401' { return New-Profile app @("$appRoot/composition/**","$testRoot/composition/**") @('LayoutCompositionPlanner','CompositionCandidate','CompositionConstraint') @() 'test/features/whiteboard/smart_layout/composition' }
        'V3-402' { return New-Profile app @("$appRoot/placement/**","$testRoot/placement/**") @('FlowPlacer','PlacementCursor','PlacedBlock') @() 'test/features/whiteboard/smart_layout/placement' }
        'V3-403' { return New-Profile app @("$appRoot/placement/**","$testRoot/placement/**") @('LayoutPreflight','NoFeasibleLayout','PreserveFallback') @() 'test/features/whiteboard/smart_layout/placement' }
        'V3-404' { return New-Profile app @("$appRoot/metrics/**","$testRoot/metrics/**") @('LayoutMetricContract','LayoutProfile','LayoutMetricCalculator') @() 'test/features/whiteboard/smart_layout/metrics' }
        'V3-405' { return New-Profile app @("$appRoot/metrics/**","$testRoot/metrics/**") @('LayoutStructureSignature','SceneMetricsContract','SemanticCoverageMetric') @() 'test/features/whiteboard/smart_layout/metrics' }
        'V3-406' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/planner/**','docs/研发记录/evidence/smart-layout-v3/gates/G3/**') @('PlannerQualityEvaluator') @('planner_quality_report','gate_three_report') }
        'V3-500' { return New-Profile app @("$appRoot/patch/**","$testRoot/patch/**") @('SmartLayoutScenePatch','SmartLayoutScenePatchBuilder','PatchInvariant') @() 'test/features/whiteboard/smart_layout/patch' }
        'V3-501' { return New-Profile app @("$appRoot/reducer/**","$testRoot/reducer/**") @('SmartLayoutSceneReducer','SmartLayoutPreviewAdapter','ReducedScene') @() 'test/features/whiteboard/smart_layout/reducer' }
        'V3-502' { return New-Profile app @("$appRoot/commit/**","$testRoot/commit/**",'FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart') @('ValidatedCandidateCommitGateway','SmartLayoutCommitTransaction','HistoryCommitResult') @() 'test/features/whiteboard/smart_layout/commit' }
        'V3-503' { return New-Profile app @("$appRoot/rendering/**","$testRoot/rendering/**") @('DraftSceneRenderer','DraftRenderLayer','DraftRenderSnapshot') @() 'test/features/whiteboard/smart_layout/rendering' }
        'V3-504' { return New-Profile app @("$appRoot/validation/**","$testRoot/validation/**") @('HardConstraintValidator','LayoutScorer','CorrectionRerunCoordinator') @() 'test/features/whiteboard/smart_layout/validation' }
        'V3-505' { return New-Profile app @("$appRoot/session/**","$appRoot/views/**","$testRoot/session/**","$testRoot/views/**",'FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart') @('SmartLayoutSessionViewModel','SmartLayoutSessionView','SmartLayoutCandidateView') @() 'test/features/whiteboard/smart_layout' }
        'V3-506' { return New-Profile evidence @("$testRoot/transaction/**",'docs/研发记录/evidence/smart-layout-v3/gates/G4/**') @('TransactionMatrixRunner') @('transaction_matrix','gate_four_report') }
        'V3-600' { return New-Profile evidence @("$testRoot/compatibility/**",'docs/研发记录/evidence/smart-layout-v3/compatibility/**') @('AdjacentFeatureCompatibilitySuite') @('adjacent_feature_report') }
        'V3-601' { return New-Profile app @("$appRoot/document/**","$testRoot/document/**",'FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_document.dart') @('SmartLayoutDocumentV3Mapper','SmartLayoutDocumentCompatibility') @() 'test/features/whiteboard/smart_layout/document' }
        'V3-602' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/ci/**','.github/workflows/smart-layout-v3*','docs/研发记录/evidence/smart-layout-v3/ci/**') @('SmartLayoutCiMatrix','DeterminismCiCheck') @('ci_matrix','determinism_report') }
        'V3-603' { return New-Profile evidence @('scripts/smart-layout-v3/**','docs/研发记录/evidence/smart-layout-v3/gates/G5/**') @('SmartLayoutGateRunner','ScopeAudit') @('scope_audit','gate_five_report') }
        'V3-604' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/performance/**','docs/研发记录/evidence/smart-layout-v3/performance/**') @('SmartLayoutPerformanceRunner') @('performance_report','memory_report') }
        'V3-605' { return New-Profile platform @('FlowMuse-App/tool/smart_layout_v3/platform/**','.github/workflows/smart-layout-v3-platform*','docs/研发记录/evidence/smart-layout-v3/platform/**') @('PlatformBuildMatrix','PlatformSmokeSuite') @('platform_build_report','platform_smoke_report') }
        'V3-606' { return New-Profile evidence @('FlowMuse-App/tool/smart_layout_v3/experiment/**','docs/研发记录/evidence/smart-layout-v3/experiments/**') @('FrozenExperimentRunner') @('author_study','third_party_study','frozen_experiment_report') }
        'V3-700' { return New-Profile ops @("$appRoot/rollout/**","$testRoot/rollout/**","$serverRoot/smart_layout_v3*.go",'docs/研发记录/evidence/smart-layout-v3/rollout/**') @('SmartLayoutCapability','SmartLayoutKillSwitch','SmartLayoutObservability') @('deployment_record','observability_readiness') }
        'V3-701' { return New-Profile app @("$appRoot/**","$testRoot/**",'FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart','FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart') @('SmartLayoutPublicEntry','SmartLayoutRollbackPolicy') @() 'test/features/whiteboard/smart_layout/rollout' }
        'V3-702' { return New-Profile ops @('docs/研发记录/evidence/smart-layout-v3/competition/**','FlowMuse-App/tool/smart_layout_v3/competition/**',"$testRoot/rollout/**") @('SyntheticStabilityEvaluator','SmartLayoutFaultInjectionMatrix') @('synthetic_stability_report','fault_injection_report') }
        'V3-703' { return New-Profile app @("$appRoot/**","$testRoot/**",'FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/**','FlowMuse-App/test/features/whiteboard/editor_core/smart_layout*','docs/研发记录/evidence/smart-layout-v3/competition/**') @('SmartLayoutPublicEntry','V2ClientIsolationMatrix') @('v2_client_isolation_report','v2_retention_note') 'test/features/whiteboard/smart_layout' }
        'V3-704' { return New-Profile cross @("$serverRoot/smart_layout.go","$serverRoot/smart_layout_test.go","$serverRoot/vision_layout.go","$serverRoot/vision_layout_test.go","$serverRoot/smart_layout_v3*.go",'docs/研发记录/evidence/smart-layout-v3/competition/**') @('SmartLayoutRouteIsolationMatrix','RegisterSmartLayoutV3') @('server_route_isolation_report','legacy_endpoint_retention_note') }
        'V3-705' { return New-Profile evidence @('docs/研发记录/**','scripts/smart-layout-v3/**') @('CompetitionDeliveryAudit') @('competition_delivery_audit','task_evidence_index','demo_runbook') }
        default { throw "No execution profile for parent task $ParentId" }
    }
}

function Get-ExecutorType([string]$Id) {
    return 'agent'
}

function Get-ValidationMode([string]$Id) {
    if ($Id -match '^V3-(000B|002C|003B|004[AC]|606A)$') { return 'ai_surrogate_panel' }
    if ($Id -eq 'V3-605A') { return 'ai_synthetic_with_release_deferred' }
    return 'automated'
}

function Get-ExecutionLane([string]$Id) {
    if ($Id -match '^V3-(700A|702A|703A|704A|705A)$') { return 'competition_delivery' }
    return 'ai_synthetic_development'
}

function Get-ReviewMode([string]$Id) {
    # Phase 0 is already complete; retain its original independent-review contract and evidence.
    if ($Id -match '^V3-0') { return 'independent' }
    if ($Id -eq 'V3-606A') { return 'panel_evidence' }
    $independent = @(
        'V3-200A','V3-203A','V3-206A',
        'V3-303A','V3-305A',
        'V3-401B','V3-404A','V3-406A',
        'V3-500B','V3-501A','V3-502A','V3-504A','V3-506A',
        'V3-600A',
        'V3-700B','V3-701A'
    )
    if ($Id -in $independent) { return 'independent' }
    return 'automated'
}

function Get-Commands($Profile, [string]$Id) {
    $commands = @()
    switch ($Profile.domain) {
        'app' {
            $commands += New-Command 'focused-flutter-test' 'FlowMuse-App' "flutter test $($Profile.focused_test_path)"
            $commands += New-Command 'flutter-analyze-smart-layout' 'FlowMuse-App' 'flutter analyze lib/features/whiteboard/smart_layout test/features/whiteboard/smart_layout'
        }
        'server' {
            $commands += New-Command 'focused-go-test' 'FlowMuse-Server' 'go test ./internal/recognition/...'
            $commands += New-Command 'go-vet' 'FlowMuse-Server' 'go vet ./...'
        }
        'cross' {
            $commands += New-Command 'focused-flutter-test' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout'
            $commands += New-Command 'focused-go-test' 'FlowMuse-Server' 'go test ./internal/recognition/...'
        }
        'platform' {
            $commands += New-Command 'flutter-test' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout'
            $commands += New-Command 'platform-build-matrix' '.' "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/Run-PlatformMatrix.ps1 -TaskId $Id"
        }
        'ops' {
            $commands += New-Command 'rollout-contract-tests' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout/rollout'
            $commands += New-Command 'server-contract-tests' 'FlowMuse-Server' 'go test ./internal/recognition/...'
        }
        default {
            $commands += New-Command 'artifact-contract' '.' "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action VerifyArtifacts -TaskId $Id"
        }
    }
    return @($commands)
}

function Get-Gates {
    return @(
        [ordered]@{ id='G0'; title='质量协议冻结'; phases=@(0); terminal_task='V3-004C'; commands=@(New-Command 'validate-manifest' '.' 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Validate') },
        [ordered]@{ id='G1'; title='识别与语义质量'; phases=@(0,1,2); terminal_task='V3-206A'; commands=@(New-Command 'flutter-smart-layout-tests' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout'; New-Command 'go-recognition-tests' 'FlowMuse-Server' 'go test ./internal/recognition/...') },
        [ordered]@{ id='G2'; title='几何与变换正确性'; phases=@(0,1,2,3); terminal_task='V3-305A'; commands=@(New-Command 'flutter-smart-layout-tests' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout') },
        [ordered]@{ id='G3'; title='组合与规划质量'; phases=@(0,1,2,3,4); terminal_task='V3-406A'; commands=@(New-Command 'flutter-smart-layout-tests' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout') },
        [ordered]@{ id='G4'; title='Patch 事务与交互'; phases=@(0,1,2,3,4,5); terminal_task='V3-506A'; commands=@(New-Command 'flutter-smart-layout-tests' 'FlowMuse-App' 'flutter test test/features/whiteboard/smart_layout'; New-Command 'flutter-analyze' 'FlowMuse-App' 'flutter analyze') },
        [ordered]@{ id='G5'; title='开发候选、性能与合成实验'; phases=@(0,1,2,3,4,5,6); terminal_task='V3-606A'; commands=@(New-Command 'flutter-all-tests' 'FlowMuse-App' 'flutter test'; New-Command 'flutter-analyze' 'FlowMuse-App' 'flutter analyze'; New-Command 'go-all-tests' 'FlowMuse-Server' 'go test ./...'; New-Command 'go-vet' 'FlowMuse-Server' 'go vet ./...') },
        [ordered]@{ id='FINAL'; title='比赛演示与交付'; phases=@(0,1,2,3,4,5,6,7); terminal_task='V3-705A'; commands=@(New-Command 'flutter-all-tests' 'FlowMuse-App' 'flutter test'; New-Command 'flutter-analyze' 'FlowMuse-App' 'flutter analyze'; New-Command 'go-all-tests' 'FlowMuse-Server' 'go test ./...'; New-Command 'go-vet' 'FlowMuse-Server' 'go vet ./...') }
    )
}

function Generate-Manifest {
    if (-not (Test-Path -LiteralPath $script:PlanPath)) { throw "Backlog not found: $script:PlanPath" }
    $rows = @()
    foreach ($line in Get-Content -LiteralPath $script:PlanPath -Encoding utf8) {
        if ($line -match '^\| (V3-\d{3}[A-Z]) (.+?) \| ([SML]) \| (.+?) \| (.+?) \| (.+?) \|$') {
            $id = $Matches[1]; $title = $Matches[2].Trim(); $size = $Matches[3]
            $dependencyText = $Matches[4].Trim(); $deliverable = $Matches[5].Trim(); $acceptance = $Matches[6].Trim()
            $parentId = $id.Substring(0, 6)
            $profile = Get-TaskProfile $parentId $id
            $reviewMode = Get-ReviewMode $id
            $dependencies = @([regex]::Matches($dependencyText, 'V3-\d{3}[A-Z]') | ForEach-Object { $_.Value } | Select-Object -Unique)
            $evidenceDir = "$script:EvidenceRoot/tasks/$id"
            $allowed = @($profile.allowed_paths) + @("$evidenceDir/**")
            $taskArtifactKeys = if (@($profile.artifact_keys).Count -gt 0) { @(($id.ToLowerInvariant() -replace '-', '_') + '_deliverable') } else { @() }
            $rows += [ordered]@{
                id = $id
                parent_id = $parentId
                phase = [int]$id.Substring(3,1)
                title = $title
                size = $size
                executor_type = Get-ExecutorType $id
                execution_lane = Get-ExecutionLane $id
                validation_mode = Get-ValidationMode $id
                dependencies = @($dependencies)
                objective = $deliverable
                deliverable = $deliverable
                acceptance = $acceptance
                allowed_paths = @($allowed | Select-Object -Unique)
                target_symbols = @($profile.target_symbols)
                artifact_keys = @($taskArtifactKeys)
                artifact_categories = @($profile.artifact_keys)
                commands = @(Get-Commands $profile $id)
                required_inputs = @()
                block_if_missing_inputs = $false
                evidence = [ordered]@{
                    root = $evidenceDir
                    result = "$evidenceDir/result.json"
                    commands = "$evidenceDir/commands.json"
                    review = "$evidenceDir/review.json"
                    commit = "$evidenceDir/commit.json"
                    gate_artifacts = "$evidenceDir/artifacts/**"
                }
                commit = [ordered]@{
                    required = $true
                    one_task_only = $true
                    subject_must_contain = $id
                    changed_paths_must_match_allowed_paths = $true
                }
                review = [ordered]@{
                    mode = $reviewMode
                    required = ($reviewMode -eq 'independent')
                    independent = ($reviewMode -eq 'independent')
                    model = $script:ExecutorModel
                    reasoning_effort = $script:ReasoningEffort
                    reviewer_run_must_differ_from_executor_run = ($reviewMode -eq 'independent')
                }
                failure_return_to = [ordered]@{
                    implementation_or_test_failure = $id
                    dependency_contract_failure = @($dependencies)
                    review_rejection = $id
                    gate_failure = $id
                }
            }
        }
    }
    if ($rows.Count -ne $script:ExpectedTaskCount) { throw "Expected $script:ExpectedTaskCount task rows, parsed $($rows.Count). Refusing to generate." }
    $sourceHash = (Get-FileHash -LiteralPath $script:PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        schema_version = '2.0.0'
        project = 'FlowMuse smart-layout v3 architecture refactor'
        branch = 'feature/smart-layout-v3-refactor'
        source = [ordered]@{ path = To-RepoPath $script:PlanPath.Substring($script:RepoRoot.Length); sha256 = $sourceHash }
        generated_at_utc = [DateTime]::UtcNow.ToString('o')
        task_count = $rows.Count
        status_values = @('planned','ready','in_progress','blocked','review_pending','completed')
        execution_policy = [ordered]@{
            executor_model = $script:ExecutorModel
            executor_reasoning_effort = $script:ReasoningEffort
            independent_reviewer_model = $script:ExecutorModel
            independent_reviewer_reasoning_effort = $script:ReasoningEffort
            review_modes = [ordered]@{
                automated = 'commands, artifact hashes, path allowlist, and dedicated commit; no subagent review'
                independent = 'one fresh reviewer run for high-risk protocol, algorithm, transaction, integration, retirement, or phase-terminal work'
                panel_evidence = 'task-owned blind panel evidence; no additional generic reviewer run'
            }
            preflight_command = 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Preflight'
            harness_required_capabilities = @('filesystem_read_write','apply_patch','shell','git','long_running_continuation')
            one_task_one_commit = $true
            guessing_or_fabricating_evidence = 'forbidden'
            secrets_in_evidence = 'forbidden'
            development_lane = 'ai_synthetic_development'
            competition_lane = 'competition_delivery'
            ai_surrogate_panel = [ordered]@{
                reviewers = 2
                blind_and_context_isolated = $true
                disagreement_arbiter = 1
                human_validation_performed = $false
                required_disclosure = 'HUMAN_VALIDATION_NOT_PERFORMED'
            }
            competition_scope = 'demo_and_technical_validation_only'
            temporary_script_policy = [ordered]@{
                repository_source_edits_from_temp_scripts = 'forbidden'
                temp_scripts_allowed_for = @('read_only_analysis','throwaway_data_transformation')
                persistent_generators_and_validators_must_be_committed = $true
                duplicate_result_files = 'forbidden'
            }
        }
        scope = [ordered]@{
            core_roots = @('FlowMuse-App/lib/features/whiteboard/smart_layout/**','FlowMuse-App/test/features/whiteboard/smart_layout/**','FlowMuse-Server/internal/recognition/smart_layout_v3*','docs/研发记录/**','scripts/smart-layout-v3/**')
            compatibility_only = @('FlowMuse-App/lib/features/whiteboard/editor_core/**','FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart')
            excluded_production_roots = @('FlowMuse-App/lib/features/whiteboard/ai_assistant/**','FlowMuse-App/lib/features/whiteboard/collaboration/**','FlowMuse-App/lib/features/whiteboard/editor_core/src/tools/select_tool.dart','FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/mindmap/**')
        }
        evidence_contract = [ordered]@{
            result_required_fields = @('task_id','run_id','summary','changed_paths','artifacts')
            command_run_required_fields = @('command_id','command','exit_code','started_at_utc','finished_at_utc')
            review_required_only_when_mode = 'independent'
            review_required_fields = @('task_id','run_id','executor_run_id','model','reasoning_effort','verdict','findings')
            allowed_review_verdicts = @('approved','rejected')
        }
        gates = @(Get-Gates | ForEach-Object {
            $_.invoke_command = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId $($_.id)"
            $_.failure_return_to = $_.terminal_task
            $_
        })
        tasks = @($rows)
    }
    Write-JsonFile $script:ManifestPath $manifest

    if ($ForceState -or -not (Test-Path -LiteralPath $script:StatePath)) {
        $states = @()
        foreach ($task in $rows) {
            $states += [ordered]@{
                id = $task.id
                status = 'planned'
                blocked_reasons = @()
                executor_run_id = $null
                commit = $null
                review_status = if ($task.review.required) { 'pending' } else { 'not_required' }
                updated_at_utc = [DateTime]::UtcNow.ToString('o')
            }
        }
        Write-JsonFile $script:StatePath ([ordered]@{
            schema_version = '2.0.0'
            manifest_sha256 = (Get-FileHash -LiteralPath $script:ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
            generated_at_utc = [DateTime]::UtcNow.ToString('o')
            tasks = @($states)
            gate_runs = @()
        })
    } else {
        $existingState = Read-JsonFile $script:StatePath
        $newIds = @($rows | ForEach-Object id)
        $unsafeRemoved = @($existingState.tasks | Where-Object { $_.id -notin $newIds -and $_.status -in @('completed','in_progress','review_pending') })
        if ($unsafeRemoved.Count -gt 0) {
            throw "State migration refused: removed task IDs still carry protected status: $($unsafeRemoved.id -join ', '). Restore or explicitly resolve them before Generate."
        }
        $existingById = @{}; foreach ($item in $existingState.tasks) { $existingById[$item.id] = $item }
        $migratedStates = @()
        foreach ($task in $rows) {
            $old = $existingById[$task.id]
            if ($old -and $old.status -eq 'completed') {
                $migratedStates += $old
                continue
            }
            if ($old -and $old.status -in @('in_progress','review_pending')) {
                throw "State migration refused: $($task.id) is $($old.status). Complete or block it before Generate."
            }
            $manualReasons = if ($old) { @($old.blocked_reasons | Where-Object code -eq 'manual') } else { @() }
            $migratedStates += [ordered]@{
                id = $task.id
                status = if ($manualReasons.Count -gt 0) { 'blocked' } else { 'planned' }
                blocked_reasons = @($manualReasons)
                executor_run_id = $null
                commit = $null
                review_status = if ($task.review.required) { 'pending' } else { 'not_required' }
                updated_at_utc = [DateTime]::UtcNow.ToString('o')
            }
        }
        $existingState.schema_version = '2.0.0'
        $existingState.tasks = @($migratedStates)
        $existingState.generated_at_utc = [DateTime]::UtcNow.ToString('o')
        Save-State $existingState
    }
    Write-Host "Generated $($rows.Count) tasks: $script:ManifestPath"
}

function Get-ManifestAndState {
    $manifest = Read-JsonFile $script:ManifestPath
    $state = Read-JsonFile $script:StatePath
    return @($manifest, $state)
}

function Test-AllowedPath([string]$Path, [string[]]$Patterns) {
    $candidate = To-RepoPath $Path
    foreach ($pattern in $Patterns) {
        $wildcard = (To-RepoPath $pattern) -replace '\*\*', '*'
        if ($candidate -like $wildcard) { return $true }
    }
    return $false
}

function Validate-Manifest([string]$OnlyTaskId = '') {
    $manifest, $state = Get-ManifestAndState
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($manifest.task_count -ne $script:ExpectedTaskCount -or @($manifest.tasks).Count -ne $script:ExpectedTaskCount) { $errors.Add("Manifest must contain exactly $script:ExpectedTaskCount tasks.") }
    $currentSourceHash = (Get-FileHash -LiteralPath $script:PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifest.source.sha256 -ne $currentSourceHash) { $errors.Add('Backlog hash differs from the generated manifest; regenerate before execution.') }
    $currentManifestHash = (Get-FileHash -LiteralPath $script:ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($state.manifest_sha256 -ne $currentManifestHash) { $errors.Add('State belongs to a different manifest; regenerate or synchronize state.') }
    $ids = @($manifest.tasks | ForEach-Object { $_.id })
    if (@($ids | Select-Object -Unique).Count -ne $script:ExpectedTaskCount) { $errors.Add('Task IDs are not unique.') }
    if (@($state.tasks).Count -ne $script:ExpectedTaskCount) { $errors.Add("State must contain exactly $script:ExpectedTaskCount tasks.") }
    $stateIds = @($state.tasks | ForEach-Object id)
    if (@($stateIds | Select-Object -Unique).Count -ne $script:ExpectedTaskCount -or @($stateIds | Where-Object { $_ -notin $ids }).Count -gt 0) { $errors.Add('State task IDs must exactly match Manifest task IDs.') }
    foreach ($task in $manifest.tasks) {
        if ($OnlyTaskId -and $task.id -ne $OnlyTaskId) { continue }
        if ($task.executor_type -notin @('agent','human','environment','mixed')) { $errors.Add("$($task.id): invalid executor_type") }
        if ($task.review.mode -notin @('automated','independent','panel_evidence')) { $errors.Add("$($task.id): invalid review.mode") }
        if ([bool]$task.review.required -ne ($task.review.mode -eq 'independent')) { $errors.Add("$($task.id): review.required must be true only for independent mode") }
        if ($task.review.mode -eq 'panel_evidence' -and $task.validation_mode -ne 'ai_surrogate_panel') { $errors.Add("$($task.id): panel_evidence requires ai_surrogate_panel validation") }
        if ($task.validation_mode -eq 'ai_surrogate_panel' -and $task.executor_type -ne 'agent') { $errors.Add("$($task.id): AI surrogate panel tasks must be agent tasks") }
        if (@($task.required_inputs).Count -gt 0) { $errors.Add("$($task.id): competition plan must not depend on external input files") }
        if (@($task.allowed_paths).Count -eq 0) { $errors.Add("$($task.id): allowed_paths is empty") }
        if (@($task.target_symbols).Count -eq 0 -and @($task.artifact_keys).Count -eq 0) { $errors.Add("$($task.id): target_symbols and artifact_keys are both empty") }
        if (@($task.commands).Count -eq 0) { $errors.Add("$($task.id): commands is empty") }
        foreach ($command in $task.commands) {
            if (-not $command.command -or @($command.expected_exit_codes).Count -eq 0) { $errors.Add("$($task.id): command $($command.id) is incomplete") }
        }
        foreach ($dependency in $task.dependencies) {
            if ($dependency -notin $ids) { $errors.Add("$($task.id): missing dependency $dependency") }
        }
    }
    $remaining = [System.Collections.Generic.HashSet[string]]::new([string[]]$ids)
    $resolved = [System.Collections.Generic.HashSet[string]]::new()
    while ($remaining.Count -gt 0) {
        $ready = @($manifest.tasks | Where-Object { $remaining.Contains($_.id) -and @($_.dependencies | Where-Object { -not $resolved.Contains($_) }).Count -eq 0 })
        if ($ready.Count -eq 0) { $errors.Add("Dependency cycle detected among: $([string]::Join(',', $remaining))"); break }
        foreach ($task in $ready) { [void]$remaining.Remove($task.id); [void]$resolved.Add($task.id) }
    }
    if (@($manifest.gates).Count -ne 7) { $errors.Add('Expected gates G0-G5 and FINAL.') }
    if ($errors.Count -gt 0) { throw "Manifest validation failed:`n - $($errors -join "`n - ")" }
    $reviewCounts = @($manifest.tasks | Group-Object { $_.review.mode } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    Write-Host "Manifest valid: $script:ExpectedTaskCount tasks, 7 gates, no missing dependencies or cycles; review modes: $reviewCounts."
}

function Invoke-AgentPreflight {
    Validate-Manifest
    $checks = @()
    foreach ($name in @('powershell','git','flutter','go')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        $checks += [ordered]@{ command=$name; required_at_start=($name -in @('powershell','git')); available=[bool]$command; path=if ($command) { $command.Source } else { $null } }
    }
    $missing = @($checks | Where-Object { $_.required_at_start -and -not $_.available })
    $report = [ordered]@{
        model = $script:ExecutorModel
        reasoning_effort = $script:ReasoningEffort
        required_harness_capabilities = @('filesystem_read_write','apply_patch','shell','git','long_running_continuation')
        cli_checks = @($checks)
        status = if ($missing.Count -eq 0) { 'passed' } else { 'blocked' }
        checked_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-JsonFile (Resolve-RepoPath "$script:EvidenceRoot/agent-preflight.json") $report
    if ($missing.Count -gt 0) { throw "Agent preflight blocked; missing startup commands: $($missing.command -join ', ')" }
    Write-Host "$script:ExecutorModel $script:ReasoningEffort preflight passed."
}

function Save-State($State) {
    $State.manifest_sha256 = (Get-FileHash -LiteralPath $script:ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-JsonFile $script:StatePath $State
}

function Sync-State {
    $manifest, $state = Get-ManifestAndState
    $stateById = @{}; foreach ($item in $state.tasks) { $stateById[$item.id] = $item }
    foreach ($task in $manifest.tasks) {
        $current = $stateById[$task.id]
        if ($current.status -in @('in_progress','review_pending','completed')) { continue }
        $unfinished = @($task.dependencies | Where-Object { $stateById[$_].status -ne 'completed' })
        $manualReasons = @($current.blocked_reasons | Where-Object { $_.code -eq 'manual' })
        if ($manualReasons.Count -gt 0) {
            $current.status = 'blocked'; $current.blocked_reasons = @($manualReasons)
        } elseif ($unfinished.Count -gt 0) {
            $current.status = 'planned'
            $current.blocked_reasons = @([ordered]@{ code='dependencies_incomplete'; details=@($unfinished) })
        } else {
            $current.status = 'ready'; $current.blocked_reasons = @()
        }
        $current.updated_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    Save-State $state
    return @($manifest, $state)
}

function Get-TaskPair([string]$Id) {
    if (-not $Id) { throw 'TaskId is required.' }
    $manifest, $state = Get-ManifestAndState
    $task = $manifest.tasks | Where-Object id -eq $Id
    $taskState = $state.tasks | Where-Object id -eq $Id
    if (-not $task -or -not $taskState) { throw "Unknown task: $Id" }
    return @($manifest, $state, $task, $taskState)
}

function Show-Next([string]$ActorType) {
    $manifest, $state = Sync-State
    $stateById = @{}; foreach ($item in $state.tasks) { $stateById[$item.id] = $item }
    $eligibleTypes = if ($ActorType -eq 'agent') { @('agent','mixed') } elseif ($ActorType -eq 'human') { @('human','mixed') } else { @('environment','mixed') }
    $next = $manifest.tasks | Where-Object { $stateById[$_.id].status -eq 'ready' -and $_.executor_type -in $eligibleTypes } | Select-Object -First 1
    if (-not $next) {
        $blocking = @($state.tasks | Where-Object status -eq 'blocked')
        [ordered]@{ status='no_agent_task_ready'; blocked_count=$blocking.Count; blocked=@($blocking | Select-Object id,blocked_reasons) } | ConvertTo-Json -Depth 10
        return
    }
    [ordered]@{ status='ready'; task=$next; state=$stateById[$next.id] } | ConvertTo-Json -Depth 20
}

function Start-Task([string]$Id, [string]$ActorType) {
    $null = Sync-State
    $manifest, $state, $task, $taskState = Get-TaskPair $Id
    $eligibleTypes = if ($ActorType -eq 'agent') { @('agent','mixed') } elseif ($ActorType -eq 'human') { @('human','mixed') } else { @('environment','mixed') }
    if ($task.executor_type -notin $eligibleTypes) { throw "$Id is assigned to $($task.executor_type), not $ActorType." }
    if ($taskState.status -ne 'ready') { throw "$Id is not ready; current status is $($taskState.status)." }
    $taskState.status = 'in_progress'; $taskState.executor_run_id = [guid]::NewGuid().ToString(); $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o')
    Save-State $state
    [ordered]@{ task_id=$Id; status='in_progress'; actor=$ActorType; executor_run_id=$taskState.executor_run_id; task=$task } | ConvertTo-Json -Depth 20
}

function Block-Task([string]$Id, [string]$Why) {
    if (-not $Why) { throw 'Reason is required for a manual block.' }
    $manifest, $state, $task, $taskState = Get-TaskPair $Id
    $taskState.status = 'blocked'; $taskState.blocked_reasons = @([ordered]@{ code='manual'; details=$Why }); $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o')
    Save-State $state
    Write-Host "$Id blocked: $Why"
}

function Read-TaskEvidence($Task) {
    $result = Read-JsonFile (Resolve-RepoPath $Task.evidence.result)
    $commands = Read-JsonFile (Resolve-RepoPath $Task.evidence.commands)
    $review = if ($Task.review.required) { Read-JsonFile (Resolve-RepoPath $Task.evidence.review) } else { $null }
    return @($result, $commands, $review)
}

function Validate-TaskEvidence($Task, $TaskState, [string]$CommitHash = '') {
    $errors = [System.Collections.Generic.List[string]]::new()
    try { $result, $commandEvidence, $review = Read-TaskEvidence $Task } catch { throw "$($Task.id): evidence missing or invalid JSON: $($_.Exception.Message)" }
    if ($result.task_id -ne $Task.id) { $errors.Add('result.task_id mismatch') }
    if (-not $result.run_id -or $result.run_id -ne $TaskState.executor_run_id) { $errors.Add('result.run_id must match the started executor run') }
    foreach ($field in @('summary','changed_paths','artifacts')) {
        if ($null -eq $result.$field) { $errors.Add("result.$field is required") }
    }
    foreach ($path in @($result.changed_paths)) {
        if (-not (Test-AllowedPath $path @($Task.allowed_paths))) { $errors.Add("changed path outside task allowlist: $path") }
    }
    if (@($result.changed_paths).Count -eq 0) { $errors.Add('result.changed_paths must contain at least one task-owned path') }
    foreach ($command in $Task.commands | Where-Object required) {
        $run = @($commandEvidence.runs | Where-Object command_id -eq $command.id) | Select-Object -Last 1
        if (-not $run) { $errors.Add("missing command evidence: $($command.id)"); continue }
        if ([int]$run.exit_code -notin @($command.expected_exit_codes | ForEach-Object { [int]$_ })) { $errors.Add("unexpected exit code for $($command.id): $($run.exit_code)") }
        if ($run.command -ne $command.command) { $errors.Add("command text mismatch for $($command.id)") }
        foreach ($field in @('started_at_utc','finished_at_utc')) { if (-not $run.$field) { $errors.Add("$($command.id).$field is required") } }
    }
    foreach ($key in @($Task.artifact_keys)) {
        $artifact = @($result.artifacts | Where-Object key -eq $key) | Select-Object -Last 1
        if (-not $artifact) { $errors.Add("missing required artifact key: $key"); continue }
        if (-not $artifact.path -or -not (Test-Path -LiteralPath (Resolve-RepoPath $artifact.path))) { $errors.Add("artifact path missing for key $key") }
        elseif (-not (Test-AllowedPath $artifact.path @($Task.allowed_paths))) { $errors.Add("artifact path outside task allowlist for key $key") }
        elseif (-not $artifact.sha256) { $errors.Add("artifact sha256 missing for key $key") }
        else {
            $actualHash = (Get-FileHash -LiteralPath (Resolve-RepoPath $artifact.path) -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $artifact.sha256.ToLowerInvariant()) { $errors.Add("artifact hash mismatch for key $key") }
        }
    }
    if ($Task.review.required) {
        if ($review.task_id -ne $Task.id -or $review.verdict -ne 'approved') { $errors.Add('independent review is not approved') }
        if ($review.model -ne $Task.review.model -or $review.reasoning_effort -ne $Task.review.reasoning_effort) { $errors.Add('review model or reasoning effort mismatch') }
        if (-not $review.run_id -or $review.run_id -eq $result.run_id -or $review.executor_run_id -ne $result.run_id) { $errors.Add('review must be from a different run and reference executor_run_id') }
    }
    if ($CommitHash) {
        $subject = (& git -C $script:RepoRoot show -s --format=%s $CommitHash 2>$null)
        if ($LASTEXITCODE -ne 0) { $errors.Add("commit does not resolve: $CommitHash") }
        elseif ($subject -notlike "*$($Task.id)*") { $errors.Add("commit subject must contain $($Task.id)") }
        $changed = @(& git -C $script:RepoRoot diff-tree --root --no-commit-id --name-only -r $CommitHash 2>$null)
        foreach ($path in $changed) { if (-not (Test-AllowedPath $path @($Task.allowed_paths))) { $errors.Add("commit changes path outside task allowlist: $path") } }
    }
    if ($errors.Count -gt 0) { throw "$($Task.id) evidence validation failed:`n - $($errors -join "`n - ")" }
    return @($result, $commandEvidence, $review)
}

function Verify-TaskArtifacts([string]$Id) {
    $manifest, $state, $task, $taskState = Get-TaskPair $Id
    $result = Read-JsonFile (Resolve-RepoPath $task.evidence.result)
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($result.task_id -ne $Id) { $errors.Add('result.task_id mismatch') }
    if (-not $result.run_id -or $result.run_id -ne $taskState.executor_run_id) { $errors.Add('result.run_id must match the started executor run') }
    foreach ($path in @($result.changed_paths)) {
        if (-not (Test-AllowedPath $path @($task.allowed_paths))) { $errors.Add("changed path outside task allowlist: $path") }
    }
    foreach ($key in @($task.artifact_keys)) {
        $artifact = @($result.artifacts | Where-Object key -eq $key) | Select-Object -Last 1
        if (-not $artifact) { $errors.Add("missing required artifact key: $key"); continue }
        $artifactPath = if ($artifact.path) { Resolve-RepoPath $artifact.path } else { '' }
        if (-not $artifactPath -or -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { $errors.Add("artifact file missing for key $key"); continue }
        if ((Get-Item -LiteralPath $artifactPath).Length -eq 0) { $errors.Add("artifact file is empty for key $key") }
        if (-not (Test-AllowedPath $artifact.path @($task.allowed_paths))) { $errors.Add("artifact path outside task allowlist for key $key") }
        if (-not $artifact.sha256) { $errors.Add("artifact sha256 missing for key $key") }
        else {
            $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $artifact.sha256.ToLowerInvariant()) { $errors.Add("artifact hash mismatch for key $key") }
        }
    }
    if ($errors.Count -gt 0) { throw "$Id artifact validation failed:`n - $($errors -join "`n - ")" }
    Write-Host "$Id artifact contract valid."
}

function Review-Task([string]$Id) {
    $manifest, $state, $task, $taskState = Get-TaskPair $Id
    if ($taskState.status -notin @('in_progress','review_pending')) { throw "$Id must be in_progress or review_pending before review." }
    if (-not $task.review.required) {
        $taskState.review_status = 'not_required'; $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o'); Save-State $state
        Write-Host "$Id review mode is $($task.review.mode); no generic subagent review is required."
        return
    }
    $resultPath = Resolve-RepoPath $task.evidence.result
    $reviewPath = Resolve-RepoPath $task.evidence.review
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "Missing executor result: $($task.evidence.result)" }
    if (-not (Test-Path -LiteralPath $reviewPath)) {
        $taskState.status = 'review_pending'; $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o'); Save-State $state
        throw "Independent review required at $($task.evidence.review). Use a fresh $script:ExecutorModel $script:ReasoningEffort run; do not self-approve."
    }
    $result = Read-JsonFile $resultPath; $review = Read-JsonFile $reviewPath
    if ($review.run_id -eq $result.run_id -or $review.executor_run_id -ne $result.run_id) { throw 'Reviewer run must be independent and reference the executor run.' }
    if ($review.model -ne $script:ExecutorModel -or $review.reasoning_effort -ne $script:ReasoningEffort) { throw "Review must use $script:ExecutorModel with $script:ReasoningEffort reasoning effort." }
    if ($review.verdict -eq 'rejected') {
        $taskState.status = 'in_progress'; $taskState.review_status = 'rejected'; $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o'); Save-State $state
        Write-Host "$Id review rejected; return to $Id."
        return
    }
    if ($review.verdict -ne 'approved') { throw "Invalid review verdict: $($review.verdict)" }
    $taskState.status = 'review_pending'; $taskState.review_status = 'approved'; $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o'); Save-State $state
    Write-Host "$Id independent review approved; completion still requires command evidence and one commit."
}

function Complete-Task([string]$Id, [string]$CommitHash) {
    if (-not $CommitHash) { throw 'Commit is required. Each task must have exactly one dedicated commit.' }
    $manifest, $state, $task, $taskState = Get-TaskPair $Id
    if ($taskState.status -notin @('in_progress','review_pending')) { throw "$Id must be in_progress or review_pending before completion." }
    $duplicate = @($state.tasks | Where-Object { $_.id -ne $Id -and $_.commit -eq $CommitHash })
    if ($duplicate.Count -gt 0) { throw "Commit $CommitHash is already assigned to $($duplicate[0].id)." }
    $null = Validate-TaskEvidence $task $taskState $CommitHash
    Write-JsonFile (Resolve-RepoPath $task.evidence.commit) ([ordered]@{
        task_id = $Id
        commit = $CommitHash
        subject = (& git -C $script:RepoRoot show -s --format=%s $CommitHash)
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
    })
    $taskState.status = 'completed'; $taskState.commit = $CommitHash; $taskState.review_status = if ($task.review.required) { 'approved' } else { 'not_required' }; $taskState.blocked_reasons = @(); $taskState.updated_at_utc = [DateTime]::UtcNow.ToString('o')
    Save-State $state
    Write-Host "$Id completed with dedicated commit $CommitHash."
}

function Invoke-ManifestCommand($Command) {
    $cwd = Resolve-RepoPath $Command.cwd
    if (-not (Test-Path -LiteralPath $cwd)) { return [ordered]@{ command_id=$Command.id; command=$Command.command; exit_code=127; error="cwd missing: $($Command.cwd)" } }
    Push-Location $cwd
    try {
        $global:LASTEXITCODE = 0
        & ([scriptblock]::Create($Command.command))
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        return [ordered]@{ command_id=$Command.id; command=$Command.command; exit_code=$exitCode; expected_exit_codes=@($Command.expected_exit_codes) }
    } catch {
        return [ordered]@{ command_id=$Command.id; command=$Command.command; exit_code=1; expected_exit_codes=@($Command.expected_exit_codes); error=$_.Exception.Message }
    } finally { Pop-Location }
}

function Invoke-Gate([string]$Id, [switch]$OnlyCheck) {
    if (-not $Id) { throw 'GateId is required.' }
    $manifest, $state = Get-ManifestAndState
    $gate = $manifest.gates | Where-Object id -eq $Id
    if (-not $gate) { throw "Unknown gate: $Id" }
    $stateById = @{}; foreach ($item in $state.tasks) { $stateById[$item.id] = $item }
    $requiredTasks = @($manifest.tasks | Where-Object { $_.phase -in @($gate.phases) })
    $incomplete = @($requiredTasks | Where-Object { $stateById[$_.id].status -ne 'completed' } | ForEach-Object id)
    if ($incomplete.Count -gt 0) { throw "$Id blocked: incomplete prerequisite tasks: $($incomplete -join ', ')" }
    foreach ($task in $requiredTasks) { $null = Validate-TaskEvidence $task $stateById[$task.id] $stateById[$task.id].commit }
    $runs = @()
    $failedCommand = $null
    if (-not $OnlyCheck) {
        foreach ($command in $gate.commands) {
            $run = Invoke-ManifestCommand $command; $runs += $run
            if ([int]$run.exit_code -notin @($command.expected_exit_codes | ForEach-Object { [int]$_ })) {
                $failedCommand = $run
                break
            }
        }
    }
    $gateDir = Resolve-RepoPath "$script:EvidenceRoot/gates/$Id"
    $gateStatus = if ($failedCommand) { 'failed' } elseif ($OnlyCheck) { 'checked' } else { 'passed' }
    $report = [ordered]@{ gate_id=$Id; status=$gateStatus; check_only=[bool]$OnlyCheck; terminal_task=$gate.terminal_task; failure_return_to=$gate.failure_return_to; verified_task_count=$requiredTasks.Count; failed_command=$failedCommand; runs=@($runs); finished_at_utc=[DateTime]::UtcNow.ToString('o') }
    $reportName = if ($OnlyCheck) { 'gate-check-result.json' } else { 'gate-result.json' }
    Write-JsonFile (Join-Path $gateDir $reportName) $report
    $state.gate_runs = @($state.gate_runs) + @($report)
    Save-State $state
    if ($failedCommand) { throw "$Id command $($failedCommand.command_id) failed with $($failedCommand.exit_code); return to $($gate.failure_return_to)." }
    if ($OnlyCheck) { Write-Host "$Id evidence check completed; this is not a formal Gate pass." }
    else { Write-Host "$Id passed; verified $($requiredTasks.Count) tasks." }
}

switch ($Action) {
    'Generate' { Generate-Manifest; Validate-Manifest }
    'Validate' { Validate-Manifest $TaskId }
    'Preflight' { Invoke-AgentPreflight }
    'VerifyArtifacts' { Verify-TaskArtifacts $TaskId }
    'Sync' { $null = Sync-State; Write-Host 'State synchronized.' }
    'Next' { Show-Next $Actor }
    'Show' { $manifest, $state, $task, $taskState = Get-TaskPair $TaskId; [ordered]@{ task=$task; state=$taskState } | ConvertTo-Json -Depth 20 }
    'Start' { Start-Task $TaskId $Actor }
    'Block' { Block-Task $TaskId $Reason }
    'Review' { Review-Task $TaskId }
    'Complete' { Complete-Task $TaskId $Commit }
    'Gate' { Invoke-Gate $GateId -OnlyCheck:$CheckOnly }
}
