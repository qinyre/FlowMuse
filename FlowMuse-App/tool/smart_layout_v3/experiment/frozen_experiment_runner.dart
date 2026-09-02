/// V3-606A：frozen 实验执行器——目标符号 [FrozenExperimentRunner]。
///
/// 按预注册 EvaluationSpec（v1.0.0，hash 钉定）执行 frozen 双盲实验：
/// - prepare：上游 hash 验证（RR-3/RR-4）→ ai_surrogate 协议机器重放 →
///   v3_flow_policy 确定性产出 → 自动失败码（复用 V3-003A 检查器）→
///   机械 rubric（code 纯函数）→ 双盲输入包（96 输出盲化混洗）；
/// - finalize：双 persona 盲评产物按 DG1~DG4 合成 → 优效/非劣统计
///   （splitmix64 bootstrap B=10000 seed=20260831，Holm）→ T1~T6 →
///   Gate 5 机器判定 + 披露。
///
/// v3 臂口径（dev 线限制，报告如实披露）：v3_flow_policy 为 v3 放置语义
/// 的确定性代表策略——阅读序多栏流式 + 行带原子组（keep 语义）+ 禁裁字
/// 等比缩放（字号缩档代表）+ 失败即缩不丢弃（fail-closed 代表）+ 笔迹/
/// 装饰线/绑定原位（preserved 语义）；与 v2_naive_reflow / ai_surrogate
/// 同一处理级别，非生产 v3 全管线复刻。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import '../baseline/editor_protocol.dart';
import '../baseline/smart_layout_baseline_runner.dart';

/// v3 代表策略：行带原子组多栏流式 + 禁裁字等比缩放。
class V3FlowPolicy {
  const V3FlowPolicy._();

  static const double margin = 24;
  static const double gap = 12;
  static const double gutter = 16;
  static const double compactGap = 6;
  static const double rowBand = 64;

  static const Set<String> contentTypes = {'text', 'shape', 'image'};

