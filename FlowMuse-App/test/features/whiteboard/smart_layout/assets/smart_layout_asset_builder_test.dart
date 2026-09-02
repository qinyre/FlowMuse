import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

// dart:ui Rect 等类型在本文件直接以非限定名使用。
export 'dart:ui' show Rect, Offset;

import 'package:flow_muse/features/whiteboard/smart_layout/assets/smart_layout_asset_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/assets/smart_layout_render_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 合成页图：四象限纯色（左上红/右上绿/左下蓝/右下黄），
  /// crop 像素可精确预测。
  Future<ui.Image> quadrantPage(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    void fill(Rect rect, int color) => canvas.drawRect(
      rect,
      ui.Paint()
        ..color = ui.Color(color)
        ..style = ui.PaintingStyle.fill,
    );
    fill(Rect.fromLTWH(0, 0, width / 2, height / 2), 0xFFAA0000);
    fill(Rect.fromLTWH(width / 2, 0, width / 2, height / 2), 0xFF00AA00);
    fill(Rect.fromLTWH(0, height / 2, width / 2, height / 2), 0xFF0000AA);
    fill(
      Rect.fromLTWH(width / 2, height / 2, width / 2, height / 2),
      0xFFAAAA00,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  /// rawRgba codec：逐字节对拍用（避开 PNG 压缩器差异）。
  Future<ByteData> rawRgbaCodec(ui.Image image) => image
      .toByteData(format: ui.ImageByteFormat.rawRgba)
      .then((d) => d ?? (throw StateError('raw 编码返回空')));

  test(
    '成功构建：clean+annotated+crops，mark 只在 annotated，账本齐全',
    () async {
      final page = await quadrantPage(200, 200);
      addTearDown(page.dispose);
      final builder = SmartLayoutAssetBuilder(codec: rawRgbaCodec);
      final outcome = await builder.build(
        pageImage: page,
        transform: const PagePixelTransform(scale: 1),
        crops: [
          const AssetCropSpec(
            sourceKey: 'r1',
            pageRect: Rect.fromLTWH(10, 10, 50, 40),
          ),
          const AssetCropSpec(
            sourceKey: 'r2',
            pageRect: Rect.fromLTWH(120, 120, 60, 60),
          ),
        ],
        marks: [
          const AssetMarkSpec(
            markId: 'm1',
            label: 'm1',
            pageRect: Rect.fromLTWH(10, 10, 50, 40),
          ),
        ],
      );
      expect(outcome.succeeded, isTrue, reason: outcome.failureReason ?? '');
      final bundle = outcome.bundle!;
      expect(
        bundle.assets.keys,
        containsAll(['clean|page', 'annotated|page', 'crop|r1', 'crop|r2']),
      );
      expect(bundle.marks, hasLength(1));
      expect(bundle.marks.single.assetKey, 'annotated|page');
      expect(bundle.marks.single.label, 'm1');
      expect(
        bundle.marks.single.pixelRect,
        const Rect.fromLTWH(10, 10, 50, 40),
      );
      expect(bundle.assets['crop|r1']!.widthPx, 50);
      expect(builder.activeResourceCount, 0, reason: '成功路径活体资源必须归零');
      final clean = bundle.assets['clean|page']!;
      expect(
        clean.fingerprint,
        AssetFingerprint.of(
          kind: 'clean',
          sourceKey: 'page',
          rasterRect: const Rect.fromLTWH(0, 0, 200, 200),
          scale: 1,
          contentBytes: clean.bytes,
        ),
        reason: '指纹必须可由资产自身参数+内容重算',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'crop 内容=clean 源逐字节一致：标记绝不进入 OCR crop',
    () async {
      final page = await quadrantPage(200, 200);
      final builder = SmartLayoutAssetBuilder(codec: rawRgbaCodec);
      final outcome = await builder.build(
        pageImage: page,
        transform: const PagePixelTransform(scale: 1),
        crops: [
          const AssetCropSpec(
            sourceKey: 'r1',
            pageRect: Rect.fromLTWH(10, 10, 50, 40),
          ),
        ],
        marks: [
          const AssetMarkSpec(
            markId: 'm1',
            label: 'm1',
            pageRect: Rect.fromLTWH(10, 10, 50, 40),
          ),
        ],
      );
      // 期望：直接从同一页图独立裁剪（不经 builder）。
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        page,
        const Rect.fromLTWH(10, 10, 50, 40),
        const Rect.fromLTWH(0, 0, 50, 40),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final expected = await recorder.endRecording().toImage(50, 40);
      final expectedBytes = await expected.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expected.dispose();

      final crop = outcome.bundle!.assets['crop|r1']!;
      expect(crop.bytes.length, expectedBytes!.lengthInBytes);
      for (var i = 0; i < expectedBytes.lengthInBytes; i++) {
        if (crop.bytes[i] != expectedBytes.getUint8(i)) {
          fail('crop 第 $i 字节与 clean 源不一致——标记泄漏进 OCR crop');
        }
      }
      expect(builder.activeResourceCount, 0);
      page.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('page↔pixel 变换：往返一致、DPR=2 正确、栅格取整半开区间', () {
    const transform = PagePixelTransform(scale: 2, offsetX: 10, offsetY: 20);
    const pageRect = Rect.fromLTWH(5, 8, 30, 40);
    final pixel = transform.pageRectToPixel(pageRect);
    expect(pixel, const Rect.fromLTWH(30, 56, 60, 80));
    expect(transform.pixelRectToPage(pixel), pageRect);
    final raster = transform.pixelRectToRaster(
      const Rect.fromLTWH(0.2, 0.8, 10.3, 20.9),
    );
    // 右/下界 10.5/21.7 → ceil 为 11/22（半开区间）
    expect(raster, const Rect.fromLTWH(0, 0, 11, 22));
  });

  test('越界明确：crop/mark 超出页栅格返回确定性原因', () async {
    final page = await quadrantPage(100, 100);
    addTearDown(page.dispose);
    final builder = SmartLayoutAssetBuilder(codec: rawRgbaCodec);
    final outOfBounds = await builder.build(
      pageImage: page,
      transform: const PagePixelTransform(scale: 1),
      crops: [
        const AssetCropSpec(
          sourceKey: 'r1',
          pageRect: Rect.fromLTWH(80, 80, 50, 50),
        ),
      ],
      marks: const [],
    );
    expect(outOfBounds.failureReason, 'crop-out-of-bounds(r1)');
    final markOut = await builder.build(
      pageImage: page,
      transform: const PagePixelTransform(scale: 1),
      crops: const [],
      marks: [
        const AssetMarkSpec(
          markId: 'm9',
          label: 'm9',
          pageRect: Rect.fromLTWH(95, 95, 20, 20),
        ),
      ],
    );
    expect(markOut.failureReason, 'mark-out-of-bounds(m9)');
    expect(builder.activeResourceCount, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    '取消：构建前取消→failed(cancelled)，零资源零迟到写入',
    () async {
      final page = await quadrantPage(100, 100);
      addTearDown(page.dispose);
      final builder = SmartLayoutAssetBuilder(codec: rawRgbaCodec);
      final token = AssetBuildCancelToken()..cancel();
      final outcome = await builder.build(
        pageImage: page,
        transform: const PagePixelTransform(scale: 1),
        crops: const [
          AssetCropSpec(sourceKey: 'r1', pageRect: Rect.fromLTWH(0, 0, 10, 10)),
        ],
        marks: const [],
        cancelToken: token,
      );
      expect(outcome.succeeded, isFalse);
      expect(outcome.failureReason, 'cancelled');
      expect(builder.activeResourceCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'codec 故障注入：任一编码失败→整体 failed，资源归零无迟到写入',
    () async {
      final page = await quadrantPage(100, 100);
      addTearDown(page.dispose);
      var call = 0;
      Future<ByteData> failingCodec(ui.Image image) async {
        call++;
        if (call >= 2) throw StateError('codec exploded');
        return rawRgbaCodec(image);
      }

      final builder = SmartLayoutAssetBuilder(codec: failingCodec);
      final outcome = await builder.build(
        pageImage: page,
        transform: const PagePixelTransform(scale: 1),
        crops: [
          for (var i = 0; i < 6; i++)
            AssetCropSpec(
              sourceKey: 'c$i',
              pageRect: Rect.fromLTWH(10.0 + i, 10, 10, 10),
            ),
        ],
        marks: const [],
      );
      expect(outcome.succeeded, isFalse, reason: 'codec 失败必须整体失败');
      expect(outcome.failureReason, 'codec-failed');
      expect(builder.activeResourceCount, 0, reason: '失败路径活体资源必须归零');
      expect(outcome.bundle, isNull, reason: '失败后不得再产出部分资产包');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('指纹：相同输入稳定，内容/几何/sourceKey 任一变化即变', () {
    final fp1 = AssetFingerprint.of(
      kind: 'crop',
      sourceKey: 'r1',
      rasterRect: const Rect.fromLTWH(0, 0, 10, 10),
      scale: 1,
      contentBytes: [1, 2, 3],
    );
    final fp2 = AssetFingerprint.of(
      kind: 'crop',
      sourceKey: 'r1',
      rasterRect: const Rect.fromLTWH(0, 0, 10, 10),
      scale: 1,
      contentBytes: [1, 2, 3],
    );
    expect(fp1, fp2);
    expect(
      AssetFingerprint.of(
        kind: 'crop',
        sourceKey: 'r1',
        rasterRect: const Rect.fromLTWH(0, 0, 10, 10),
        scale: 1,
        contentBytes: [1, 2, 4],
      ),
      isNot(fp1),
    );
    expect(
      AssetFingerprint.of(
        kind: 'crop',
        sourceKey: 'other',
        rasterRect: const Rect.fromLTWH(0, 0, 10, 10),
        scale: 1,
        contentBytes: [1, 2, 3],
      ),
      isNot(fp1),
    );
    expect(
      AssetFingerprint.of(
        kind: 'clean',
        sourceKey: 'r1',
        rasterRect: const Rect.fromLTWH(0, 0, 10, 10),
        scale: 1,
        contentBytes: [1, 2, 3],
      ),
      isNot(fp1),
    );
  });
}
