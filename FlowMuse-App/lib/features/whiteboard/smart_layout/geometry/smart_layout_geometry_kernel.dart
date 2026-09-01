import 'dart:math' as math;

import 'layout_insets.dart';
import 'layout_obstacle.dart';
import 'layout_rect.dart';
import 'oriented_layout_rect.dart';

/// 智能排版 feature-local 几何内核（V3-301A）。
///
/// 只服务 smart_layout 排版链路（障碍绕置、页界 contain、placement
/// 碰撞查询、metrics 几何断言），是 [snapshot] bounds/helper 之上的
/// 薄判定层：不替换 editor_core 全局几何、不迁移既有调用者、不导出
/// 通用 kernel（架构 §"GeometryKernel"）。全部纯函数；空间查询经
/// [LayoutObstacleIndex]（网格索引，3000 笔画/100 块预算见类注释）。
class SmartLayoutGeometryKernel {
  const SmartLayoutGeometryKernel._();

  /// 统一浮点容差：页界/相交判定按闭盒 + 1e-9，方向恒为保守
  /// （更易判交/更易判含），零漏检。
  static const double epsilon = OrientedLayoutRect.epsilon;

  // ---- AABB 原语判定 ----

  static bool aabbIntersects(LayoutRect a, LayoutRect b) =>
      a.intersects(b);

  static bool aabbContains(LayoutRect outer, LayoutRect inner) =>
      outer.containsRect(inner);

  /// 轴向欧氏间隙（相交为 0）。OBB 真实距离的下界，判定
  /// "间距 ≥ 要求"方向安全。
  static double gapBetween(LayoutRect a, LayoutRect b) => a.gapTo(b);

  // ---- OBB 判定 ----

  /// 分离轴定理精判（零漏检；近分离保守判交，见
  /// [OrientedLayoutRect.intersects]）。
  static bool obbIntersects(
    OrientedLayoutRect a,
    OrientedLayoutRect b,
  ) => a.intersects(b);

  /// OBB 形态与 AABB 候选盒相交：候选按轴对齐 OBB 参与 SAT
  /// （零尺寸候选退化为线段/点判定）。
  static bool obbIntersectsRect(
    OrientedLayoutRect obb,
    LayoutRect rect,
  ) => obb.intersects(rect.orientedAboutCenter(0));

  // ---- 页界 contain ----

  /// [candidate] 是否完全位于 page 扣除 [insets] 的内容区（含边界，
  /// 容差 [tolerance]）。
  static bool pageContainsRect({
    required LayoutRect page,
    LayoutInsets insets = const LayoutInsets.zero(),
    required LayoutRect candidate,
    double tolerance = epsilon,
  }) {
    final content = insets.isZero ? page : page.deflateInsets(insets);
    return content.inflate(tolerance).containsRect(candidate);
  }

  // ---- 保护对象线性判定（小规模/单点检查） ----

  /// 候选盒是否与任一障碍的保守 AABB 相交（含嵌套与零尺寸）。
  static bool overlapsAnyObstacleAabb(
    LayoutRect candidate,
    Iterable<LayoutObstacle> obstacles,
  ) {
    for (final obstacle in obstacles) {
      if (candidate.intersects(obstacle.conservativeBounds)) return true;
    }
    return false;
  }

  /// 候选盒是否与任一障碍的 OBB 精确相交。
  static bool overlapsAnyObstacleObb(
    LayoutRect candidate,
    Iterable<LayoutObstacle> obstacles,
  ) {
    final candidateObb = candidate.orientedAboutCenter(0);
    for (final obstacle in obstacles) {
      if (candidateObb.intersects(obstacle.obb)) return true;
    }
    return false;
  }

  /// 构建障碍空间索引（大规模查询入口）。
  static LayoutObstacleIndex buildIndex(
    Iterable<LayoutObstacle> obstacles, {
    double? cellSize,
  }) => LayoutObstacleIndex(obstacles: obstacles, cellSize: cellSize);
}

