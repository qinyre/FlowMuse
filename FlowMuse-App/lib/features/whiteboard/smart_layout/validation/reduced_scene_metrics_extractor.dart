import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../composition/layout_block.dart';
import '../metrics/scene_metrics_contract.dart';
import '../reducer/smart_layout_scene_reducer.dart';
import '../rendering/draft_scene_renderer.dart';
import '../snapshot/deterministic_hash.dart';
import '../snapshot/source_coverage_ledger.dart';

/// 语义关系期望（渲染后元素 id 表达；语义→渲染 id 的翻译属候选链
/// V3-504B，本层不读 placement 自报）。
enum SemanticRelationExpectationKind { captionOf, keepWith }

class SemanticRelationExpectation {
  const SemanticRelationExpectation({
    required this.relationId,
    required this.kind,
    required this.anchorId,
    required this.followerId,
    this.maxGap,
    this.memberIds = const {},
  });

  final String relationId;
  final SemanticRelationExpectationKind kind;

  /// captionOf：figure；keepWith：前驱。
  final String anchorId;

  /// captionOf：caption；keepWith：后继。
  final String followerId;
  final double? maxGap;
  final Set<String> memberIds;
}

/// 阅读序期望（渲染后元素 id 的语义阅读序；相邻项构成检查对）。
class ReadingOrderExpectation {
  const ReadingOrderExpectation({
    required this.orderedElementIds,
    this.columnByNode = const {},
    this.columns = const [],
  });

  final List<String> orderedElementIds;
  final Map<String, int> columnByNode;
  final List<Bounds> columns;
}

/// 真实 Scene metrics 提取器（V3-504A）：从 **reducer + renderer 的真实
/// 产物** 提取 [SceneMetricsExtraction]——归约后 Scene、渲染层（真实
/// 墨迹盒）与账本三者缺一不可；不读取 placement 层任何自报数据
///（源码门禁：本文件零 placement 引用，测试钉死）。
///
/// 证据链 fail closed：[SceneMetricsExtraction] 构造校验（revision/
/// fingerprint/digest 缺失即抛）+ digest 由渲染层 canonical 重算。
abstract final class ReducedSceneMetricsExtractor {
  static const String rendererFingerprintV1 = 'draft-scene-renderer-v1';

