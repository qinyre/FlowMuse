/// 区域高清资产（spec §5）：识别图 = 只渲染该区域 target 笔迹的临时 PNG。
/// [assetId] 会话内自增（`a<n>`），不写入 Scene、不伪造 fileId。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui'
    as ui
    show
        Image,
        ImageDescriptor,
        ImageByteFormat,
        ImmutableBuffer,
        Offset,
        PixelFormat,
        Size;

import 'package:flutter/foundation.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/ink_region_segmenter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/region_segment.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';

/// 分区层区域记录：regionId 沿用 `regionIdOf`（`r:` + 成员最小 sourceId），
/// 显式区分 [targetSourceIds]（本区域待消费正文笔迹）与
/// [contextSourceIds]（相邻区域边缘笔迹——首版不进识别图，仅用于本地
/// 归属唯一性断言与未来扩展）。
class RegionRecord {
  const RegionRecord({
    required this.regionId,
    required this.bounds,
    required this.targetSourceIds,
    required this.localLineHeight,
    this.contextSourceIds = const [],
  });

  final String regionId;

  /// 页面坐标外框。
  final RecognitionBounds bounds;
  final List<String> targetSourceIds;
  final List<String> contextSourceIds;

  /// 局部行高估计（页面单位），缩放与留白的基准。
  final double localLineHeight;

  @override
  String toString() =>
      'RegionRecord($regionId, targets: ${targetSourceIds.length}, '
      'context: ${contextSourceIds.length}, lineH: $localLineHeight)';
}

