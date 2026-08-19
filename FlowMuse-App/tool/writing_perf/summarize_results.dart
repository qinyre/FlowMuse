import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const int supportedReportSchemaVersion = 1;

class WritingRunSummary {
  const WritingRunSummary({
    required this.path,
    required this.valid,
    required this.invalidReasons,
    required this.accepted,
    required this.painted,
    required this.terminalBeforePreview,
    required this.coverage,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.worstMicros,
    required this.eventToPaintMicros,
  });

  final String path;
  final bool valid;
  final List<String> invalidReasons;
  final int accepted;
  final int painted;
  final int terminalBeforePreview;
  final double coverage;
  final int? p50Micros;
  final int? p95Micros;
  final int? p99Micros;
  final int? worstMicros;
  final List<int> eventToPaintMicros;
}

class WritingResultsSummary {
  const WritingResultsSummary({required this.runs});

  final List<WritingRunSummary> runs;

  List<WritingRunSummary> get validRuns =>
      runs.where((run) => run.valid).toList();

  double get validRate => runs.isEmpty ? 0 : validRuns.length / runs.length;

  int? get medianRunP95 {
    final values = validRuns.map((run) => run.p95Micros!).toList()..sort();
    return values.isEmpty ? null : nearestRank(values, 0.50);
  }

  double? get runP95SpreadRatio {
    final values = validRuns.map((run) => run.p95Micros!).toList()..sort();
    final median = medianRunP95;
    if (values.length < 2 || median == null || median == 0) return null;
    return (values.last - values.first) / median;
  }

  ({int low, int high})? get bootstrapP95Interval {
    final values = validRuns.expand((run) => run.eventToPaintMicros).toList();
    return values.isEmpty ? null : bootstrapP95(values);
  }