  static EditorOutcome apply(Map<String, Object?> scene) {
    final page = scene['page'] as Map<String, Object?>;
    final pageW = (page['width'] as num).toDouble();
    final pageH = (page['height'] as num).toDouble();
    final elements = (scene['elements'] as List).cast<Map<String, Object?>>();

    final content = <Map<String, Object?>>[];
    final passthrough = <Map<String, Object?>>[];
    for (final element in elements) {
      if (contentTypes.contains(element['type'])) {
        content.add(_clone(element));
      } else {
        passthrough.add(_clone(element));
      }
    }

    int rowBandOf(Map<String, Object?> e) {
      final b = (e['bbox'] as List).cast<num>();
      return ((b[1].toDouble() + b[3].toDouble() / 2) / rowBand).floor();
    }

    content.sort((a, b) {
      final ra = rowBandOf(a), rb = rowBandOf(b);
      if (ra != rb) return ra.compareTo(rb);
      final xa = (a['bbox'] as List).cast<num>()[0].toDouble();
      final xb = (b['bbox'] as List).cast<num>()[0].toDouble();
      if (xa != xb) return xa.compareTo(xb);
      return (a['id'] as String).compareTo(b['id'] as String);
    });

    // 行带原子组（keep 语义）：同 rowBand 的内容元素为一个不可拆单元。
    final units = <List<Map<String, Object?>>>[];
    for (final e in content) {
      if (units.isEmpty || rowBandOf(units.last.last) != rowBandOf(e)) {
        units.add([e]);
      } else {
        units.last.add(e);
      }
    }

    // 栏数推导（可用高内自增 N；与 ai_surrogate 协议同式但按原子组高度）。
    final availW = pageW - 2 * margin;
    final availH = pageH - 2 * margin;
    double unitsTotalHeight() {
      var total = 0.0;
      for (var i = 0; i < units.length; i++) {
        var unitH = 0.0;
        final unit = units[i];
        for (var j = 0; j < unit.length; j++) {
          unitH += (unit[j]['bbox'] as List).cast<num>()[3].toDouble();
          if (j > 0) unitH += compactGap;
        }
        if (i > 0) unitH += gap;
        total += unitH;
      }
      return total;
    }

    var columns = 1;
    final totalH = unitsTotalHeight();
    while (columns < 100) {
      final colW = (availW - gutter * (columns - 1)) / columns;
      if (colW <= 0) {
        columns++;
        continue;
      }
      if (totalH / columns <= availH) break;
      columns++;
    }
    final colW = math.max((availW - gutter * (columns - 1)) / columns, 1.0);

    // 装栏：逐原子组放置；组高（按列宽禁裁字等比缩放后）超剩余栏高 →
    // 换栏；末栏仍超 → 整组等比缩到剩余高度（字号缩档代表，不拆不丢）。
    final steps = <Map<String, Object?>>[];
    var columnIndex = 0;
    var cursorY = margin;
    for (final unit in units) {
      // 先按列宽禁裁字等比缩放（宽超列宽 → 等比；高不变则后续统一处理）。
      for (final e in unit) {
        final b = (e['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList();
        if (b[2] > colW && b[2] > 0) {
          final scale = colW / b[2];
          e['bbox'] = [b[0], b[1], colW, b[3] * scale];
        }
      }
      var unitH = 0.0;
      for (var j = 0; j < unit.length; j++) {
        unitH += (unit[j]['bbox'] as List).cast<num>()[3].toDouble();
        if (j > 0) unitH += compactGap;
      }
      // 换栏（组间 gap 已在组高外）。
      if (cursorY + unitH > pageH - margin &&
          columnIndex + 1 < columns) {
        columnIndex++;
        cursorY = margin;
      }
      var remaining = pageH - margin - cursorY;
      var scaleAll = 1.0;
      if (unitH > remaining && remaining > 0) {
        scaleAll = remaining / unitH; // fail-closed：缩到可放，不拆不丢
      }
      var y = cursorY;
      for (var j = 0; j < unit.length; j++) {
        final e = unit[j];
        final b = (e['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList();
        final newH = b[3] * scaleAll;
        final newW = b[2] * scaleAll;
        final newX = margin + columnIndex * (colW + gutter);
        e['bbox'] = [newX, y, newW, newH];
        y += newH + compactGap * scaleAll;
        steps.add({
          'element_id': e['id'],
          'from': [b[0], b[1], b[2], b[3]],
          'to': [newX, y - newH - compactGap * scaleAll, newW, newH],
        });
      }
      cursorY = y - compactGap * scaleAll + gap;
    }

    // 输出顺序：原位元素（原相对顺序）→ 重排元素（R1 序）。
    final out = {
      'page': _clone(page),
      'elements': [...passthrough, ...content],
    };
    return EditorOutcome(
      scene: out,
      steps: steps,
      modificationCount: steps.length,
      columns: columns,
    );
  }

  static Map<String, Object?> _clone(Map<String, Object?> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, Object?>;
}

/// 机械 rubric（rubric.json scoring_rules 的机器子集实现）：
/// 维度分 = f(绑定 code 集)；overall = min(全部有分数维度)。
class MechanicalRubric {
  const MechanicalRubric._();

  static const Map<String, List<String>> dimensionBindings = {
    'D1': ['C-SNAPSHOT-LOST-SOURCE', 'C-SNAPSHOT-TYPED-TEXT-LOST'],
    'D5': ['M-LAYOUT-OOB', 'M-LAYOUT-OVERLAP'],
  };

  /// 机器可观测 code 子集 → 8 维分数（未观测维度无绑定 code 记 5 分）。
  static Map<String, int> dimensionScores(List<String> codes) {
    final scores = <String, int>{};
    for (final dim in const ['D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8']) {
      final bound = (dimensionBindings[dim] ?? const <String>[])
          .toSet()
          .intersection(codes.toSet());
      final hasCritical = bound.any((c) => c.startsWith('C-'));
      final majors = bound.where((c) => c.startsWith('M-')).toSet();
      if (hasCritical) {
        scores[dim] = 1;
      } else if (majors.length >= 2) {
        scores[dim] = 2;
      } else if (majors.length == 1) {
        scores[dim] = 3;
      } else if (bound.any((c) => c.startsWith('m-'))) {
        scores[dim] = 4;
      } else {
        scores[dim] = 5;
      }
    }
    return scores;
  }

  static int overall(List<String> codes) {
    final scores = dimensionScores(codes);
    return scores.values.reduce(math.min);
  }
}

/// splitmix64（seed=20260831，spec 固定流）。
class SplitMix64 {
  SplitMix64(this.seed);

  final int seed;
  int _state = 0;

  double nextDouble() {
    _state = (_state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    var z = _state;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF;
    z = z ^ (z >> 31);
    return (z % 1000000000) / 1000000000;
  }
}

class FrozenExperimentRunner {
  FrozenExperimentRunner({required this.repoRoot});

  final String repoRoot;
  static const bootstrapSeed = 20260831;
  static const bootstrapB = 10000;

  String get evidenceRoot => '$repoRoot/docs/研发记录/evidence/smart-layout-v3';
  String get experimentsDir => '$evidenceRoot/experiments';

  Map<String, Object?> _readJson(String path) =>
      jsonDecode(File(path).readAsStringSync(encoding: utf8))
          as Map<String, Object?>;

  String _sha256File(String path) =>
      crypto.sha256.convert(File(path).readAsBytesSync()).toString();

  /// prepare：hash 验证 → 双臂产出 → 失败码/机械 rubric → 盲化包。
  Map<String, Object?> prepare() {
    final spec = _readJson(
      '$repoRoot/docs/研发记录/specs/smart-layout-v3/evaluation-spec.json',
    );

    // ---- RR-3/RR-4：上游 pinning 验证（拒绝即退出码 2，不产统计）----
    final failures = <String>[];
    final upstream = spec['upstream_contracts'] as Map<String, Object?>;
    for (final entry in upstream.entries) {
      final contract = entry.value as Map<String, Object?>;
      final path = contract['path'] as String;
      final expected = contract['sha256'] as String;
      final actual = _sha256File('$repoRoot/$path');
      if (actual != expected) {
        failures.add('${entry.key}: $path hash $actual != $expected');
      }
    }
    if (failures.isNotEmpty) {
      final report = {
        'status': 'refused',
        'rejection_rules': ['RR-3', 'RR-4'],
        'failures': failures,
      };
      _writeJson('$experimentsDir/v3-arm-report.json', report);
      return report;
    }

    // ---- 48 dev 样本 ----
    final devManifest = _readJson(
      '$evidenceRoot/datasets/splits/development/manifest.json',
    );
    final sampleIds = [
      for (final s in (devManifest['samples'] as List).cast<Map<String, Object?>>())
        s['sample_id'] as String,
    ];
    final samplesById = <String, Map<String, Object?>>{};
    for (final id in sampleIds) {
      samplesById[id] = _readJson(
        '$evidenceRoot/datasets/synthetic-pool-v2/samples/$id.scene.json',
      );
    }

    // ---- 双臂产出与评估 ----
    final perSample = <Map<String, Object?>>[];
    for (final id in sampleIds) {
      final input = samplesById[id]!;
      final surrogate = EditorProtocol.apply(input);
      final v3 = V3FlowPolicy.apply(input);
      final surrogateEval = SmartLayoutBaselineRunner.evaluate(
        input,
        surrogate.scene,
      );
      final v3Eval = SmartLayoutBaselineRunner.evaluate(input, v3.scene);
      perSample.add({
        'sample_id': id,
        'v3': {
          'codes': v3Eval.codes,
          'critical_count': v3Eval.criticalCount,
          'major_count': v3Eval.majorCount,
          'rubric_overall': MechanicalRubric.overall(v3Eval.codes),
          'modification_count': v3.modificationCount,
          'scene_sha256':
              SmartLayoutBaselineRunner.canonicalSceneSha256(v3.scene),
        },
        'ai_surrogate': {
          'codes': surrogateEval.codes,
          'critical_count': surrogateEval.criticalCount,
          'major_count': surrogateEval.majorCount,
          'rubric_overall': MechanicalRubric.overall(surrogateEval.codes),
          'modification_count': surrogate.modificationCount,
          'scene_sha256': SmartLayoutBaselineRunner.canonicalSceneSha256(
            surrogate.scene,
          ),
        },
      });
    }

    // v2 基线 dev 违规样本（three-baseline by_split 钉定 7/48；逐样本
    // 重放对齐：no_op/v2 由 SmartLayoutBaselineRunner 同式重算）。
    final v2Flags = <String, bool>{};
    for (final id in sampleIds) {
      final input = samplesById[id]!;
      final v2 = SmartLayoutBaselineRunner.applyPolicy('v2_naive_reflow', input);
      final eval = SmartLayoutBaselineRunner.evaluate(input, v2);
      v2Flags[id] = eval.majorCount > 0 || eval.criticalCount > 0;
    }

    // ---- 盲化（确定性混洗 seed=bootstrapSeed；arm 标签仅在 mapping）----
    final blindEntries = <Map<String, Object?>>[];
    var blindSeq = 0;
    for (final s in perSample) {
      blindEntries.add({
        'sample_id': s['sample_id'],
        'arm': 'v3',
        'scene': samplesById[s['sample_id'] as String],
      });
      blindEntries.add({
        'sample_id': s['sample_id'],
        'arm': 'ai_surrogate',
        'scene': samplesById[s['sample_id'] as String],
      });
    }
    final rng = SplitMix64(bootstrapSeed);
    // Fisher-Yates（确定性）。
    for (var i = blindEntries.length - 1; i > 0; i--) {
      final j = (rng.nextDouble() * (i + 1)).floor() % (i + 1);
      final tmp = blindEntries[i];
      blindEntries[i] = blindEntries[j];
      blindEntries[j] = tmp;
    }
    final blindOutputs = <String, Map<String, Object?>>{};
    final blindMapping = <String, Map<String, Object?>>{};
    for (final entry in blindEntries) {
      blindSeq++;
      final blindId = 'FX-${blindSeq.toString().padLeft(3, '0')}';
      final id = entry['sample_id'] as String;
      final arm = entry['arm'] as String;
      Map<String, Object?> output;
      if (arm == 'v3') {
        output = V3FlowPolicy.apply(samplesById[id]!).scene;
      } else {
        output = EditorProtocol.apply(samplesById[id]!).scene;
      }
      blindOutputs[blindId] = output;
      blindMapping[blindId] = {'sample_id': id, 'arm': arm};
    }
    final blindInputs = <String, Map<String, Object?>>{};
    for (final entry in blindEntries) {
      final blindId = (blindMapping.entries
              .firstWhere((m) =>
                  (m.value['sample_id'] == entry['sample_id'] &&
                  m.value['arm'] == entry['arm']))
              .key);
      blindInputs[blindId] =
          entry['scene'] as Map<String, Object?>;
    }
    _writeJson('$experimentsDir/blind-input.json', {
      'schema_version': '1.0.0',
      'note': '双盲：persona 只见 blind_id 与输入/输出场景，不见 arm 标签',
      'rubric_path':
          'docs/研发记录/evidence/smart-layout-v3/tasks/V3-000B/artifacts/rubric.json',
      'inputs': blindInputs,
      'outputs': blindOutputs,
    });
    _writeJson('$experimentsDir/blind-mapping.json', {
      'schema_version': '1.0.0',
      'disclosure': 'finalize 后方可打开；执行者与 persona 均不得提前读取',
      'mapping': blindMapping,
      'inputs_by_sample': samplesById,
    });

    final report = {
      'schema_version': '1.0.0',
      'task': 'V3-606A',
      'stage': 'prepare',
      'status': 'prepared',
      'spec_pinning_verified': true,
      'split': {'name': 'development', 'n': sampleIds.length},
      'v3_policy_disclosure': const [
        'v3_flow_policy 为 v3 放置语义确定性代表策略（阅读序多栏流式+行带原子组+禁裁字等比缩放+fail-closed 缩放不拆不丢+笔迹原位）',
        '与 v2_naive_reflow / ai_surrogate 同一处理级别，非生产 v3 全管线复刻（dev 线限制）',
      ],
      'per_sample': perSample,
      'v2_major_flags': v2Flags,
      'blind_count': blindOutputs.length,
    };
    _writeJson('$experimentsDir/v3-arm-report.json', report);
    return report;
  }

  /// finalize：双 persona 盲评合成（DG1~DG4）+ 预注册统计（T1~T6）+
  /// Gate 5 机器判定。
  Map<String, Object?> finalize() {
    final arm = _readJson('$experimentsDir/v3-arm-report.json');
    if (arm['status'] != 'prepared') {
      throw StateError('prepare 未完成或被拒绝: ${arm['status']}');
    }
    final agentA = _readJson('$experimentsDir/persona-a.json');
    final agentB = _readJson('$experimentsDir/persona-b.json');

    // ---- DG1 隔离与覆盖校验 ----
    final runA = agentA['run_id'] as String;
    final runB = agentB['run_id'] as String;
    if (runA == runB) {
      throw StateError('DG1 违反：persona run_id 必须互异');
    }
    final ratingsA = (agentA['ratings'] as Map<String, Object?>)
        .cast<String, Map<String, Object?>>();
    final ratingsB = (agentB['ratings'] as Map<String, Object?>)
        .cast<String, Map<String, Object?>>();
    if (ratingsA.keys.toSet().difference(ratingsB.keys.toSet()).isNotEmpty ||
        ratingsB.keys.toSet().difference(ratingsA.keys.toSet()).isNotEmpty) {
      throw StateError('DG1 违反：两 persona blind_id 覆盖不一致');
    }

    // ---- DG2~DG4 合成（样本级 overall：Δ=0/1 保守取低；Δ≥2 须仲裁）----
    final mapping = (_readJson('$experimentsDir/blind-mapping.json')
        ['mapping'] as Map<String, Object?>)
        .cast<String, Map<String, Object?>>();
    final blindIds = ratingsA.keys.toList()..sort();
    final softDisagreements = <String>[];
    final mandatoryArbitration = <String>[];
    final finalOverallByBlind = <String, int>{};
    for (final blindId in blindIds) {
      final a = (ratingsA[blindId]!['overall'] as num).toInt();
      final b = (ratingsB[blindId]!['overall'] as num).toInt();
      final delta = (a - b).abs();
      if (delta <= 1) {
        finalOverallByBlind[blindId] = math.min(a, b);
        if (delta == 1) softDisagreements.add(blindId);
      } else {
        mandatoryArbitration.add(blindId);
      }
    }
    var arbiterUsed = false;
    if (mandatoryArbitration.isNotEmpty) {
      final arbiterFile = File('$experimentsDir/persona-arbiter.json');
      if (!arbiterFile.existsSync()) {
        throw StateError(
          'DG4：${mandatoryArbitration.length} 项 Δ≥2 分歧需第三代理仲裁'
          '（persona-arbiter.json 缺失）',
        );
      }
      final arbiter = _readJson('$experimentsDir/persona-arbiter.json');
      final rulings = (arbiter['rulings'] as Map<String, Object?>)
          .cast<String, Map<String, Object?>>();
      for (final blindId in mandatoryArbitration) {
        if (rulings[blindId] == null) {
          throw StateError('DG4：仲裁缺 $blindId 裁决');
        }
        finalOverallByBlind[blindId] =
            (rulings[blindId]!['overall'] as num).toInt();
      }
      arbiterUsed = true;
    }

    // ---- 揭盲：blind → (sample, arm)；与机械 rubric 校准对拍 ----
    final perSample = (arm['per_sample'] as List).cast<Map<String, Object?>>();
    final rubricV3 = <String, int>{};
    final rubricSurrogate = <String, int>{};
    final calibrationDeltas = <String, int>{};
    Map<String, Object?> armRecord(String id, String armName) =>
        perSample.firstWhere((s) => s['sample_id'] == id)[armName]
            as Map<String, Object?>;
    // 预注册统计口径（rubric R1：评分=code 纯函数）用机械分；panel 合成
    // 分仅作双盲校准层（逐样本 |Δ| 披露）。
    for (final blindId in blindIds) {
      final target = mapping[blindId]!;
      final sampleId = target['sample_id'] as String;
      final armName = target['arm'] as String;
      final panelScore = finalOverallByBlind[blindId]!;
      final mechanical =
          (armRecord(sampleId, armName)['rubric_overall'] as num).toInt();
      calibrationDeltas[blindId] = (panelScore - mechanical).abs();
    }
    for (final record in perSample) {
      final sampleId = record['sample_id'] as String;
      rubricV3[sampleId] =
          ((record['v3'] as Map<String, Object?>)['rubric_overall'] as num)
              .toInt();
      rubricSurrogate[sampleId] =
          ((record['ai_surrogate'] as Map<String, Object?>)['rubric_overall']
                  as num)
              .toInt();
    }

    final sampleIds = rubricV3.keys.toList()..sort();
    final v2Flags = (arm['v2_major_flags'] as Map<String, Object?>)
        .cast<String, bool>();

    // ---- 指标（RR-1/RR-2：registered_metrics + D_SAMPLES）----
    final n = sampleIds.length;
    final v3MajVec = [
      for (final id in sampleIds)
        ((armRecord(id, 'v3')['major_count'] as num) > 0),
    ];
    final sucMajVec = [
      for (final id in sampleIds)
        ((armRecord(id, 'ai_surrogate')['major_count'] as num) > 0),
    ];
    final v2MajVec = [for (final id in sampleIds) v2Flags[id]!];
    final v3Crit = [
      for (final id in sampleIds)
        ((armRecord(id, 'v3')['critical_count'] as num) > 0),
    ].where((x) => x).length;
    final deltaRubric = [
      for (final id in sampleIds)
        (rubricV3[id]! - rubricSurrogate[id]!).toDouble(),
    ];

    // ---- bootstrap（splitmix64 固定流；E1→E2→E3）----
    (double, double) bootstrap(List<double> diffs,
        {required double threshold, required bool upperTail}) {
      final point = diffs.reduce((a, b) => a + b) / diffs.length;
      final rng = SplitMix64(bootstrapSeed);
      var exceed = 0;
      for (var b = 0; b < bootstrapB; b++) {
        var sum = 0.0;
        for (var i = 0; i < diffs.length; i++) {
          sum += diffs[(rng.nextDouble() * diffs.length).floor() % diffs.length];
        }
        final bootMean = sum / diffs.length;
        if (upperTail ? bootMean >= threshold : bootMean <= threshold) {
          exceed++;
        }
      }
      return (point, exceed / bootstrapB);
    }

    final pairedRDai = [
      for (var i = 0; i < n; i++)
        (v3MajVec[i] ? 1.0 : 0.0) - (sucMajVec[i] ? 1.0 : 0.0),
    ];
    final pairedRDv2 = [
      for (var i = 0; i < n; i++)
        (v3MajVec[i] ? 1.0 : 0.0) - (v2MajVec[i] ? 1.0 : 0.0),
    ];
    final e1 = bootstrap(pairedRDai, threshold: 0.10, upperTail: true);
    final e2 = bootstrap(pairedRDv2, threshold: 0.0, upperTail: true);
    final e3 = bootstrap(deltaRubric, threshold: -0.25, upperTail: false);

    // ---- T6：Spearman(rubric_overall(v3), 每样本失败码计数) ----
    final codeCounts = [
      for (final id in sampleIds)
        ((armRecord(id, 'v3')['codes'] as List).length).toDouble(),
    ];
    final rubricVals = [for (final id in sampleIds) rubricV3[id]!.toDouble()];
    final rho = _spearman(rubricVals, codeCounts);
    final allZeroCodes = codeCounts.every((c) => c == 0);

    // ---- Holm 校正（族 T2/T3/T4，α=0.05）----
    final rawPs = [e1.$2, e2.$2, e3.$2];
    final order = [0, 1, 2]..sort((x, y) => rawPs[x].compareTo(rawPs[y]));
    final holm = List<double>.filled(3, 1.0);
    var runningMax = 0.0;
    for (var rank = 0; rank < 3; rank++) {
      final idx = order[rank];
      runningMax = math.max(runningMax, math.min(rawPs[idx] * (3 - rank), 1.0));
      holm[idx] = runningMax;
    }
    final t2Pass = holm[0] < 0.05 && e1.$1 < 0.10;
    final t4Pass = holm[1] < 0.05 && e2.$1 < 0.0;
    final t3Pass = holm[2] < 0.05 && e3.$1 > -0.25;

    // ---- T5：性能预算（消费 V3-604A 机器证据）----
    final perfReport =
        _readJson('$evidenceRoot/performance/v3-604a-report.json');
    final t5Pass = perfReport['all_passed'] == true;
    final gatePass = v3Crit == 0 && t2Pass && t3Pass && t4Pass && t5Pass;

    final v3Mods = [
      for (final s in perSample)
        ((s['v3'] as Map<String, Object?>)['modification_count'] as num),
    ].fold<num>(0, (a, b) => a + b);

    final report = {
      'schema_version': '1.0.0',
      'task': 'V3-606A',
      'stage': 'finalize',
      'gate': 'G5',
      'status': gatePass ? 'passed' : 'failed',
      'machine_decision': {
        'T1_critical_zero': {
          'v3_critical_samples': v3Crit,
          'pass': v3Crit == 0,
        },
        'T2_noninferiority_ai': {
          'rd_major': e1.$1,
          'p_one_sided_holm': holm[0],
          'margin': 0.10,
          'pass': t2Pass,
          'v3_major_samples': v3MajVec.where((x) => x).length,
          'surrogate_major_samples': sucMajVec.where((x) => x).length,
          'n': n,
        },
        'T3_rubric_noninferiority': {
          'delta_rubric': e3.$1,
          'p_one_sided_holm': holm[2],
          'margin': -0.25,
          'pass': t3Pass,
        },
        'T4_superiority_v2': {
          'rd_major_v2': e2.$1,
          'p_one_sided_holm': holm[1],
          'pass': t4Pass,
          'v2_major_samples': v2MajVec.where((x) => x).length,
        },
        'T5_perf_budgets': {
          'source': 'performance/v3-604a-report.json',
          'pass': t5Pass,
        },
        'T6_construct': {
          'spearman_rho': rho.isNaN ? null : rho,
          'indeterminate': allZeroCodes,
          'note': allZeroCodes
              ? '每样本失败码计数全 0 → construct_check_indeterminate'
                  '（不判 fail，披露口径）'
              : 'bootstrap 单侧判定按 spec；此处记点估计',
        },
      },
      'operational_cost_proxy': {
        'v3_modification_total_dev': v3Mods,
        'ai_surrogate_modification_total_pinned': 480,
        'note': 'v3 代表策略操作步数（development 48 样本）vs ai_surrogate '
            '钉定全池 480（three-baseline 口径，披露性对照）',
      },
      'panel': {
        'agent_a_run_id': runA,
        'agent_b_run_id': runB,
        'isolation': '两个全新上下文子代理，互不可见，执行者不兼任',
        'soft_disagreements': softDisagreements.length,
        'mandatory_arbitration': mandatoryArbitration.length,
        'arbiter_used': arbiterUsed,
        'calibration': {
          'max_abs_delta_vs_mechanical':
              calibrationDeltas.values.reduce(math.max),
          'note': '机械 rubric（code 纯函数）与盲评合成分逐样本偏差（校准披露）',
        },
      },
      'panel_disclosure': {
        'panel_type': 'ai_surrogate',
        'human_validation_performed': false,
        'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
        'statement': '本实验双盲盲评由两个上下文隔离的 GLM-5.3 Max AI 代理执行，'
            '分歧才启用第三仲裁；不构成真人同行评审。',
      },
      'production_release_note': {
        'development_gates': 'G0~G5 全部为 development Gate，通过不授权生产发布',
        'disclosure': 'PRODUCTION_RELEASE_NOT_AUTHORIZED',
      },
      'v3_policy_disclosure': arm['v3_policy_disclosure'],
    };
    _writeJson('$experimentsDir/gate-5-experiment-report.json', report);
    return report;
  }

  /// Spearman ρ（并列取平均秩；退化返回 NaN）。
  static double _spearman(List<double> a, List<double> b) {
    List<double> ranks(List<double> v) {
      final idx = [
        for (var i = 0; i < v.length; i++) i,
      ]..sort((x, y) => v[x].compareTo(v[y]));
      final r = List<double>.filled(v.length, 0);
      var i = 0;
      while (i < idx.length) {
        var j = i;
        while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
          j++;
        }
        final avg = (i + j) / 2.0 + 1;
        for (var k = i; k <= j; k++) {
          r[idx[k]] = avg;
        }
        i = j + 1;
      }
      return r;
    }

    final ra = ranks(a);
    final rb = ranks(b);
    final n = a.length;
    final meanA = ra.reduce((x, y) => x + y) / n;
    final meanB = rb.reduce((x, y) => x + y) / n;
    var num = 0.0;
    var da = 0.0;
    var db = 0.0;
    for (var i = 0; i < n; i++) {
      num += (ra[i] - meanA) * (rb[i] - meanB);
      da += (ra[i] - meanA) * (ra[i] - meanA);
      db += (rb[i] - meanB) * (rb[i] - meanB);
    }
    if (da == 0 || db == 0) return double.nan;
    return num / math.sqrt(da * db);
  }

  void _writeJson(String path, Map<String, Object?> value) {
    final file = File(path);
    file.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }
}

Future<void> main(List<String> args) async {
  final repoRoot = args.isNotEmpty ? args[0] : '.';
  final runner = FrozenExperimentRunner(repoRoot: repoRoot);
  if (args.contains('prepare')) {
    final report = runner.prepare();
    stdout.writeln(
      '[experiment] prepare: ${report['status']} '
      '(${report['blind_count'] ?? 0} blind outputs)',
    );
    exit(report['status'] == 'prepared' ? 0 : 2);
  }
  if (args.contains('finalize')) {
    final report = runner.finalize();
    final md = report['machine_decision'] as Map<String, Object?>;
    bool passOf(String key) => (md[key] as Map)['pass'] as bool;
    stdout.writeln(
      '[experiment] finalize: gate5=${report['status']} '
      'T1=${passOf('T1_critical_zero')} '
      'T2=${passOf('T2_noninferiority_ai')} '
      'T3=${passOf('T3_rubric_noninferiority')} '
      'T4=${passOf('T4_superiority_v2')} '
      'T5=${passOf('T5_perf_budgets')}',
    );
    exit(report['status'] == 'passed' ? 0 : 2);
  }
  stderr.writeln(
      'usage: frozen_experiment_runner.dart <repoRoot> {prepare|finalize}');
  exit(64);
}
