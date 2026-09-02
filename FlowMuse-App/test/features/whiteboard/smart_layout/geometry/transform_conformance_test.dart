import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/smart_layout/geometry/affine_layout_transform.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_transform_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/transform_invariant.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-302A conformance：支持矩阵每格、稳定拒绝码、仿射不变量与
/// old/new 深一致性 fixtures（嵌套组/旋转 frame/绑定链）。
void main() {
  group('支持矩阵：每格有 fixture', () {
    test('九类已知元素 × 三操作全部支持（movable）', () {
      for (final kind in SmartLayoutTransformContract.supportByKind.keys) {
        for (final op in LayoutTransformOp.values) {
          final decision = SmartLayoutTransformContract.decide(
            kind: kind,
            mobility: SnapshotMobility.movable,
            op: op,
          );
          expect(
            decision.supported,
            isTrue,
            reason: '$kind × ${op.name} 应支持',
          );
        }
      }
    });

    test('未知类型原子拒绝：不存在"尽量变换"', () {
      for (final op in LayoutTransformOp.values) {
        expect(
          SmartLayoutTransformContract.decide(
            kind: 'future-widget',
            mobility: SnapshotMobility.movable,
            op: op,
          ).reason,
          TransformRejectReason.unsupportedElementType,
          reason: '未知类型 ${op.name} 必须拒绝',
        );
      }
    });

    test('mobility 拒绝优先于类型矩阵', () {
      // 背景元素即使 kind 在矩阵内也拒绝；锁定物同理。
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'rectangle',
          mobility: SnapshotMobility.background,
          op: LayoutTransformOp.move,
        ).reason,
        TransformRejectReason.backgroundElement,
      );
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'text',
          mobility: SnapshotMobility.protectedObstacle,
          op: LayoutTransformOp.rotate,
        ).reason,
        TransformRejectReason.protectedObstacleLocked,
      );
      // mobility 拒绝优先于未知类型（同格只报一个稳定码）。
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'future-widget',
          mobility: SnapshotMobility.background,
          op: LayoutTransformOp.move,
        ).reason,
        TransformRejectReason.backgroundElement,
      );
    });

    test('resize 目标几何校验：负/NaN 拒绝，零尺寸合法', () {
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'rectangle',
          mobility: SnapshotMobility.movable,
          op: LayoutTransformOp.resize,
          resizeTargetWidth: -5,
        ).reason,
        TransformRejectReason.degenerateResizeTarget,
      );
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'image',
          mobility: SnapshotMobility.movable,
          op: LayoutTransformOp.resize,
          resizeTargetHeight: double.nan,
        ).reason,
        TransformRejectReason.degenerateResizeTarget,
      );
      expect(
        SmartLayoutTransformContract.decide(
          kind: 'rectangle',
          mobility: SnapshotMobility.movable,
          op: LayoutTransformOp.resize,
          resizeTargetWidth: 0,
          resizeTargetHeight: 120,
        ).supported,
        isTrue,
        reason: '零尺寸是合法形态（V3-301A 契约）',
      );
    });

    test('传播顺序固定：成员→容器→绑定→索引版本', () {
      expect(SmartLayoutTransformContract.propagationOrder, [
        DependencyRecalcPhase.members,
        DependencyRecalcPhase.containers,
        DependencyRecalcPhase.bindings,
        DependencyRecalcPhase.indexesAndVersion,
      ]);
    });

    test('绑定跟随契约：arrow 跟随，其余几何原语不跟随', () {
      expect(
        SmartLayoutTransformContract.bindingFollowsElement('arrow'),
        isTrue,
      );
      expect(
        SmartLayoutTransformContract.bindingFollowsElement('text'),
        isFalse,
      );
    });
  });

  group('AffineLayoutTransform 数学不变量', () {
    test('identity 不动点', () {
      const t = AffineLayoutTransform.identity();
      expect(t.isIdentity, isTrue);
      expect(t.applyToPoint(12.5, -7.25), (12.5, -7.25));
      expect(
        t.applyToRect(const LayoutRect(left: 1, top: 2, width: 3, height: 4)),
        const LayoutRect(left: 1, top: 2, width: 3, height: 4),
      );
    });

    test('平移逆变换还原', () {
      final t = AffineLayoutTransform.translation(5.5, -3.25);
      final inv = t.invert();
      final p = t.applyToPoint(10, 20);
      expect(inv.applyToPoint(p.$1, p.$2), (10, 20));
    });

    test('绕点旋转：锚点不动 + 逆变换还原 + 保距', () {
      final t = AffineLayoutTransform.rotationAround(3, 4, 0.7);
      final anchor = t.applyToPoint(3, 4);
      expect(anchor.$1, closeTo(3, 1e-9));
      expect(anchor.$2, closeTo(4, 1e-9));
      final p1 = t.applyToPoint(10, 10);
      final p2 = t.applyToPoint(-2, 5);
      final d1 = math.sqrt(math.pow(12, 2) + math.pow(5, 2));
      final d2 = math.sqrt(math.pow(p1.$1 - p2.$1, 2) + math.pow(p1.$2 - p2.$2, 2));
      expect(d2, closeTo(d1, 1e-9), reason: '旋转保距');
      final inv = t.invert();
      expect(inv.applyToPoint(p1.$1, p1.$2).$1, closeTo(10, 1e-9));
      expect(inv.applyToPoint(p1.$1, p1.$2).$2, closeTo(10, 1e-9));
    });

    test('复合应用序：a.compose(b) = 先 b 后 a', () {
      final move = AffineLayoutTransform.translation(10, 0);
      final rotate = AffineLayoutTransform.rotationAround(0, 0, math.pi / 2);
      final combined = rotate.compose(move); // 先移 (1,0)->(11,0)，再旋 90°->(0,11)
      final p = combined.applyToPoint(1, 0);
      expect(p.$1, closeTo(0, 1e-12));
      expect(p.$2, closeTo(11, 1e-12));
    });

    test('复合逆 = 逆的倒序复合', () {
      final a = AffineLayoutTransform.rotationAround(1, 2, 0.4);
      final b = AffineLayoutTransform.translation(-3, 5);
      final inv = a.compose(b).invert();
      final p = a.compose(b).applyToPoint(7, -8);
      final restored = inv.applyToPoint(p.$1, p.$2);
      expect(restored.$1, closeTo(7, 1e-9));
      expect(restored.$2, closeTo(-8, 1e-9));
    });

    test('scaleAround 锚点不动 + 尺寸缩放', () {
      final t = AffineLayoutTransform.scaleAround(0, 0, 2, 3);
      expect(t.applyToPoint(4, 5), (8, 15));
      expect(t.applyToSize(10, 7), (20, 21));
    });

    test('退化矩阵求逆显式失败', () {
      expect(
        () => AffineLayoutTransform.scaleAround(0, 0, 0, 1).invert(),
        throwsStateError,
        reason: '排版变换必须可逆',
      );
    });
  });

  group('TransformInvariant 深一致性 fixtures', () {
    SnapshotBounds b(double l, double t, double w, double h) =>
        SnapshotBounds(left: l, top: t, width: w, height: h);

    SnapshotObject obj(
      String id,
      SnapshotBounds bounds, {
      double rotation = 0,
      List<String> groupIds = const [],
      String? frameId,
      List<String> bindingRefs = const [],
      int zIndex = 0,
      List<String> memberIds = const [],
      SnapshotMobility mobility = SnapshotMobility.movable,
      SnapshotBounds? visual,
    }) => SnapshotObject(
      sourceId: id,
      kind: 'rectangle',
      bounds: bounds,
      visualBounds: visual ?? bounds,
      rotation: rotation,
      mobility: mobility,
      groupIds: groupIds,
      frameId: frameId,
      bindingRefs: bindingRefs,
      zIndex: zIndex,
      memberIds: memberIds,
    );

    test('嵌套组整组移动：全成员同变换零违规', () {
      final old = [
        obj('outer-member-a', b(0, 0, 100, 50), groupIds: const ['g1'], zIndex: 1),
        obj('inner-member-b', b(10, 10, 20, 20), groupIds: const ['g2', 'g1'], zIndex: 2),
        obj('inner-member-c', b(40, 12, 30, 25), groupIds: const ['g2', 'g1'], zIndex: 3),
      ];
      const dx = 25.0, dy = -10.0;
      final moved = [
        for (final o in old)
          obj(
            o.sourceId,
            b(o.bounds.left + dx, o.bounds.top + dy, o.bounds.width, o.bounds.height),
            groupIds: o.groupIds,
            zIndex: o.zIndex,
            visual: b(
              o.visualBounds.left + dx,
              o.visualBounds.top + dy,
              o.visualBounds.width,
              o.visualBounds.height,
            ),
          ),
      ];
      final t = AffineLayoutTransform.translation(dx, dy);
      final violations = TransformInvariant.checkObjects(
        oldObjects: old,
        newObjects: moved,
        expectedTransforms: {
          for (final o in old) o.sourceId: t,
        },
      );
      expect(violations, isEmpty);
    });

    test('漏移一个成员：geometryMismatch 精确命中', () {
      final old = [
        obj('a', b(0, 0, 10, 10), zIndex: 1),
        obj('b', b(100, 0, 10, 10), zIndex: 2),
      ];
      final t = AffineLayoutTransform.translation(50, 0);
      final moved = [
        obj('a', b(50, 0, 10, 10), zIndex: 1),
        obj('b', b(100, 0, 10, 10), zIndex: 2), // 漏移
      ];
      final violations = TransformInvariant.checkObjects(
        oldObjects: old,
        newObjects: moved,
        expectedTransforms: {'a': t, 'b': t},
      );
      expect(
        violations.map((v) => v.kind),
        contains(TransformInvariantKind.geometryMismatch),
      );
      expect(violations.where((v) => v.sourceId == 'b'), isNotEmpty);
      expect(violations.where((v) => v.sourceId == 'a'), isEmpty);
    });

    test('旋转 frame 场景：成员绕 frame 中心协变零违规', () {
      const theta = math.pi / 6;
      // frame 中心 (50, 40)。
      final frameOld = obj('frame-1', b(0, 0, 100, 80), zIndex: 0, memberIds: const ['m1']);
      final m1Old = obj('m1', b(20, 30, 40, 20), frameId: 'frame-1', zIndex: 1);
      final t = AffineLayoutTransform.rotationAround(50, 40, theta);

      SnapshotObject rotateObj(SnapshotObject o) {
        final obb = OrientedShape.fromBounds(o.bounds, o.rotation)
            .rotatedAbout(50, 40, theta);
        return obj(
          o.sourceId,
          obb.rotatedBounds,
          rotation: o.rotation + theta,
          frameId: o.frameId,
          zIndex: o.zIndex,
          memberIds: o.memberIds,
          visual: obb.conservativeAabb,
        );
      }

      final violations = TransformInvariant.checkObjects(
        oldObjects: [frameOld, m1Old],
        newObjects: [rotateObj(frameOld), rotateObj(m1Old)],
        expectedTransforms: {'frame-1': t, 'm1': t},
        rotationDelta: theta,
      );
      expect(violations, isEmpty);
    });

    test('rotation 协变违规命中', () {
      const theta = math.pi / 4;
      final old = [obj('r', b(0, 0, 30, 30), rotation: 0.2)];
      final t = AffineLayoutTransform.rotationAround(15, 15, theta);
      // 几何正确但 rotation 忘记加 θ。
      final obb = OrientedShape.fromBounds(b(0, 0, 30, 30), 0.2)
          .rotatedAbout(15, 15, theta);
      final moved = [
        obj('r', obb.rotatedBounds, rotation: 0.2, visual: obb.conservativeAabb),
      ];
      final violations = TransformInvariant.checkObjects(
        oldObjects: old,
        newObjects: moved,
        expectedTransforms: {'r': t},
        rotationDelta: theta,
      );
      expect(
        violations.map((v) => v.kind),
        contains(TransformInvariantKind.rotationCovarianceViolated),
      );
    });

    test('绑定链：引用保持闭合，断链/悬空命中', () {
      final old = [
        obj('arrow-1', b(0, 30, 100, 10), bindingRefs: const ['note'], zIndex: 2),
        obj('note', b(80, 10, 60, 20), zIndex: 1),
      ];
      final t = AffineLayoutTransform.translation(0, 5);
      SnapshotObject shift(SnapshotObject o) => obj(
        o.sourceId,
        b(o.bounds.left, o.bounds.top + 5, o.bounds.width, o.bounds.height),
        bindingRefs: o.bindingRefs,
        zIndex: o.zIndex,
        visual: b(o.visualBounds.left, o.visualBounds.top + 5, o.visualBounds.width, o.visualBounds.height),
      );

      // 合法：双移 + 引用保持 → 零违规。
      expect(
        TransformInvariant.checkObjects(
          oldObjects: old,
          newObjects: [shift(old[0]), shift(old[1])],
          expectedTransforms: {'arrow-1': t, 'note': t},
        ),
        isEmpty,
      );

      // 断链：arrow 丢引用 → bindingRefBroken。
      final dropped = obj(
        'arrow-1',
        b(0, 35, 100, 10),
        bindingRefs: const [],
        zIndex: 2,
        visual: b(0, 35, 100, 10),
      );
      expect(
        TransformInvariant.checkObjects(
          oldObjects: old,
          newObjects: [dropped, shift(old[1])],
          expectedTransforms: {'arrow-1': t, 'note': t},
        ).map((v) => v.kind),
        contains(TransformInvariantKind.bindingRefBroken),
      );

      // 悬空：引用了不存在的 id → bindingRefBroken。
      final dangling = obj(
        'arrow-1',
        b(0, 35, 100, 10),
        bindingRefs: const ['ghost'],
        zIndex: 2,
        visual: b(0, 35, 100, 10),
      );
      expect(
        TransformInvariant.checkObjects(
          oldObjects: old,
          newObjects: [dangling, shift(old[1])],
          expectedTransforms: {'arrow-1': t, 'note': t},
        ).map((v) => v.kind),
        contains(TransformInvariantKind.bindingRefBroken),
      );
    });

    test('源集合增删与 mobility 变化命中', () {
      final old = [
        obj('a', b(0, 0, 10, 10), zIndex: 1),
        obj('b', b(20, 0, 10, 10), zIndex: 2),
      ];
      const t = AffineLayoutTransform.identity();
      // 增源 + 删源 + mobility 改动 + z 序翻转一次验证。
      final moved = [
        obj('a', b(0, 0, 10, 10), zIndex: 2, mobility: SnapshotMobility.protectedObstacle),
        obj('extra', b(99, 99, 1, 1), zIndex: 3),
      ];
      final kinds = TransformInvariant.checkObjects(
        oldObjects: old,
        newObjects: moved,
        expectedTransforms: {'a': t},
      ).map((v) => v.kind).toSet();
      expect(kinds, contains(TransformInvariantKind.sourceSetChanged));
      expect(kinds, contains(TransformInvariantKind.mobilityChanged));
    });

    test('z 相对序翻转命中', () {
      final old = [
        obj('a', b(0, 0, 10, 10), zIndex: 1),
        obj('b', b(20, 0, 10, 10), zIndex: 2),
      ];
      const t = AffineLayoutTransform.identity();
      final moved = [
        obj('a', b(0, 0, 10, 10), zIndex: 2),
        obj('b', b(20, 0, 10, 10), zIndex: 1),
      ];
      expect(
        TransformInvariant.checkObjects(
          oldObjects: old,
          newObjects: moved,
          expectedTransforms: {'a': t, 'b': t},
        ).map((v) => v.kind),
        contains(TransformInvariantKind.zOrderNotPreserved),
      );
    });

    test('笔迹集合校验：平移零违规、漏移命中', () {
      SnapshotInkStroke stroke(String id, double x) => SnapshotInkStroke(
        sourceId: id,
        bounds: b(x, 0, 100, 20),
        visualBounds: b(x - 2, -2, 104, 24),
        rotation: 0,
        groupIds: const [],
        frameId: null,
        zIndex: 0,
        pointCount: 3,
        hasPressures: true,
      );
      final old = [stroke('s1', 0), stroke('s2', 200)];
      final t = AffineLayoutTransform.translation(10, 0);
      final moved = [
        SnapshotInkStroke(
          sourceId: 's1',
          bounds: b(10, 0, 100, 20),
          visualBounds: b(8, -2, 104, 24),
          rotation: 0,
          groupIds: const [],
          frameId: null,
          zIndex: 0,
          pointCount: 3,
          hasPressures: true,
        ),
        stroke('s2', 200), // 漏移
      ];
      final violations = TransformInvariant.checkInkStrokes(
        oldStrokes: old,
        newStrokes: moved,
        expectedTransforms: {'s1': t, 's2': t},
      );
      expect(
        violations.map((v) => v.kind),
        contains(TransformInvariantKind.geometryMismatch),
      );
      expect(violations.where((v) => v.sourceId == 's2'), isNotEmpty);
    });
  });
}

