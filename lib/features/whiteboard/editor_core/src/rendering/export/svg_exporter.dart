import 'dart:convert';

import '../../core/elements/elements.dart';
import '../../core/io/io.dart';
import '../../core/scene/scene_exports.dart';
import '../../core/serialization/serialization.dart';
import 'export_bounds.dart';
import 'svg_element_renderer.dart';

/// Orchestrates full SVG document generation from a scene.
class SvgExporter {
  /// Exports the [scene] (or a subset via [selectedIds]) to an SVG string.
  ///
  /// Returns an empty string if there are no visible elements.
  ///
  /// [backgroundColor] adds a background `<rect>` fill.
  /// [embedMarkdraw] embeds the serialized .markdraw data as an HTML comment.
  static String export(
    Scene scene, {
    String? backgroundColor,
    Set<ElementId>? selectedIds,
    bool embedMarkdraw = true,
  }) {
    final bounds = ExportBounds.compute(scene, selectedIds: selectedIds);
    if (bounds == null) return '';

    final buf = StringBuffer();

    // SVG header
    buf.write('<svg xmlns="http://www.w3.org/2000/svg" ');
    buf.write('viewBox="${_n(bounds.left)} ${_n(bounds.top)} ');
    buf.write('${_n(bounds.size.width)} ${_n(bounds.size.height)}" ');
    buf.write('width="${_n(bounds.size.width)}" ');
    buf.write('height="${_n(bounds.size.height)}"');
    buf.write('>');

    // Background rect
    if (backgroundColor != null) {
      buf.write('<rect x="${_n(bounds.left)}" y="${_n(bounds.top)}" ');
      buf.write('width="${_n(bounds.size.width)}" ');
      buf.write('height="${_n(bounds.size.height)}" ');
      buf.write('fill="$backgroundColor"/>');
    }

    // Collect elements to render
    final ordered = scene.orderedElements;

    // Emit clipPath definitions for frames
    final frames = ordered.where((e) => !e.isDeleted && e is FrameElement);
    if (frames.isNotEmpty) {
      buf.write('<defs>');
      for (final frame in frames) {
        buf.write('<clipPath id="clip-${frame.id.value}">');
        buf.write('<rect x="${_n(frame.x)}" y="${_n(frame.y)}" ');
        buf.write('width="${_n(frame.width)}" height="${_n(frame.height)}"/>');
        buf.write('</clipPath>');
      }
      buf.write('</defs>');
    }

    for (final element in ordered) {
      if (element.isDeleted) continue;
      // Skip bound text — rendered with parent
      if (element is TextElement && element.containerId != null) continue;

      // If selection filter is active, skip non-selected elements
      if (selectedIds != null && !selectedIds.contains(element.id)) continue;

      // Wrap frame children in clip group
      final hasClip = element.frameId != null;
      if (hasClip) {
        buf.write('<g clip-path="url(#clip-${element.frameId})">');
      }

      buf.write(SvgElementRenderer.render(element, files: scene.files));

      // Render bound text for this element
      final boundText = scene.findBoundText(element.id);
      if (boundText != null && boundText.text.isNotEmpty) {
        _renderBoundText(buf, element, boundText);
      }

      if (hasClip) {
        buf.write('</g>');
      }
    }

    // Embed markdraw data
    if (embedMarkdraw) {
      final doc = SceneDocumentConverter.sceneToDocument(scene);
      final markdrawContent = DocumentSerializer.serialize(doc);
      final base64Data = base64Encode(utf8.encode(markdrawContent));
      buf.write('<!-- markdraw:base64:$base64Data -->');
    }

    buf.write('</svg>');
    return buf.toString();
  }

  static void _renderBoundText(
    StringBuffer buf,
    dynamic parent,
    TextElement textElem,
  ) {
    if (parent is ArrowElement) {
      // Arrow label — just render text element at its position
      buf.write(SvgElementRenderer.render(textElem));
    } else {
      // Shape label — render text centered within parent
      buf.write(SvgElementRenderer.render(textElem));
    }
  }

  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      var end = s.length;
      while (end > 0 && s[end - 1] == '0') {
        end--;
      }
      if (end > 0 && s[end - 1] == '.') end--;
      return s.substring(0, end);
    }
    return s;
  }
}
