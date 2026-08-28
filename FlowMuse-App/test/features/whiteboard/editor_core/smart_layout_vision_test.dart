import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2 模板卡片制视觉管线：模型解析、Set-of-Mark 编号直查匹配、
/// 识别准备（认字/图文配对/裁剪重问）→ 三模板预落位 → 点选装配计划。
/// 无经典管线回退：识别失败/无内容直接抛异常或返回 null。
///
/// 标记编号约定（控制器按阅读序上→左编号）：仅 _addStrokes 时 m1=簇s1、
/// m2=簇s2；再加 img-cat 时 m3=图片元素。
void main() {
  group('SmartLayoutVisionElement 模型', () {
    test('解析 markIds 与引用 id；confidence 缺省 0.9 并钳制到 0-1', () {
      final element = SmartLayoutVisionElement.fromJson({
        'id': 'e2',
        'role': 'caption',
        'text': '小羊睡觉',
        'vertical': true,
        'pairId': 'pair-1',
        'markIds': ['m3', 'm4'],
        'confidence': 2.5,
      });
      expect(element.id, 'e2');
      expect(element.role, 'caption');
      expect(element.vertical, isTrue);
      expect(element.markIds, ['m3', 'm4']);
      expect(element.confidence, 1);

      final defaults = SmartLayoutVisionElement.fromJson({
        'role': 'body',
        'text': '缺省',
      });
      expect(defaults.markIds, isEmpty);
      expect(defaults.confidence, 0.9);
    });

    test('请求 toJson：marks 非空时携带编号列表', () {
      const request = SmartLayoutVisionRequest(
        pageId: 'p-1',
        imageBase64: 'aGk=',
        marks: ['m1', 'm2'],
      );
      expect(request.toJson()['marks'], ['m1', 'm2']);
      const empty = SmartLayoutVisionRequest(pageId: 'p-1', imageBase64: 'aGk=');
      expect(empty.toJson().containsKey('marks'), isFalse);
    });

    test('响应解析：只取 elements，style/structure 等旧字段被忽略', () {
      final response = SmartLayoutVisionResponse.fromJson({
        'style': 'mindmap',
        'confidence': 0.7,
        'structure': {
          'root': {'text': '主题'},
        },
        'elements': [
          {'id': 'e0', 'role': 'body', 'text': '主题', 'markIds': ['m1']},
        ],
      });
      expect(response.elements, hasLength(1));
      expect(response.elements.single.id, 'e0');
      expect(response.elements.single.text, '主题');
    });
  });

  group('SmartLayoutVisionMatcher（Set-of-Mark 直查）', () {
    SmartLayoutVisionElement elem(
      String role,
      List<String> markIds, {
      String? text,
      String? pairId,
    }) => SmartLayoutVisionElement(
      role: role,
      text: text ?? (role == 'figure' ? null : '文字'),
      markIds: markIds,
      pairId: pairId,
    );

    test('markIds 直查：文本项认领映射簇，未认领簇进红区', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [elem('body', ['m1', 'm2'])],
        textMarks: {'m1': 'a', 'm2': 'b'},
        figureMarks: {},
        allClusterKeys: {'a', 'b', 'c'},
      );
      expect(match.textClaims[0], ['a', 'b']);
      expect(match.unclaimedClusterKeys, {'c'});
      expect(match.matchedItemCount, 1);
    });

    test('同编号被多项引用时首占者赢，后项只认领剩余编号', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [
          elem('body', ['m1']),
          elem('body', ['m1', 'm2']),
        ],
        textMarks: {'m1': 'a', 'm2': 'b'},
        figureMarks: {},
        allClusterKeys: {'a', 'b'},
      );
      expect(match.textClaims[0], ['a']);
      expect(match.textClaims[1], ['b']);
      expect(match.unclaimedClusterKeys, isEmpty);
    });

    test('图形与文本按映射表各归其位，未知编号忽略', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [
          elem('figure', ['m9', 'm3']),
          elem('body', ['m1']),
        ],
        textMarks: {'m1': 'a', 'm2': 'b'},
        figureMarks: {'m3': 'img-a'},
        allClusterKeys: {'a', 'b'},
      );
      expect(match.figureClaims[0], 'img-a');
      expect(match.textClaims[1], ['a']);
      expect(match.unclaimedClusterKeys, {'b'});
    });

    test('认领与失败区互补：无匹配时全部簇进入失败集合', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [],
        textMarks: {'m1': 'a'},
        figureMarks: {},
        allClusterKeys: {'a'},
      );
      expect(match.matchedItemCount, 0);
      expect(match.unclaimedClusterKeys, {'a'});
    });
  });

  group('控制器视觉识别准备（v2）', () {
    testWidgets('识别 + pairId 配对 → 准备产物含标题/配对，三模板均可落位',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.applyResult(
        AddElementResult(
          ImageElement(
            id: const ElementId('img-cat'),
            x: 700,
            y: 600,
            width: 600,
            height: 600,
            fileId: 'file-cat',
          ),
        ),
      );
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(3), reason: '截图候选对象应编号发出');
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('title', '手工记账', ['m1'], id: 'e0'),
            _visionElement(
              'caption',
              '流水明细一整段',
              ['m2'],
              id: 'e1',
              pairId: 'pair-1',
            ),
            _visionElement('figure', '', ['m3'], id: 'e2', pairId: 'pair-1'),
          ],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(preparation!.content.title, isNotNull);
      expect(preparation.content.pairs, hasLength(1));
      expect(preparation.removeIds.map((id) => id.value), contains('k-s1'));
      expect(preparation.failedStrokeIds, isEmpty);
      expect(
        preparation.layouts,
        hasLength(3),
        reason: '三张模板都应有预落位结果',
      );
      for (final kind in SmartLayoutTemplateKind.values) {
        expect(
          preparation.layouts[kind],
          isNotNull,
          reason: '${kind.displayName} 应能放得下',
        );
      }
    });

    testWidgets('点选图文讲义 → 计划含标题/图注新增与图移动，笔迹进删除清单',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.applyResult(
        AddElementResult(
          ImageElement(
            id: const ElementId('img-cat'),
            x: 700,
            y: 600,
            width: 600,
            height: 600,
            fileId: 'file-cat',
          ),
        ),
      );
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('title', '手工记账', ['m1'], id: 'e0'),
              _visionElement(
                'caption',
                '流水明细一整段',
                ['m2'],
                id: 'e1',
                pairId: 'pair-1',
              ),
              _visionElement('figure', '', ['m3'], id: 'e2', pairId: 'pair-1'),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      final result = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.handout,
      );
      final plan = result.plan;
      expect(plan, isNotNull);
      expect(plan!.style, SmartLayoutTemplateKind.handout);
      final addedTexts = plan.addElements.whereType<TextElement>().map(
        (element) => element.text,
      );
      expect(addedTexts, containsAll(['手工记账', '流水明细一整段']));
      expect(plan.moveDeltas.keys.map((id) => id.value), contains('img-cat'));
      expect(plan.removeIds.map((id) => id.value), containsAll(['k-s1']));
      expect(plan.failedStrokeIds, isEmpty);
      expect(plan.previewRects, isNotEmpty);
    });

    testWidgets('点选原文整理 → 文本原位转换且图不动', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', '零散字一', ['m1']),
              _visionElement('body', '零散字二', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      final result = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.inplace,
      );
      final plan = result.plan;
      expect(plan, isNotNull);
      expect(plan!.style, SmartLayoutTemplateKind.inplace);
      // 原文整理语义：新增文本落在原稿附近（不移动图形、删除笔迹）
      expect(plan.moveDeltas, isEmpty);
      expect(
        plan.removeIds.map((id) => id.value),
        containsAll(['k-s1', 'k-s2']),
      );
      for (final element in plan.addElements.whereType<TextElement>()) {
        final nearS1 = (element.x - 500).abs() < 400;
        expect(nearS1, isTrue, reason: '文本应留在原稿 ${element.x} 附近');
      }
    });

    testWidgets('VLM 单引擎：有文本直接采用，无文本项进失败红区且不触发 MyScript',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      var myScriptCalls = 0;
      controller.onRecognizeInk = (request) async {
        myScriptCalls++;
        throw StateError('智能排版不应调用 MyScript');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', 'VLM正文', ['m1']),
              _visionElement('body', '', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(myScriptCalls, 0, reason: '智能排版已完全摘除 MyScript');
      expect(preparation.failedStrokeIds.map((id) => id.value), contains('k-s2'),
          reason: '无文本项的原笔迹留在红区待用户处置');
      expect(preparation.failures, isNotEmpty, reason: 'VLM 无文本项按失败进红区');
      expect(
        preparation.layouts[SmartLayoutTemplateKind.inplace],
        isNotNull,
      );
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      expect(
        plan.addElements.whereType<TextElement>().map((e) => e.text),
        contains('VLM正文'),
      );
      expect(plan.failureRects, isNotEmpty, reason: '失败红区矩形随计划进入草稿态');
      expect(
        plan.lowConfidenceTexts,
        isEmpty,
        reason: '失败项不属于低置信校对清单',
      );
    });

    testWidgets('引用未知编号的元素被忽略：对应簇留在红区', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', '正常认领', ['m1']),
              _visionElement('body', '编造编号', ['m99']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(
        preparation.failedStrokeIds.map((id) => id.value),
        contains('k-s2'),
        reason: '无有效认领的簇按未识别进红区',
      );
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      expect(
        plan.addElements.whereType<TextElement>().map((e) => e.text),
        ['正常认领'],
      );
    });

    testWidgets('低置信标注：把握不足 → 计划携带橙色校对清单与场景矩形',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', '零散字一', ['m1'], confidence: 0.2),
              _visionElement('body', '零散字二', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      expect(plan.lowConfidenceTexts, hasLength(1));
      expect(plan.lowConfidenceTexts.single.confidence, 0.2);
      expect(plan.lowConfidenceRects, hasLength(1));
      expect(plan.lowConfidenceRects.single.isFinite, isTrue);
      expect(plan.lowConfidenceRects.single.width, greaterThan(0));
    });

    testWidgets('低置信裁剪重问：新结果把握更高才采用，救回的项不再标橙',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', 'M', ['m1'], confidence: 0.4),
              _visionElement('body', '子', ['m2']),
            ],
          );
      final reAskRequests = <SmartLayoutTranscribeRequest>[];
      controller.onTranscribeCrop = (request) async {
        reAskRequests.add(request);
        return const SmartLayoutTranscribeResponse(
          text: '先',
          confidence: 0.95,
        );
      };
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(reAskRequests, hasLength(1), reason: '只有把握不足的块被裁剪重问');
      expect(
        reAskRequests.single.imageBase64,
        isNotEmpty,
        reason: '重问请求应携带裁剪出的局部截图',
      );
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      final texts = plan.addElements
          .whereType<TextElement>()
          .map((e) => e.text)
          .toList();
      expect(texts, contains('先'), reason: '"M"应被重问纠正为"先"');
      expect(texts, isNot(contains('M')));
      expect(plan.lowConfidenceTexts, isEmpty, reason: '救回的项把握 0.95 不再标橙');
    });

    testWidgets('低置信裁剪重问：新结果把握不升 → 保留原结果并标橙', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', 'M', ['m1'], confidence: 0.4),
              _visionElement('body', '子', ['m2']),
            ],
          );
      controller.onTranscribeCrop = (request) async =>
          const SmartLayoutTranscribeResponse(text: '先', confidence: 0.3);
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      final texts = plan.addElements
          .whereType<TextElement>()
          .map((e) => e.text)
          .toList();
      expect(texts, contains('M'), reason: '重问结果把握更低，保留原识别');
      expect(plan.lowConfidenceTexts, hasLength(1), reason: '原把握 0.4 应标橙');
    });

    testWidgets('vision 接口抛异常 → 直接向上抛出（无经典管线回退）', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async {
        throw StateError('HTTP 502');
      };
      Object? caught;
      await tester.runAsync(() async {
        try {
          await controller.prepareSmartLayoutTemplates(pageId: 'page-1');
        } catch (error) {
          caught = error;
        }
      });
      expect(caught, isA<StateError>(), reason: '无回退，异常直接向上抛');
    });

    testWidgets('VLM 无元素 → 抛出提示重试', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          const SmartLayoutVisionResponse(elements: []);
      Object? caught;
      await tester.runAsync(() async {
        try {
          await controller.prepareSmartLayoutTemplates(pageId: 'page-1');
        } catch (error) {
          caught = error;
        }
      });
      expect(caught, isA<StateError>(), reason: '无内容时提示重试');
    });

    testWidgets('页面无手写 → 返回 null（无内容）', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      controller.onVisionSmartLayout = (request) async {
        throw StateError('不应被调用');
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNull);
    });
  });
}

