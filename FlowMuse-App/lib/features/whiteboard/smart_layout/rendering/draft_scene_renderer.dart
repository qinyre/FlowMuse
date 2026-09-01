import 'dart:ui'
    as ui
    show Canvas, Picture, PictureRecorder, Image, Codec, instantiateImageCodec;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../design/text_measure_adapter.dart';

/// 资源事实（不猜测、不伪造）。
enum DraftResourceStatus {
  /// 图片已用真实 codec 解码并参与绘制。
  resolved,

  /// 引用缺失或解码失败：按编辑器占位语义降级（灰框），如实记录。
  missing,

  /// 非资源型元素（文本/形状/笔迹等）。
  notApplicable,
}

/// 单元素渲染层记录：真实 painter 几何 + 资源事实。
class DraftRenderLayer {
  const DraftRenderLayer({
    required this.elementId,
    required this.kind,
    required this.zIndex,
    required this.bounds,
    required this.resourceStatus,
  });

  final String elementId;

  /// 元素 type（text/image/freedraw/...未知原样）。
  final String kind;
  final int zIndex;

  /// 真实渲染边界（场景坐标）：
  /// - 文本（含公式 math text）：TextPainter 实测墨迹盒（真实换行后
  ///   最宽行宽 × 实测高），不是元素盒子估算；
  /// - 图片：显示盒（crop/等比由 painter 决定，记录最终绘制盒）；
  /// - 其余：元素盒（painter 几何）。
  final Bounds bounds;
  final DraftResourceStatus resourceStatus;
}

/// 渲染快照：Draft 位图（真实绘制产物，非估算缩略图）+ 层记录。
/// [image] 归调用方所有——用毕必须 [dispose]；renderer 不保留引用。
class DraftRenderSnapshot {
  DraftRenderSnapshot({
    required this.image,
    required this.pixelSize,
    required this.layers,
    required this.missingFileIds,
  });

  final ui.Image image;
  final Size pixelSize;
  final List<DraftRenderLayer> layers;
  final List<String> missingFileIds;

  bool get hasMissingResources => missingFileIds.isNotEmpty;

  bool _disposed = false;

  /// 释放位图；幂等。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

/// 渲染取消/释放语义：render 代际作废 + 活资源计数可观测归零。
class DraftRenderCancelled implements Exception {
  const DraftRenderCancelled();
}

/// 真实 DraftSceneRenderer（V3-503A）：复用编辑器真实渲染链——
/// [StaticCanvasPainter]（viewport 变换/culling/ElementRenderer 全派发）
/// 与 [TextMeasureAdapter]（TextPainter 实测，与 V3-300A 同路径）——
/// 把 Draft Scene 渲染为位图并采集文本/图片/公式边界。
///
/// - 与编辑器渲染几何一致：同一 painter、同一 viewport 变换、同一
///   字体解析（FontResolver）；
/// - 缺资源明确降级：引用缺失/解码失败的图片按编辑器占位语义绘制，
///   layer 与 snapshot 如实记录 missing，不删除元素、不造数据；
/// - 不使用估算缩略图：位图来自 PictureRecorder→toImage 的真实绘制；
/// - 资源归零：解码图片在光栅化后立即释放；[cancelCurrent] 作废在途
///   代际并释放全部中间资源；[liveResourceCount] 可观测，连续渲染与
///   取消后必须归零。
class DraftSceneRenderer {
  int _generation = 0;
  int _cancelledThrough = 0;
  int _liveResources = 0;
  bool _disposed = false;

  /// 当前活资源数（已解码未释放的 ui.Image）；测试观测用。
  int get liveResourceCount => _liveResources;

  bool get isDisposed => _disposed;

  /// 作废当前在途渲染：下一检查点抛 [DraftRenderCancelled]，中间资源
  /// 全部释放。幂等；对已完成的渲染无影响。
  void cancelCurrent() {
    _cancelledThrough = _generation;
  }

  /// 释放 renderer：作废在途渲染并拒绝后续调用。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelCurrent();
  }

  void _checkCancelled(int generation) {
    if (_disposed) {
      throw StateError('DraftSceneRenderer 已释放');
    }
    if (generation <= _cancelledThrough) {
      throw const DraftRenderCancelled();
    }
  }

