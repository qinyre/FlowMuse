import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';

void main() {
  test('has polygon and quadratic variants', () {
    expect(OutlineRenderMode.values, contains(OutlineRenderMode.polygon));
    expect(OutlineRenderMode.values, contains(OutlineRenderMode.quadratic));
    expect(OutlineRenderMode.values.length, 2);
  });
}
