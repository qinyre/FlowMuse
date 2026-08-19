import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';

void main() {
  testWidgets('真实 Controller 到 StaticCanvasPainter 使用同一 probe', (tester) async {
    final probe = ActivePreviewMetricsProbe();
    final controller = MarkdrawController(activePreviewMetricsProbe: probe);
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => EditorCanvas(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    const start = Offset(100, 100);
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        position: start,
        kind: PointerDeviceKind.stylus,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(130, 110),
        delta: Offset(30, 10),
        kind: PointerDeviceKind.stylus,
      ),
    );
    await tester.pump();
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(160, 100),
        delta: Offset(30, -10),
        kind: PointerDeviceKind.stylus,
      ),
    );
    await tester.pump();
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        position: Offset(160, 100),
        kind: PointerDeviceKind.stylus,
      ),
    );
    await tester.pump();

    expect(probe.samples, isNotEmpty);
    expect(probe.samples.where((sample) => sample.painted), isNotEmpty);
    expect(controller.currentScene.elements, hasLength(1));
  });

  test('同一帧配对 high-water mark 覆盖的全部 accepted 点', () {
    var now = 100;
    final probe = ActivePreviewMetricsProbe(nowMicros: () => now);
    final epoch = probe.startStroke();
    final first = probe.recordAcceptedPoint(epoch);
    now = 120;
    final second = probe.recordAcceptedPoint(epoch);

    now = 200;
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(strokeEpoch: epoch, maxInputSeq: second),
      frameNumber: 7,
    );

    expect(first, 1);
    expect(probe.samples.map((sample) => sample.inputSeq), [first, second]);
    expect(probe.samples.map((sample) => sample.frameNumber), [7, 7]);
    expect(probe.samples.map((sample) => sample.eventToPaintMicros), [100, 80]);
  });

  test('重复 paint 不覆盖首次时间且不同 epoch 不会误配', () {
    var now = 0;
    final probe = ActivePreviewMetricsProbe(nowMicros: () => now);
    final firstEpoch = probe.startStroke();
    final firstSeq = probe.recordAcceptedPoint(firstEpoch);
    now = 10;
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(
        strokeEpoch: firstEpoch,
        maxInputSeq: firstSeq,
      ),
      frameNumber: 1,
    );
    now = 20;
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(
        strokeEpoch: firstEpoch,
        maxInputSeq: firstSeq,
      ),
      frameNumber: 2,
    );

    final secondEpoch = probe.startStroke();
    now = 30;
    final secondSeq = probe.recordAcceptedPoint(secondEpoch);
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(
        strokeEpoch: firstEpoch,
        maxInputSeq: secondSeq,
      ),
      frameNumber: 3,
    );

    expect(probe.samples.first.frameNumber, 1);
    expect(probe.samples.last.painted, isFalse);
  });

  test('终止前未绘制点单独标记且迟到 paint 不会复活', () {
    var now = 0;
    final probe = ActivePreviewMetricsProbe(nowMicros: () => now);
    final epoch = probe.startStroke();
    final seq = probe.recordAcceptedPoint(epoch);
    probe.recordRejectedRawSample('minDistance');
    probe.finishStroke(epoch, ActivePreviewTerminalReason.cancel);

    now = 50;
    probe.recordPaintedThrough(
      marker: ActivePreviewPaintMarker(strokeEpoch: epoch, maxInputSeq: seq),
      frameNumber: 9,
    );

    expect(probe.samples.single.terminalBeforePreview, isTrue);
    expect(probe.samples.single.painted, isFalse);
    expect(probe.rejectedRawSamples, {'minDistance': 1});
  });
}
