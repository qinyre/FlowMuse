import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../composition/layout_composition_planner.dart';
import '../design/smart_layout_design_tokens.dart';
import '../design/text_measure_adapter.dart';
import '../geometry/layout_rect.dart';
import '../geometry/smart_layout_geometry_kernel.dart';
import '../snapshot/deterministic_hash.dart';
import 'flow_placer.dart';

/// 栏区域切割（V3-402B）：protected 障碍与栏相交时把栏切成障碍上/下
/// 可用段（零硬碰撞的构造性保证——放置只发生在可用段内）。
class ColumnRegionBuilder {
  const ColumnRegionBuilder();

  /// [obstacles]：protected 块的保守盒（绝对坐标）。
  /// 返回按上→下排序的可用段；无障碍时返回原栏。
  ///
  /// 段与障碍之间留 [_clearance] 亚像素间隙：V3-301A 冻结的是闭盒
  /// 相交语义（共边即相交），贴边放置会构成“硬碰撞”，必须严格分离。
  List<LayoutRect> splitColumn(
    LayoutRect column,
    List<LayoutRect> obstacles,
  ) {
    if (obstacles.isEmpty) return [column];
    // 收集与本栏横向重叠、纵向有交的障碍。
    final overlapping = obstacles
        .where(
          (o) =>
              o.left < column.right &&
              column.left < o.right &&
              o.top < column.bottom &&
              column.top < o.bottom,
        )
        .toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    if (overlapping.isEmpty) return [column];
    final segments = <LayoutRect>[];
    var cursorTop = column.top;
    for (final o in overlapping) {
      final blockedTop = o.top - _clearance;
      if (blockedTop > cursorTop) {
        segments.add(LayoutRect(
          left: column.left,
          top: cursorTop,
          width: column.width,
          height: blockedTop - cursorTop,
        ));
      }
      final resumeAt = o.bottom + _clearance;
      cursorTop = cursorTop < resumeAt ? resumeAt : cursorTop;
    }
    if (column.bottom > cursorTop) {
      segments.add(LayoutRect(
        left: column.left,
        top: cursorTop,
        width: column.width,
        height: column.bottom - cursorTop,
      ));
    }
    return segments;
  }

  /// 段与障碍的亚像素间隙（严格分离以满足闭盒零碰撞语义）。
  static const double _clearance = 1e-6;
}

/// 平衡放置结果（V3-402B）：402A 基础上加 preserved 原位投影、
/// 密度报告与 golden hash。
class BalancedPlacement {
  const BalancedPlacement({
    required this.placed,
    required this.usedHeights,
    required this.preservedRects,
    required this.density,
    required this.goldenHash,
  });

  final List<PlacedBlock> placed;
  final List<double> usedHeights;

  /// preserved/protected 块的原位坐标（保留路径 golden 输入）。
  final Map<String, LayoutRect> preservedRects;

  /// 内容区填充率（0~1；usedMax/内容高；软指标输入，不做硬门禁）。
  final double density;

  /// 确定性 golden：placed + preserved 的 canonical 指纹。
  final String goldenHash;
}

/// 平衡放置失败（含 402A 稳定码透传 + 页界超界）。
class BalancedPlacementFailure {
  const BalancedPlacementFailure({
    required this.kind,
    required this.blockId,
    this.detail = '',
  });

  final FlowPlacementFailureKind kind;
  final String blockId;
  final String detail;
}

/// V3-402B：栏高平衡、页界 contain、protected 绕置、密度报告与
/// golden geometry。全部在 FlowPlacer（402A）原语之上组合：
/// - 双栏平衡：保持阅读序枚举放置单元切分点，两栏各自在障碍切割后
///   的段流上放置，最小化两栏填充深度（最深块底 − 栏顶）的最大值
///   （组不拆；确定性：并列取更早切分点）；
/// - 绕置：栏先按 protected 保守盒切割成可用段（构造性零碰撞），
///   再按段流放置；
/// - contain：全部放置盒必须 ⊆ 页面内容区（kernel.pageContainsRect）；
/// - 密度：max(usedHeights)/contentHeight 报告值（不设硬门禁）；
/// - golden：canonical 指纹双跑一致（结果确定）。
class BalancedFlowPlacer {
  const BalancedFlowPlacer();

