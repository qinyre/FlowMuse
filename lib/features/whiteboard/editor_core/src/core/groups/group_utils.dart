import '../elements/elements.dart';
import '../scene/scene_exports.dart';

/// Stateless utility methods for element grouping logic.
///
/// Groups are implicit — defined by shared `groupIds` values on elements,
/// not by separate group objects. The `groupIds` list is innermost-first,
/// outermost-last (Excalidraw convention).
class GroupUtils {
  GroupUtils._();

  /// Returns the outermost (last) groupId, or null if not grouped.
  static String? outermostGroupId(Element element) {
    if (element.groupIds.isEmpty) return null;
    return element.groupIds.last;
  }

  /// Returns the innermost (first) groupId, or null if not grouped.
  static String? innermostGroupId(Element element) {
    if (element.groupIds.isEmpty) return null;
    return element.groupIds.first;
  }

  /// Returns all active elements in [scene] that have [groupId] in their
  /// groupIds list.
  static List<Element> findGroupMembers(Scene scene, String groupId) {
    return scene.activeElements
        .where((e) => e.groupIds.contains(groupId))
        .toList();
  }

  /// Expands [ids] to include all members of [groupId] that are active in
  /// [scene].
  static Set<ElementId> expandToGroup(
    Scene scene,
    Set<ElementId> ids,
    String groupId,
  ) {
    final expanded = Set<ElementId>.from(ids);
    for (final e in scene.activeElements) {
      if (e.groupIds.contains(groupId)) {
        expanded.add(e.id);
      }
    }
    return expanded;
  }

  /// Adds [newGroupId] as the outermost group on each element.
  ///
  /// Returns new element copies with the groupId appended.
  static List<Element> groupElements(
    List<Element> elements,
    String newGroupId,
  ) {
    return elements.map((e) {
      return e.copyWith(groupIds: [...e.groupIds, newGroupId]);
    }).toList();
  }

  /// Removes the outermost groupId from each element.
  ///
  /// Returns new element copies with the last groupId removed.
  /// Elements with no groupIds are returned unchanged.
  static List<Element> ungroupElements(List<Element> elements) {
    return elements.map((e) {
      if (e.groupIds.isEmpty) return e;
      final newIds = List<String>.from(e.groupIds)..removeLast();
      return e.copyWith(groupIds: newIds);
    }).toList();
  }

  /// Determines which group level to select when clicking an element.
  ///
  /// Returns a groupId to expand selection to, or null to select the
  /// individual element.
  ///
  /// Drill-down logic:
  /// - Element not grouped → null (select individual)
  /// - No group members currently selected → outermost groupId
  /// - Outermost group already selected → next inner groupId
  /// - Innermost group already selected → null (individual)
  static String? resolveGroupForClick(
    Element clicked,
    Set<ElementId> currentSelection,
    Scene scene,
  ) {
    if (clicked.groupIds.isEmpty) return null;

    // Walk from outermost to innermost
    for (var i = clicked.groupIds.length - 1; i >= 0; i--) {
      final groupId = clicked.groupIds[i];
      final members = findGroupMembers(scene, groupId);
      final allSelected = members.every((m) => currentSelection.contains(m.id));
      if (!allSelected) {
        return groupId;
      }
    }

    // All group levels already selected → select individual
    return null;
  }
}
