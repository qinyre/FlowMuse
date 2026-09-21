import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/resolved_page_scope.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RectangleElement page(String id, double x) => RectangleElement(
    id: ElementId('frame-$id'),
    x: x,
    y: 0,
    width: 600,
    height: 800,
    customData: {
      'flowMuse': {'pageId': id, 'role': 'page'},
    },
  );
  TextElement text(
    String id, {
    String? owner,
    double x = 60,
    List<String> groups = const [],
    bool locked = false,
  }) => TextElement(
    id: ElementId(id),
    x: x,
    y: 100,
    width: 120,
    height: 40,
    text: '原文',
    fontFamily: 'Excalifont',
    groupIds: groups,
    locked: locked,
    customData: owner == null
        ? null
        : {
            'flowMuse': {'pageId': owner},
          },
  );
  Scene pages() =>
      Scene().addElement(page('p1', 0)).addElement(page('p2', 800));

  test('显式归属、缺失归属、失效旧页归属共享快照范围且不改元数据', () {
    final scene = pages()
        .addElement(text('explicit', owner: 'p1'))
        .addElement(text('missing'))
        .addElement(text('stale', owner: 'deleted-page'));
    final fingerprint = SceneFingerprint.of(scene);
    final scope = ResolvedPageScope.resolve(scene, 'p1');
    expect(scope.includedSourceIds, {
      'frame-p1',
      'explicit',
      'missing',
      'stale',
    });
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: 'p1',
      sceneRevision: SceneRevision(
        epoch: 0,
        revision: 1,
        fingerprint: fingerprint,
      ),
      scope: scope,
    );
    expect(
      snapshot.sourceCoverage.statuses.keys.toSet(),
      scope.includedSourceIds,
    );
    expect(
      scope.captureScene(scene).activeElements.map((e) => e.id.value).toSet(),
      scope.includedSourceIds,
    );
    expect(SceneFingerprint.of(scene), fingerprint);
    expect(
      scope
          .captureScene(scene)
          .activeElements
          .singleWhere((e) => e.id.value == 'missing')
          .pageId,
      isNull,
    );
    expect(
      const SnapshotExtractor()
          .extract(
            scene: scene,
            pageId: 'p1',
            sceneRevision: snapshot.sceneRevision,
          )
          .sourceCoverage
          .sourceCount,
      2,
      reason: '未传 scope 的旧调用保持精确 pageId 语义',
    );
  });

  test('有效他页内容不因落在当前页而被抢入，作为固定障碍并报告部分整理', () {
    final scene = pages().addElement(text('other', owner: 'p2'));
    final scope = ResolvedPageScope.resolve(scene, 'p1');
    expect(scope.includedSourceIds, {'frame-p1'});
    expect(scope.excludedReasons, {'other': 'other-page'});
    expect(scope.fixedBounds.keys, ['other']);
  });

  test('轻微越页边且98%可见的无归属图片纳入；显著越界/重叠页仍不猜', () {
    ImageElement picture(String id, double x, double width) => ImageElement(
      id: ElementId(id),
      x: x,
      y: 200,
      width: width,
      height: 160,
      fileId: 'asset',
    );
    final scene = pages()
        .addElement(picture('near-edge', -4, 400))
        .addElement(picture('outside', -30, 400))
        .addElement(picture('tiny-outside', -4, 4));
    final before = SceneFingerprint.of(scene);
    final scope = ResolvedPageScope.resolve(scene, 'p1');
    expect(scope.includedSourceIds, contains('near-edge'));
    expect(scope.includedSourceIds, isNot(contains('outside')));
    expect(scope.includedSourceIds, isNot(contains('tiny-outside')));
    expect(
      ResolvedPageScope.resolve(
        scene.addElement(page('overlap', 0)),
        'p1',
      ).includedSourceIds,
      isNot(contains('near-edge')),
    );
    expect(SceneFingerprint.of(scene), before);
    expect(
      scene.activeElements.whereType<ImageElement>().every(
        (e) => e.pageId == null,
      ),
      isTrue,
    );
  });

  test('跨页、跨边界和多个重叠页的推断归属不猜测', () {
    final scene = pages()
        .addElement(text('edge', x: 580))
        .addElement(text('member', groups: ['g']))
        .addElement(text('remote', owner: 'p2', x: 900, groups: ['g']));
    final scope = ResolvedPageScope.resolve(scene, 'p1');
    expect(scope.includedSourceIds, {'frame-p1'});
    expect(scope.excludedReasons, {
      'edge': 'ambiguous-page',
      'member': 'closure-conflict',
    });
    final overlap = ResolvedPageScope.resolve(
      scene.addElement(page('p3', 0)),
      'p1',
    );
    expect(overlap.includedSourceIds, {'frame-p1'});
  });

  test('同页原生组可临时归属，锁定成员与跨页闭包整组保护', () {
    final scene = pages()
        .addElement(text('a', owner: 'p1', groups: ['good']))
        .addElement(text('b', groups: ['good']))
        .addElement(text('c', owner: 'p1', groups: ['locked']))
        .addElement(text('d', owner: 'p1', groups: ['locked'], locked: true))
        .addElement(text('e', owner: 'p1', groups: ['cross']))
        .addElement(text('f', owner: 'p2', x: 900, groups: ['cross']));
    final scope = ResolvedPageScope.resolve(scene, 'p1');
    expect(scope.includedSourceIds, containsAll(['a', 'b', 'c', 'd', 'e']));
    expect(scope.protectedSourceIds, containsAll(['c', 'd', 'e']));
    expect(scope.protectedSourceIds.intersection({'a', 'b'}), isEmpty);
    expect(
      scope.effectivePageIdOf(
        scene.activeElements.singleWhere((e) => e.id.value == 'b'),
      ),
      'p1',
    );
  });

  test('反向绑定和缺失闭包引用保护本页元素', () {
    final scene = pages().addElement(
      text('bound', owner: 'p1').copyWith(
        boundElements: const [BoundElement(id: 'gone', type: 'arrow')],
      ),
    );
    expect(
      ResolvedPageScope.resolve(scene, 'p1').protectedSourceIds,
      contains('bound'),
    );
  });

  test('无页面框时保持明确归属，不用画布包围盒猜测', () {
    final scene = Scene()
        .addElement(text('known', owner: 'p1'))
        .addElement(text('unknown'));
    expect(ResolvedPageScope.resolve(scene, 'p1').includedSourceIds, {'known'});
  });
}
