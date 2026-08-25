import 'dart:ui';

import '../../editor/bindings/binding_utils.dart';
import '../../editor/bindings/bound_text_utils.dart';
import '../../editor/tool_result.dart';
import '../elements/elements.dart';
import '../scene/scene.dart';

/// 批量移动元素并携带关联更新：绑定箭头跟随、绑定文本跟随、frame 子元素跟随。
/// 输入 deltas 为"左上角平移量"；成组整体移动由调用方在 deltas 中展开为每个成员。
class SmartLayoutMoveBuilder {
  const SmartLayoutMoveBuilder._();

  static List<ToolResult> buildResults(
    Scene scene,
    Map<ElementId, Offset> deltas,
  ) {
    if (deltas.isEmpty) return const [];
    final results = <ToolResult>[];
    final seen = <ElementId>{};
    final movedRaw = <Element>[];

    // 1. 主体移动
    for (final entry in deltas.entries) {
      Element? original;
      for (final element in scene.activeElements) {
        if (element.id == entry.key) {
          original = element;
          break;
        }
      }
      if (original == null) continue;
      final updated = original.copyWith(
        x: original.x + entry.value.dx,
        y: original.y + entry.value.dy,
      );
      movedRaw.add(updated);
      seen.add(entry.key);
      results.add(UpdateElementResult(updated));
    }

    // 2. frame 子元素跟随（子元素的 frameId 指向被移动的 frame）
    if (movedRaw.isNotEmpty) {
      final frameDeltaById = <String, Offset>{
        for (final entry in deltas.entries) entry.key.value: entry.value,
      };
      final frameIds = <String>{
        for (final element in movedRaw)
          if (element is FrameElement) element.id.value,
      };
      if (frameIds.isNotEmpty) {
        for (final element in scene.activeElements) {
          final frameId = element.frameId;
          if (frameId == null || !frameIds.contains(frameId)) continue;
          if (seen.contains(element.id)) continue;
          final delta = frameDeltaById[frameId];
          if (delta == null) continue;
          seen.add(element.id);
          results.add(
            UpdateElementResult(
              element.copyWith(
                x: element.x + delta.dx,
                y: element.y + delta.dy,
              ),
            ),
          );
        }
      }
    }

    // 3. 绑定文本跟随（位置随父元素）
    results.addAll(BoundTextUtils.updateBoundTextPositions(scene, movedRaw));

    // 4. 绑定箭头更新（用临时场景解析端点）
    var tempScene = scene;
    for (final element in movedRaw) {
      tempScene = tempScene.updateElement(element);
    }
    final arrowSeen = <ElementId>{};
    for (final element in movedRaw) {
      final arrows = BindingUtils.findBoundArrows(scene, element.id);
      for (final arrow in arrows) {
        if (seen.contains(arrow.id) || arrowSeen.contains(arrow.id)) continue;
        arrowSeen.add(arrow.id);
        final updated = BindingUtils.updateBoundArrowEndpoints(
          arrow,
          tempScene,
        );
        if (!identical(updated, arrow)) {
          results.add(UpdateElementResult(updated));
        }
      }
    }
    return results;
  }
}
