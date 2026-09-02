import '../snapshot/layout_page_snapshot.dart';
import 'layout_rect.dart';
import 'oriented_layout_rect.dart';

/// 保护对象/障碍几何投影（V3-301A）。
///
/// 双形态持有：
/// - [conservativeBounds]：快照 [SnapshotObject.visualBounds]/
///   [SnapshotInkStroke.visualBounds]（含笔刷包络与旋转外扩的保守 AABB），
///   是空间索引与零漏检预筛的唯一依据；
/// - [obb]：元素未旋转 [SnapshotObject.bounds] 绕中心旋转的精确 OBB
///   （笔迹不旋转，直接取 visualBounds 本身），供 SAT 精判。
/// 不变量：obb ⊆ conservativeBounds（构造时断言防回归）。
class LayoutObstacle {
  LayoutObstacle({
    required this.id,
    required this.conservativeBounds,
    required this.obb,
  }) : assert(
         _isCovered(conservativeBounds, obb),
         'obb must stay inside conservativeBounds',
       );

  /// 从快照对象投影：visualBounds 做保守盒，原始 bounds 绕中心旋转做 OBB。
  factory LayoutObstacle.fromSnapshotObject(SnapshotObject object) {
    final conservative = LayoutRect.fromSnapshotBounds(
      object.visualBounds,
    );
    final obb = OrientedLayoutRect.fromRect(
      LayoutRect.fromSnapshotBounds(object.bounds),
      object.rotation,
    );
    return LayoutObstacle(
      id: object.sourceId,
      conservativeBounds: conservative,
      obb: obb,
    );
  }

  /// 从笔迹投影：笔画无旋转，visualBounds（含笔刷包络）即精确形态。
  factory LayoutObstacle.fromSnapshotInkStroke(SnapshotInkStroke stroke) {
    final bounds = LayoutRect.fromSnapshotBounds(stroke.visualBounds);
    return LayoutObstacle(
      id: stroke.sourceId,
      conservativeBounds: bounds,
      obb: OrientedLayoutRect.fromRect(bounds, 0),
    );
  }

  /// 容差：快照侧 conservativeVisualBounds 与本处 OBB 四角是两条浮点
  /// 计算路径，ulp 级抖动不得触发断言；1e-9 对零漏检语义无实际影响。
  static const _coverEpsilon = 1e-9;

  static bool _isCovered(LayoutRect aabb, OrientedLayoutRect obb) {
    final obbAabb = obb.toConservativeAabb();
    return aabb.inflate(_coverEpsilon).containsRect(obbAabb);
  }

  final String id;

  /// 保守 AABB（索引键；零漏检保证的来源）。
  final LayoutRect conservativeBounds;

  /// 精确 OBB（SAT 精判用）。
  final OrientedLayoutRect obb;

  /// 保守 AABB 相交（预筛语义；允许假阳性）。
  bool aabbIntersects(LayoutObstacle other) =>
      conservativeBounds.intersects(other.conservativeBounds);

  /// OBB SAT 相交（精判语义；零漏检、近分离保守判交）。
  bool obbIntersects(LayoutObstacle other) => obb.intersects(other.obb);

  @override
  String toString() =>
      'LayoutObstacle($id, ${conservativeBounds.toString()})';
}
