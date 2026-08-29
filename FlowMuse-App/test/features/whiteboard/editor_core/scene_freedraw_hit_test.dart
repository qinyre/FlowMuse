import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自由笔画命中/擦除热区与可视笔宽的一致性（Issue #5 A20；
/// P5 缺陷已于 T6 修复：命中含 profile.visualHalfWidth）。
void main() {
  FreedrawElement highlighterStroke({double strokeWidth = 20}) =>
      FreedrawElement(
        id: const ElementId('freedraw-highlighter'),
        x: 100,
        y: 100,
        width: 200,
        height: 4,
        points: const [Point(0, 2), Point(100, 2), Point(200, 2)],
        pressures: const [],
        simulatePressure: true,
        isComplete: true,
        customData: customDataWithBrushType(null, BrushType.highlighter),
        strokeColor: '#ffff00',
        strokeWidth: strokeWidth,
      );

  test('A20: 默认荧光笔可见外缘可命中（原 P5 缺陷已修复）', () {
    final scene = Scene().addElement(highlighterStroke());

    // 可见半宽 ≈ 44（含 AA 余量）：AABB 外 30px（y=70）处应可命中
    expect(
      scene.getElementAtPoint(const Point(200, 70)),
      isNotNull,
      reason: '可见笔宽内的点应可选中/擦除',
    );
    // AABB 内仍命中
    expect(scene.getElementAtPoint(const Point(200, 102)), isNotNull);
    // 可见外缘之外不命中（y=50 距中心线 52 > 44）
    expect(
      scene.getElementAtPoint(const Point(200, 50)),
      isNull,
      reason: '可见外缘之外的点不得命中',
    );
  });

  test('A20: 最大宽度荧光笔可见外缘可命中', () {
    final scene = Scene().addElement(highlighterStroke(strokeWidth: 100));
    // 半宽 = 100×4.2/2+2 = 212 → y = 100+2-212 < 0，取 y=0 边缘内
    expect(
      scene.getElementAtPoint(const Point(200, 0)),
      isNotNull,
      reason: '最大荧光笔上缘应可命中',
    );
    expect(scene.getElementAtPoint(const Point(-100, 102)), isNotNull);
  });

  test('sceneBounds 覆盖五种笔刷真实可见轮廓', () {
    for (final brush in BrushType.values) {
      final scene = Scene().addElement(
        FreedrawElement(
          id: ElementId('stroke-\${brush.name}'),
          x: 50,
          y: 50,
          width: 100,
          height: 2,
          points: const [Point(0, 1), Point(50, 1), Point(100, 1)],
          pressures: const [],
          simulatePressure: true,
          isComplete: true,
          customData: customDataWithBrushType(null, brush),
          strokeWidth: 20,
        ),
      );
      final bounds = scene.sceneBounds()!;
      final half = BrushRenderProfile.forType(brush).visualHalfWidth(20);
      expect(
        bounds.top,
        lessThanOrEqualTo(51 - half + 0.001),
        reason: '\${brush.name} 上缘含笔宽',
      );
      expect(
        bounds.bottom,
        greaterThanOrEqualTo(52 + half - 0.001),
        reason: '\${brush.name} 下缘含笔宽',
      );
    }
  });

  test('elementVisualBounds：其他元素保持既有边界行为', () {
    final rect = RectangleElement(
      id: const ElementId('rect-1'),
      x: 10,
      y: 10,
      width: 50,
      height: 30,
    );
    final b = elementVisualBounds(rect);
    expect(b.left, 10);
    expect(b.top, 10);
    expect(b.size.width, 50);
    expect(b.size.height, 30);
  });
}
