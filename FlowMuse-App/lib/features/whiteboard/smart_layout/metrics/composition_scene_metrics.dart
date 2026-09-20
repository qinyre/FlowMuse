import 'dart:convert';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../rendering/draft_scene_renderer.dart';
import '../snapshot/deterministic_hash.dart';
import '../validation/reduced_scene_metrics_extractor.dart';
import 'layout_metric_contract.dart';
import 'layout_profile.dart';

/// 同一输入冻结适用性和关系分母。原稿是只读 Scene，不造 no-op patch。
/// ponytail: <=128 块用两两几何检查；长文档再考虑空间索引。
class CompositionMetricContext {
  CompositionMetricContext({
    required this.source,
    required this.page,
    required this.analyzed,
    this.pageIntent = 'unknown',
  });

  static const version = 'composition-score/2';
  final LayoutBlockAssembly source;
  final Bounds page;
  final bool analyzed;
  final String pageIntent;

  List<LayoutBlock> get blocks =>
      source.blocks.where((b) => !b.isPreservedLike).toList();

  List<List<String>> get groups {
    final ids = blocks
        .where((b) => b.kind != LayoutBlockKind.title)
        .map((b) => b.id)
        .toSet();
    final sets = <Set<String>>[
      for (final id in ids) {id},
    ];
    for (final r in source.relationships) {
      if (!ids.contains(r.fromBlockId) || !ids.contains(r.toBlockId)) continue;
      final a = sets.indexWhere((s) => s.contains(r.fromBlockId));
      final b = sets.indexWhere((s) => s.contains(r.toBlockId));
      if (a != b) {
        sets[a].addAll(sets[b]);
        sets.removeAt(b);
      }
    }
    final groupOf = {
      for (final s in sets)
        for (final id in s) id: s,
    };
    final emitted = <String>{};
    return [
      for (final b in blocks)
        if (!emitted.contains(b.id))
          () {
            final group = groupOf[b.id] ?? {b.id};
            emitted.addAll(group);
            return blocks
                .where((b) => group.contains(b.id))
                .map((b) => b.id)
                .toList();
          }(),
    ];
  }

  Map<String, Bounds> boxes(
    DraftRenderSnapshot snapshot,
    Map<String, List<String>> mapping,
  ) {
    final layers = {for (final l in snapshot.layers) l.elementId: l};
    final result = <String, Bounds>{};
    for (final b in blocks) {
      final ids = mapping[b.id] ?? b.sourceRefs;
      final found = [for (final id in ids) layers[id]];
      if (found.isEmpty ||
          found.any(
            (l) => l == null || l.resourceStatus == DraftResourceStatus.missing,
          )) {
        continue;
      }
      result[b.id] = found.map((l) => l!.bounds).reduce((a, b) => a.union(b));
    }
    return result;
  }

