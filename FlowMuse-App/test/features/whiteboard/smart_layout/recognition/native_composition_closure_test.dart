import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/affine_layout_transform.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_scene_transformer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_transform_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/candidate_patch_materializer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';

/// §6.4 末段 原生组合单元：闭包计算（group/frame/binding）、整体变换、
/// 同组只变换一次；闭包共享/含锁定成员时整组保留。
void main() {
  TextElement groupedText(
    String id,
    String groupId, {
    double x = 100,
    bool locked = false,
  }) =>
      TextElement(
        id: ElementId(id),
        x: x,
        y: 50,
        width: 200,
        height: 40,
        text: 'text $id',
        groupIds: [groupId],
        locked: locked,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: 1,
      );

  LayoutRect rect(double left, double top) =>
      LayoutRect(left: left, top: top, width: 200, height: 40);

  test('closureOf：同组成员整体进闭包（group 闭包展开）', () {
    final scene = Scene()
        .addElement(groupedText('t1', 'grp-1'))
        .addElement(groupedText('t2', 'grp-1', x: 400))
        .addElement(groupedText('t3', 'grp-2', x: 700));
    final closure = SmartLayoutSceneTransformer.closureOf(
      scene,
      {ElementId('t1')},
    );
    expect(closure, containsAll([ElementId('t1'), ElementId('t2')]));
    expect(
      closure.contains(const ElementId('t3')),
      isFalse,
      reason: '无关组不进闭包',
    );
  });

  test('变换整组一次：成员 t1 变换后 t2 同步位移（appliedSourceIds 含两者）',
      () {
    final scene = Scene()
        .addElement(groupedText('t1', 'grp-1'))
        .addElement(groupedText('t2', 'grp-1', x: 400));
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {ElementId('t1')},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform(
        m00: 1,
        m01: 0,
        m10: 0,
        m11: 1,
        tx: 50,
        ty: 0,
      ),
    );
    expect(outcome, isA<SceneTransformSuccess>());
    final success = outcome as SceneTransformSuccess;
    expect(success.appliedSourceIds, containsAll(const ['t1', 't2']));
    final next = success.scene;
    final moved1 = next.activeElements.firstWhere(
      (e) => e.id.value == 't1',
    );
    final moved2 = next.activeElements.firstWhere(
      (e) => e.id.value == 't2',
    );
    expect(moved1.x, 150, reason: '目标位移 +50');
    expect(moved2.x, 450, reason: '同组成员同步位移（整体变换）');
  });

  test('闭包含锁定成员：整组保留（变换契约拒绝，零副作用）', () {
    final scene = Scene()
        .addElement(groupedText('t1', 'grp-1'))
        .addElement(groupedText('t2', 'grp-1', x: 400, locked: true));
    final outcome = SmartLayoutSceneTransformer.apply(
      scene: scene,
      targetIds: {ElementId('t1')},
      op: LayoutTransformOp.move,
      transform: AffineLayoutTransform(
        m00: 1,
        m01: 0,
        m10: 0,
        m11: 1,
        tx: 50,
        ty: 0,
      ),
    );
    expect(outcome, isA<SceneTransformFailure>(), reason: '锁定成员阻断整组');
    expect((outcome as SceneTransformFailure).sourceId, 't2');
  });

  test('物化：两个消费块共享闭包 → sharedClosureGroup（整组保留）', () {
    final scene = Scene()
        .addElement(groupedText('t1', 'grp-1'))
        .addElement(groupedText('t2', 'grp-1', x: 400))
        .addElement(groupedText('t3', 'grp-2', x: 700));
    final revision = SceneRevision(
      epoch: 0,
      revision: 3,
      fingerprint: SceneFingerprint.of(scene),
    );
    TextBlockSpec spec(String text) => TextBlockSpec(
      text: text,
      fontFamily: 'Excalifont',
      fontSize: 20,
      lineHeight: 1.25,
    );
    LayoutBlock typedBlock(String id, String ref) => LayoutBlock(
      id: id,
      kind: LayoutBlockKind.paragraph,
      sourceRefs: [ref],
      orderIndex: 0,
      keepTogether: false,
      textOrigin: LayoutTextOrigin.typed,
      text: spec('text $ref'),
    );
    final preservedBlock = LayoutBlock(
      id: 'b3',
      kind: LayoutBlockKind.preserved,
      sourceRefs: ['t3'],
      orderIndex: 2,
      keepTogether: true,
    );
    final assembly = LayoutBlockAssembly(
      blocks: [typedBlock('b1', 't1'), typedBlock('b2', 't2'), preservedBlock],
      relationships: const [],
      atomicGroups: const [],
      documentConsumedSourceIds: const ['t1', 't2'],
      documentPreservedSourceIds: const ['t3'],
    );
    final placement = FlowPlacementSuccess(
      placed: [
        PlacedBlock(
          blockId: 'b1',
          rect: rect(0, 0),
          columnIndex: 0,
          lineCount: 1,
          appliedFontSize: 20,
          shrunk: false,
        ),
        PlacedBlock(
          blockId: 'b2',
          rect: rect(0, 100),
          columnIndex: 0,
          lineCount: 1,
          appliedFontSize: 20,
          shrunk: false,
        ),
      ],
      usedHeights: const [],
    );
    final outcome = SmartLayoutCandidateMaterializer.materialize(
      baseScene: scene,
      baseRevision: revision,
      sourceCoverage: SourceCoverageLedger.pending(const [
        't1',
        't2',
        't3',
      ]),
      assembly: assembly,
      placement: placement,
      timestampMs: 1000,
    );
    expect(outcome, isA<PatchMaterializationFailure>());
    final failure = outcome as PatchMaterializationFailure;
    expect(failure.kind, PatchMaterializationFailureKind.sharedClosureGroup);
    expect(failure.blockId, 'b2');
  });
}
