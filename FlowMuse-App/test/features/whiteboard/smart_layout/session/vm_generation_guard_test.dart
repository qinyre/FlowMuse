import 'dart:async';

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
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';

/// §9.8 发布代次守卫（R7）：completeGenerationFromValidated 两个调用点
/// （正常完成 :485 / 纠错重跑完成 :633）发布前校验"捕获时 generation ==
/// 当前会话 generation"；旧代次产物（即使空数组）不得清空较新代候选。
/// 另覆盖纠错在途串行化（重复入口 no-op）。
/// 可编程测试宿主：真实编辑器 + 会话链（fake 传输）+ 可变识别代次 +
/// 可门控的识别候选链与纠错重跑链。
class Harness {
  Harness(this.container, this.controller);

  final ProviderContainer container;
  final MarkdrawController controller;

  int generation = 1;

  /// 识别候选链门（null = 直通返回既有候选）。
  Completer<void>? chainGate;
  Completer<void>? chainEntered;

  /// 纠错重跑链门与计数。
  Completer<void>? rerunGate;
  Completer<void>? rerunEntered;
  int rerunCalls = 0;

  /// 识别候选链直接回放的候选（真实门禁产物）。
  List<ValidatedCandidate> chainCandidates = const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final page = Bounds.fromLTWH(0, 0, 800, 600);

  /// 空语义装配（守卫只读 generation，不消费文档内容）。
  SmartLayoutRecognitionSucceeded outcomeOf(int generation) =>
      SmartLayoutRecognitionSucceeded(
        semantic: SemanticAssembly(
          document: SemanticDocument(
            formatVersion: SemanticDocumentFormat.currentVersion,
            pageId: 'page-1',
            epoch: 0,
            revision: 1,
            fingerprint: '0123456789abcdef',
            blocks: const [],
            readingOrder: const SemanticReadingOrder(orderedBlockIds: []),
            conflicts: const [],
            consumedSourceIds: const [],
            preservedSourceIds: const [],
          ),
          ledger: SourceCoverageLedger.pending(const []),
        ),
        recognition: RecognitionSessionResult(
          operationId: 'op-guard',
          generation: generation,
          pageId: 'page-1',
          scene: Scene(),
          sceneRevision: const RecognitionSceneRevision(
            epoch: 0,
            revision: 1,
            fingerprint: '0123456789abcdef',
          ),
          contentFingerprint: 'fedcba9876543210',
          regionRecords: const [],
          regionOutcomes: const {},
          ledger: SourceLedger.register(const []),
          assetIndex: RegionAssetIndex(),
        ),
      );

