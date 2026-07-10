import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/diamond_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/ellipse_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/frame_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/rectangle_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _context = ToolContext(
  scene: Scene(),
  viewport: const ViewportState(),
  selectedIds: const {},
);

void main() {
  test(
    'geometric tools keep the active tool and clear selection after creation',
    () {
      final results = <ToolResult?>[
        _draw(RectangleTool()),
        _draw(DiamondTool()),
        _draw(EllipseTool()),
        _draw(FrameTool()),
      ];

      for (final result in results) {
        expect(result, isA<CompoundResult>());
        final parts = (result! as CompoundResult).results;
        expect(parts.whereType<AddElementResult>(), hasLength(1));
        expect(
          parts.whereType<SetSelectionResult>().single.selectedIds,
          isEmpty,
        );
        expect(parts.whereType<SwitchToolResult>(), isEmpty);
      }
    },
  );
}

ToolResult? _draw(dynamic tool) {
  tool.onPointerDown(const Point(0, 0), _context);
  tool.onPointerMove(const Point(20, 20), _context);
  return tool.onPointerUp(const Point(20, 20), _context);
}
