// Uint8List/ByteData 经 package:flutter/foundation.dart 重导出提供。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

const int maxAiVisualAttachments = 3;
const int maxAiVisualAttachmentBytes = 4 * 1024 * 1024;
const int maxAiVisualAttachmentLongestSide = 1568;

/// 附件来源类型：selection=选区截图；pdfPage=PDF 页原始位图。
/// 供面板区分活动选区槽与手动附件，免字符串匹配。
enum AiVisualAttachmentKind { selection, pdfPage }

/// 单次 AI 请求的视觉附件。仅存于面板内存态：
/// 不序列化（无 toJson）、不入库、不入会话历史、不入日志。
/// 构造自由、发送前统一经 [requireValidAiVisualAttachments] 校验。
@immutable
class AiVisualAttachment {
  const AiVisualAttachment({
    required this.sourceLabel,
    required this.mimeType,
    required this.bytes,
    required this.kind,
  });

  final String sourceLabel;
  final String mimeType;
  final Uint8List bytes;
  final AiVisualAttachmentKind kind;

  String get sizeLabel => '${(bytes.lengthInBytes / 1024).toStringAsFixed(0)} KiB';
}

/// 发送前的附件校验单点。定稿校验顺序（勿再调整）：
/// 数量 → mime → 空字节 → PNG 魔数 → 4MiB 长度 → 结构化 chunk 扫描。
List<AiVisualAttachment> requireValidAiVisualAttachments(
  List<AiVisualAttachment> attachments,
) {
  if (attachments.length > maxAiVisualAttachments) {
    throw const FormatException('最多添加 3 张图片');
  }
  for (final attachment in attachments) {
    if (attachment.mimeType != 'image/png') {
      throw const FormatException('仅支持 PNG 图片附件');
    }
    if (attachment.bytes.isEmpty) {
      throw const FormatException('图片数据为空，请重新添加');
    }
    if (!_hasPngSignature(attachment.bytes)) {
      throw const FormatException('仅支持 PNG 图片附件');
    }
    if (attachment.bytes.length > maxAiVisualAttachmentBytes) {
      throw const FormatException('单张图片需小于 4 MiB，请缩小选区后重试');
    }
    if (!_isPngChunkStructureClean(attachment.bytes)) {
      throw const FormatException('仅支持 PNG 图片附件');
    }
  }
  return List.unmodifiable(attachments);
}

const _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

bool _hasPngSignature(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// PNG 纯净性校验：按 chunk 结构解析（8 字节签名后循环「4B 长度 + 4B 类型 +
/// 数据 + 4B CRC」直至 IEND），禁止携带 tEXt/iTXt/zTXt（防 .markdraw 元数据
/// 外发）。长度越界、结构截断、IEND 后仍有剩余字节（拼接尾挂）均视为畸形
/// 拒绝。禁裸子串搜索——IDAT 压缩流中偶现 "tEXt" 字节序列会误伤合法图片。
bool _isPngChunkStructureClean(Uint8List bytes) {
  final byteData = ByteData.sublistView(bytes);
  var offset = _pngSignature.length;
  var sawIend = false;
  while (offset < bytes.length) {
    if (sawIend) return false;
    final remaining = bytes.length - offset;
    if (remaining < 12) return false;
    final dataLength = byteData.getUint32(offset, Endian.big);
    if (dataLength > remaining - 12) return false;
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'tEXt' || type == 'iTXt' || type == 'zTXt') return false;
    offset += 12 + dataLength;
    if (type == 'IEND') sawIend = true;
  }
  return sawIend;
}

/// 仅当带附件且状态码属于视觉/体积相关 4xx 时返回专用文案；
/// 其余（含 401/403 鉴权失败与 404 地址/模型配置错误）返回 null，走通用文案。
String? aiVisualAttachmentError({
  required int statusCode,
  required bool hasAttachments,
}) {
  if (!hasAttachments) return null;
  return switch (statusCode) {
    413 => '图片附件超出服务大小限制，请减少附件或缩小图片后重试（HTTP 413）',
    400 || 415 || 422 =>
      '当前模型可能不支持图片输入，请移除图片附件后重试，或更换支持视觉的模型（HTTP $statusCode）',
    _ => null,
  };
}

/// 过渡期选区附件构建（T5' 切线后删除，归一化单点移交捕获模块）：
/// 把选区渲染出的 PNG 字节解码重编码到最长边上限内；解码失败返回 null
/// （调用方降级纯文本）。所有解码资源在 finally 中释放，异常路径不泄漏。
Future<AiVisualAttachment?> buildAiVisualAttachment(
  Uint8List? pngBytes, {
  String sourceLabel = '当前选区',
}) async {
  if (pngBytes == null || pngBytes.isEmpty) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.FrameInfo? frame;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(pngBytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    var targetWidth = descriptor.width;
    var targetHeight = descriptor.height;
    final longestEdge =
        targetWidth > targetHeight ? targetWidth : targetHeight;
    if (longestEdge > maxAiVisualAttachmentLongestSide) {
      final ratio = maxAiVisualAttachmentLongestSide / longestEdge;
      targetWidth = (targetWidth * ratio).round();
      targetHeight = (targetHeight * ratio).round();
    }
    codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    frame = await codec.getNextFrame();
    final encoded = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (encoded == null) return null;
    return AiVisualAttachment(
      sourceLabel: sourceLabel,
      mimeType: 'image/png',
      bytes: encoded.buffer.asUint8List(),
      kind: AiVisualAttachmentKind.selection,
    );
  } catch (_) {
    // 解码/重编码失败属业务失败的一种：返回 null 让调用方降级纯文本。
    return null;
  } finally {
    buffer?.dispose();
    descriptor?.dispose();
    codec?.dispose();
    frame?.image.dispose();
  }
}
