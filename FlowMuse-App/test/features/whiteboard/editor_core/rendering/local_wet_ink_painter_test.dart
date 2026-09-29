import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/property_panel_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/draw_style.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('直接渲染活动点列并挂接 accepted-to-paint probe', () {
    final probe = ActivePreviewMetricsProbe(nowMicros: () => 1000);
    final epoch = probe.startStroke();
    final seq = probe.recordAcceptedPoint(epoch);
    final state = LocalWetInkState();
    addTearDown(state.dispose);
    state.publish(
      LocalWetInkFrame(
        strokeEpoch: epoch,
        maxInputSeq: seq,
        view: ActiveFreedrawView(
          strokeId: const ElementId('stroke-1'),
          points: const [Point(10, 20), Point(30, 40)],
          pressures: const [0.2, 0.8],
          simulatePressure: false,
          brushType: BrushType.fountainPen,
        ),
        style: const ElementStyle(strokeColor: '#123456', strokeWidth: 4),
      ),
    );
    final adapter = _RecordingAdapter();
    final painter = LocalWetInkPainter(
      state: state,
      adapter: adapter,
      viewport: const ViewportState(offset: Offset(5, 7), zoom: 2),
      activePreviewMetricsProbe: probe,
    );

    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(200, 100));
    recorder.endRecording();

    expect(adapter.calls, 1);
    expect(adapter.points, const [Point(10, 20), Point(30, 40)]);
    expect(adapter.pressures, const [0.2, 0.8]);
    expect(adapter.style?.strokeColor, const Color(0xff123456));
    expect(adapter.style?.strokeWidth, 4);
    expect(probe.samples.single.painted, isTrue);
  });

  test('单点、长笔和模拟压感均复用现有 Freedraw renderer', () {
    for (final points in [
      const [Point.zero],
      [for (var index = 0; index < 2000; index++) Point(index.toDouble(), 1)],
    ]) {
      final state = LocalWetInkState();
      state.publish(
        LocalWetInkFrame(
          strokeEpoch: 1,
          view: ActiveFreedrawView(
            strokeId: const ElementId('stroke'),
            points: points,
            pressures: const [],
            simulatePressure: true,
            brushType: BrushType.ballpoint,
          ),
          style: const ElementStyle(),
        ),
      );
      final adapter = _RecordingAdapter();
      final recorder = PictureRecorder();

      LocalWetInkPainter(
        state: state,
        adapter: adapter,
        viewport: const ViewportState(),
      ).paint(Canvas(recorder), const Size(200, 100));
      recorder.endRecording();

      expect(adapter.calls, 1);
      expect(adapter.simulatePressure, isTrue);
      state.dispose();
    }
  });

  test('活动湿墨沿用静态画层的 contentBounds 裁剪', () async {
    final state = LocalWetInkState();
    addTearDown(state.dispose);
    state.publish(
      const LocalWetInkFrame(
        strokeEpoch: 1,
        view: ActiveFreedrawView(
          strokeId: ElementId('stroke'),
          points: [Point.zero],
          pressures: [],
          simulatePressure: true,
          brushType: BrushType.ballpoint,
        ),
        style: ElementStyle(),
      ),
    );
    final recorder = PictureRecorder();
    final adapter = _SolidCanvasAdapter();

    LocalWetInkPainter(
      state: state,
      adapter: adapter,
      viewport: const ViewportState(),
      contentBounds: Bounds.fromLTWH(10, 10, 20, 20),
    ).paint(Canvas(recorder), const Size(40, 40));

    final image = await recorder.endRecording().toImage(40, 40);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);
    int alphaAt(int x, int y) => bytes!.getUint8((y * 40 + x) * 4 + 3);
    expect(alphaAt(5, 5), 0);
    expect(alphaAt(15, 15), 255);
    image.dispose();
  });
}

class _RecordingAdapter implements RoughAdapter {
  int calls = 0;
  List<Point>? points;
  List<double>? pressures;
  bool? simulatePressure;
  DrawStyle? style;

  @override
  void drawFreedraw(
    Canvas canvas,
    List<Point> points,
    List<double> pressures,
    bool simulatePressure,
    BrushType brushType,
    DrawStyle style, {
    bool isComplete = true,
    bool pressureEncoded = false,
    FreedrawTaperPhase taperPhase = FreedrawTaperPhase.full,
    double? wholeStrokeRawLength,
  }) {
    calls++;
    this.points = points;
    this.pressures = pressures;
    this.simulatePressure = simulatePressure;
    this.style = style;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SolidCanvasAdapter implements RoughAdapter {
  @override
  void drawFreedraw(
    Canvas canvas,
    List<Point> points,
    List<double> pressures,
    bool simulatePressure,
    BrushType brushType,
    DrawStyle style, {
    bool isComplete = true,
    bool pressureEncoded = false,
    FreedrawTaperPhase taperPhase = FreedrawTaperPhase.full,
    double? wholeStrokeRawLength,
  }) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 40, 40),
      Paint()..color = const Color(0xffffffff),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