/// 测试 fixture helper：OBB 形状的旋转重建（bounds 中心绕外部点旋转，
/// 半宽高不变，rotation 累加）。
class OrientedShape {
  OrientedShape({
    required this.centerX,
    required this.centerY,
    required this.halfWidth,
    required this.halfHeight,
    required this.rotation,
  });

  factory OrientedShape.fromBounds(SnapshotBounds bounds, double rotation) =>
      OrientedShape(
        centerX: bounds.left + bounds.width / 2,
        centerY: bounds.top + bounds.height / 2,
        halfWidth: bounds.width / 2,
        halfHeight: bounds.height / 2,
        rotation: rotation,
      );

  final double centerX;
  final double centerY;
  final double halfWidth;
  final double halfHeight;
  final double rotation;

  /// 中心绕 (cx, cy) 旋转 θ，自身朝向累加 θ。
  OrientedShape rotatedAbout(double cx, double cy, double theta) {
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    final dx = centerX - cx;
    final dy = centerY - cy;
    return OrientedShape(
      centerX: cx + dx * cosT - dy * sinT,
      centerY: cy + dx * sinT + dy * cosT,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      rotation: rotation + theta,
    );
  }

  /// 未旋转语义 bounds（x,y = 中心减半宽高）。
  SnapshotBounds get rotatedBounds => SnapshotBounds(
    left: centerX - halfWidth,
    top: centerY - halfHeight,
    width: halfWidth * 2,
    height: halfHeight * 2,
  );

  /// OBB 四角的外包盒（visualBounds 语义）。
  SnapshotBounds get conservativeAabb {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (dx, dy) in [
      (-halfWidth, -halfHeight),
      (halfWidth, -halfHeight),
      (halfWidth, halfHeight),
      (-halfWidth, halfHeight),
    ]) {
      final x = centerX + dx * cosR - dy * sinR;
      final y = centerY + dx * sinR + dy * cosR;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return SnapshotBounds(
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }
}