  Harness setUpHarness() {
    final controller = MarkdrawController();
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('s1'),
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
          id: const ElementId('t1'),
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
            }) async => const NativeHttpResponse(statusCode: 200, body: '{}'),
      ),
      session: session,
    );
    late final Harness harness;
    harness = Harness(
      ProviderContainer(
        overrides: [
          smartLayoutSessionDependenciesProvider.overrideWithValue(
            SmartLayoutSessionDependencies(
              session: session,
              repository: repo,
              analysisRunner: (ticket) async => outcomeOf(1),
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
              candidateChainFromDocument: (outcome, ticket) async {
                final entered = harness.chainEntered;
                if (entered != null && !entered.isCompleted) {
                  entered.complete();
                }
                final gate = harness.chainGate;
                if (gate != null) {
                  await gate.future;
                }
                return harness.chainCandidates;
              },
              correctionHandler: (intent) => AffectedSourceSet(
                regionIds: const {},
                strokeSourceIds: const {'s1'},
                renderAssetKeys: const {},
                cropKeys: const {},
              ),
              rerunChain: (scope) async {
                harness.rerunCalls++;
                final entered = harness.rerunEntered;
                if (entered != null && !entered.isCompleted) {
                  entered.complete();
                }
                final gate = harness.rerunGate;
                if (gate != null) {
                  await gate.future;
                }
                return const [];
              },
              currentRecognitionGeneration: () => harness.generation,
            ),
          ),
        ],
      ),
      controller,
    );
    addTearDown(harness.container.dispose);
    addTearDown(controller.dispose);
    return harness;
  }

  /// 经完整门禁流水线构建真实验证候选（发布卡需要真实候选）。
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
                id: const ElementId('t1'),
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

  SmartLayoutSessionUiState stateOf(Harness harness) =>
      harness.container.read(smartLayoutSessionViewModelProvider);

  SmartLayoutSessionViewModel vmOf(Harness harness) =>
      harness.container.read(smartLayoutSessionViewModelProvider.notifier);

  test(':485 正常完成点：产物代次过期 → 候选零发布（analyzing 不动）', () async {
    final harness = setUpHarness();
    final candidate = await buildCandidate(harness.controller, 'c1', 'single');
    harness.chainCandidates = [candidate];
    harness.chainEntered = Completer<void>();
    harness.chainGate = Completer<void>();
    final vm = vmOf(harness);

    final analysis = vm.startAnalysis();
    await harness.chainEntered!.future;
    // 链返回前代次被新纠错/新分析接管 → 迟到候选丢弃。
    harness.generation = 2;
    harness.chainGate!.complete();
    await analysis;

    final state = stateOf(harness);
    expect(state.phase, SmartLayoutSessionPhase.analyzing);
    expect(state.validatedCards, isEmpty, reason: '旧代候选不发布');
    expect(state.candidates, isEmpty);
    expect(state.failure, isNull, reason: '代次守卫不是失败');
  });

  test(':485 对照：代次一致 → 正常发布进入 reviewing', () async {
    final harness = setUpHarness();
    final candidate = await buildCandidate(harness.controller, 'c1', 'single');
    harness.chainCandidates = [candidate];
    final vm = vmOf(harness);

    await vm.startAnalysis();
    final state = stateOf(harness);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, hasLength(1));
    expect(state.validatedCards.single.candidate, same(candidate));
  });

  test(':633 纠错重跑完成点：旧代空数组不清空较新代候选', () async {
    final harness = setUpHarness();
    final candidate = await buildCandidate(harness.controller, 'c1', 'single');
    harness.chainCandidates = [candidate];
    final vm = vmOf(harness);
    await vm.startAnalysis();
    expect(stateOf(harness).validatedCards, hasLength(1));

    harness.rerunEntered = Completer<void>();
    harness.rerunGate = Completer<void>();
    final correction = vm.applyRegionCorrection(
      const RegionCorrectionIntent(
        kind: 'role',
        subjectIds: ['b1'],
        detail: 'title',
      ),
    );
    await harness.rerunEntered!.future;
    // 重跑在途时新一轮纠错已接管（代次 +1）→ 本轮产物（空数组）不得
    // 清空当前 review 卡。
    harness.generation = 3;
    harness.rerunGate!.complete();
    await correction;

    final state = stateOf(harness);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, hasLength(1), reason: '旧代空数组不清空卡片');
    expect(harness.rerunCalls, 1);
  });

  test(':633 对照：代次一致的重跑空产出如实清空卡片', () async {
    final harness = setUpHarness();
    final candidate = await buildCandidate(harness.controller, 'c1', 'single');
    harness.chainCandidates = [candidate];
    final vm = vmOf(harness);
    await vm.startAnalysis();
    expect(stateOf(harness).validatedCards, hasLength(1));

    await vm.applyRegionCorrection(
      const RegionCorrectionIntent(
        kind: 'role',
        subjectIds: ['b1'],
        detail: 'title',
      ),
    );
    final state = stateOf(harness);
    expect(state.phase, SmartLayoutSessionPhase.reviewing);
    expect(state.validatedCards, isEmpty, reason: '无解如实呈现（空卡）');
  });

  test('纠错在途串行化：重复入口 no-op，重跑链只调一次', () async {
    final harness = setUpHarness();
    final candidate = await buildCandidate(harness.controller, 'c1', 'single');
    harness.chainCandidates = [candidate];
    final vm = vmOf(harness);
    await vm.startAnalysis();
    expect(stateOf(harness).validatedCards, hasLength(1));

    harness.rerunEntered = Completer<void>();
    harness.rerunGate = Completer<void>();
    final first = vm.applyRegionCorrection(
      const RegionCorrectionIntent(
        kind: 'role',
        subjectIds: ['b1'],
        detail: 'title',
      ),
    );
    await harness.rerunEntered!.future;
    // 在途纠错：第二次入口为 no-op（isCorrecting 语义）。
    await vm.applyRegionCorrection(
      const RegionCorrectionIntent(
        kind: 'role',
        subjectIds: ['b1'],
        detail: 'title',
      ),
    );
    expect(harness.rerunCalls, 1, reason: '在途期间重复纠错不重入');
    harness.rerunGate!.complete();
    await first;
    expect(harness.rerunCalls, 1);
    expect(stateOf(harness).validatedCards, isEmpty);
  });
}
