import '../core/elements/collaboration_element_owner.dart';
import '../core/elements/elements.dart';
import '../core/layout/canvas_layout.dart';

/// v4 §7.1 分类顺序（无 focus → 系统 → 本地高亮 → creator 命中 → history
/// 命中 → 其余 0.22）。静态 painter 与数学 overlay 共用，禁止两处各写一份。
double collaborationFocusAlpha(
  Element element, {
  required String? focusedCreatorKey,
  required bool focusHistoricalContent,
  Set<ElementId> highlightedElementIds = const {},
}) {
  if (focusedCreatorKey == null && !focusHistoricalContent) return 1.0;
  if (element.isCanvasPage || element.isPdfBackground) return 1.0;
  if (highlightedElementIds.contains(element.id)) return 1.0;
  final creator = readCreator(element);
  if (focusedCreatorKey != null) {
    return creator != null && creator.creatorKey == focusedCreatorKey
        ? 1.0
        : 0.22;
  }
  return creator == null ? 1.0 : 0.22;
}
