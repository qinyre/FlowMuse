import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1×1 基准 PNG（IHDR + IDAT + IEND，无文本 chunk、IEND 后无残余字节）。
final Uint8List basePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

AiVisualAttachment selectionAttachmentOf(Uint8List bytes) =>
    AiVisualAttachment(
      sourceLabel: '当前选区',
      mimeType: 'image/png',
      bytes: bytes,
      kind: AiVisualAttachmentKind.selection,
    );

// 原 buildAiVisualAttachment 的 3 个归一化行为用例已随该函数删除迁至
// visual_attachment_capture_test.dart（归一化单点 normalizeAttachmentPng）。

void main() {
  test('第 4 张附件被拒绝并提示数量上限', () {
    expect(
      () => requireValidAiVisualAttachments([
        for (var i = 0; i < maxAiVisualAttachments + 1; i++)
          selectionAttachmentOf(basePng),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '最多添加 3 张图片',
        ),
      ),
    );
  });

  test('非 PNG mime 被拒绝', () {
    final attachment = AiVisualAttachment(
      sourceLabel: '当前选区',
      mimeType: 'image/jpeg',
      bytes: basePng,
      kind: AiVisualAttachmentKind.selection,
    );
    expect(
      () => requireValidAiVisualAttachments([attachment]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '仅支持 PNG 图片附件',
        ),
      ),
    );
  });

  test('空字节被拒绝', () {
    final attachment = selectionAttachmentOf(Uint8List(0));
    expect(
      () => requireValidAiVisualAttachments([attachment]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '图片数据为空，请重新添加',
        ),
      ),
    );
  });

  test('mime 合法但非 PNG 魔数被拒绝', () {
    final jpegHeader = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
    ]);
    final attachment = selectionAttachmentOf(jpegHeader);
    expect(
      () => requireValidAiVisualAttachments([attachment]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '仅支持 PNG 图片附件',
        ),
      ),
    );
  });

  test('超 4MiB 被拒绝且先于 chunk 扫描命中体积文案', () {
    final oversized = Uint8List(maxAiVisualAttachmentBytes + 1);
    oversized.setRange(0, 8, basePng.sublist(0, 8));
    final attachment = selectionAttachmentOf(oversized);
    expect(
      () => requireValidAiVisualAttachments([attachment]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '单张图片需小于 4 MiB，请缩小选区后重试',
        ),
      ),
    );
  });

  test('合法列表原样通过并保留字段', () {
    final first = AiVisualAttachment(
      sourceLabel: '当前选区',
      mimeType: 'image/png',
      bytes: basePng,
      kind: AiVisualAttachmentKind.selection,
    );
    final second = AiVisualAttachment(
      sourceLabel: 'PDF 第 3 页',
      mimeType: 'image/png',
      bytes: basePng,
      kind: AiVisualAttachmentKind.pdfPage,
    );
    final valid = requireValidAiVisualAttachments([first, second]);
    expect(valid, hasLength(2));
    expect(valid.first, same(first));
    expect(valid.last, same(second));
    expect(valid.first.kind, AiVisualAttachmentKind.selection);
    expect(valid.last.kind, AiVisualAttachmentKind.pdfPage);
    expect(valid.first.sizeLabel, '0 KiB');
    expect(() => valid.add(first), throwsUnsupportedError);
  });

  test('chunk 结构畸形被拒绝', () {
    // Given：PNG 签名后声明一个 16 字节数据的 IHDR chunk，但数据与 CRC 被截断。
    final malformed = Uint8List.fromList([
      ...basePng.sublist(0, 8),
      0x00, 0x00, 0x00, 0x10,
      0x49, 0x48, 0x44, 0x52,
      0x01, 0x02, 0x03,
    ]);
    expect(
      () => requireValidAiVisualAttachments([selectionAttachmentOf(malformed)]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '仅支持 PNG 图片附件',
        ),
      ),
    );
  });

  test('IEND 后拼接 tEXt 尾部被拒绝', () {
    // Given：在完整基准 PNG 的 IEND 之后拼接一个结构完整的 tEXt chunk。
    final stego = Uint8List.fromList([
      ...basePng,
      0x00, 0x00, 0x00, 0x09,
      ...'tEXt'.codeUnits,
      ...'Comment\x00x'.codeUnits,
      0x00, 0x00, 0x00, 0x00,
    ]);
    expect(
      () => requireValidAiVisualAttachments([selectionAttachmentOf(stego)]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '仅支持 PNG 图片附件',
        ),
      ),
    );
  });

  test('无附件任何状态码都返回 null', () {
    for (final statusCode in [400, 401, 403, 404, 413, 415, 422, 500]) {
      expect(
        aiVisualAttachmentError(
          statusCode: statusCode,
          hasAttachments: false,
        ),
        isNull,
        reason: '状态码 $statusCode 无附件应落通用文案',
      );
    }
  });

  test('有附件 413 返回体积文案', () {
    final message = aiVisualAttachmentError(
      statusCode: 413,
      hasAttachments: true,
    );
    expect(message, contains('HTTP 413'));
    expect(message, contains('大小限制'));
  });

  test('有附件 400/415/422 返回视觉文案', () {
    for (final statusCode in [400, 415, 422]) {
      final message = aiVisualAttachmentError(
        statusCode: statusCode,
        hasAttachments: true,
      );
      expect(message, contains('不支持图片输入'), reason: '状态码 $statusCode');
      expect(message, contains('HTTP $statusCode'), reason: '状态码 $statusCode');
    }
  });

  test('有附件 401/403/404/500 返回 null', () {
    for (final statusCode in [401, 403, 404, 500]) {
      expect(
        aiVisualAttachmentError(
          statusCode: statusCode,
          hasAttachments: true,
        ),
        isNull,
        reason: '状态码 $statusCode 不应误报为视觉问题',
      );
    }
  });
}
