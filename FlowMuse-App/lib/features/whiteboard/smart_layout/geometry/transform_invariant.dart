import '../snapshot/layout_page_snapshot.dart';
import 'affine_layout_transform.dart';
import 'layout_rect.dart';

/// 变换不变量违规类型（V3-302A；V3-303A 的执行结果必须零违规）。
enum TransformInvariantKind {
  /// 源集合增删：变换不得创建/删除源对象。
  sourceSetChanged,

  /// mobility 三态不得变化。
  mobilityChanged,

  /// groupIds 成员关系不得变化。
  groupMembershipChanged,

  /// frameId / frame memberIds 不得变化。
  frameMembershipChanged,

  /// bindingRefs 悬空（引用不存在的源）或集合变化。
  bindingRefBroken,

  /// zIndex 相对序必须保持。
  zOrderNotPreserved,

  /// visualBounds 与期望变换不符（含笔刷包络/旋转外扩语义）。
  geometryMismatch,

  /// rotate 场景成员 rotation 未按 Δθ 协变。
  rotationCovarianceViolated,
}

class TransformInvariantViolation {
  const TransformInvariantViolation({
    required this.kind,
    required this.sourceId,
    this.detail = '',
  });

  final TransformInvariantKind kind;
  final String sourceId;
  final String detail;

  @override
  String toString() => '${kind.name}($sourceId${detail.isEmpty ? '' : ': $detail'})';
}

/// old/new 快照深一致性校验器（V3-302A 契约；纯函数）。
///
/// 期望几何语义：元素视觉形状是 OBB(bounds, rotation)（笔迹为含包络
/// 的 visualBounds，rotation 恒 0）；变换 T 后期望 visualBounds =
/// T 作用于该形状四角的外包 AABB——与快照 conservativeVisualBounds
/// 同语义，任意仿射下闭式精确。旋转场景另校验 rotation 按
/// [rotationDelta] 协变。
class TransformInvariant {
  const TransformInvariant._();

  static const double defaultTolerance = 1e-6;

