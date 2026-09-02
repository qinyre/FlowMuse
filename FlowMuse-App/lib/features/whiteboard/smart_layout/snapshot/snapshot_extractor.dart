import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import 'layout_page_snapshot.dart';
import 'scene_revision.dart';
import 'source_coverage_ledger.dart';

/// 从 Scene 提取页面级 [LayoutPageSnapshot] 的唯一入口。
///
/// 页归属：元素的 flowMuseData.pageId 等于目标页（无分页数据的历史
/// Scene 按空页处理，不猜测归属）。页面框（isCanvasPage）与 PDF 底图
/// （isPdfBackground）计入 background 对象；锁定元素为
/// protectedObstacle；其余 movable。软删元素不属于页面内容。
/// 未知元素类型按其 type 原样投影，不丢弃。
class SnapshotExtractor {
  const SnapshotExtractor();

  LayoutPageSnapshot extract({
    required Scene scene,
    required String pageId,
    required SceneRevision sceneRevision,
  }) {
    final active = scene.orderedElements
        .where((e) => !e.isDeleted && e.pageId == pageId)
        .toList();
    final zIndexById = <String, int>{
      for (var i = 0; i < active.length; i++) active[i].id.value: i,
    };

    SnapshotBounds? pageBounds;
    final objects = <SnapshotObject>[];
    final inkStrokes = <SnapshotInkStroke>[];
    final renderAssets = <SnapshotRenderAsset>[];

    for (final element in active) {
      final sourceId = element.id.value;
      final zIndex = zIndexById[sourceId] ?? 0;
      final visualBounds = conservativeVisualBounds(element);
      if (element.isCanvasPage) {
        pageBounds = pageBounds == null
            ? visualBounds
            : pageBounds.union(visualBounds);
      }
      if (element is FreedrawElement) {
        inkStrokes.add(
          SnapshotInkStroke(
            sourceId: sourceId,
            bounds: SnapshotBounds.ofElement(element),
            visualBounds: visualBounds,
            rotation: element.angle,
            groupIds: List.unmodifiable(element.groupIds),
            frameId: element.frameId,
            zIndex: zIndex,
            pointCount: element.points.length,
            hasPressures: element.pressures.isNotEmpty,
          ),
        );
        continue;
      }

      final bindingRefs = <String>[
        for (final bound in element.boundElements) bound.id,
        if (element is TextElement && element.containerId != null)
          element.containerId!,
      ];
      SnapshotObject object = SnapshotObject(
        sourceId: sourceId,
        kind: element.type,
        bounds: SnapshotBounds.ofElement(element),
        visualBounds: visualBounds,
        rotation: element.angle,
        mobility: _mobilityOf(element),
        groupIds: List.unmodifiable(element.groupIds),
        frameId: element.frameId,
        bindingRefs: List.unmodifiable(bindingRefs),
        zIndex: zIndex,
        memberIds: element is FrameElement
            ? _frameMemberIds(active, element)
            : const [],
        exactText: element is TextElement ? element.text : null,
        textStyle: element is TextElement
            ? SnapshotTextStyle(
                fontSize: element.fontSize,
                fontFamily: element.fontFamily,
                lineHeight: element.lineHeight,
              )
            : null,
        fileId: element is ImageElement ? element.fileId : null,
        imageCrop:
            element is ImageElement &&
                element.crop != null &&
                !element.crop!.isFullImage
            ? element.crop
            : null,
        imageIntrinsicSize: element is ImageElement
            ? SnapshotBounds(
                left: 0,
                top: 0,
                width: element.width / element.imageScale,
                height: element.height / element.imageScale,
              )
            : null,
      );
      objects.add(object);

      if (element is ImageElement) {
        final file = scene.files[element.fileId];
        renderAssets.add(
          SnapshotRenderAsset(
            fileId: element.fileId,
            ownerSourceId: sourceId,
            status: file == null
                ? SnapshotRenderAssetStatus.missing
                : SnapshotRenderAssetStatus.resolved,
            mimeType: file?.mimeType ?? element.mimeType,
            byteLength: file?.bytes.length,
          ),
        );
      }
    }

    SnapshotBounds? contentBounds;
    for (final object in objects.where(
      (o) => o.mobility != SnapshotMobility.background,
    )) {
      contentBounds =
          contentBounds?.union(object.visualBounds) ?? object.visualBounds;
    }
    for (final stroke in inkStrokes) {
      contentBounds =
          contentBounds?.union(stroke.visualBounds) ?? stroke.visualBounds;
    }

    final sourceIds = <String>[
      for (final object in objects) object.sourceId,
      for (final stroke in inkStrokes) stroke.sourceId,
    ];

    return LayoutPageSnapshot(
      pageId: pageId,
      pageBounds: pageBounds,
      contentBounds: contentBounds,
      sceneRevision: sceneRevision,
      objects: List.unmodifiable(objects),
      inkStrokes: List.unmodifiable(inkStrokes),
      renderAssets: List.unmodifiable(renderAssets),
      sourceCoverage: SourceCoverageLedger.pending(sourceIds),
    );
  }

  static SnapshotMobility _mobilityOf(Element element) {
    if (element.isCanvasPage || element.isPdfBackground) {
      return SnapshotMobility.background;
    }
    if (element.locked) return SnapshotMobility.protectedObstacle;
    return SnapshotMobility.movable;
  }

  static List<String> _frameMemberIds(
    List<Element> pageElements,
    FrameElement frame,
  ) {
    return [
      for (final element in pageElements)
        if (element.frameId == frame.id.value) element.id.value,
    ];
  }
}