  /// 提取真实指标。
  ///
  /// [pageContentBounds]：页内容区（层真实几何必须全部包含；null 时
  /// 页界违规计 0，页界硬判定仍由 HardConstraintValidator 以同一几何
  /// 复核）。[captionGapTolerance]：caption 与 figure 允许的最大垂直
  /// 间距（缺省 24.0，与紧凑排版令牌同量级）。
  static SceneMetricsExtraction extract({
    required ReducedScene reduced,
    required DraftRenderSnapshot snapshot,
    required SourceCoverageLedger ledger,
    Bounds? pageContentBounds,
    List<SemanticRelationExpectation> relations = const [],
    ReadingOrderExpectation? readingOrder,
    double captionGapTolerance = 24.0,
    Set<String>? validationElementIds,
    Map<String, List<String>> outputElementIdsByBlock = const {},
    List<CompositionGroupIntent> compositionGroups = const [],
  }) {
    final patch = reduced.patch;

    // ---- coverage：以归约后真实在场性判定，不信自报 ----
    final activeIds = {
      for (final element in reduced.scene.activeElements) element.id.value,
    };
    final writeIds = patch.writeSet.elementIds.toSet();
    final renderedConsumed = <String>[];
    final renderedPreserved = <String>[];
    final missing = <String>[];
    for (final id in ledger.statuses.keys) {
      final status = ledger.statusOf(id);
      if (status == SourceCoverageStatus.consumed) {
        final removedAsConsumed = patch.removes.any((op) => op.elementId == id);
        if (removedAsConsumed || activeIds.contains(id)) {
          renderedConsumed.add(id);
        } else {
          missing.add(id);
        }
      } else if (status == SourceCoverageStatus.preserved) {
        // preserved 必须仍在场且未被本 patch 写。
        if (activeIds.contains(id) && !writeIds.contains(id)) {
          renderedPreserved.add(id);
        } else {
          missing.add(id);
        }
      } else {
        missing.add(id);
      }
    }

    // ---- 页界违规计数（渲染层真实几何 vs 页内容区）----
    var boundsViolations = 0;
    if (pageContentBounds != null) {
      for (final layer in snapshot.layers) {
        if (validationElementIds != null &&
            !validationElementIds.contains(layer.elementId)) {
          continue;
        }
        if (!_inside(layer.bounds, pageContentBounds)) boundsViolations++;
      }
    }

    // ---- 关系满足表（真实渲染几何判定）----
    final nodeBounds = <String, Bounds>{
      for (final layer in snapshot.layers) layer.elementId: layer.bounds,
    };
    for (final entry in outputElementIdsByBlock.entries) {
      final boxes = [for (final id in entry.value) nodeBounds[id]];
      if (boxes.isEmpty || boxes.any((b) => b == null)) continue;
      nodeBounds[entry.key] = boxes.cast<Bounds>().reduce((a, b) => a.union(b));
    }
    final groupOf = {
      for (final g in compositionGroups)
        for (final id in g.memberIds) id: g,
    };
    final groupBounds = <String, Bounds>{};
    for (final g in compositionGroups) {
      if (g.memberIds.every(nodeBounds.containsKey)) {
        groupBounds[g.id] = g.memberIds
            .map((id) => nodeBounds[id]!)
            .reduce((a, b) => a.union(b));
      }
    }
    bool relationSatisfied(SemanticRelationExpectation r) {
      final a = groupOf[r.anchorId];
      final b = groupOf[r.followerId];
      if (a == null || b == null) {
        return _relationSatisfied(
          r,
          nodeBounds,
          captionGapTolerance,
          outputElementIdsByBlock.keys.toSet(),
        );
      }
      if (a.id == b.id) {
        // 正文可以多段，检查完整阅读轨道；图注仍须直接贴图。
        return r.kind != SemanticRelationExpectationKind.captionOf ||
            _relationSatisfied(r, nodeBounds, a.maxGap, const {});
      }
      final anchor = groupBounds[a.id];
      final follower = groupBounds[b.id];
      return anchor != null &&
          follower != null &&
          _stacked(anchor, follower, r.maxGap ?? captionGapTolerance);
    }

    final relationResults = <(String, bool)>[
      for (final relation in relations)
        (relation.relationId, relationSatisfied(relation)),
      for (final g in compositionGroups)
        ('group:${g.id}', _groupSatisfied(g, nodeBounds)),
    ];

    // ---- 阅读序：真实渲染位置（先上后下、同高先左）与期望相邻对 ----
    var orderPairsTotal = 0;
    var orderPairsCorrect = 0;
    if (readingOrder != null && readingOrder.orderedElementIds.length > 1) {
      bool precedes(String a, String b) {
        final pa = nodeBounds[a];
        final pb = nodeBounds[b];
        if (pa == null || pb == null) return false;
        if (compositionGroups.isNotEmpty) {
          final ga = groupOf[a];
          final gb = groupOf[b];
          if (ga == null || gb == null) return false;
          if (ga.id == gb.id) {
            final ta = ga.tracks.indexWhere((t) => t.contains(a));
            final tb = ga.tracks.indexWhere((t) => t.contains(b));
            return ta == tb
                ? pa.bottom <= pb.top + .5
                : ta < tb && pa.right <= pb.left + .5;
          }
          final ba = groupBounds[ga.id]!;
          final bb = groupBounds[gb.id]!;
          if (ga.row == gb.row) {
            return ga.column < gb.column &&
                ba.right <= bb.left + .5 &&
                ba.top < bb.bottom &&
                bb.top < ba.bottom;
          }
          return ga.row < gb.row && ba.bottom <= bb.top + .5;
        }
        if (readingOrder.columnByNode.isNotEmpty) {
          final ca = readingOrder.columnByNode[a];
          final cb = readingOrder.columnByNode[b];
          if (ca == null ||
              cb == null ||
              ca < 0 ||
              cb < 0 ||
              ca >= readingOrder.columns.length ||
              cb >= readingOrder.columns.length) {
            return false;
          }
          if (!_inside(pa, readingOrder.columns[ca]) ||
              !_inside(pb, readingOrder.columns[cb])) {
            return false;
          }
          if (ca != cb) return ca < cb;
          return pa.bottom <= pb.top + 0.5;
        }
        if ((pa.top - pb.top).abs() > 1e-9) return pa.top < pb.top;
        return pa.left < pb.left;
      }

      final order = readingOrder.orderedElementIds;
      for (var i = 0; i + 1 < order.length; i++) {
        orderPairsTotal++;
        if (precedes(order[i], order[i + 1])) {
          orderPairsCorrect++;
        }
      }
    }

    return SceneMetricsExtraction(
      sceneRevision: patch.baseRevision.revision,
      rendererFingerprint: rendererFingerprintV1,
      renderedSceneDigest: reducedSceneDigestOf(snapshot),
      ledgerSourceIds: List.unmodifiable(ledger.statuses.keys.toList()..sort()),
      renderedConsumedSourceIds: List.unmodifiable(renderedConsumed..sort()),
      renderedPreservedSourceIds: List.unmodifiable(renderedPreserved..sort()),
      relationResults: List.unmodifiable(relationResults),
      orderPairsTotal: orderPairsTotal,
      orderPairsCorrect: orderPairsCorrect,
      visualBoundsViolations: boundsViolations,
    );
  }

