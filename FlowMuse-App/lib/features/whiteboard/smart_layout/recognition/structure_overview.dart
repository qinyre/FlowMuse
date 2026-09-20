import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../rendering/draft_scene_renderer.dart';
import '../snapshot/layout_page_snapshot.dart' show conservativeVisualBounds;
import 'recognition_budget.dart';
import 'recognition_models.dart';

/// 同轮捕获的内容概览，编号 [n] 与请求 units[n-1] 对应。
/// 只生成临时位图，不向 Scene 添加编号/边框或改变原图裁剪。
Future<String?> buildStructureOverview({
  required Scene scene,
  required List<RecognitionUnitInput> units,
  required RecognitionBudget budget,
  required bool Function() isActive,
}) async {
  final content = scene.activeElements
      .where((e) => !e.isCanvasPage && !e.isPdfBackground)
      .toList();
  if (content.isEmpty || units.isEmpty || !isActive()) return null;
  var contentScene = Scene();
  ui.Rect? bounds;
  for (final element in content) {
    contentScene = contentScene.addElement(element);
    final box = conservativeVisualBounds(element);
    final rect = ui.Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    bounds = bounds?.expandToInclude(rect) ?? rect;
    if (element is ImageElement) {
      final file = scene.files[element.fileId];
      if (file != null) {
        contentScene = contentScene.addFile(element.fileId, file);
      }
    }
  }
  for (final unit in units) {
    final b = unit.bounds;
    bounds = bounds!.expandToInclude(
      ui.Rect.fromLTWH(b.left, b.top, b.width, b.height),
    );
  }
  final frame = bounds!.inflate(24);
  if (!frame.isFinite || frame.isEmpty) return null;
  final renderer = DraftSceneRenderer();
  try {
    // ponytail: 超字节限额最多降采样两次；不拆成逐图模型请求。
    for (
      var edge = math.min(2048, budget.overviewMaxEdgePx);
      edge >= 512;
      edge ~/= 2
    ) {
      if (!isActive()) return null;
      final scale = math.min(
        edge / math.max(frame.width, frame.height),
        math.sqrt((2 * 1024 * 1024 - 4096) / (frame.width * frame.height)),
      );
      final width = math.max(1, (frame.width * scale).floor());
      final height = math.max(1, (frame.height * scale).floor());
      final snapshot = await renderer.render(
        scene: contentScene,
        viewport: ViewportState(offset: frame.topLeft, zoom: scale),
        pixelSize: ui.Size(width.toDouble(), height.toDouble()),
      );
      try {
        // 不让模型依据占位灰框猜图片内容。
        if (!isActive() || snapshot.hasMissingResources) return null;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
        canvas.drawImage(snapshot.image, ui.Offset.zero, ui.Paint());
        for (var i = 0; i < units.length; i++) {
          final b = units[i].bounds;
          final rect = ui.Rect.fromLTWH(
            (b.left - frame.left) * scale,
            (b.top - frame.top) * scale,
            b.width * scale,
            b.height * scale,
          );
          canvas.drawRect(
            rect,
            ui.Paint()
              ..color = const ui.Color(0xff1565c0)
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          final label = TextPainter(
            text: TextSpan(
              text: '[${i + 1}]',
              style: const TextStyle(
                color: ui.Color(0xff1565c0),
                fontSize: 16,
                backgroundColor: ui.Color(0xffffffff),
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          label.paint(
            canvas,
            ui.Offset(
              rect.left.clamp(0, math.max(0, width - label.width)),
              math.max(0, rect.top - label.height),
            ),
          );
          label.dispose();
        }
        final picture = recorder.endRecording();
        ui.Image? marked;
        try {
          marked = await picture.toImage(width, height);
          final png = await marked.toByteData(format: ui.ImageByteFormat.png);
          if (!isActive() || png == null) return null;
          final encoded = base64Encode(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
          if (encoded.length <= recognitionMaxImageBase64Chars) return encoded;
        } finally {
          marked?.dispose();
          picture.dispose();
        }
      } finally {
        snapshot.dispose();
      }
    }
    return null;
  } finally {
    renderer.dispose();
  }
}
