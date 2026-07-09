import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/export/svg_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 透明 PNG 的最小合法字节。
const _pngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  test('exported SVG is well-formed and renders key elements', () {
    final scene = Scene()
        .addElement(
          RectangleElement(
            id: ElementId('rect-1'),
            x: 0,
            y: 0,
            width: 100,
            height: 80,
            strokeColor: '#000000',
            backgroundColor: '#FF0000',
          ),
        )
        .addElement(
          ImageElement(
            id: ElementId('img-1'),
            x: 200,
            y: 0,
            width: 400,
            height: 600,
            fileId: 'file-1',
            mimeType: 'image/png',
          ),
        )
        .addElement(
          TextElement(
            id: ElementId('text-1'),
            x: 0,
            y: 700,
            width: 100,
            height: 30,
            text: 'Hello',
            fontSize: 24,
            strokeColor: '#000000',
          ),
        )
        .addFile(
          'file-1',
          ImageFile(
            mimeType: 'image/png',
            bytes: Uint8List.fromList(_pngBytes),
          ),
        );

    final svg = SvgExporter.export(scene, embedMarkdraw: false);

    // 打印完整 SVG 供人工审查
    // ignore: avoid_print
    print(
      '===== GENERATED SVG START =====\n$svg\n===== GENERATED SVG END =====',
    );

    // 1. 必须有 XML 声明（安卓内容嗅探需要）
    expect(svg.startsWith('<?xml'), true, reason: '缺 XML 声明头');

    // 2. 必须有 SVG 根标签带命名空间
    expect(
      svg.contains('<svg xmlns="http://www.w3.org/2000/svg"'),
      true,
      reason: '缺 SVG 命名空间',
    );

    // 3. 必须以 </svg> 结尾（结构完整）
    expect(svg.trim().endsWith('</svg>'), true, reason: 'SVG 未正确闭合');

    // 4. 标签数量必须平衡（粗略的结构完整性检查）
    final openTags = RegExp(r'<([a-zA-Z][a-zA-Z0-9]*)(\s|>)').allMatches(svg);
    final closeTags = RegExp(r'</([a-zA-Z][a-zA-Z0-9]*)>').allMatches(svg);
    final selfClosing = RegExp(r'/>').allMatches(svg);
    // openTags 含自闭合（它们也有 />）。计算逻辑：每个非自闭合开标签应有对应闭标签。
    final nonSelfClosingOpens = openTags.length - selfClosing.length;
    expect(
      nonSelfClosingOpens,
      closeTags.length,
      reason: '开闭标签不平衡: 开=$nonSelfClosingOpens 闭=${closeTags.length}',
    );

    // 5. image 元素必须同时有 href 和 xlink:href（跨平台兼容）
    expect(
      svg.contains('href="data:image/png;base64,'),
      true,
      reason: 'image 缺 href',
    );
    expect(
      svg.contains('xlink:href="data:image/png;base64,'),
      true,
      reason: 'image 缺 xlink:href',
    );

    // 6. data URI 必须是有效的 base64
    final dataUriMatch = RegExp(
      r'href="(data:image/png;base64,([A-Za-z0-9+/=]+))"',
    ).firstMatch(svg);
    expect(dataUriMatch, isNotNull, reason: '无法提取 image data URI');
    final b64 = dataUriMatch!.group(2)!;
    final decoded = base64Decode(b64);
    expect(decoded.length, _pngBytes.length, reason: 'base64 解码后长度不符');
  });
}
