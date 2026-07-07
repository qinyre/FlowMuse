import 'dart:typed_data';
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/scene/scene_exports.dart';
import '../rough/rough_adapter.dart';
import '../static_canvas_painter.dart';
import '../viewport_state.dart';
import 'export_bounds.dart';
import 'png_metadata.dart';

/// Renders a scene to PNG bytes via [PictureRecorder] and [StaticCanvasPainter].
class PngExporter {
  /// Exports the [scene] (or a subset via [selectedIds]) to PNG bytes.
  ///
  /// Returns null if the scene (or selection) has no visible elements.
  ///
  /// [scale] multiplies the pixel dimensions (e.g., 2 for retina).
  /// [backgroundColor] fills behind the scene; null for transparent.
  /// [embedMarkdraw] embeds the serialized .markdraw data in a PNG tEXt chunk.
  static Future<Uint8List?> export(
    Scene scene,
    RoughAdapter adapter, {
    int scale = 1,
    Color? backgroundColor,
    Set<ElementId>? selectedIds,
    bool embedMarkdraw = true,
  }) async {
    final bounds = ExportBounds.compute(scene, selectedIds: selectedIds);
    if (bounds == null) return null;

    final width = bounds.size.width * scale;
    final height = bounds.size.height * scale;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill background if provided
    if (backgroundColor != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = backgroundColor,
      );
    }

    // Create a viewport that maps the export bounds to the canvas origin
    final viewport = ViewportState(
      offset: Offset(bounds.left, bounds.top),
      zoom: scale.toDouble(),
    );

    final painter = StaticCanvasPainter(
      scene: scene,
      adapter: adapter,
      viewport: viewport,
    );

    painter.paint(canvas, Size(width, height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    if (byteData == null) return null;
    var pngBytes = byteData.buffer.asUint8List();

    // Embed .markdraw data in PNG tEXt chunk
    if (embedMarkdraw) {
      pngBytes = PngMetadata.embedMarkdrawData(pngBytes, scene) ?? pngBytes;
    }

    return pngBytes;
  }
}