  LayoutMetricVector calculate({
    required Scene scene,
    required DraftRenderSnapshot snapshot,
    required Map<String, Bounds> originalBounds,
    Map<String, List<String>> mapping = const {},
  }) {
    final bs = blocks;
    final rects = boxes(snapshot, mapping);
    final elements = {for (final e in scene.activeElements) e.id.value: e};
    final states = {
      for (final id in LayoutMetricId.values) id: LayoutMetricState.evaluated,
    };
    final values = {for (final id in LayoutMetricId.values) id: 0.0};
    final hasText = bs.any((b) => b.text != null);
    final hasFigure = bs.any((b) => b.figure != null);
    final components = groups;
    final media = components
        .where(
          (g) =>
              g.any((id) => source.blockById(id)?.figure != null) &&
              g.any((id) => source.blockById(id)?.text != null),
        )
        .toList();
    if (!hasText) {
      states[LayoutMetricId.hierarchy] = LayoutMetricState.notApplicable;
    }
    if (!hasText || !hasFigure) {
      states[LayoutMetricId.figureTextAffinity] =
          LayoutMetricState.notApplicable;
    } else if (!analyzed || media.isEmpty) {
      states[LayoutMetricId.figureTextAffinity] = LayoutMetricState.unavailable;
    }
    if (bs.length < 2) {
      for (final id in [
        LayoutMetricId.readingOrder,
        LayoutMetricId.alignmentRhythm,
        LayoutMetricId.densityWhitespace,
        LayoutMetricId.visualBalance,
      ]) {
        states[id] = LayoutMetricState.notApplicable;
      }
    }
    if (!analyzed && bs.length > 1) {
      states[LayoutMetricId.readingOrder] = LayoutMetricState.unavailable;
    }
    if (!analyzed && hasText) {
      states[LayoutMetricId.hierarchy] = LayoutMetricState.unavailable;
    }
    if (rects.length != bs.length) {
      for (final id in states.keys) {
        if (states[id] == LayoutMetricState.evaluated) {
          states[id] = LayoutMetricState.unavailable;
        }
      }
      return _vector(values, states, snapshot, scene);
    }
    final scale = page.size.width / 1024;
    final em = 24 * scale;
    final groupRects = [
      for (final g in components)
        g.map((id) => rects[id]!).reduce((a, b) => a.union(b)),
    ];
    final groupIndex = {
      for (var i = 0; i < components.length; i++)
        for (final id in components[i]) id: i,
    };
    double distance(Bounds a, Bounds b) {
      final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
      final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
      return math.sqrt(dx * dx + dy * dy);
    }

    double average(Iterable<double> numbers) =>
        numbers.isEmpty ? 1 : numbers.reduce((a, b) => a + b) / numbers.length;
    bool precedes(Bounds a, Bounds b) {
      if (a.bottom <= b.top + .5) return true;
      return a.right <= b.left + .5 && a.top < b.bottom && b.top < a.bottom;
    }

    values[LayoutMetricId.readingOrder] = average([
      for (var i = 0; i + 1 < bs.length; i++)
        () {
          final a = bs[i].id, b = bs[i + 1].id;
          final same = groupIndex[a] == groupIndex[b];
          return precedes(
                same ? rects[a]! : groupRects[groupIndex[a]!],
                same ? rects[b]! : groupRects[groupIndex[b]!],
              )
              ? 1.0
              : 0.0;
        }(),
    ]);
    values[LayoutMetricId.figureTextAffinity] = average([
      for (final g in media)
        for (var i = 0; i + 1 < g.length; i++)
          1 / (1 + distance(rects[g[i]]!, rects[g[i + 1]]!) / (4 * em)),
    ]);

    // 字号/行高来自实际 TextElement + painter 墨迹盒。原笔迹用实际区域
    // 高度/物理行数比较可读尺度，不因没有 TextElement 就判原稿为零分。
    final lineHeights = <String, double>{};
    final legibility = <double>[];
    for (final b in bs.where((b) => b.text != null)) {
      final outputs = (mapping[b.id] ?? b.sourceRefs)
          .map((id) => elements[id])
          .toList();
      final text = outputs.whereType<TextElement>().firstOrNull;
      final raw = b.text!.projection?.rawText ?? b.text!.text;
      final rect = rects[b.id]!;
      final height = text != null
          ? text.fontSize * text.lineHeight
          : rect.size.height / math.max(1, raw.split('\n').length);
      lineHeights[b.id] = height;
      final lines = math.max(
        1,
        (rect.size.height / math.max(1, height)).round(),
      );
      final displayed = text?.text ?? raw;
      final chars = displayed.runes.where((r) => r > 32).length;
      var quality = (height / (16 * scale)).clamp(0.0, 1.0);
      if (rect.size.width / math.max(1, height) > 36) quality *= .75;
      if (b.textOrigin == LayoutTextOrigin.transcribed &&
          chars >= 6 &&
          lines > 1 &&
          chars / lines < 4) {
        quality *= .6;
      }
      legibility.add(quality);
    }
    final bodyHeights = [
      for (final b in bs)
        if (b.text != null && b.kind != LayoutBlockKind.title)
          lineHeights[b.id]!,
    ];
    final hierarchy = <double>[];
    if (bodyHeights.isNotEmpty) {
      final body = average(bodyHeights);
      for (final b in bs.where(
        (b) => b.kind == LayoutBlockKind.title && b.text != null,
      )) {
        final ratio = lineHeights[b.id]! / math.max(1, body);
        hierarchy.add(
          (ratio / 1.3).clamp(0.0, 1.0) * (ratio > 2.2 ? 2.2 / ratio : 1),
        );
      }
    }
    values[LayoutMetricId.hierarchy] = hierarchy.isEmpty
        ? average(legibility)
        : .65 * average(legibility) + .35 * average(hierarchy);

    final alignment = <double>[];
    for (final g in components) {
      for (var i = 0; i + 1 < g.length; i++) {
        final a = rects[g[i]]!, b = rects[g[i + 1]]!;
        alignment.add(
          1 /
              (1 +
                  math.min((a.left - b.left).abs(), (a.top - b.top).abs()) /
                      em),
        );
      }
    }
    for (var i = 0; i + 1 < groupRects.length; i++) {
      final a = groupRects[i], b = groupRects[i + 1];
      alignment.add(
        1 / (1 + math.min((a.left - b.left).abs(), (a.top - b.top).abs()) / em),
      );
    }
    // 普通阅读页也可能包含同一章节的短图注对照，不能完全依赖模型的
    // pageIntent 标签。仅同级短图注适用，长正文/列表不因此被挤进并列。
    final shortCaptionPeers =
        media.length >= 2 &&
        media.length <= 3 &&
        media.every((g) {
          final members = g.map((id) => source.blockById(id)!).toList();
          final texts = members.where((b) => b.text != null).toList();
          return members.where((b) => b.figure != null).length == 1 &&
              texts.isNotEmpty &&
              texts.every((b) => b.kind == LayoutBlockKind.caption) &&
              texts.fold<int>(0, (sum, b) => sum + b.text!.text.runes.length) <=
                  80;
        }) &&
        {
              for (final g in media)
                for (final id in g) source.blockById(id)!.extras['sectionId'],
            }.length ==
            1;
    if ((pageIntent == 'comparison' || shortCaptionPeers) && media.length > 1) {
      for (var i = 0; i + 1 < media.length; i++) {
        final a =
            rects[media[i].firstWhere(
              (id) => source.blockById(id)?.figure != null,
            )]!;
        final b =
            rects[media[i + 1].firstWhere(
              (id) => source.blockById(id)?.figure != null,
            )]!;
        // 短同级比较内容共享图顶更容易横向对照；长组仍可单列。
        alignment.add((a.top - b.top).abs() < em ? 1 : .65);
      }
    }
    values[LayoutMetricId.alignmentRhythm] = average(alignment);
    if (groupRects.isNotEmpty) {
      final envelope = groupRects.reduce((a, b) => a.union(b));
      final area = groupRects.fold<double>(
        0,
        (sum, b) => sum + b.size.width * b.size.height,
      );
      // 只评价内容包络中的空洞，不要求短笔记占满页面，也不奖赏搬到页底。
      values[LayoutMetricId.densityWhitespace] =
          (area / math.max(1, envelope.size.width * envelope.size.height))
              .clamp(0.0, 1.0);
      final weightedX =
          groupRects.fold<double>(
            0,
            (sum, b) =>
                sum + (b.left + b.right) / 2 * b.size.width * b.size.height,
          ) /
          math.max(1, area);
      values[LayoutMetricId.visualBalance] =
          (1 -
                  (weightedX - (page.left + page.right) / 2).abs() /
                      math.max(1, page.size.width))
              .clamp(0.0, 1.0);
    }
    final diagonal = math.sqrt(
      page.size.width * page.size.width + page.size.height * page.size.height,
    );
    values[LayoutMetricId.modificationCost] = average([
      for (final b in bs)
        () {
          final old = originalBounds[b.id], now = rects[b.id]!;
          if (old == null) return 0.0;
          final change =
              (old.left - now.left).abs() +
              (old.top - now.top).abs() +
              (old.size.width - now.size.width).abs() +
              (old.size.height - now.size.height).abs();
          return (1 - change / math.max(1, diagonal)).clamp(0.0, 1.0);
        }(),
    ]);
    return _vector(values, states, snapshot, scene);
  }

