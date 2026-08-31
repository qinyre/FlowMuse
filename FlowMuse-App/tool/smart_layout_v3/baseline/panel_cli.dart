/// V3-003B 组装 CLI：双隔离代理编辑协议产物的机器重放校验 + 三基线并表。
///
/// 职责（全部为程序断言，任一失败整体 status=failed，退出码 2）：
/// 1. hash 链：两代理 inputs_read 与 protocol.json / blind-input.json 实测 SHA-256 一致；
/// 2. 隔离性：run_id 两两互异且均不等于执行者 run_id；
/// 3. 可重放：对 85 盲化样本逐一 EditorProtocol 重放，两代理 target_scene / steps /
///    modification_count 必须与重放完全一致（protocol.json 的 replayability 条款）；
/// 4. 一致性：双代理产物逐样本对拍，零分歧则不调用第三仲裁代理；
/// 5. PNG：重放目标场景栅格化（blind 编号命名）并记录 SHA-256；
/// 6. 三基线并表：HumanBaselineComparator 输出分层报告（deliverable）。
///
/// 用法（FlowMuse-App 目录）：
///   dart run tool/smart_layout_v3/baseline/panel_cli.dart `<evidence_root>` `<executor_run_id>`
///   evidence_root 例如 docs/研发记录/evidence/smart-layout-v3
/// 退出码：0 组装全部通过；2 校验失败（报告仍写出，status=failed）；3 输入错误。
library;

import 'dart:convert';
import 'dart:io' show Directory, File, exit, stderr, stdout;

import 'package:crypto/crypto.dart' as crypto;

