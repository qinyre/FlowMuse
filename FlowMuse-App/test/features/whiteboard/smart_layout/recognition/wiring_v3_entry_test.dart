import 'dart:async';
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

  _ObservedController controllerWithContent({
    bool nativeText = false,
    bool grouped = false,
  }) {
    final controller = _ObservedController(
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
                groupIds: grouped ? const ['native-group'] : const [],
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
                  recognitionStrokeSessionKey: 's1',
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

  testWidgets('真实入口：原生文本组合进入排版且整组只移动一次', (tester) async {
    final controller = controllerWithContent(nativeText: true, grouped: true);
    addTearDown(controller.dispose);
    controller.applyResult(
      AddElementResult(
        TextElement(
          id: const ElementId('t2'),
          x: 550,
          y: 150,
          width: 150,
          height: 60,
          text: '组合成员',
          fontFamily: 'Excalifont',
          groupIds: const ['native-group'],
          customData: const {
            'flowMuse': {'pageId': pageId},
          },
        ),
      ),
    );
    final transport = transportOf();
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);
    final ticket = scope.session.beginOperation();
    final result = await tester.runAsync(
      () => scope.dependencies.analysisRunner!(ticket),
    );
    expect(result, isA<SmartLayoutRecognitionSucceeded>());
    final recognized = result as SmartLayoutRecognitionSucceeded;
    expect(recognized.recognition.ledger.consumedCount, 2);
    final candidates = await tester.runAsync(
      () => scope.dependencies.candidateChainFromDocument!(recognized, ticket),
    );
    expect(candidates, isNotEmpty);
    for (final c in candidates!) {
      c.dispose();
    }
    expect(transport.requests, isEmpty, reason: '原生组合无需OCR');
    scope.session.cancelOperation();
  });

  for (final cancelV3 in [true, false]) {
    testWidgets('R8 同一控制器并发：取消 ${cancelV3 ? 'V3' : 'V1'} 不影响另一链路', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = controllerWithContent();
      addTearDown(controller.dispose);
      // 两条在途链及传输 Completer 必须同处真实异步 zone。
      await tester.runAsync(() async {
        final transport = transportOf()..blockRequests();
        addTearDown(transport.release);
        final scope = SmartLayoutRealSessionScope.build(
          controller: controller,
          serverUri: Uri.parse('http://127.0.0.1:9'),
          pageId: pageId,
          post: transport.post,
        );
        addTearDown(scope.dispose);
        final oldEntered = Completer<void>();
        final oldResponse = Completer<SmartLayoutVisionResponse>();
        controller.onVisionSmartLayout = (_) {
          oldEntered.complete();
          return oldResponse.future;
        };
        final oldRun = controller
            .prepareSmartLayoutTemplates(pageId: pageId)
            .then<Object?>((value) => value, onError: (Object error) => error);
        await Future.any([
          oldEntered.future,
          oldRun.then((value) => throw StateError('旧准备未进入回调: $value')),
        ]).timeout(const Duration(seconds: 10));
        final ticket = scope.session.beginOperation();
        final newRun = scope.dependencies.analysisRunner!(ticket);
        await transport.firstRequestSeen.future.timeout(
          const Duration(seconds: 10),
        );
        final token = transport.requests.first.cancelToken;
        expect(token, isNotNull);
        expect(token!.isCancelled, isFalse);
        if (cancelV3) {
          scope.session.cancelOperation();
          scope.dependencies.onCancelAnalysis!();
          expect(token.isCancelled, isTrue);
          expect(controller.cancelCalls, 0, reason: 'V3 取消不可调用旧控制器');
        } else {
          controller.cancelSmartLayoutPreparation();
          expect(token.isCancelled, isFalse, reason: '旧取消不得取消 V3 token');
        }
        transport.release();
        oldResponse.complete(
          SmartLayoutVisionResponse.fromJson({
            'elements': [
              {
                'id': 'e1',
                'role': 'body',
                'text': '隔离测试正文',
                'markIds': ['m1'],
                'confidence': 1.0,
              },
            ],
          }),
        );
        final oldResult = await oldRun;
        final newResult = await newRun;
        expect(controller.prepareCalls, 1, reason: '只有显式 V1 操作进入旧准备');
        expect(
          transport.requests.every(
            (r) =>
                Uri.parse(r.url).path == '/api/ink/smart-layout/recognize/v3',
          ),
          isTrue,
        );
        if (cancelV3) {
          expect(oldResult, isA<SmartLayoutTemplatePreparation>());
          expect(newResult, isNot(isA<SmartLayoutRecognitionSucceeded>()));
        } else {
          expect(oldResult, isA<SmartLayoutCancelledException>());
          expect(newResult, isA<SmartLayoutRecognitionSucceeded>());
          scope.session.cancelOperation();
        }
      });
    });
  }

  testWidgets('R8 V3 服务未配置：保留源、不回退旧准备或视觉引擎', (tester) async {
    final controller = controllerWithContent();
    addTearDown(controller.dispose);
    var oldVisionCalls = 0;
    controller.onVisionSmartLayout = (_) async {
      oldVisionCalls++;
      throw StateError('V3 不应调用旧视觉识别');
    };
    final transport = FakeRecognitionTransport(
      responder: (_) async =>
          (503, errorEnvelopeJson('unconfigured', 'not configured', false)),
    );
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
      post: transport.post,
    );
    addTearDown(scope.dispose);
    final ticket = scope.session.beginOperation();
    final outcome = await tester.runAsync(
      () => scope.dependencies.analysisRunner!(ticket),
    );
    expect(outcome, isA<SmartLayoutRecognitionSucceeded>());
    final result = (outcome as SmartLayoutRecognitionSucceeded).recognition;
    expect(result.partial, isTrue);
    expect(result.ledger.preservedCount, 1);
    expect(result.ledger.consumedCount, 0);
    expect(controller.prepareCalls, 0);
    expect(oldVisionCalls, 0);
    scope.dependencies.onCancelAnalysis!();
    expect(controller.cancelCalls, 0);
    scope.session.cancelOperation();
  });

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
    expect(
      () => scope.dependencies.correctionHandler(
        RegionCorrectionIntent(
          kind: 'merge',
          subjectIds: [region.regionId, region.regionId],
          detail: '',
        ),
      ),
      throwsA(isA<SmartLayoutCorrectionRejected>()),
    );
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
    final undo = scope.dependencies.correctionHandler(
      const RegionCorrectionIntent(
        kind: 'undo-region',
        subjectIds: [],
        detail: '',
      ),
    );
    expect(undo.strokeSourceIds, {'k-s1', 'k-s2'});
    final restored = await tester.runAsync(
      () => scope.dependencies.rerunChain(undo.strokeSourceIds),
    );
    expect(restored, isNotEmpty);
    for (final c in restored!) {
      c.dispose();
    }
    final lastRead = transport.decodedBodies('read').last;
    expect((lastRead['regions'] as List).map((r) => r['regionId']), ['r:k-s1']);
    expect(lastRead['generation'], recognition.generation + 2);
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

/// 只观测调用，仍执行真实旧控制器；生产代码不增加测试开关。
class _ObservedController extends MarkdrawController {
  _ObservedController({required super.config});
  int prepareCalls = 0;
  int cancelCalls = 0;

  @override
  Future<SmartLayoutTemplatePreparation?> prepareSmartLayoutTemplates({
    required String pageId,
    void Function(int completed, int total)? onProgress,
  }) {
    prepareCalls++;
    return super.prepareSmartLayoutTemplates(
      pageId: pageId,
      onProgress: onProgress,
    );
  }

  @override
  void cancelSmartLayoutPreparation() {
    cancelCalls++;
    super.cancelSmartLayoutPreparation();
  }
}
