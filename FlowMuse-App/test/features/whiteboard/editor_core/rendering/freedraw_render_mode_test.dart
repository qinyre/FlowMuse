import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';

void main() {
  test(
    'RoughCanvasAdapter exposes mutable outlineRenderMode defaulting to quadratic',
    () {
      final a = RoughCanvasAdapter();
      expect(a.outlineRenderMode, OutlineRenderMode.quadratic);
      a.outlineRenderMode = OutlineRenderMode.polygon;
      expect(a.outlineRenderMode, OutlineRenderMode.polygon);
    },
  );
}
