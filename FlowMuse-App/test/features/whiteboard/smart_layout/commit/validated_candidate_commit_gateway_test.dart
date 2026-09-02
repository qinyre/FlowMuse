import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/commit/validated_candidate_commit_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/hard_constraint_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(String id, {double x = 10}) => RectangleElement(
    id: ElementId(id),
    x: x,
    y: 10,
    width: 40,
    height: 40,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  TextElement text(String id, {double x = 20, double w = 200}) => TextElement(
    id: ElementId(id),
    x: x,
    y: 40,
    width: w,
    height: 28,
    text: '正文内容',
    fontSize: 20,
    fontFamily: 'Excalifont',
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  final page = Bounds.fromLTWH(0, 0, 800, 600);

  /// 真实编辑器链：controller→gateway→tracker（与产品接线同构）。
  (MarkdrawController, SmartLayoutEditorGateway, SceneRevisionTracker)
  setUpEditor({bool autoDispose = true}) {
    final controller = MarkdrawController();
    if (autoDispose) addTearDown(controller.dispose);
    controller.applyResult(AddElementResult(rect('s1')));
    controller.applyResult(AddElementResult(text('t1')));
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    addTearDown(tracker.dispose);
    return (controller, editor, tracker);
  }

  SourceCoverageLedger ledger() => SourceCoverageLedger.pending(const [
    's1',
    't1',
  ]).markConsumed(const ['s1', 't1']);

  /// 经完整门禁流水线构建候选（真实 reduce/render/metrics/hard）。
  Future<ValidatedCandidate> buildCandidate(
    MarkdrawController controller,
    SceneRevisionTracker tracker,
  ) async {
    final base = controller.currentScene;
    final patch =
        (SmartLayoutScenePatchBuilder(
              baseScene: base,
              baseRevision: tracker.current,
              sourceCoverage: ledger(),
            )..updateElement(
              text('t1', x: 100, w: 220).copyWith(version: 2),
              baseVersion: 1,
            ))
            .build();
    final result = await ValidatedCandidatePipeline.run(
      baseScene: base,
      pageContentBounds: page,
      candidates: [
        CandidateGateInput(
          candidateId: 'c1',
          diversityKey: 'single',
          patch: patch,
          metricInput: LayoutMetricInput(
            assembly: LayoutBlockAssembly(
              blocks: [
                LayoutBlock(
                  id: 'b1',
                  kind: LayoutBlockKind.paragraph,
                  sourceRefs: const ['t1'],
                  orderIndex: 0,
                  keepTogether: false,
                  text: const TextBlockSpec(
                    text: '正文内容',
                    fontFamily: 'Excalifont',
                    fontSize: 20,
                    lineHeight: 1.25,
                  ),
                ),
              ],
              relationships: const [],
              atomicGroups: const [],
              documentConsumedSourceIds: const ['t1'],
              documentPreservedSourceIds: const ['s1'],
            ),
            placed: [
              PlacedBlock(
                blockId: 'b1',
                rect: LayoutRect(left: 100, top: 40, width: 220, height: 28),
                columnIndex: 0,
                lineCount: 1,
                appliedFontSize: 20,
                shrunk: false,
              ),
            ],
            columnRects: [
              LayoutRect(left: 40, top: 40, width: 360, height: 500),
            ],
            preservedRects: const {},
            originalBounds: {
              'b1': LayoutRect(left: 20, top: 40, width: 200, height: 28),
            },
            contentHeight: 500,
            hardValidated: true,
          ),
          veto: const VetoVerdict(kinds: [], reasons: []),
        ),
      ],
      profile: LayoutProfile.readability,
    );
    return result.top.single;
  }

  test('基线未变：直接提交、preview=commit、History 精确一次', () async {
    final (controller, editor, tracker) = setUpEditor();
    final candidate = await buildCandidate(controller, tracker);
    addTearDown(candidate.dispose);
    final before = controller.currentScene;

    final gateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final result = gateway.commit(candidate);
    expect(result, isA<HistoryCommitted>());
    final committed = result as HistoryCommitted;
    expect(committed.redispatched, isFalse);

    // preview=commit：提交后场景与候选归约产物等价（排除提交域元数据）。
    final committedText = controller.currentScene.elements.firstWhere(
      (e) => e.id.value == 't1',
    );
    final draftText = committed.reduced.scene.elements.firstWhere(
      (e) => e.id.value == 't1',
    );
    expect(committedText.x, draftText.x);
    expect(committedText.version, draftText.version);
    expect(
      (committedText as TextElement).fontSize,
      (draftText as TextElement).fontSize,
    );

    // History 精确：一次 undo 回提交前。
    controller.undo();
    expect(
      controller.currentScene.elements.firstWhere((e) => e.id.value == 't1').x,
      before.elements.firstWhere((e) => e.id.value == 't1').x,
    );
  });

  test('写集相交：远端改写 t1 → 拒绝且 Scene/History 零副作用', () async {
    final (controller, editor, tracker) = setUpEditor();
    final candidate = await buildCandidate(controller, tracker);
    addTearDown(candidate.dispose);

    // 远端改写写集元素 t1（版本前进）。
    controller.applyResult(
      UpdateElementResult(text('t1', x: 55).copyWith(version: 99)),
    );
    final afterRemote = controller.currentScene;

    final gateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final result = gateway.commit(candidate);
    expect(result, isA<HistoryCommitRejected>());
    final rejected = result as HistoryCommitRejected;
    expect(rejected.kind, CommitRejectionKind.writeSetConflict);

    // 零副作用：场景实例未变；历史栈无智能排版空事务
    //（applyResult 不入栈，undo 对空栈是 no-op，远端编辑保持在场）。
    expect(identical(controller.currentScene, afterRemote), isTrue);
    controller.undo();
    expect(
      controller.currentScene.elements.firstWhere((e) => e.id.value == 't1').x,
      55,
      reason: '无空事务入栈：undo 不改远端编辑结果',
    );
  });

  test('写集不相交：远端改写 s1 → 基于新 revision 重派一次提交成功', () async {
    final (controller, editor, tracker) = setUpEditor();
    final candidate = await buildCandidate(controller, tracker);
    addTearDown(candidate.dispose);

    // 远端改写非写集元素 s1。
    controller.applyResult(
      UpdateElementResult(rect('s1', x: 33).copyWith(version: 9)),
    );
    final revisionAfterRemote = tracker.current;

    final gateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final result = gateway.commit(candidate);
    expect(result, isA<HistoryCommitted>());
    final committed = result as HistoryCommitted;
    expect(committed.redispatched, isTrue);
    expect(
      committed.baseRevision.fingerprint,
      revisionAfterRemote.fingerprint,
      reason: '重派基线是远端变化后的新 revision（提交本身会再推进）',
    );
    // 两个改动都在场：远端 s1 与智能排版 t1。
    expect(
      controller.currentScene.elements.firstWhere((e) => e.id.value == 's1').x,
      33,
    );
    expect(
      controller.currentScene.elements.firstWhere((e) => e.id.value == 't1').x,
      100,
    );
  });

  test('编辑器释放：拒绝提交', () async {
    final (controller, editor, tracker) = setUpEditor(autoDispose: false);
    final candidate = await buildCandidate(controller, tracker);
    final gateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    // 手动释放（controller.dispose 非幂等，本用例自管生命周期）。
    controller.dispose();
    final result = gateway.commit(candidate);
    expect(result, isA<HistoryCommitRejected>());
    expect(
      (result as HistoryCommitRejected).kind,
      CommitRejectionKind.editorDisposed,
    );
  });

  test('证据断链：装配后 metrics/快照不符 → 拒绝', () async {
    final (controller, editor, tracker) = setUpEditor();
    final a = await buildCandidate(controller, tracker);
    addTearDown(a.dispose);
    // 不相交远端改动后重建候选 b：其渲染层（s1 位置）与 a 不同，
    // digest 必然不同（确定性本身不允许同输入产生不同 digest）。
    controller.applyResult(
      UpdateElementResult(rect('s1', x: 33).copyWith(version: 9)),
    );
    final b = await buildCandidate(controller, tracker);
    addTearDown(b.dispose);

    // 用 a 的证据与 b 的快照重新装配（同 baseRevision，digest 不一致）。
    final tampered = ValidatedCandidate.assemble(
      candidateId: 'tampered',
      diversityKey: a.diversityKey,
      patch: a.patch,
      reduced: a.reduced,
      snapshot: b.snapshot,
      metrics: a.metrics,
      vector: a.vector,
      score: a.score,
      hardReport: const HardConstraintReport(violations: []),
    );
    final gateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final result = gateway.commit(tampered);
    expect(result, isA<HistoryCommitRejected>());
    expect(
      (result as HistoryCommitRejected).kind,
      CommitRejectionKind.provenanceBroken,
    );
    // b 的快照由 tampered 持有；a/b 各自 dispose 防泄漏。
    tampered.dispose();
  });
}
