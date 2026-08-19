import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_report.dart';

void main() {
  test('报告区分 paired、missing 与 terminal 并保留 frameNumber', () {
    var now = 0;
    final probe = ActivePreviewMetricsProbe(nowMicros: () => now);
    final epoch = probe.startStroke();
    final first = probe.recordAcceptedPoint(epoch);
    probe.recordAcceptedPoint(epoch);
    now = 10;
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(strokeEpoch: epoch, maxInputSeq: first),
      frameNumber: 12,
    );
    probe.finishStroke(epoch, ActivePreviewTerminalReason.pointerUp);
    probe.recordRejectedRawSample('distance');

    final report = WritingPerformanceReport.capture(
      activePreview: probe,
      frames: const [
        FrameRenderMetrics(
          frameNumber: 12,
          buildMicros: 1000,
          rasterMicros: 2000,
          totalSpanMicros: 3500,
        ),
      ],
    );

    expect(report.accepted, 2);
    expect(report.painted, 1);
    expect(report.missingPaint, 0);
    expect(report.terminalBeforePreview, 1);
    expect(report.coverage, 1);
    expect(report.rejectedRawSamples, {'distance': 1});
    expect(report.activePreviewSamples.first['frameNumber'], 12);
    expect(report.frames.single.totalSpanMicros, 3500);
  });

  test('当前 schema 可无损 round-trip', () {
    const original = WritingPerformanceReport(
      schemaVersion: writingPerformanceReportSchemaVersion,
      invalidReasons: ['injection_jitter'],
      accepted: 1,
      painted: 0,
      missingPaint: 1,
      terminalBeforePreview: 0,
      coverage: 0,
      rejectedRawSamples: {'coalesced': 2},
      activePreviewSamples: [
        {
          'strokeEpoch': 1,
          'inputSeq': 1,
          'eventToPaintMicros': null,
          'frameNumber': null,
          'terminalReason': null,
        },
      ],
      frames: [],
    );

    expect(
      WritingPerformanceReport.fromJson(original.toJson()).toJson(),
      original.toJson(),
    );
  });

  test('未知 schema 明确拒绝', () {
    expect(
      () => WritingPerformanceReport.fromJson({'schemaVersion': 99}),
      throwsUnsupportedError,
    );
  });
}
