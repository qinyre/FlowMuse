import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/elements/elements.dart' as core show TextElement;
import '../core/elements/elements.dart' hide TextElement;
import '../core/scene/scene_exports.dart';
import '../editor/bindings/arrow_label_utils.dart';
import 'element_renderer.dart';
import 'rough/rough_adapter.dart';
import 'text_renderer.dart';
import 'viewport_culling.dart';
import 'viewport_state.dart';

/// A [CustomPainter] that renders all active scene elements with a
/// hand-drawn aesthetic via [RoughAdapter].
///
/// Elements are drawn in fractional-index order. Deleted elements,
/// bound text (containerId != null), and off-screen elements are skipped
/// via [cullElements]. Viewport pan/zoom transforms are applied to the
/// canvas before rendering.
///
/// An optional [previewElement] is rendered last, for live creation preview.
class StaticCanvasPainter extends CustomPainter {
  final Scene scene;
  final RoughAdapter adapter;
  final ViewportState viewport;
  final Element? previewElement;

  /// When set, the text element with this ID is not rendered — the editing
  /// overlay is shown instead.
  final ElementId? editingElementId;

  /// Decoded images keyed by fileId, passed through to ElementRenderer.
  final Map<String, ui.Image>? resolvedImages;

  /// Pending flowchart elements rendered at 50% opacity as a preview.
  final List<Element>? pendingElements;

  /// Grid size in scene units; null means no grid.
  final int? gridSize;

  /// Whether the canvas background is dark (affects grid line colors).
  final bool isDarkBackground;

  const StaticCanvasPainter({
    required this.scene,
    required this.adapter,
    required this.viewport,
    this.previewElement,
    this.editingElementId,
    this.resolvedImages,
    this.pendingElements,
    this.gridSize,
    this.isDarkBackground = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // Apply viewport transform: scale then translate
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);

    // Render grid behind elements
    if (gridSize != null) {
      _renderGrid(canvas, size, gridSize!);
    }

    final visible = cullElements(scene.orderedElements, viewport, size);
    for (final element in visible) {
      // Skip standalone text that is being edited
      if (editingElementId != null &&
          element.id == editingElementId &&
          element is core.TextElement) {
        continue;
      }

      // Clip children of frames to frame bounds
      final parentFrame = element.frameId != null
          ? _findFrameElement(element.frameId!)
          : null;
      if (parentFrame != null) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(
            parentFrame.x,
            parentFrame.y,
            parentFrame.width,
            parentFrame.height,
          ),
        );
      }

      // For arrows with bound text, wrap in a saveLayer so we can
      // punch a clear hole behind the label (matching Excalidraw).
      // Keep the layer active during editing so the arrow line stays
      // cleared behind the editing overlay.
      final arrowLabel = element is ArrowElement
          ? scene.findBoundText(element.id)
          : null;
      final hasArrowLabel = arrowLabel != null && arrowLabel.text.isNotEmpty;
      if (hasArrowLabel) {
        canvas.saveLayer(null, Paint());
      }

      ElementRenderer.render(
        canvas,
        element,
        adapter,
        resolvedImages: resolvedImages,
      );
      _renderBoundText(canvas, element);

      if (hasArrowLabel) {
        canvas.restore();
      }

