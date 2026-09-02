import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_insets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/oriented_layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_geometry_kernel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutRect AABB 原语', () {
    test('闭盒相交：共享边/角即相交', () {
      const a = LayoutRect(left: 0, top: 0, width: 10, height: 10);
      const touchRight = LayoutRect(left: 10, top: 5, width: 4, height: 2);
      const apart = LayoutRect(left: 10.5, top: 0, width: 2, height: 2);
      expect(a.intersects(touchRight), isTrue, reason: '共享右边');
      expect(a.intersects(apart), isFalse);
      expect(SmartLayoutGeometryKernel.aabbIntersects(a, touchRight), isTrue);
    });

    test('嵌套 contain：完全内含与相等均算包含', () {
      const outer = LayoutRect(left: 0, top: 0, width: 100, height: 50);
      const inner = LayoutRect(left: 10, top: 10, width: 30, height: 20);
      expect(outer.containsRect(inner), isTrue);
      expect(outer.containsRect(outer), isTrue);
      expect(inner.containsRect(outer), isFalse);
      expect(SmartLayoutGeometryKernel.aabbContains(outer, inner), isTrue);
    });

    test('零尺寸形态：点/线不漏报', () {
      const point = LayoutRect(left: 5, top: 5, width: 0, height: 0);
      const box = LayoutRect(left: 0, top: 0, width: 10, height: 10);
      const hLine = LayoutRect(left: 20, top: 5, width: 8, height: 0);
      expect(point.isDegenerate, isTrue);
      expect(box.intersects(point), isTrue, reason: '点在盒内');
      expect(box.intersects(hLine), isFalse, reason: '线段在盒右侧');
      expect(box.gapTo(hLine), closeTo(10, 1e-12));
    });

    test('间隙：相交为 0，对角距离为欧氏值', () {
      const a = LayoutRect(left: 0, top: 0, width: 10, height: 10);
      const b = LayoutRect(left: 13, top: 4, width: 5, height: 5);
      expect(a.gapTo(b), closeTo(3, 1e-12));
      expect(a.gapTo(a), 0);
      expect(SmartLayoutGeometryKernel.gapBetween(a, b), closeTo(3, 1e-12));
    });

    test('union/intersectOrNull 与值语义', () {
      const a = LayoutRect(left: 0, top: 0, width: 10, height: 10);
      const b = LayoutRect(left: 5, top: 5, width: 10, height: 10);
      final u = a.union(b);
      expect(u, const LayoutRect(left: 0, top: 0, width: 15, height: 15));
      final i = a.intersectOrNull(b);
      expect(i, const LayoutRect(left: 5, top: 5, width: 5, height: 5));
      expect(a.intersectOrNull(const LayoutRect(left: 20, top: 20, width: 1, height: 1)), isNull);
      expect(a == const LayoutRect(left: 0, top: 0, width: 10, height: 10), isTrue);
      expect(a.hashCode, const LayoutRect(left: 0, top: 0, width: 10, height: 10).hashCode);
    });

    test('fromPoints 与 inflate/insets', () {
      final r = LayoutRect.fromPoints(10, 20, 4, 6);
      expect(r, const LayoutRect(left: 4, top: 6, width: 6, height: 14));
      const insets = LayoutInsets(left: 2, top: 1, right: 3, bottom: 4);
      expect(insets.inflateRect(r), const LayoutRect(left: 2, top: 5, width: 11, height: 19));
      expect(insets.deflateRect(r), const LayoutRect(left: 6, top: 7, width: 1, height: 9));
      expect(const LayoutInsets.zero().isZero, isTrue);
      expect(
        () => const LayoutInsets(left: 100, top: 0, right: 100, bottom: 0).deflateRect(r),
        throwsArgumentError,
        reason: '过度收缩显式失败，不允许负尺寸盒静默流转',
      );
    });
  });

  group('OrientedLayoutRect OBB', () {
    test('轴对齐退化：旋转 0/π 与 AABB 判定一致', () {
      final obb0 = OrientedLayoutRect.fromRect(
        const LayoutRect(left: 0, top: 0, width: 10, height: 10),
        0,
      );
      final obbPi = OrientedLayoutRect.fromRect(
        const LayoutRect(left: 0, top: 0, width: 10, height: 10),
        math.pi,
      );
      final other = OrientedLayoutRect.fromRect(
        const LayoutRect(left: 10, top: 0, width: 5, height: 5),
        0,
      );
      expect(obb0.isAxisAligned, isTrue);
      expect(obbPi.isAxisAligned, isTrue, reason: '旋转 π 的矩形 AABB 不变');
      expect(obb0.intersects(other), isTrue, reason: '共享边接触');
      expect(obb0.toConservativeAabb(), const LayoutRect(left: 0, top: 0, width: 10, height: 10));
    });

    test('45° 旋转保守 AABB 数学核对：(w+h)·|cos45|·2', () {
      final obb = OrientedLayoutRect.fromRect(
        const LayoutRect(left: 0, top: 0, width: 40, height: 30),
        math.pi / 4,
      );
      final aabb = obb.toConservativeAabb();
      final expected = (40 + 30) * math.cos(math.pi / 4);
      expect(aabb.width, closeTo(expected, 1e-9));
      expect(aabb.height, closeTo(expected, 1e-9));
      expect(aabb.centerX, closeTo(20, 1e-9));
    });

    test('SAT 近分离：平行 45° 细条 AABB 重叠但 OBB 分离', () {
      // 两条平行 45° 细条：保守 AABB 大面积重叠，法向投影距离
      // 10·cos45°≈7.07 > 半宽和 2——SAT 必须判分离。
      final a = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 20,
        halfHeight: 1,
        rotation: math.pi / 4,
      );
      final b = OrientedLayoutRect(
        centerX: 0,
        centerY: 10,
        halfWidth: 20,
        halfHeight: 1,
        rotation: math.pi / 4,
      );
      expect(
        a.toConservativeAabb().intersects(b.toConservativeAabb()),
        isTrue,
        reason: '旋转外扩盒重叠（近分离情形）',
      );
      expect(a.intersects(b), isFalse, reason: 'SAT 精判分离');
      // 对照：法向偏移 2·cos45°≈1.41 ≤ 半宽和 2 → 真实相交。
      final c = OrientedLayoutRect(
        centerX: 0,
        centerY: 2,
        halfWidth: 20,
        halfHeight: 1,
        rotation: math.pi / 4,
      );
      expect(a.intersects(c), isTrue);
    });

    test('SAT 相交：45° 长条与轴对齐长条真实交叠', () {
      final rotated = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 30,
        halfHeight: 2,
        rotation: math.pi / 4,
      );
      final axisAligned = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 5,
        halfHeight: 5,
        rotation: 0,
      );
      expect(rotated.intersects(axisAligned), isTrue);
      expect(SmartLayoutGeometryKernel.obbIntersects(rotated, axisAligned), isTrue);
    });

    test('OBB 嵌套：小 OBB 完全在大旋转 OBB 内', () {
      final big = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 30,
        halfHeight: 30,
        rotation: math.pi / 6,
      );
      final small = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 5,
        halfHeight: 5,
        rotation: math.pi / 3,
      );
      expect(big.intersects(small), isTrue, reason: '完全内含必相交');
    });

    test('零尺寸 OBB（线段）判定', () {
      final degenerate = OrientedLayoutRect(
        centerX: 5,
        centerY: 5,
        halfWidth: 0,
        halfHeight: 10,
        rotation: 0,
      );
      final box = OrientedLayoutRect(
        centerX: 5,
        centerY: 5,
        halfWidth: 10,
        halfHeight: 10,
        rotation: 0,
      );
      expect(degenerate.intersects(box), isTrue);
      final far = OrientedLayoutRect(
        centerX: 30,
        centerY: 5,
        halfWidth: 5,
        halfHeight: 5,
        rotation: 0,
      );
      expect(degenerate.intersects(far), isFalse);
    });

    test('epsilon 保守方向：数学端点接触的旋转对不因浮点抖动漏检', () {
      // b 沿 a 长轴平移恰 2·hw=40：端点相触，SAT 投影 dist 数学上等于
      // r1+r2；浮点 ulp 抖动由 epsilon 兜底，接触不得漏检。
      final a = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 20,
        halfHeight: 2,
        rotation: math.pi / 4,
      );
      final b = OrientedLayoutRect(
        centerX: 40 * math.cos(math.pi / 4),
        centerY: 40 * math.sin(math.pi / 4),
        halfWidth: 20,
        halfHeight: 2,
        rotation: math.pi / 4,
      );
      expect(a.intersects(b), isTrue, reason: '接触即相交（闭盒保守）');
      final far = OrientedLayoutRect(
        centerX: 44 * math.cos(math.pi / 4),
        centerY: 44 * math.sin(math.pi / 4),
        halfWidth: 20,
        halfHeight: 2,
        rotation: math.pi / 4,
      );
      expect(a.intersects(far), isFalse);
    });

    test('轴对齐快路径精确语义：1e-12 间隙是真实分离非漏检', () {
      final a = OrientedLayoutRect(centerX: 0, centerY: 0, halfWidth: 10, halfHeight: 10);
      final apart = OrientedLayoutRect(
        centerX: 20 + 1e-12,
        centerY: 0,
        halfWidth: 10,
        halfHeight: 10,
      );
      final overlap = OrientedLayoutRect(
        centerX: 20 - 1e-12,
        centerY: 0,
        halfWidth: 10,
        halfHeight: 10,
      );
      expect(a.intersects(apart), isFalse);
      expect(a.intersects(overlap), isTrue);
    });

    test('obbIntersectsRect：旋转障碍与候选盒', () {
      final rotatedObstacle = OrientedLayoutRect(
        centerX: 0,
        centerY: 0,
        halfWidth: 40,
        halfHeight: 3,
        rotation: math.pi / 4,
      );
      // 候选盒在原点附近必与 45° 长条相交。
      const near = LayoutRect(left: -5, top: -5, width: 10, height: 10);
      expect(SmartLayoutGeometryKernel.obbIntersectsRect(rotatedObstacle, near), isTrue);
      // 远离长条两端的盒：保守 AABB 可能相交（外扩盒很宽）但 SAT 分离。
      const farAlong = LayoutRect(left: 30, top: 30, width: 5, height: 5);
      // 45° 长条在 (30,30) 方向的 reach = 40·cos45 ≈ 28.3 < 30 → 分离，
      // 但外扩 AABB 到 ±30.3，候选 (30..35,30..35) 与其重叠 → 精判价值所在。
      expect(SmartLayoutGeometryKernel.obbIntersectsRect(rotatedObstacle, farAlong), isFalse);
    });
  });

  group('页界 contain', () {
    const page = LayoutRect(left: 0, top: 0, width: 800, height: 600);

    test('insets 内容区完全容纳', () {
      const insets = LayoutInsets(left: 24, top: 16, right: 32, bottom: 16);
      const fits = LayoutRect(left: 24, top: 16, width: 744, height: 568);
      const overRight = LayoutRect(left: 24, top: 16, width: 745, height: 568);
      const onEdge = LayoutRect(left: 24, top: 16, width: 744.0000000001, height: 568);
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, insets: insets, candidate: fits),
        isTrue,
      );
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, insets: insets, candidate: overRight),
        isFalse,
      );
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, insets: insets, candidate: onEdge),
        isTrue,
        reason: '1e-10 越线在默认 1e-9 容差内',
      );
    });

    test('零 insets 与越界拒绝', () {
      const inside = LayoutRect(left: 0, top: 0, width: 800, height: 600);
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, candidate: inside),
        isTrue,
      );
      const negativeOrigin = LayoutRect(left: -1, top: 0, width: 5, height: 5);
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, candidate: negativeOrigin),
        isFalse,
      );
      // 零尺寸点恰在页角（闭盒）算 contain。
      const cornerPoint = LayoutRect(left: 800, top: 600, width: 0, height: 0);
      expect(
        SmartLayoutGeometryKernel.pageContainsRect(page: page, candidate: cornerPoint),
        isTrue,
      );
    });
  });
}
