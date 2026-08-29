import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_culling.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视口裁剪（P1-1 回归）：裁剪必须用可视边界而非中心线 AABB——
/// 粗荧光笔（w=50，sizeScale 4.2 → 可视半宽约 107）中心线出视口而
/// 笔缘仍可见时，中心线 AABB 会整条误裁，笔迹突然消失。
void main() {
  FreedrawElement highlighterAt(double y, {String id = 'hl'}) =>
      FreedrawElement(
        id: ElementId(id),
        x: 100,
        y: y,
        width: 200,
        height: 4,
        points: const [Point(0, 2), Point(100, 2), Point(200, 2)],
        pressures: const [],
        simulatePressure: true,
        isComplete: true,
        customData: customDataWithBrushType(null, BrushType.highlighter),
        strokeColor: '#ffff00',
        strokeWidth: 50,
      );

  test('P1-1: 中心线在视口外但粗笔边缘仍可见时不被裁剪', () {
    // 视口 800×600 zoom1、margin 50 → expanded 上缘 -50。中心线
    // AABB（-60..-56）与 expanded 不相交（旧实现误裁）；
    // elementVisualBounds 上缘 ≈ -60-107 = -167，相交，必须保留。
    final element = highlighterAt(-60);
    final kept = cullElements(
      [element],
      const ViewportState(),
      const Size(800, 600),
    );
    expect(kept, contains(element));
  });

  test('P1-1: 可视边界完全在视口外时仍被正常裁剪', () {
    // 负向对照：可视边界上缘 ≈ -509，远离视口，必须剔除。
    final element = highlighterAt(-400, id: 'hl-far');
    final kept = cullElements(
      [element],
      const ViewportState(),
      const Size(800, 600),
    );
    expect(kept, isNot(contains(element)));
  });
}
