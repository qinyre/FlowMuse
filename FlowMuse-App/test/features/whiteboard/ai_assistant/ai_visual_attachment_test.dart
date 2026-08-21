import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(int length) => Uint8List(length);

void main() {
  test('合法 PNG 附件通过校验并保留字段', () {
    final attachment = AiVisualAttachment.validated(
      mimeType: 'image/png',
      bytes: bytesOf(1024),
      sourceLabel: '当前选区',
      width: 800,
      height: 600,
    );
    expect(attachment.mimeType, 'image/png');
    expect(attachment.sourceLabel, '当前选区');
    expect(attachment.width, 800);
    expect(attachment.height, 600);
  });

  test('拒绝不支持的 MIME 类型', () {
    expect(
      () => AiVisualAttachment.validated(
        mimeType: 'image/gif',
        bytes: bytesOf(16),
        sourceLabel: '当前选区',
        width: 10,
        height: 10,
      ),
      throwsFormatException,
    );
  });

  test('拒绝超过 4MiB 的单张附件', () {
    expect(
      () => AiVisualAttachment.validated(
        mimeType: 'image/png',
        bytes: bytesOf(maxAiVisualBytes + 1),
        sourceLabel: '当前选区',
        width: 100,
        height: 100,
      ),
      throwsFormatException,
    );
  });

  test('拒绝空字节或空来源标签', () {
    expect(
      () => AiVisualAttachment.validated(
        mimeType: 'image/jpeg',
        bytes: Uint8List(0),
        sourceLabel: '当前选区',
        width: 10,
        height: 10,
      ),
      throwsFormatException,
    );
    expect(
      () => AiVisualAttachment.validated(
        mimeType: 'image/jpeg',
        bytes: bytesOf(16),
        sourceLabel: '  ',
        width: 10,
        height: 10,
      ),
      throwsFormatException,
    );
  });

  test('拒绝非正数或超长边尺寸', () {
    for (final (width, height) in [(0, 10), (10, 0), (-5, 10), (2049, 10)]) {
      expect(
        () => AiVisualAttachment.validated(
          mimeType: 'image/png',
          bytes: bytesOf(16),
          sourceLabel: '当前选区',
          width: width,
          height: height,
        ),
        throwsFormatException,
        reason: 'width=$width height=$height 应被拒绝',
      );
    }
  });
}
