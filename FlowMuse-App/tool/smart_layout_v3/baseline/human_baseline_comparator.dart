/// V3-003B 三基线并表比较器（HumanBaselineComparator）。
///
/// 把 no-op、v2_naive_reflow（来自 baseline-run.json）与 AI surrogate 整理基线
/// （编辑协议产物）用同一套分类账谓词评测并分层并表（按 split/场景族/复杂度带）。
/// 名称说明：比较目标是『AI surrogate 整理基线』，不代表真人整理效率
///（类名沿用任务卡 target_symbol HumanBaselineComparator，语义见 disclosure）。
library;

import 'smart_layout_baseline_runner.dart';

class HumanBaselineComparator {
  const HumanBaselineComparator._();

  /// 组装三基线分层报告。输入场景由调用方注入（inputScenes: sample_id → 池场景）。
  static Map<String, Object?> compare({
    required Map<String, Object?> poolManifest,
    required Map<String, String> splitLookup,
    required Map<String, Map<String, Object?>> autoRuns,
    required Map<String, Map<String, Object?>> inputScenes,
    required Map<String, Map<String, Object?>> aiBaseline,
    required Map<String, Object?> replayCheck,
  }) {
    final samples = (poolManifest['samples'] as List).cast<Map<String, Object?>>();

    final perSample = <Map<String, Object?>>[];
    for (final sample in samples) {
      final id = sample['sample_id'] as String;
      final aiEntry = aiBaseline[id];
      Map<String, Object?>? aiMetrics;
      if (aiEntry != null) {
        final input = inputScenes[id];
        if (input != null) {
          aiMetrics = SmartLayoutBaselineRunner.evaluate(
                  input, aiEntry['scene'] as Map<String, Object?>)
              .toJson();
        }
      }
      perSample.add({
        'sample_id': id,
        'split': splitLookup[id] ?? 'unknown',
        'scene_family': sample['scene_family'],
        'complexity_band': _band(sample),
        'no_op': _metricsOf(autoRuns['no_op'], id),
        'v2_naive_reflow': _metricsOf(autoRuns['v2_naive_reflow'], id),
        'ai_surrogate': {
          'metrics': ?aiMetrics,
          'modification_count': ?aiEntry?['modification_count'],
          'steps': ?aiEntry?['steps'],
        },
      });
    }

    Map<String, Object?> aggregate(List<Map<String, Object?>> rows) {
        Map<String, Object?>? policyStats(String policy) {
        Map<String, Object?>? rowOf(Map<String, Object?> row) =>
            row[policy] as Map<String, Object?>?;
        final rowsWithMetrics = rows
            .map(rowOf)
            .whereType<Map<String, Object?>>()
            .where((p) => p.containsKey('metrics') || p.containsKey('modification_count'))
            .toList();
        if (rowsWithMetrics.isEmpty) return null;
        final metricsList = rowsWithMetrics
            .map((p) => p['metrics'] as Map<String, Object?>?)
            .whereType<Map<String, Object?>>()
            .toList();
        double sum(String key) =>
            metricsList.fold<double>(0, (acc, m) => acc + ((m[key] as num?)?.toDouble() ?? 0));
        return {
          if (metricsList.isNotEmpty) ...{
            'samples_with_metrics': metricsList.length,
            'oob_total': sum('oob_count'),
            'overlap_pair_total': sum('overlap_pair_count'),
            'min_source_recall': metricsList
                .map((m) => (m['source_recall'] as num?)?.toDouble() ?? 1.0)
                .reduce((a, b) => a < b ? a : b),
            'samples_with_failure_codes': metricsList
                .where((m) => ((m['failure_codes'] as List?) ?? const []).isNotEmpty)
                .length,
          },
          if (policy == 'ai_surrogate')
            'modification_count_total': rowsWithMetrics.fold<int>(
                0, (acc, p) => acc + ((p['modification_count'] as int?) ?? 0)),
        };
      }

      return {
        'samples': rows.length,
        'no_op': policyStats('no_op'),
        'v2_naive_reflow': policyStats('v2_naive_reflow'),
        'ai_surrogate': policyStats('ai_surrogate'),
      };
    }

    Map<String, Object?> byAxis(String Function(Map<String, Object?>) valueOf) {
      final groups = <String, List<Map<String, Object?>>>{};
      for (final row in perSample) {
        groups.putIfAbsent(valueOf(row), () => []).add(row);
      }
      final keys = groups.keys.toList()..sort();
      return {
        for (final key in keys) key: aggregate(groups[key]!),
      };
    }

    return {
      'schema_version': '1.0.0',
      'artifact': 'three-baseline-report',
      'task': 'V3-003B',
      'layers': {
        'overall': aggregate(perSample),
        'by_split': byAxis((r) => r['split'] as String),
        'by_scene_family': byAxis((r) => r['scene_family'] as String? ?? 'unknown'),
        'by_complexity_band': byAxis((r) => r['complexity_band'] as String),
      },
      'replay_check': replayCheck,
      'panel_disclosure': {
        'panel_type': 'ai_surrogate',
        'human_validation_performed': false,
        'disclosure': 'HUMAN_VALIDATION_NOT_PERFORMED',
        'statement':
            '第三条基线是两个上下文隔离 GLM-5.3 Max 代理按固定编辑协议生成的 AI surrogate 整理基线；修改次数/操作步骤是协议产物，不代表真人整理效率（类名 HumanBaselineComparator 沿用任务卡符号表，语义以本披露为准）。',
      },
    };
  }

  static Map<String, Object?>? _metricsOf(Map<String, Object?>? run, String sampleId) {
    if (run == null) return null;
    for (final s in (run['samples'] as List).cast<Map<String, Object?>>()) {
      if (s['sample_id'] == sampleId && s['status'] == 'ok') {
        return {'metrics': s['metrics']};
      }
    }
    return null;
  }

  static String _band(Map<String, Object?> sample) {
    final features = sample['features'] as Map<String, Object?>?;
    final strokes = features?['stroke_count'] as int?;
    if (strokes == null) return 'unspecified';
    if (strokes == 0) return 'none';
    if (strokes <= 15) return 'low';
    if (strokes <= 40) return 'medium';
    return 'high';
  }
}