      if (parentFrame != null) {
        canvas.restore();
      }
    }

    // Render live creation preview on top
    if (previewElement != null) {
      ElementRenderer.render(
        canvas,
        previewElement!,
        adapter,
        resolvedImages: resolvedImages,
      );
    }

    // Render pending flowchart elements at 50% opacity
    if (pendingElements != null && pendingElements!.isNotEmpty) {
      canvas.saveLayer(null, Paint()..color = const Color(0x80FFFFFF));
      for (final element in pendingElements!) {
        ElementRenderer.render(
          canvas,
          element,
          adapter,
          resolvedImages: resolvedImages,
        );
      }
      canvas.restore();
    }

    canvas.restore();
  }

  /// Finds a frame element by its ID value.
  FrameElement? _findFrameElement(String frameId) {
    final el = scene.getElementById(ElementId(frameId));
    return el is FrameElement ? el : null;
  }

  /// Renders bound text inside a container shape or at an arrow's midpoint.
  void _renderBoundText(Canvas canvas, Element element) {
    final boundText = scene.findBoundText(element.id);
    if (boundText == null || boundText.text.isEmpty) return;
    final isEditing =
        editingElementId != null && boundText.id == editingElementId;

    if (element is ArrowElement) {
      // Always clear the arrow behind the label (even during editing,
      // so the overlay text isn't drawn over the arrow line).
      _renderArrowLabel(canvas, element, boundText, skipText: isEditing);
    } else {
      if (!isEditing) {
        _renderShapeLabel(canvas, element, boundText);
      }
    }
  }

  /// Renders bound text centered inside a container shape.
  void _renderShapeLabel(
    Canvas canvas,
    Element shape,
    core.TextElement textElem,
  ) {
    final hasRotation = shape.angle != 0.0;
    if (hasRotation) {
      canvas.save();
      final cx = shape.x + shape.width / 2;
      final cy = shape.y + shape.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(shape.angle);
      canvas.translate(-cx, -cy);
    }

    const boundTextPadding = 5.0;
    final maxWidth = shape.width - boundTextPadding * 2;
    final painter = TextRenderer.buildTextPainter(textElem);
    // Use longestLine so painter.width reflects actual content width,
    // allowing us to manually position based on textAlign.
    painter.textWidthBasis = TextWidthBasis.longestLine;
    painter.layout(maxWidth: maxWidth > 0 ? maxWidth : 0);

    final textX = switch (textElem.textAlign) {
      TextAlign.left => shape.x + boundTextPadding,
      TextAlign.center => shape.x + (shape.width - painter.width) / 2,
      TextAlign.right =>
        shape.x + shape.width - painter.width - boundTextPadding,
    };
    final textY = switch (textElem.verticalAlign) {
      VerticalAlign.top => shape.y + boundTextPadding,
      VerticalAlign.middle => shape.y + (shape.height - painter.height) / 2,
      VerticalAlign.bottom =>
        shape.y + shape.height - painter.height - boundTextPadding,
    };
    painter.paint(canvas, Offset(textX, textY));
    painter.dispose();

    if (hasRotation) {
      canvas.restore();
    }
  }

  /// Renders a label centered on the arrow's midpoint, clearing the arrow
  /// line behind the text (matching Excalidraw behavior).
  ///
  /// When [skipText] is true, only the clear rect is drawn (used during
  /// editing so the overlay text isn't drawn over the arrow line).
  void _renderArrowLabel(
    Canvas canvas,
    ArrowElement arrow,
    core.TextElement textElem, {
    bool skipText = false,
  }) {
    final mid = ArrowLabelUtils.computeArrowMidpoint(arrow);

    final painter = TextRenderer.buildTextPainter(textElem);
    painter.layout();

    // Center text on midpoint
    final textX = mid.x - painter.width / 2;
    final textY = mid.y - painter.height / 2;

    // Clear the arrow behind the text with padding — the arrow and label
    // are wrapped in a saveLayer by the paint loop, so BlendMode.clear
    // punches a transparent hole through the arrow pixels, letting the
    // canvas background show through.
    canvas.drawRect(
      Rect.fromLTWH(
        textX - boundTextPadding,
        textY - boundTextPadding,
        painter.width + boundTextPadding * 2,
        painter.height + boundTextPadding * 2,
      ),
      Paint()..blendMode = ui.BlendMode.clear,
    );

    if (!skipText) {
      painter.paint(canvas, Offset(textX, textY));
    }
    painter.dispose();
  }

  void _renderGrid(Canvas canvas, Size size, int gridSize) {
    final g = gridSize.toDouble();

    // Compute visible range in scene coordinates
    final left = viewport.offset.dx;
    final top = viewport.offset.dy;
    final right = left + size.width / viewport.zoom;
    final bottom = top + size.height / viewport.zoom;

    final lineColor = isDarkBackground
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE0E0E0);
    final boldColor = isDarkBackground
        ? const Color(0xFF4A4A4A)
        : const Color(0xFFCCCCCC);

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0 / viewport.zoom;

    final boldPaint = Paint()
      ..color = boldColor
      ..strokeWidth = 1.0 / viewport.zoom;

    final startX = (left / g).floor() * g;
    final startY = (top / g).floor() * g;

    for (var x = startX; x <= right; x += g) {
      final isBold = (x / g).round() % 5 == 0;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, bottom),
        isBold ? boldPaint : paint,
      );
    }
    for (var y = startY; y <= bottom; y += g) {
      final isBold = (y / g).round() % 5 == 0;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        isBold ? boldPaint : paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaticCanvasPainter oldDelegate) {
    return !identical(scene, oldDelegate.scene) ||
        !identical(adapter, oldDelegate.adapter) ||
        viewport != oldDelegate.viewport ||
        !identical(previewElement, oldDelegate.previewElement) ||
        !identical(pendingElements, oldDelegate.pendingElements) ||
        !identical(resolvedImages, oldDelegate.resolvedImages) ||
        editingElementId != oldDelegate.editingElementId ||
        gridSize != oldDelegate.gridSize ||
        isDarkBackground != oldDelegate.isDarkBackground;
  }
}
