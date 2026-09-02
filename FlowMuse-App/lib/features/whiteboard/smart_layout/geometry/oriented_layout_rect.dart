import 'dart:math' as math;

import 'layout_rect.dart';

/// 旋转矩形（OBB）：中心 + 半宽高 + 弧度旋转（V3-301A）。
///
/// 相交判定用分离轴定理（两盒各自 2 条边法线共 4 轴）。浮点 epsilon
/// 只向"更易相交"方向偏置（分离距离必须严格大于半径和 + eps 才判分离），
/// 保证数学相交对零漏检；近分离的边界情形按相交处理（保守方向）。
class OrientedLayoutRect {
  const OrientedLayoutRect({
    required this.centerX,
    required this.centerY,
    required this.halfWidth,
    required this.halfHeight,
    this.rotation = 0,
  });

  /// 绕 [rect] 中心旋转 [rotation] 弧度。
  factory OrientedLayoutRect.fromRect(
    LayoutRect rect,
    double rotation,
  ) => OrientedLayoutRect(
    centerX: rect.centerX,
    centerY: rect.centerY,
    halfWidth: rect.width / 2,
    halfHeight: rect.height / 2,
    rotation: rotation,
  );

  /// 智能排版统一相交浮点容差（10^-9 量级，闭盒语义）。
  static const double epsilon = 1e-9;

  final double centerX;
  final double centerY;
  final double halfWidth;
  final double halfHeight;
  final double rotation;

  bool get isAxisAligned =>
      rotation == 0 ||
      (rotation % math.pi).abs() < epsilon ||
      (rotation % math.pi - math.pi).abs() < epsilon;

  /// 旋转后四角（左上、右上、左下、右下；确定性顺序）。
  List<(double, double)> corners() {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final xs = [-halfWidth, halfWidth];
    final ys = [-halfHeight, halfHeight];
    final result = <(double, double)>[];
    for (final dy in ys) {
      for (final dx in xs) {
        result.add((
          centerX + dx * cosR - dy * sinR,
          centerY + dx * sinR + dy * cosR,
        ));
      }
    }
    return result;
  }

  /// 保守 AABB（四角外包）。恒 ⊇ OBB 本体，作空间索引键零漏检。
  LayoutRect toConservativeAabb() {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final (x, y) in corners()) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return LayoutRect(
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  /// SAT 相交。与 [epsilon] 比较保证零漏检（见类注释）。
  bool intersects(OrientedLayoutRect other) {
    // 快路径：双方轴对齐时退化为 AABB 判定（含零尺寸形态）。
    if (isAxisAligned && other.isAxisAligned) {
      return toConservativeAabb().intersects(
        other.toConservativeAabb(),
      );
    }
    final axes = _candidateAxes(other);
    for (final axis in axes) {
      final ax = math.cos(axis);
      final ay = math.sin(axis);
      final r1 = projectionRadius(ax, ay);
      final r2 = other.projectionRadius(ax, ay);
      final dx = other.centerX - centerX;
      final dy = other.centerY - centerY;
      final dist = (dx * ax + dy * ay).abs();
      if (dist > r1 + r2 + epsilon) return false;
    }
    return true;
  }

  List<double> _candidateAxes(OrientedLayoutRect other) => [
    rotation,
    rotation + math.pi / 2,
    other.rotation,
    other.rotation + math.pi / 2,
  ];

  /// 本盒在单位轴 (ax, ay) 上的投影半径。
  double projectionRadius(double ax, double ay) =>
      halfWidth * (ax * math.cos(rotation) + ay * math.sin(rotation)).abs() +
      halfHeight *
          (-ax * math.sin(rotation) + ay * math.cos(rotation)).abs();

  @override
  bool operator ==(Object other) =>
      other is OrientedLayoutRect &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.halfWidth == halfWidth &&
      other.halfHeight == halfHeight &&
      other.rotation == rotation;

  @override
  int get hashCode =>
      Object.hash(centerX, centerY, halfWidth, halfHeight, rotation);

  @override
  String toString() =>
      'OrientedLayoutRect(c $centerX,$centerY, hw $halfWidth, hh '
      '$halfHeight, rot $rotation)';
}
