import 'dart:math' as math;

import 'layout_rect.dart';

/// 智能排版 feature 内部 2D 仿射变换（V3-302A）。
///
/// 仅表达排版会用的 move/resize/rotate 组合，纯数学不可变值对象；
/// 修改任何元素/Scene 属于 V3-303A，本类不触碰编辑器状态。
/// 矩阵按列向量约定：x' = m00·x + m01·y + tx，y' = m10·x + m11·y + ty。
class AffineLayoutTransform {
  const AffineLayoutTransform({
    required this.m00,
    required this.m01,
    required this.m10,
    required this.m11,
    required this.tx,
    required this.ty,
  });

  const AffineLayoutTransform.identity()
    : m00 = 1,
      m01 = 0,
      m10 = 0,
      m11 = 1,
      tx = 0,
      ty = 0;

  AffineLayoutTransform.translation(double dx, double dy)
    : m00 = 1,
      m01 = 0,
      m10 = 0,
      m11 = 1,
      tx = dx,
      ty = dy;

  /// 绕 (cx, cy) 旋转 [radians]（数学正方向，页面坐标系 y 向下时
  /// 视觉为顺时针；与 Element.angle 同一约定）。
  factory AffineLayoutTransform.rotationAround(
    double cx,
    double cy,
    double radians,
  ) {
    final cosR = math.cos(radians);
    final sinR = math.sin(radians);
    return AffineLayoutTransform(
      m00: cosR,
      m01: -sinR,
      m10: sinR,
      m11: cosR,
      tx: cx - cx * cosR + cy * sinR,
      ty: cy - cx * sinR - cy * cosR,
    );
  }

  /// 绕 (ax, ay) 缩放（resize 的几何表达；排版 resize 通常以锚角为轴）。
  factory AffineLayoutTransform.scaleAround(
    double ax,
    double ay,
    double sx,
    double sy,
  ) => AffineLayoutTransform(
    m00: sx,
    m01: 0,
    m10: 0,
    m11: sy,
    tx: ax - ax * sx,
    ty: ay - ay * sy,
  );

  final double m00;
  final double m01;
  final double m10;
  final double m11;
  final double tx;
  final double ty;

  bool get isIdentity =>
      m00 == 1 && m01 == 0 && m10 == 0 && m11 == 1 && tx == 0 && ty == 0;

  (double, double) applyToPoint(double x, double y) => (
    m00 * x + m01 * y + tx,
    m10 * x + m11 * y + ty,
  );

  /// 线性部分作用于尺寸向量（平移不影响尺寸）。
  (double, double) applyToSize(double width, double height) => (
    (m00 * width + m01 * height).abs(),
    (m10 * width + m11 * height).abs(),
  );

  /// 变换盒四角后的保守 AABB——旋转/斜切把盒变成 OBB，取外包；
  /// 与快照 conservativeVisualBounds 同语义，invariant 校验据此比对。
  LayoutRect applyToRect(LayoutRect rect) {
    final corners = [
      applyToPoint(rect.left, rect.top),
      applyToPoint(rect.right, rect.top),
      applyToPoint(rect.right, rect.bottom),
      applyToPoint(rect.left, rect.bottom),
    ];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final (x, y) in corners) {
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

  /// 复合：`a.compose(b)` 表示先应用 b 再应用 a（矩阵乘 a·b）。
  AffineLayoutTransform compose(AffineLayoutTransform other) =>
      AffineLayoutTransform(
        m00: m00 * other.m00 + m01 * other.m10,
        m01: m00 * other.m01 + m01 * other.m11,
        m10: m10 * other.m00 + m11 * other.m10,
        m11: m10 * other.m01 + m11 * other.m11,
        tx: m00 * other.tx + m01 * other.ty + tx,
        ty: m10 * other.tx + m11 * other.ty + ty,
      );

  /// 逆变换；退化（det=0，如零缩放）抛 [StateError]——
  /// 排版变换必须可逆，不可逆参数属于上游错误。
  AffineLayoutTransform invert() {
    final det = m00 * m11 - m01 * m10;
    if (det == 0 || !det.isFinite) {
      throw StateError('transform is singular: det=$det');
    }
    final inv00 = m11 / det;
    final inv01 = -m01 / det;
    final inv10 = -m10 / det;
    final inv11 = m00 / det;
    return AffineLayoutTransform(
      m00: inv00,
      m01: inv01,
      m10: inv10,
      m11: inv11,
      tx: -(inv00 * tx + inv01 * ty),
      ty: -(inv10 * tx + inv11 * ty),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AffineLayoutTransform &&
      other.m00 == m00 &&
      other.m01 == m01 &&
      other.m10 == m10 &&
      other.m11 == m11 &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(m00, m01, m10, m11, tx, ty);

  @override
  String toString() =>
      'AffineLayoutTransform([$m00, $m01; $m10, $m11] + ($tx, $ty))';
}
