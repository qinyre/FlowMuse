import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'smart_layout_render_assets.dart';

/// 取消令牌：与 HTTP 令牌同语义（协作式、幂等）。
class AssetBuildCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 资产编码器：图像 → 字节。默认 PNG；测试注入失败/原始像素 codec
/// 做故障注入与逐字节对拍。
typedef AssetByteCodec = Future<ByteData> Function(ui.Image image);

Future<ByteData> _defaultPngCodec(ui.Image image) => image
    .toByteData(format: ui.ImageByteFormat.png)
    .then((data) => data ?? (throw StateError('PNG 编码返回空')));

/// 裁剪规格：page 坐标区域 + 可追踪 sourceKey（regionId 等）。
class AssetCropSpec {
  const AssetCropSpec({required this.sourceKey, required this.pageRect});

  final String sourceKey;
  final ui.Rect pageRect;
}

/// mark 规格：page 坐标徽章框 + 稳定编号 label（如 "m1"）。
class AssetMarkSpec {
  const AssetMarkSpec({
    required this.markId,
    required this.label,
    required this.pageRect,
  });

  final String markId;
  final String label;
  final ui.Rect pageRect;
}

/// 构建结果：成功给资产包；失败给确定性原因；两者互斥。
class AssetBuildOutcome {
  const AssetBuildOutcome._(this.bundle, this.failureReason);

  const AssetBuildOutcome.failed(String reason) : this._(null, reason);

  const AssetBuildOutcome.succeeded(SmartLayoutRenderAssets bundle)
    : this._(bundle, null);

  final SmartLayoutRenderAssets? bundle;
  final String? failureReason;

  bool get succeeded => bundle != null;
}

/// clean/annotated/crop 资产构建器（V3-105A）。
///
/// - clean：调用方提供的整页干净栅格（builder 不持有、不释放）；
/// - annotated：在整页副本上画 mark 徽章（编号账本同时产出）；
/// - crop：只从 clean 源裁剪——标记按构造不进 OCR crop；
/// - 并发：有界并行（[maxConcurrency]），结果按 key 排序组装；
/// - 取消/失败：任一步失败即整体失败，全部中间图像在 finally 释放，
///   失败/取消后不再有任何写入（迟到续作在写入前二次检查令牌）。
class SmartLayoutAssetBuilder {
  SmartLayoutAssetBuilder({
    AssetByteCodec codec = _defaultPngCodec,
    int maxConcurrency = 4,
  }) : assert(maxConcurrency > 0),
       _codec = codec,
       _maxConcurrency = maxConcurrency;

  final AssetByteCodec _codec;
  final int _maxConcurrency;

  int _activeResources = 0;

  /// 当前由 builder 持有的活体图像计数（测试释放断言依据；
  /// 任何返回路径都必须归零）。
  int get activeResourceCount => _activeResources;

