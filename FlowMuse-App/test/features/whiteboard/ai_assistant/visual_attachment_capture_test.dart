import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/visual_attachment_capture.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// visual_attachment_capture 测试（§3.4 用例表 + 融合修订）。
///
/// 图像相关路径（toImage/codec/toByteData 走真异步渲染管线）一律用普通
/// test()——fake-async 的 testWidgets 区内永不完成（与 export_region_png
/// 测试同范式）。含图片的场景经 loadScene 构造时，自动预热是
/// fire-and-forget，与本模块"读 Scene.files 原始字节"的 PDF 路径无竞态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('已合规 PNG 原样返回（不重编码）', () async {
    // Given: 100×50 合成 PNG（≤byteLimit）
    final input = await _solidPng(100, 50);

    // When: 归一化
    final output = await normalizeAttachmentPng(input);

    // Then: 同一对象原样返回（迁入自 buildAiVisualAttachment
    // 「小图保持原尺寸」用例：不重编码即保持像素与纯净性）
    expect(identical(input, output), isTrue);
  });

  test('超长边缩到 1568 且比例保持', () async {
    // Given: 2000×1000 合成 PNG
    final input = await _solidPng(2000, 1000);

    // When: 归一化
    final output = await normalizeAttachmentPng(input);

    // Then: 输出解码尺寸 1568×784（迁入自 buildAiVisualAttachment
    // 「超大长边按比例缩放到 1568 上限」用例）
    final (width, height) = await _pngDimensions(output);
    expect(width, 1568);
    expect(height, 784);
  });

  test('逐档降级最终收敛：输出达标或明确失败', () async {
    // Given: byteLimit 注入 2000，输入 2000×1000 高噪声 PNG（不可压缩）
    final input = await _noisePng(2000, 1000);

    // When: 归一化
    Uint8List? output;
    StateError? error;
    try {
      output = await normalizeAttachmentPng(input, byteLimit: 2000);
    } on StateError catch (failure) {
      error = failure;
    }

    // Then: 两分支皆合法，断言其一
    if (error != null) {
      expect(error.message, '图片过大，请缩小选区后重试');
    } else {
      expect(output, isNotNull);
      expect(output!.length, lessThanOrEqualTo(2000));
    }
  });

  test('768 档仍超限明确失败', () async {
    // Given: byteLimit 注入 1，输入任意合法 PNG
    // When/Then: 所有档位都无法压到 1 字节内 → 体积文案
    expect(
      () => normalizeAttachmentPng(basePng, byteLimit: 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '图片过大，请缩小选区后重试',
        ),
      ),
    );
  });

  test('无视觉选区返回 null、无消息（融合修订：不抛"请先选中"）', () async {
    // Given: controller 无任何选中
    final emptyController = MarkdrawController();
    addTearDown(emptyController.dispose);

    // When/Then: 返回 null 而非抛错（守卫语义：无可捕获视觉内容）
    expect(await captureSelectionAttachment(emptyController), isNull);

    // And: 纯文本选区同样返回 null——对已选中文本的用户，
    // "请先在画布选中要发送的内容"是错误指控（§1.6 文案集修订）
    final textOnlyController = MarkdrawController();
    addTearDown(textOnlyController.dispose);
    textOnlyController.applyResult(
      AddElementResult(
        TextElement(
          id: const ElementId('text-only-1'),
          x: 0,
          y: 0,
          width: 100,
          height: 30,
          text: '纯文本选区',
          fontFamily: 'Excalifont',
        ),
      ),
    );
    textOnlyController.applyResult(
      SetSelectionResult({const ElementId('text-only-1')}),
    );
    expect(await captureSelectionAttachment(textOnlyController), isNull);
  });

  test('场景无 PDF 背景元素报"当前笔记没有 PDF 页面"（双文案之一）', () async {
    // Given: 无限画布 controller（无页面、无 isPdfBackground 元素）
    final controller = MarkdrawController();
    addTearDown(controller.dispose);

    // When/Then: 融合修订 §4.1-7——双文案按场景元素判定
    expect(
      captureCurrentPdfPageAttachment(controller),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '当前笔记没有 PDF 页面',
        ),
      ),
    );
  });

  test('场景含 PDF 背景但视口不在页内报滚动引导文案', () async {
    // Given: 场景含 pdfBackground 元素，但唯一页面远离视口
    // （视口 (0,0,800,600)，页面在 y=5000 处）
    final controller = _pdfPageController(
      basePng,
      pageBounds: const Rect.fromLTWH(0, 5000, 800, 600),
    );

    // When/Then: 报"视口不在页内"文案。pageForVisibleRect 有 nearest
    // 回退、此处返回非 null 页，若依赖其 null 判定会漏判走通（R3-F3）
    expect(
      captureCurrentPdfPageAttachment(controller),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '当前视图不在 PDF 页面内，请先滚动到 PDF 页',
        ),
      ),
    );
  });

  test('视口在页内但无 PDF 背景元素报"当前页面不是 PDF 页"', () async {
    // Given: 单页 paged 布局（视口落在页内），场景无 isPdfBackground 元素
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setLayout(_singlePageLayout('p1'));

    // When/Then: 当前页不是 PDF 页
    expect(
      captureCurrentPdfPageAttachment(controller),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '当前页面不是 PDF 页',
        ),
      ),
    );
  });

  test('PDF 页附件成功且标签正确', () async {
    // Given: pdfBackground 元素 + Scene.files 注入 100×50 PNG + 单页布局
    final pagePng = await _solidPng(100, 50);
    final controller = _pdfPageController(pagePng);

    // When: 捕获当前 PDF 页
    final attachment = await captureCurrentPdfPageAttachment(controller);

    // Then: 标签、类型、字节合规
    expect(attachment, isNotNull);
    expect(attachment!.sourceLabel, 'PDF 第 1 页');
    expect(attachment.mimeType, 'image/png');
    expect(attachment.kind, AiVisualAttachmentKind.pdfPage);
    expect(attachment.bytes, isNotEmpty);
    expect(
      attachment.bytes.length,
      lessThanOrEqualTo(maxAiVisualAttachmentBytes),
    );
  });

  test('PDF 页附件字节通过结构化 chunk 扫描（PNG 纯净性）', () async {
    // Given: PDF 路径产物（Scene.files 原始字节，可被手工构造 .markdraw
    // 注入任意内容，须过模型层全量校验）
    final pagePng = await _solidPng(100, 50);
    final controller = _pdfPageController(pagePng);
    final attachment = await captureCurrentPdfPageAttachment(controller);

    // When/Then: 模型层校验（数量→mime→魔数→长度→结构化 chunk 扫描）
    // 原样通过
    expect(requireValidAiVisualAttachments([attachment!]), hasLength(1));

    // And: 手写 chunk 解析确认无 tEXt/iTXt/zTXt 元数据
    final chunkTypes = _pngChunkTypes(attachment.bytes);
    expect(chunkTypes, contains('IHDR'), reason: '解析器应至少读到 IHDR');
    expect(chunkTypes, isNot(contains('tEXt')));
    expect(chunkTypes, isNot(contains('iTXt')));
    expect(chunkTypes, isNot(contains('zTXt')));
  });

  test('选区截图成功', () async {
    // Given: controller 含非文本元素（矩形）并选中
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('shape-1'),
          x: 0,
          y: 0,
          width: 120,
          height: 80,
          strokeColor: '#000000',
          backgroundColor: '#000000',
        ),
      ),
    );
    controller.applyResult(
      SetSelectionResult({const ElementId('shape-1')}),
    );

    // When: 捕获选区
    final attachment = await captureSelectionAttachment(controller);

    // Then: 返回合法附件（守卫要求非文本元素，纯文本选区在上一用例覆盖）
    expect(attachment, isNotNull);
    expect(attachment!.sourceLabel, '选区截图');
    expect(attachment.mimeType, 'image/png');
    expect(attachment.kind, AiVisualAttachmentKind.selection);
    expect(attachment.bytes, isNotEmpty);
    expect(
      attachment.bytes.length,
      lessThanOrEqualTo(maxAiVisualAttachmentBytes),
    );
    expect(requireValidAiVisualAttachments([attachment]), hasLength(1));
  });

  test('损坏 PNG 归一化失败消息稳定', () async {
    // Given: 非 PNG 随机字节
    final broken = Uint8List.fromList([
      for (var i = 0; i < 32; i++) i,
    ]);

    // When/Then: _pngDimensions 兜底转换，不泄漏底层异常（迁入自
    // buildAiVisualAttachment「非法字节」用例——新契约下由降级 null 改为
    // 可行动文案）
    expect(
      () => normalizeAttachmentPng(broken),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '图片处理失败，请重试',
        ),
      ),
    );
  });

  test('PDF 背景元素指向非 PNG 文件被拒', () async {
    // Given: pdfBackground 元素 + Scene.files 注入 mimeType='image/jpeg'
    // 的 file + 单页 paged 布局
    final controller = _pdfPageController(
      basePng,
      fileMimeType: 'image/jpeg',
    );

    // When/Then: mime 白名单把关
    expect(
      captureCurrentPdfPageAttachment(controller),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '当前页面不是 PDF 页',
        ),
      ),
    );
  });

  test('超大维度 PNG 被拒（解压炸弹护栏）', () async {
    // Given: 基准 1×1 PNG，maxPixelCount 注入 0（避免真实构造超大图）
    // When/Then: 维度护栏先于解码触发
    expect(
      () => normalizeAttachmentPng(basePng, maxPixelCount: 0),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '图片过大，请缩小选区后重试',
        ),
      ),
    );
  });
}

