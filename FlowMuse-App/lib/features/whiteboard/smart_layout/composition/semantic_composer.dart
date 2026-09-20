import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../design/text_measure_adapter.dart';
import '../geometry/layout_rect.dart';
import '../metrics/layout_structure_signature.dart';
import '../placement/balanced_flow_placer.dart';
import '../placement/flow_placer.dart';
import '../snapshot/layout_page_snapshot.dart';
import 'composition_policy.dart';
import 'layout_block.dart';
import 'layout_block_assembler.dart';

class SemanticCompositionLayout {
  const SemanticCompositionLayout({
    required this.family,
    required this.policy,
    required this.assembly,
    required this.placed,
    required this.groups,
    required this.content,
    required this.preservedRects,
  });

  final String family;
  final CompositionPolicy policy;
  final LayoutBlockAssembly assembly;
  final List<PlacedBlock> placed;
  final List<CompositionGroupIntent> groups;
  final LayoutRect content;
  final Map<String, LayoutRect> preservedRects;

  String get signature => const LayoutStructureSignature().compositionOf(
    placed: placed,
    groups: groups,
    scale: policy.scale,
  );
}

/// V3 组内实测 → 外层行流。复用字体测量缓存、障碍切割和既有物化器。
/// 不调用模型、不把标题 keepWith 传递成一整个章节的原子组。
abstract final class SemanticComposer {
  static Future<List<SemanticCompositionLayout>> generate({
    required Scene scene,
    required LayoutBlockAssembly assembly,
    required LayoutRect pageFrame,
    required TextMeasureAdapter measure,
    Map<String, LayoutRect> fixedObstacles = const {},
  }) async {
    if (pageFrame.width <= 0 || pageFrame.height <= 0) return const [];
    final pixels = await _imagePixels(scene, assembly);
    final unavailable = assembly.blocks
        .where(
          (b) =>
              b.figure != null &&
              b.extras['nativeComposite'] != true &&
              !pixels.containsKey(b.figure!.fileId),
        )
        .map((b) => b.id)
        .toSet();
    if (unavailable.isNotEmpty) assembly = _preserve(assembly, unavailable);
    if (assembly.blocks.every((b) => b.isPreservedLike)) return const [];
    final layouts = <SemanticCompositionLayout>[];
    final signatures = <String>{};
    // 每家族先正常间距，再压间距/改单列，最后统一紧凑档。最多四个成品。
    for (final family in [
      'single',
      'mediaSide',
      'peerGrid',
      'conservativeLayout',
    ]) {
      SemanticCompositionLayout? layout;
      _CannotFit? failure;
      for (final (compact, tight) in [
        (false, false),
        (false, true),
        (true, true),
      ]) {
        final policy = CompositionPolicy(
          pageWidth: pageFrame.width,
          compact: compact,
          tight: tight,
        );
        final styled = _styled(scene, assembly, policy);
        try {
          layout = _page(
            scene,
            styled,
            pageFrame,
            measure,
            pixels,
            fixedObstacles,
            family,
            policy,
          );
          break;
        } on _CannotFit catch (error) {
          failure = error;
          if (tight && family != 'single' && family != 'conservativeLayout') {
            try {
              layout = _page(
                scene,
                styled,
                pageFrame,
                measure,
                pixels,
                fixedObstacles,
                'single',
                policy,
              );
              break;
            } on _CannotFit catch (fallback) {
              failure = fallback;
            }
          }
        }
      }
      if (layout == null && failure != null) {
        final policy = CompositionPolicy(
          pageWidth: pageFrame.width,
          compact: true,
          tight: true,
        );
        var remaining = _styled(scene, assembly, policy);
        // ponytail: 最多按块数重排一次失败组件；128-unit 上限内线性轮数，
        // 若将来支持长文档，再用增量段流替代这段小规模重算。
        for (var i = 0; i < assembly.blocks.length; i++) {
          remaining = _preserve(remaining, failure!.ids);
          if (remaining.blocks.every((b) => b.isPreservedLike)) break;
          try {
            layout = _page(
              scene,
              remaining,
              pageFrame,
              measure,
              pixels,
              fixedObstacles,
              'single',
              policy,
            );
            break;
          } on _CannotFit catch (error) {
            failure = error;
          }
        }
      }
      if (layout != null && signatures.add(layout.signature)) {
        layouts.add(layout);
      }
    }
    return List.unmodifiable(layouts);
  }

