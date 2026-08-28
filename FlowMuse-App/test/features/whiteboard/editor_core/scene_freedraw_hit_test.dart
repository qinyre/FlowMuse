import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自由笔画命中/擦除热区与可视笔宽的一致性（Issue #5 T0 缺陷探针 →
/// T6 修复后转为守护断言）。
void main() {
  test('P5: 荧光笔可见外缘超出中心线 AABB，命中/擦除热区不含笔宽（T6 修复）', () {
    // Given: 默认荧光笔（strokeWidth=20，sizeScale=4.2 → 可视半宽约 42）
    final element = FreedrawElement(
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
      strokeWidth: 20,
    );
    final scene = Scene().addElement(element);

    // When: 点击中心线 AABB 之外、可见笔宽之内的点（中心线上方 30px）
    final justOutsideAabb = const Point(200, 70);

    // Then: 现状命中只看中心线 AABB → 不可命中（缺陷证据）
    expect(
      scene.getElementAtPoint(justOutsideAabb),
      isNull,
      reason: '可见笔宽约 ±42px，AABB 外 30px 处应可命中，现状不可（缺陷）',
    );

    // 反证：AABB 内仍命中，证明元素本身可交互
    expect(scene.getElementAtPoint(const Point(200, 102)), isNotNull);
  });
}
