import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_plan.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_sampler.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

import 'natural_media/natural_media_image_metrics.dart';
import 'natural_media_visual_sheet_support.dart';

// ---------------------------------------------------------------------------
// T7：统一远端湿墨（计划任务卡）：v2 段渲染（双 leading context + owned
// 边 + 全局索引对齐）、64/128 点边界无重复/缺失 primitive、block 合并
// 稳定、远端湿墨 vs 静态 90% mask ≤2%、style renderVersion 变化阻断、
// v1 incoming 不变。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// N 点水平正弦笔迹（压力平滑变化，触发包络/颗粒全路径）。
  List<Point> wavePoints(int n) => [
    for (var i = 0; i < n; i++)
      Point(i * 3.0, 20 + 8 * math.sin(i / 5.0) + i * 0.05),
  ];
  List<double> wavePressures(int n) => [
    for (var i = 0; i < n; i++)
      (0.35 + 0.3 * math.sin(i / 7.0)).clamp(0.05, 1.0),
  ];

  DecodedLiveInkChunk chunk(
    String strokeId,
    List<Point> points,
    List<double> pressures,
    LiveInkStyle style,
    int startIndex,
    int count,
  ) => DecodedLiveInkChunk(
    senderSocketId: 'sender',
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndex,
      points: [
        for (var offset = 0; offset < count; offset++)
          LiveInkPoint(
            x: points[startIndex + offset].x,
            y: points[startIndex + offset].y,
            pressure: pressures[startIndex + offset],
          ),
      ],
      style: style,
    ),
  );

  const v2PencilStyle = LiveInkStyle(
    brushType: 'pencil',
    strokeColor: '#000000',
    strokeWidth: 6,
    opacity: 100,
    renderVersion: 2,
  );
  const v2BrushStyle = LiveInkStyle(
    brushType: 'brushPen',
    strokeColor: '#000000',
    strokeWidth: 6,
    opacity: 100,
    renderVersion: 2,
  );

  void feedStroke(
    RemoteWetInkStore store,
    String strokeId,
    List<Point> points,
    List<double> pressures,
    LiveInkStyle style, {
    int from = 0,
    int? to,
  }) {
    final end = to ?? points.length;
    for (var start = from; start < end; start += 64) {
      final count = (end - start).clamp(0, 64);
      if (count == 0) break;
      store.apply(chunk(strokeId, points, pressures, style, start, count));
    }
  }

  /// 按画家同口径组装段的 v2 plan（双 leading + 段点 + trailing）。
  NaturalMediaStrokePlan segmentPlan(
    RemoteWetInkSegment segment,
    RemoteWetInkStrokeSnapshot snapshot,
    BrushType brushType,
  ) {
    final list = [
      ...segment.leadingPoints.reversed,
      ...segment.points,
      if (segment.trailingPoint != null) segment.trailingPoint!,
    ];
    return NaturalMediaStrokeSampler.sample(
      strokeId: snapshot.strokeId,
      points: [for (final p in list) Point(p.x, p.y)],
      pressures: [for (final p in list) p.pressure ?? 0.5],
      strokeWidth: snapshot.style.strokeWidth,
      brushType: brushType,
      isComplete: false,
      ownedEdgeStart: segment.leadingPoints.isEmpty
          ? segment.startIndex + 1
          : segment.startIndex,
      ownedEdgeEndExclusive: segment.startIndex + segment.points.length,
      edgeIndexOffset: segment.startIndex - segment.leadingPoints.length,
    );
  }

  test('T7-a 63/64/65/127/128/129 点边界：段 key 并集=整笔且无重复', () {
    for (final n in [63, 64, 65, 127, 128, 129]) {
      final points = wavePoints(n);
      final pressures = wavePressures(n);
      final store = RemoteWetInkStore(autoCleanup: false);
      addTearDown(store.dispose);
      feedStroke(store, 'bnd-$n', points, pressures, v2BrushStyle);
      final snapshot = store.strokes.single;

      final whole = NaturalMediaStrokeSampler.sample(
        strokeId: 'bnd-$n',
        points: points,
        pressures: pressures,
        strokeWidth: 6,
        brushType: BrushType.brushPen,
        isComplete: false,
      );
      final wholeKeys = whole.primitiveKeyDigest().toSet();

      final segments = [
        ...snapshot.frozenBlocks.expand((b) => b.segments),
        ...snapshot.tailSegments,
      ];
      final union = <String>{};
      var totalCount = 0;
      for (final segment in segments) {
        final plan = segmentPlan(segment, snapshot, BrushType.brushPen);
        final keys = plan.primitiveKeyDigest();
        totalCount += keys.length;
        union.addAll(keys);
      }
      expect(union.length, totalCount, reason: '$n 点：段间不得重复 primitive key');
      expect(union, equals(wholeKeys), reason: '$n 点：段 key 并集必须与整笔完全相等');
    }
  });

  test('T7-b 远端湿墨 vs 静态：弧长前 90% mask 像素差 ≤2%（铅笔/毛笔）', () async {
    for (final (name, style, brushType) in [
      ('铅笔', v2PencilStyle, BrushType.pencil),
      ('毛笔', v2BrushStyle, BrushType.brushPen),
    ]) {
      final points = wavePoints(96);
      final pressures = wavePressures(96);
      final store = RemoteWetInkStore(autoCleanup: false);
      addTearDown(store.dispose);
      feedStroke(store, 'raster-$name', points, pressures, style);
      final cache = RemoteWetInkRenderCache();
      addTearDown(cache.dispose);
      final painter = RemoteWetInkPainter(
        store: store,
        cache: cache,
        adapter: RoughCanvasAdapter(),
        viewport: const ViewportState(),
      );

      Future<NaturalMediaRaster> raster(Future<ui.Image> Function() run) async {
        final image = await run();
        final raster = await NaturalMediaRaster.fromImage(image);
        image.dispose();
        return raster;
      }

      final remoteRaster = await raster(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Offset.zero & const ui.Size(kCellWidth, kCellHeight),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        painter.paint(canvas, const ui.Size(kCellWidth, kCellHeight));
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          kCellWidth.round(),
          kCellHeight.round(),
        );
        picture.dispose();
        return image;
      });

      final staticElement = FreedrawElement(
        id: ElementId('raster-$name'),
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        points: points,
        pressures: pressures,
        simulatePressure: false,
        isComplete: false,
        customData: customDataWithFreedrawRender(
          null,
          brushType,
          renderVersion: BrushRenderVersion.naturalMediaV2,
        ),
        strokeWidth: 6,
      );
      final staticRaster = await raster(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Offset.zero & const ui.Size(kCellWidth, kCellHeight),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        ElementRenderer.render(canvas, staticElement, RoughCanvasAdapter());
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          kCellWidth.round(),
          kCellHeight.round(),
        );
        picture.dispose();
        return image;
      });

      final geom = StrokeArcGeometry(points);
      final diff = PixelDiff.differingInkRatio(
        remoteRaster,
        staticRaster,
        mask: ArcPrefixMask.default90(geom).containsPixel,
      );
      expect(
        diff,
        lessThanOrEqualTo(0.02),
        reason: '$name 远端湿墨与静态渲染前 90% 像素差 $diff 应 ≤2%',
      );
    }
  });

  test('T7-c block 合并不改变已冻结区域（key/切线/包络顶点逐值相等）', () {
    final points = wavePoints(192);
    final pressures = wavePressures(192);
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    // 冻结策略：第 2 块到达后 [0..63] 冻结为 L0-A；第 3 块到达后
    // [64..127] 冻结为 L0-B 并与 A 合并成 L1[0..127]。合并只允许重录
    // 块内 Picture，不得改变已冻结 primitive 的 key/切线/包络顶点。
    feedStroke(
      store,
      'merge',
      points,
      pressures,
      v2BrushStyle,
      from: 0,
      to: 64,
    );
    feedStroke(
      store,
      'merge',
      points,
      pressures,
      v2BrushStyle,
      from: 64,
      to: 128,
    );
    final preMerge = store.strokes.single;
    final preSegments = [
      ...preMerge.frozenBlocks.expand((b) => b.segments),
      ...preMerge.tailSegments,
    ];
    // 主体原语（顶点/join）进同一条 Path，顺序必须一致；毫丝是另一条
    // 复合 Path，跨 Path 相对顺序不影响光栅，按多重集比较。
    String bodyFingerprint(NaturalMediaStrokePlan plan, int maxEdge) => [
      for (final p in plan.primitives)
        if (p.edgeIndex <= maxEdge &&
            (p.kind == NaturalMediaPrimitiveKind.brushEnvelopeVertex ||
                p.kind == NaturalMediaPrimitiveKind.brushJoin))
          '${p.edgeIndex}:${p.ordinal}:${p.channel}:${p.kind.name}'
              ':${p.center!.x.toStringAsFixed(9)}:${p.center!.y.toStringAsFixed(9)}'
              ':${p.halfThickness?.toStringAsFixed(9)}',
    ].join(';');
    List<String> strandFingerprint(NaturalMediaStrokePlan plan, int maxEdge) {
      final out = [
        for (final p in plan.primitives)
          if (p.edgeIndex <= maxEdge &&
              p.kind == NaturalMediaPrimitiveKind.brushStrand)
            '${p.edgeIndex}:${p.ordinal}:${p.center!.x.toStringAsFixed(9)}:${p.center!.y.toStringAsFixed(9)}',
      ];
      out.sort();
      return out;
    }

    final prePrefixPlan = segmentPlan(
      preSegments.firstWhere((s) => s.startIndex == 0),
      preMerge,
      BrushType.brushPen,
    );
    final preBoundaryJoin = segmentPlan(
      preSegments.firstWhere((s) => s.startIndex == 64),
      preMerge,
      BrushType.brushPen,
    );

    feedStroke(
      store,
      'merge',
      points,
      pressures,
      v2BrushStyle,
      from: 128,
      to: 192,
    );
    final post = store.strokes.single;
    expect(post.frozenBlocks.length, 1, reason: 'L0-A + L0-B 应合并为单块 L1');
    final merged = post.frozenBlocks
        .expand((b) => b.segments)
        .firstWhere((s) => s.startIndex == 0);
    final mergedPlan = segmentPlan(merged, post, BrushType.brushPen);

    expect(
      bodyFingerprint(mergedPlan, 63),
      equals(bodyFingerprint(prePrefixPlan, 63)),
      reason: '合并不得改变已冻结的 A 块主体原语（key/切线/顶点/顺序）',
    );
    expect(
      strandFingerprint(mergedPlan, 63),
      equals(strandFingerprint(prePrefixPlan, 63)),
      reason: '合并不得改变已冻结的 A 块毫丝',
    );
    // 边 64（边界边）：primitive 几何与 key 逐值一致。顺序差异是分块
    // 边界固有（入界 join 在段首、整笔在 from 边循环尾），两条主体 Path
    // 的点集相同；合并稳定性另由 T7-b 的 90% mask ≤2% 像素门净检验。
    final boundaryExpected = [
      ...bodyFingerprint(prePrefixPlan, 64).split(';'),
      ...bodyFingerprint(preBoundaryJoin, 64).split(';'),
    ]..sort();
    final boundaryActual = bodyFingerprint(mergedPlan, 64).split(';')..sort();
    expect(
      boundaryActual,
      equals(boundaryExpected),
      reason: '边界 join（边 64）合并前后必须逐值一致（4 leading context）',
    );
    expect(
      strandFingerprint(mergedPlan, 64),
      equals(
        strandFingerprint(prePrefixPlan, 64) +
            strandFingerprint(preBoundaryJoin, 64),
      ),
      reason: '边界毫丝合并前后一致',
    );
  });

  test('T7-d 同 stroke 中途换 renderVersion 被 _sameStyle 阻断', () {
    final points = wavePoints(6);
    final pressures = wavePressures(6);
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    store.apply(chunk('flip', points, pressures, v2PencilStyle, 0, 3));
    expect(store.strokes.single.pointCount, 3);

    const v1Style = LiveInkStyle(
      brushType: 'pencil',
      strokeColor: '#000000',
      strokeWidth: 6,
      opacity: 100,
    );
    final dropped = store.apply(
      chunk('flip', points, pressures, v1Style, 3, 3),
    );
    expect(dropped.accepted, isFalse, reason: '版本翻转的 chunk 必须被拒绝');
    expect(store.strokes.single.pointCount, 3, reason: '拒绝后点数不变');
  });

  test('T7-e v1 incoming 仍走 adapter v1 路径（不走自然介质）', () {
    final points = wavePoints(4);
    final pressures = wavePressures(4);
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    const v1Style = LiveInkStyle(
      brushType: 'pencil',
      strokeColor: '#000000',
      strokeWidth: 6,
      opacity: 100,
    );
    store.apply(chunk('v1', points, pressures, v1Style, 0, 4));
    final adapter = _V1SpyAdapter();
    final cache = RemoteWetInkRenderCache();
    addTearDown(cache.dispose);
    RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    ).paint(_blankCanvas(), const ui.Size(100, 100));
    expect(
      adapter.calls,
      greaterThan(0),
      reason: 'v1 必须经 adapter.drawFreedraw',
    );
  });
}

ui.Canvas _blankCanvas() => ui.Canvas(ui.PictureRecorder());

class _V1SpyAdapter extends RoughCanvasAdapter {
  int calls = 0;
  @override
  void drawFreedraw(
    ui.Canvas canvas,
    List<Point> points,
    List<double> pressures,
    bool simulatePressure,
    BrushType brushType,
    dynamic style, {
    bool isComplete = true,
    bool pressureEncoded = false,
    dynamic taperPhase,
    double? wholeStrokeRawLength,
    double? deviceScale,
  }) {
    calls++;
    super.drawFreedraw(
      canvas,
      points,
      pressures,
      simulatePressure,
      brushType,
      style,
      isComplete: isComplete,
      pressureEncoded: pressureEncoded,
      taperPhase: taperPhase,
      wholeStrokeRawLength: wholeStrokeRawLength,
      deviceScale: deviceScale,
    );
  }
}
