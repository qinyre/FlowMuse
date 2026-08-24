import 'dart:ui';

import '../../editor/mindmap/mindmap_layout.dart';
import '../../editor/mindmap/mindmap_tree.dart';
import '../elements/elements.dart';
import '../math/math.dart';
import 'smart_layout_plan.dart';

class MindmapStyleEngineResult {
  const MindmapStyleEngineResult({
    required this.elements,
    required this.bounds,
  });

  /// 已放置到最终位置、尚未合并 pageId 的树元素（矩形+文本+箭头）。
  final List<Element> elements;

  /// 整棵树 union 放置区域（用于预览矩形）。
  final Bounds bounds;
}

/// 头脑风暴 → 真思维导图引擎：复用 MindmapLayout 确定性布局 + 页内避碰放置。
/// 整棵树作为整体平移，不改变节点尺寸/层级/绑定。
class MindmapStyleEngine {
  const MindmapStyleEngine._();

  static MindmapStyleEngineResult? plan({
    required MindmapNode node,
    required Rect contentArea,
    required List<Bounds> occupied,
  }) {
    final preview = MindmapLayout.treeToElements(
      node,
      origin: const Point(0, 0),
    );
    if (preview.isEmpty) return null;
    var union = Bounds.fromLTWH(
      preview.first.x,
      preview.first.y,
      preview.first.width,
      preview.first.height,
    );
    for (final element in preview.skip(1)) {
      union = union.union(
        Bounds.fromLTWH(
          element.x,
          element.y,
          element.width,
          element.height,
        ),
      );
    }
    final placement = SmartLayoutPlacement.findInsertionBounds(
      contentArea,
      union.size.width,
      union.size.height,
      occupied,
    );
    if (placement == null) return null;
    final dx = placement.left - union.left;
    final dy = placement.top - union.top;
    final moved = [
      for (final element in preview)
        element.copyWith(x: element.x + dx, y: element.y + dy),
    ];
    return MindmapStyleEngineResult(
      elements: moved,
      bounds: Bounds.fromLTWH(
        placement.left,
        placement.top,
        union.size.width,
        union.size.height,
      ),
    );
  }
}
