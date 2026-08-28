import 'dart:math' as math;
import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';

/// 只供测试使用的笔迹轮廓几何指标（Issue #5 T0）。
///
/// 与具体渲染实现解耦：直接测量 perfect_freehand 输出的闭合多边形，
/// 不复刻包内半径公式，避免实现调参时指标随之"恒真"。
class BrushOutlineMetrics {
  const BrushOutlineMetrics({
    required this.bounds,
    required this.area,
    required this.pointCount,
  });

  /// 轮廓包围盒（逻辑像素）。
  final Rect bounds;

  /// 鞋带公式绝对面积（逻辑像素²）。
  final double area;

  final int pointCount;

  bool get isFinite =>
      bounds.left.isFinite &&
      bounds.top.isFinite &&
      bounds.right.isFinite &&
      bounds.bottom.isFinite &&
      area.isFinite;

  static BrushOutlineMetrics measure(List<Offset> outline) {
    if (outline.isEmpty) {
      return const BrushOutlineMetrics(
        bounds: Rect.zero,
        area: 0,
        pointCount: 0,
      );
    }
    var minX = outline.first.dx;
    var minY = outline.first.dy;
    var maxX = outline.first.dx;
    var maxY = outline.first.dy;
    var twiceArea = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final q = outline[(i + 1) % outline.length];
      twiceArea += p.dx * q.dy - q.dx * p.dy;
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return BrushOutlineMetrics(
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
      area: twiceArea.abs() / 2,
      pointCount: outline.length,
    );
  }

  /// 沿原始折线弧长比例 [t]（0~1）处的局部线宽。
  ///
  /// 做法：取折线上弧长 t 处的点与切线，用垂直于切线的直线切割轮廓
  /// 多边形，收集交点在切割线上的参数，取极差为宽度。与包内半径公式
  /// 无关，避免恒真。
  static double widthAtArc(
    List<Point> polyline,
    List<Offset> outline,
    double t,
  ) {
    if (polyline.length < 2 || outline.length < 3) return 0;
    final target = _pointAtArcFraction(polyline, t);
    final tangent = _tangentAtArcFraction(polyline, t);
    final nx = -tangent.y;
    final ny = tangent.x;
    final nLen = math.sqrt(nx * nx + ny * ny);
    if (nLen < 1e-9) return 0;
    final dx = nx / nLen;
    final dy = ny / nLen;

    var minS = double.infinity;
    var maxS = double.negativeInfinity;
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      // 解 target + s*d = a + u*e（e = b-a）：
      //   det = ex*dy - ey*dx
      //   u = (dx*ry - dy*rx)/det，s = (ex*ry - ey*rx)/det，其中 r = a-target
      final ex = b.dx - a.dx;
      final ey = b.dy - a.dy;
      final denom = ex * dy - ey * dx;
      if (denom.abs() < 1e-12) continue;
      final rx = a.dx - target.x;
      final ry = a.dy - target.y;
      final u = (dx * ry - dy * rx) / denom;
      if (u < 0.0 || u > 1.0) continue;
      final s = (ex * ry - ey * rx) / denom;
      if (s < minS) minS = s;
      if (s > maxS) maxS = s;
    }
    if (minS == double.infinity) return 0;
    return maxS - minS;
  }

  /// 在 [fractions] 各弧长比例处采样局部宽度。
  static List<double> widthsAtArcSamples(
    List<Point> polyline,
    List<Offset> outline,
    List<double> fractions,
  ) {
    return [for (final t in fractions) widthAtArc(polyline, outline, t)];
  }

  /// 采样最大局部宽度（A2/A3 差异断言用）。
  static double maxWidthAtSamples(
    List<Point> polyline,
    List<Offset> outline, {
    int sampleCount = 11,
  }) {
    var max = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final w = widthAtArc(polyline, outline, i / (sampleCount - 1));
      if (w > max) max = w;
    }
    return max;
  }

  static Point _pointAtArcFraction(List<Point> polyline, double t) {
    final total = _polylineLength(polyline);
    final want = total * t.clamp(0.0, 1.0);
    var acc = 0.0;
    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final seg = math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
      );
      if (acc + seg >= want || i == polyline.length - 2) {
        final u = seg <= 0 ? 0.0 : ((want - acc) / seg).clamp(0.0, 1.0);
        return Point(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u);
      }
      acc += seg;
    }
    return polyline.last;
  }

  static Point _tangentAtArcFraction(List<Point> polyline, double t) {
    final p = _pointAtArcFraction(polyline, t);
    final q = _pointAtArcFraction(polyline, (t + 0.02).clamp(0.0, 1.0));
    final r = _pointAtArcFraction(polyline, (t - 0.02).clamp(0.0, 1.0));
    return Point(q.x - r.x, q.y - r.y);
  }

  static double _polylineLength(List<Point> polyline) {
    var total = 0.0;
    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      total += math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    }
    return total;
  }
}
