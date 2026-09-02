import 'g1_inputs.dart';

/// 识别延迟评测器（V3-206A 目标符号）。
///
/// 口径对齐 tool/smart_layout_v3/benchmark/benchmark-spec.json：
/// warmup_runs=1、repetitions=3、percentile_method=nearest_rank、
/// concurrency=1、timeout_seconds=300（单样本预算）。
/// 全部机器判定：p95 ≤ timeout_seconds → verdict pass。
class RecognitionLatencyEvaluator {
  RecognitionLatencyEvaluator({
    this.warmupRuns = 1,
    this.repetitions = 3,
    this.timeoutSeconds = 300,
    this.minSamples = 10,
  });

  final int warmupRuns;
  final int repetitions;
  final int timeoutSeconds;
  final int minSamples;

  G1LatencyReport measure({
    required List<String> sampleIds,
    required Map<String, G1SceneSample> samplesById,
  }) {
    final perSampleMs = <double>[];
    var evaluated = 0;
    final watch = Stopwatch();
    for (final sampleId in sampleIds) {
      final sample = samplesById[sampleId];
      if (sample == null) continue;
      evaluated++;
      for (var i = 0; i < warmupRuns; i++) {
        segmentSample(sample);
      }
      watch.reset();
      var totalMs = 0.0;
      for (var r = 0; r < repetitions; r++) {
        watch.start();
        segmentSample(sample);
        watch.stop();
        totalMs += watch.elapsedMicroseconds / 1000.0;
      }
      perSampleMs.add(totalMs / repetitions);
    }
    final p50 = nearestRank(perSampleMs, 0.50);
    final p95 = nearestRank(perSampleMs, 0.95);
    final maxMs = perSampleMs.isEmpty
        ? 0.0
        : perSampleMs.reduce((a, b) => a > b ? a : b);
    final verdicts = <String, String>{
      if (evaluated < minSamples)
        'latency': 'insufficient($evaluated<$minSamples)'
      else ...{
        'latency': p95 / 1000.0 <= timeoutSeconds ? 'pass' : 'fail',
      },
    };
    return G1LatencyReport(
      evaluatedSamples: evaluated,
      p50Ms: p50,
      p95Ms: p95,
      maxMs: maxMs,
      timeoutSeconds: timeoutSeconds,
      repetitions: repetitions,
      verdicts: verdicts,
    );
  }

  /// nearest_rank 百分位（与 benchmark-spec 一致；测试直接复用）。
  static double nearestRank(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final rank = ((q * sorted.length).ceil()).clamp(1, sorted.length);
    return sorted[rank - 1];
  }
}

class G1LatencyReport {
  const G1LatencyReport({
    required this.evaluatedSamples,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
    required this.timeoutSeconds,
    required this.repetitions,
    required this.verdicts,
  });

  final int evaluatedSamples;
  final double p50Ms;
  final double p95Ms;
  final double maxMs;
  final int timeoutSeconds;
  final int repetitions;
  final Map<String, String> verdicts;

  Map<String, Object?> toJson() => {
    'evaluated_samples': evaluatedSamples,
    'p50_ms': _round2(p50Ms),
    'p95_ms': _round2(p95Ms),
    'max_ms': _round2(maxMs),
    'timeout_seconds': timeoutSeconds,
    'repetitions': repetitions,
    'percentile_method': 'nearest_rank',
    'verdicts': verdicts,
  };

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