  /// 渲染 Draft Scene。
  ///
  /// [viewport]：场景→位图变换（与编辑器 painter 同式：scale(zoom) 后
  /// translate(-offset)）；[pixelSize]：目标位图尺寸；[adapter]：真实
  /// rough 适配器（与编辑器导出/画布同源，缺省新建无缓存实例）；
  /// 取消时抛 [DraftRenderCancelled] 且零残留资源。
  Future<DraftRenderSnapshot> render({
    required Scene scene,
    required ViewportState viewport,
    required Size pixelSize,
    RoughAdapter? adapter,
  }) async {
    if (_disposed) {
      throw StateError('DraftSceneRenderer 已释放');
    }
    final generation = ++_generation;
    final active = scene.activeElements;

    // ---- 1. 图片预解码（真实 codec；串行解码限制峰值资源）----
    final referencedFileIds = <String>{};
    for (final element in active) {
      if (element is ImageElement) referencedFileIds.add(element.fileId);
    }
    final resolved = <String, ui.Image>{};
    final missing = <String>[];
    final acquired = <ui.Image>[];
    try {
      for (final fileId in referencedFileIds) {
        _checkCancelled(generation);
        final file = scene.files[fileId];
        if (file == null) {
          missing.add(fileId);
          continue;
        }
        final image = await _decode(fileId, file.bytes);
        if (image == null) {
          missing.add(fileId);
          continue;
        }
        acquired.add(image);
        resolved[fileId] = image;
      }

      // ---- 2. 真实 painter 绘制 + 光栅化 ----
      _checkCancelled(generation);
      final picture = _paintToPicture(
        scene: scene,
        viewport: viewport,
        pixelSize: pixelSize,
        resolvedImages: resolved,
        adapter: adapter,
      );
      ui.Image? rasterized;
      try {
        _checkCancelled(generation);
        rasterized = await picture.toImage(
          pixelSize.width.ceil(),
          pixelSize.height.ceil(),
        );
      } finally {
        picture.dispose();
      }

      // ---- 3. 边界采集（文本/公式走真实测量，与 V3-300A 同路径）----
      final layers = <DraftRenderLayer>[];
      final measure = TextMeasureAdapter();
      final zIndexById = <String, int>{};
      for (var i = 0; i < scene.orderedElements.length; i++) {
        zIndexById[scene.orderedElements[i].id.value] = i;
      }
      for (final element in active) {
        layers.add(_layerOf(element, measure, resolved, zIndexById, missing));
      }

      return DraftRenderSnapshot(
        image: rasterized,
        pixelSize: pixelSize,
        layers: List.unmodifiable(layers),
        missingFileIds: List.unmodifiable(missing),
      );
    } finally {
      // 解码图与所有中间资源归零（成功路径在光栅化后即无用途）。
      for (final image in acquired) {
        _release(image);
      }
    }
  }

  DraftRenderLayer _layerOf(
    Element element,
    TextMeasureAdapter measure,
    Map<String, ui.Image> resolved,
    Map<String, int> zIndexById,
    List<String> missing,
  ) {
    if (element is ImageElement) {
      final resolvedImage = resolved[element.fileId];
      return DraftRenderLayer(
        elementId: element.id.value,
        kind: element.type,
        zIndex: zIndexById[element.id.value] ?? 0,
        bounds: Bounds.fromLTWH(
          element.x,
          element.y,
          element.width,
          element.height,
        ),
        resourceStatus: resolvedImage == null
            ? (missing.contains(element.fileId)
                  ? DraftResourceStatus.missing
                  : DraftResourceStatus.notApplicable)
            : DraftResourceStatus.resolved,
      );
    }
    if (element is TextElement) {
      // 文本与公式 math text 同路径：真实 TextPainter 测量墨迹盒。
      final result = element.text.isEmpty
          ? null
          : measure.measure(
              text: element.text,
              fontFamily: element.fontFamily,
              fontSize: element.fontSize,
              lineHeight: element.lineHeight,
              maxWidth: element.width,
            );
      return DraftRenderLayer(
        elementId: element.id.value,
        kind: element.type,
        zIndex: zIndexById[element.id.value] ?? 0,
        bounds: Bounds.fromLTWH(
          element.x,
          element.y,
          result?.width ?? 0,
          result?.height ?? 0,
        ),
        resourceStatus: DraftResourceStatus.notApplicable,
      );
    }
    return DraftRenderLayer(
      elementId: element.id.value,
      kind: element.type,
      zIndex: zIndexById[element.id.value] ?? 0,
      bounds: Bounds.fromLTWH(
        element.x,
        element.y,
        element.width,
        element.height,
      ),
      resourceStatus: DraftResourceStatus.notApplicable,
    );
  }

  ui.Picture _paintToPicture({
    required Scene scene,
    required ViewportState viewport,
    required Size pixelSize,
    required Map<String, ui.Image> resolvedImages,
    RoughAdapter? adapter,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final painter = StaticCanvasPainter(
      scene: scene,
      adapter: adapter ?? RoughCanvasAdapter(),
      viewport: viewport,
      resolvedImages: resolvedImages.isEmpty ? null : resolvedImages,
    );
    painter.paint(canvas, pixelSize);
    return recorder.endRecording();
  }

  /// 真实 codec 解码；codec 帧立即释放，失败返回 null（missing 事实）。
  Future<ui.Image?> _decode(String fileId, Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _liveResources++;
      return frame.image;
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  void _release(ui.Image image) {
    _liveResources--;
    image.dispose();
  }
}
