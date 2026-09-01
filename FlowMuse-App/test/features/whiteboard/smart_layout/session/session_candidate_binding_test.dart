import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/correction/correction_patch_applier.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';

const _okBody = '''
{"protocolVersion":3,"requestId":"req-1","regions":[
 {"id":"g1","role":"title","sourceIds":["s1"],"readingOrder":0,"confidence":0.9,"relations":[]}
],"warnings":[]}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final page = Bounds.fromLTWH(0, 0, 800, 600);

  AffectedSourceSet emptyCorrection(RegionCorrectionIntent intent) =>
      AffectedSourceSet(
        regionIds: const {},
        strokeSourceIds: const {},
        renderAssetKeys: const {},
        cropKeys: const {},
      );

  Future<List<ValidatedCandidate>> emptyRerun(Set<String> scope) async =>
      const [];

  (ProviderContainer, MarkdrawController, SmartLayoutSession, StringBuffer)
  setUpContainerWithController(
    MarkdrawController controller, {
    AffectedSourceSet Function(RegionCorrectionIntent intent)? correction,
    Future<List<ValidatedCandidate>> Function(Set<String> scope)? rerun,
  }) {
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('s1'),
          x: 10,
          y: 10,
          width: 40,
          height: 40,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        TextElement(
          id: ElementId('t1'),
          x: 20,
          y: 40,
          width: 200,
          height: 28,
          text: '正文内容',
          fontSize: 20,
          fontFamily: 'Excalifont',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      ),
    );
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    addTearDown(tracker.dispose);
    final session = SmartLayoutSession(
      editor: editor,
      revisions: tracker,
      pageId: 'page-1',
    );
    final repo = V3AnalysisRepository(
      http: SmartLayoutHttpGateway(
        serverUri: Uri.parse('http://127.0.0.1:48931'),
        post:
            ({
              required url,
              headers = const {},
              required body,
              connectTimeoutMs = 8000,
              readTimeoutMs = 15000,
              cancelToken,
            }) async => NativeHttpResponse(statusCode: 200, body: _okBody),
      ),
      session: session,
    );
    final rerunCalls = StringBuffer();
    final container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          SmartLayoutSessionDependencies(
            session: session,
            repository: repo,
            requestBuilder: (ticket) async =>
                SmartLayoutV3Request.fromJson(const {
                  'protocolVersion': 3,
                  'pageId': 'page-1',
                  'sceneRevision': {
                    'epoch': 0,
                    'revision': 1,
                    'fingerprint': '0123456789abcdef',
                  },
                  'assets': [
                    {
                      'key': 'clean|page',
                      'kind': 'clean',
                      'fingerprint': '0123456789abcdef',
                    },
                  ],
                  'marks': [],
                  'exactTexts': [],
                  'sourceRefs': ['s1'],
                }),
            commitResultBuilder: (id) => AddElementResult(
              RectangleElement(
                id: ElementId('applied-$id'),
                x: 1,
                y: 1,
                width: 5,
                height: 5,
                seed: 3,
                versionNonce: 4,
                updated: 5,
              ),
            ),
            correctionHandler: correction ?? emptyCorrection,
            rerunChain: rerun ?? emptyRerun,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, controller, session, rerunCalls);
  }

  /// 真实编辑器 + 会话 + 仓库链（fake 传输）。
  (ProviderContainer, MarkdrawController, SmartLayoutSession, StringBuffer)
  setUpContainer({
    AffectedSourceSet Function(RegionCorrectionIntent intent)? correction,
    Future<List<ValidatedCandidate>> Function(Set<String> scope)? rerun,
  }) {
    final controller = MarkdrawController();
    return setUpContainerWithController(
      controller,
      correction: correction,
      rerun: rerun,
    );
  }

  /// 经完整门禁流水线构建真实验证候选（多样性键可指定）。
  /// 基线 revision 由独立 tracker 观察当前场景（与容器内 tracker 同值）。
  Future<ValidatedCandidate> buildCandidate(
    MarkdrawController controller,
    String candidateId,
    String diversityKey,
  ) async {
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    addTearDown(tracker.dispose);
    final base = controller.currentScene;
    final patch =
        (SmartLayoutScenePatchBuilder(
              baseScene: base,
              baseRevision: tracker.current,
              sourceCoverage: SourceCoverageLedger.pending(const [
                's1',
                't1',
              ]).markConsumed(const ['s1', 't1']),
            )..updateElement(
              TextElement(
                id: ElementId('t1'),
                x: 100,
                y: 40,
                width: 220,
                height: 28,
                text: '正文内容',
                fontSize: 20,
                fontFamily: 'Excalifont',
                seed: 7,
                versionNonce: 11,
                updated: 1000,
                version: 2,
              ),
              baseVersion: 1,
            ))
            .build();
    final result = await ValidatedCandidatePipeline.run(
      baseScene: base,
      pageContentBounds: page,
      candidates: [
        CandidateGateInput(
          candidateId: candidateId,
          diversityKey: diversityKey,
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

  test('验证候选卡绑定：rank/结构差异/评分解释/真实缩略图/账本核对', () async {
    final (container, controller, tracker, _) = setUpContainer();
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await vm.startAnalysis();
    await Future<void>.delayed(Duration.zero);

    final a = await buildCandidate(controller, 'c1', 'single');
    final b = await buildCandidate(controller, 'c2', 'two-column');
    vm.completeGenerationFromValidated([a, b]);

    final state = container.read(smartLayoutSessionViewModelProvider);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, hasLength(2));
    final first = state.validatedCards[0];
    final second = state.validatedCards[1];
    expect(first.candidate, same(a), reason: '每张卡绑定当前 ValidatedCandidate');
    expect(first.rank, 1);
    expect(first.structureDiffLabel, '基准结构');
    expect(second.structureDiffLabel, '结构不同');
    expect(first.scoreEntries, isNotEmpty);
    expect(first.thumbnail.width, 800, reason: '真实 renderer 缩略图');
    expect(state.selectedValidatedCandidate, same(a));

    // 全文账本核对：两源逐一 consumed。
    expect(state.ledgerReview, hasLength(2));
    expect(state.ledgerReview.map((e) => e.$2).toSet(), {
      SourceCoverageStatus.consumed,
    });

    // 切换候选不写权威 Scene：场景实例与指纹不变。
    final sceneBefore = controller.currentScene;
    vm.chooseCandidate('c2');
    expect(
      identical(controller.currentScene, sceneBefore),
      isTrue,
      reason: '候选切换零权威 Scene 写入',
    );
    expect(state.validatedCards[1].candidate, same(b));
    for (final card in state.validatedCards) {
      card.candidate.dispose();
    }
  });

  test('纠错修正：触发最小重跑、旧候选失效、新候选发布', () async {
    final scopes = <Set<String>>[];
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('s1'),
          x: 10,
          y: 10,
          width: 40,
          height: 40,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        TextElement(
          id: ElementId('t1'),
          x: 20,
          y: 40,
          width: 200,
          height: 28,
          text: '正文内容',
          fontSize: 20,
          fontFamily: 'Excalifont',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      ),
    );
    final (container, _, _, _) = setUpContainerWithController(
      controller,
      correction: (intent) => AffectedSourceSet(
        regionIds: const {'r1'},
        strokeSourceIds: const {'i1'},
        renderAssetKeys: const {},
        cropKeys: const {},
      ),
      rerun: (scope) async {
        scopes.add(scope);
        return [await buildCandidate(controller, 'c1-rerun', 'single')];
      },
    );
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await vm.startAnalysis();
    await Future<void>.delayed(Duration.zero);
    final a = await buildCandidate(controller, 'c1', 'single');
    vm.completeGenerationFromValidated([a]);
    expect(
      container.read(smartLayoutSessionViewModelProvider).validatedCards,
      hasLength(1),
    );

    await vm.applyRegionCorrection(
      const RegionCorrectionIntent(kind: 'merge', subjectIds: ['r1', 'r2']),
    );

    final state = container.read(smartLayoutSessionViewModelProvider);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, hasLength(1));
    expect(
      state.validatedCards.single.candidateId,
      'c1-rerun',
      reason: '旧候选失效，重跑候选发布',
    );
    expect(scopes, [
      {'i1'},
    ], reason: '最小重跑以受影响源为 scope');
    state.validatedCards.single.candidate.dispose();
  });

  test('修正重跑无产出：空卡 reviewing（无解如实呈现）', () async {
    final (container, controller, tracker, _) = setUpContainer(
      correction: (intent) => AffectedSourceSet(
        regionIds: const {'r1'},
        strokeSourceIds: const {'i1'},
        renderAssetKeys: const {},
        cropKeys: const {},
      ),
      rerun: (scope) async => const [],
    );
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await vm.startAnalysis();
    await Future<void>.delayed(Duration.zero);
    final a = await buildCandidate(controller, 'c1', 'single');
    vm.completeGenerationFromValidated([a]);

    await vm.applyRegionCorrection(
      const RegionCorrectionIntent(kind: 'split', subjectIds: ['r1']),
    );
    final state = container.read(smartLayoutSessionViewModelProvider);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, isEmpty, reason: '无解不伪装成功');
    expect(state.candidates, isEmpty);
  });
}
