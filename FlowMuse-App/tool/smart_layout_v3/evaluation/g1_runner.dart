import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'g1_inputs.dart';
import 'recognition_latency_evaluator.dart';
import 'recognition_quality_evaluator.dart';

/// G1 评测入口（V3-206A；分割器依赖 Flutter，经 flutter test 执行）：
///   flutter test tool/smart_layout_v3/evaluation/g1_runner_cli_test.dart
///
/// 产出（全部机器判定，写 evidence/gates/G1/）：
/// - quality-development.json / quality-validation.json（分离 split）
/// - latency-development.json
/// - prerequisites.json（schema hash/管线 hash/live-route/split 隔离）
/// - gate-one-report.json（由 build_gate_one_report.py 确定性组装）
///
/// 任何前置缺失（schema/hash/live-route）→ prerequisites.blocked=true，
/// planner 保持 blocked（acceptance）。
/// 运行一次完整 G1 评测；返回 0（完成）或 2（前置缺失→planner blocked）。
Future<int> runG1Evaluation() async {
  final inputs = G1Inputs.load();
  final outDir = Directory('${G1Inputs.evidenceRoot}/gates/G1')
    ..createSync(recursive: true);

  // 1. 质量：development 与 validation 严格分离。
  final quality = RecognitionQualityEvaluator();
  final devReport = quality.evaluate(
    splitName: 'development',
    sampleIds: inputs.devSampleIds,
    samplesById: inputs.samplesById,
    labelsBySample: inputs.labelsBySample,
    idMappingBySample: inputs.idMappingBySample,
  );
  final validationReport = quality.evaluate(
    splitName: 'validation',
    sampleIds: inputs.validationSampleIds,
    samplesById: inputs.samplesById,
    labelsBySample: inputs.labelsBySample,
    idMappingBySample: inputs.idMappingBySample,
  );
  _writeJson(outDir, 'quality-development.json', devReport.toJson());
  _writeJson(outDir, 'quality-validation.json', validationReport.toJson());

  // 2. 延迟（development；确定性口径 warmup=1/repetitions=3/nearest_rank）。
  final latency = RecognitionLatencyEvaluator();
  final latencyReport = latency.measure(
    sampleIds: inputs.devSampleIds,
    samplesById: inputs.samplesById,
  );
  _writeJson(outDir, 'latency-development.json', latencyReport.toJson());

  // 3. 校准偏差：dev 与 validation 的 pair-F1 漂移（报告值，不判定——
  //    阈值未在 Phase 0 冻结，属 FINAL 级统计）。
  final calibrationDrift = (devReport.pairF1 - validationReport.pairF1).abs();

  // 4. 前置检查（schema hash / 管线 hash / live-route / frozen 隔离）。
  final prereq = await _prerequisites(inputs);
  prereq['calibration_drift_pair_f1'] = double.parse(
    calibrationDrift.toStringAsFixed(4),
  );
  _writeJson(outDir, 'prerequisites.json', prereq);

  final blocked = prereq['blocked'] as bool;
  stdout.writeln(
    blocked
        ? 'G1 前置缺失——planner 保持 blocked：${prereq['block_reasons']}'
        : 'G1 评测完成（dev=${devReport.evaluatedSamples} '
              'validation=${validationReport.evaluatedSamples}）；'
              '正式 gate 由 AgentExecution Gate -GateId G1 执行。',
  );
  return blocked ? 2 : 0;
}

