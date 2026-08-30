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
    // 湿墨必为新笔迹：pressures 已编码，customData 带 pressureEncoding=1
    // 与落笔冻结的 renderVersion（T6 工作项 3），与提交后静态元素共用
    // 同一渲染判定/dispatch。缺 pressures（模拟压感）时分发端自动回 v1。
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
      customData: customDataWithFreedrawRender(
        null,
        view.brushType,
        renderVersion: view.renderVersion,
      ),
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
