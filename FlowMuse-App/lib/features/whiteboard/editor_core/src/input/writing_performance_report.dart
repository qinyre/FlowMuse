import 'active_preview_metrics_probe.dart';
import 'stroke_render_metrics.dart';

const int writingPerformanceReportSchemaVersion = 1;

class WritingPerformanceReport {
  const WritingPerformanceReport({
    required this.schemaVersion,
    required this.invalidReasons,
    required this.accepted,
    required this.painted,
    required this.missingPaint,
    required this.terminalBeforePreview,
    required this.coverage,
    required this.rejectedRawSamples,
    required this.activePreviewSamples,
    required this.frames,
  });

  factory WritingPerformanceReport.capture({
    required ActivePreviewMetricsProbe activePreview,
    required List<FrameRenderMetrics> frames,
    List<String> invalidReasons = const [],
  }) {
    final samples = activePreview.samples;
    final painted = samples.where((sample) => sample.painted).length;
    final terminal = samples
        .where((sample) => sample.terminalBeforePreview)
        .length;
    final eligible = samples.length - terminal;
    final missing = eligible - painted;
    return WritingPerformanceReport(
      schemaVersion: writingPerformanceReportSchemaVersion,
      invalidReasons: List.unmodifiable(invalidReasons),
      accepted: samples.length,
      painted: painted,
      missingPaint: missing,
      terminalBeforePreview: terminal,
      coverage: eligible == 0 ? 0 : painted / eligible,
      rejectedRawSamples: activePreview.rejectedRawSamples,
      activePreviewSamples: [
        for (final sample in samples)
          {
            'strokeEpoch': sample.strokeEpoch,
            'inputSeq': sample.inputSeq,
            'eventToPaintMicros': sample.eventToPaintMicros,
            'frameNumber': sample.frameNumber,
            'terminalReason': sample.terminalReason?.name,
          },
      ],
      frames: List.unmodifiable(frames),
    );
  }

  factory WritingPerformanceReport.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != writingPerformanceReportSchemaVersion) {
      throw UnsupportedError(
        'Unsupported writing performance schema: $version',
      );
    }
    return WritingPerformanceReport(
      schemaVersion: version! as int,
      invalidReasons: List<String>.from(json['invalidReasons']! as List),
      accepted: json['accepted']! as int,
      painted: json['painted']! as int,
      missingPaint: json['missingPaint']! as int,
      terminalBeforePreview: json['terminalBeforePreview']! as int,
      coverage: (json['coverage']! as num).toDouble(),
      rejectedRawSamples: Map<String, int>.from(
        json['rejectedRawSamples']! as Map,
      ),
      activePreviewSamples: [
        for (final sample in json['activePreviewSamples']! as List)
          Map<String, Object?>.from(sample as Map),
      ],
      frames: [
        for (final frame in json['frames']! as List)
          FrameRenderMetrics.fromJson(Map<String, Object?>.from(frame as Map)),
      ],
    );
  }

  final int schemaVersion;
  final List<String> invalidReasons;
  final int accepted;
  final int painted;
  final int missingPaint;
  final int terminalBeforePreview;
  final double coverage;
  final Map<String, int> rejectedRawSamples;
  final List<Map<String, Object?>> activePreviewSamples;
  final List<FrameRenderMetrics> frames;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'invalidReasons': invalidReasons,
    'accepted': accepted,
    'painted': painted,
    'missingPaint': missingPaint,
    'terminalBeforePreview': terminalBeforePreview,
    'coverage': coverage,
    'rejectedRawSamples': rejectedRawSamples,
    'activePreviewSamples': activePreviewSamples,
    'frames': [for (final frame in frames) frame.toJson()],
  };
}
