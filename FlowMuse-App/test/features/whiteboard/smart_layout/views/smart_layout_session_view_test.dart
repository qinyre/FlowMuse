import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
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
            }) async =>
                NativeHttpResponse(statusCode: 200, body: _okBody),
      ),
      session: session,
    );
    final container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          SmartLayoutSessionDependencies(
            session: session,
            repository: repo,
            requestBuilder: (ticket) async => SmartLayoutV3Request.fromJson(
              const {
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
              },
            ),
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

  testWidgets('reviewing：候选卡渲染、点选切换经 ViewModel、应用可点',
      (tester) async {
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
}
