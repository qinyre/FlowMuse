import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../snapshot/layout_page_snapshot.dart';
import 'layout_insets.dart';
import 'oriented_layout_rect.dart';

/// 智能排版 feature 内部 AABB 原语（V3-301A）。
///
/// 零尺寸（宽或高为 0 的线段/点）是合法形态：闭盒语义下接触即相交，
/// 不允许因退化维度漏报。值语义（==/hashCode 含全部四分量）。
class LayoutRect {
  const LayoutRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// 从快照边界投影（复用 V3-102A 的 [SnapshotBounds]，不自建第二套）。
  factory LayoutRect.fromSnapshotBounds(SnapshotBounds bounds) => LayoutRect(
    left: bounds.left,
    top: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );

  /// 两点（任意对角）确定的盒，负尺寸归零。
  factory LayoutRect.fromPoints(
    double ax,
    double ay,
    double bx,
    double by,
  ) => LayoutRect(
    left: math.min(ax, bx),
    top: math.min(ay, by),
    width: (bx - ax).abs(),
    height: (by - ay).abs(),
  );

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  /// 宽或高为 0（点/线段形态）。
  bool get isDegenerate => width <= 0 || height <= 0;

  /// 闭盒相交：共享边/角即相交（保守方向，零漏检）。
  bool intersects(LayoutRect other) =>
      left <= other.right &&
      other.left <= right &&
      top <= other.bottom &&
      other.top <= bottom;

  /// 完全包含（含相等；退化盒落在边界上视为包含）。
  bool containsRect(LayoutRect other) =>
      left <= other.left &&
      top <= other.top &&
      other.right <= right &&
      other.bottom <= bottom;

  bool containsPoint(Offset point) =>
      point.dx >= left &&
      point.dx <= right &&
      point.dy >= top &&
      point.dy <= bottom;

  /// 轴向欧氏间隙（相交或接触为 0）——OBB 真实距离的下界：
  /// 保守 gap ≤ 真实 gap，据其判定"间距达标"方向安全。
  double gapTo(LayoutRect other) {
    final dx =
        left > other.right
            ? left - other.right
            : other.left > right
            ? other.left - right
            : 0.0;
    final dy =
        top > other.bottom
            ? top - other.bottom
            : other.top > bottom
            ? other.top - bottom
            : 0.0;
    return math.sqrt(dx * dx + dy * dy);
  }

  LayoutRect union(LayoutRect other) => LayoutRect(
    left: math.min(left, other.left),
    top: math.min(top, other.top),
    width:
        math.max(right, other.right) - math.min(left, other.left),
    height:
        math.max(bottom, other.bottom) - math.min(top, other.top),
  );

  /// 闭盒交集；无交（连接触都没有）返回 null。线接触产生零面积盒。
  LayoutRect? intersectOrNull(LayoutRect other) {
    if (!intersects(other)) return null;
    final l = math.max(left, other.left);
    final t = math.max(top, other.top);
    final r = math.min(right, other.right);
    final b = math.min(bottom, other.bottom);
    return LayoutRect(left: l, top: t, width: r - l, height: b - t);
  }

  /// 四边同量外扩（接受负值收缩；本 feature 的页界收缩走 [deflateInsets]）。
  LayoutRect inflate(double delta) => LayoutRect(
    left: left - delta,
    top: top - delta,
    width: width + delta * 2,
    height: height + delta * 2,
  );

  LayoutRect inflateInsets(LayoutInsets insets) => LayoutRect(
    left: left - insets.left,
    top: top - insets.top,
    width: width + insets.left + insets.right,
    height: height + insets.top + insets.bottom,
  );

  /// 按 [insets] 内缩（页边距内容区）。过度收缩抛 [ArgumentError]，
  /// 页面参数错误必须显式失败，不允许负尺寸盒静默流转。
  LayoutRect deflateInsets(LayoutInsets insets) {
    final w = width - insets.left - insets.right;
    final h = height - insets.top - insets.bottom;
    if (w < 0 || h < 0) {
      throw ArgumentError(
        'insets $insets exceed rect ${toString()}',
      );
    }
    return LayoutRect(left: left + insets.left, top: top + insets.top, width: w, height: h);
  }

  /// 绕本盒中心旋转 [rotation] 弧度得到精确 OBB。
  OrientedLayoutRect orientedAboutCenter(double rotation) =>
      OrientedLayoutRect(
        centerX: centerX,
        centerY: centerY,
        halfWidth: width / 2,
        halfHeight: height / 2,
        rotation: rotation,
      );

  @override
  bool operator ==(Object other) =>
      other is LayoutRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'LayoutRect(L $left, T $top, W $width, H $height)';
}
