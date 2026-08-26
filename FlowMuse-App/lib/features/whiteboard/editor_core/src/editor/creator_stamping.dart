import '../core/elements/collaboration_element_owner.dart';
import '../core/elements/elements.dart';
import '../core/layout/canvas_layout.dart';
import '../core/scene/scene_exports.dart';
import 'tool_result.dart';

/// 对本地用户产生的 [result] 统一执行 v4 §5.2 归属规则：
/// - Add 普通独立元素：无论传入是否自带 owner，覆盖为当前操作者；
/// - Add 绑定文字（TextElement.containerId 非空）：优先同批先新增的父
///   元素，其次当前 Scene 父元素；父无 owner 则绑定文字无 owner；
/// - Add 系统元素（CanvasPage/PDF Background）：清除 owner；
/// - Update：强制保留 Scene 中既有 owner（无则继续无）；
/// - 其余结果类型原样返回。
/// 纯函数，不改输入；与 undo/redo、远端 applyRemote* 无关（它们不经过
/// 本函数）。
ToolResult stampCreatorOnResult(
  ToolResult result,
  Scene scene,
  CollaborationCreator creator,
) {
  final batchCreators = <ElementId, CollaborationCreator>{};
  return _walk(result, scene, creator, batchCreators);
}

ToolResult _walk(
  ToolResult node,
  Scene scene,
  CollaborationCreator creator,
  Map<ElementId, CollaborationCreator> batchCreators,
) {
  switch (node) {
    case AddElementResult(:final element):
      final stamped = _stampAdd(element, scene, batchCreators, creator);
      return identical(stamped, element) ? node : AddElementResult(stamped);
    case UpdateElementResult(:final element):
      final stamped = _stampUpdate(element, scene);
      return identical(stamped, element) ? node : UpdateElementResult(stamped);
    case CompoundResult(:final results):
      // 两遍处理（v4 §5.2："必须能看到同批次先新增的父元素"）：第一遍
      // 处理非绑定文字（父元素），第二遍处理绑定文字——即使绑定文字在
      // 列表中排在父元素之前也能正确继承。非元素结果与嵌套 CompoundResult
      // 原样保留在原位。元素顺序本身不重排（最终场景顺序由 fractional
      // index 决定，重排 Add 无行为差异，但保持原序更稳妥）。
      var changed = false;
      final stampedMap = <ToolResult, ToolResult>{};
      void stampRound(bool boundRound) {
        for (final child in results) {
          if (child is! AddElementResult) continue;
          final isBoundText =
              child.element is TextElement &&
              (child.element as TextElement).containerId != null;
          if (isBoundText != boundRound) continue;
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        }
      }

      stampRound(false); // 先父元素
      stampRound(true); // 后绑定文字
      for (final child in results) {
        if (child is UpdateElementResult) {
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        } else if (child is CompoundResult) {
          final stamped = _walk(child, scene, creator, batchCreators);
          stampedMap[child] = stamped;
          changed = changed || !identical(stamped, child);
        }
      }
      if (!changed) return node;
      return CompoundResult([
        for (final child in results) stampedMap[child] ?? child,
      ]);
    default:
      return node;
  }
}

Element _stampAdd(
  Element element,
  Scene scene,
  Map<ElementId, CollaborationCreator> batchCreators,
  CollaborationCreator creator,
) {
  if (element.isCanvasPage || element.isPdfBackground) {
    return withoutCreator(element);
  }
  final containerId = element is TextElement ? element.containerId : null;
  if (containerId != null) {
    final parentCreator =
        batchCreators[ElementId(containerId)] ??
        _creatorOfSceneElement(scene, ElementId(containerId));
    if (parentCreator == null) {
      return withoutCreator(element);
    }
    batchCreators[element.id] = parentCreator;
    return withCreator(element, parentCreator);
  }
  batchCreators[element.id] = creator;
  return withCreator(element, creator);
}

Element _stampUpdate(Element element, Scene scene) {
  final existing = scene.getElementById(element.id);
  if (existing == null) return element;
  final existingCreator = readCreator(existing);
  if (existingCreator == null) {
    return withoutCreator(element);
  }
  final incoming = readCreator(element);
  if (incoming != null &&
      incoming.creatorKey == existingCreator.creatorKey &&
      incoming.displayName == existingCreator.displayName &&
      incoming.isGuest == existingCreator.isGuest) {
    return element;
  }
  return withCreator(element, existingCreator);
}

CollaborationCreator? _creatorOfSceneElement(Scene scene, ElementId id) {
  final element = scene.getElementById(id);
  if (element == null) return null;
  return readCreator(element);
}
