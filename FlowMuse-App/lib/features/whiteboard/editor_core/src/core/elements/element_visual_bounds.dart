import 'elements.dart';
import '../math/math.dart';

/// 元素可视边界（issue #5 T6）。
///
/// 自由笔画元素的中心线 AABB 不含笔刷可见半径（荧光笔半宽可达
/// strokeWidth×4.2/2），Scene 命中、sceneBounds、导出边界与远端湿墨
/// dim 层必须统一用本函数外扩后的边界；其他元素保持既有边界行为，
/// 本函数不顺带重做全部图形命中。
Bounds elementVisualBounds(Element element) {
  if (element is FreedrawElement) {
    final brushType = brushTypeFromCustomData(element.customData);
    final profile = BrushRenderProfile.forType(brushType);
    final half = profile.visualHalfWidth(element.strokeWidth);
    return Bounds.fromLTWH(
      element.x - half,
      element.y - half,
      element.width + half * 2,
      element.height + half * 2,
    );
  }
  return Bounds.fromLTWH(element.x, element.y, element.width, element.height);
}
