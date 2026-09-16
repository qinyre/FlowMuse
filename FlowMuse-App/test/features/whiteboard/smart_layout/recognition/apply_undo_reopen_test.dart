import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/candidate_patch_materializer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';

import 'structure_test_helpers.dart';

/// §11 R6 应用/撤销/保存重开：识别链（适配→块装配→物化）产出的 patch
/// 经 reducer 原子应用；语义撤销恢复 base 内容；重开后提取快照健康。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  /// 全体元素打 pageId（快照提取的页归属口径）。
  Scene pageScene(Scene scene) {
    var withData = scene;
    for (final element in scene.elements) {
      withData = withData.upsertRemoteElements([
        element.copyWith(
          customData: const {
            'flowMuse': {'pageId': 'p1'},
          },
        ),
      ]);
    }
    return withData;
  }

  test('应用→撤销→重开：识别 patch 全链不变量', () async {
    final result = await sessionOf(
      const [RegionSpec(regionId: 'r:ink', top: 100, left: 0, text: '手写内容转写')],
      scene: Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 0,
          width: 200,
          height: 40,
          text: '原生文本',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          version: 1,
        ),
      ),
    );
    final base = pageScene(result.scene);
    final assembly = adapter.assemble(
      result,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );

    final snapshot = const SnapshotExtractor().extract(
      scene: base,
      pageId: 'p1',
      sceneRevision: SceneRevision(
        epoch: 0,
        revision: 5,
        fingerprint: SceneFingerprint.of(base),
      ),
    );
    final blockAssembly = const LayoutBlockAssembler().assemble(
      document: assembly.document,
      snapshot: snapshot,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    expect(blockAssembly.ledgerConserved, isTrue);

    final inkBlockId = 'ink:r:ink';
    final typedBlockId = 'native:text-1';
    final placement = FlowPlacementSuccess(
      placed: [
        PlacedBlock(
          blockId: inkBlockId,
          rect: LayoutRect(left: 0, top: 0, width: 240, height: 50),
          columnIndex: 0,
          lineCount: 2,
          appliedFontSize: tokens.bodySize,
          shrunk: false,
        ),
        PlacedBlock(
          blockId: typedBlockId,
          rect: LayoutRect(left: 0, top: 80, width: 240, height: 40),
          columnIndex: 0,
          lineCount: 1,
          appliedFontSize: tokens.bodySize,
          shrunk: false,
        ),
      ],
      usedHeights: const [],
    );
    final outcome = SmartLayoutCandidateMaterializer.materialize(
      baseScene: base,
      baseRevision: snapshot.sceneRevision,
      sourceCoverage: snapshot.sourceCoverage,
      assembly: blockAssembly,
      placement: placement,
      timestampMs: 2000,
      pageId: 'p1',
    );
    expect(outcome, isA<PatchMaterializationSuccess>(), reason: '$outcome');
    final patch = (outcome as PatchMaterializationSuccess).patch;

    // ---- 应用：reducer 原子折叠 ----
    final reduced = SmartLayoutSceneReducer.apply(base: base, patch: patch);
    expect(reduced, isA<ReducedScene>());
    final applied = (reduced as ReducedScene).scene;
    final activeById = {
      for (final element in applied.activeElements) element.id.value: element,
    };
    expect(activeById.containsKey('s-ink'), isFalse, reason: '转写源笔迹软删');
    expect(activeById.containsKey('text-1'), isTrue, reason: 'typed 变换不删除');
    final added = applied.activeElements
        .where(
          (e) => e.id.value.startsWith(
            SmartLayoutCandidateMaterializer.addedIdPrefix,
          ),
        )
        .toList();
    expect(added, hasLength(1));
    final addedText = added.single as TextElement;
    expect(addedText.text, '手写内容转写');
    expect(addedText.fontSize, tokens.bodySize, reason: '§8.2 字号档经块组装透传');
    final movedTyped = activeById['text-1'] as TextElement;
    expect(movedTyped.x, 0);
    expect(movedTyped.y, 80, reason: 'typed 移到放置盒');
    expect(movedTyped.fontSize, tokens.bodySize, reason: '字号显式对齐放置档');

    // ---- 撤销（语义恢复；版本计数器按编辑器惯例单调不回滚）----
    final baseById = {
      for (final element in base.elements) element.id.value: element,
    };
    var undone = applied;
    undone = undone.upsertRemoteElements([
      for (final op in patch.adds)
        op.element.copyWith(isDeleted: true, version: op.element.version + 1),
      for (final op in patch.updates)
        baseById[op.elementId]!.copyWith(version: op.element.version + 1),
      for (final op in patch.removes)
        baseById[op.elementId]!.copyWith(
          isDeleted: false,
          version: op.newVersion + 1,
        ),
    ]);
    final undoneActiveIds = {
      for (final element in undone.activeElements) element.id.value,
    };
    final baseActiveIds = {
      for (final element in base.activeElements) element.id.value,
    };
    expect(undoneActiveIds, baseActiveIds, reason: '撤销恢复 base 活动元素集');
    final restoredInk = undone.activeElements.firstWhere(
      (e) => e.id.value == 's-ink',
    );
    expect(restoredInk, isA<FreedrawElement>());
    final restoredTyped =
        undone.activeElements.firstWhere((e) => e.id.value == 'text-1')
            as TextElement;
    final baseTyped = baseById['text-1'] as TextElement;
    expect(restoredTyped.text, baseTyped.text);
    expect(restoredTyped.x, baseTyped.x);
    expect(restoredTyped.y, baseTyped.y);
    expect(restoredTyped.fontSize, baseTyped.fontSize);

    // ---- 保存重开：应用后的场景重新提取快照健康 ----
    final reopened = const SnapshotExtractor().extract(
      scene: applied,
      pageId: 'p1',
      sceneRevision: SceneRevision(
        epoch: 0,
        revision: 6,
        fingerprint: SceneFingerprint.of(applied),
      ),
    );
    expect(
      reopened.objects.map((o) => o.sourceId),
      containsAll(['text-1', addedText.id.value]),
      reason: '新文本带 pageId 归属，重开可见',
    );
    expect(
      reopened.inkStrokes.map((s) => s.sourceId),
      isNot(contains('s-ink')),
      reason: '软删笔迹不属于页面内容',
    );
    expect(reopened.sourceCoverage.sourceCount, 2);
  });
}