  static bool _inside(Bounds inner, Bounds outer) =>
      inner.left >= outer.left - 1e-9 &&
      inner.top >= outer.top - 1e-9 &&
      inner.right <= outer.right + 1e-9 &&
      inner.bottom <= outer.bottom + 1e-9;

  static bool _stacked(Bounds a, Bounds b, double gap) =>
      a.left < b.right &&
      b.left < a.right &&
      b.top >= a.bottom - .5 &&
      b.top - a.bottom <= gap + .5;

  static bool _groupSatisfied(
    CompositionGroupIntent g,
    Map<String, Bounds> bounds,
  ) {
    final tracks = <Bounds>[];
    final slot = Bounds.fromLTWH(
      g.slot.left - .5,
      g.slot.top - .5,
      g.slot.width + 1,
      g.slot.height + 1,
    );
    for (final track in g.tracks) {
      final boxes = [for (final id in track) bounds[id]];
      if (boxes.isEmpty || boxes.any((b) => b == null || !_inside(b, slot))) {
        return false;
      }
      for (var i = 0; i + 1 < boxes.length; i++) {
        if (!_stacked(boxes[i]!, boxes[i + 1]!, g.maxGap)) return false;
      }
      tracks.add(boxes.cast<Bounds>().reduce((a, b) => a.union(b)));
    }
    if (g.kind == CompositionGroupKind.mediaSide) {
      if (tracks.length != 2) return false;
      final a = tracks[0];
      final b = tracks[1];
      return b.left >= a.right - .5 &&
          b.left - a.right <= g.maxGap + .5 &&
          a.top < b.bottom &&
          b.top < a.bottom &&
          (a.top - b.top).abs() <= .5;
    }
    return tracks.length == 1;
  }

  static bool _relationSatisfied(
    SemanticRelationExpectation relation,
    Map<String, Bounds> byId,
    double captionGapTolerance,
    Set<String> blockIds,
  ) {
    final anchor = byId[relation.anchorId];
    final follower = byId[relation.followerId];
    if (anchor == null || follower == null) return false;
    final horizontalOverlap =
        follower.left < anchor.right && anchor.left < follower.right;
    final gap = follower.top - anchor.bottom;
    if (!horizontalOverlap ||
        gap < -0.5 ||
        gap > (relation.maxGap ?? captionGapTolerance) + 0.5) {
      return false;
    }
    // 无关块不能插在关联两端之间；允许同组其他说明/图注。
    for (final id in blockIds) {
      if (id == relation.anchorId ||
          id == relation.followerId ||
          relation.memberIds.contains(id)) {
        continue;
      }
      final box = byId[id];
      if (box == null) continue;
      if (box.top >= anchor.bottom &&
          box.bottom <= follower.top &&
          box.right > anchor.left &&
          box.left < anchor.right) {
        return false;
      }
    }
    return true;
  }
}

/// 渲染层 canonical digest（确定性：层按元素 id 排序、全几何+资源状态
/// 参与；missing 列表排序参与）。提取器与硬门禁共用——任何层几何被
/// 替换都会使 digest 断链（fail closed）。
String reducedSceneDigestOf(DraftRenderSnapshot snapshot) {
  final sortedLayers = snapshot.layers.toList()
    ..sort((a, b) => a.elementId.compareTo(b.elementId));
  final sortedMissing = snapshot.missingFileIds.toList()..sort();
  final payload = [
    for (final layer in sortedLayers)
      '${layer.elementId}|${layer.kind}|${_n(layer.bounds.left)},'
          '${_n(layer.bounds.top)},${_n(layer.bounds.size.width)},'
          '${_n(layer.bounds.size.height)}|${layer.resourceStatus.name}',
    'missing=${sortedMissing.join(',')}',
  ].join('~');
  return fingerprint64('draft-render|$payload');
}

String _n(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.roundToDouble().toInt().toString();
  }
  return v.toString();
}
