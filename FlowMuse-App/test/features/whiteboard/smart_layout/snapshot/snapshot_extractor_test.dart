import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pageId = 'page-1';
  const pageCustomData = {
    'flowMuse': {'role': 'page', 'pageId': pageId},
  };
  const onPageCustomData = {
    'flowMuse': {'pageId': pageId},
  };

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(scene),
  );

  RectangleElement onPage(
    String id, {
    double x = 10,
    double angle = 0,
    bool locked = false,
    Map<String, Object?>? customData = onPageCustomData,
  }) {
    return RectangleElement(
      id: ElementId(id),
      x: x,
      y: 10,
      width: 40,
      height: 30,
      angle: angle,
      locked: locked,
      seed: 7,
      versionNonce: 11,
      updated: 1000,
      customData: customData,
    );
  }

  group('SourceCoverageLedger', () {
    test('建账全 pending；重复 id 构造失败', () {
      final ledger = SourceCoverageLedger.pending(['a', 'b']);
      expect(ledger.sourceCount, 2);
      expect(ledger.pendingCount, 2);
      expect(ledger.isFinalized, isFalse);
      expect(ledger.statusOf('a'), SourceCoverageStatus.pending);
      expect(
        () => SourceCoverageLedger.pending(['a', 'a']),
        throwsArgumentError,
      );
    });

    test('终态只能进入一次：consumed/preserved 二选一且不可再标记', () {
      var ledger = SourceCoverageLedger.pending(['a', 'b', 'c']);
      ledger = ledger.markConsumed(['a']);
      ledger = ledger.markPreserved(['b']);
      expect(ledger.consumedCount, 1);
      expect(ledger.preservedCount, 1);
      expect(ledger.isFinalized, isFalse);
      ledger = ledger.markConsumed(['c']);
      expect(ledger.isFinalized, isTrue);
      expect(
        () => ledger.markPreserved(['a']),
        throwsStateError,
        reason: '终态不可翻转',
      );
      expect(
        () => ledger.markConsumed(['ghost']),
        throwsStateError,
        reason: '未知源不可标记',
      );
    });

    test('标记返回新账本，原账本不受影响（唯一性透传基础）', () {
      final base = SourceCoverageLedger.pending(['a']);
      final next = base.markConsumed(['a']);
      expect(base.pendingCount, 1);
      expect(next.consumedCount, 1);
      expect(next, isNot(base));
      expect(next.hashValue, isNot(base.hashValue));
    });

    test('值语义与哈希稳定', () {
      final a = SourceCoverageLedger.pending(['x', 'y']).markConsumed(['x']);
      final b = SourceCoverageLedger.pending(['y', 'x']).markConsumed(['x']);
      expect(a, b);
      expect(a.hashValue, b.hashValue);
      expect(
        SourceCoverageLedger.pending(['x']).hashValue,
        SourceCoverageLedger.pending(['x']).hashValue,
      );
    });
  });

  group('SnapshotExtractor 页归属与 mobility', () {
    test('只收本页未删元素；软删与其他页元素不入账', () {
      final scene = Scene()
          .addElement(onPage('on-page'))
          .addElement(
            onPage(
              'other-page',
              customData: const {
                'flowMuse': {'pageId': 'page-2'},
              },
            ),
          )
          .addElement(onPage('deleted').copyWith(isDeleted: true));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      expect(snapshot.objects.map((o) => o.sourceId), ['on-page']);
      expect(snapshot.sourceCoverage.sourceCount, 1);
      expect(
        snapshot.sourceCoverage.statusOf('on-page'),
        SourceCoverageStatus.pending,
      );
    });

    test('页面框=background+pageBounds；锁定物=protectedObstacle；普通物=movable', () {
      final pageFrame = onPage(
        'frame-page',
        x: 0,
        customData: pageCustomData,
      ).copyWith(width: 1588, height: 2246);
      final scene = Scene()
          .addElement(pageFrame)
          .addElement(onPage('locked-rect', locked: true))
          .addElement(onPage('plain-rect'));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final byId = {for (final o in snapshot.objects) o.sourceId: o};
      expect(byId['frame-page']!.mobility, SnapshotMobility.background);
      expect(byId['locked-rect']!.mobility, SnapshotMobility.protectedObstacle);
      expect(byId['plain-rect']!.mobility, SnapshotMobility.movable);
      expect(snapshot.pageBounds, isNotNull);
      expect(snapshot.pageBounds!.width, greaterThan(1500));
      // 三者都入账，无一丢失
      expect(snapshot.sourceCoverage.sourceCount, 3);
    });
  });

  group('不可变投影完整性（无丢失）', () {
    test('旋转元素：rotation 记录且 visualBounds 大于轴对齐 bounds', () {
      final scene = Scene().addElement(onPage('rot', angle: 0.7853981));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final object = snapshot.objects.single;
      expect(object.rotation, 0.7853981);
      // 40×30 旋转 45°：AABB 宽 = (40+30)·cos45°
      expect(object.visualBounds.width, closeTo(49.4975, 0.001));
    });

    test('嵌套组与 zIndex：groupIds 保序，zIndex 按阅读序', () {
      final scene = Scene()
          .addElement(
            onPage('child-a').copyWith(groupIds: const ['g1', 'g1/g2']),
          )
          .addElement(
            onPage('child-b').copyWith(groupIds: const ['g1', 'g1/g2']),
          )
          .addElement(onPage('outside'));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final byId = {for (final o in snapshot.objects) o.sourceId: o};
      expect(byId['child-a']!.groupIds, ['g1', 'g1/g2']);
      expect(byId['child-a']!.zIndex, lessThan(byId['outside']!.zIndex));
    });

    test('绑定：boundElements 与容器文本 containerId 双向引用', () {
      final container = onPage('shape-1').copyWith(
        boundElements: const [BoundElement(id: 'arrow-1', type: 'arrow')],
      );
      final boundText = TextElement(
        id: const ElementId('bound-text'),
        x: 12,
        y: 12,
        width: 30,
        height: 20,
        text: '容器内文本',
        containerId: 'shape-1',
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final scene = Scene().addElement(container).addElement(boundText);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final byId = {for (final o in snapshot.objects) o.sourceId: o};
      expect(byId['shape-1']!.bindingRefs, contains('arrow-1'));
      expect(byId['bound-text']!.bindingRefs, ['shape-1']);
      expect(byId['bound-text']!.exactText, '容器内文本');
      expect(byId['bound-text']!.textStyle, isNotNull);
    });

    test('裁剪图片：crop 记录、内在尺寸估计、文件 resolved', () {
      final image = ImageElement(
        id: const ElementId('img-1'),
        x: 0,
        y: 0,
        width: 100,
        height: 50,
        fileId: 'file-1',
        imageScale: 2.0,
        crop: const ImageCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final scene = Scene()
          .addFile(
            'file-1',
            ImageFile(
              mimeType: 'image/png',
              bytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          )
          .addElement(image);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final object = snapshot.objects.single;
      expect(object.fileId, 'file-1');
      expect(
        object.imageCrop,
        const ImageCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
      );
      expect(object.imageIntrinsicSize!.width, closeTo(50, 0.001));
      final asset = snapshot.renderAssets.single;
      expect(asset.status, SnapshotRenderAssetStatus.resolved);
      expect(asset.byteLength, 4);
      expect(asset.mimeType, 'image/png');
      expect(asset.ownerSourceId, 'img-1');
    });

    test('缺文件：asset=missing 但对象与账本完整保留', () {
      final image = ImageElement(
        id: const ElementId('img-miss'),
        x: 0,
        y: 0,
        width: 80,
        height: 80,
        fileId: 'ghost-file',
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final scene = Scene().addElement(image);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      expect(
        snapshot.renderAssets.single.status,
        SnapshotRenderAssetStatus.missing,
      );
      expect(snapshot.objects.single.sourceId, 'img-miss');
      expect(
        snapshot.sourceCoverage.statusOf('img-miss'),
        SourceCoverageStatus.pending,
        reason: '缺文件对象仍入账，由消费者按 preserved 处理',
      );
    });

    test('未知元素类型：kind 原样保留并照常入账', () {
      final mystery = Element(
        id: const ElementId('mystery-1'),
        type: 'future-widget',
        x: 5,
        y: 5,
        width: 10,
        height: 10,
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final scene = Scene().addElement(mystery);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      expect(snapshot.objects.single.kind, 'future-widget');
      expect(
        snapshot.sourceCoverage.statusOf('mystery-1'),
        SourceCoverageStatus.pending,
      );
    });

    test('笔迹：进入 inkStrokes，点数/压力/几何齐全', () {
      final stroke = FreedrawElement(
        id: const ElementId('ink-1'),
        x: 0,
        y: 0,
        width: 100,
        height: 20,
        points: const [Point(0, 0), Point(50, 10), Point(100, 20)],
        pressures: const [0.1, 0.5, 0.9],
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final scene = Scene().addElement(stroke);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      expect(snapshot.inkStrokes, hasLength(1));
      final ink = snapshot.inkStrokes.single;
      expect(ink.pointCount, 3);
      expect(ink.hasPressures, isTrue);
      expect(ink.visualBounds.width, greaterThan(100), reason: '笔刷包络外扩后的可视边界');
      expect(snapshot.objects, isEmpty);
      expect(
        snapshot.sourceCoverage.statusOf('ink-1'),
        SourceCoverageStatus.pending,
      );
    });

    test('frame：memberIds 收集框内成员', () {
      final frame = FrameElement(
        id: const ElementId('frame-1'),
        x: 0,
        y: 0,
        width: 500,
        height: 500,
        seed: 3,
        versionNonce: 5,
        updated: 1,
        customData: onPageCustomData,
      );
      final inside = onPage('in-1').copyWith(frameId: 'frame-1');
      final scene = Scene().addElement(frame).addElement(inside);
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final frameObject = snapshot.objects.singleWhere(
        (o) => o.sourceId == 'frame-1',
      );
      expect(frameObject.kind, 'frame');
      expect(frameObject.memberIds, ['in-1']);
      expect(
        snapshot.objects.singleWhere((o) => o.sourceId == 'in-1').frameId,
        'frame-1',
      );
    });
  });

  group('contentBounds 与指纹', () {
    test('contentBounds 为非背景对象+笔迹并集；空页为 null', () {
      final emptyScene = Scene();
      final emptySnapshot = const SnapshotExtractor().extract(
        scene: emptyScene,
        pageId: pageId,
        sceneRevision: revisionOf(emptyScene),
      );
      expect(emptySnapshot.contentBounds, isNull);

      final scene = Scene()
          .addElement(onPage('bg', x: 0, customData: pageCustomData))
          .addElement(onPage('a', x: 100))
          .addElement(onPage('b', x: 300));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final content = snapshot.contentBounds!;
      expect(content.left, greaterThanOrEqualTo(100));
      expect(content.right, closeTo(340, 0.001));
    });

    test('快照指纹确定且随对象位移变化', () {
      final scene = Scene().addElement(onPage('a')).addElement(onPage('b'));
      final moved = Scene()
          .addElement(onPage('a', x: 500))
          .addElement(onPage('b'));
      final extractor = const SnapshotExtractor();
      final s1 = extractor.extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final again = extractor.extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final s2 = extractor.extract(
        scene: moved,
        pageId: pageId,
        sceneRevision: revisionOf(moved),
      );
      expect(s1.fingerprint, again.fingerprint);
      expect(s1.fingerprint, isNot(s2.fingerprint));
    });

    test('账本消费推进时快照账本哈希变化（消费进度可校验）', () {
      final scene = Scene().addElement(onPage('a')).addElement(onPage('b'));
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: pageId,
        sceneRevision: revisionOf(scene),
      );
      final consumed = snapshot.sourceCoverage.markConsumed(['a']);
      expect(consumed.hashValue, isNot(snapshot.sourceCoverage.hashValue));
      expect(consumed.consumedCount, 1);
    });
  });
}
