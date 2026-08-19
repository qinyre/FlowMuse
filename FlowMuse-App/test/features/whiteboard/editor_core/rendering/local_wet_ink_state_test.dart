import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/property_panel_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_state.dart';

void main() {
  test('publish 每次只通知专用监听器并保持同一活动 view', () {
    final state = LocalWetInkState();
    addTearDown(state.dispose);
    var notifications = 0;
    state.addListener(() => notifications++);
    final view = ActiveFreedrawView(
      strokeId: const ElementId('stroke'),
      points: const [Point(1, 2)],
      pressures: const [0.5],
      simulatePressure: false,
      brushType: BrushType.fountainPen,
    );
    final frame = LocalWetInkFrame(
      strokeEpoch: 7,
      view: view,
      style: const ElementStyle(strokeColor: '#123456'),
    );

    state.publish(frame);
    state.publish(frame);

    expect(state.frame!.view, same(view));
    expect(state.revision, 2);
    expect(notifications, 2);
  });

  test('clear 可同步清状态而不额外通知', () {
    final state = LocalWetInkState();
    addTearDown(state.dispose);
    var notifications = 0;
    state.addListener(() => notifications++);
    state.publish(
      LocalWetInkFrame(
        strokeEpoch: 1,
        view: ActiveFreedrawView(
          strokeId: const ElementId('stroke'),
          points: const [Point.zero],
          pressures: const [],
          simulatePressure: true,
          brushType: BrushType.fountainPen,
        ),
        style: const ElementStyle(),
      ),
    );

    state.clear(notify: false);

    expect(state.frame, isNull);
    expect(notifications, 1);
  });
}
