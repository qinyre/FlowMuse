import 'dart:typed_data';
import 'dart:ui' as ui;

import '../snapshot/deterministic_hash.dart';

/// page 坐标（Scene 单位）↔ 像素坐标 的确定性变换。
/// pixel = (page + offset) × scale（scale 即 DPR/栅格密度）。
class PagePixelTransform {
  const PagePixelTransform({
    required this.scale,
    this.offsetX = 0,
    this.offsetY = 0,
  }) : assert(scale > 0);

  final double scale;
  final double offsetX;
  final double offsetY;

  ui.Rect pageRectToPixel(ui.Rect pageRect) => ui.Rect.fromLTRB(
    (pageRect.left + offsetX) * scale,
    (pageRect.top + offsetY) * scale,
    (pageRect.right + offsetX) * scale,
    (pageRect.bottom + offsetY) * scale,
  );

  ui.Rect pixelRectToPage(ui.Rect pixelRect) => ui.Rect.fromLTRB(
    pixelRect.left / scale - offsetX,
    pixelRect.top / scale - offsetY,
    pixelRect.right / scale - offsetX,
    pixelRect.bottom / scale - offsetY,
  );

  /// 像素矩形取整（半开区间 [floor(left), ceil(right))）。
  ui.Rect pixelRectToRaster(ui.Rect pixelRect) => ui.Rect.fromLTRB(
    pixelRect.left.floorToDouble(),
    pixelRect.top.floorToDouble(),
    pixelRect.right.ceilToDouble(),
    pixelRect.bottom.ceilToDouble(),
  );
}

/// 资产 canonical 指纹：kind+sourceKey+几何+变换+内容字节全部参与；
/// 相同输入（含相同像素内容）必得相同指纹，供请求关联与审计。
class AssetFingerprint {
  const AssetFingerprint._(this.value);

  final String value;

  static AssetFingerprint of({
    required String kind,
    required String sourceKey,
    required ui.Rect rasterRect,
    required double scale,
    required List<int> contentBytes,
  }) {
    final content = fnv1a32(contentBytes);
    return AssetFingerprint._(
      fingerprint64(
        'asset|$kind|$sourceKey|'
        '${rasterRect.left}|${rasterRect.top}|'
        '${rasterRect.width}|${rasterRect.height}|$scale|$content',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AssetFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AssetFingerprint($value)';
}

/// 三类资产：clean（无标记整页/区域）、annotated（带 mark 徽章）、
/// crop（区域裁剪，只从 clean 源派生——标记永远不进 OCR crop）。
enum SmartLayoutAssetKind { clean, annotated, crop }

/// 一条已编码资产：PNG 字节 + 元数据 + 指纹；不持有活体图像资源。
class SmartLayoutRenderAsset {
  const SmartLayoutRenderAsset({
    required this.key,
    required this.kind,
    required this.sourceKey,
    required this.widthPx,
    required this.heightPx,
    required this.bytes,
    required this.fingerprint,
  });

  final String key;
  final SmartLayoutAssetKind kind;
  final String sourceKey;
  final int widthPx;
  final int heightPx;
  final Uint8List bytes;
  final AssetFingerprint fingerprint;
}

/// mark 账本条目：徽章只画在 annotated 资产上，账本记录其 page/pixel
/// 几何与所属资产键，保证 source 可追踪、标记不进入 crop。
class SmartLayoutMarkLedgerEntry {
  const SmartLayoutMarkLedgerEntry({
    required this.markId,
    required this.label,
    required this.pageRect,
    required this.pixelRect,
    required this.assetKey,
  });

  final String markId;
  final String label;
  final ui.Rect pageRect;
  final ui.Rect pixelRect;
  final String assetKey;
}

/// 一次构建的完整资产包（不可变；活体图像已在构建期全部释放）。
class SmartLayoutRenderAssets {
  const SmartLayoutRenderAssets({
    required this.transform,
    required this.assets,
    required this.marks,
    required this.pageWidthPx,
    required this.pageHeightPx,
  });

  final PagePixelTransform transform;
  final Map<String, SmartLayoutRenderAsset> assets;
  final List<SmartLayoutMarkLedgerEntry> marks;
  final int pageWidthPx;
  final int pageHeightPx;

  SmartLayoutRenderAsset? assetOf(SmartLayoutAssetKind kind, String sourceKey) {
    for (final asset in assets.values) {
      if (asset.kind == kind && asset.sourceKey == sourceKey) return asset;
    }
    return null;
  }
}