Future<Map<String, Object?>> _prerequisites(G1Inputs inputs) async {
  final reasons = <String>[];
  final checks = <String, Object?>{};

  // 4a. schema hash：协议规范 sha256 与冻结登记一致。
  final protocolFile = File(
    '../docs/研发记录/specs/smart-layout-v3/protocol/protocol.md',
  );
  if (!protocolFile.existsSync()) {
    reasons.add('schema-missing(protocol.md)');
    checks['schema_hash'] = null;
  } else {
    final digest = crypto.sha256.convert(protocolFile.readAsBytesSync());
    checks['schema_hash'] = digest.toString();
    final taskResult = File(
      '${G1Inputs.evidenceRoot}/tasks/V3-200A/result.json',
    );
    if (taskResult.existsSync()) {
      final registered =
          (jsonDecode(taskResult.readAsStringSync())
                  as Map<String, Object?>)['artifacts']
              as List?;
      final pinned = registered?.isNotEmpty == true
          ? (registered!.first as Map<String, Object?>)['sha256'] as String?
          : null;
      checks['schema_hash_pinned'] = pinned;
      if (pinned == null || pinned != digest.toString()) {
        reasons.add('schema-hash-mismatch');
      }
    } else {
      reasons.add('schema-pin-record-missing');
    }
  }

  // 4b. 管线 hash：分割器/装配器/协议 DTO 的 sha256 记录（漂移可检）。
  final pipelineFiles = [
    'lib/features/whiteboard/smart_layout/segmentation/ink_region_segmenter.dart',
    'lib/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart',
    'lib/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart',
    '../FlowMuse-Server/internal/recognition/smart_layout_v3.go',
  ];
  final pipelineHashes = <String, String>{};
  for (final path in pipelineFiles) {
    final file = File(path);
    if (!file.existsSync()) {
      reasons.add('pipeline-file-missing($path)');
      continue;
    }
    pipelineHashes[path] = crypto.sha256
        .convert(file.readAsBytesSync())
        .toString();
  }
  checks['pipeline_hashes'] = pipelineHashes;

  // 4c. live-route：真实路由 smoke（go test -run TestV3LiveRouteSmoke）。
  final goRoot = '../FlowMuse-Server';
  const goExePath = r'D:\Program\Go\bin\go.exe';
  if (!File(goExePath).existsSync()) {
    reasons.add('go-toolchain-missing');
    checks['live_route_exit_code'] = null;
  } else {
    final goResult = await Process.run(
      goExePath,
      [
        'test',
        './internal/recognition/',
        '-run',
        r'^TestV3LiveRouteSmoke$',
        '-count=1',
      ],
      workingDirectory: goRoot,
      environment: {
        'PATH': 'D:/Program/Go/bin;${Platform.environment['PATH'] ?? ''}',
        'GOPATH': 'D:/Program/go-path',
        'GOCACHE': 'D:/Program/go-path/cache',
        'GOFLAGS': '-mod=mod',
        'GOPROXY': 'https://goproxy.cn,direct',
      },
    );
    checks['live_route_exit_code'] = goResult.exitCode;
    final errText = (goResult.stderr as String).trim();
    if (errText.isNotEmpty) {
      checks['live_route_stderr_tail'] = errText.length > 400
          ? errText.substring(errText.length - 400)
          : errText;
    }
    if (goResult.exitCode != 0) {
      reasons.add('live-route-failed(${goResult.exitCode})');
    }
  }

  // 4d. frozen holdout 隔离：dev/validation 与 frozen 无交集（SR-4）。
  final frozenManifest =
      jsonDecode(
            File(
              '${G1Inputs.evidenceRoot}/datasets/splits/frozen_holdout/manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final frozenIds = {
    for (final raw in frozenManifest['samples'] as List)
      (raw as Map<String, Object?>)['sample_id'] as String,
  };
  final overlap = frozenIds.intersection({
    ...inputs.devSampleIds,
    ...inputs.validationSampleIds,
  });
  checks['frozen_isolation'] = overlap.isEmpty;
  if (overlap.isNotEmpty) {
    reasons.add('frozen-contamination(${overlap.length})');
  }

  return {
    'checks': checks,
    'block_reasons': reasons,
    'blocked': reasons.isNotEmpty,
  };
}

void _writeJson(Directory dir, String name, Object? json) {
  File(
    '${dir.path}/$name',
  ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));
}
