import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'deterministic_hash.dart';
import 'scene_revision.dart';
import 'source_coverage_ledger.dart';

/// 页面快照中对象的移动性分类（计划 §4.2）。
enum SnapshotMobility {
  /// 可参与重排。
  movable,

  /// 不可移动但会占据空间（锁定物等），排版必须绕开。
  protectedObstacle,

  /// 背景基础设施（页面框、PDF 底图），排版不触碰。
  background,
}

/// 轴对齐矩形（快照内不依赖 editor_core 的 Bounds，保持只读投影）。
class SnapshotBounds {
  const SnapshotBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory SnapshotBounds.ofElement(Element element) => SnapshotBounds(
    left: element.x,
    top: element.y,
    width: element.width,
    height: element.height,
  );

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  SnapshotBounds union(SnapshotBounds other) {
    final newLeft = left < other.left ? left : other.left;
    final newTop = top < other.top ? top : other.top;
    final newRight = right > other.right ? right : other.right;
    final newBottom = bottom > other.bottom ? bottom : other.bottom;
    return SnapshotBounds(
      left: newLeft,
      top: newTop,
      width: newRight - newLeft,
      height: newBottom - newTop,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SnapshotBounds &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SnapshotBounds($left, $top, ${width}x$height)';
}

/// 文本样式投影（exactText 之外排版需要的最小字段）。
class SnapshotTextStyle {
  const SnapshotTextStyle({
    required this.fontSize,
    required this.fontFamily,
    required this.lineHeight,
  });

  final double fontSize;
  final String fontFamily;
  final double lineHeight;

  @override
  bool operator ==(Object other) =>
      other is SnapshotTextStyle &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(fontSize, fontFamily, lineHeight);

  @override
  String toString() =>
      'SnapshotTextStyle($fontSize, $fontFamily, lineHeight: $lineHeight)';
}

/// 页面对象（非笔迹元素）的不可变投影。
class SnapshotObject {
  const SnapshotObject({
    required this.sourceId,
    required this.kind,
    required this.bounds,
    required this.visualBounds,
    required this.rotation,
    required this.mobility,
    required this.groupIds,
    required this.frameId,
    required this.bindingRefs,
    required this.zIndex,
    required this.memberIds,
    this.exactText,
    this.textStyle,
    this.fileId,
    this.imageCrop,
    this.imageIntrinsicSize,
  });

  final String sourceId;

  /// 元素类型字符串（'rectangle'/'text'/'image'/'frame'/'arrow'/未知类型
  /// 原样保留，不丢弃）。
  final String kind;
  final SnapshotBounds bounds;

  /// 旋转/笔刷包络外扩后的保守可视 AABB。
  final SnapshotBounds visualBounds;
  final double rotation;
  final SnapshotMobility mobility;
  final List<String> groupIds;
  final String? frameId;

  /// 绑定关系引用（boundElements id + 容器文本的 containerId）。
  final List<String> bindingRefs;
  final int zIndex;

  /// frame 对象的成员 id（组员经 groupIds 表达，此字段仅为 frame 填充）。
  final List<String> memberIds;

  /// typed text 永远来自 exactText（不来自 OCR 猜测）。
  final String? exactText;
  final SnapshotTextStyle? textStyle;
  final String? fileId;

  /// 归一化裁剪框（0–1）；非裁剪图片为 null。
  final ImageCrop? imageCrop;

  /// 图片内在尺寸（显示尺寸 / imageScale 的几何估计；文件缺失时仍记录）。
  final SnapshotBounds? imageIntrinsicSize;

  @override
  String toString() =>
      'SnapshotObject($sourceId, kind: $kind, mobility: $mobility, z: $zIndex)';
}

/// 手写笔迹的不可变投影（点位/压力细节留在 Scene，快照只留几何与引用）。
class SnapshotInkStroke {
  const SnapshotInkStroke({
    required this.sourceId,
    required this.bounds,
    required this.visualBounds,
    required this.rotation,
    required this.groupIds,
    required this.frameId,
    required this.zIndex,
    required this.pointCount,
    required this.hasPressures,
  });

  final String sourceId;
  final SnapshotBounds bounds;
  final SnapshotBounds visualBounds;
  final double rotation;
  final List<String> groupIds;
  final String? frameId;
  final int zIndex;
  final int pointCount;
  final bool hasPressures;

  @override
  String toString() =>
      'SnapshotInkStroke($sourceId, points: $pointCount, z: $zIndex)';
}

/// 渲染资产事实：图片文件引用的存在性。
/// [SnapshotRenderAssetStatus.missing] 只陈述事实——消费者不得删除或
/// 重造该对象，一律按 ledger preserved 处理。
enum SnapshotRenderAssetStatus { resolved, missing }

class SnapshotRenderAsset {
  const SnapshotRenderAsset({
    required this.fileId,
    required this.ownerSourceId,
    required this.status,
    this.mimeType,
    this.byteLength,
  });

  final String fileId;

  /// 引用该文件的页面对象 id。
  final String ownerSourceId;
  final SnapshotRenderAssetStatus status;
  final String? mimeType;
  final int? byteLength;

  @override
  String toString() => 'SnapshotRenderAsset($fileId, $status)';
}

/// 页面级不可变快照（计划 §4.2）：创建即冻结，持有唯一
/// [SourceCoverageLedger]（全部源 pending），后续阶段只透传校验。
class LayoutPageSnapshot {
  const LayoutPageSnapshot({
    required this.pageId,
    required this.pageBounds,
    required this.contentBounds,
    required this.sceneRevision,
    required this.objects,
    required this.inkStrokes,
    required this.renderAssets,
    required this.sourceCoverage,
  });

  final String pageId;

  /// 页面框（无页面框元素时为 null）。
  final SnapshotBounds? pageBounds;

  /// 全部对象+笔迹 visualBounds 的并集；空页为 null。
  final SnapshotBounds? contentBounds;
  final SceneRevision sceneRevision;
  final List<SnapshotObject> objects;
  final List<SnapshotInkStroke> inkStrokes;
  final List<SnapshotRenderAsset> renderAssets;
  final SourceCoverageLedger sourceCoverage;

  /// 快照 canonical 指纹（pageId+revision+对象投影+账本哈希），
  /// 供 preview=commit 与 metrics 一致性校验。
  String get fingerprint {
    final payload = [
      'page|$pageId',
      'rev|${sceneRevision.epoch}:${sceneRevision.revision}:'
          '${sceneRevision.fingerprint.value}',
      'ledger|${sourceCoverage.hashValue}',
      for (final object in objects)
        'obj|${object.sourceId}|${object.kind}|${object.mobility.name}'
            '|${object.zIndex}|${object.exactText ?? '-'}',
      for (final stroke in inkStrokes)
        'ink|${stroke.sourceId}|${stroke.zIndex}|${stroke.pointCount}',
      for (final asset in renderAssets)
        'asset|${asset.fileId}|${asset.ownerSourceId}|${asset.status.name}',
    ].join('~');
    return fingerprint64(payload);
  }

  @override
  String toString() =>
      'LayoutPageSnapshot($pageId, objects: ${objects.length}, '
      'ink: ${inkStrokes.length}, assets: ${renderAssets.length})';
}

/// 保守可视边界：先取 editor_core 可视边界（含笔刷包络），再对旋转
/// 元素取旋转四角的 AABB。
SnapshotBounds conservativeVisualBounds(Element element) {
  final base = elementVisualBounds(element);
  final box = SnapshotBounds(
    left: base.left,
    top: base.top,
    width: base.right - base.left,
    height: base.bottom - base.top,
  );
  if (element.angle == 0) return box;
  final centerX = element.x + element.width / 2;
  final centerY = element.y + element.height / 2;
  final rad = element.angle;
  final cosRad = math.cos(rad);
  final sinRad = math.sin(rad);
  final corners = <(double, double)>[
    (box.left, box.top),
    (box.right, box.top),
    (box.right, box.bottom),
    (box.left, box.bottom),
  ];
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final (x, y) in corners) {
    final dx = x - centerX;
    final dy = y - centerY;
    final rx = centerX + dx * cosRad - dy * sinRad;
    final ry = centerY + dx * sinRad + dy * cosRad;
    if (rx < minX) minX = rx;
    if (rx > maxX) maxX = rx;
    if (ry < minY) minY = ry;
    if (ry > maxY) maxY = ry;
  }
  return SnapshotBounds(
    left: minX,
    top: minY,
    width: maxX - minX,
    height: maxY - minY,
  );
}
