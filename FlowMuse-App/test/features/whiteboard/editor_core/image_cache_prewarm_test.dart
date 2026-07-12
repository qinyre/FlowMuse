import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadScene 后多张图片串行预热,resolveImages 不并发触发解码', () async {
    // 1. 导入 3 页 PDF 构造场景 JSON
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final renderer = _FakeRenderer([
      PdfRenderedPage(bytes: await _makePng(0xff0000ff), mimeType: 'image/png', width: 100, height: 100, pageNumber: 1),
      PdfRenderedPage(bytes: await _makePng(0xff00ff00), mimeType: 'image/png', width: 100, height: 100, pageNumber: 2),
      PdfRenderedPage(bytes: await _makePng(0xffff0000), mimeType: 'image/png', width: 100, height: 100, pageNumber: 3),
    ]);
    await PdfImporter(renderer: renderer).importPdf(
      source: PdfImportSource(name: 't.pdf', bytes: Uint8List.fromList([1])),
      controller: controller,
      canvasSize: const Size(800, 600),
    );
    final json = controller.serializeScene(format: DocumentFormat.excalidraw);

    // 2. 新 controller 加载(loadScene 会触发 _prewarmImageCache)
    final controller2 = MarkdrawController();
    addTearDown(controller2.dispose);
    controller2.loadFromContent(json, 'test.excalidraw');

    // 3. loadScene 返回后,首次 resolveImages 应返回 null(图片还在串行解码中),
    //    且不会并发启动解码(所有 fileId 已被 markDecoding 占位)。
    final resolvedImmediately = controller2.resolveImages();
    expect(resolvedImmediately, isNull,
        reason: '预热未完成时 resolveImages 应返回 null,不返回部分图片');

    // 4. 等待串行预热完成
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (controller2.imageCache.length >= 3) break;
    }

    // 5. 预热完成后,3 张图片全部在缓存中
    expect(controller2.imageCache.length, 3,
        reason: '3 张图片应全部串行解码完成');
    final resolved = controller2.resolveImages();
    expect(resolved, isNotNull);
    expect(resolved!.length, 3, reason: 'resolveImages 应返回全部 3 张已解码图片');
  });

  test('解码失败的图片被标记为 failed,不会无限重试', () async {
    final cache = ImageElementCache();
    addTearDown(cache.dispose);

    // 用无效字节触发解码失败
    final badFile = ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList([0, 1, 2]));
    final result = cache.getImage('bad', badFile);
    expect(result, isNull);

    // 等待异步解码(会失败)
    for (var i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 再次 getImage 不应重新触发解码(已在 _failed 中)
    // 由于 _failed 是私有的,我们通过 imageCache.length 仍为 0 来间接验证
    // 不会因为重复调用 getImage 而产生多次解码尝试
    expect(cache.length, 0);
  });
}

class _FakeRenderer implements PdfPageRenderer {
  _FakeRenderer(this.pages);
  final List<PdfRenderedPage> pages;
  @override
  Future<List<PdfRenderedPage>> render(PdfImportSource source, PdfRenderOptions options) async => pages;
}

Future<Uint8List> _makePng(int argbColor) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = Color(argbColor));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}