  static LayoutBlockAssembly _styled(
    Scene scene,
    LayoutBlockAssembly assembly,
    CompositionPolicy policy,
  ) {
    final byId = {for (final e in scene.activeElements) e.id.value: e};
    return _assembly(assembly, [
      for (final b in assembly.blocks)
        () {
          if (b.isPreservedLike || b.extras['nativeComposite'] == true) {
            return b;
          }
          final original = b.sourceRefs.length == 1
              ? byId[b.sourceRefs.single]
              : null;
          final spec = b.text;
          if (spec == null) return b;
          final raw = spec.projection?.rawText ?? spec.text;
          final projection =
              spec.projection ??
              DisplayTextProjection.create(
                rawText: raw,
                origin: b.textOrigin ?? LayoutTextOrigin.typed,
                kind: b.kind,
              );
          return _block(
            b,
            text: TextBlockSpec(
              text: projection.displayText,
              fontFamily: original is TextElement
                  ? original.fontFamily
                  : spec.fontFamily,
              fontSize: policy.fontSize(
                b.kind,
                sectionHeading: b.extras['sectionHeading'] == true,
              ),
              lineHeight: policy.lineHeight(b.kind),
              direction: spec.direction,
              projection: projection,
            ),
          );
        }(),
    ]);
  }

