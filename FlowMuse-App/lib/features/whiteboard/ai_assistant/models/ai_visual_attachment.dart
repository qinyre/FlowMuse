import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

const int maxAiVisualAttachments = 3;
const int maxAiVisualBytes = 4 * 1024 * 1024;
const int maxAiVisualEdgeLength = 2048;

const _allowedMimeTypes = {'image/png', 'image/jpeg'};

/// 用户明确选择的画布视觉内容，仅存在于当前 AI 请求内。
@immutable
class AiVisualAttachment {
  const AiVisualAttachment({
    required this.mimeType,
    required this.bytes,
    required this.sourceLabel,
    required this.width,
    required this.height,
  });

  factory AiVisualAttachment.validated({
    required String mimeType,
    required Uint8List bytes,
    required String sourceLabel,
    required int width,
    required int height,
  }) {
    if (!_allowedMimeTypes.contains(mimeType)) {
      throw const FormatException('不支持的图片类型');
    }
    if (bytes.isEmpty || bytes.length > maxAiVisualBytes) {
      throw const FormatException('图片大小超出限制');
    }
    final label = sourceLabel.trim();
    if (label.isEmpty) {
      throw const FormatException('图片来源标签无效');
    }
    if (width <= 0 ||
        height <= 0 ||
        width > maxAiVisualEdgeLength ||
        height > maxAiVisualEdgeLength) {
      throw const FormatException('图片尺寸超出限制');
    }
    return AiVisualAttachment(
      mimeType: mimeType,
      bytes: bytes,
      sourceLabel: label,
      width: width,
      height: height,
    );
  }

  final String mimeType;
  final Uint8List bytes;
  final String sourceLabel;
  final int width;
  final int height;
}

/// 把选区渲染出的 PNG 字节转为受控附件；解码失败返回 null（调用方降级纯文本）。
Future<AiVisualAttachment?> buildAiVisualAttachment(
  Uint8List? pngBytes, {
  String sourceLabel = '当前选区',
}) async {
  if (pngBytes == null || pngBytes.isEmpty) return null;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pngBytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    var targetWidth = descriptor.width;
    var targetHeight = descriptor.height;
    final longestEdge = targetWidth > targetHeight ? targetWidth : targetHeight;
    if (longestEdge > maxAiVisualEdgeLength) {
      final ratio = maxAiVisualEdgeLength / longestEdge;
      targetWidth = (targetWidth * ratio).round();
      targetHeight = (targetHeight * ratio).round();
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final encoded = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    descriptor.dispose();
    codec.dispose();
    if (encoded == null) return null;
    return AiVisualAttachment.validated(
      mimeType: 'image/png',
      bytes: encoded.buffer.asUint8List(),
      sourceLabel: sourceLabel,
      width: targetWidth,
      height: targetHeight,
    );
  } catch (_) {
    return null;
  }
}
