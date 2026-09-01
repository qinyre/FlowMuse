import '../../editor_core/flow_muse_whiteboard_editor.dart';
import 'affine_layout_transform.dart';

/// 变换类语义：排版只产生平移/绕点旋转/轴对齐缩放三类
///（V3-302A 契约 op 集合）；斜切、含旋转的缩放一律不支持。
class TransformSemantics {
  const TransformSemantics._({
    required this.kind,
    this.sx = 1,
    this.sy = 1,
    this.rotationDelta = 0,
  }) : preservesSize = kind != TransformKind.axisScale;

  /// 分类顺序必须是：平移 → 正交旋转（det≈1）→ 轴对齐正缩放。
  /// π 旋转矩阵 m00=m11=-1 也是轴对齐形态，若先判缩放会被误分类为
  /// sx=sy=-1 产生负尺寸——正交判定必须先于缩放；负/镜像缩放与
  /// 含旋转的缩放一律确定性失败。
  factory TransformSemantics.of(
    AffineLayoutTransform t,
    double rotationDelta,
  ) {
    const eps = 1e-9;
    final isAxisAligned = t.m01.abs() < eps && t.m10.abs() < eps;
    if (isAxisAligned && (t.m00 - 1).abs() < eps && (t.m11 - 1).abs() < eps) {
      return const TransformSemantics._(kind: TransformKind.translation);
    }
    final det = t.m00 * t.m11 - t.m01 * t.m10;
    if ((det - 1).abs() < eps && rotationDelta != 0) {
      return TransformSemantics._(
        kind: TransformKind.rotationLike,
        rotationDelta: rotationDelta,
      );
    }
    if (isAxisAligned && t.m00 > 0 && t.m11 > 0) {
      return TransformSemantics._(
        kind: TransformKind.axisScale,
        sx: t.m00,
        sy: t.m11,
      );
    }
    throw UnsupportedError(
      'unsupported transform class: negative/mirrored scale, shear, or '
      'rotation-composed scale ($t) — 排版变换必须分解为单操作',
    );
  }

  final TransformKind kind;
  final double sx;
  final double sy;
  final double rotationDelta;
  final bool preservesSize;
}

enum TransformKind { translation, rotationLike, axisScale }

/// 元素基础几何（中心过仿射 + 尺寸按类处理）。
class ElementBaseGeometry {
  const ElementBaseGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.angle,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double angle;
}

/// 计算元素基础几何变换（中心随仿射移动；平移/旋转保尺寸，
/// 轴对齐缩放按 (sx, sy) 缩尺寸；angle 只在旋转类累加）。
ElementBaseGeometry transformBaseGeometry(
  Element element,
  AffineLayoutTransform transform,
  TransformSemantics semantics,
) {
  _assertComposableWithRotation(element.angle, semantics);
  final cx = element.x + element.width / 2;
  final cy = element.y + element.height / 2;
  final moved = transform.applyToPoint(cx, cy);
  final width = semantics.preservesSize
      ? element.width
      : element.width * semantics.sx;
  final height = semantics.preservesSize
      ? element.height
      : element.height * semantics.sy;
  return ElementBaseGeometry(
    x: moved.$1 - width / 2,
    y: moved.$2 - height / 2,
    width: width,
    height: height,
    angle: element.angle + semantics.rotationDelta,
  );
}

/// 笔迹（freedraw）元素变换适配（V3-303A）。
///
/// 语义约束（与渲染器 element_renderer._absolutePoints 一致）：
/// points 是元素局部坐标，渲染时平移 (x,y)；angle 绕元素中心由画布
/// 变换表达。因此平移/旋转只动 x/y(/angle)，轴对齐缩放时 points 的
/// 局部坐标与包围盒按 (sx, sy) 同步缩放。
class StrokeTransformAdapter {
  const StrokeTransformAdapter._();

  static FreedrawElement transform(
    FreedrawElement stroke,
    AffineLayoutTransform transform,
    TransformSemantics semantics,
  ) {
    final next = transformBaseGeometry(stroke, transform, semantics);
    final moved = stroke.copyWith(
      x: next.x,
      y: next.y,
      width: next.width,
      height: next.height,
      angle: next.angle,
    );
    if (semantics.kind != TransformKind.axisScale) return moved;
    return moved.copyWithFreedraw(
      points: [
        for (final p in stroke.points)
          Point(p.x * semantics.sx, p.y * semantics.sy),
      ],
    );
  }
}

/// 文本元素变换适配（V3-303A）。
///
/// 只动几何（x/y/w/h/angle）；text 内容、containerId 与绑定引用不变
/// （容器跟随由 transformer 闭包展开保证同变换）。
class TextTransformAdapter {
  const TextTransformAdapter._();

  static TextElement transform(
    TextElement text,
    AffineLayoutTransform transform,
    TransformSemantics semantics,
  ) {
    final next = transformBaseGeometry(text, transform, semantics);
    return text.copyWith(
      x: next.x,
      y: next.y,
      width: next.width,
      height: next.height,
      angle: next.angle,
    );
  }
}

/// 已旋转元素上的轴对齐缩放是局部系语义，与世界系变换期望不等价
///（TransformInvariant 会按世界系校验）——确定性失败而非静默偏差。
void _assertComposableWithRotation(double angle, TransformSemantics semantics) {
  if (semantics.kind == TransformKind.axisScale && angle != 0) {
    throw UnsupportedError(
      'axis-aligned scale on rotated element (angle=$angle) is not '
      'world-equivalent — rotate back or decompose first',
    );
  }
}

/// 线/箭头类元素（points 局部坐标，渲染语义与 freedraw 相同：
/// element_renderer._absolutePoints）变换适配。缩放时包围盒与局部
/// points 按 (sx, sy) 同步缩放；平移/旋转只动 x/y(/angle)。
class LineLikeTransformAdapter {
  const LineLikeTransformAdapter._();

  static LineElement transform(
    LineElement line,
    AffineLayoutTransform transform,
    TransformSemantics semantics,
  ) {
    final next = transformBaseGeometry(line, transform, semantics);
    final moved = line.copyWith(
      x: next.x,
      y: next.y,
      width: next.width,
      height: next.height,
      angle: next.angle,
    );
    if (semantics.kind != TransformKind.axisScale) return moved;
    final scaled = [
      for (final p in line.points)
        Point(p.x * semantics.sx, p.y * semantics.sy),
    ];
    return moved.copyWithLine(points: scaled);
  }
}
