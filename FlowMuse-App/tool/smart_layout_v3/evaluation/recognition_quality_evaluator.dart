import 'g1_inputs.dart';

/// 识别质量评测器（V3-206A 目标符号）：
/// 分割 pairwise 精确率/召回率、merge/split 错误、最差分组。
///
/// - development 与 validation 严格分离（各自 split 单独汇总）；
/// - frozen holdout 永不进入（SR-4）；
/// - 低样本明确：可用样本 < [minSamples]（默认 10）→ verdict=insufficient；
/// - 全部机器判定，无人工评分项。
class RecognitionQualityEvaluator {
  RecognitionQualityEvaluator({this.minSamples = 10, double? worstGroupFloor})
    : worstGroupFloor = worstGroupFloor;

  /// 低样本下限：低于该值不下质量结论。
  final int minSamples;

  /// 最差分组 pair-F1 预线（null=只报告不判定）。
  final double? worstGroupFloor;

  G1QualityReport evaluate({
    required String splitName,
    required List<String> sampleIds,
    required Map<String, G1SceneSample> samplesById,
    required Map<String, G1Annotation> labelsBySample,
    required Map<String, Map<String, String>> idMappingBySample,
  }) {
    var truePositives = 0;
    var falsePositives = 0;
    var falseNegatives = 0;
    var mergeErrors = 0;
    var splitErrors = 0;
    var strokeLossSamples = 0;
    final perSample = <Map<String, Object?>>[];
    var evaluated = 0;

    for (final sampleId in sampleIds) {
      final sample = samplesById[sampleId];
      final annotation = labelsBySample[sampleId];
      final mapping = idMappingBySample[sampleId];
      if (sample == null || annotation == null || mapping == null) {
        continue;
      }
      evaluated++;
      final predicted = segmentSample(sample);
      // 期望组：e-id → 真实 id 后再按元素类型过滤（预测侧只见笔画）。
      final expected = [
        for (final group in annotation.expectedGroups())
          [
            for (final eId in group)
              if (sample.elementTypeById[mapping[eId] ?? eId] == 'stroke')
                mapping[eId] ?? eId,
          ],
      ].where((group) => group.isNotEmpty).toList();
      // 源守恒：预测分组必须覆盖全部笔画（丢笔迹即 stroke-loss 样本）。
      final predictedIds = {for (final group in predicted) ...group};
      final strokeIds = {
        for (final stroke in sample.strokes) stroke['id'] as String,
      };
      final lostStrokes = strokeIds.difference(predictedIds).toList()..sort();
      if (lostStrokes.isNotEmpty) {
        strokeLossSamples++;
      }

      final score = _pairScore(expected: expected, predicted: predicted);
      truePositives += score.truePositives;
      falsePositives += score.falsePositives;
      falseNegatives += score.falseNegatives;
      mergeErrors += score.mergeErrors;
      splitErrors += score.splitErrors;
      perSample.add({
        'sample_id': sampleId,
        'pair_precision': score.precision,
        'pair_recall': score.recall,
        'pair_f1': score.f1,
        'merge_errors': score.mergeErrors,
        'split_errors': score.splitErrors,
        'lost_strokes': lostStrokes,
        'expected_groups': expected.length,
        'predicted_groups': predicted.length,
      });
    }

    final precision = truePositives + falsePositives == 0
        ? 1.0
        : truePositives / (truePositives + falsePositives);
    final recall = truePositives + falseNegatives == 0
        ? 1.0
        : truePositives / (truePositives + falseNegatives);
    final f1 = precision + recall == 0
        ? 0.0
        : 2 * precision * recall / (precision + recall);

    perSample.sort(
      (a, b) => ((a['pair_f1'] as double).compareTo(b['pair_f1'] as double)),
    );
    Map<String, Object?>? worst;
    if (perSample.isNotEmpty) {
      worst = perSample.first;
    }

    final verdicts = <String, String>{};
    if (evaluated < minSamples) {
      verdicts['quality'] = 'insufficient';
      verdicts['low_sample'] = 'insufficient($evaluated<$minSamples)';
    } else {
      verdicts['quality'] = 'measured';
      verdicts['stroke_conservation'] = strokeLossSamples == 0
          ? 'pass'
          : 'fail($strokeLossSamples)';
      if (worstGroupFloor != null && worst != null) {
        verdicts['worst_group_preline'] =
            (worst['pair_f1'] as double) >= worstGroupFloor!
            ? 'pass'
            : 'below_preline';
      }
    }

    return G1QualityReport(
      split: splitName,
      evaluatedSamples: evaluated,
      pairPrecision: precision,
      pairRecall: recall,
      pairF1: f1,
      mergeErrors: mergeErrors,
      splitErrors: splitErrors,
      strokeLossSamples: strokeLossSamples,
      worstGrouping: worst,
      perSample: perSample,
      verdicts: verdicts,
    );
  }

