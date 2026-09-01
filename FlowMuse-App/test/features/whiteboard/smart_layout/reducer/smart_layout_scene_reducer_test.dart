import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_preview_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(String id, {double x = 10, int version = 1}) =>
      RectangleElement(
        id: ElementId(id),
        x: x,
        y: 10,
        width: 40,
        height: 40,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: version,
      );

  TextElement text(String id, {double x = 5, int version = 1}) => TextElement(
    id: ElementId(id),
    x: x,
    y: 5,
    width: 30,
    height: 20,
    text: '正文',
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: version,
  );

  ImageFile png(List<int> bytes) =>
      ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList(bytes));

  Scene baseScene() => Scene().addElement(rect('s1')).addElement(text('t1'));

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(scene),
  );

  SourceCoverageLedger ledger() => SourceCoverageLedger.pending(const [
    's1',
    't1',
  ]).markConsumed(const ['t1']).markPreserved(const ['s1']);

  SmartLayoutScenePatchBuilder builderFor(Scene scene) =>
      SmartLayoutScenePatchBuilder(
        baseScene: scene,
        baseRevision: revisionOf(scene),
        sourceCoverage: ledger(),
      );

  /// 完整 patch：remove t1 / update s1 / add n1 / file / doc / selection。
  SmartLayoutScenePatch fullPatch() {
    final scene = baseScene();
    return (builderFor(scene)
          ..removeElement('t1', baseVersion: 1, versionNonce: 501)
          ..updateElement(rect('s1', x: 999, version: 2), baseVersion: 1)
          ..addElement(text('n1', version: 1))
          ..addFile('img1', png(const [1, 2, 3]))
          ..replaceSmartLayoutDocument(
            SmartLayoutDocument(version: 3, blocks: const [], generatedAt: 42),
          )
          ..setSelectionIntent(const ['s1', 'n1']))
        .build();
  }

  test('确定性归约：固定序折叠、软删契约、输入不可变', () {
    final base = baseScene();
    final outcome = SmartLayoutPreviewAdapter.draft(
      base: base,
      patch: fullPatch(),
    );
    expect(outcome, isA<ReducedScene>());
    final reduced = outcome as ReducedScene;
    final scene = reduced.scene;

    // remove：软删 + patch 版本契约。
    final removed = scene.elements.firstWhere((e) => e.id.value == 't1');
    expect(removed.isDeleted, isTrue);
    expect(removed.version, 2);
    expect(removed.versionNonce, 501);

    // update：完整负载原样替换（patch nonce 保留，无编辑器 bump）。
    final updated = scene.elements.firstWhere((e) => e.id.value == 's1');
    expect(updated.x, 999);
    expect(updated.version, 2);
    expect(updated.versionNonce, 11, reason: 'patch 负载原样生效');

    // add：追加存在且活跃。
    final added = scene.elements.firstWhere((e) => e.id.value == 'n1');
    expect(added.version, 1);

    // file/document 折叠。
    expect(scene.files.containsKey('img1'), isTrue);
    expect(scene.smartLayout?.version, 3);

    // selection 意图暴露（不进 Scene）。
    expect(reduced.selectionIds, {ElementId('s1'), ElementId('n1')});
    expect(reduced.softDeletedIds, ['t1']);
    expect(reduced.updatedIds, ['s1']);
    expect(reduced.addedIds, ['n1']);

    // 输入不可变：base 元素仍活跃、版本未动。
    expect(
      base.elements.firstWhere((e) => e.id.value == 't1').isDeleted,
      isFalse,
    );
    expect(base.elements.firstWhere((e) => e.id.value == 's1').version, 1);
    expect(base.files.isEmpty, isTrue);
    expect(base.smartLayout, isNull);
  });

  test('失败原子：目标失配整体失败，无部分结果', () {
    final patch = fullPatch();
    // base 缺 t1/s1（构造另一 base）：update/remove 失配、add 冲突。
    final other = Scene()
        .addElement(rect('s1', version: 1))
        .addElement(text('n1', version: 1));

    final noTarget = SmartLayoutSceneReducer.apply(base: other, patch: patch);
    expect(
      noTarget,
      isA<SceneReduceFailure>()
          .having(
            (f) => f.kind,
            'kind',
            SceneReduceFailureKind.removeTargetMissing,
          )
          .having((f) => f.subjectId, 'subject', 't1'),
    );

    // add 冲突：对包含 n1 的 base 归约只含 add 的 patch。
    final addOnlyPatch = (builderFor(
      baseScene(),
    )..addElement(text('zz', version: 1))).build();
    final conflicting = Scene().addElement(text('zz', version: 1));
    final conflict = SmartLayoutSceneReducer.apply(
      base: conflicting,
      patch: addOnlyPatch,
    );
    expect(
      conflict,
      isA<SceneReduceFailure>().having(
        (f) => f.kind,
        'kind',
        SceneReduceFailureKind.addTargetConflicts,
      ),
    );
  });

  test('Draft 可重放：写集完好时同一 patch 在远端无关变更后重放成功', () {
    final patch = fullPatch();
    // 远端新增无关元素（写集外），重放同一 patch。
    final evolved = baseScene().addElement(rect('remote-9', version: 1));
    final replay = SmartLayoutPreviewAdapter.draft(base: evolved, patch: patch);
    expect(replay, isA<ReducedScene>());
    final scene = (replay as ReducedScene).scene;
    expect(
      scene.elements.firstWhere((e) => e.id.value == 'remote-9').isDeleted,
      isFalse,
      reason: '无关元素不受影响',
    );
    expect(
      scene.elements.firstWhere((e) => e.id.value == 't1').isDeleted,
      isTrue,
    );
    expect(scene.elements.firstWhere((e) => e.id.value == 's1').x, 999);

    // 写集元素被远端删除后重放：显式失败（不静默跳过）。
    final broken = Scene().addElement(rect('s1', version: 1));
    final failed = SmartLayoutPreviewAdapter.draft(base: broken, patch: patch);
    expect(failed, isA<SceneReduceFailure>());
  });

  test('preview=commit：同一归约结果经 gateway 提交后深度等价（排除提交域元数据）', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    // 提交前给场景摆入 base 内容（真实路径）。
    controller.applyResult(AddElementResult(rect('s1')));
    controller.applyResult(AddElementResult(text('t1')));

    final gateway = SmartLayoutEditorGateway(controller);
    final base = controller.currentScene;
    // patch 必须基于当前控制器场景（指纹一致）。
    final patch =
        (SmartLayoutScenePatchBuilder(
                baseScene: base,
                baseRevision: SceneRevision(
                  epoch: 0,
                  revision: 4,
                  fingerprint: SceneFingerprint.of(base),
                ),
                sourceCoverage: ledger(),
              )
              ..removeElement('t1', baseVersion: 1, versionNonce: 501)
              ..updateElement(rect('s1', x: 999, version: 2), baseVersion: 1)
              ..addElement(text('n1', version: 1))
              ..addFile('img1', png(const [1, 2, 3]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 3,
                  blocks: const [],
                  generatedAt: 42,
                ),
              )
              ..setSelectionIntent(const ['s1', 'n1']))
            .build();

    final reduced =
        SmartLayoutSceneReducer.apply(base: base, patch: patch) as ReducedScene;

    final before = SceneFingerprint.of(controller.currentScene);
    gateway.commitValidated(reduced.commitResult);
    final after = SceneFingerprint.of(controller.currentScene);

    expect(after == before, isFalse, reason: '提交真实生效');

    // 元素级等价：负载排除 (versionNonce, updated) 深度相等 + version 一致。
    final committed = controller.currentScene;
    final draft = reduced.scene;
    expect(committed.elements.length, draft.elements.length);
    for (final draftElement in draft.elements) {
      final committedElement = committed.elements.firstWhere(
        (e) => e.id == draftElement.id,
      );
      expect(
        committedElement.version,
        draftElement.version,
        reason: '${draftElement.id}: version 数字一致（编辑器统一 bump）',
      );
      final a = _payloadWithoutCommitMetadata(draftElement);
      final b = _payloadWithoutCommitMetadata(committedElement);
      expect(b, a, reason: '${draftElement.id}: 负载深度等价（除提交域元数据）');
    }
    expect(committed.files.keys, draft.files.keys);
    expect(committed.smartLayout?.version, draft.smartLayout?.version);
    expect(
      controller.selectedElements.map((e) => e.id).toSet(),
      reduced.selectionIds,
      reason: '选择意图经 commitResult 一致落地',
    );
  });

  test('undo/redo 精确且无重复 push：一次 undo 回提交前、redo 回提交后', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(AddElementResult(rect('s1')));
    controller.applyResult(AddElementResult(text('t1')));
    final gateway = SmartLayoutEditorGateway(controller);

    final base = controller.currentScene;
    final patch =
        (SmartLayoutScenePatchBuilder(
                baseScene: base,
                baseRevision: SceneRevision(
                  epoch: 0,
                  revision: 4,
                  fingerprint: SceneFingerprint.of(base),
                ),
                sourceCoverage: ledger(),
              )
              ..removeElement('t1', baseVersion: 1, versionNonce: 501)
              ..updateElement(rect('s1', x: 999, version: 2), baseVersion: 1))
            .build();
    final reduced =
        SmartLayoutSceneReducer.apply(base: base, patch: patch) as ReducedScene;

    final beforeCommit = SceneFingerprint.of(controller.currentScene);
    gateway.commitValidated(reduced.commitResult);
    final afterCommit = SceneFingerprint.of(controller.currentScene);

    // commitResult 是单一 CompoundResult（一次 applyResult 一次事务）。
    expect(reduced.commitResult, isA<CompoundResult>());

    controller.undo();
    expect(
      SceneFingerprint.of(controller.currentScene),
      beforeCommit,
      reason: '单次 undo 精确回到提交前（无重复 push）',
    );
    controller.redo();
    expect(
      SceneFingerprint.of(controller.currentScene),
      afterCommit,
      reason: 'redo 精确回到提交后',
    );
  });

  test('commitResult 固定序：files→document→remove→update→add→selection', () {
    final reduced =
        SmartLayoutSceneReducer.apply(base: baseScene(), patch: fullPatch())
            as ReducedScene;
    final compound = reduced.commitResult as CompoundResult;
    final kinds = compound.results.map((r) {
      if (r is AddFileResult) return 'file';
      if (r is SetSmartLayoutResult) return 'doc';
      if (r is RemoveElementResult) return 'remove';
      if (r is UpdateElementResult) return 'update';
      if (r is AddElementResult) return 'add';
      if (r is SetSelectionResult) return 'selection';
      throw StateError('未知结果类型: $r');
    }).toList();
    expect(kinds, ['file', 'doc', 'remove', 'update', 'add', 'selection']);
    // update 元素以 baseVersion 传入（编辑器 bump 后= baseVersion+1=契约值）。
    final update = compound.results
        .whereType<UpdateElementResult>()
        .single
        .element;
    expect(update.id.value, 's1');
    expect(update.version, 1, reason: '回退到 base 版本，编辑器 bump 落到 2');
  });
}

/// 元素负载（排除 versionNonce/updated 提交域元数据）。
Map<String, Object?> _payloadWithoutCommitMetadata(Element element) {
  final json =
      Map<String, Object?>.from(ExcalidrawJsonCodec.elementToJson(element))
        ..remove('versionNonce')
        ..remove('updated');
  return json;
}
