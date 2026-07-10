// test/features/whiteboard/editor_core/input/stroke_recorder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';

StrokeInputSample s(int ms, StrokePhase phase) => StrokeInputSample(
  pointerId: 1, x: ms.toDouble(), y: 0.0, time: Duration(milliseconds: ms),
  pressure: 0.5, kind: StrokeInputKind.stylus, phase: phase,
  source: StrokeSampleSource.actual,
);

void main() {
  test('records samples and viewport metadata, round-trips JSON', () {
    final rec = StrokeRecorder();
    rec.record(s(0, StrokePhase.down), viewportZoom: 1.0, viewportTransform: [1,0,0,1,0,0]);
    rec.record(s(16, StrokePhase.move), viewportZoom: 1.0, viewportTransform: [1,0,0,1,0,0]);
    final rec1 = rec.finish(buildVersion: 'test', deviceInfo: 'unit');

    final json = rec1.toJson();
    final rec2 = StrokeRecording.fromJson(json);

    expect(rec2.samples.length, 2);
    expect(rec2.samples.first.phase, StrokePhase.down);
    expect(rec2.samples.last.x, 16.0);
    expect(rec2.viewportZoom, 1.0);
    expect(rec2.buildVersion, 'test');
    expect(rec2.deviceInfo, 'unit');
    // 确定性：相同输入 → 相同录制
    expect(rec2.samples, rec1.samples);
  });

  test('clear empties the recorder', () {
    final rec = StrokeRecorder();
    rec.record(s(0, StrokePhase.down), viewportZoom: 1, viewportTransform: [1,0,0,1,0,0]);
    rec.clear();
    final r = rec.finish();
    expect(r.samples, isEmpty);
  });
}
