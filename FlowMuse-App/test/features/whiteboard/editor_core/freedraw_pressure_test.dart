import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ToolContext context;

  setUp(() {
    context = ToolContext(
      scene: Scene(),
      viewport: const ViewportState(),
      selectedIds: const {},
    );
  });

  test('stores aligned pressure samples for a pressure-enabled stroke', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.2);
    tool.onPointerMove(const Point(5, 2), context, pressure: 0.6);
    final result = tool.onPointerUp(const Point(10, 4), context, pressure: 0.8);

    final element = _createdElement(result);
    expect(element.points, hasLength(3));
    expect(element.pressures, [0.2, 0.6, 0.8]);
    expect(element.simulatePressure, isFalse);
  });

  test('keeps pressure empty when the stroke has no reliable pressure', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context);
    tool.onPointerMove(const Point(5, 2), context);
    final result = tool.onPointerUp(const Point(10, 4), context);

    final element = _createdElement(result);
    expect(element.points, hasLength(3));
    expect(element.pressures, isEmpty);
    expect(element.simulatePressure, isTrue);
  });

  test('keeps freedraw active after completing a stroke', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.3);
    final result = tool.onPointerUp(const Point(2, 2), context, pressure: 0.4);

    expect(result, isA<AddElementResult>());
  });

  test('does not request a raw polyline overlay while drawing', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.3);
    tool.onPointerMove(const Point(2, 2), context, pressure: 0.4);

    expect(tool.overlay!.showCreationPreviewLine, isFalse);
  });
}

FreedrawElement _createdElement(ToolResult? result) {
  final addResult = switch (result) {
    AddElementResult() => result,
    CompoundResult(:final results) =>
      results.whereType<AddElementResult>().single,
    _ => throw StateError('Expected a freedraw element result'),
  };
  return addResult.element as FreedrawElement;
}
