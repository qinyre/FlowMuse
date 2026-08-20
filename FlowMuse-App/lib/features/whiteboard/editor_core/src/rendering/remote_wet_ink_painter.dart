import 'dart:ui' as ui;

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

  void sync(List<RemoteWetInkStrokeSnapshot> snapshots, RoughAdapter adapter) {
    final activeIds = {for (final snapshot in snapshots) snapshot.strokeId};
    final removedIds = [
      for (final strokeId in _strokes.keys)
        if (!activeIds.contains(strokeId)) strokeId,
    ];
    for (final strokeId in removedIds) {
      _strokes.remove(strokeId)?.dispose();
      _lastPaintedMaxPointIndex.remove(strokeId);
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
      cache?.paint(canvas, snapshot.incrementalSegments);
      for (final segment in snapshot.tailSegments) {
        lastFrameTailPointCount += segment.points.length;
        _drawSegment(canvas, segment, snapshot, adapter);
      }
      _lastPaintedMaxPointIndex[snapshot.strokeId] = snapshot.maxPointIndex;
    }
  }

  void dispose() {
    for (final stroke in _strokes.values) {
      stroke.dispose();
    }
    _strokes.clear();
    _lastPaintedMaxPointIndex.clear();
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
  ui.Picture? _consolidatedPicture;
  int _consolidatedSegmentCount = 0;
  final Map<RemoteWetInkSegment, ui.Picture> _incrementalPictures = {};
  int _consolidatedPointCount = 0;

  int get pictureLayerCount =>
      (_consolidatedPicture == null ? 0 : 1) + _incrementalPictures.length;
  int get pictureNestingDepth => pictureLayerCount == 0 ? 0 : 1;
  int get retainedGeometryPointCount =>
      _consolidatedPointCount +
      _incrementalPictures.keys.fold(
        0,
        (total, segment) => total + segment.points.length,
      );

  int sync(RemoteWetInkStrokeSnapshot snapshot, RoughAdapter adapter) {
    var recordedPoints = 0;
    if (snapshot.consolidatedSegments.length < _consolidatedSegmentCount) {
      dispose();
    }
    if (snapshot.consolidatedSegments.length > _consolidatedSegmentCount) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      var consolidatedPointCount = 0;
      for (final segment in snapshot.consolidatedSegments) {
        recordedPoints += segment.points.length;
        consolidatedPointCount += segment.points.length;
        _drawSegment(canvas, segment, snapshot, adapter);
      }
      final nextPicture = recorder.endRecording();
      _consolidatedPicture?.dispose();
      _consolidatedPicture = nextPicture;
      _consolidatedSegmentCount = snapshot.consolidatedSegments.length;
      _consolidatedPointCount = consolidatedPointCount;
    }

    final currentSegments = snapshot.incrementalSegments.toSet();
    final removed = [
      for (final segment in _incrementalPictures.keys)
        if (!currentSegments.contains(segment)) segment,
    ];
    for (final segment in removed) {
      _incrementalPictures.remove(segment)?.dispose();
    }
    for (final segment in snapshot.incrementalSegments) {
      if (_incrementalPictures.containsKey(segment)) continue;
      final recorder = ui.PictureRecorder();
      _drawSegment(Canvas(recorder), segment, snapshot, adapter);
      _incrementalPictures[segment] = recorder.endRecording();
      recordedPoints += segment.points.length;
    }
    return recordedPoints;
  }

  void paint(Canvas canvas, List<RemoteWetInkSegment> incrementalSegments) {
    final consolidated = _consolidatedPicture;
    if (consolidated != null) canvas.drawPicture(consolidated);
    for (final segment in incrementalSegments) {
      final picture = _incrementalPictures[segment];
      if (picture != null) canvas.drawPicture(picture);
    }
  }

  void dispose() {
    _consolidatedPicture?.dispose();
    _consolidatedPicture = null;
    _consolidatedSegmentCount = 0;
    _consolidatedPointCount = 0;
    for (final picture in _incrementalPictures.values) {
      picture.dispose();
    }
    _incrementalPictures.clear();
  }
}

void _drawSegment(
  Canvas canvas,
  RemoteWetInkSegment segment,
  RemoteWetInkStrokeSnapshot stroke,
  RoughAdapter adapter,
) {
  if (segment.points.isEmpty) return;
  final pressures = segment.points.every((point) => point.pressure != null)
      ? [for (final point in segment.points) point.pressure!]
      : const <double>[];
  final element = FreedrawElement(
    id: ElementId(stroke.strokeId),
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    points: [for (final point in segment.points) Point(point.x, point.y)],
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