import 'editor_protocol.dart';
import 'human_baseline_comparator.dart';
import 'smart_layout_baseline_runner.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: panel_cli.dart <evidence_root> <executor_run_id>');
    exit(3);
  }
  final root = args[0];
  final executorRunId = args[1];
  final panelDir = '$root/baseline/ai-surrogate';
  Map<String, Object?> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync(encoding: utf8)) as Map<String, Object?>;
  final required = [
    '$panelDir/protocol.json',
    '$panelDir/blind-input.json',
    '$panelDir/blind-mapping.json',
    '$panelDir/agent-a.json',
    '$panelDir/agent-b.json',
    '$root/datasets/synthetic-pool-v2/dataset-manifest.json',
    '$root/baseline/no-op/baseline-run.json',
    '$root/baseline/v2/baseline-run.json',
  ];
  for (final path in required) {
    if (!File(path).existsSync()) {
      stderr.writeln('input missing: $path');
      exit(3);
    }
  }
  for (final split in ['development', 'validation', 'frozen_holdout']) {
    final path = '$root/datasets/splits/$split/manifest.json';
    if (!File(path).existsSync()) {
      stderr.writeln('input missing: $path');
      exit(3);
    }
  }

  final errors = <String>[];
  String sha256OfFile(String path) =>
      crypto.sha256.convert(File(path).readAsBytesSync()).toString();

  final protocolBytes = File('$panelDir/protocol.json').readAsBytesSync();
  final blindBytes = File('$panelDir/blind-input.json').readAsBytesSync();
  final protocolSha = crypto.sha256.convert(protocolBytes).toString();
  final blindSha = crypto.sha256.convert(blindBytes).toString();

  final blind = readJson('$panelDir/blind-input.json');
  final mapping = readJson('$panelDir/blind-mapping.json');
  final agentA = readJson('$panelDir/agent-a.json');
  final agentB = readJson('$panelDir/agent-b.json');

  // ---- 1. hash 链与隔离性 ----
  for (final agent in [agentA, agentB]) {
    final label = agent['agent'] as String;
    final inputs = agent['inputs_read'] as Map<String, Object?>?;
    if (inputs == null) {
      errors.add('agent $label: inputs_read missing');
      continue;
    }
    if (inputs['protocol_sha256'] != protocolSha) {
      errors.add('agent $label: protocol_sha256 mismatch');
    }
    if (inputs['blind_input_sha256'] != blindSha) {
      errors.add('agent $label: blind_input_sha256 mismatch');
    }
  }
  final runA = agentA['run_id'] as String?;
  final runB = agentB['run_id'] as String?;
  if (runA == null || runA.isEmpty) errors.add('agent A: run_id missing');
  if (runB == null || runB.isEmpty) errors.add('agent B: run_id missing');
  if (runA == runB) errors.add('isolation: agent run ids identical');
  if (runA == executorRunId || runB == executorRunId) {
    errors.add('isolation: panelist run id equals executor run id');
  }
  for (final agent in [agentA, agentB]) {
    final label = agent['agent'] as String;
    if (agent['model'] != 'glm-5.3' || agent['reasoning_effort'] != 'max') {
      errors.add('agent $label: model/effort stamp unexpected');
    }
    if ((agent['tool_log'] as List?) == null) {
      errors.add('agent $label: tool_log missing');
    }
  }

  // ---- 2. 机器重放 + 双代理对拍 ----
  final blindSamples = (blind['samples'] as List).cast<Map<String, Object?>>();
  List<Map<String, Object?>> resultsOf(Map<String, Object?> agent) =>
      (agent['results'] as List).cast<Map<String, Object?>>();
  Map<String, Map<String, Object?>> byBlindId(Map<String, Object?> agent) => {
        for (final r in resultsOf(agent)) r['blind_id'] as String: r,
      };
  final aById = byBlindId(agentA);
  final bById = byBlindId(agentB);
  if (aById.length != resultsOf(agentA).length) errors.add('agent A: duplicate blind_id');
  if (bById.length != resultsOf(agentB).length) errors.add('agent B: duplicate blind_id');
  if (aById.length != blindSamples.length) {
    errors.add('agent A: results count ${aById.length} != ${blindSamples.length}');
  }
  if (bById.length != blindSamples.length) {
    errors.add('agent B: results count ${bById.length} != ${blindSamples.length}');
  }

  final pngDir = Directory('$panelDir/pngs');
  pngDir.createSync(recursive: true);
  final replayRows = <Map<String, Object?>>[];
  var aReplayMismatches = 0;
  var bReplayMismatches = 0;
  var abDisagreements = 0;
  final abDisagreementIds = <String>[];
  final replayBySampleId = <String, Map<String, Object?>>{};
  // 形如 {"mapping": {"BL-001": "syn-p2-...", ...}}。
  final mappingPairs = (mapping['mapping'] as Map).cast<String, String>();
  final blindToSample = <String, String>{...mappingPairs};
  if (blindToSample.length != blindSamples.length) {
    errors.add('mapping: covers ${blindToSample.length} != ${blindSamples.length}');
  }

  for (final sample in blindSamples) {
    final blindId = sample['blind_id'] as String;
    final outcome = EditorProtocol.apply(sample);
    final replayScene = outcome.scene;
    final replaySteps = outcome.steps;
    final replayCount = outcome.modificationCount;

    // PNG：以重放目标场景为准（两代理须与重放一致，故 PNG 对双代理同时成立）。
    final png = SmartLayoutBaselineRunner.rasterizePng(replayScene);
    final pngFile = File('${pngDir.path}/$blindId.png');
    pngFile.writeAsBytesSync(png);

    final sampleId = blindToSample[blindId];
    if (sampleId != null) {
      replayBySampleId[sampleId] = {
        'scene': replayScene,
        'steps': replaySteps,
        'modification_count': replayCount,
      };
    }

    var aMismatch = false, bMismatch = false;
    for (final entry in {'A': aById[blindId], 'B': bById[blindId]}.entries) {
      final result = entry.value;
      if (result == null) {
        errors.add('$blindId: agent ${entry.key} result missing');
        (entry.key == 'A' ? (aMismatch = true) : (bMismatch = true));
        continue;
      }
      if (canonicalJson(result['target_scene']) != canonicalJson(replayScene) ||
          canonicalJson(result['steps']) != canonicalJson(replaySteps) ||
          result['modification_count'] != replayCount) {
        errors.add('$blindId: agent ${entry.key} output != machine replay');
        (entry.key == 'A' ? (aMismatch = true) : (bMismatch = true));
      }
    }
    if (aMismatch) aReplayMismatches++;
    if (bMismatch) bReplayMismatches++;

    final ra = aById[blindId], rb = bById[blindId];
    if (ra != null && rb != null) {
      final agree = canonicalJson(ra['target_scene']) == canonicalJson(rb['target_scene']) &&
          canonicalJson(ra['steps']) == canonicalJson(rb['steps']) &&
          ra['modification_count'] == rb['modification_count'];
      if (!agree) {
        abDisagreements++;
        abDisagreementIds.add(blindId);
      }
    }
    replayRows.add({
      'blind_id': blindId,
      'sample_id': sampleId,
      'columns': outcome.columns,
      'modification_count': replayCount,
      'png_sha256': crypto.sha256.convert(png).toString(),
    });
  }
  replayRows.sort((x, y) => (x['blind_id'] as String).compareTo(y['blind_id'] as String));

  // ---- 3. 三基线并表 ----
  final poolManifest = readJson('$root/datasets/synthetic-pool-v2/dataset-manifest.json');
  final splitLookup = <String, String>{};
  for (final split in ['development', 'validation', 'frozen_holdout']) {
    final m = readJson('$root/datasets/splits/$split/manifest.json');
    for (final s in (m['samples'] as List).cast<Map<String, Object?>>()) {
      splitLookup[s['sample_id'] as String] = split;
    }
  }
  final inputScenes = <String, Map<String, Object?>>{};
  for (final sample
      in (poolManifest['samples'] as List).cast<Map<String, Object?>>()) {
    final id = sample['sample_id'] as String;
    final content = sample['content'] as Map<String, Object?>;
    inputScenes[id] =
        readJson('$root/datasets/synthetic-pool-v2/${content['path']}');
  }
  final autoRuns = <String, Map<String, Object?>>{};
  for (final dir in ['no-op', 'v2']) {
    final run = readJson('$root/baseline/$dir/baseline-run.json');
    autoRuns[run['policy'] as String] = run;
  }
  if (!autoRuns.containsKey('no_op') || !autoRuns.containsKey('v2_naive_reflow')) {
    errors.add('auto baseline runs missing expected policies');
  }

  final replayCheck = {
    'status': (aReplayMismatches == 0 && bReplayMismatches == 0) ? 'passed' : 'failed',
    'method': 'EditorProtocol machine replay per protocol.json replayability clause',
    'samples_replayed': replayRows.length,
    'per_agent': {
      'A': {
        'run_id': runA,
        'replay_mismatches': aReplayMismatches,
        'notes_count': (agentA['notes'] as List?)?.length ?? 0,
      },
      'B': {
        'run_id': runB,
        'replay_mismatches': bReplayMismatches,
        'notes_count': (agentB['notes'] as List?)?.length ?? 0,
      },
    },
    'inter_agent': {
      'identical_samples': replayRows.length - abDisagreements,
      'disagreements': abDisagreements,
      'disagreement_blind_ids': abDisagreementIds,
      'arbiter_invoked': false,
      'arbiter_note': abDisagreements == 0
          ? '双代理产物逐样本完全一致，零分歧，无需第三仲裁代理（协议未触发）。'
          : '存在分歧，须第三仲裁代理裁决后再组装。',
    },
  };

  final report = HumanBaselineComparator.compare(
    poolManifest: poolManifest,
    splitLookup: splitLookup,
    autoRuns: autoRuns,
    inputScenes: inputScenes,
    aiBaseline: replayBySampleId,
    replayCheck: replayCheck,
  );

  final panelReport = {
    'schema_version': '1.0.0',
    'artifact': 'ai-surrogate-panel-report',
    'task': 'V3-003B',
    'status': errors.isEmpty ? 'passed' : 'failed',
    'executor_run_id': executorRunId,
    'panel': {
      'agent_a_run_id': runA,
      'agent_b_run_id': runB,
      'model': 'glm-5.3',
      'reasoning_effort': 'max',
      'isolation': '两个全新上下文子代理，互不可见，执行者不兼任',
    },
    'input_hashes': {
      'protocol_sha256': protocolSha,
      'blind_input_sha256': blindSha,
      'agent_a_json_sha256': sha256OfFile('$panelDir/agent-a.json'),
      'agent_b_json_sha256': sha256OfFile('$panelDir/agent-b.json'),
    },
    'replay_check': replayCheck,
    'modification_count_total':
        replayRows.fold<int>(0, (acc, r) => acc + (r['modification_count'] as int)),
    'samples': replayRows,
    'errors': errors,
    'panel_disclosure': {
      'panel_type': 'ai_surrogate',
      'human_validation_performed': false,
      'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
      'statement':
          '两名整理者为上下文隔离的 GLM-5.3 Max AI 代理，产物仅构成 AI surrogate 整理基线，不代表真人整理效率；两代理输出均与机器重放一致方可入表。',
    },
  };

  File('$panelDir/panel-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(panelReport), encoding: utf8);
  File('$panelDir/three-baseline-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report), encoding: utf8);

  stdout.writeln(const JsonEncoder.withIndent(' ').convert({
    'status': panelReport['status'],
    'samples': replayRows.length,
    'modification_count_total': panelReport['modification_count_total'],
    'agent_a_replay_mismatches': aReplayMismatches,
    'agent_b_replay_mismatches': bReplayMismatches,
    'inter_agent_disagreements': abDisagreements,
    'arbiter_invoked': false,
    'error_count': errors.length,
    'first_errors': errors.take(8).toList(),
  }));
  exit(errors.isEmpty ? 0 : 2);
}

/// 顺序无关、整数归一的规范化 JSON：num 为整数值时归一为 int，Map 键排序，
/// 使 24 / 24.0 / 键序差异不影响对拍。
Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return [for (final e in v) _canon(e)];
  if (v is num && !v.isNaN && v == v.truncateToDouble()) {
    return v is int ? v : v.toInt();
  }
  return v;
}

String canonicalJson(Object? v) => jsonEncode(_canon(v));
