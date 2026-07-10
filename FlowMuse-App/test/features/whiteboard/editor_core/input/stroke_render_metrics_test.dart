import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';

void main() {
  test('StrokeRenderMetrics holds values', () {
    const m = StrokeRenderMetrics(
      outlinePointCount: 42,
      getStrokeDuration: Duration(microseconds: 120),
      pathBuildDuration: Duration(microseconds: 30),
    );
    expect(m.outlinePointCount, 42);
    expect(m.getStrokeDuration, const Duration(microseconds: 120));
    expect(m.pathBuildDuration, const Duration(microseconds: 30));
  });

  test('sink receives metrics', () {
    final captured = <StrokeRenderMetrics>[];
    final sink = _ListSink(captured);
    sink.onMetrics(const StrokeRenderMetrics(
      outlinePointCount: 1,
      getStrokeDuration: Duration.zero,
      pathBuildDuration: Duration.zero,
    ));
    expect(captured.length, 1);
    expect(captured.first.outlinePointCount, 1);
  });
}

class _ListSink extends StrokeRenderMetricsSink {
  _ListSink(this.list);
  final List<StrokeRenderMetrics> list;
  @override
  void onMetrics(StrokeRenderMetrics m) => list.add(m);
}