MarkdrawController _buildController() {
  final controller = MarkdrawController(
    config: MarkdrawEditorConfig(
      initialLayout: CanvasLayout(
        type: CanvasLayoutType.paged,
        pages: const [
          CanvasPage(
            id: 'page-1',
            index: 0,
            bounds: Rect.fromLTWH(0, 0, 1588, 2246),
            template: CanvasPageTemplate.blank,
          ),
        ],
      ),
    ),
  );
  // 离线字体：避免测试环境触发 Google Fonts 网络加载
  controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
  return controller;
}

void _addStrokes(MarkdrawController controller) {
  void add(String id, String session, double x, double y, double w, double h) {
    controller.applyResult(
      AddElementResult(
        FreedrawElement(
          id: ElementId(id),
          x: x,
          y: y,
          width: w,
          height: h,
          points: const [Point(0, 0), Point(40, 20)],
          customData: {
            recognitionStrokeSessionKey: session,
            'flowMuse': {'pageId': 'page-1'},
          },
        ),
      ),
    );
  }

  add('k-s1', 's1', 200, 150, 300, 60);
  add('k-s2', 's2', 250, 400, 280, 56);
}

/// Set-of-Mark 测试桩：直接以编号引用候选对象（m1=簇s1、m2=簇s2、m3=img-cat）。
SmartLayoutVisionElement _visionElement(
  String role,
  String text,
  List<String> markIds, {
  String? id,
  String? pairId,
  double confidence = 0.9,
}) => SmartLayoutVisionElement(
  id: id,
  role: role,
  text: text.isEmpty ? null : text,
  markIds: markIds,
  pairId: pairId,
  confidence: confidence,
);