  Object placeBalanced({
    required LayoutBlockAssembly assembly,
    required CompositionCandidate candidate,
    required LayoutRect pageContent,
    required List<LayoutRect> columnRects,
    required double contentHeight,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    // 1. protected/preserved 收集：障碍切割 + 原位投影。
    final obstacles = <LayoutRect>[];
    final preservedRects = <String, LayoutRect>{};
    for (final block in assembly.blocks) {
      if (block.kind != LayoutBlockKind.protected) continue;
      final boundsJson = block.extras['bounds'];
      if (boundsJson is Map<String, Object?>) {
        final rect = LayoutRect(
          left: (boundsJson['left'] as num).toDouble(),
          top: (boundsJson['top'] as num).toDouble(),
          width: (boundsJson['width'] as num).toDouble(),
          height: (boundsJson['height'] as num).toDouble(),
        );
        obstacles.add(rect);
        preservedRects[block.id] = rect;
      }
    }
    for (final block in assembly.blocks) {
      if (block.kind != LayoutBlockKind.preserved) continue;
      final boundsJson = block.extras['bounds'];
      if (boundsJson is Map<String, Object?>) {
        preservedRects[block.id] = LayoutRect(
          left: (boundsJson['left'] as num).toDouble(),
          top: (boundsJson['top'] as num).toDouble(),
          width: (boundsJson['width'] as num).toDouble(),
          height: (boundsJson['height'] as num).toDouble(),
        );
      }
    }

    // 2. 障碍切割 → 段流（每栏上→下）。
    const splitter = ColumnRegionBuilder();
    final segmentFlow = <LayoutRect>[
      for (final column in columnRects) ...splitter.splitColumn(column, obstacles),
    ];
    if (segmentFlow.isEmpty) {
      return BalancedPlacementFailure(
        kind: FlowPlacementFailureKind.columnsExhausted,
        blockId: '*',
        detail: 'protected obstacles consume all column space',
      );
    }

    // 3. 非 twoColumn 结构（single 或更多栏）：全段流顺序放置——
    //    v1 栏平衡仅定义在双栏候选上（计划 §V3-402B）。
    if (columnRects.length != 2) {
      return _placeOnSegments(
        assembly: assembly,
        candidate: candidate,
        segments: segmentFlow,
        contentHeight: contentHeight,
        pageContent: pageContent,
        preservedRects: preservedRects,
        obstacles: obstacles,
        measure: measure,
        tokens: tokens,
      );
    }

    // 4. 双栏平衡：保持阅读序枚举放置单元切分点 k（前 k 单元入栏 0，
    //    其余入栏 1；原子组不拆），两侧各自在“本栏被障碍切割出的段流”
    //    上放置。平衡目标为栏填充深度（最深块底 − 栏顶），最小化两栏
    //    最大值，并列取更早切分点（确定性；k=n 即“栏 0 放不下才溢栏”
    //    的顺序流退化情形）。单个 k 不可行只跳过（顺序流溢出但切分
    //    可行是正常情形），全部 k 不可行才失败并报告首个失败（k=n
    //    顺序流的稳定原因）。
    final units = FlowPlacer.placementUnits(assembly);
    final leftSegments = splitter.splitColumn(columnRects[0], obstacles);
    final rightSegments = splitter.splitColumn(columnRects[1], obstacles);
    FlowPlacementSuccess? best;
    double bestMax = double.infinity;
    FlowPlacementFailure? firstFailure;

    double depthOf(Object? outcome, LayoutRect column) {
      if (outcome == null) return 0;
      var depth = 0.0;
      for (final p in (outcome as FlowPlacementSuccess).placed) {
        final d = p.rect.bottom - column.top;
        if (d > depth) depth = d;
      }
      return depth;
    }

    for (var k = units.length; k >= 0; k--) {
      final leftOutcome = _placePrefix(
        assembly,
        candidate,
        units,
        0,
        k,
        leftSegments,
        contentHeight,
        measure,
        tokens,
      );
      if (leftOutcome is FlowPlacementFailure) {
        firstFailure ??= leftOutcome;
        continue;
      }
      final rightOutcome = k >= units.length
          ? null
          : _placePrefix(
              assembly,
              candidate,
              units,
              k,
              units.length,
              rightSegments,
              contentHeight,
              measure,
              tokens,
            );
      if (rightOutcome is FlowPlacementFailure) {
        firstFailure ??= rightOutcome;
        continue;
      }
      final usedLeft = depthOf(leftOutcome, columnRects[0]);
      final usedRight = depthOf(rightOutcome, columnRects[1]);
      final leftSuccess = leftOutcome as FlowPlacementSuccess?;
      final rightSuccess = rightOutcome as FlowPlacementSuccess?;
      final worst = usedLeft > usedRight ? usedLeft : usedRight;
      // 越晚的 k 越接近"栏 0 优先"顺序流；择优并列时保留更早 k
      //（内容更均衡），严格更小才替换。
      if (worst < bestMax - 1e-9) {
        bestMax = worst;
        best = FlowPlacementSuccess(
          placed: [
            ...?leftSuccess?.placed.map((p) => PlacedBlock(
                  blockId: p.blockId,
                  rect: p.rect,
                  columnIndex: 0,
                  lineCount: p.lineCount,
                  appliedFontSize: p.appliedFontSize,
                  shrunk: p.shrunk,
                )),
            ...?rightSuccess?.placed.map((p) => PlacedBlock(
                  blockId: p.blockId,
                  rect: p.rect,
                  columnIndex: 1,
                  lineCount: p.lineCount,
                  appliedFontSize: p.appliedFontSize,
                  shrunk: p.shrunk,
                )),
          ],
          usedHeights: [usedLeft, usedRight],
        );
      }
    }
    if (best == null) {
      return firstFailure == null
          ? const BalancedPlacementFailure(
              kind: FlowPlacementFailureKind.columnsExhausted,
              blockId: '*',
              detail: 'no feasible column split',
            )
          : BalancedPlacementFailure(
              kind: firstFailure.kind,
              blockId: firstFailure.blockId,
              detail: firstFailure.detail,
            );
    }
    return _finalize(
      success: best,
      assembly: assembly,
      columnCount: 2,
      contentHeight: contentHeight,
      pageContent: pageContent,
      preservedRects: preservedRects,
      obstacles: obstacles,
    );
  }

  /// 把 [units)[from, end) 的成员按阅读序组成子装配，放置到该侧栏的
  /// 段流 [segments] 上；多成员单元重新登记为子装配的 atomicGroup，
  /// 保证组内 compact 间距与“不跨段拆组”语义不变。空前缀返回 null
  ///（该侧为空，填充深度 0）；段流被障碍整栏吃掉则该 k 不可行。
  Object? _placePrefix(
    LayoutBlockAssembly assembly,
    CompositionCandidate candidate,
    List<List<LayoutBlock>> units,
    int from,
    int end,
    List<LayoutRect> segments,
    double contentHeight,
    TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens,
  ) {
    final blocks = <LayoutBlock>[
      for (var u = from; u < end; u++) ...units[u],
    ];
    if (blocks.isEmpty) return null;
    if (segments.isEmpty) {
      return FlowPlacementFailure(
        kind: FlowPlacementFailureKind.columnsExhausted,
        blockId: blocks.first.id,
        detail: 'protected obstacles consume the whole column',
      );
    }
    final groups = <List<String>>[
      for (final unit in units.sublist(from, end))
        if (unit.length > 1) [for (final b in unit) b.id],
    ];
    final sub = LayoutBlockAssembly(
      blocks: List.unmodifiable(blocks),
      relationships: const [],
      atomicGroups: List.unmodifiable(groups),
      documentConsumedSourceIds: assembly.documentConsumedSourceIds,
      documentPreservedSourceIds: assembly.documentPreservedSourceIds,
    );
    return const FlowPlacer().place(
      assembly: sub,
      candidate: candidate,
      columnRects: segments,
      contentHeight: contentHeight,
      measure: measure,
      tokens: tokens,
    );
  }

  Object _placeOnSegments({
    required LayoutBlockAssembly assembly,
    required CompositionCandidate candidate,
    required List<LayoutRect> segments,
    required double contentHeight,
    required LayoutRect pageContent,
    required Map<String, LayoutRect> preservedRects,
    required List<LayoutRect> obstacles,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
  }) {
    final outcome = const FlowPlacer().place(
      assembly: assembly,
      candidate: candidate,
      columnRects: segments,
      contentHeight: contentHeight,
      measure: measure,
      tokens: tokens,
    );
    if (outcome is FlowPlacementFailure) {
      return BalancedPlacementFailure(
        kind: outcome.kind,
        blockId: outcome.blockId,
        detail: outcome.detail,
      );
    }
    return _finalize(
      success: outcome as FlowPlacementSuccess,
      assembly: assembly,
      columnCount: segments.length,
      contentHeight: contentHeight,
      pageContent: pageContent,
      preservedRects: preservedRects,
      obstacles: obstacles,
    );
  }

  BalancedPlacement _finalize({
    required FlowPlacementSuccess success,
    required LayoutBlockAssembly assembly,
    required int columnCount,
    required double contentHeight,
    required LayoutRect pageContent,
    required Map<String, LayoutRect> preservedRects,
    required List<LayoutRect> obstacles,
  }) {
    // 页界 contain：全部放置盒 ⊆ 内容区（闭盒+容差）。
    for (final p in success.placed) {
      if (!SmartLayoutGeometryKernel.pageContainsRect(
        page: pageContent,
        candidate: p.rect,
      )) {
        throw StateError(
          'placement escapes page content bounds: ${p.blockId} at ${p.rect}',
        );
      }
    }
    // 构造性零碰撞已由障碍切割保证；防御性复核只针对 protected 障碍
    //（preserved 投影不参与重排、不构成绕置约束）。
    for (final p in success.placed) {
      for (final obstacle in obstacles) {
        if (p.rect.intersects(obstacle)) {
          throw StateError(
            'hard collision with protected obstacle: ${p.blockId}',
          );
        }
      }
    }
    final usedMax = success.usedHeights.reduce(
      (a, b) => a > b ? a : b,
    );
    final density = contentHeight > 0
        ? (usedMax / contentHeight).clamp(0.0, 1.0)
        : 0.0;

    String num(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final canonical = [
      for (final p in success.placed)
        '${p.blockId}:${num(p.rect.left)},${num(p.rect.top)},'
        '${num(p.rect.width)},${num(p.rect.height)}#${p.columnIndex}'
        '#${p.lineCount}#${num(p.appliedFontSize)}',
      ...([
        for (final id in preservedRects.keys.toList()..sort())
          '$id@${num(preservedRects[id]!.left)},'
          '${num(preservedRects[id]!.top)}',
      ]),
    ].join('|');
    return BalancedPlacement(
      placed: success.placed,
      usedHeights: success.usedHeights,
      preservedRects: Map.unmodifiable(preservedRects),
      density: density,
      goldenHash: fingerprint64('balanced-placement|$canonical'),
    );
  }
}