  /// 校验对象投影集合（objects；inkStrokes 走 [checkInkStrokes]）。
  static List<TransformInvariantViolation> checkObjects({
    required List<SnapshotObject> oldObjects,
    required List<SnapshotObject> newObjects,
    required Map<String, AffineLayoutTransform> expectedTransforms,
    double rotationDelta = 0,
    double tolerance = defaultTolerance,
  }) {
    final violations = <TransformInvariantViolation>[];
    final oldById = {
      for (final o in oldObjects) o.sourceId: o,
    };
    final newById = {
      for (final o in newObjects) o.sourceId: o,
    };
    _checkSourceSet(oldById.keys, newById.keys, violations);
    _checkRelations(oldById, newById, violations);

    // z 序相对序保持（排序 id 序列不变）。
    final oldOrder = (oldById.values.toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex)))
        .map((o) => o.sourceId)
        .toList();
    final newOrder = (newById.values.toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex)))
        .map((o) => o.sourceId)
        .toList();
    if (oldOrder.length == newOrder.length &&
        !_equalIdSeq(oldOrder, newOrder)) {
      violations.add(TransformInvariantViolation(
        kind: TransformInvariantKind.zOrderNotPreserved,
        sourceId: '*',
        detail: 'relative z order changed: $oldOrder -> $newOrder',
      ));
    }

    for (final entry in oldById.entries) {
      final old = entry.value;
      final moved = newById[entry.key];
      if (moved == null) continue;
      final transform = expectedTransforms[entry.key];
      if (transform == null) continue;

      final expectedVisual = _expectedVisualBounds(
        LayoutRect.fromSnapshotBounds(old.bounds),
        old.rotation,
        transform,
      );
      final actualVisual = LayoutRect.fromSnapshotBounds(moved.visualBounds);
      if (!_rectClose(expectedVisual, actualVisual, tolerance)) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.geometryMismatch,
          sourceId: entry.key,
          detail:
              'expected ${expectedVisual.toString()} got ${actualVisual.toString()}',
        ));
      }
      if (rotationDelta != 0) {
        final expectedRotation = old.rotation + rotationDelta;
        if ((moved.rotation - expectedRotation).abs() > tolerance) {
          violations.add(TransformInvariantViolation(
            kind: TransformInvariantKind.rotationCovarianceViolated,
            sourceId: entry.key,
            detail:
                'expected ${expectedRotation.toStringAsFixed(9)} got ${moved.rotation.toStringAsFixed(9)}',
          ));
        }
      }
    }
    return violations;
  }

  /// 校验笔迹投影集合（视觉形状 = visualBounds 本身，不旋转）。
  static List<TransformInvariantViolation> checkInkStrokes({
    required List<SnapshotInkStroke> oldStrokes,
    required List<SnapshotInkStroke> newStrokes,
    required Map<String, AffineLayoutTransform> expectedTransforms,
    double tolerance = defaultTolerance,
  }) {
    final violations = <TransformInvariantViolation>[];
    final oldById = {
      for (final s in oldStrokes) s.sourceId: s,
    };
    final newById = {
      for (final s in newStrokes) s.sourceId: s,
    };
    _checkSourceSet(oldById.keys, newById.keys, violations);
    for (final entry in oldById.entries) {
      final moved = newById[entry.key];
      final transform = expectedTransforms[entry.key];
      if (moved == null || transform == null) continue;
      final expected = _expectedVisualBounds(
        LayoutRect.fromSnapshotBounds(entry.value.visualBounds),
        0,
        transform,
      );
      final actual = LayoutRect.fromSnapshotBounds(moved.visualBounds);
      if (!_rectClose(expected, actual, tolerance)) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.geometryMismatch,
          sourceId: entry.key,
          detail:
              'expected ${expected.toString()} got ${actual.toString()}',
        ));
      }
    }
    return violations;
  }

  static void _checkSourceSet(
    Iterable<String> oldIds,
    Iterable<String> newIds,
    List<TransformInvariantViolation> violations,
  ) {
    final oldSet = oldIds.toSet();
    final newSet = newIds.toSet();
    for (final removed in oldSet.difference(newSet)) {
      violations.add(TransformInvariantViolation(
        kind: TransformInvariantKind.sourceSetChanged,
        sourceId: removed,
        detail: 'source removed by transform',
      ));
    }
    for (final added in newSet.difference(oldSet)) {
      violations.add(TransformInvariantViolation(
        kind: TransformInvariantKind.sourceSetChanged,
        sourceId: added,
        detail: 'source created by transform',
      ));
    }
  }

  static void _checkRelations(
    Map<String, SnapshotObject> oldById,
    Map<String, SnapshotObject> newById,
    List<TransformInvariantViolation> violations,
  ) {
    final allNewIds = newById.keys.toSet();
    for (final entry in oldById.entries) {
      final old = entry.value;
      final moved = newById[entry.key];
      if (moved == null) continue;
      if (moved.mobility != old.mobility) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.mobilityChanged,
          sourceId: entry.key,
          detail: '${old.mobility.name} -> ${moved.mobility.name}',
        ));
      }
      if (!_sameSeq(old.groupIds, moved.groupIds)) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.groupMembershipChanged,
          sourceId: entry.key,
          detail: '${old.groupIds} -> ${moved.groupIds}',
        ));
      }
      if (old.frameId != moved.frameId) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.frameMembershipChanged,
          sourceId: entry.key,
          detail: '${old.frameId} -> ${moved.frameId}',
        ));
      }
      if (!_sameSeq(old.bindingRefs, moved.bindingRefs)) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.bindingRefBroken,
          sourceId: entry.key,
          detail: '${old.bindingRefs} -> ${moved.bindingRefs}',
        ));
      } else {
        for (final ref in moved.bindingRefs) {
          if (!allNewIds.contains(ref)) {
            violations.add(TransformInvariantViolation(
              kind: TransformInvariantKind.bindingRefBroken,
              sourceId: entry.key,
              detail: 'dangling ref $ref',
            ));
          }
        }
      }
      if (!_sameSeq(old.memberIds, moved.memberIds)) {
        violations.add(TransformInvariantViolation(
          kind: TransformInvariantKind.frameMembershipChanged,
          sourceId: entry.key,
          detail: 'frame members ${old.memberIds} -> ${moved.memberIds}',
        ));
      }
    }
  }

  /// 期望视觉外包：形状 OBB(或笔迹含包络盒) 四角过仿射后的 AABB。
  /// 必须直接变换 OBB 四角——先外扩再变换会把旋转二次叠加。
  static LayoutRect _expectedVisualBounds(
    LayoutRect shapeBounds,
    double rotation,
    AffineLayoutTransform transform,
  ) {
    final obb = shapeBounds.orientedAboutCenter(rotation);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final (x, y) in obb.corners()) {
      final (tx, ty) = transform.applyToPoint(x, y);
      if (tx < minX) minX = tx;
      if (tx > maxX) maxX = tx;
      if (ty < minY) minY = ty;
      if (ty > maxY) maxY = ty;
    }
    return LayoutRect(
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  static bool _rectClose(LayoutRect a, LayoutRect b, double tolerance) =>
      (a.left - b.left).abs() <= tolerance &&
      (a.top - b.top).abs() <= tolerance &&
      (a.width - b.width).abs() <= tolerance &&
      (a.height - b.height).abs() <= tolerance;

  static bool _sameSeq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _equalIdSeq(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
