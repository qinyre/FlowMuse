import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/affine_layout_transform.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_scene_transformer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_transform_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/transform_invariant.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-303A 验收：identity/inverse/组合；关系双向一致；失败零副作用；
/// draft gateway 接入；upsert 语义（version 不在变换层推进）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SceneTransformOutcome move(Scene scene, Set<String> ids, double dx,
      double dy) {
    return SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {for (final v in ids) ElementId(v)},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform.translation(dx, dy),
    );
  }

  test('平移主元素：几何更新、version/versionNonce 不动（upsert 语义）',
      () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 0,
          y: 0,
          width: 40,
          height: 30,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final before = scene.elements.single;
    final outcome = move(scene, {'r1'}, 10, 5);
    expect(outcome, isA<SceneTransformSuccess>());
    final success = outcome as SceneTransformSuccess;
    final moved = success.scene.elements.single;
    expect(moved.x, 10);
    expect(moved.y, 5);
    expect(moved.version, before.version, reason: '变换层不推进版本');
    expect(moved.versionNonce, before.versionNonce);
    expect(moved.updated, before.updated);
    expect(success.updatedElements, hasLength(1));
    expect(success.appliedSourceIds, ['r1']);
  });

  test('identity 变换：元素逐字段等值，Scene fingerprint 不变', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 3,
          y: 4,
          width: 40,
          height: 30,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(FreedrawElement(
          id: const ElementId('ink1'),
          x: 100,
          y: 100,
          width: 50,
          height: 20,
          points: const [Point(0, 0), Point(50, 20)],
          seed: 2,
          versionNonce: 2,
          updated: 2,
        ));
    final beforeFp = SceneFingerprint.of(scene);
    final outcome = move(scene, {'r1', 'ink1'}, 0, 0);
    final success = outcome as SceneTransformSuccess;
    for (final e in success.scene.elements) {
      final old = scene.elements.firstWhere((o) => o.id == e.id);
      expect(e.x, old.x);
      expect(e.y, old.y);
      expect(e.width, old.width);
      expect(e.angle, old.angle);
    }
    expect(SceneFingerprint.of(success.scene), beforeFp,
        reason: 'identity 变换不得改变内容指纹');
  });

  test('inverse：平移后逆平移逐字段还原（浮点 1e-9）', () {
    var scene = Scene().addElement(FreedrawElement(
          id: const ElementId('ink1'),
          x: 12.5,
          y: -7.25,
          width: 50,
          height: 20,
          points: const [Point(0, 0), Point(25, 10), Point(50, 20)],
          pressures: const [0.2, 0.5, 0.9],
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final forward = move(scene, {'ink1'}, 33.75, -12.5) as SceneTransformSuccess;
    final back = SmartLayoutSceneTransformer.apply(
      scene: forward.scene,
      targetIds: {const ElementId('ink1')},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform.translation(-33.75, 12.5),
    ) as SceneTransformSuccess;
    final restored = back.scene.elements.single as FreedrawElement;
    expect(restored.x, closeTo(12.5, 1e-9));
    expect(restored.y, closeTo(-7.25, 1e-9));
    expect(restored.points.length, 3);
    expect(restored.points[2].x, closeTo(50, 1e-9));
  });

  test('组合：两次平移合成一次等价', () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final s1 =
        move(scene, {'r1'}, 10, 0) as SceneTransformSuccess;
    final s2 =
        move(s1.scene, {'r1'}, 0, 20) as SceneTransformSuccess;
    final composed = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('r1')},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform.translation(10, 20),
    ) as SceneTransformSuccess;
    final twoStep = s2.scene.elements.single;
    final oneStep = composed.scene.elements.single;
    expect(twoStep.x, closeTo(oneStep.x, 1e-9));
    expect(twoStep.y, closeTo(oneStep.y, 1e-9));
  });

  test('旋转：中心绕点移动、angle 累加、尺寸不变', () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 100,
          y: 100,
          width: 80,
          height: 40,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    const theta = 0.5;
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('r1')},
      op: LayoutTransformOp.rotate,
      transform: AffineLayoutTransform.rotationAround(50, 50, theta),
      rotationDelta: theta,
    );
    final moved = (outcome as SceneTransformSuccess).scene.elements.single;
    expect(moved.width, 80);
    expect(moved.height, 40);
    expect(moved.angle, closeTo(theta, 1e-9));
    // 中心 (140,120) 绕 (50,50) 旋转 θ。
    final expectedCx = 50 + (90 * math.cos(theta) - 70 * math.sin(theta));
    final expectedCy = 50 + (90 * math.sin(theta) + 70 * math.cos(theta));
    expect(moved.x + moved.width / 2, closeTo(expectedCx, 1e-9));
    expect(moved.y + moved.height / 2, closeTo(expectedCy, 1e-9));
  });

  test('缩放：包围盒与局部 points 同步缩放', () {
    var scene = Scene().addElement(FreedrawElement(
          id: const ElementId('ink1'),
          x: 0,
          y: 0,
          width: 100,
          height: 50,
          points: const [Point(0, 0), Point(50, 25), Point(100, 50)],
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('ink1')},
      op: LayoutTransformOp.resize,
      transform: AffineLayoutTransform.scaleAround(0, 0, 2, 3),
      resizeTargetWidth: 200,
      resizeTargetHeight: 150,
    );
    final moved =
        (outcome as SceneTransformSuccess).scene.elements.single
            as FreedrawElement;
    expect(moved.width, closeTo(200, 1e-9));
    expect(moved.height, closeTo(150, 1e-9));
    expect(moved.points[1].x, closeTo(100, 1e-9));
    expect(moved.points[1].y, closeTo(75, 1e-9));
  });

  test('嵌套组闭包：全体成员同变换，关系零违规（TransformInvariant）', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('a'),
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          groupIds: const ['g1'],
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(RectangleElement(
          id: const ElementId('b'),
          x: 50,
          y: 0,
          width: 10,
          height: 10,
          groupIds: const ['g2', 'g1'],
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ))
        .addElement(RectangleElement(
          id: const ElementId('c'),
          x: 100,
          y: 0,
          width: 10,
          height: 10,
          groupIds: const ['g2', 'g1'],
          seed: 3,
          versionNonce: 3,
          updated: 1,
        ));
    final outcome = move(scene, {'a'}, 5, 7);
    final success = outcome as SceneTransformSuccess;
    expect(success.appliedSourceIds, containsAll(['a', 'b', 'c']),
        reason: '同组成员整体移动');
    // TransformInvariant 深一致性（真实快照提取路径）。
    const pageCustomData = {
      'flowMuse': {'pageId': 'p1'},
    };
    Scene pageScene(Scene s) {
      var withData = s;
      for (final e in s.elements) {
        withData = withData.upsertRemoteElements([
          e.copyWith(customData: pageCustomData),
        ]);
      }
      return withData;
    }

    final oldSnapshot = const SnapshotExtractor().extract(
      scene: pageScene(scene),
      pageId: 'p1',
      sceneRevision: _revisionOf(scene),
    );
    final newSnapshot = const SnapshotExtractor().extract(
      scene: pageScene(success.scene),
      pageId: 'p1',
      sceneRevision: _revisionOf(success.scene),
    );
    final violations = TransformInvariant.checkObjects(
      oldObjects: oldSnapshot.objects,
      newObjects: newSnapshot.objects,
      expectedTransforms: {
        for (final sourceId in success.appliedSourceIds)
          sourceId: AffineLayoutTransform.translation(5, 7),
      },
    );
    expect(violations, isEmpty);
  });

  test('frame 成员与容器文本跟随', () {
    var scene = Scene()
        .addElement(FrameElement(
          id: const ElementId('f1'),
          x: 0,
          y: 0,
          width: 300,
          height: 200,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(RectangleElement(
          id: const ElementId('inner'),
          x: 20,
          y: 20,
          width: 50,
          height: 50,
          frameId: 'f1',
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ))
        .addElement(TextElement(
          id: const ElementId('label'),
          x: 0,
          y: 200,
          width: 300,
          height: 20,
          text: 'label',
          containerId: 'f1',
          seed: 3,
          versionNonce: 3,
          updated: 1,
        ));
    final outcome = move(scene, {'f1'}, 30, 40);
    final success = outcome as SceneTransformSuccess;
    final byId = {
      for (final e in success.scene.elements) e.id.value: e,
    };
    expect(byId['f1']!.x, 30);
    expect(byId['inner']!.x, 50, reason: 'frame 成员跟随');
    expect(byId['label']!.x, 30, reason: '容器文本跟随');
    expect((byId['label'] as TextElement).containerId, 'f1');
    expect(success.appliedSourceIds, containsAll(['f1', 'inner', 'label']));
  });

  test('绑定箭头端点跟随（v1 同语义：起点贴 box 右缘中点）', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('box'),
          x: 0,
          y: 0,
          width: 100,
          height: 50,
          boundElements: const [],
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(ArrowElement(
          id: const ElementId('arrow'),
          x: 100,
          y: 0,
          width: 50,
          height: 25,
          points: const [Point(0, 0), Point(50, 25)],
          startBinding: const PointBinding(
            elementId: 'box',
            fixedPoint: Point(1.0, 0.5),
          ),
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ));
    final outcome = move(scene, {'box'}, 50, 100);
    final success = outcome as SceneTransformSuccess;
    final arrow = success.scene.elements
        .firstWhere((e) => e.id.value == 'arrow') as ArrowElement;
    expect(arrow.points.first.x + arrow.x, closeTo(150, 1.0),
        reason: '起点贴合移动后 box 右缘中点');
    expect(arrow.points.first.y + arrow.y, closeTo(125, 1.0));
  });

  test('锁定元素拒绝：Scene 引用与 fingerprint 不变（全有或全无）', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('locked-rect'),
          x: 0,
          y: 0,
          width: 40,
          height: 30,
          locked: true,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(RectangleElement(
          id: const ElementId('normal'),
          x: 100,
          y: 0,
          width: 40,
          height: 30,
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ));
    final fp = SceneFingerprint.of(scene);
    final outcome = move(scene, {'locked-rect', 'normal'}, 10, 0);
    expect(outcome, isA<SceneTransformFailure>());
    final failure = outcome as SceneTransformFailure;
    expect(failure.reason, TransformRejectReason.protectedObstacleLocked);
    expect(failure.sourceId, 'locked-rect');
    expect(scene.elements.firstWhere((e) => e.id.value == 'normal').x, 100,
        reason: '全有或全无：合法元素也未被移动');
    expect(SceneFingerprint.of(scene), fp);
  });

  test('背景元素拒绝与非法 resize 目标拒绝', () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('page-frame'),
          x: 0,
          y: 0,
          width: 800,
          height: 600,
          seed: 1,
          versionNonce: 1,
          updated: 1,
          customData: const {
            'flowMuse': {'role': 'page', 'pageId': 'p1'},
          },
        ));
    final outcome = move(scene, {'page-frame'}, 5, 5);
    expect(
      (outcome as SceneTransformFailure).reason,
      TransformRejectReason.backgroundElement,
    );

    var scene2 = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 0,
          y: 0,
          width: 40,
          height: 30,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final resizeOutcome = SmartLayoutSceneTransformer.apply(
      scene: scene2,
      targetIds: {const ElementId('r1')},
      op: LayoutTransformOp.resize,
      transform: AffineLayoutTransform.scaleAround(0, 0, 2, 1),
      resizeTargetWidth: -5,
    );
    expect(
      (resizeOutcome as SceneTransformFailure).reason,
      TransformRejectReason.degenerateResizeTarget,
    );
  });

  test('未知类型原子拒绝：不存在"尽量变换"', () {
    var scene = Scene().addElement(Element(
          id: const ElementId('widget-x'),
          type: 'future-widget',
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final outcome = move(scene, {'widget-x'}, 1, 1);
    expect(
      (outcome as SceneTransformFailure).reason,
      TransformRejectReason.unsupportedElementType,
    );
    expect(scene.elements.single.x, 0, reason: '拒绝时零副作用');
  });

  test('π 旋转归入旋转类：angle 累加、尺寸不变、无负宽高（复审 finding 1）',
      () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 100,
          y: 100,
          width: 80,
          height: 40,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('r1')},
      op: LayoutTransformOp.rotate,
      transform: AffineLayoutTransform.rotationAround(
        140,
        120,
        math.pi,
      ),
      rotationDelta: math.pi,
    );
    final moved =
        (outcome as SceneTransformSuccess).scene.elements.single;
    expect(moved.width, 80, reason: 'π 旋转不得改变尺寸');
    expect(moved.height, 40);
    expect(moved.width, greaterThan(0));
    expect(moved.angle, closeTo(math.pi, 1e-9));
    // 中心绕自身旋转不动。
    expect(moved.x + moved.width / 2, closeTo(140, 1e-9));
    expect(moved.y + moved.height / 2, closeTo(120, 1e-9));
  });

  test('负缩放与镜像确定性抛出（不产生负尺寸/镜像元素）', () {
    var scene = Scene().addElement(RectangleElement(
          id: const ElementId('r1'),
          x: 0,
          y: 0,
          width: 40,
          height: 30,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ));
    expect(
      () => SmartLayoutSceneTransformer.apply(
        scene: scene,
        targetIds: {const ElementId('r1')},
        op: LayoutTransformOp.resize,
        transform: AffineLayoutTransform.scaleAround(0, 0, -2, 1),
      ),
      throwsUnsupportedError,
    );
    // 已旋转元素上的轴对齐缩放（局部系 ≠ 世界系）同样确定性失败。
    var rotatedScene = Scene().addElement(RectangleElement(
          id: const ElementId('r2'),
          x: 0,
          y: 0,
          width: 40,
          height: 30,
          angle: 0.3,
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ));
    expect(
      () => SmartLayoutSceneTransformer.apply(
        scene: rotatedScene,
        targetIds: {const ElementId('r2')},
        op: LayoutTransformOp.resize,
        transform: AffineLayoutTransform.scaleAround(0, 0, 2, 2),
      ),
      throwsUnsupportedError,
    );
  });

  test('line/arrow 缩放：局部 points 同步缩放（复审 finding 2）', () {
    var scene = Scene()
        .addElement(ArrowElement(
          id: const ElementId('arrow'),
          x: 10,
          y: 10,
          width: 100,
          height: 50,
          points: const [Point(0, 0), Point(100, 50)],
          startBinding: const PointBinding(
            elementId: 'box',
            fixedPoint: Point(1.0, 0.5),
          ),
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(LineElement(
          id: const ElementId('line'),
          x: 0,
          y: 100,
          width: 80,
          height: 0,
          points: const [Point(0, 0), Point(80, 0)],
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ));
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('line')},
      op: LayoutTransformOp.resize,
      transform: AffineLayoutTransform.scaleAround(0, 100, 2, 2),
      resizeTargetWidth: 160,
    );
    final success = outcome as SceneTransformSuccess;
    final scaledLine = success.scene.elements
        .firstWhere((e) => e.id.value == 'line') as LineElement;
    expect(scaledLine.width, closeTo(160, 1e-9));
    expect(scaledLine.points.last.x, closeTo(160, 1e-9),
        reason: 'line points 与包围盒同步缩放');

    final arrowOutcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {const ElementId('arrow')},
      op: LayoutTransformOp.resize,
      transform: AffineLayoutTransform.scaleAround(0, 0, 2, 2),
      resizeTargetWidth: 200,
      resizeTargetHeight: 100,
    );
    final scaledArrow = (arrowOutcome as SceneTransformSuccess)
        .scene
        .elements
        .firstWhere((e) => e.id.value == 'arrow') as ArrowElement;
    expect(scaledArrow.points.last.x, closeTo(200, 1e-9),
        reason: 'arrow points 与包围盒同步缩放');
    expect(scaledArrow.startBinding?.elementId, 'box', reason: '绑定保持');
  });

  test('交叉嵌套组 contains 语义不拆组（复审 finding 3）', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('a'),
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          groupIds: const ['g1'],
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(RectangleElement(
          id: const ElementId('b'),
          x: 50,
          y: 0,
          width: 10,
          height: 10,
          groupIds: const ['g1', 'g2'],
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ));
    final outcome = move(scene, {'a'}, 5, 0);
    expect((outcome as SceneTransformSuccess).appliedSourceIds,
        containsAll(['a', 'b']),
        reason: 'b 与 a 共享 g1（即使 b 的最外层是 g2）也必须整体移动');
  });

  test('软删元素跳过；锁定绑定箭头使整批拒绝（复审 finding 4）', () {
    var scene = Scene()
        .addElement(RectangleElement(
          id: const ElementId('box'),
          x: 0,
          y: 0,
          width: 50,
          height: 50,
          seed: 1,
          versionNonce: 1,
          updated: 1,
        ))
        .addElement(ArrowElement(
          id: const ElementId('locked-arrow'),
          x: 50,
          y: 25,
          width: 30,
          height: 0,
          points: const [Point(0, 0), Point(30, 0)],
          startBinding: const PointBinding(
            elementId: 'box',
            fixedPoint: Point(1.0, 0.5),
          ),
          locked: true,
          seed: 2,
          versionNonce: 2,
          updated: 1,
        ))
        // 软删元素：目标集合含其 id 也不得被变换。
        .addElement(RectangleElement(
          id: const ElementId('deleted'),
          x: 200,
          y: 200,
          width: 10,
          height: 10,
          seed: 3,
          versionNonce: 3,
          updated: 1,
        ));
    scene = scene.softDeleteElement(const ElementId('deleted'));
    final outcome = move(scene, {'box', 'deleted'}, 10, 0);
    // box 移动会带动锁定箭头端点重采样 → 预检拒绝（全有或全无）。
    expect(outcome, isA<SceneTransformFailure>());
    final failure = outcome as SceneTransformFailure;
    expect(failure.reason, TransformRejectReason.protectedObstacleLocked);
    expect(failure.sourceId, 'locked-arrow');
    // 软删元素零触碰。
    final deleted = scene.elements
        .firstWhere((e) => e.id.value == 'deleted');
    expect(deleted.x, 200);
  });

  test('draft gateway 接入：captureDraftBase → transform → commitValidated',
      () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(AddElementResult(RectangleElement(
      id: const ElementId('r1'),
      x: 10,
      y: 10,
      width: 40,
      height: 40,
      seed: 1,
      versionNonce: 1,
      updated: 1,
    )));
    final gateway = SmartLayoutEditorGateway(controller);
    final draftBase = gateway.captureDraftBase();
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: draftBase,
      targetIds: {const ElementId('r1')},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform.translation(100, 50),
    );
    final success = outcome as SceneTransformSuccess;
    gateway.commitValidated(success.commitResult);
    final committed = gateway.currentScene.elements
        .firstWhere((e) => e.id.value == 'r1');
    expect(committed.x, 110);
    expect(committed.y, 60);
    expect(
      committed.version,
      greaterThan(draftBase.elements.single.version),
      reason: '提交入口统一推进版本（applyResult bump）',
    );
    // 草稿基线不受提交影响。
    expect(draftBase.elements.single.x, 10);
  });
}

SceneRevision _revisionOf(Scene scene) => SceneRevision(
      epoch: 0,
      revision: 1,
      fingerprint: SceneFingerprint.of(scene),
    );
