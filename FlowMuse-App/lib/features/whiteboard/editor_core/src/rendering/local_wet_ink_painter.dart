import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/elements/elements.dart';
import '../core/layout/layout.dart';
import '../core/math/math.dart';
import '../input/active_preview_metrics_probe.dart';
import 'element_renderer.dart';
import 'local_wet_ink_state.dart';
import 'rough/rough_adapter.dart';
import 'viewport_state.dart';

/// Paints the current local stroke without rebuilding or mutating the scene.
class LocalWetInkPainter extends CustomPainter {
  LocalWetInkPainter({
    required this.state,
    required this.adapter,
    required this.viewport,
    this.layout,
    this.contentBounds,
    this.activePreviewMetricsProbe,
  }) : super(repaint: state);

  final LocalWetInkState state;
  final RoughAdapter adapter;
  final ViewportState viewport;
  final CanvasLayout? layout;
  final Bounds? contentBounds;
  final ActivePreviewMetricsProbe? activePreviewMetricsProbe;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = state.frame;
    if (frame == null || frame.view.points.isEmpty) return;

    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
    _clipToPages(canvas);
    final bounds = contentBounds;
    if (bounds != null) {
      canvas.clipRect(
        Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.size.width,
          bounds.size.height,
        ),
      );
    }

    final view = frame.view;
    final base = FreedrawElement(
      id: view.strokeId,
      x: 0,
      y: 0,
      width: 0,
      height: 0,
      points: view.points,
      pressures: view.pressures,
      simulatePressure: view.simulatePressure,
      isComplete: false,
      customData: customDataWithBrushType(null, view.brushType),
    );
    final style = frame.style;
    final element = base.copyWith(
      strokeColor: style.strokeColor,
      backgroundColor: style.backgroundColor,
      strokeWidth: style.strokeWidth,
      strokeStyle: style.strokeStyle,
      fillStyle: style.fillStyle,
      roughness: style.roughness,
      opacity: style.opacity,
    );
    ElementRenderer.render(canvas, element, adapter);
    canvas.restore();

    final maxInputSeq = frame.maxInputSeq;
    if (maxInputSeq != null) {
      activePreviewMetricsProbe?.recordPaintedThrough(
        marker: ActivePreviewPaintMarker(
          strokeEpoch: frame.strokeEpoch,
          maxInputSeq: maxInputSeq,
        ),
        frameNumber: ui.PlatformDispatcher.instance.frameData.frameNumber,
      );
    }
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
  bool shouldRepaint(LocalWetInkPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.adapter != adapter ||
      oldDelegate.viewport != viewport ||
      oldDelegate.layout != layout ||
      oldDelegate.contentBounds != contentBounds ||
      oldDelegate.activePreviewMetricsProbe != activePreviewMetricsProbe;
}
