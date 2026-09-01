import 'layout_rect.dart';

/// 页边距/保护间距原语（V3-301A）。值语义。
class LayoutInsets {
  const LayoutInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  const LayoutInsets.zero()
    : left = 0,
      top = 0,
      right = 0,
      bottom = 0;

  const LayoutInsets.all(double v)
    : left = v,
      top = v,
      right = v,
      bottom = v;

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isZero => left == 0 && top == 0 && right == 0 && bottom == 0;

  /// 外扩（页面框加保护带方向）。
  LayoutRect inflateRect(LayoutRect rect) => LayoutRect(
    left: rect.left - left,
    top: rect.top - top,
    width: rect.width + left + right,
    height: rect.height + top + bottom,
  );

  /// 内缩（页界 contain 的内容区）；过度收缩抛 [ArgumentError]。
  LayoutRect deflateRect(LayoutRect rect) =>
      rect.deflateInsets(this);

  @override
  bool operator ==(Object other) =>
      other is LayoutInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'LayoutInsets(L $left, T $top, R $right, B $bottom)';
}
