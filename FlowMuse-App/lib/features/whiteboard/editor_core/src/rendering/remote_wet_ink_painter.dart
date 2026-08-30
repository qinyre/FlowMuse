import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

import '../core/elements/elements.dart';
import '../core/layout/layout.dart';
import '../core/math/math.dart';
import 'natural_media/brush_pen_stroke_renderer_v2.dart';
import 'natural_media/pencil_stroke_renderer_v2.dart';
import 'rough/draw_style.dart';
import 'rough/freedraw_renderer.dart';
import 'rough/rough_adapter.dart';
import 'viewport_state.dart';

class RemoteWetInkRenderCache {
  static const int _estimatedBytesPerRecordedPoint = 240;
  static const int _estimatedBytesPerPicture = 1024;

  final Map<String, _RemoteStrokePictureCache> _strokes = {};
  final Map<String, int> _lastPaintedMaxPointIndex = {};
  final Map<String, RemoteWetInkStrokeSnapshot> _lastPaintedSnapshots = {};
  final Map<String, Uint8List> _paintedPointBits = {};
  final Map<String, int> _paintedPointLogEnds = {};
  int recordedGeometryPointCount = 0;
  int lastFrameTailPointCount = 0;

  int get pictureLayerCount => _strokes.values.fold(
    0,
    (total, stroke) => total + stroke.pictureLayerCount,
  );

  int get retainedGeometryPointCount => _strokes.values.fold(
    0,
    (total, stroke) => total + stroke.retainedGeometryPointCount,
  );

  int get maxPictureNestingDepth => _strokes.values.fold(
    0,
    (depth, stroke) =>
        stroke.pictureNestingDepth > depth ? stroke.pictureNestingDepth : depth,
  );

  int get estimatedRetainedBytes =>
      retainedGeometryPointCount * _estimatedBytesPerRecordedPoint +
      pictureLayerCount * _estimatedBytesPerPicture;

  int? paintedMaxPointIndex(String strokeId) =>
      _lastPaintedMaxPointIndex[strokeId];

  int? paintedRevision(String strokeId) =>
      _lastPaintedSnapshots[strokeId]?.revision;

  List<int> pictureMinStartIndices(String strokeId) =>
      _strokes[strokeId]?.orderedMinStartIndices ?? const [];

  bool wasPointPainted(String strokeId, int pointIndex) =>
      pointIndex >= 0 &&
      pointIndex < RemoteWetInkStore.maxPointsPerStroke &&
      ((_paintedPointBits[strokeId]?[pointIndex >> 3] ?? 0) &
              (1 << (pointIndex & 7))) !=
          0;

  void sync(
    List<RemoteWetInkStrokeSnapshot> snapshots,
    RoughAdapter adapter, {
    double? deviceScale,
  }) {
    final activeIds = {for (final snapshot in snapshots) snapshot.strokeId};
    final removedIds = [
      for (final strokeId in _strokes.keys)
        if (!activeIds.contains(strokeId)) strokeId,
    ];
    for (final strokeId in removedIds) {
      _strokes.remove(strokeId)?.dispose();
      _lastPaintedMaxPointIndex.remove(strokeId);
      _lastPaintedSnapshots.remove(strokeId);
      _paintedPointBits.remove(strokeId);
      _paintedPointLogEnds.remove(strokeId);
    }
    for (final snapshot in snapshots) {
      final cache = _strokes.putIfAbsent(
        snapshot.strokeId,
        _RemoteStrokePictureCache.new,
      );
      recordedGeometryPointCount += cache.sync(
        snapshot,
        adapter,
        deviceScale: deviceScale,
      );
    }
  }

  void paint(
    Canvas canvas,
    List<RemoteWetInkStrokeSnapshot> snapshots,
    RoughAdapter adapter,
  ) {
    lastFrameTailPointCount = 0;
    for (final snapshot in snapshots) {
      paintStroke(canvas, snapshot, adapter);
    }
  }

