import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fake_recognition_transport.dart';

/// R7 入口切换（spec §10/§11）：新 outcome 变体
/// [SmartLayoutRecognitionSucceeded] 经 `runFromSemanticAssembly` 进入
/// 生成链（第 0 步 page-furniture 剥离 + §6.4 三方一致断言）；旧
/// `run(response)` 入口原样保留（服务实验/测试路径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const pageId = 'page-1';

  MarkdrawController controllerWithContent({bool nativeText = false}) {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: const [
            CanvasPage(
              id: pageId,
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 1200, 800),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('page-frame'),
          x: 0,
          y: 0,
          width: 1200,
          height: 800,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          customData: const {
            'flowMuse': {'role': 'page', 'pageId': pageId},
          },
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        nativeText
            ? TextElement(
                id: const ElementId('k-s1'),
                x: 200,
                y: 150,
                width: 300,
                height: 60,
                text: '旧入口原生正文',
                fontFamily: 'Excalifont',
                customData: const {
                  'flowMuse': {'pageId': pageId},
                },
              )
            : FreedrawElement(
                id: const ElementId('k-s1'),
                x: 200,
                y: 150,
                width: 300,
                height: 60,
                points: const [Point(0, 0), Point(40, 20)],
                customData: const {
                  'flowMuse': {'pageId': pageId},
                },
              ),
      ),
    );
    return controller;
  }

  FakeRecognitionTransport transportOf() => FakeRecognitionTransport(
    responder: (body) async =>
        buildBatchResponseBody(jsonDecode(body) as Map<String, Object?>),
  );

  testWidgets('新 outcome 变体：背景剥离入账本，候选链走文档入口', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithContent();
    addTearDown(controller.dispose);
    final transport = transportOf();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);

    final ticket = scope.session.beginOperation();
    // 图片编码/候选渲染需要真实异步队列，不能在 widget fakeAsync 内等待。
    final outcome = await tester.runAsync(
      () => scope.dependencies.analysisRunner!(ticket),
    );
    expect(outcome, isA<SmartLayoutRecognitionSucceeded>());
    final recognition =
        (outcome as SmartLayoutRecognitionSucceeded).recognition;
    expect(scope.dependencies.currentRecognitionGeneration, isNotNull);
    expect(
      scope.dependencies.currentRecognitionGeneration!(),
      recognition.generation,
    );
    // 第 0 步口径（§6.4-1）：页框（背景）不进识别账本源集合。
    expect(recognition.ledger.sourceIds, isNot(contains('page-frame')));
    expect(recognition.ledger.sourceIds, contains('k-s1'));
    // 语义装配与账本三方一致（装配阶段已内联校验，此处断言投影闭合）。
    expect(recognition.ledger.projection.fullySettled, isTrue);

    final candidates = await tester.runAsync(
      () => scope.dependencies.candidateChainFromDocument!(outcome, ticket),
    );
    expect(candidates, isNotEmpty, reason: 'runFromSemanticAssembly 产出候选');
    for (final candidate in candidates!) {
      candidate.dispose();
    }

    scope.session.cancelOperation();
    scope.session.reset();
  });

  testWidgets('真实分区纠错：只重读受影响区域，新代次沿用正式管线', (tester) async {
    final controller = controllerWithContent();
    addTearDown(controller.dispose);
    for (final (id, x, y) in [('k-s2', 220.0, 150.0), ('k-s3', 800.0, 600.0)]) {
      controller.applyResult(
        AddElementResult(
          FreedrawElement(
            id: ElementId(id),
            x: x,
            y: y,
            width: 80,
            height: 60,
            points: const [Point(0, 0), Point(40, 20)],
            customData: const {
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
    }
    final transport = transportOf();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);
    final ticket = scope.session.beginOperation();
    final first = await tester.runAsync(
      () => scope.dependencies.analysisRunner!(ticket),
    );
    expect(first, isA<SmartLayoutRecognitionSucceeded>());
    final recognition = (first as SmartLayoutRecognitionSucceeded).recognition;
    final region = recognition.regionRecords.singleWhere(
      (r) => r.targetSourceIds.contains('k-s1'),
    );
    expect(region.targetSourceIds.toSet(), {'k-s1', 'k-s2'});
    final previousCount = transport.requests.length;
    final affected = scope.dependencies.correctionHandler(
      RegionCorrectionIntent(
        kind: 'split',
        subjectIds: [region.regionId],
        detail: '[["k-s1"],["k-s2"]]',
      ),
    );
    expect(affected.renderAssetKeys, isNotEmpty);
    final candidates = await tester.runAsync(
      () => scope.dependencies.rerunChain(affected.strokeSourceIds),
    );
    expect(candidates, isNotEmpty);
    for (final candidate in candidates!) {
      candidate.dispose();
    }
    final reads = transport.requests
        .skip(previousCount)
        .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
        .where((r) => r['stage'] == 'read')
        .toList();
    expect(reads, hasLength(1));
    expect(
      (reads.single['regions'] as List).map((r) => r['regionId']).toSet(),
      {'r:k-s1', 'r:k-s2'},
    );
    expect(reads.single['generation'], recognition.generation + 1);
    scope.session.cancelOperation();
  });

  testWidgets('旧入口不受影响：run(response) 仍可独立产出候选', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithContent(nativeText: true);
    addTearDown(controller.dispose);
    final transport = transportOf();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);

    // 旧路径：requestBuilder 捕获同源快照，response 认领源进入 run()。
    final ticket = scope.session.beginOperation();
    await scope.dependencies.requestBuilder(ticket);
    final response = SmartLayoutV3Response.fromJson(
      jsonDecode('''
{
  "protocolVersion": 3,
  "requestId": "req-1",
  "regions": [
    {"id": "g1", "role": "body", "sourceIds": ["k-s1"], "readingOrder": 0,
     "confidence": 0.9, "relations": []}
  ],
  "warnings": []
}'''),
    );
    final candidates = await tester.runAsync(
      () => scope.dependencies.candidateChain!(response, ticket),
    );
    expect(candidates, isNotEmpty, reason: '旧 response 入口原样可用');
    for (final candidate in candidates!) {
      candidate.dispose();
    }

    scope.session.cancelOperation();
    scope.session.reset();
  });

  testWidgets('状态播报：识别阶段进入既定枚举，完成后回落', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithContent();
    addTearDown(controller.dispose);
    final transport = transportOf();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);
    final seen = <String?>[];
    scope.recognitionStatus.addListener(() {
      seen.add(scope.recognitionStatus.value);
    });

    final ticket = scope.session.beginOperation();
    await tester.runAsync(() => scope.dependencies.analysisRunner!(ticket));
    expect(seen, containsAll(['正在准备', '正在识别']));
    expect(scope.recognitionStatus.value, isNull);

    scope.session.cancelOperation();
    scope.session.reset();
  });
}