  Future<AssetBuildOutcome> build({
    required ui.Image pageImage,
    required PagePixelTransform transform,
    required List<AssetCropSpec> crops,
    required List<AssetMarkSpec> marks,
    AssetBuildCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return const AssetBuildOutcome.failed('cancelled');
    }
    if (pageImage.width <= 0 || pageImage.height <= 0) {
      return const AssetBuildOutcome.failed('invalid-page-image');
    }
    final pagePixelBounds = ui.Rect.fromLTWH(
      0,
      0,
      pageImage.width.toDouble(),
      pageImage.height.toDouble(),
    );
    bool fullyInside(ui.Rect rect) =>
        rect.left >= pagePixelBounds.left &&
        rect.top >= pagePixelBounds.top &&
        rect.right <= pagePixelBounds.right &&
        rect.bottom <= pagePixelBounds.bottom;

    // 越界明确：crop/mark 的像素矩形必须完全落在页栅格内。
    for (final crop in crops) {
      final raster = transform.pixelRectToRaster(
        transform.pageRectToPixel(crop.pageRect),
      );
      if (!fullyInside(raster) || raster.width < 1 || raster.height < 1) {
        return AssetBuildOutcome.failed(
          'crop-out-of-bounds(${crop.sourceKey})',
        );
      }
    }
    for (final mark in marks) {
      final raster = transform.pixelRectToRaster(
        transform.pageRectToPixel(mark.pageRect),
      );
      if (!fullyInside(raster)) {
        return AssetBuildOutcome.failed('mark-out-of-bounds(${mark.markId})');
      }
    }

    final assets = <String, SmartLayoutRenderAsset>{};
    final markLedger = <SmartLayoutMarkLedgerEntry>[];
    try {
      // 1. clean 整页资产。
      final cleanBytes = await _encode(pageImage);
      if (_isCancelled(cancelToken)) {
        return const AssetBuildOutcome.failed('cancelled');
      }
      final cleanKey = 'clean|page';
      assets[cleanKey] = SmartLayoutRenderAsset(
        key: cleanKey,
        kind: SmartLayoutAssetKind.clean,
        sourceKey: 'page',
        widthPx: pageImage.width,
        heightPx: pageImage.height,
        bytes: cleanBytes.buffer.asUint8List(
          cleanBytes.offsetInBytes,
          cleanBytes.lengthInBytes,
        ),
        fingerprint: AssetFingerprint.of(
          kind: 'clean',
          sourceKey: 'page',
          rasterRect: ui.Rect.fromLTWH(
            0,
            0,
            pageImage.width.toDouble(),
            pageImage.height.toDouble(),
          ),
          scale: transform.scale,
          contentBytes: cleanBytes.buffer.asUint8List(
            cleanBytes.offsetInBytes,
            cleanBytes.lengthInBytes,
          ),
        ),
      );

      // 2. annotated 整页（画 mark 徽章）。
      if (marks.isNotEmpty) {
        final annotatedImage = await _renderAnnotated(
          pageImage,
          transform,
          marks,
          markLedger,
        );
        try {
          final bytes = await _encode(annotatedImage);
          if (_isCancelled(cancelToken)) {
            return const AssetBuildOutcome.failed('cancelled');
          }
          const annotatedKey = 'annotated|page';
          assets[annotatedKey] = SmartLayoutRenderAsset(
            key: annotatedKey,
            kind: SmartLayoutAssetKind.annotated,
            sourceKey: 'page',
            widthPx: annotatedImage.width,
            heightPx: annotatedImage.height,
            bytes: bytes.buffer.asUint8List(
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
            fingerprint: AssetFingerprint.of(
              kind: 'annotated',
              sourceKey: 'page',
              rasterRect: ui.Rect.fromLTWH(
                0,
                0,
                annotatedImage.width.toDouble(),
                annotatedImage.height.toDouble(),
              ),
              scale: transform.scale,
              contentBytes: bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ),
          );
        } finally {
          _dispose(annotatedImage);
        }
      }

      // 3. crops：有界并行，全部从 clean 源裁剪。
      final cropResults = await _mapBounded(
        crops,
        (crop) => _buildCrop(pageImage, transform, crop),
        cancelToken,
      );
      if (cropResults == null) {
        return const AssetBuildOutcome.failed('cancelled');
      }
      for (final asset in cropResults) {
        if (_isCancelled(cancelToken)) {
          return const AssetBuildOutcome.failed('cancelled');
        }
        assets[asset.key] = asset;
      }

      return AssetBuildOutcome.succeeded(
        SmartLayoutRenderAssets(
          transform: transform,
          assets: Map.unmodifiable(assets),
          marks: List.unmodifiable(markLedger),
          pageWidthPx: pageImage.width,
          pageHeightPx: pageImage.height,
        ),
      );
    } on _AssetCodecException {
      return AssetBuildOutcome.failed('codec-failed');
    } catch (error) {
      return AssetBuildOutcome.failed('build-failed($error)');
    }
  }

  Future<ui.Image> _renderAnnotated(
    ui.Image pageImage,
    PagePixelTransform transform,
    List<AssetMarkSpec> marks,
    List<SmartLayoutMarkLedgerEntry> ledger,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(pageImage, ui.Offset.zero, ui.Paint());
    final textStyle = ui.TextStyle(
      color: const ui.Color(0xFF000000),
      fontSize: 12,
    );
    for (final mark in marks) {
      final pixel = transform.pixelRectToRaster(
        transform.pageRectToPixel(mark.pageRect),
      );
      final badge = ui.Rect.fromLTWH(
        pixel.left,
        math.max(0, pixel.top - pixel.height - 2),
        math.max(pixel.width, 18),
        math.max(pixel.height * 0.6, 14),
      );
      canvas.drawCircle(
        badge.topLeft + ui.Offset(badge.width / 2, badge.height / 2),
        badge.height / 2,
        ui.Paint()
          ..color = const ui.Color(0xFFFFFFFF)
          ..style = ui.PaintingStyle.fill,
      );
      final paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: ui.TextAlign.center),
      )
        ..pushStyle(textStyle)
        ..addText(mark.label);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: badge.width));
      canvas.drawParagraph(
        paragraph,
        badge.topLeft + ui.Offset(0, (badge.height - paragraph.height) / 2),
      );
      ledger.add(
        SmartLayoutMarkLedgerEntry(
          markId: mark.markId,
          label: mark.label,
          pageRect: mark.pageRect,
          pixelRect: pixel,
          assetKey: 'annotated|page',
        ),
      );
    }
    final picture = recorder.endRecording();
    _activeResources++;
    try {
      final image = await picture.toImage(pageImage.width, pageImage.height);
      return image;
    } catch (_) {
      _activeResources--;
      rethrow;
    }
  }

  Future<SmartLayoutRenderAsset> _buildCrop(
    ui.Image pageImage,
    PagePixelTransform transform,
    AssetCropSpec crop,
  ) async {
    final pixel = transform.pixelRectToRaster(
      transform.pageRectToPixel(crop.pageRect),
    );
    final width = pixel.width.round();
    final height = pixel.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      pageImage,
      pixel,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    _activeResources++;
    ui.Image image;
    try {
      image = await picture.toImage(width, height);
    } catch (_) {
      _activeResources--;
      rethrow;
    }
    try {
      final bytes = await _encode(image);
      final byteList = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      return SmartLayoutRenderAsset(
        key: 'crop|${crop.sourceKey}',
        kind: SmartLayoutAssetKind.crop,
        sourceKey: crop.sourceKey,
        widthPx: width,
        heightPx: height,
        bytes: byteList,
        fingerprint: AssetFingerprint.of(
          kind: 'crop',
          sourceKey: crop.sourceKey,
          rasterRect: pixel,
          scale: transform.scale,
          contentBytes: byteList,
        ),
      );
    } finally {
      _dispose(image);
    }
  }

  Future<ByteData> _encode(ui.Image image) async {
    try {
      return await _codec(image);
    } catch (_) {
      throw const _AssetCodecException();
    }
  }

  void _dispose(ui.Image image) {
    _activeResources--;
    image.dispose();
  }

  static bool _isCancelled(AssetBuildCancelToken? token) =>
      token?.isCancelled ?? false;

  /// 有界并行 map；取消返回 null。单元素失败向上抛（整体失败）。
  Future<List<T>?> _mapBounded<S, T>(
    List<S> items,
    Future<T> Function(S) transform,
    AssetBuildCancelToken? cancelToken,
  ) async {
    final results = List<T?>.filled(items.length, null);
    var next = 0;
    final workers = List.generate(
      math.min(_maxConcurrency, items.length),
      (_) => () async {
        while (next < items.length) {
          if (_isCancelled(cancelToken)) return;
          final index = next++;
          results[index] = await transform(items[index]);
        }
      },
    );
    await Future.wait(workers.map((worker) => worker()));
    if (_isCancelled(cancelToken)) return null;
    return results.cast<T>();
  }
}

class _AssetCodecException implements Exception {
  const _AssetCodecException();
}
