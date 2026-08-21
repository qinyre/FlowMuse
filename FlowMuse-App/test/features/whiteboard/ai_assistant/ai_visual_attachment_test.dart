import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(int length) => Uint8List(length);

Future<Uint8List> solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

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

  test('超大长边按比例缩放到上限内并重编码', () async {
    final png = await solidPng(3000, 1500);
    final attachment = await buildAiVisualAttachment(png);
    expect(attachment, isNotNull);
    expect(attachment!.width, maxAiVisualEdgeLength);
    expect(attachment.height, maxAiVisualEdgeLength ~/ 2);
    expect(attachment.mimeType, 'image/png');
  });

  test('小图保持原尺寸直接复用字节', () async {
    final png = await solidPng(320, 240);
    final attachment = await buildAiVisualAttachment(png);
    expect(attachment, isNotNull);
    expect(attachment!.width, 320);
    expect(attachment.height, 240);
  });

  test('非法字节返回 null 而不是抛异常', () async {
    expect(await buildAiVisualAttachment(null), isNull);
    expect(await buildAiVisualAttachment(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