  /// 单个 stroke 的绘制（含 tail 与簿记）。painter 的聚焦包装在调用侧，
  /// 本方法不感知 focus —— 几何缓存 Picture 复用不受 alpha 影响。
  void paintStroke(
    Canvas canvas,
    RemoteWetInkStrokeSnapshot snapshot,
    RoughAdapter adapter,
  ) {
    final cache = _strokes[snapshot.strokeId];
    cache?.paint(canvas);
    final wholeLength = wholeVisibleRawLength(snapshot);
    for (var i = 0; i < snapshot.tailSegments.length; i++) {
      final segment = snapshot.tailSegments[i];
      lastFrameTailPointCount += segment.points.length;
      _drawSegment(
        canvas,
        segment,
        snapshot,
        adapter,
        taperPhase: _tailTaperPhase(snapshot, i),
        wholeStrokeRawLength: wholeLength,
        ownsStrokeTail: i == snapshot.tailSegments.length - 1,
      );
    }
    _lastPaintedMaxPointIndex[snapshot.strokeId] = snapshot.maxPointIndex;
    _lastPaintedSnapshots[snapshot.strokeId] = snapshot;
    _markPaintedIndices(snapshot);
  }

  /// 尾段笔锋相位（issue #5 T3）：
  /// - 整笔尚在尾段（无冻结块）且只有一段含 index 0 → full（否则常见
  ///   ≤64 点短划在湿墨期间起笔恒宽、提交瞬间突然长出起锋）；
  /// - 含笔迹起点的首段 → headOnly；最新尾段 → tailOnly（收锋跟随
  ///   对端笔尖）；其余中间段 → none（段边界不收针）。
  FreedrawTaperPhase _tailTaperPhase(
    RemoteWetInkStrokeSnapshot snapshot,
    int tailIndex,
  ) {
    final tails = snapshot.tailSegments;
    final isFirstSegment = tailIndex == 0 && tails.first.startIndex == 0;
    final isLastSegment = tailIndex == tails.length - 1;
    if (snapshot.frozenBlocks.isEmpty && isFirstSegment && isLastSegment) {
      return FreedrawTaperPhase.full;
    }
    if (isFirstSegment) return FreedrawTaperPhase.headOnly;
    if (isLastSegment) return FreedrawTaperPhase.tailOnly;
    return FreedrawTaperPhase.none;
  }

  void dispose() {
    for (final stroke in _strokes.values) {
      stroke.dispose();
    }
    _strokes.clear();
    _lastPaintedMaxPointIndex.clear();
    _lastPaintedSnapshots.clear();
    _paintedPointBits.clear();
    _paintedPointLogEnds.clear();
  }

  void _markPaintedIndices(RemoteWetInkStrokeSnapshot snapshot) {
    final bits = _paintedPointBits.putIfAbsent(
      snapshot.strokeId,
      () => Uint8List(RemoteWetInkStore.maxPointsPerStroke >> 3),
    );
    final start = _paintedPointLogEnds[snapshot.strokeId] ?? 0;
    for (var cursor = start; cursor < snapshot.pointIndexLogEnd; cursor++) {
      final index = snapshot.pointIndexLog[cursor];
      bits[index >> 3] |= 1 << (index & 7);
    }
    _paintedPointLogEnds[snapshot.strokeId] = snapshot.pointIndexLogEnd;
  }
}

class RemoteWetInkPainter extends CustomPainter {
  RemoteWetInkPainter({
    required this.store,
    required this.cache,
    required this.adapter,
    required this.viewport,
    this.layout,
    this.focusedCreatorKey,
    this.focusHistoricalContent = false,
    this.socketIdCreatorKeys = const {},
    this.presenceCreatorRevision = 0,
  }) : super(repaint: store);

  final RemoteWetInkStore store;
  final RemoteWetInkRenderCache cache;
  final RoughAdapter adapter;
  final ViewportState viewport;
  final CanvasLayout? layout;

  /// 协作聚焦（本机视图态纯数据，v4 §8.2）。
  final String? focusedCreatorKey;
  final bool focusHistoricalContent;
  final Map<String, String> socketIdCreatorKeys;
  final int presenceCreatorRevision;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = store.strokes;
    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
    _clipToPages(canvas);
    // 缓存同步/冻结块录制放在视口变换之后：录制离屏 Picture 时 canvas
    // 是恒等矩阵，显式取真实回放缩放传入，铅笔 shader 颗粒频率与直接
    // 绘制同源（缩放/像素密度不改变场景内颗粒尺度）。
    cache.sync(
      strokes,
      adapter,
      deviceScale: FreedrawRenderer.canvasScale(canvas),
    );
    if (strokes.isEmpty) {
      canvas.restore();
      return;
    }