/// 1×1 基准 PNG（IHDR + IDAT + IEND，无文本 chunk、IEND 后无残余字节）。
final Uint8List basePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

/// 构造"PDF 页"场景：pdfBackground 元素 + Scene.files 页图 + 单页布局。
///
/// [pageBounds] 默认与测试视口（(0,0,800,600)，canvasSize 兜底值）重合；
/// 挪远即得"视口不在页内"的场景。
MarkdrawController _pdfPageController(
  Uint8List pagePng, {
  String fileMimeType = 'image/png',
  Rect pageBounds = const Rect.fromLTWH(0, 0, 800, 600),
}) {
  final controller = MarkdrawController();
  addTearDown(controller.dispose);
  controller.loadScene(
    Scene()
        .addFile('pdf-1', ImageFile(mimeType: fileMimeType, bytes: pagePng))
        .addElement(
          ImageElement(
            id: const ElementId('pdf-elem-1'),
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            fileId: 'pdf-1',
            customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
          ),
        ),
  );
  controller.setLayout(
    CanvasLayout(
      type: CanvasLayoutType.paged,
      pages: [
        CanvasPage(
          id: 'page-1',
          index: 0,
          bounds: pageBounds,
          template: CanvasPageTemplate.blank,
        ),
      ],
    ),
  );
  return controller;
}

CanvasLayout _singlePageLayout(String pageId) => CanvasLayout(
  type: CanvasLayoutType.paged,
  pages: [
    CanvasPage(
      id: pageId,
      index: 0,
      bounds: const Rect.fromLTWH(0, 0, 800, 600),
      template: CanvasPageTemplate.blank,
    ),
  ],
);

/// 用 PictureRecorder 合成指定尺寸的纯色 PNG。
Future<Uint8List> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 合成指定尺寸的高噪声 PNG（随机像素，不可压缩），用于体积档位测试。
Future<Uint8List> _noisePng(int width, int height) async {
  final random = math.Random(7);
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = random.nextInt(256);
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  // ImageDescriptor.raw 是同步工厂（本 Flutter 版本签名）。
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  try {
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

/// 只读 PNG 头部尺寸，不解码像素。
Future<(int, int)> _pngDimensions(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return (descriptor.width, descriptor.height);
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

/// 手写 PNG chunk 类型解析：跳过 8 字节签名，循环读 4B 长度 + 4B 类型。
List<String> _pngChunkTypes(Uint8List bytes) {
  final types = <String>[];
  final data = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    types.add(type);
    offset += 12 + length;
    if (type == 'IEND') break;
  }
  return types;
}
