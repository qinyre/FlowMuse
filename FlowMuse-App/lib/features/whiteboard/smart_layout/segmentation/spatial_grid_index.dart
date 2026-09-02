import 'dart:math' as math;

/// 笔画轴对齐盒（分割内部几何形态，避免依赖 editor_core Bounds）。
class StrokeBox {
  const StrokeBox({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String id;
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get size => math.max(width, height);

  /// 两盒欧氏间隙（相交为 0）。
  double gapTo(StrokeBox other) {
    final dx = left > other.right
        ? left - other.right
        : other.left > right
        ? other.left - right
        : 0.0;
    final dy = top > other.bottom
        ? top - other.bottom
        : other.top > bottom
        ? other.top - bottom
        : 0.0;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// 均匀网格空间索引：O(1) 定位 + 半径查询只访问邻近 cell，
/// 保证 3000 笔画页不做 O(N²) 全配对（计划 §4.3 硬约束）。
///
/// [evaluationCount] 记录累计的候选盒距离评估次数，供测试断言
/// 线性-ish 上界（确定性，不依赖墙上时钟）。
class SpatialGridIndex {
  SpatialGridIndex({required this.cellSize, required List<StrokeBox> boxes})
    : assert(cellSize > 0) {
    for (final box in boxes) {
      _cell(keyFor(box.left, box.top, cellSize)).add(box);
      _cell(keyFor(box.right, box.bottom, cellSize)).add(box);
      _cell(keyFor(box.left, box.bottom, cellSize)).add(box);
      _cell(keyFor(box.right, box.top, cellSize)).add(box);
    }
    // 每个 box 可能落进多个 cell，去重交给查询侧 seen 集合；
    // 插入成本 O(N)。
    _allBoxes = List.unmodifiable(boxes);
  }

  final double cellSize;
  late final List<StrokeBox> _allBoxes;
  final Map<String, List<StrokeBox>> _cells = {};

  /// 候选距离评估计数（只增不减；测试性能断言依据）。
  int evaluationCount = 0;

  static (int, int) keyFor(double x, double y, double cellSize) =>
      (x ~/ cellSize, y ~/ cellSize);

  List<StrokeBox> _cell((int, int) key) =>
      _cells.putIfAbsent('${key.$1}:${key.$2}', () => <StrokeBox>[]);

  /// 半径邻接查询：返回与 [box] 的间隙 ≤ [radius] 的其他盒
  ///（按 id 排序，确定性）。
  List<StrokeBox> neighborsWithin(StrokeBox box, double radius) {
    final minKey = keyFor(box.left - radius, box.top - radius, cellSize);
    final maxKey = keyFor(box.right + radius, box.bottom + radius, cellSize);
    final seen = <String>{};
    final result = <StrokeBox>[];
    for (var cx = minKey.$1; cx <= maxKey.$1; cx++) {
      for (var cy = minKey.$2; cy <= maxKey.$2; cy++) {
        final cell = _cells['$cx:$cy'];
        if (cell == null) continue;
        for (final candidate in cell) {
          if (candidate.id == box.id || !seen.add(candidate.id)) continue;
          evaluationCount++;
          if (box.gapTo(candidate) <= radius) {
            result.add(candidate);
          }
        }
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// 全部盒（构建顺序保留）。
  List<StrokeBox> get allBoxes => _allBoxes;
}

/// 简单加权并查集（连通分量）。
class UnionFind {
  UnionFind(int n) : _parent = List<int>.generate(n, (i) => i);

  final List<int> _parent;

  int find(int x) {
    while (_parent[x] != x) {
      _parent[x] = _parent[_parent[x]];
      x = _parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _parent[ra] = rb;
  }
}
