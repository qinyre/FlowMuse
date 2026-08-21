import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../models/ai_visual_attachment.dart';

/// 把 PNG 归一化到最长边 ≤[maxAiVisualAttachmentLongestSide] 且字节数
/// ≤[byteLimit]。已合规的输入原样返回（不重编码，保持像素与纯净性）。
/// [byteLimit] 与 [maxPixelCount] 仅供测试注入（默认值即全局常量）。
Future<Uint8List> normalizeAttachmentPng(
  Uint8List bytes, {
  int byteLimit = maxAiVisualAttachmentBytes,
  int maxPixelCount = 4096 * 4096,
}) async {
  final (width, height) = await _pngDimensions(bytes);
  // 解压炸弹护栏：引擎对 PNG 无原生缩放解码，下方重缩放分支会先全尺寸解码
  // （峰值 ≈ 宽×高×4B），超大维度直接拒绝。该暴露面为存量（打开笔记即解码），
  // 此处不让伪造输入经附件路径放大。
  if (width * height > maxPixelCount) {
    throw StateError('图片过大，请缩小选区后重试');
  }
  final longest = math.max(width, height).toDouble();
  if (longest <= maxAiVisualAttachmentLongestSide &&
      bytes.length <= byteLimit) {
    return bytes;
  }
  // 档位首值必须等于 maxAiVisualAttachmentLongestSide。
  final tiers = <double>[
    maxAiVisualAttachmentLongestSide.toDouble(),
    1280,
    1024,
    768,
  ];
  for (final tier in tiers) {
    if (tier >= longest) continue; // 该档不缩小，体积不会下降
    final scale = tier / longest;
    final png = await _rescalePng(
      bytes,
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
    if (png != null && png.length <= byteLimit) return png;
  }
  throw StateError('图片过大，请缩小选区后重试');
}

/// Reads encoded pixel dimensions without decoding pixels; converts any
/// decode failure into a user-actionable [StateError].
Future<(int, int)> _pngDimensions(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (descriptor.width, descriptor.height);
  } catch (_) {
    throw StateError('图片处理失败，请重试');
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<Uint8List?> _rescalePng(
  Uint8List bytes,
  int targetWidth,
  int targetHeight,
) async {
  ui.Codec? codec;
  ui.FrameInfo? frame;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null; // 该档失败降级下一档
  } finally {
    frame?.image.dispose();
    codec?.dispose();
  }
}

/// 捕获当前选区为视觉附件（选区路径，经 exportRegionPng 区域渲染引擎）。
///
/// 捕获契约（hybrid §1.2）：返回 null 表示"当前选区无可捕获的视觉内容"
/// ——守卫为选区过滤 !isDeleted 后含非文本元素（判定自 whiteboard_page 的
/// visualSelected 迁入），不属失败，由调用方按场景静默或提示；抛
/// [StateError] 表示真失败，消息即用户文案。
Future<AiVisualAttachment?> captureSelectionAttachment(
  MarkdrawController controller,
) async {
  final selectedIds = controller.editorState.selectedIds;
  final hasVisualSelection = controller.selectedElements.any(
    (element) => !element.isDeleted && element is! TextElement,
  );
  if (selectedIds.isEmpty || !hasVisualSelection) return null;
  final bounds = ExportBounds.compute(
    controller.editorState.scene,
    selectedIds: selectedIds,
    padding: 8,
  );
  if (bounds == null) return null; // 防御分支：守卫已保证有活选区元素
  final rect = ui.Rect.fromLTWH(
    bounds.left,
    bounds.top,
    bounds.size.width,
    bounds.size.height,
  );
  final failedImages = await controller.prewarmRegionImages(rect);
  if (failedImages > 0) {
    // _failed 集合本会话粘性（image_cache.dart 不清理），"重试"无法兑现，
    // 文案如实指向重开笔记。
    throw StateError('图片解码失败，请重新打开笔记后重试');
  }
  final png = await controller.exportRegionPng(rect);
  if (png == null) throw StateError('截图生成失败，请重试');
  final normalized = await normalizeAttachmentPng(png);
  return AiVisualAttachment(
    sourceLabel: '选区截图',
    mimeType: 'image/png',
    bytes: normalized,
    kind: AiVisualAttachmentKind.selection,
  );
}

/// 捕获当前视口所在 PDF 页的原始位图附件（PDF 页路径，取导入时的整页
/// 原始字节，不含白板批注）。
///
/// 判页失败双文案（hybrid §1.6）：场景不含任何 `isPdfBackground` 元素 →
/// "当前笔记没有 PDF 页面"；场景含 PDF 背景但视口未落在页内 → "当前视图
/// 不在 PDF 页面内，请先滚动到 PDF 页"。视口判定用
/// `visible.overlaps(page.bounds)` 自行完成——`pageForVisibleRect` 有
/// nearest 回退、有页时永不返回 null，不得以它的 null 判"不在页内"。
Future<AiVisualAttachment?> captureCurrentPdfPageAttachment(
  MarkdrawController controller,
) async {
  final rawSize = controller.canvasSize;
  final canvasSize =
      rawSize.width <= 0 || rawSize.height <= 0
          ? const ui.Size(800, 600) // 与控制器 :1843 兜底一致
          : rawSize;
  final visible = controller.editorState.viewport.visibleRect(canvasSize);
  final page = controller.pageForVisibleRect(visible);
  if (page == null || !visible.overlaps(page.bounds)) {
    final hasPdfBackground = controller.editorState.scene.elements.any(
      (element) => !element.isDeleted && element.isPdfBackground,
    );
    if (!hasPdfBackground) {
      throw StateError('当前笔记没有 PDF 页面');
    }
    throw StateError('当前视图不在 PDF 页面内，请先滚动到 PDF 页');
  }
  ImageElement? background;
  for (final element in controller.editorState.scene.elements) {
    if (element.isDeleted || element is! ImageElement) continue;
    if (!element.isPdfBackground || element.pageId != page.id) continue;
    background = element;
    break;
  }
  final fileId = background?.fileId;
  final file = fileId == null
      ? null
      : controller.editorState.scene.files[fileId];
  // Scene.files 可经手工构造的 .markdraw 载入任意 mimeType+bytes 组合，
  // 双重把关：mime 白名单 + 模型层的 PNG 魔数校验。
  if (file == null || file.mimeType != 'image/png') {
    throw StateError('当前页面不是 PDF 页');
  }
  final normalized = await normalizeAttachmentPng(file.bytes);
  return AiVisualAttachment(
    sourceLabel: 'PDF 第 ${page.index + 1} 页',
    mimeType: 'image/png',
    bytes: normalized,
    kind: AiVisualAttachmentKind.pdfPage,
  );
}