class RegionAsset {
  const RegionAsset({
    required this.assetId,
    required this.pngBytes,
    required this.scale,
    required this.paddingPageUnits,
    required this.paddingPx,
    required this.targetSourceIds,
    required this.contextSourceIds,
    required this.pageBounds,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final String assetId;
  final Uint8List pngBytes;

  /// 像素/页面单位（与渲染参数一致并随请求上行）。
  final double scale;

  /// 留白（页面单位）与对应像素数。
  final double paddingPageUnits;
  final double paddingPx;

  final List<String> targetSourceIds;
  final List<String> contextSourceIds;

  /// 含留白的页面坐标外框（pageBounds ↔ 局部坐标 ↔ 像素坐标 闭环的一端）。
  final RecognitionBounds pageBounds;
  final int pixelWidth;
  final int pixelHeight;

  @override
  String toString() =>
      'RegionAsset($assetId, ${pixelWidth}x$pixelHeight, '
      'scale: ${scale.toStringAsFixed(2)}, targets: '
      '${targetSourceIds.length})';
}

enum RegionAssetFailureReason {
  /// 区域在最低可读缩放下仍超单图上限：调用方应先局部分区；
  /// 不可安全拆分则整块保留原件（spec §5.2）。
  tooLarge,

  /// 渲染失败（目标缺员/零尺寸等）：该区域按 preserved 处理，不使整批失败。
  renderError,
}

sealed class RegionAssetOutcome {
  const RegionAssetOutcome();
}

class RegionAssetBuilt extends RegionAssetOutcome {
  const RegionAssetBuilt(this.asset);

  final RegionAsset asset;
}

class RegionAssetFailed extends RegionAssetOutcome {
  const RegionAssetFailed(this.regionId, this.reason, [this.detail = '']);

  final String regionId;
  final RegionAssetFailureReason reason;
  final String detail;
}

/// 资产索引（spec §5.7）：assetId 为主键（一笔迹可关联多张临时资产），
/// 同时维护 sourceId → assetId[] 反向索引供纠错失效使用；原生资产沿用
/// `fileId|ownerSourceId`(/`|crop`) 既有约定，不入本索引。
class RegionAssetIndex {
  final Map<String, RegionAsset> _assetsById = {};
  final Map<String, List<String>> _assetIdsBySource = {};

  void register(RegionAsset asset) {
    if (_assetsById.containsKey(asset.assetId)) {
      throw StateError('assetId 重复: ${asset.assetId}');
    }
    _assetsById[asset.assetId] = asset;
    for (final sourceId in asset.targetSourceIds) {
      _assetIdsBySource.putIfAbsent(sourceId, () => []).add(asset.assetId);
    }
    for (final sourceId in asset.contextSourceIds) {
      _assetIdsBySource.putIfAbsent(sourceId, () => []).add(asset.assetId);
    }
  }

  RegionAsset? assetOf(String assetId) => _assetsById[assetId];

  List<String> assetIdsOf(String sourceId) =>
      List.unmodifiable(_assetIdsBySource[sourceId] ?? const <String>[]);

  int get assetCount => _assetsById.length;

  /// 纠错失效：返回涉及源集合的临时资产 id 全集。
  Set<String> invalidateForSources(Iterable<String> sourceIds) {
    final dead = <String>{};
    for (final sourceId in sourceIds) {
      dead.addAll(_assetIdsBySource[sourceId] ?? const <String>[]);
    }
    for (final assetId in dead) {
      final asset = _assetsById.remove(assetId);
      if (asset == null) continue;
      for (final sourceId in asset.targetSourceIds) {
        _assetIdsBySource[sourceId]?.remove(assetId);
      }
      for (final sourceId in asset.contextSourceIds) {
        _assetIdsBySource[sourceId]?.remove(assetId);
      }
    }
    return dead;
  }
}

/// 归属唯一性断言（spec §5.3）：同笔迹可以是多张资产的 target 或 context，
/// 但只在一个 target 集合中计为待消费。违反抛 [StateError]。
void assertTargetOwnershipUniqueness(Iterable<RegionRecord> records) {
  final targetOwner = <String, String>{};
  for (final record in records) {
    for (final sourceId in record.targetSourceIds) {
      final existing = targetOwner[sourceId];
      if (existing != null && existing != record.regionId) {
        throw StateError(
          '源 $sourceId 同时是 $existing 与 '
          '${record.regionId} 的 target（每源至多一个 target 区域）',
        );
      }
      targetOwner[sourceId] = record.regionId;
    }
  }
}

/// 小笔迹归属（spec §5.4）：句号、小数点、编号点、短横线等微小笔迹在
/// 分区层生成候选归属——最近文本区域且间距 < 0.8×该区域局部行高；
/// 禁止按面积小删除，无法确认归属的独立保留（不出现在结果中）。
class SmallStrokeAttribution {
  const SmallStrokeAttribution();

  /// 返回 sourceId → 目标 regionId 的归属表；未匹配的笔迹缺席（独立保留）。
  Map<String, String> attribute({
    required List<RegionRecord> regions,
    required Map<String, RecognitionBounds> smallStrokeBounds,
  }) {
    final result = <String, String>{};
    for (final entry in smallStrokeBounds.entries) {
      String? bestRegion;
      var bestGap = double.infinity;
      for (final region in regions) {
        final gap = gapBetween(region.bounds, entry.value);
        final threshold = 0.8 * region.localLineHeight;
        if (gap < threshold && gap < bestGap) {
          bestGap = gap;
          bestRegion = region.regionId;
        }
      }
      if (bestRegion != null) {
        result[entry.key] = bestRegion;
      }
    }
    return result;
  }

  /// 两外框间距：相交/包含为 0，否则为最近边距。
  static double gapBetween(RecognitionBounds a, RecognitionBounds b) {
    final dx = math.max(
      0.0,
      math.max(a.left - (b.left + b.width), b.left - (a.left + a.width)),
    );
    final dy = math.max(
      0.0,
      math.max(a.top - (b.top + b.height), b.top - (a.top + a.height)),
    );
    if (dx == 0 && dy == 0) return 0;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// 区域高清资产构建器（spec §5）：
/// - 经**隔离的** [DraftSceneRenderer] 实例直接渲染（独立生命周期，
///   不触碰预览渲染；dispose 释放）；
/// - 识别图只渲染 target 笔迹（context 笔迹不进图，§5.3）；
/// - 缩放目标：局部行高落在预算 [RecognitionBudget.regionTargetLineHeightMinPx]
///   起步（取最低可读档，控制体积）；超单图上限 fail closed 返回
///   [RegionAssetFailureReason.tooLarge]，由调用方局部分区或整块保留；
/// - 留白 = regionPaddingLineHeight × 局部行高（页面单位）；
/// - 浅色铅笔（颜色亮度 > 阈值）仅对临时资产做**一次**固定参数对比度增强，
///   原图与笔迹样式不变，不双份发送；
/// - 渲染位图在成功/失败/取消路径均释放。
class RegionAssetBuilder {
  RegionAssetBuilder({required Scene capturedScene, this.assetPrefix = 'a'})
    : _scene = capturedScene,
      _renderer = DraftSceneRenderer();

  final Scene _scene;
  final String assetPrefix;
  final DraftSceneRenderer _renderer;
  int _counter = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _renderer.dispose();
  }

  void _checkAlive() {
    if (_disposed) {
      throw StateError('RegionAssetBuilder 已释放');
    }
  }

  /// 构建单区域资产。单区域失败按 [RegionAssetFailed] 返回（区域隔离），
  /// 不抛出；[DraftRenderCancelled]（取消）向上传播。
  Future<RegionAssetOutcome> build(
    RegionRecord record,
    RecognitionBudget budget,
  ) async {
    _checkAlive();
    if (record.targetSourceIds.isEmpty) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.renderError,
        'target 笔迹为空',
      );
    }
    if (!record.bounds.width.isFinite ||
        !record.bounds.height.isFinite ||
        record.bounds.width <= 0 ||
        record.bounds.height <= 0) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.renderError,
        '区域外框退化',
      );
    }
    final lineHeight = record.localLineHeight > 0
        ? record.localLineHeight
        : math.max(1.0, record.bounds.height);
    final scale = budget.regionTargetLineHeightMinPx / lineHeight;
    if (!scale.isFinite || scale <= 0) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.renderError,
        '缩放退化: $scale',
      );
    }
    final paddingPage = budget.regionPaddingLineHeight * lineHeight;
    final paddedLeft = record.bounds.left - paddingPage;
    final paddedTop = record.bounds.top - paddingPage;
    final paddedWidth = record.bounds.width + 2 * paddingPage;
    final paddedHeight = record.bounds.height + 2 * paddingPage;
    final pixelWidth = (paddedWidth * scale).ceil();
    final pixelHeight = (paddedHeight * scale).ceil();
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.renderError,
        '像素尺寸退化',
      );
    }
    if (math.max(pixelWidth, pixelHeight) > budget.regionMaxEdgePx ||
        pixelWidth * pixelHeight > budget.regionMaxPixels) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.tooLarge,
        '${math.max(pixelWidth, pixelHeight)}px / '
        '${pixelWidth * pixelHeight}px 超上限',
      );
    }

    // 只渲染 target 笔迹的隔离子场景（保持原 z 序）。
    final targetSet = record.targetSourceIds.toSet();
    var subScene = Scene();
    var matched = 0;
    for (final element in _scene.orderedElements) {
      if (targetSet.contains(element.id.value)) {
        subScene = subScene.addElement(element);
        matched++;
      }
    }
    if (matched != record.targetSourceIds.length) {
      return RegionAssetFailed(
        record.regionId,
        RegionAssetFailureReason.renderError,
        'target 笔迹缺员: $matched/${record.targetSourceIds.length}',
      );
    }

    final snapshot = await _renderer.render(
      scene: subScene,
      viewport: ViewportState(
        offset: ui.Offset(paddedLeft, paddedTop),
        zoom: scale,
      ),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
    ui.Image? enhanced;
    try {
      final needsEnhancement = _targetHasLightStroke(
        record.targetSourceIds,
        budget.pencilLightnessThreshold,
      );
      final image = snapshot.image;
      Uint8List png;
      if (needsEnhancement) {
        enhanced = await _enhanceOnce(image);
        png = await _encodePng(enhanced);
      } else {
        png = await _encodePng(image);
      }
      final assetId = '$assetPrefix${++_counter}';
      return RegionAssetBuilt(
        RegionAsset(
          assetId: assetId,
          pngBytes: png,
          scale: scale,
          paddingPageUnits: paddingPage,
          paddingPx: paddingPage * scale,
          targetSourceIds: List.unmodifiable(record.targetSourceIds),
          contextSourceIds: List.unmodifiable(record.contextSourceIds),
          pageBounds: RecognitionBounds(
            left: paddedLeft,
            top: paddedTop,
            width: paddedWidth,
            height: paddedHeight,
          ),
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
        ),
      );
    } finally {
      snapshot.dispose();
      enhanced?.dispose();
    }
  }

  bool _targetHasLightStroke(List<String> targetSourceIds, double threshold) {
    final targetSet = targetSourceIds.toSet();
    for (final element in _scene.orderedElements) {
      if (!targetSet.contains(element.id.value)) continue;
      if (element is FreedrawElement &&
          lightnessOfStrokeColor(element.strokeColor) > threshold) {
        return true;
      }
    }
    return false;
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG 编码失败');
    }
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  /// 一次固定参数对比度增强（gamma=2.2，仅暗化中间调、纯白背景不变）；
  /// 输入/输出均为解码位图，原始笔迹样式不受影响。
  static Future<ui.Image> _enhanceOnce(ui.Image source) async {
    final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      throw StateError('像素读取失败');
    }
    final pixels = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = _gamma255(pixels[i]);
      pixels[i + 1] = _gamma255(pixels[i + 1]);
      pixels[i + 2] = _gamma255(pixels[i + 2]);
      // alpha 保持。
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: source.width,
      height: source.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    ui.Image? frameImage;
    try {
      final frame = await codec.getNextFrame();
      frameImage = frame.image;
      return frameImage;
    } finally {
      codec.dispose();
      descriptor.dispose();
    }
  }

  static const double _enhanceGamma = 2.2;

  static int _gamma255(int value) {
    if (value >= 255) return 255;
    if (value <= 0) return 0;
    final double normalized = value / 255.0;
    return (255.0 * math.pow(normalized, _enhanceGamma)).round();
  }
}