  static SemanticCompositionLayout _page(
    Scene scene,
    LayoutBlockAssembly assembly,
    LayoutRect frame,
    TextMeasureAdapter measure,
    Map<String, ui.Size> pixels,
    Map<String, LayoutRect> fixed,
    String family,
    CompositionPolicy policy,
  ) {
    final content = LayoutRect(
      left: frame.left + policy.margin,
      top: frame.top + policy.margin,
      width: frame.width - 2 * policy.margin,
      height: frame.height - 2 * policy.margin,
    );
    final active = assembly.blocks.where((b) => !b.isPreservedLike).toList();
    if (content.isDegenerate) throw _CannotFit(active.map((b) => b.id).toSet());
    final units = _units(assembly);
    final preserved = <String, LayoutRect>{
      for (final b in assembly.blocks.where((b) => b.isPreservedLike))
        b.id: _originalBounds(scene, b),
    };
    final segments = const ColumnRegionBuilder().splitColumn(content, [
      ...fixed.values,
      ...preserved.values,
    ]);
    final media = units.where(_isMedia).length;
    final grid = family == 'peerGrid' && media >= 2 && media <= 4;
    final cellWidth = grid
        ? (content.width - policy.groupGap) / 2
        : content.width;
    if (grid && cellWidth < 12 * policy.bodySize) {
      throw _CannotFit(active.map((b) => b.id).toSet());
    }
    final imageHeightBudget =
        content.height / math.max(1, grid ? (media / 2).ceil() : media);
    final rows = <List<_LocalGroup>>[];
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      final members = <_LocalGroup>[];
      final pair =
          grid &&
          _isMedia(unit) &&
          i + 1 < units.length &&
          _isMedia(units[i + 1]) &&
          unit.first.extras['sectionId'] ==
              units[i + 1].first.extras['sectionId'];
      members.add(
        _local(
          scene,
          unit,
          pair ? cellWidth : content.width,
          imageHeightBudget,
          measure,
          pixels,
          family == 'mediaSide',
          policy,
        ),
      );
      if (pair) {
        members.add(
          _local(
            scene,
            units[++i],
            cellWidth,
            imageHeightBudget,
            measure,
            pixels,
            false,
            policy,
          ),
        );
        if (members.any(
          (g) => g.placed.where((p) => p.lineCount > 8).isNotEmpty,
        )) {
          throw _CannotFit(members.expand((g) => g.ids).toSet());
        }
        // 同行图顶对齐，前置说明底对齐；整组平移，不拉大图注内间距。
        final imageTops = [
          for (final g in members)
            g.placed
                .firstWhere(
                  (p) => assembly.blockById(p.blockId)?.figure != null,
                )
                .rect
                .top,
        ];
        final target = imageTops.reduce(math.max);
        for (var m = 0; m < members.length; m++) {
          members[m] = members[m].shiftDown(target - imageTops[m]);
        }
      }
      rows.add(members);
    }
    if (segments.isEmpty) throw _CannotFit(active.map((b) => b.id).toSet());
    final placed = <PlacedBlock>[];
    final groups = <CompositionGroupIntent>[];
    var segment = 0;
    var y = segments.first.top;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final height = row.map((g) => g.height).reduce(math.max);
      final heading =
          row.length == 1 &&
          assembly.blockById(row.single.ids.first)?.kind ==
              LayoutBlockKind.title;
      final previousHeading =
          r > 0 &&
          rows[r - 1].length == 1 &&
          assembly.blockById(rows[r - 1].single.ids.first)?.kind ==
              LayoutBlockKind.title;
      final gap = r == 0
          ? 0.0
          : previousHeading
          ? policy.innerGap
          : heading
          ? policy.sectionGap
          : policy.groupGap;
      y += gap;
      var nextHeight = 0.0;
      if (heading) {
        // 连续标题只带到第一个内容组，不把后续整章变成原子组。
        for (var next = r + 1; next < rows.length; next++) {
          nextHeight +=
              policy.innerGap +
              rows[next].map((g) => g.height).reduce(math.max);
          if (rows[next].length != 1 ||
              assembly.blockById(rows[next].single.ids.first)?.kind !=
                  LayoutBlockKind.title) {
            break;
          }
        }
      }
      while (y + height + nextHeight > segments[segment].bottom + .001) {
        if (++segment == segments.length) {
          throw _CannotFit(row.expand((g) => g.ids).toSet());
        }
        y = segments[segment].top;
      }
      for (var c = 0; c < row.length; c++) {
        final g = row[c];
        final left = content.left + (c == 0 ? 0 : cellWidth + policy.groupGap);
        for (final p in g.placed) {
          placed.add(
            PlacedBlock(
              blockId: p.blockId,
              rect: LayoutRect(
                left: left + p.rect.left,
                top: y + p.rect.top,
                width: p.rect.width,
                height: p.rect.height,
              ),
              columnIndex: c,
              lineCount: p.lineCount,
              appliedFontSize: p.appliedFontSize,
              shrunk: policy.compact,
            ),
          );
        }
        groups.add(
          CompositionGroupIntent(
            id: g.ids.first,
            kind: g.kind,
            tracks: g.tracks,
            slot: LayoutRect(
              left: left,
              top: y,
              width: g.width,
              height: g.height,
            ),
            row: r,
            column: c,
            maxGap: policy.innerGap,
          ),
        );
      }
      y += height;
    }
    final order = {
      for (var i = 0; i < assembly.blocks.length; i++) assembly.blocks[i].id: i,
    };
    placed.sort((a, b) => order[a.blockId]!.compareTo(order[b.blockId]!));
    return SemanticCompositionLayout(
      family: family,
      policy: policy,
      assembly: assembly,
      placed: List.unmodifiable(placed),
      groups: List.unmodifiable(groups),
      content: content,
      preservedRects: Map.unmodifiable(preserved),
    );
  }

  static List<List<LayoutBlock>> _units(LayoutBlockAssembly assembly) {
    final active = assembly.blocks.where((b) => !b.isPreservedLike).toList();
    final groupOf = <String, Set<String>>{};
    for (final group in assembly.atomicGroups) {
      final ids = active
          .where((b) => group.contains(b.id) && b.kind != LayoutBlockKind.title)
          .map((b) => b.id)
          .toSet();
      if (ids.isEmpty) continue;
      final indexes = [
        for (var i = 0; i < active.length; i++)
          if (ids.contains(active[i].id)) i,
      ];
      if (indexes.last - indexes.first + 1 != ids.length) throw _CannotFit(ids);
      for (final id in ids) {
        groupOf[id] = ids;
      }
    }
    final emitted = <String>{};
    return [
      for (final b in active)
        if (!emitted.contains(b.id))
          () {
            final members = groupOf[b.id] ?? {b.id};
            emitted.addAll(members);
            return active.where((b) => members.contains(b.id)).toList();
          }(),
    ];
  }

  static bool _isMedia(List<LayoutBlock> unit) =>
      unit.any(
        (b) => b.figure != null && b.extras['nativeComposite'] != true,
      ) &&
      unit.any((b) => b.text != null);

  static _LocalGroup _local(
    Scene scene,
    List<LayoutBlock> unit,
    double width,
    double imageHeightBudget,
    TextMeasureAdapter measure,
    Map<String, ui.Size> pixels,
    bool preferSide,
    CompositionPolicy policy,
  ) {
    final ids = unit.map((b) => b.id).toSet();
    final media = _isMedia(unit);
    final pictureTrack = unit
        .where((b) => b.figure != null || b.kind == LayoutBlockKind.caption)
        .toList();
    final textTrack = unit
        .where((b) => b.figure == null && b.kind != LayoutBlockKind.caption)
        .toList();
    // B 先处理现有一图多说明；C 多图组复用同一组及轨道，不复制正文。
    var side =
        preferSide &&
        media &&
        textTrack.isNotEmpty &&
        width * .6 - policy.innerGap >= 12 * policy.bodySize;
    var pictureWidth = width * (side ? .4 : .6);
    final figureWidths = [
      for (final b in pictureTrack.where((b) => b.figure != null))
        _figureSize(
          scene,
          b,
          pictureWidth,
          imageHeightBudget,
          pixels,
          policy,
        ).width,
    ];
    if (side &&
        (figureWidths.isEmpty ||
            figureWidths.any((w) => w < 4 * policy.bodySize))) {
      side = false;
    }
    if (side) {
      pictureWidth = math.max(
        figureWidths.reduce(math.max),
        pictureTrack.any((b) => b.text != null) ? 6 * policy.bodySize : 0,
      );
    }
    final tracks = side ? [pictureTrack, textTrack] : [unit];
    // 不改语义阅读序：文字在图前时也保留先文字后图（左→右）。
    if (side &&
        unit.indexOf(textTrack.first) < unit.indexOf(pictureTrack.first)) {
      tracks.setAll(0, [textTrack, pictureTrack]);
    }
    if (side &&
        tracks.expand((t) => t).map((b) => b.id).join('|') !=
            unit.map((b) => b.id).join('|')) {
      return _local(
        scene,
        unit,
        width,
        imageHeightBudget,
        measure,
        pixels,
        false,
        policy,
      );
    }
    final placed = <PlacedBlock>[];
    var left = 0.0;
    var totalHeight = 0.0;
    for (final track in tracks) {
      final isPicture = side && identical(track, pictureTrack);
      final trackWidth = side
          ? isPicture
                ? pictureWidth
                : width - pictureWidth - policy.innerGap
          : width;
      var y = 0.0;
      var occupiedWidth = 0.0;
      // 图片高度预算扣除同轨道实测文字；长文字不能靠压扁图片/字体强塞。
      final textHeight = track
          .where((b) => b.text != null)
          .fold<double>(
            0,
            (h, b) =>
                h +
                _measure(
                  b.text!,
                  math.min(trackWidth, policy.maxTextWidth),
                  measure,
                ).height,
          );
      final figures = track.where((b) => b.figure != null).length;
      final maxImageHeight = math.max(
        policy.bodySize * 4,
        (imageHeightBudget -
                textHeight -
                policy.innerGap * (track.length - 1)) /
            math.max(1, figures),
      );
      for (final b in track) {
        double w, h;
        var lines = 1;
        var font = 0.0;
        if (b.text != null) {
          w = math.min(trackWidth, policy.maxTextWidth);
          final m = _measure(b.text!, w, measure);
          if (m.overflows || m.height <= 0) throw _CannotFit(ids);
          h = m.height;
          w = m.width;
          lines = m.lineCount;
          font = b.text!.fontSize;
        } else if (b.figure != null) {
          final maxWidth = media && !side ? width * .6 : trackWidth;
          final size = _figureSize(
            scene,
            b,
            maxWidth,
            maxImageHeight,
            pixels,
            policy,
          );
          w = size.width;
          h = size.height;
        } else {
          throw _CannotFit(ids);
        }
        if (w <= 0 || h <= 0) throw _CannotFit(ids);
        placed.add(
          PlacedBlock(
            blockId: b.id,
            rect: LayoutRect(left: left, top: y, width: w, height: h),
            columnIndex: 0,
            lineCount: lines,
            appliedFontSize: font,
            shrunk: policy.compact,
          ),
        );
        y += h + policy.innerGap;
        occupiedWidth = math.max(occupiedWidth, w);
      }
      totalHeight = math.max(totalHeight, y - policy.innerGap);
      left += occupiedWidth + policy.innerGap;
    }
    return _LocalGroup(
      ids: unit.map((b) => b.id).toList(),
      kind: !media
          ? CompositionGroupKind.textFlow
          : side
          ? CompositionGroupKind.mediaSide
          : CompositionGroupKind.mediaStack,
      tracks: tracks.map((t) => t.map((b) => b.id).toList()).toList(),
      placed: placed,
      width: width,
      height: totalHeight,
    );
  }

  static TextMeasureResult _measure(
    TextBlockSpec spec,
    double width,
    TextMeasureAdapter measure,
  ) => measure.measure(
    text: spec.text,
    fontFamily: spec.fontFamily,
    fontSize: spec.fontSize,
    lineHeight: spec.lineHeight,
    maxWidth: width,
    direction: spec.direction == TextDirectionSpec.rtl
        ? ui.TextDirection.rtl
        : ui.TextDirection.ltr,
  );

  static ui.Size _figureSize(
    Scene scene,
    LayoutBlock b,
    double width,
    double maxHeight,
    Map<String, ui.Size> pixels,
    CompositionPolicy policy,
  ) {
    final original = _originalBounds(scene, b);
    var ratio = original.width / original.height;
    var limit = original.width;
    if (b.sourceRefs.length == 1) {
      final e = scene.activeElements.firstWhere(
        (e) => e.id.value == b.sourceRefs.single,
      );
      if (e is ImageElement) {
        ratio = e.width / e.height; // 已显示比例含 crop；不能把 crop 再乘一次。
        final px = pixels[e.fileId];
        if (px != null) {
          limit =
              math.min(
                px.width * (e.crop?.width ?? 1),
                px.height * (e.crop?.height ?? 1) * ratio,
              ) *
              policy.scale;
        }
      }
    }
    if (!ratio.isFinite || ratio <= 0) throw _CannotFit({b.id});
    final w = math.min(math.min(width, limit), maxHeight * ratio);
    if (b.extras['nativeComposite'] == true &&
        scene.activeElements.whereType<TextElement>().any(
          (e) =>
              b.sourceRefs.contains(e.id.value) &&
              e.fontSize * w / original.width < 12,
        )) {
      throw _CannotFit({b.id});
    }
    return ui.Size(w, w / ratio);
  }

  static LayoutRect _originalBounds(Scene scene, LayoutBlock block) =>
      LayoutRect.fromSnapshotBounds(
        scene.activeElements
            .where((e) => block.sourceRefs.contains(e.id.value))
            .map(conservativeVisualBounds)
            .reduce((a, b) => a.union(b)),
      );

  static LayoutBlockAssembly _preserve(
    LayoutBlockAssembly assembly,
    Set<String> failed,
  ) {
    final ids = {...failed};
    var changed = true;
    while (changed) {
      final before = ids.length;
      for (final r in assembly.relationships) {
        if (ids.contains(r.fromBlockId) || ids.contains(r.toBlockId)) {
          ids.addAll([r.fromBlockId, r.toBlockId]);
        }
      }
      changed = before != ids.length;
    }
    return _assembly(assembly, [
      for (final b in assembly.blocks)
        if (ids.contains(b.id))
          _block(
            b,
            kind: LayoutBlockKind.preserved,
            extras: {
              ...b.extras,
              'compositionPreserveReason': 'group-does-not-fit',
            },
          )
        else
          b,
    ]);
  }

  static LayoutBlock _block(
    LayoutBlock b, {
    LayoutBlockKind? kind,
    TextBlockSpec? text,
    Map<String, Object?>? extras,
  }) => LayoutBlock(
    id: b.id,
    kind: kind ?? b.kind,
    sourceRefs: b.sourceRefs,
    orderIndex: b.orderIndex,
    keepTogether: b.keepTogether,
    textOrigin: b.textOrigin,
    text: text ?? b.text,
    figure: b.figure,
    measuredIntrinsic: b.measuredIntrinsic,
    extras: extras ?? b.extras,
  );

  static LayoutBlockAssembly _assembly(
    LayoutBlockAssembly original,
    List<LayoutBlock> blocks,
  ) {
    final active = blocks
        .where((b) => !b.isPreservedLike)
        .map((b) => b.id)
        .toSet();
    return LayoutBlockAssembly(
      blocks: List.unmodifiable(blocks),
      relationships: original.relationships
          .where(
            (r) =>
                active.contains(r.fromBlockId) && active.contains(r.toBlockId),
          )
          .toList(),
      atomicGroups: original.atomicGroups,
      blockAliases: original.blockAliases,
      documentConsumedSourceIds: [
        for (final b in blocks.where((b) => !b.isPreservedLike))
          ...b.sourceRefs,
      ],
      documentPreservedSourceIds: [
        for (final b in blocks.where((b) => b.isPreservedLike)) ...b.sourceRefs,
      ],
    );
  }

  static Future<Map<String, ui.Size>> _imagePixels(
    Scene scene,
    LayoutBlockAssembly assembly,
  ) async {
    final result = <String, ui.Size>{};
    final ids = assembly.blocks.map((b) => b.figure?.fileId).nonNulls.toSet();
    for (final id in ids) {
      final bytes = scene.files[id]?.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        result[id] = ui.Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
      } catch (_) {
        // 尺寸无效由 generate 整组保留；不猜分辨率或放大不可见资产。
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    return result;
  }
}

class _LocalGroup {
  const _LocalGroup({
    required this.ids,
    required this.kind,
    required this.tracks,
    required this.placed,
    required this.width,
    required this.height,
  });
  final List<String> ids;
  final CompositionGroupKind kind;
  final List<List<String>> tracks;
  final List<PlacedBlock> placed;
  final double width;
  final double height;

  _LocalGroup shiftDown(double delta) => _LocalGroup(
    ids: ids,
    kind: kind,
    tracks: tracks,
    width: width,
    height: height + delta,
    placed: [
      for (final p in placed)
        PlacedBlock(
          blockId: p.blockId,
          rect: LayoutRect(
            left: p.rect.left,
            top: p.rect.top + delta,
            width: p.rect.width,
            height: p.rect.height,
          ),
          columnIndex: p.columnIndex,
          lineCount: p.lineCount,
          appliedFontSize: p.appliedFontSize,
          shrunk: p.shrunk,
        ),
    ],
  );
}

class _CannotFit implements Exception {
  const _CannotFit(this.ids);
  final Set<String> ids;
}
