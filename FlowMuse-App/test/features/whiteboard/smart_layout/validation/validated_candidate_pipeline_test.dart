import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/correction/correction_patch_applier.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/scene_metrics_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/correction_rerun_coordinator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/hard_constraint_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/layout_scorer.dart';
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

  TextElement text(String id, {double x = 20, double w = 200}) =>
      TextElement(
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

  Scene baseScene() =>
      Scene().addElement(rect('s1')).addElement(text('t1'));

  SourceCoverageLedger ledger() =>
      SourceCoverageLedger.pending(const ['s1', 't1'])
          .markConsumed(const ['s1', 't1']);

  SmartLayoutScenePatchBuilder builderFor(Scene scene) =>
      SmartLayoutScenePatchBuilder(
        baseScene: scene,
        baseRevision: SceneRevision(
          epoch: 0,
          revision: 7,
          fingerprint: SceneFingerprint.of(scene),
        ),
        sourceCoverage: ledger(),
      );

  /// 合法 patch：t1 移动到页内新位置。
  SmartLayoutScenePatch goodPatch(String textId, Scene scene) => (builderFor(
        scene,
      )
        ..updateElement(
          text(textId, x: 100, w: 220).copyWith(version: 2),
          baseVersion: 1,
        ))
      .build();

  LayoutMetricInput metricInput(bool hardValidated) => LayoutMetricInput(
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
    columnRects: [LayoutRect(left: 40, top: 40, width: 360, height: 500)],
    preservedRects: const {},
    originalBounds: {
      'b1': LayoutRect(left: 20, top: 40, width: 200, height: 28),
    },
    contentHeight: 500,
    hardValidated: hardValidated,
  );

  const noVeto = VetoVerdict(kinds: [], reasons: []);

  CandidateGateInput candidate(
    String id,
    String key,
    Scene scene, {
    bool hardValidated = true,
    VetoVerdict veto = noVeto,
  }) => CandidateGateInput(
    candidateId: id,
    diversityKey: key,
    patch: goodPatch('t1', scene),
    metricInput: metricInput(hardValidated),
    veto: veto,
  );

  test('完整门禁流水线：Top 封装、证据链齐全、渲染资源可释放', () async {
    final scene = baseScene();
    final result = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [candidate('c1', 'single', scene)],
      profile: LayoutProfile.readability,
    );
    expect(result.hasCandidates, isTrue);
    expect(result.top, hasLength(1), reason: '不足 3 不补');
    final top = result.top.single;
    expect(top.candidateId, 'c1');
    expect(top.ledgerHash, isNotEmpty);
    expect(top.metrics.renderedSceneDigest, isNotEmpty);
    expect(top.vector.values.isNotEmpty, isTrue);
    expect(top.score.entries, isNotEmpty);
    top.dispose();
  });

  test('多样性 Top3：同结构只留最高分代表、不足 3 不补', () async {
    final scene = baseScene();
    // 三候选同结构（同 diversityKey）→ 只有 1 个入选。
    final sameStructure = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [
        candidate('c1', 'single', scene),
        candidate('c2', 'single', scene),
        candidate('c3', 'single', scene),
      ],
      profile: LayoutProfile.readability,
    );
    expect(sameStructure.top, hasLength(1));
    for (final c in sameStructure.top) {
      c.dispose();
    }

    // 两种结构 → 恰好 2 个（不凑第 3）。
    final twoStructures = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [
        candidate('c1', 'single', scene),
        candidate('c2', 'two-column', scene),
      ],
      profile: LayoutProfile.readability,
    );
    expect(twoStructures.top, hasLength(2));
    expect(
      twoStructures.top.map((c) => c.diversityKey).toSet(),
      {'single', 'two-column'},
    );
    for (final c in twoStructures.top) {
      c.dispose();
    }
  });

  test('fail closed：硬门禁失败与反投机否决进入淘汰记录', () async {
    final scene = baseScene();
    // 越界 patch：s1 移出页内容区 → 硬门禁失败。
    final badPatch = (builderFor(scene)
          ..updateElement(
            rect('s1', x: 5000).copyWith(version: 2),
            baseVersion: 1,
          ))
        .build();
    final vetoed = const VetoVerdict(
      kinds: [AntiGamingVetoKind.noOp],
      reasons: ['mean move below epsilon'],
    );
    final result = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [
        CandidateGateInput(
          candidateId: 'bad',
          diversityKey: 'single',
          patch: badPatch,
          metricInput: metricInput(true),
          veto: noVeto,
        ),
        candidate('vetoed', 'single', scene, veto: vetoed),
      ],
      profile: LayoutProfile.readability,
    );
    expect(result.hasCandidates, isFalse);
    expect(result.infeasibleExplanation, isNotNull);
    final codes = result.rejections.map((r) => r.candidateId).toList();
    expect(codes, containsAll(['bad', 'vetoed']));
    final hard = result.rejections.firstWhere((r) => r.candidateId == 'bad');
    expect(
      hard.reasonCodes.any((c) => c.startsWith('hard:')),
      isTrue,
      reason: '越界候选必须以硬违规淘汰',
    );
    final vetoRejection = result.rejections.firstWhere(
      (r) => r.candidateId == 'vetoed',
    );
    expect(vetoRejection.reasonCodes, contains('noOp'));
    expect(result.infeasibleExplanation!.aggregatedReasons, isNotEmpty);
  });

  test('assemble fail closed：硬门禁未过/provenance 断链拒绝构造', () async {
    final scene = baseScene();
    final result = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [candidate('c1', 'single', scene)],
      profile: LayoutProfile.readability,
    );
    final ok = result.top.single;
    addTearDown(ok.dispose);
    final vector = ok.vector;
    final score = ok.score;

    // 硬门禁失败报告。
    expect(
      () => ValidatedCandidate.assemble(
        candidateId: 'x',
        diversityKey: 'k',
        patch: ok.patch,
        reduced: ok.reduced,
        snapshot: ok.snapshot,
        metrics: ok.metrics,
        vector: vector,
        score: score,
        hardReport: const HardConstraintReport(
          violations: [HardConstraintViolation(
            kind: HardConstraintKind.pageBounds,
            subjectIds: ['x'],
            detail: '',
          )],
        ),
      ),
      throwsStateError,
    );

    // provenance 断链（他轮 revision 的真实构造 metrics）。
    final forged = SceneMetricsSnapshot(
      coverage: ok.metrics.coverage,
      relationCompliance: ok.metrics.relationCompliance,
      orderPairAccuracy: ok.metrics.orderPairAccuracy,
      visualBoundsViolations: ok.metrics.visualBoundsViolations,
      sceneRevision: 999,
      rendererFingerprint: ok.metrics.rendererFingerprint,
      renderedSceneDigest: ok.metrics.renderedSceneDigest,
      factsFingerprint: ok.metrics.factsFingerprint,
    );
    expect(
      () => ValidatedCandidate.assemble(
        candidateId: 'x',
        diversityKey: 'k',
        patch: ok.patch,
        reduced: ok.reduced,
        snapshot: ok.snapshot,
        metrics: forged,
        vector: vector,
        score: score,
        hardReport: const HardConstraintReport(violations: []),
      ),
      throwsStateError,
    );
  });

  test('LayoutScorer：并列按 id 字典序破平（确定性）', () {
    final vector = LayoutMetricVector(
      values: {for (final id in LayoutMetricId.values) id: 0.8},
      factsFingerprint: 'facts-fixture',
    );
    final candidates = [
      ScoreCandidateFacts(
        candidateId: 'b',
        diversityKey: 'k2',
        vector: vector,
        veto: noVeto,
      ),
      ScoreCandidateFacts(
        candidateId: 'a',
        diversityKey: 'k1',
        vector: vector,
        veto: noVeto,
      ),
    ];
    final result = LayoutScorer.rank(
      candidates: candidates,
      profile: LayoutProfile.readability,
    );
    expect(result.ranked.first.facts.candidateId, 'a');
  });

  test('CorrectionRerunCoordinator：旧候选全失效释放、scope 传递确定、双跑一致',
      () async {
    final scene = baseScene();
    final first = await ValidatedCandidatePipeline.run(
      baseScene: scene,
      pageContentBounds: page,
      candidates: [candidate('c1', 'single', scene)],
      profile: LayoutProfile.readability,
    );
    final previous = first.top.single;

    final scopes = <Set<String>>[];
    Future<List<ValidatedCandidate>> chain(Set<String> scope) async {
      scopes.add(scope);
      final rerun = await ValidatedCandidatePipeline.run(
        baseScene: scene,
        pageContentBounds: page,
        candidates: [candidate('c1-rerun', 'single', scene)],
        profile: LayoutProfile.readability,
      );
      return rerun.top;
    }

    final coordinator = CorrectionRerunCoordinator(chain: chain);
    final affected = AffectedSourceSet(
      regionIds: const {'r1'},
      strokeSourceIds: const {'i1', 'i2'},
      renderAssetKeys: const {'file-1|i1'},
      cropKeys: const {'file-1|i1|crop'},
    );
    final result = await coordinator.rerun(
      previousCandidates: [previous],
      affected: affected,
    );

    expect(result.plan.invalidatedCandidateIds, ['c1'], reason: '旧候选全失效');
    expect(result.plan.affectedSourceIds, {'i1', 'i2'});
    expect(result.plan.assetKeys, {'file-1|i1'});
    expect(result.newCandidates, hasLength(1));
    expect(result.newCandidates.single.candidateId, 'c1-rerun');
    expect(scopes, [
      {'i1', 'i2'},
    ], reason: 'scope 确定传递');
    for (final c in result.newCandidates) {
      c.dispose();
    }
  });
}