/// 笔画颜色亮度（近似相对亮度；解析失败按深色处理，不触发增强）。
double lightnessOfStrokeColor(String? hexColor) {
  if (hexColor == null || hexColor.isEmpty) return 0;
  var hex = hexColor.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  int? r;
  int? g;
  int? b;
  if (hex.length == 6) {
    r = int.tryParse(hex.substring(0, 2), radix: 16);
    g = int.tryParse(hex.substring(2, 4), radix: 16);
    b = int.tryParse(hex.substring(4, 6), radix: 16);
  } else if (hex.length == 8) {
    r = int.tryParse(hex.substring(2, 4), radix: 16);
    g = int.tryParse(hex.substring(4, 6), radix: 16);
    b = int.tryParse(hex.substring(6, 8), radix: 16);
  }
  if (r == null || g == null || b == null) return 0;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
}

/// 分区产物：识别区域记录 + 成员笔画（供类型守卫与账本使用）。
class RegionPartition {
  const RegionPartition({required this.record, required this.strokes});

  final RegionRecord record;
  final List<FreedrawElement> strokes;
}

/// 分区层（spec §5 前段、§6.1 proposing）：场景 → 识别区域记录。
///
/// - 复用确定性 [InkRegionSegmenter]（连通分量 + 列聚类），不新造分割算法；
/// - regionId 沿用 `regionIdOf` 口径（`r:` + 成员最小 sourceId）；
/// - 微小段（句号/编号点/短横线级）就近并入最近文本区域（间距 <
///   0.8×该区域局部行高），无法确认归属的独立保留，禁止按面积小删除；
/// - 邻区边缘笔迹进 contextSourceIds（首版不进识别图，仅本地归属断言）。
class RegionPartitioner {
  const RegionPartitioner({double smallStrokeExtentFactor = 0.35})
    : _smallStrokeExtentFactor = smallStrokeExtentFactor;

