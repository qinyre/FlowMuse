import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'layout_page_snapshot.dart';

/// V3 一次捕获的页面范围；只提供本轮有效归属，不改写 Scene 元数据。
class ResolvedPageScope {
  ResolvedPageScope._({
    required this.pageId,
    required Set<String> includedSourceIds,
    required Set<String> protectedSourceIds,
    required Map<String, String> effectivePageIds,
    required Map<String, String> excludedReasons,
    required Map<String, SnapshotBounds> fixedBounds,
  }) : includedSourceIds = Set.unmodifiable(includedSourceIds),
       protectedSourceIds = Set.unmodifiable(protectedSourceIds),
       effectivePageIds = Map.unmodifiable(effectivePageIds),
       excludedReasons = Map.unmodifiable(excludedReasons),
       fixedBounds = Map.unmodifiable(fixedBounds);

  final String pageId;
  final Set<String> includedSourceIds;
  final Set<String> protectedSourceIds;
  final Map<String, String> effectivePageIds;

  /// 只记录当前页可见但未纳入的内容；他页正常内容不制造告警。
  final Map<String, String> excludedReasons;
  final Map<String, SnapshotBounds> fixedBounds;

  String? effectivePageIdOf(Element element) =>
      effectivePageIds[element.id.value] ?? element.pageId;

  Scene captureScene(Scene scene) {
    var captured = Scene();
    for (final element in scene.orderedElements) {
      if (!element.isDeleted && includedSourceIds.contains(element.id.value)) {
        captured = captured.addElement(element);
      }
    }
    for (final entry in scene.files.entries) {
      captured = captured.addFile(entry.key, entry.value);
    }
    return captured;
  }

  static ResolvedPageScope resolve(Scene scene, String pageId) {
    final elements = {for (final e in scene.activeElements) e.id.value: e};
    final pages = <String, SnapshotBounds>{};
    for (final e in elements.values) {
      if (e.isCanvasPage && e.pageId != null) {
        final bounds = SnapshotBounds.ofElement(e);
        if (!_valid(bounds)) continue;
        pages.update(e.pageId!, (b) => b.union(bounds), ifAbsent: () => bounds);
      }
    }
    final bounds = {
      for (final e in elements.values) e.id.value: conservativeVisualBounds(e),
    };
    final owners = <String, String>{};
    final recovered = <String>{};
    for (final e in elements.values) {
      final owner = e.pageId;
      if (owner == pageId || pages.containsKey(owner)) {
        owners[e.id.value] = owner!;
      } else if (!(e.isCanvasPage || e.isPdfBackground)) {
        final containing = pages.entries.where(
          (p) => _inside(bounds[e.id.value]!, p.value),
        );
        if (containing.length == 1) {
          owners[e.id.value] = containing.single.key;
          recovered.add(e.id.value);
        }
      }
    }

    // 无向闭包同时检查反向 frame/container/arrow 引用；只检查变换器的
    // 向下跟随范围会漏掉“跨页箭头绑定到本页图片”的情况。
    final edges = {for (final id in elements.keys) id: <String>{}};
    final broken = <String>{};
    void link(String a, String? b) {
      if (b == null) return;
      if (!elements.containsKey(b)) {
        broken.add(a);
        return;
      }
      edges[a]!.add(b);
      edges[b]!.add(a);
    }

    final groupHead = <String, String>{};
    for (final e in elements.values) {
      final id = e.id.value;
      for (final group in e.groupIds) {
        final head = groupHead.putIfAbsent(group, () => id);
        link(id, head);
      }
      link(id, e.frameId);
      for (final bound in e.boundElements) {
        link(id, bound.id);
      }
      if (e is TextElement) link(id, e.containerId);
      if (e is ArrowElement) {
        link(id, e.startBinding?.elementId);
        link(id, e.endBinding?.elementId);
      }
    }
    final included = <String>{};
    final protected = <String>{};
    final visited = <String>{};
    final conflicted = <String>{};
    for (final id in elements.keys) {
      if (visited.contains(id)) continue;
      final component = <String>{};
      final pending = [id];
      while (pending.isNotEmpty) {
        final next = pending.removeLast();
        if (!component.add(next)) continue;
        pending.addAll(edges[next]!);
      }
      visited.addAll(component);
      final samePage = component.every((id) => owners[id] == pageId);
      final unsafe =
          !samePage ||
          component.any((id) {
            final e = elements[id]!;
            return broken.contains(id) ||
                e.locked ||
                (e is ImageElement && !scene.files.containsKey(e.fileId)) ||
                (!(e is TextElement ||
                    e is ImageElement ||
                    e is FreedrawElement)) ||
                (component.length > 1 && e is FreedrawElement);
          });
      for (final member in component) {
        if (owners[member] != pageId) continue;
        // 推断归属只有在整个闭包同页时才成立；显式归属保留入账但不动。
        if (recovered.contains(member) && !samePage) {
          conflicted.add(member);
          continue;
        }
        included.add(member);
        if (unsafe) protected.add(member);
      }
    }
    final excluded = <String, String>{};
    final fixed = <String, SnapshotBounds>{};
    final target = pages[pageId];
    if (target != null) {
      for (final e in elements.values) {
        final id = e.id.value;
        if (included.contains(id) || e.isCanvasPage || e.isPdfBackground) {
          continue;
        }
        if (!_intersects(bounds[id]!, target)) continue;
        excluded[id] = conflicted.contains(id)
            ? 'closure-conflict'
            : pages.containsKey(e.pageId)
            ? 'other-page'
            : 'ambiguous-page';
        fixed[id] = bounds[id]!;
      }
    }
    return ResolvedPageScope._(
      pageId: pageId,
      includedSourceIds: included,
      protectedSourceIds: protected,
      effectivePageIds: {for (final id in included) id: pageId},
      excludedReasons: excluded,
      fixedBounds: fixed,
    );
  }

  static bool _valid(SnapshotBounds b) =>
      [b.left, b.top, b.width, b.height].every((v) => v.isFinite) &&
      b.width > 0 &&
      b.height > 0;

  static bool _inside(SnapshotBounds a, SnapshotBounds b) {
    if (!_valid(a)) return false;
    // 历史拖入图片可能仅越页边几像素；不要因此把同页图文拆成两套范围。
    // 同时约束边距和可见面积，小物体/显著跨页物体不能借容差被抢入。
    final tolerance = b.width * .01;
    final width = math.max(
      0.0,
      math.min(a.right, b.right) - math.max(a.left, b.left),
    );
    final height = math.max(
      0.0,
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top),
    );
    return a.left >= b.left - tolerance &&
        a.top >= b.top - tolerance &&
        a.right <= b.right + tolerance &&
        a.bottom <= b.bottom + tolerance &&
        width * height >= a.width * a.height * .98;
  }

  static bool _intersects(SnapshotBounds a, SnapshotBounds b) =>
      a.left < b.right &&
      b.left < a.right &&
      a.top < b.bottom &&
      b.top < a.bottom;
}
