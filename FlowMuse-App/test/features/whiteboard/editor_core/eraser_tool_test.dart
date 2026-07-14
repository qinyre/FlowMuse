import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/eraser_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('拖动时立即删除命中的元素，而非等待抬笔', () {
    final first = RectangleElement(
      id: ElementId('first'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    final second = RectangleElement(
      id: ElementId('second'),
      x: 20,
      y: 0,
      width: 10,
      height: 10,
    );
    final tool = EraserTool();
    final scene = Scene().addElement(first).addElement(second);

    final down = tool.onPointerDown(const Point(5, 5), _context(scene));
    expect(_removedIds(down), {first.id});

    final afterFirst = scene.softDeleteElement(first.id);
    final move = tool.onPointerMove(const Point(25, 5), _context(afterFirst));
    expect(_removedIds(move), {second.id});

    final afterSecond = afterFirst.softDeleteElement(second.id);
    expect(tool.onPointerUp(const Point(25, 5), _context(afterSecond)), isNull);
  });
}

ToolContext _context(Scene scene) => ToolContext(
  scene: scene,
  viewport: const ViewportState(),
  selectedIds: const {},
);

Set<ElementId> _removedIds(ToolResult? result) => switch (result) {
  CompoundResult(:final results) =>
    results.whereType<RemoveElementResult>().map((result) => result.id).toSet(),
  RemoveElementResult(:final id) => {id},
  _ => throw StateError('Expected a delete result'),
};