  /// 判定"小笔迹段"的尺度因子（段外框双维 < 该因子×局部行高）。
  final double _smallStrokeExtentFactor;

  List<RegionPartition> partition(Scene scene) {
    final strokes = scene.activeElements.whereType<FreedrawElement>().toList(
      growable: false,
    );
    if (strokes.isEmpty) return const [];
    final segments = InkRegionSegmenter().segment(strokes);

    // 1. 区分小段与正常区域段。
    String regionIdOfSegment(RegionSegment segment) =>
        'r:${_minStrokeId(segment.strokeIds)}';
    final byId = <String, FreedrawElement>{
      for (final stroke in strokes) stroke.id.value: stroke,
    };
    RecognitionBounds boundsOfSegment(RegionSegment segment) =>
        RecognitionBounds(
          left: segment.left,
          top: segment.top,
          width: segment.width,
          height: segment.height,
        );
    double lineHeightOf(RegionSegment segment) =>
        segment.localScale > 0 ? segment.localScale : 1.0;

    final normal = <RegionSegment>[];
    final small = <RegionSegment>[];
    for (final segment in segments) {
      final threshold = _smallStrokeExtentFactor * lineHeightOf(segment);
      if (segment.width < threshold && segment.height < threshold) {
        small.add(segment);
      } else {
        normal.add(segment);
      }
    }

    // 2. 小段就近并入（<0.8×宿主行高）；无法确认归属的独立保留。
    final mergedInto = <String, String>{};
    if (small.isNotEmpty && normal.isNotEmpty) {
      final attribution = SmallStrokeAttribution();
      final hostRecords = <RegionRecord>[
        for (final segment in normal)
          RegionRecord(
            regionId: regionIdOfSegment(segment),
            bounds: boundsOfSegment(segment),
            targetSourceIds: segment.strokeIds,
            localLineHeight: lineHeightOf(segment),
          ),
      ];
      final smallBounds = <String, RecognitionBounds>{
        for (final segment in small)
          regionIdOfSegment(segment): boundsOfSegment(segment),
      };
      final attributionMap = attribution.attribute(
        regions: hostRecords,
        smallStrokeBounds: smallBounds,
      );
      for (final entry in attributionMap.entries) {
        mergedInto[entry.key] = entry.value;
      }
    }

    // 3. 重建成员集合（并入的小段成员归入宿主区域）。
    final membersByRegion = <String, Set<String>>{};
    for (final segment in normal) {
      membersByRegion
          .putIfAbsent(regionIdOfSegment(segment), () => <String>{})
          .addAll(segment.strokeIds);
    }
    for (final segment in small) {
      final host = mergedInto[regionIdOfSegment(segment)];
      if (host != null) {
        membersByRegion
            .putIfAbsent(host, () => <String>{})
            .addAll(segment.strokeIds);
      } else {
        // 独立保留：自成区域。
        membersByRegion
            .putIfAbsent(regionIdOfSegment(segment), () => <String>{})
            .addAll(segment.strokeIds);
      }
    }
    final lineHeightByRegion = <String, double>{
      for (final segment in normal)
        regionIdOfSegment(segment): lineHeightOf(segment),
      for (final segment in small)
        regionIdOfSegment(segment): lineHeightOf(segment),
    };

    // 4. 生成记录：bounds = 成员并集外框；context = 邻区边缘笔迹。
    final results = <RegionPartition>[];
    for (final entry in membersByRegion.entries) {
      final members = entry.value.toList()..sort();
      var left = double.infinity;
      var top = double.infinity;
      var right = double.negativeInfinity;
      var bottom = double.negativeInfinity;
      for (final member in members) {
        final stroke = byId[member]!;
        left = math.min(left, stroke.x);
        top = math.min(top, stroke.y);
        right = math.max(right, stroke.x + stroke.width);
        bottom = math.max(bottom, stroke.y + stroke.height);
      }
      final bounds = RecognitionBounds(
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
      );
      final lineHeight = lineHeightByRegion[entry.key] ?? 1.0;
      final context = <String>[];
      for (final other in membersByRegion.entries) {
        if (other.key == entry.key) continue;
        for (final member in other.value) {
          final stroke = byId[member]!;
          final memberBounds = RecognitionBounds(
            left: stroke.x,
            top: stroke.y,
            width: stroke.width,
            height: stroke.height,
          );
          if (SmallStrokeAttribution.gapBetween(bounds, memberBounds) <
              0.8 * lineHeight) {
            context.add(member);
          }
        }
      }
      results.add(
        RegionPartition(
          record: RegionRecord(
            regionId: entry.key,
            bounds: bounds,
            targetSourceIds: List.unmodifiable(members),
            contextSourceIds: List.unmodifiable(context..sort()),
            localLineHeight: lineHeight,
          ),
          strokes: List.unmodifiable([
            for (final member in members) byId[member]!,
          ]),
        ),
      );
    }
    assertTargetOwnershipUniqueness(results.map((entry) => entry.record));
    return List.unmodifiable(results);
  }

  static String _minStrokeId(List<String> ids) {
    var min = ids.first;
    for (final id in ids) {
      if (id.compareTo(min) < 0) min = id;
    }
    return min;
  }
}