/// 均匀网格障碍索引：插入覆盖盒跨越的全部 cell（不是只插四角——
/// 只插四角在查询盒落在障碍中部 cell 时会漏检），查询按扩展范围访问，
/// 保证零漏检；[evaluationCount] 供确定性预算断言（不依赖墙上时钟）。
///
/// 预算依据（计划 §"3000 笔画/100 块"）：cellSize 默认取障碍最大边，
/// 每障碍至多跨 (w/c+1)×(h/c+1) 个 cell；均匀分布下单查询只触碰邻域
/// cell，总评估次线性于 N×Q。
class LayoutObstacleIndex {
  LayoutObstacleIndex({
    required Iterable<LayoutObstacle> obstacles,
    double? cellSize,
  }) {
    // 先物化：lazy iterable 只遍历一次，默认 cellSize 与插入共用同一份。
    final materialized = obstacles.toList();
    this.cellSize = cellSize ?? _defaultCellSize(materialized);
    for (final obstacle in materialized) {
      final b = obstacle.conservativeBounds;
      final minX = _key(b.left);
      final maxX = _key(b.right);
      final minY = _key(b.top);
      final maxY = _key(b.bottom);
      for (var cx = minX; cx <= maxX; cx++) {
        for (var cy = minY; cy <= maxY; cy++) {
          _cells.putIfAbsent((cx, cy), () => <LayoutObstacle>[]).add(
            obstacle,
          );
        }
      }
      _all.add(obstacle);
    }
    _all.sort((a, b) => a.id.compareTo(b.id));
  }

  /// cellSize 下限：退化/零尺寸障碍必须映射到确定 cell。
  static const double _minCellSize = 1.0;

  static double _defaultCellSize(Iterable<LayoutObstacle> obstacles) {
    var maxEdge = 0.0;
    for (final o in obstacles) {
      final b = o.conservativeBounds;
      if (b.width > maxEdge) maxEdge = b.width;
      if (b.height > maxEdge) maxEdge = b.height;
    }
    if (!maxEdge.isFinite || maxEdge <= 0) return _minCellSize;
    return math.max(maxEdge, _minCellSize);
  }

  late final double cellSize;
  final List<LayoutObstacle> _all = [];
  final Map<(int, int), List<LayoutObstacle>> _cells = {};

  /// 累计候选距离评估次数（含 SAT 精判；只增不减；预算断言依据）。
  int evaluationCount = 0;

  /// 截断除法映射坐标到 cell 列；截断 vs floor 的差异只改变 cell
  /// 划分形状，零漏检由插入全覆盖 + 查询范围扩展保证。
  int _key(double v) => v ~/ cellSize;

  (int, int, int, int) _cellRange(LayoutRect rect, double expand) {
    final minX = _key(rect.left - expand);
    final maxX = _key(rect.right + expand);
    final minY = _key(rect.top - expand);
    final maxY = _key(rect.bottom + expand);
    return (minX, minY, maxX, maxY);
  }

  /// 与 [rect]（闭盒，含零尺寸）保守 AABB 相交的全部障碍（按 id 排序）。
  List<LayoutObstacle> queryIntersecting(LayoutRect rect) {
    final (minX, minY, maxX, maxY) = _cellRange(rect, 0);
    return _collect(
      minX,
      minY,
      maxX,
      maxY,
      (obstacle) => rect.intersects(obstacle.conservativeBounds),
    );
  }

  /// 与 [obb] 精确相交的障碍（保守盒预筛零漏检 + SAT 精判）。
  List<LayoutObstacle> queryIntersectingObb(OrientedLayoutRect obb) {
    final pre = queryIntersecting(obb.toConservativeAabb());
    final result = <LayoutObstacle>[];
    for (final obstacle in pre) {
      evaluationCount++;
      if (obb.intersects(obstacle.obb)) result.add(obstacle);
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// 间隙 ≤ [radius] 的障碍（保守 AABB 间隙，真实 OBB 距离下界）。
  List<LayoutObstacle> queryWithinGap(LayoutRect rect, double radius) {
    assert(radius >= 0);
    final (minX, minY, maxX, maxY) = _cellRange(rect, radius);
    return _collect(
      minX,
      minY,
      maxX,
      maxY,
      (obstacle) => rect.gapTo(obstacle.conservativeBounds) <= radius,
    );
  }

  List<LayoutObstacle> _collect(
    int minX,
    int minY,
    int maxX,
    int maxY,
    bool Function(LayoutObstacle) predicate,
  ) {
    final seen = <String>{};
    final result = <LayoutObstacle>[];
    for (var cx = minX; cx <= maxX; cx++) {
      for (var cy = minY; cy <= maxY; cy++) {
        final cell = _cells[(cx, cy)];
        if (cell == null) continue;
        for (final obstacle in cell) {
          if (!seen.add(obstacle.id)) continue;
          evaluationCount++;
          if (predicate(obstacle)) result.add(obstacle);
        }
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// 全部障碍（按 id 排序；确定性）。
  List<LayoutObstacle> get all => List.unmodifiable(_all);

  int get length => _all.length;
}