  String toCsv() {
    final buffer = StringBuffer(
      'path,valid,invalidReasons,accepted,painted,terminalBeforePreview,'
      'coverage,p50Micros,p95Micros,p99Micros,worstMicros\n',
    );
    for (final run in runs) {
      buffer.writeln(
        [
          _csv(run.path),
          run.valid,
          _csv(run.invalidReasons.join('|')),
          run.accepted,
          run.painted,
          run.terminalBeforePreview,
          run.coverage.toStringAsFixed(6),
          run.p50Micros ?? '',
          run.p95Micros ?? '',
          run.p99Micros ?? '',
          run.worstMicros ?? '',
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String toMarkdown() {
    final interval = bootstrapP95Interval;
    final spread = runP95SpreadRatio;
    final status = validRuns.length < 5
        ? 'insufficient_valid_runs'
        : spread != null && spread <= 0.10
        ? 'stable'
        : 'unstable';
    final buffer = StringBuffer()
      ..writeln('# 书写性能结果汇总')
      ..writeln()
      ..writeln('- 状态：`$status`')
      ..writeln('- 有效轮次：${validRuns.length}/${runs.length}')
      ..writeln('- 有效率：${(validRate * 100).toStringAsFixed(2)}%')
      ..writeln('- 五轮 P95 中位数：${medianRunP95 ?? 'not_measured'} µs')
      ..writeln(
        '- P95 bootstrap 95% CI：${interval == null ? 'not_measured' : '${interval.low}～${interval.high} µs'}',
      )
      ..writeln(
        '- 轮间波动：${spread == null ? 'not_measured' : '${(spread * 100).toStringAsFixed(2)}%'}',
      )
      ..writeln()
      ..writeln(
        '| raw path | valid | invalid reasons | accepted | coverage | P50/P95/P99/worst (µs) |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | --- |');
    for (final run in runs) {
      buffer.writeln(
        '| `${run.path}` | ${run.valid} | ${run.invalidReasons.join(', ')} | '
        '${run.accepted} | ${(run.coverage * 100).toStringAsFixed(2)}% | '
        '${run.p50Micros ?? '-'}/${run.p95Micros ?? '-'}/'
        '${run.p99Micros ?? '-'}/${run.worstMicros ?? '-'} |',
      );
    }
    return buffer.toString();
  }
}

Future<WritingResultsSummary> summarizeDirectory(Directory input) async {
  if (!await input.exists()) {
    throw ArgumentError.value(input.path, 'input', 'directory does not exist');
  }
  final files = await input
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  final runs = <WritingRunSummary>[];
  for (final file in files) {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) continue;
    final root = Map<String, Object?>.from(json);
    if (root['mode'] == 'collaboration_cpu_non_ui') continue;
    runs.add(_summarizeRun(file.absolute.path, root));
  }
  return WritingResultsSummary(runs: runs);
}

WritingRunSummary _summarizeRun(String path, Map<String, Object?> root) {
  final invalidReasons = <String>[];
  if (root['schemaVersion'] != supportedReportSchemaVersion) {
    invalidReasons.add('unsupported_root_schema');
  }
  if (root['measurementEligible'] != true) {
    invalidReasons.add('not_profile_or_not_device_eligible');
  }
  final rawPerformance = root['performance'];
  if (rawPerformance is! Map) {
    invalidReasons.add('missing_performance_report');
    return WritingRunSummary(
      path: path,
      valid: false,
      invalidReasons: invalidReasons,
      accepted: 0,
      painted: 0,
      terminalBeforePreview: 0,
      coverage: 0,
      p50Micros: null,
      p95Micros: null,
      p99Micros: null,
      worstMicros: null,
      eventToPaintMicros: const [],
    );
  }
  final performance = Map<String, Object?>.from(rawPerformance);
  if (performance['schemaVersion'] != supportedReportSchemaVersion) {
    invalidReasons.add('unsupported_performance_schema');
  }
  final reportInvalidReasons = performance['invalidReasons'];
  if (reportInvalidReasons is List) {
    invalidReasons.addAll(reportInvalidReasons.cast<String>());
  }
  final accepted = (performance['accepted'] as num?)?.toInt() ?? 0;
  final painted = (performance['painted'] as num?)?.toInt() ?? 0;
  final terminal = (performance['terminalBeforePreview'] as num?)?.toInt() ?? 0;
  final coverage = (performance['coverage'] as num?)?.toDouble() ?? 0;
  if (accepted < 100) invalidReasons.add('fewer_than_100_accepted_samples');
  if (coverage < 0.995) invalidReasons.add('coverage_below_99_5_percent');
  final samples = performance['activePreviewSamples'];
  final durations = <int>[];
  if (samples is List) {
    for (final rawSample in samples) {
      if (rawSample is! Map) continue;
      final duration = rawSample['eventToPaintMicros'];
      if (duration is num && rawSample['terminalReason'] == null) {
        durations.add(duration.toInt());
      }
    }
  }
  durations.sort();
  if (durations.isEmpty) invalidReasons.add('no_painted_samples');
  return WritingRunSummary(
    path: path,
    valid: invalidReasons.isEmpty,
    invalidReasons: List.unmodifiable(invalidReasons),
    accepted: accepted,
    painted: painted,
    terminalBeforePreview: terminal,
    coverage: coverage,
    p50Micros: durations.isEmpty ? null : nearestRank(durations, 0.50),
    p95Micros: durations.isEmpty ? null : nearestRank(durations, 0.95),
    p99Micros: durations.isEmpty ? null : nearestRank(durations, 0.99),
    worstMicros: durations.isEmpty ? null : durations.last,
    eventToPaintMicros: List.unmodifiable(durations),
  );
}

int nearestRank(List<int> sortedValues, double percentile) {
  if (sortedValues.isEmpty) throw ArgumentError('values must not be empty');
  if (percentile <= 0 || percentile > 1) {
    throw RangeError.range(percentile, 0, 1, 'percentile');
  }
  final index = math.max(0, (percentile * sortedValues.length).ceil() - 1);
  return sortedValues[index];
}

({int low, int high}) bootstrapP95(
  List<int> values, {
  int iterations = 1000,
  int seed = 1701,
}) {
  if (values.isEmpty) throw ArgumentError('values must not be empty');
  final random = math.Random(seed);
  final estimates = <int>[];
  for (var iteration = 0; iteration < iterations; iteration++) {
    final sample = [
      for (var index = 0; index < values.length; index++)
        values[random.nextInt(values.length)],
    ]..sort();
    estimates.add(nearestRank(sample, 0.95));
  }
  estimates.sort();
  return (
    low: nearestRank(estimates, 0.025),
    high: nearestRank(estimates, 0.975),
  );
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

Future<void> main(List<String> arguments) async {
  String? inputPath;
  String? outputPath;
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--input':
        inputPath = arguments[++index];
        break;
      case '--output':
        outputPath = arguments[++index];
        break;
    }
  }
  if (inputPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/writing_perf/summarize_results.dart --input <raw-directory> --output <report.md>',
    );
    exitCode = 64;
    return;
  }
  final summary = await summarizeDirectory(Directory(inputPath));
  final markdownFile = File(outputPath);
  await markdownFile.parent.create(recursive: true);
  await markdownFile.writeAsString(summary.toMarkdown());
  final csvPath = outputPath.toLowerCase().endsWith('.md')
      ? '${outputPath.substring(0, outputPath.length - 3)}.csv'
      : '$outputPath.csv';
  await File(csvPath).writeAsString(summary.toCsv());
  stdout.writeln('markdown=${markdownFile.absolute.path}');
  stdout.writeln('csv=${File(csvPath).absolute.path}');
}
