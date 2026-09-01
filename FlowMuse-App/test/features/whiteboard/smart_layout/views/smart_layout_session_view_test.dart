import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_view.dart';

const _okBody = '''
{"protocolVersion":3,"requestId":"req-1","regions":[
 {"id":"g1","role":"title","sourceIds":["s1"],"readingOrder":0,"confidence":0.9,"relations":[]}
],"warnings":[]}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer setUpContainer() {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
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
                id: ElementId('view-applied-$id'),
                x: 1,
                y: 1,
                width: 5,
                height: 5,
                seed: 3,
                versionNonce: 4,
                updated: 5,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget host(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SmartLayoutSessionView()),
      ),
    ),
  );

  testWidgets('idle：空范围禁启；加范围后可启，摘要随状态更新', (tester) async {
    final container = setUpContainer();
    await tester.pumpWidget(host(container));

    expect(find.text('开始智能排版'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: '空范围禁启',
    );
    expect(find.textContaining('排版范围 0 项'), findsOneWidget);

    container
        .read(smartLayoutSessionViewModelProvider.notifier)
        .addScopeSource('s1');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('排版范围 1 项'), findsOneWidget);
  });

  testWidgets('reviewing：候选卡渲染、点选切换经 ViewModel、应用可点', (tester) async {
    final container = setUpContainer();
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await tester.pumpWidget(host(container));

    await vm.startAnalysis();
    await tester.pump();
    vm.completeGeneration(const [
      SmartLayoutCandidateSummary(candidateId: 'c1', structureLabel: '单栏'),
      SmartLayoutCandidateSummary(candidateId: 'c2', structureLabel: '双栏'),
    ]);
    await tester.pump();

    expect(find.text('单栏'), findsOneWidget);
    expect(find.text('双栏'), findsOneWidget);
    expect(find.text('应用所选排版'), findsOneWidget);

    await tester.tap(find.text('双栏'));
    await tester.pump();
    expect(
      container.read(smartLayoutSessionViewModelProvider).selectedCandidateId,
      'c2',
      reason: '视图点选只转发 ViewModel，不自持业务状态',
    );

    await tester.tap(find.text('应用所选排版'));
    await tester.pump();
    expect(find.textContaining('排版已应用'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '完成'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('取消后渲染终态信息与完成（复位）入口', (tester) async {
    final container = setUpContainer();
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await tester.pumpWidget(host(container));
    await vm.startAnalysis();
    await tester.pump();
    expect(find.text('取消'), findsOneWidget);

    vm.cancel();
    await tester.pump();
    expect(find.textContaining('已取消'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(find.text('开始智能排版'), findsOneWidget);
  });

  testWidgets('验证候选卡：真实缩略图/评分解释/结构差异/账本核对渲染', (tester) async {
    final container = setUpContainer();
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('s1');
    await tester.pumpWidget(host(container));
    await vm.startAnalysis();
    await tester.pump();

    // 经真实管线构建候选并发布（渲染快照来自 DraftSceneRenderer）。
    final cards = await _buildValidatedCards(container);
    vm.completeGenerationFromValidated(cards);
    await tester.pump();

    expect(find.byType(RawImage), findsNWidgets(2), reason: '每张卡一枚真实渲染缩略图');
    expect(find.textContaining('第 1 名'), findsOneWidget);
    expect(find.textContaining('第 2 名'), findsOneWidget);
    expect(find.textContaining('基准结构'), findsOneWidget);
    expect(find.textContaining('结构不同'), findsOneWidget);
    expect(find.textContaining('评分 '), findsNWidgets(2));
    expect(find.textContaining('构成：'), findsNWidgets(2), reason: '评分解释可还原分解');
    expect(
      find.textContaining('已消费'),
      findsAtLeastNWidgets(1),
      reason: '账本核对逐源呈现',
    );
    expect(find.text('合并所选区域'), findsOneWidget, reason: '纠错入口');

    await tester.tap(find.textContaining('第 2 名'));
    await tester.pump();
    expect(
      container.read(smartLayoutSessionViewModelProvider).selectedCandidateId,
      'c2',
      reason: '切换经 ViewModel，不写权威 Scene',
    );
    for (final c in cards) {
      c.dispose();
    }
  });

  group('V3-505C 无鼠标/可访问性闭环', () {
    Widget hostWithRestore(ProviderContainer container, FocusNode restore) =>
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Focus(
                focusNode: restore,
                child: const SingleChildScrollView(
                  child: SmartLayoutSessionView(
                    restoreFocusNode: null,
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('键盘全流程：Enter 开始 → Escape 取消 → Enter 复位并归还焦点', (
      tester,
    ) async {
      final container = setUpContainer();
      final restoreNode = FocusNode();
      addTearDown(restoreNode.dispose);
      container
          .read(smartLayoutSessionViewModelProvider.notifier)
          .addScopeSource('s1');
      await tester.pumpWidget(hostWithRestore(container, restoreNode));

      // 焦点在开始按钮（autofocus）：Enter 触发开始分析。
      expect(find.text('开始智能排版'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        container.read(smartLayoutSessionViewModelProvider).phase,
        SmartLayoutSessionPhase.analyzing,
        reason: 'Enter 无鼠标启动分析',
      );

      // Escape：立即取消（不等待在途）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.textContaining('已取消'), findsOneWidget);

      // Enter：完成（复位）——焦点归还宿主节点。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('开始智能排版'), findsOneWidget);
      expect(restoreNode.hasFocus, isTrue, reason: '会话结束焦点恢复');
    });

    testWidgets('reviewing 键盘：方向键切换候选、Enter 应用所选', (tester) async {
      final container = setUpContainer();
      final restoreNode = FocusNode();
      addTearDown(restoreNode.dispose);
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('s1');
      await tester.pumpWidget(hostWithRestore(container, restoreNode));
      await vm.startAnalysis();
      await tester.pump();
      vm.completeGeneration(const [
        SmartLayoutCandidateSummary(candidateId: 'c1', structureLabel: '单栏'),
        SmartLayoutCandidateSummary(candidateId: 'c2', structureLabel: '双栏'),
      ]);
      await tester.pump();

      // 下方向键：c1 → c2；上方向键回 c1。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        container.read(smartLayoutSessionViewModelProvider).selectedCandidateId,
        'c2',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        container.read(smartLayoutSessionViewModelProvider).selectedCandidateId,
        'c1',
      );

      // Enter：应用所选（焦点在应用按钮）。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.textContaining('排版已应用'), findsOneWidget);
      expect(
        container.read(smartLayoutSessionViewModelProvider).phase,
        SmartLayoutSessionPhase.applied,
      );
    });

    testWidgets('无解分支：空候选呈现 + 重新分析按钮触发重走', (tester) async {
      final container = setUpContainer();
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('s1');
      await tester.pumpWidget(host(container));
      await vm.startAnalysis();
      await tester.pump();
      vm.completeGeneration(const []);
      await tester.pump();

      expect(find.text('本次分析没有可用的排版候选'), findsOneWidget);
      expect(find.text('重新分析'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);

      await tester.tap(find.text('重新分析'));
      await tester.pump();
      expect(
        container.read(smartLayoutSessionViewModelProvider).phase,
        SmartLayoutSessionPhase.analyzing,
        reason: '重新分析重走完整链（无 candidateChain 的手动路径停 analyzing）',
      );
    });

    testWidgets('Semantics：相位 liveRegion 播报随状态迁移更新', (tester) async {
      final handle = tester.ensureSemantics();
      final container = setUpContainer();
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('s1');
      await tester.pumpWidget(host(container));
      expect(find.bySemanticsLabel(RegExp('待开始')), findsOneWidget);

      await vm.startAnalysis();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('正在分析')), findsOneWidget);

      vm.cancel();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('已取消')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('零 modal：各相位有界泵全部收敛（无弹层残留）', (tester) async {
      final container = setUpContainer();
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
        ..addScopeSource('s1');
      await tester.pumpWidget(host(container));

      await vm.startAnalysis();
      await tester.pump(const Duration(milliseconds: 50));
      vm.completeGeneration(const [
        SmartLayoutCandidateSummary(candidateId: 'c1', structureLabel: '单栏'),
      ]);
      await tester.pump(const Duration(milliseconds: 50));
      await vm.applySelectedCandidate();
      // applying→applied 在微任务内完成；有界泵避免忙指示器无限动画
      // 导致 pumpAndSettle 超时（进度动画 ≠ 模态死锁）。
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        container.read(smartLayoutSessionViewModelProvider).phase,
        SmartLayoutSessionPhase.applied,
      );
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: '会话面板非模态：全程无 dialog',
      );
    });
  });
}

/// 经完整门禁流水线构建两个真实验证候选（结构键不同）。
Future<List<ValidatedCandidate>> _buildValidatedCards(
  ProviderContainer container,
) async {
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
  final editor = SmartLayoutEditorGateway(controller);
  final tracker = SceneRevisionTracker(editor: editor);
  addTearDown(tracker.dispose);
  final base = controller.currentScene;

  Future<ValidatedCandidate> build(String id, String key) async {
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
      pageContentBounds: Bounds.fromLTWH(0, 0, 800, 600),
      candidates: [
        CandidateGateInput(
          candidateId: id,
          diversityKey: key,
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

  return [await build('c1', 'single'), await build('c2', 'two-column')];
}
