import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

void main() {
  final context = ToolContext(
    scene: Scene(),
    viewport: const ViewportState(),
    selectedIds: const {},
  );

  test('PointerDown 建立稳定 strokeId 并由 final 元素复用', () {
    final tool = FreedrawTool();
    tool.onPointerDown(const Point(10, 20), context, pressure: 0.2);
    final view = tool.activeView!;
    tool.onPointerMove(const Point(20, 30), context, pressure: 0.4);
    final pointsBeforeUp = List<Point>.of(view.points);

    final result = tool.onPointerUp(
      const Point(30, 25),
      context,
      pressure: 0.6,
    );
    final element = (result as AddElementResult).element as FreedrawElement;

    expect(element.id, view.strokeId);
    expect(pointsBeforeUp, [const Point(10, 20), const Point(20, 30)]);
    expect(element.points, [
      const Point(0, 0),
      const Point(10, 10),
      const Point(20, 5),
    ]);
    expect(tool.activeView, isNull);
  });

  test('Cancel 清除活动 view 且不产生 final 结果', () {
    final tool = FreedrawTool();
    tool.onPointerDown(Point.zero, context);

    tool.reset();

    expect(tool.activeView, isNull);
  });

  test('实时墨迹模式在 PointerDown 冻结且下一笔可切换', () {
    final tool = FreedrawTool()..prepareStrokeLiveMode(true);
    tool.onPointerDown(Point.zero, context);
    final first = tool.activeView!;

    tool.prepareStrokeLiveMode(false);
    expect(first.strokeLiveMode, isTrue);
    tool.onPointerUp(const Point(1, 1), context);

    tool.prepareStrokeLiveMode(false);
    tool.onPointerDown(const Point(2, 2), context);
    final second = tool.activeView!;

    expect(second.strokeLiveMode, isFalse);
    expect(second.strokeId, isNot(first.strokeId));
  });

  test('实时墨迹模式不改变 final 笔画几何和压力', () {
    FreedrawElement draw(bool liveMode) {
      final tool = FreedrawTool()..prepareStrokeLiveMode(liveMode);
      tool.onPointerDown(const Point(10, 20), context, pressure: 0.2);
      tool.onPointerMove(const Point(20, 30), context, pressure: 0.4);
      return (tool.onPointerUp(const Point(30, 25), context, pressure: 0.6)
                  as AddElementResult)
              .element
          as FreedrawElement;
    }

    final legacy = draw(false);
    final live = draw(true);

    expect(live.x, legacy.x);
    expect(live.y, legacy.y);
    expect(live.width, legacy.width);
    expect(live.height, legacy.height);
    expect(live.points, legacy.points);
    expect(live.pressures, legacy.pressures);
    expect(live.simulatePressure, legacy.simulatePressure);
    Map<String, Object?> stableCustomData(FreedrawElement element) {
      return Map<String, Object?>.of(element.customData ?? const {})
        ..remove(recognitionStrokeSessionKey)
        ..remove(recognitionStrokeStartedAtKey)
        ..remove(recognitionStrokePointTimesKey);
    }

    expect(stableCustomData(live), stableCustomData(legacy));
  });
}