    final focusActive = focusedCreatorKey != null || focusHistoricalContent;
    // 逐 stroke 调 paintStroke 时不再经过 cache.paint 的每帧重置，这里手动清零。
    cache.lastFrameTailPointCount = 0;
    for (final snapshot in strokes) {
      final alpha = focusActive ? _alphaForSnapshot(snapshot) : 1.0;
      if (alpha >= 1.0) {
        cache.paintStroke(canvas, snapshot, adapter);
      } else {
        // §8.2：逐 stroke 临时 alpha 合成，冻结 Picture 几何缓存不受污染。
        // bounds 用实际渲染笔迹包围盒 + 最大有效线宽余量，禁止全屏层。
        canvas.saveLayer(
          _strokeBounds(snapshot),
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
        );
        cache.paintStroke(canvas, snapshot, adapter);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  /// §8.1 行为表：映射缺失 fail-open 1.0（宁全亮不错暗）；creator focus
  /// 目标外 0.22；history focus 下有主的活动湿墨不属于历史 → 0.22。
  double _alphaForSnapshot(RemoteWetInkStrokeSnapshot snapshot) {
    final creatorKey = socketIdCreatorKeys[snapshot.senderSocketId];
    if (creatorKey == null) return 1.0;
    if (focusedCreatorKey != null) {
      return creatorKey == focusedCreatorKey ? 1.0 : 0.22;
    }
    return 0.22;
  }

  Rect _strokeBounds(RemoteWetInkStrokeSnapshot snapshot) {
    // 冻结几何的包围盒由 store 在冻结时增量维护（评审 P1 修复：聚焦层
    // bounds 不得每帧重扫全部冻结点——最长笔迹可达 16384 点）；每帧只
    // 扫描有限的 tail 段，与 Picture 缓存"只处理有限 tail"的设计对齐。
    final frozen = snapshot.frozenBounds;
    var minX = frozen?.minX ?? double.infinity;
    var minY = frozen?.minY ?? double.infinity;
    var maxX = frozen?.maxX ?? double.negativeInfinity;
    var maxY = frozen?.maxY ?? double.negativeInfinity;
    void absorb(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    for (final segment in snapshot.tailSegments) {
      if (segment.leadingPoint != null) {
        absorb(segment.leadingPoint!.x, segment.leadingPoint!.y);
      }
      for (final point in segment.points) {
        absorb(point.x, point.y);
      }
      if (segment.trailingPoint != null) {
        absorb(segment.trailingPoint!.x, segment.trailingPoint!.y);
      }
    }

    if (minX > maxX || minY > maxY) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    // §8.2 余量按笔刷 profile 的保守可视半径（issue #5 T6 单一真源：
    // visualHalfWidth = size×(0.5+maxThinning×0.5)+AA 余量，覆盖
    // thinning/平头/抗锯齿）。禁止退回名义 strokeWidth/2 或手写
    // kMaxBrushSizeScale 常量（v4 §8.2 明令禁止）。
    final margin = BrushRenderProfile.forType(
      BrushType.fromWireName(snapshot.style.brushType),
    ).visualHalfWidth(snapshot.style.strokeWidth);
    return Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );
  }

  void _clipToPages(Canvas canvas) {
    final currentLayout = layout;
    if (currentLayout == null ||
        !currentLayout.isPaged ||
        currentLayout.pages.isEmpty) {
      return;
    }
    final pageClip = Path();
    for (final page in currentLayout.pages) {
      pageClip.addRect(page.bounds);
    }
    canvas.clipPath(pageClip);
  }

  @override
  bool shouldRepaint(RemoteWetInkPainter oldDelegate) {
    if (oldDelegate.focusedCreatorKey != focusedCreatorKey) return true;
    if (oldDelegate.focusHistoricalContent != focusHistoricalContent) {
      return true;
    }
    final anyFocus = focusedCreatorKey != null || focusHistoricalContent;
    if (anyFocus &&
        oldDelegate.presenceCreatorRevision != presenceCreatorRevision) {
      return true;
    }
    return oldDelegate.store != store ||
        oldDelegate.adapter != adapter ||
        oldDelegate.viewport != viewport ||
        oldDelegate.layout != layout;
  }
}

class _RemoteStrokePictureCache {
  final Map<int, _FrozenBlockPicture> _blockPictures = {};

  int get pictureLayerCount => _blockPictures.length;
  int get pictureNestingDepth => pictureLayerCount == 0 ? 0 : 1;
  int get retainedGeometryPointCount =>
      _blockPictures.values.fold(0, (total, block) => total + block.pointCount);
  List<int> get orderedMinStartIndices =>
      (_blockPictures.values.toList()
            ..sort((a, b) => a.minStartIndex.compareTo(b.minStartIndex)))
          .map((block) => block.minStartIndex)
          .toList(growable: false);

  int sync(
    RemoteWetInkStrokeSnapshot snapshot,
    RoughAdapter adapter, {
    double? deviceScale,
  }) {
    var recordedPoints = 0;
    final activeLevels = {
      for (final block in snapshot.frozenBlocks) block.level,
    };
    final removedLevels = [
      for (final level in _blockPictures.keys)
        if (!activeLevels.contains(level)) level,
    ];
    for (final level in removedLevels) {
      _blockPictures.remove(level)?.picture.dispose();
    }
    for (final block in snapshot.frozenBlocks) {
      final current = _blockPictures[block.level];
      if (current?.revision == block.revision) continue;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final wholeLength = wholeVisibleRawLength(snapshot);
      for (var i = 0; i < block.segments.length; i++) {
        final segment = block.segments[i];
        recordedPoints += segment.points.length;
        // 冻结块是笔迹中段：只有包含笔迹起点的首块首段带起笔 taper
        // （headOnly），永不带收笔 taper（段边界不收针）；v2 同口径
        // 以 ownsStrokeHead 表达。
        final ownsHead = i == 0 && segment.startIndex == 0;
        // 无 tail 时末块拥有笔尖（v2 端帽随最后冻结点；后续点到达会
        // 冻结新块并重录，帽位随笔尖推进）。
        final ownsTail =
            snapshot.tailSegments.isEmpty &&
            i == block.segments.length - 1 &&
            segment.startIndex + segment.points.length > snapshot.maxPointIndex;
        _drawSegment(
          canvas,
          segment,
          snapshot,
          adapter,
          taperPhase: ownsHead
              ? FreedrawTaperPhase.headOnly
              : FreedrawTaperPhase.none,
          wholeStrokeRawLength: wholeLength,
          // 离屏录制 canvas 恒等：显式传回放缩放，铅笔颗粒频率与直接绘制同源。
          deviceScale: deviceScale,
          ownsStrokeHead: ownsHead,
          ownsStrokeTail: ownsTail,
        );
      }
      final nextPicture = recorder.endRecording();
      final replacement = _FrozenBlockPicture(
        picture: nextPicture,
        revision: block.revision,
        pointCount: block.pointCount,
        minStartIndex: block.segments.first.startIndex,
      );
      current?.picture.dispose();
      _blockPictures[block.level] = replacement;
    }
    return recordedPoints;
  }

  void paint(Canvas canvas) {
    final blocks = _blockPictures.values.toList()
      ..sort((a, b) => a.minStartIndex.compareTo(b.minStartIndex));
    for (final block in blocks) {
      canvas.drawPicture(block.picture);
    }
  }

  void dispose() {
    for (final block in _blockPictures.values) {
      block.picture.dispose();
    }
    _blockPictures.clear();
  }
}

class _FrozenBlockPicture {
  const _FrozenBlockPicture({
    required this.picture,
    required this.revision,
    required this.pointCount,
    required this.minStartIndex,
  });

  final ui.Picture picture;
  final int revision;
  final int pointCount;
  final int minStartIndex;
}

/// 整条可见笔迹的原始折线长度 = 冻结部分（store 增量维护）+ tail 段
/// （含 leading/trailing 桥接点）。供笔锋 <3×size 门控使用（issue #5 T3）。
double wholeVisibleRawLength(RemoteWetInkStrokeSnapshot snapshot) {
  var length = snapshot.frozenRawLength;
  for (final segment in snapshot.tailSegments) {
    LiveInkPoint? prev = segment.leadingPoint;
    for (final point in segment.points) {
      if (prev != null) {
        final dx = point.x - prev.x;
        final dy = point.y - prev.y;
        length += math.sqrt(dx * dx + dy * dy);
      }
      prev = point;
    }
    final trailing = segment.trailingPoint;
    if (prev != null && trailing != null) {
      final dx = trailing.x - prev.x;
      final dy = trailing.y - prev.y;
      length += math.sqrt(dx * dx + dy * dy);
    }
  }
  return length;
}

void _drawSegment(
  Canvas canvas,
  RemoteWetInkSegment segment,
  RemoteWetInkStrokeSnapshot stroke,
  RoughAdapter adapter, {
  FreedrawTaperPhase taperPhase = FreedrawTaperPhase.none,
  double? wholeStrokeRawLength,
  double? deviceScale,
  bool ownsStrokeHead = false,
  bool ownsStrokeTail = false,
}) {
  if (segment.points.isEmpty) return;
  // v1 输入列表保持既有单 leading 桥接口径（验收：v1 incoming 摘要
  // 不变）；v2 分支另组双 leading context 列表。
  final renderedPoints = [
    if (segment.leadingPoint != null) segment.leadingPoint!,
    ...segment.points,
    if (segment.trailingPoint != null) segment.trailingPoint!,
  ];
  final pressures = renderedPoints.every((point) => point.pressure != null)
      ? [for (final point in renderedPoints) point.pressure!]
      : const <double>[];
  final element = FreedrawElement(
    id: ElementId(stroke.strokeId),
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    points: [for (final point in renderedPoints) Point(point.x, point.y)],
    pressures: pressures,
    simulatePressure: pressures.isEmpty,
    isComplete: false,
    strokeColor: stroke.style.strokeColor,
    strokeWidth: stroke.style.strokeWidth,
    opacity: stroke.style.opacity / 100,
  );
  final brushType = BrushType.fromWireName(stroke.style.brushType);
  // v2 自然介质（计划 T7 工作项 2）：双 leading context + 段点，按段
  // 渲染 owned 边，全局索引对齐（offset = 段起点 − leading 数），起收
  // 只归首/末段；v1 与无压感输入保持既有 adapter 路径（工作项 9）。
  final v2List = [
    ...segment.leadingPoints.reversed,
    ...segment.points,
    if (segment.trailingPoint != null) segment.trailingPoint!,
  ];
  final v2Pressures = v2List.every((point) => point.pressure != null)
      ? [for (final point in v2List) point.pressure!]
      : const <double>[];
  final isV2 = stroke.style.renderVersion == 2 && v2Pressures.isNotEmpty;
  if (isV2) {
    final v2Element = FreedrawElement(
      id: ElementId(stroke.strokeId),
      x: 0,
      y: 0,
      width: 0,
      height: 0,
      points: [for (final point in v2List) Point(point.x, point.y)],
      pressures: v2Pressures,
      simulatePressure: false,
      isComplete: false,
      strokeColor: stroke.style.strokeColor,
      strokeWidth: stroke.style.strokeWidth,
      opacity: stroke.style.opacity / 100,
    );
    final leadingCount = segment.leadingPoints.length;
    final ownsHead = ownsStrokeHead || segment.startIndex == 0;
    final style = DrawStyle.fromElement(v2Element);
    // §3.4"交界归较后 edge"：桥接边（连前段末点→本段首点）归本段
    //（有 leading context 时把 ownedStart 扩到 startIndex），否则两段
    // 都不拥有它，冻结边界会缺失 primitive。段首无 leading（笔迹起点）
    // 从首边 1 起。
    final ownedStart = leadingCount == 0
        ? segment.startIndex + 1
        : segment.startIndex;
    final ownedEnd = segment.startIndex + segment.points.length;
    final offset = segment.startIndex - leadingCount;
    if (brushType == BrushType.brushPen) {
      BrushPenStrokeRendererV2.draw(
        canvas,
        v2Element,
        style,
        ownedEdgeStart: ownedStart,
        ownedEdgeEndExclusive: ownedEnd,
        edgeIndexOffset: offset,
        ownsStrokeHead: ownsHead,
        ownsStrokeTail: ownsStrokeTail,
      );
    } else {
      PencilStrokeRendererV2.draw(
        canvas,
        v2Element,
        style,
        ownedEdgeStart: ownedStart,
        ownedEdgeEndExclusive: ownedEnd,
        edgeIndexOffset: offset,
      );
    }
    return;
  }
  adapter.drawFreedraw(
    canvas,
    element.points,
    element.pressures,
    element.simulatePressure,
    BrushType.fromWireName(stroke.style.brushType),
    DrawStyle.fromElement(element),
    isComplete: false,
    // 湿墨必为新笔迹：远端发来的 pressure 已在发送端编码。
    pressureEncoded: true,
    taperPhase: taperPhase,
    wholeStrokeRawLength: wholeStrokeRawLength,
    deviceScale: deviceScale,
  );
}
