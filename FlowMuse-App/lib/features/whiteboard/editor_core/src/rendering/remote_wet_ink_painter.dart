import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

import '../core/elements/elements.dart';
import '../core/layout/layout.dart';
import '../core/math/math.dart';
import 'rough/draw_style.dart';
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

  bool wasPointPainted(String strokeId, int pointIndex) =>
      pointIndex >= 0 &&
      pointIndex < RemoteWetInkStore.maxPointsPerStroke &&
      ((_paintedPointBits[strokeId]?[pointIndex >> 3] ?? 0) &
              (1 << (pointIndex & 7))) !=
          0;

  void sync(List<RemoteWetInkStrokeSnapshot> snapshots, RoughAdapter adapter) {
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
      recordedGeometryPointCount += cache.sync(snapshot, adapter);
    }
  }

  void paint(
    Canvas canvas,
    List<RemoteWetInkStrokeSnapshot> snapshots,
    RoughAdapter adapter,
  ) {
    lastFrameTailPointCount = 0;
    for (final snapshot in snapshots) {
      final cache = _strokes[snapshot.strokeId];
      cache?.paint(canvas);
      for (final segment in snapshot.tailSegments) {
        lastFrameTailPointCount += segment.points.length;
        _drawSegment(canvas, segment, snapshot, adapter);
      }
      _lastPaintedMaxPointIndex[snapshot.strokeId] = snapshot.maxPointIndex;
      _lastPaintedSnapshots[snapshot.strokeId] = snapshot;
      _markPaintedIndices(snapshot);
    }
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
  }) : super(repaint: store);

  final RemoteWetInkStore store;
  final RemoteWetInkRenderCache cache;
  final RoughAdapter adapter;
  final ViewportState viewport;
  final CanvasLayout? layout;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = store.strokes;
    cache.sync(strokes, adapter);
    if (strokes.isEmpty) return;

    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
    _clipToPages(canvas);
    cache.paint(canvas, strokes, adapter);
    canvas.restore();
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
  bool shouldRepaint(RemoteWetInkPainter oldDelegate) =>
      oldDelegate.store != store ||
      oldDelegate.adapter != adapter ||
      oldDelegate.viewport != viewport ||
      oldDelegate.layout != layout;
}

class _RemoteStrokePictureCache {
  final Map<int, _FrozenBlockPicture> _blockPictures = {};

  int get pictureLayerCount => _blockPictures.length;
  int get pictureNestingDepth => pictureLayerCount == 0 ? 0 : 1;
  int get retainedGeometryPointCount =>
      _blockPictures.values.fold(0, (total, block) => total + block.pointCount);

  int sync(RemoteWetInkStrokeSnapshot snapshot, RoughAdapter adapter) {
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
      for (final segment in block.segments) {
        recordedPoints += segment.points.length;
        _drawSegment(canvas, segment, snapshot, adapter);
      }
      final nextPicture = recorder.endRecording();
      final replacement = _FrozenBlockPicture(
        picture: nextPicture,
        revision: block.revision,
        pointCount: block.pointCount,
      );
      current?.picture.dispose();
      _blockPictures[block.level] = replacement;
    }
    return recordedPoints;
  }

  void paint(Canvas canvas) {
    final levels = _blockPictures.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final level in levels) {
      final block = _blockPictures[level]!;
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
  });

  final ui.Picture picture;
  final int revision;
  final int pointCount;
}

void _drawSegment(
  Canvas canvas,
  RemoteWetInkSegment segment,
  RemoteWetInkStrokeSnapshot stroke,
  RoughAdapter adapter,
) {
  if (segment.points.isEmpty) return;
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
  adapter.drawFreedraw(
    canvas,
    element.points,
    element.pressures,
    element.simulatePressure,
    BrushType.fromWireName(stroke.style.brushType),
    DrawStyle.fromElement(element),
    isComplete: false,
  );
}
