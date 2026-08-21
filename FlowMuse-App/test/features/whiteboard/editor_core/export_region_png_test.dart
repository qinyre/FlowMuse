import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// exportRegionPng/prewarmRegionImages 测试。
///
/// 图像渲染相关用例（toImage/codec/toByteData 走真异步渲染管线）一律用
/// 普通 test()——fake-async 的 testWidgets 区内永不完成。需要"未缓存"
/// 图片的用例一律经 applyResult(AddFileResult/AddElementResult) 注入，
/// 不得用 loadScene 构造：loadScene 会 fire-and-forget 触发全量预热，
/// 与被测的 prewarmRegionImages 竞态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('基本导出:非空、PNG 签名、最长边不超过 1568', () async {
    // Given: 场景含 1 个文本元素 (0,0,100,50)（用内置字体，避免
    // google_fonts 在测试环境发起网络加载）
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 0,
          width: 100,
          height: 50,
          text: 'FlowMuse',
          fontFamily: 'Excalifont',
        ),
      ),
    );

    // When: 导出该区域
    final bytes = await controller.exportRegionPng(
      const Rect.fromLTWH(0, 0, 100, 50),
    );

    // Then: 非 null、PNG 8 字节签名、解码后最长边 ≤1568
    expect(bytes, isNotNull);
    expect(
      bytes!.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: '输出应为 PNG 格式',
    );
    final image = await _decodePng(bytes);
    addTearDown(image.dispose);
    expect(math.max(image.width, image.height), lessThanOrEqualTo(1568));
  });

  test('宽高比保持:200×100 选区输出宽高比约 2.0', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 0,
          width: 200,
          height: 100,
          text: 'FlowMuse',
          fontFamily: 'Excalifont',
        ),
      ),
    );

    final bytes = await controller.exportRegionPng(
      const Rect.fromLTWH(0, 0, 200, 100),
    );

    final image = await _decodePng(bytes!);
    addTearDown(image.dispose);
    expect((image.width / image.height - 2.0).abs(), lessThan(0.02));
  });

  test('小选区矢量高清:20×20 选区输出 1568×1568', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 0,
          width: 20,
          height: 20,
          text: 'A',
          fontFamily: 'Excalifont',
        ),
      ),
    );

    // zoom>1 是矢量重渲，非位图放大
    final bytes = await controller.exportRegionPng(
      const Rect.fromLTWH(0, 0, 20, 20),
    );

    final image = await _decodePng(bytes!);
    addTearDown(image.dispose);
    expect(image.width, 1568);
    expect(image.height, 1568);
  });

  test('输出 PNG 无 tEXt/iTXt/zTXt 元数据 chunk', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 0,
          width: 100,
          height: 50,
          text: 'FlowMuse',
          fontFamily: 'Excalifont',
        ),
      ),
    );

    final bytes = await controller.exportRegionPng(
      const Rect.fromLTWH(0, 0, 100, 50),
    );

    // 手写 chunk 解析器:跳过 8 字节签名,循环读 length+type
    final chunkTypes = _pngChunkTypes(bytes!);
    expect(chunkTypes, contains('IHDR'), reason: '解析器应至少读到 IHDR');
    expect(chunkTypes, isNot(contains('tEXt')));
    expect(chunkTypes, isNot(contains('iTXt')));
    expect(chunkTypes, isNot(contains('zTXt')));
  });

  test('预热后图片元素真实渲染:预热前后字节不同,预热后中心像素为红色', () async {
    // Given: 经 applyResult 注入 ImageElement+file（200×200 纯红 PNG，
    // 测试内合成），不经 loadScene（避免自动预热竞态）
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final redPng = await _makePng(200, 200, 0xFFFF0000);
    controller.applyResult(
      AddFileResult(
        fileId: 'img-1',
        file: ImageFile(mimeType: 'image/png', bytes: redPng),
      ),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('elem-1'),
          x: 0,
          y: 0,
          width: 200,
          height: 200,
          fileId: 'img-1',
          mimeType: 'image/png',
        ),
      ),
    );
    const rect = Rect.fromLTWH(0, 0, 200, 200);

    // When: 未预热导出 bytesA;预热返回 0 后导出 bytesB
    final bytesBeforePrewarm = await controller.exportRegionPng(rect);
    final failed = await controller.prewarmRegionImages(rect);
    final bytesAfterPrewarm = await controller.exportRegionPng(rect);

    // Then: 占位图 vs 真图字节不同,且 bytesB 中心像素为红色
    expect(failed, 0);
    expect(bytesBeforePrewarm, isNotNull);
    expect(bytesAfterPrewarm, isNotNull);
    final bytesA = bytesBeforePrewarm!;
    final bytesB = bytesAfterPrewarm!;
    expect(listEquals(bytesA, bytesB), isFalse,
        reason: '未预热时渲染占位图,预热后应渲染真实图片');
    final image = await _decodePng(bytesB);
    addTearDown(image.dispose);
    final (r, g, b) = await _pixelAt(image, image.width ~/ 2, image.height ~/ 2);
    expect(r, greaterThan(200), reason: '中心像素应为红色 R 分量');
    expect(g, lessThan(60), reason: '中心像素应为红色 G 分量');
    expect(b, lessThan(60), reason: '中心像素应为红色 B 分量');
  });

  test('预热报告解码失败数:损坏 bytes 的图片返回 1', () async {
    // Given: 经 applyResult 注入指向损坏 bytes 的 ImageElement
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(
      AddFileResult(
        fileId: 'bad-1',
        file: ImageFile(
          mimeType: 'image/png',
          bytes: Uint8List.fromList([0, 1, 2, 3]),
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('elem-bad'),
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          fileId: 'bad-1',
          mimeType: 'image/png',
        ),
      ),
    );

    // When/Then: 相交图片解码失败,失败计数为 1
    final failed = await controller.prewarmRegionImages(
      const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(failed, 1);
  });

  test('分页模式裁剪到页并集:页并集之外的采样像素为背景色', () async {
    // Given: 两页 paged 布局 + 一个页外元素 + 红色画布背景
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(Scene());
    controller.setLayout(
      const CanvasLayout(
        type: CanvasLayoutType.paged,
        pages: [
          CanvasPage(
            id: 'p1',
            index: 0,
            bounds: Rect.fromLTWH(0, 0, 800, 600),
            template: CanvasPageTemplate.blank,
          ),
          CanvasPage(
            id: 'p2',
            index: 1,
            bounds: Rect.fromLTWH(0, 700, 800, 600),
            template: CanvasPageTemplate.blank,
          ),
        ],
      ),
    );
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('outside-1'),
          x: 1000,
          y: 100,
          width: 200,
          height: 200,
          strokeColor: '#000000',
          backgroundColor: '#000000',
        ),
      ),
    );
    controller.canvasBackgroundColor = '#ff0000';

    // When: 导出横跨页并集内外的矩形（x∈[-200,1400]，页并集 x∈[0,800]）
    const rect = Rect.fromLTWH(-200, -100, 1600, 1500);
    final bytes = await controller.exportRegionPng(rect);
    expect(bytes, isNotNull);

    // Then: 页并集之外（左侧、页外元素处、页间隙）均为背景红色，
    // 页内为页面纸色（非红）——证明渲染被裁剪到页并集
    final image = await _decodePng(bytes!);
    addTearDown(image.dispose);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);
    const zoom = 1568.0 / 1600.0;
    (int, int, int) pixelAtScene(double sx, double sy) {
      final px = ((sx - rect.left) * zoom).round();
      final py = ((sy - rect.top) * zoom).round();
      return _extractPixel(rgba!, image.width, px, py);
    }

    final backgroundSample = pixelAtScene(-100, 300);
    _expectRed(backgroundSample, '页并集左侧应为背景色');
    final outsideElementSample = pixelAtScene(1100, 200);
    _expectRed(outsideElementSample, '页外元素应被裁剪,采样应为背景色');
    final pageGapSample = pixelAtScene(400, 650);
    _expectRed(pageGapSample, '两页间隙不属于页并集,应为背景色');

    final insidePageSample = pixelAtScene(400, 300);
    expect(insidePageSample.$2, greaterThan(200),
        reason: '页内应为页面纸色（米白），绿色分量不是背景红色的 0');
    expect(insidePageSample.$3, greaterThan(200),
        reason: '页内应为页面纸色（米白），蓝色分量不是背景红色的 0');
  });

  test('零尺寸/负尺寸返回 null', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);

    expect(
      await controller.exportRegionPng(const Rect.fromLTWH(0, 0, 0, 10)),
      isNull,
      reason: '零宽返回 null',
    );
    expect(
      await controller.exportRegionPng(const Rect.fromLTWH(0, 0, -5, 10)),
      isNull,
      reason: '负宽返回 null',
    );
    expect(
      await controller.exportRegionPng(const Rect.fromLTWH(0, 0, 10, -1)),
      isNull,
      reason: '负高返回 null',
    );
  });

  test('预热期间无解码完成回调风暴,结束后恢复回调且单次刷新', () async {
    // Given: loadScene 空场景后经 applyResult 注入 3 个未缓存相交图片
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(Scene());
    for (var i = 0; i < 3; i++) {
      final png = await _makePng(4, 4, 0xFF00FF00);
      controller.applyResult(
        AddFileResult(
          fileId: 'img-$i',
          file: ImageFile(mimeType: 'image/png', bytes: png),
        ),
      );
      controller.applyResult(
        AddElementResult(
          ImageElement(
            id: ElementId('elem-$i'),
            x: 0,
            y: i * 10.0,
            width: 40,
            height: 40,
            fileId: 'img-$i',
            mimeType: 'image/png',
          ),
        ),
      );
    }
    const rect = Rect.fromLTWH(0, 0, 100, 100);
    var decodedCallbacks = 0;
    void countingCallback() => decodedCallbacks++;
    controller.imageCache.onImageDecoded = countingCallback;
    var repaints = 0;
    void repaintCounter() => repaints++;
    controller.addListener(repaintCounter);
    addTearDown(() => controller.removeListener(repaintCounter));

    // When: 预热相交区域
    final failed = await controller.prewarmRegionImages(rect);

    // Then: 期间解码完成回调不增加（被暂停）、恢复预热前的回调、重绘恰好 +1
    expect(failed, 0);
    expect(controller.imageCache.length, 3, reason: '3 张图片应全部入缓存');
    expect(decodedCallbacks, 0, reason: '预热期间 onImageDecoded 应被暂停');
    expect(
      identical(controller.imageCache.onImageDecoded, countingCallback),
      isTrue,
      reason: '预热结束后应恢复预热开始前的回调',
    );
    expect(repaints, 1, reason: '预热结束后仅单次 notifyListeners');
  });

  test('loadScene 预热与 prewarmRegionImages 交错同一 fileId 不双解', () async {
    // Given: 经 applyResult 注入未缓存图片（fileId: img-x）
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final png = await _makePng(8, 8, 0xFF0000FF);
    final file = ImageFile(mimeType: 'image/png', bytes: png);
    controller.applyResult(AddFileResult(fileId: 'img-x', file: file));
    controller.applyResult(
      AddElementResult(
        ImageElement(
          id: const ElementId('elem-x'),
          x: 0,
          y: 0,
          width: 40,
          height: 40,
          fileId: 'img-x',
          mimeType: 'image/png',
        ),
      ),
    );
    const rect = Rect.fromLTWH(0, 0, 100, 100);

    // When: prewarmRegionImages 先启动（占位+在途），loadScene 的全量预热
    // 在其在途期间交错启动同一 fileId
    final prewarmFuture = controller.prewarmRegionImages(rect);
    controller.loadScene(
      Scene()
          .addFile('img-x', file)
          .addElement(
            ImageElement(
              id: const ElementId('elem-x'),
              x: 0,
              y: 0,
              width: 40,
              height: 40,
              fileId: 'img-x',
              mimeType: 'image/png',
            ),
          ),
    );
    final failed = await prewarmFuture;
    final imageAfterPrewarm = controller.imageCache.peek('img-x');

    // 排空事件循环，让 loadScene 的 fire-and-forget 预热
    // （以及任何可能的第二次解码）完成
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final imageAfterSettle = controller.imageCache.peek('img-x');

    // Then: 缓存条目恰为 1，双方 peek 得同一 ui.Image 实例
    expect(failed, 0);
    expect(controller.imageCache.length, 1,
        reason: '同一 fileId 只应解码一次入缓存');
    expect(imageAfterPrewarm, isNotNull);
    expect(imageAfterSettle, isNotNull);
    expect(
      identical(imageAfterPrewarm, imageAfterSettle),
      isTrue,
      reason: '双方应共享同一解码实例，双解会覆盖为不同实例',
    );
  });

  test('LRU 逐出后被逐出 id 经 getImage 能重新解码', () async {
    // Given: maxSize=2 的缓存，先解码 a、b 后对含已缓存 id 的集合 markDecoding
    final cache = ImageElementCache(maxSize: 2);
    addTearDown(cache.dispose);
    final fileA = ImageFile(mimeType: 'image/png', bytes: await _makePng(2, 2, 0xFF0000FF));
    final fileB = ImageFile(mimeType: 'image/png', bytes: await _makePng(2, 2, 0xFF00FF00));
    final fileC = ImageFile(mimeType: 'image/png', bytes: await _makePng(2, 2, 0xFFFF0000));
    await cache.decodeAndWait('a', fileA);
    await cache.decodeAndWait('b', fileB);

    // markDecoding 前置条件：已缓存 id 不插占位（否则逐出后 getImage 见
    // 占位返回 null，图片永久空白），仅在途条目不被覆盖
    cache.markDecoding(['a', 'b', 'c']);
    await cache.decodeAndWait('c', fileC);

    // When: a 被 LRU 逐出后再次 getImage
    expect(cache.length, 2);
    expect(cache.contains('a'), isFalse, reason: 'maxSize=2 时 a 已被逐出');
    expect(cache.getImage('a', fileA), isNull,
        reason: '重新解码是异步的，首次 getImage 返回 null');
    for (var i = 0; i < 100 && !cache.contains('a'); i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // Then: 被逐出 id 能重新解码入缓存
    expect(cache.contains('a'), isTrue,
        reason: '被逐出的 id 经 getImage 应能重新解码');
    expect(cache.peek('a'), isNotNull);
  });
}

/// 用 PictureRecorder 合成指定尺寸的纯色 PNG。
Future<Uint8List> _makePng(int width, int height, int color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color(color),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// 读取图片 (x, y) 处的 RGB 像素。
Future<(int, int, int)> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _extractPixel(data!, image.width, x, y);
}

(int, int, int) _extractPixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return (
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void _expectRed((int, int, int) pixel, String reason) {
  expect(pixel.$1, greaterThan(200), reason: '$reason（R 分量）');
  expect(pixel.$2, lessThan(60), reason: '$reason（G 分量）');
  expect(pixel.$3, lessThan(60), reason: '$reason（B 分量）');
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