  LayoutMetricVector _vector(
    Map<LayoutMetricId, double> values,
    Map<LayoutMetricId, LayoutMetricState> states,
    DraftRenderSnapshot snapshot,
    Scene scene,
  ) => LayoutMetricVector(
    values: {
      for (final id in values.keys)
        id: states[id] == LayoutMetricState.evaluated ? values[id]! : 0,
    },
    states: Map.unmodifiable(states),
    factsFingerprint: fingerprint64(
      jsonEncode([
        version,
        analyzed,
        pageIntent,
        reducedSceneDigestOf(snapshot),
        for (final b in blocks) [b.id, b.kind.name, b.sourceRefs],
        groups,
        for (final e in scene.activeElements.whereType<TextElement>())
          [e.id.value, e.text, e.fontFamily, e.fontSize, e.lineHeight],
      ]),
    ),
  );
}

/// 推荐是一份只读比较结论，不持有 patch，不可交给提交网关。
class CompositionRecommendation {
  const CompositionRecommendation({
    required this.baseline,
    required this.improvement,
    required this.recommended,
    required this.reason,
  });
  final LayoutMetricVector baseline;
  final double? improvement;
  final bool recommended;
  final String reason;

  factory CompositionRecommendation.compare(
    LayoutMetricVector baseline,
    LayoutMetricVector? best,
  ) {
    final incomplete =
        best == null ||
        LayoutMetricId.values.any(
          (id) =>
              baseline.stateOf(id) == LayoutMetricState.unavailable ||
              best.stateOf(id) == LayoutMetricState.unavailable,
        );
    if (incomplete) {
      return CompositionRecommendation(
        baseline: baseline,
        improvement: null,
        recommended: false,
        reason: best == null ? '没有安全的重排结果，保留原样。' : '分析信息不足，可预览保守方案；暂不判断优于原稿。',
      );
    }
    var before = 0.0, after = 0.0, weight = 0.0;
    for (final id in LayoutMetricId.values) {
      if (baseline.stateOf(id) != LayoutMetricState.evaluated ||
          best.stateOf(id) != LayoutMetricState.evaluated) {
        continue;
      }
      final w = LayoutProfile.composition.weights[id]!;
      weight += w;
      before += w * baseline[id];
      after += w * best[id];
    }
    final delta = weight > 0 ? (after - before) / weight : 0.0;
    final recommended = delta >= .05;
    final improved = <String>[];
    for (final (id, label) in [
      (LayoutMetricId.figureTextAffinity, '图文更贴近'),
      (LayoutMetricId.readingOrder, '阅读顺序更清楚'),
      (LayoutMetricId.hierarchy, '文字层级更清楚'),
      (LayoutMetricId.alignmentRhythm, '同级内容更整齐'),
      (LayoutMetricId.densityWhitespace, '内容空隙更均匀'),
    ]) {
      if (best[id] - baseline[id] >= .05) improved.add(label);
    }
    return CompositionRecommendation(
      baseline: baseline,
      improvement: delta,
      recommended: recommended,
      reason: recommended
          ? '${improved.isEmpty ? '整体组织有所改善' : improved.take(3).join('、')}。评分仅用于版式比较。'
          : '当前布局已较合理，可保留原样；也可手动预览其他版式。',
    );
  }
}
