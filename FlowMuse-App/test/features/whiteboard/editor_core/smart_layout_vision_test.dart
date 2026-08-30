import 'dart:convert';
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
  group('visionMarkLabelRect（SoM 徽章落位：不遮笔迹）', () {
    const canvas = Size(400, 300);
    const label = Size(30, 20);

    test('默认悬在簇框左上角上方（框外，间隙 2px）', () {
      final rect = MarkdrawController.visionMarkLabelRect(
        boxRect: const Rect.fromLTWH(100, 100, 80, 40),
        labelSize: label,
        canvasSize: canvas,
      );
      expect(rect, const Rect.fromLTWH(100, 78, 30, 20));
      expect(rect.bottom, lessThanOrEqualTo(100), reason: '徽章必须在框外上方');
    });

    test('顶部余量不足退到框下方', () {
      final rect = MarkdrawController.visionMarkLabelRect(
        boxRect: const Rect.fromLTWH(100, 10, 80, 40),
        labelSize: label,
        canvasSize: canvas,
      );
      expect(rect, const Rect.fromLTWH(100, 52, 30, 20));
    });

    test('上下都放不下（画布贴边）回框内左上角', () {
      final rect = MarkdrawController.visionMarkLabelRect(
        boxRect: const Rect.fromLTWH(100, 0, 80, 300),
        labelSize: label,
        canvasSize: canvas,
      );
      expect(rect, const Rect.fromLTWH(100, 0, 30, 20));
    });

    test('横向贴边时向内收，徽章不出画布', () {
      final rect = MarkdrawController.visionMarkLabelRect(
        boxRect: const Rect.fromLTWH(390, 100, 80, 40),
        labelSize: label,
        canvasSize: canvas,
      );
      expect(rect.left, 370, reason: '徽章右缘恰好在画布右缘');
      expect(rect.top, 78);
    });
  });

  group('SmartLayoutVisionElement 模型', () {
    test('解析 markIds 与引用 id；confidence 缺省 0.5 并钳制到 0-1', () {
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
      expect(defaults.confidence, 0.5, reason: '未自报把握视为存疑，触发裁剪重问');
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

    testWidgets('SoM 徽章只进 VLM 整页图，裁剪重问用无标记干净截图',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      String? markedImageBase64;
      controller.onVisionSmartLayout = (request) async {
        markedImageBase64 = request.imageBase64;
        return SmartLayoutVisionResponse(
          elements: [_visionElement('body', 'M', ['m1'], confidence: 0.4)],
        );
      };
      final reAskRequests = <SmartLayoutTranscribeRequest>[];
      controller.onTranscribeCrop = (request) async {
        reAskRequests.add(request);
        return const SmartLayoutTranscribeResponse(text: '先', confidence: 0.95);
      };
      await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(reAskRequests, hasLength(1), reason: '把握 0.4 的块被裁剪重问');
      expect(markedImageBase64, isNotNull);
      final markedHasBadge = await tester.runAsync(
        () => _hasBadgeRedPixel(markedImageBase64!),
      );
      final cropHasBadge = await tester.runAsync(
        () => _hasBadgeRedPixel(reAskRequests.single.imageBase64),
      );
      expect(
        markedHasBadge,
        isTrue,
        reason: '发往 VLM 的整页图应含编号徽章（红 0xFFE5484D）',
      );
      expect(
        cropHasBadge,
        isFalse,
        reason: '裁剪重问必须用无标记干净截图，避免徽章被二次转写',
      );
    });

    testWidgets('识别中取消 → 抛取消异常；再次准备正常工作（状态重置）',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      // 模拟用户在 VLM 处理期间点取消：vision mock 内先取消、延迟后返回结果，
      // prepare 应在检查点中止而不消费结果。
      controller.onVisionSmartLayout = (request) {
        controller.cancelSmartLayoutPreparation();
        return Future<SmartLayoutVisionResponse>.delayed(
          const Duration(milliseconds: 50),
          () => SmartLayoutVisionResponse(
            elements: [_visionElement('body', '不该被消费', ['m1'])],
          ),
        );
      };
      Object? caught;
      await tester.runAsync(() async {
        try {
          await controller.prepareSmartLayoutTemplates(pageId: 'page-1');
        } catch (error) {
          caught = error;
        }
      });
      expect(caught, isA<SmartLayoutCancelledException>());

      // 取消状态在下一次准备开始时重置：正常识别可完整走通。
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [_visionElement('body', '正常文本', ['m1'])],
          );
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull, reason: '取消后再次准备应正常工作');
    });

    testWidgets('全部文本被剥空且重问失败 → 提示重试（无空模板卡）', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      // 服务端回显剥离后保留的空文本元素形态：认领了簇但无文字。
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [_visionElement('body', '', ['m1'])],
          );
      controller.onTranscribeCrop = (request) async =>
          const SmartLayoutTranscribeResponse(text: '', confidence: 0);
      Object? caught;
      await tester.runAsync(() async {
        try {
          await controller.prepareSmartLayoutTemplates(pageId: 'page-1');
        } catch (error) {
          caught = error;
        }
      });
      expect(caught, isA<StateError>());
      expect(
        (caught as StateError).message,
        contains('未能识别出页面内容'),
        reason: '退化页应直接提示重试，而不是给三张空模板卡',
      );
    });

    testWidgets('figure-only 页（有图无字）不视为空内容', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.applyResult(
        AddElementResult(
          ImageElement(
            id: const ElementId('img-only'),
            x: 700,
            y: 600,
            width: 600,
            height: 600,
            fileId: 'file-only',
          ),
        ),
      );
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              // 两簇手写未被认领（进红区），仅图片被认领为图。
              _visionElement('figure', '', ['m3']),
            ],
          );
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull, reason: '有图即可排版，不算空内容');
      expect(preparation!.content.looseFigures, hasLength(1));
      expect(preparation.failedStrokeIds, isNotEmpty);
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

    testWidgets('图注几何配对兜底：VLM 漏配的 caption 就近绑图，不再与图分家',
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
      // 图注笔画紧贴图片下方（垂直间隙 50pt ≤ 64pt 阈值）。
      _addStroke(controller, 'k-cap', 'cap', 720, 1250, 120, 40);
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(4), reason: '两簇手写 + 图片 + 图注都编号');
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('body', '正文一整段', ['m1']),
            // caption 无 pairId——走查实况：VLM 漏配，靠几何兜底。
            _visionElement('caption', '图注一', ['m4']),
            _visionElement('figure', '', ['m3']),
          ],
        );
      };
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(preparation.content.pairs, hasLength(1), reason: '图注应兜底与图成组');
      expect(
        preparation.content.pairs.single.bottomTexts.single.textElement!.text,
        '图注一',
      );
      expect(preparation.content.pairs.single.figure.key, 'img-cat');
      expect(
        preparation.content.pairs.single.topTexts,
        isEmpty,
        reason: '原稿在图下方的图注归下方栈',
      );
      expect(
        preparation.content.looseTexts.map((u) => u.textElement!.text),
        ['正文一整段'],
        reason: '图注不应再混进正文流',
      );
      expect(preparation.content.looseFigures, isEmpty);
    });

    testWidgets('VLM pairId 主注 + 几何兜底标签同图成组：一图收多标签、各归上下栈',
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
      // 兜底标签：上方短标签"小猫"（距图顶 60pt ≤ 64）、侧方"图1"
      // （x 间隙 30pt ≤ 96 的图N 放宽档）；pairId 主注"流水明细"紧贴图下缘。
      _addStroke(controller, 'k-top', 'top', 800, 500, 100, 40);
      _addStroke(controller, 'k-side', 'side', 1330, 700, 60, 40);
      _addStroke(controller, 'k-cap', 'cap', 720, 1250, 120, 40);
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(6), reason: '两簇正文 + 上标签 + 图 + 侧标 + 图注');
        // 阅读序：m1/m2 两簇正文、m3 上标签、m4 图、m5 侧标、m6 图注。
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('body', '正文一段', ['m1']),
            // 上方标签：role=body、无 pairId——靠几何兜底补充。
            _visionElement('body', '小猫', ['m3']),
            _visionElement('figure', '', ['m4'], pairId: 'pair-1'),
            _visionElement('body', '图1', ['m5']),
            // pairId 主注：紧贴图下缘的 caption。
            _visionElement('caption', '流水明细', ['m6'], pairId: 'pair-1'),
          ],
        );
      };
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(preparation.content.pairs, hasLength(1), reason: '主注与兜底标签同图成组');
      final pair = preparation.content.pairs.single;
      expect(pair.figure.key, 'img-cat');
      expect(
        pair.topTexts.map((u) => u.textElement!.text),
        ['小猫'],
        reason: '原稿在图上方的兜底标签归上栈',
      );
      expect(
        pair.bottomTexts.map((u) => u.textElement!.text),
        ['图1', '流水明细'],
        reason: '下栈含侧方图N与 pairId 主注，按原稿阅读序',
      );
      expect(
        preparation.content.looseTexts.map((u) => u.textElement!.text),
        ['正文一段'],
        reason: '三枚标签都不再混进正文流',
      );
    });

    testWidgets('"图N"式标签即使 role=body 也参与就近配对（间隙放宽到 96pt）',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
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
      // 标签距图片下缘 90pt：超过 caption 阈值 64、在标签放宽阈值 96 内。
      _addStroke(controller, 'k-label', 'label', 720, 1290, 100, 40);
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(2));
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('figure', '', ['m1']),
            _visionElement('body', '图 1', ['m2']),
          ],
        );
      };
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(preparation.content.pairs, hasLength(1));
      expect(
        preparation.content.pairs.single.bottomTexts.single.textElement!.text,
        '图 1',
      );
      expect(preparation.content.looseTexts, isEmpty);
    });

    testWidgets('几何兜底不强绑：距离超阈值的图注留在正文流，图留在 looseFigures',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
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
      // 图注距图片下缘 300pt：远超兜底阈值，不强凑配对。
      _addStroke(controller, 'k-cap', 'cap', 720, 1500, 120, 40);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('figure', '', ['m1']),
              _visionElement('caption', '远处的图注', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(preparation.content.pairs, isEmpty, reason: '兜底只补漏，不硬绑');
      expect(
        preparation.content.looseTexts.map((u) => u.textElement!.text),
        contains('远处的图注'),
      );
      expect(preparation.content.looseFigures, hasLength(1));
    });

    testWidgets('竖排识别转写一律横排：不写 writingMode、按横排测量定尺寸',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      // 窄高单列笔迹：聚类阶段判为竖排列（整块识别），但转写必须横排。
      _addStroke(controller, 'k-v', 'v', 300, 150, 40, 200);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            elements: [
              _visionElement('body', '先头小子', ['m1'], vertical: true),
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
      final text = plan.addElements.whereType<TextElement>().single;
      final flowMuse = text.customData?['flowMuse'] as Map<String, Object?>?;
      expect(flowMuse?['writingMode'], isNull, reason: '不再产出竖排印刷体');
      expect(
        text.width,
        greaterThan(100),
        reason: '按横排测量撑宽（旧竖排窄长盒仅 40pt 宽）',
      );
    });

    test('isPunctuationOnlyText：纯标点/纯符号判真，含字母/数字/汉字判假', () {
      // Given：识别转写文本；When：纯标点判定；Then：只有无意义文本判真。
      expect(MarkdrawController.isPunctuationOnlyText('、'), isTrue);
      expect(MarkdrawController.isPunctuationOnlyText('~~~'), isTrue);
      expect(MarkdrawController.isPunctuationOnlyText('！？。'), isTrue);
      expect(MarkdrawController.isPunctuationOnlyText('图1'), isFalse);
      expect(MarkdrawController.isPunctuationOnlyText('正文一段'), isFalse);
      expect(MarkdrawController.isPunctuationOnlyText('abc'), isFalse);
      expect(MarkdrawController.isPunctuationOnlyText('100%'), isFalse);
      expect(
        MarkdrawController.isPunctuationOnlyText(''),
        isFalse,
        reason: '空文本由失败红区路径处理，不在此改变归属',
      );
      expect(MarkdrawController.isPunctuationOnlyText(null), isFalse);
    });

    testWidgets('纯标点转写：不生成文本元素，笔迹并入 removeIds 静默删除',
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
              _visionElement('body', '正文', ['m1']),
              _visionElement('body', '、', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(
        preparation.content.looseTexts.map((u) => u.textElement!.text),
        ['正文'],
        reason: '纯标点不进排版流',
      );
      expect(
        preparation.removeIds.map((id) => id.value),
        contains('k-s2'),
        reason: '纯标点笔迹随方案静默删除',
      );
      expect(
        preparation.failedStrokeIds.map((id) => id.value),
        isNot(contains('k-s2')),
        reason: '与识别失败红区区分：不需要用户选择即删',
      );
      expect(preparation.failures, isEmpty);
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.inplace,
          )
          .plan!;
      expect(
        plan.addElements.whereType<TextElement>().map((e) => e.text),
        isNot(contains('、')),
      );
    });

    testWidgets('噪点笔画（<8×8pt）并入 removeIds：随方案删除且不产生簇',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      // 孤立小墨点（勾/点/污渍）。
      _addStroke(controller, 'k-dot', 'dot', 900, 900, 5, 5);
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(2), reason: '噪点不编号、不产生簇');
        return SmartLayoutVisionResponse(
          elements: [_visionElement('body', '正文', ['m1'])],
        );
      };
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      expect(
        preparation.removeIds.map((id) => id.value),
        contains('k-dot'),
        reason: '噪点笔画消除"没排干净"的残留',
      );
      expect(
        preparation.failedStrokeIds.map((id) => id.value),
        isNot(contains('k-dot')),
      );
      final plan = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.handout,
          )
          .plan!;
      expect(plan.removeIds.map((id) => id.value), contains('k-dot'));
    });

    testWidgets('保留手写：文本块笔迹不删、经 moveDeltas 移动并入选区；草稿墨迹仍在',
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
              _visionElement('body', '零散字一', ['m1']),
              _visionElement('body', '零散字二', ['m2']),
            ],
          );
      final preparation = (await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      ))!;
      for (final kind in SmartLayoutTemplateKind.values) {
        expect(
          preparation.layoutsKeepInk[kind],
          isNotNull,
          reason: '${kind.displayName} 应有保留手写预落位',
        );
      }
      // 转写模式（默认）行为不变：笔迹整块删除、无移动。
      final typed = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.handout,
          )
          .plan!;
      expect(
        typed.removeIds.map((id) => id.value),
        containsAll(['k-s1', 'k-s2']),
      );
      expect(typed.moveDeltas, isEmpty);
      // 保留手写：笔迹从删除清单排除、随 moveDeltas 移动、进 selectIds。
      final ink = controller
          .buildSmartLayoutPlanForTemplate(
            preparation,
            SmartLayoutTemplateKind.handout,
            keepHandwriting: true,
          )
          .plan!;
      expect(
        ink.removeIds.map((id) => id.value),
        isNot(contains('k-s1')),
        reason: '文本块笔迹不删',
      );
      expect(ink.moveDeltas.keys, containsAll([const ElementId('k-s1'), const ElementId('k-s2')]));
      expect(ink.selectIds, contains(const ElementId('k-s1')));
      expect(ink.addElements.whereType<TextElement>(), isEmpty);
      expect(
        ink.removalRects,
        isEmpty,
        reason: '保留墨迹的簇矩形不再进灰区预览',
      );
      // 草稿态：墨迹仍在场景中并已按预览矩形落位。
      controller.enterSmartLayoutDraft(ink);
      final stroke = controller.editorState.scene.activeElements
          .where((e) => e.id == const ElementId('k-s1'))
          .single;
      expect(stroke.x, ink.previewRects.first.left);
      expect(stroke.y, ink.previewRects.first.top);
      controller.cancelSmartLayoutDraft();
    });

    test('配对兜底纯函数：就近分配、一图可收多标签、同分取图 top 小者、超阈不绑',
        () {
      // Given：两个与图注10等距（60pt）的候选图（top 不同）、一个超阈远图，
      // 以及两枚都贴图2的标签（多标签场景）。
      // When：matchUnpairedCaptionsByGeometry。
      // Then：图注10绑 top 更小者；两枚标签同图成组；远图不绑。
      final figures = {
        2: const Rect.fromLTWH(230, 570, 100, 100), // 距 caption10 30+30=60，top 570
        5: const Rect.fromLTWH(-50, 550, 100, 100), // 距 caption10 50+10=60，top 550
        9: const Rect.fromLTWH(2000, 0, 100, 100), // 超阈
      };
      final result = MarkdrawController.matchUnpairedCaptionsByGeometry(
        captions: {
          10: (
            bounds: const Rect.fromLTWH(100, 500, 100, 40),
            maxGap: kSmartLayoutCaptionPairMaxGap,
          ),
          11: (
            bounds: const Rect.fromLTWH(230, 720, 80, 30),
            maxGap: kSmartLayoutCaptionPairMaxGap,
          ),
          12: (
            bounds: const Rect.fromLTWH(235, 715, 80, 30),
            maxGap: kSmartLayoutCaptionPairMaxGap,
          ),
        },
        figures: figures,
      );
      expect(result[10], 5, reason: '距离同分取图 top 更小者（确定性）');
      expect(result[11], 2, reason: '距图2最近（50pt）');
      expect(result[12], 2, reason: '一图可收多标签：同图收两注不互斥');
      expect(result.containsValue(9), isFalse, reason: '超阈不绑');
    });
  });
  group('打字文本走同一管线（第六轮）', () {
    testWidgets('纯打字页：打字文本作为文本标记参与识别，计划克隆重排',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addTypedText(controller, 't-title', '机器标题', 100, 100);
      _addTypedText(controller, 't-body', '机器正文段落', 100, 300);
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(2), reason: '打字文本应与手写簇一样编号发出');
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('title', '', ['m1'], id: 'e0'),
            _visionElement('body', '', ['m2'], id: 'e1'),
          ],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull, reason: '无手写簇也有打字文本，不应拒绝');
      expect(preparation!.content.title!.textElement!.text, '机器标题');
      expect(
        preparation.content.looseTexts.single.textElement!.text,
        '机器正文段落',
      );
      expect(preparation.hasInkTextUnits, isFalse, reason: '无手写转写文本');

      final result = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.handout,
      );
      expect(result.error, isNull);
      final plan = result.plan!;
      final addedTexts = plan.addElements.whereType<TextElement>().toList();
      expect(
        addedTexts.map((e) => e.text),
        containsAll(['机器标题', '机器正文段落']),
      );
      expect(
        addedTexts.firstWhere((e) => e.text == '机器标题').fontSize,
        28,
        reason: '克隆版享受模板样式（标题放大到 28）',
      );
      expect(
        plan.removeIds.map((id) => id.value),
        containsAll(['t-title', 't-body']),
        reason: '默认模式原件随方案删除（克隆替换）',
      );
      expect(plan.moveDeltas, isEmpty, reason: '打字文本无墨迹可移动');
      expect(plan.removalRects, isNotEmpty, reason: '原件原位进灰区');

      // 保留手写变体：打字原元素整体移动而非删除。
      final keepResult = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.handout,
        keepHandwriting: true,
      );
      expect(keepResult.error, isNull);
      expect(
        keepResult.plan!.removeIds.map((id) => id.value),
        isEmpty,
        reason: '保留手写模式下打字原件从删除清单排除',
      );
      expect(
        keepResult.plan!.moveDeltas.keys.map((id) => id.value),
        containsAll(['t-title', 't-body']),
      );
      expect(
        keepResult.plan!.removalRects,
        isEmpty,
        reason: '保留手写模式灰区排除移动中的原件',
      );
    });

    testWidgets('混合页：打字图注与图片按 pairId 配对成组', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addTypedText(controller, 't-cap', '图1', 700, 500, width: 60, height: 30);
      controller.applyResult(
        AddElementResult(
          ImageElement(
            id: const ElementId('img-1'),
            x: 700,
            y: 600,
            width: 300,
            height: 300,
            fileId: 'file-1',
          ),
        ),
      );
      controller.onVisionSmartLayout = (request) async {
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('caption', '', ['m1'], id: 'e0', pairId: 'p1'),
            _visionElement('figure', '', ['m2'], id: 'e1', pairId: 'p1'),
          ],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(preparation!.content.pairs, hasLength(1));
      expect(
        preparation.content.pairs.first.texts.single.textElement!.text,
        '图1',
      );
      expect(
        preparation.content.pairs.first.figure.element,
        isA<ImageElement>(),
      );
      expect(preparation.content.looseTexts, isEmpty);
    });

    testWidgets('未认领的打字文本原地保留，不进红区也不删', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addTypedText(controller, 't-a', '被认领的文本', 100, 100);
      _addTypedText(controller, 't-b', '被忽略的文本', 100, 300);
      controller.onVisionSmartLayout = (request) async {
        return SmartLayoutVisionResponse(
          elements: [_visionElement('title', '', ['m1'], id: 'e0')],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(preparation!.failureRects, isEmpty, reason: '打字文本不进失败红区');
      expect(
        preparation.failedStrokeIds.map((id) => id.value),
        isEmpty,
      );
      expect(preparation.content.title!.textElement!.text, '被认领的文本');
      expect(
        preparation.content.looseTexts,
        isEmpty,
        reason: '未认领打字文本不参与排版',
      );
      final result = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.handout,
      );
      expect(
        result.plan!.removeIds.map((id) => id.value),
        ['t-a'],
        reason: '只有被认领的原件被克隆替换，未认领原件原地保留',
      );
    });

    testWidgets('重跑安全：上次智能排版产出按普通打字文本重新参与排版',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addTypedText(
        controller,
        't-old',
        '上次排版的标题',
        100,
        100,
        flowMuse: {'pageId': 'page-1', 'smartLayout': true},
      );
      controller.onVisionSmartLayout = (request) async {
        return SmartLayoutVisionResponse(
          elements: [_visionElement('title', '', ['m1'], id: 'e0')],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(preparation!.content.title!.textElement!.text, '上次排版的标题');
      final result = controller.buildSmartLayoutPlanForTemplate(
        preparation,
        SmartLayoutTemplateKind.handout,
      );
      expect(
        result.plan!.addElements.whereType<TextElement>().map((e) => e.text),
        contains('上次排版的标题'),
        reason: '旧产出重新排版后内容不丢',
      );
      expect(
        result.plan!.removeIds.map((id) => id.value),
        ['t-old'],
      );
    });
  });

  group('标题兜底（第七轮）', () {
    testWidgets('VLM 漏标 title：最上方短散文本提升为标题，不再掉进正文行',
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
        return SmartLayoutVisionResponse(
          elements: [
            _visionElement('body', '页面主标题啊', ['m1'], id: 'e0'),
            _visionElement('body', '正文一', ['m2'], id: 'e1'),
            _visionElement('figure', '', ['m3'], id: 'e2'),
          ],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(
        preparation!.content.title?.textElement?.text,
        '页面主标题啊',
        reason: '最上方短散文本应兜底为标题',
      );
      expect(
        preparation.content.looseTexts.map((u) => u.textElement?.text),
        ['正文一'],
        reason: '被提升的文本移出散文本',
      );
    });

    testWidgets('单元太少不兜底：孤立短文本不误抬成标题', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStroke(controller, 'k-solo', 's1', 200, 150, 300, 60);
      controller.onVisionSmartLayout = (request) async {
        return SmartLayoutVisionResponse(
          elements: [_visionElement('body', '唯一的文字', ['m1'], id: 'e0')],
        );
      };
      final preparation = await tester.runAsync(
        () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
      );
      expect(preparation, isNotNull);
      expect(preparation!.content.title, isNull);
      expect(preparation.content.looseTexts, hasLength(1));
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

/// 解码 base64 PNG（降采样到 800px 宽）并扫描是否存在徽章红像素：
/// 编号徽章只允许出现在发往 VLM 的整页图，裁剪重问图必须干净。
Future<bool> _hasBadgeRedPixel(String base64) async {
  final codec = await instantiateImageCodec(
    base64Decode(base64),
    targetWidth: 800,
  );
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    if (data == null) return false;
    final pixels = data.buffer.asUint8List();
    for (var i = 0; i + 2 < pixels.length; i += 4) {
      final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      // 徽章红 0xFFE5484D（留抗锯齿容差），与黑色笔迹/白色背景不重叠。
      if (r > 180 && g > 30 && g < 130 && b > 30 && b < 130 && r - g > 60) {
        return true;
      }
    }
    return false;
  } finally {
    codec.dispose();
  }
}

/// Set-of-Mark 测试桩：直接以编号引用候选对象（m1=簇s1、m2=簇s2、m3=img-cat）。
SmartLayoutVisionElement _visionElement(
  String role,
  String text,
  List<String> markIds, {
  String? id,
  String? pairId,
  double confidence = 0.9,
  bool vertical = false,
}) => SmartLayoutVisionElement(
  id: id,
  role: role,
  text: text.isEmpty ? null : text,
  markIds: markIds,
  pairId: pairId,
  confidence: confidence,
  vertical: vertical,
);

/// 添加单条手写笔画（page-1）。
void _addStroke(
  MarkdrawController controller,
  String id,
  String session,
  double x,
  double y,
  double w,
  double h,
) {
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

/// 添加打字文本元素（page-1）。
void _addTypedText(
  MarkdrawController controller,
  String id,
  String text,
  double x,
  double y, {
  double width = 200,
  double height = 40,
  double fontSize = 20,
  Map<String, Object?>? flowMuse,
}) {
  controller.applyResult(
    AddElementResult(
      TextElement(
        id: ElementId(id),
        x: x,
        y: y,
        width: width,
        height: height,
        text: text,
        fontSize: fontSize,
        // 捆绑字体，避免测试环境触发 Google Fonts 异步加载。
        fontFamily: 'Excalifont',
        customData: flowMuse == null ? null : {'flowMuse': flowMuse},
      ),
    ),
  );
}