  /// pairwise 共同成员打分 + merge/split 计数。
  static _PairScore _pairScore({
    required List<List<String>> expected,
    required List<List<String>> predicted,
  }) {
    // 确定性 pair 键：排序拼接字符串（String.hashCode 跨进程不稳定，
    // 评测产物必须可复现）。
    String pairKey(String a, String b) =>
        a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

    final expectedPairs = <String>{};
    for (final group in expected) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          expectedPairs.add(pairKey(group[i], group[j]));
        }
      }
    }
    final predictedPairs = <String>{};
    for (final group in predicted) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          predictedPairs.add(pairKey(group[i], group[j]));
        }
      }
    }
    final tp = expectedPairs.intersection(predictedPairs).length;
    final fp = predictedPairs.difference(expectedPairs).length;
    final fn = expectedPairs.difference(predictedPairs).length;

    // merge：一个预测组横跨 ≥2 个期望组的主元素。
    var merges = 0;
    for (final group in predicted) {
      final touched = <String>{};
      for (final id in group) {
        for (final eGroup in expected) {
          if (eGroup.contains(id)) {
            touched.add(eGroup.first);
          }
        }
      }
      if (touched.length > 1) merges++;
    }
    // split：一个期望组被 ≥2 个预测组瓜分。
    var splits = 0;
    for (final group in expected) {
      final touched = <String>{};
      for (final id in group) {
        for (final pGroup in predicted) {
          if (pGroup.contains(id)) {
            touched.add(pGroup.first);
          }
        }
      }
      if (touched.length > 1) splits++;
    }

    final precision = tp + fp == 0 ? 1.0 : tp / (tp + fp);
    final recall = tp + fn == 0 ? 1.0 : tp / (tp + fn);
    final f1 = precision + recall == 0
        ? 0.0
        : 2 * precision * recall / (precision + recall);
    return _PairScore(
      truePositives: tp,
      falsePositives: fp,
      falseNegatives: fn,
      precision: precision,
      recall: recall,
      f1: f1,
      mergeErrors: merges,
      splitErrors: splits,
    );
  }
}

class _PairScore {
  const _PairScore({
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.mergeErrors,
    required this.splitErrors,
  });

  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final double precision;
  final double recall;
  final double f1;
  final int mergeErrors;
  final int splitErrors;
}

class G1QualityReport {
  const G1QualityReport({
    required this.split,
    required this.evaluatedSamples,
    required this.pairPrecision,
    required this.pairRecall,
    required this.pairF1,
    required this.mergeErrors,
    required this.splitErrors,
    required this.strokeLossSamples,
    required this.worstGrouping,
    required this.perSample,
    required this.verdicts,
  });

  final String split;
  final int evaluatedSamples;
  final double pairPrecision;
  final double pairRecall;
  final double pairF1;
  final int mergeErrors;
  final int splitErrors;
  final int strokeLossSamples;
  final Map<String, Object?>? worstGrouping;
  final List<Map<String, Object?>> perSample;
  final Map<String, String> verdicts;

  Map<String, Object?> toJson() => {
    'split': split,
    'evaluated_samples': evaluatedSamples,
    'pair_precision': _round4(pairPrecision),
    'pair_recall': _round4(pairRecall),
    'pair_f1': _round4(pairF1),
    'merge_errors': mergeErrors,
    'split_errors': splitErrors,
    'stroke_loss_samples': strokeLossSamples,
    'worst_grouping': worstGrouping,
    'verdicts': verdicts,
  };

  static double _round4(double v) => double.parse(v.toStringAsFixed(4));
}
