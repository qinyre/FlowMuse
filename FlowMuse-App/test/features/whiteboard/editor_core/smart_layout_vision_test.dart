import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视觉优先管线：模型解析、Set-of-Mark 编号直查匹配、四风格分发与回退。
/// 文字转写为整页 VLM 单引擎（智能排版不使用 MyScript）；
/// VLM 无文本的项按失败进红区，低把握项进低置信校对清单。
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

    test('响应解析：mindmap 结构树随 style 解析；非法树为 null', () {
      final response = SmartLayoutVisionResponse.fromJson({
        'style': 'mindmap',
        'confidence': 0.7,
        'structure': {
          'root': {
            'text': '主题',
            'blockIds': ['e0'],
            'children': [
              {'text': '分支', 'blockIds': ['e1'], 'children': []},
            ],
          },
        },
        'elements': [
          {'id': 'e0', 'role': 'body', 'text': '主题', 'markIds': ['m1']},
          {'id': 'e1', 'role': 'body', 'text': '分支', 'markIds': ['m2']},
        ],
      });
      expect(response.style, SmartLayoutStyle.mindmap);
      expect(response.confidence, 0.7);
      expect(response.mindmapStructure, isNotNull);
      expect(response.mindmapStructure!.root.text, '主题');

      final invalid = SmartLayoutVisionResponse.fromJson({
        'style': 'mindmap',
        // 缺 root → FormatException → null
        'structure': {},
        'elements': [],
      });
      expect(invalid.mindmapStructure, isNull);

      // 非 mindmap 不解析 structure
      final ppt = SmartLayoutVisionResponse.fromJson({
        'style': 'ppt',
        'structure': {
          'root': {'text': 'x'},
        },
        'elements': [],
      });
      expect(ppt.mindmapStructure, isNull);
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

  group('控制器视觉优先管线', () {
    testWidgets('ppt 判定 + pairId 配对 → 走 pairFlow；文字用整页 VLM 文本',
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
      var legacyCalled = false;
      controller.onSmartLayoutInk = (request) async {
        legacyCalled = true;
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async {
        expect(request.marks, hasLength(3), reason: '截图候选对象应编号发出');
        return SmartLayoutVisionResponse(
          style: SmartLayoutStyle.ppt,
          confidence: 0.92,
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
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      expect(result.plan, isNotNull, reason: 'vision 路径应产出计划');
      expect(legacyCalled, isFalse, reason: '不应触发经典管线');
      final plan = result.plan!;
      expect(plan.style, SmartLayoutStyle.ppt);
      expect(plan.confidence, 0.92);
      final addedTexts = plan.addElements.whereType<TextElement>().map(
        (element) => element.text,
      );
      expect(addedTexts, containsAll(['手工记账', '流水明细一整段']));
      expect(plan.moveDeltas.keys.map((id) => id.value), contains('img-cat'));
      expect(plan.removeIds.map((id) => id.value), containsAll(['k-s1']));
      expect(plan.failedStrokeIds, isEmpty);
    });

    testWidgets('ppt 无配对（两栏路径）标题也不丢失', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.ppt,
            confidence: 0.8,
            elements: [
              _visionElement('title', '手工记账', ['m1']),
              _visionElement('body', '流水明细一整段', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull);
      final addedTexts = plan!.addElements.whereType<TextElement>().map(
        (element) => element.text,
      );
      expect(
        addedTexts,
        containsAll(['手工记账', '流水明细一整段']),
        reason: '两栏路径不应丢弃标题',
      );
    });

    testWidgets('article 判定由视觉管线接管：按阅读流落位且不触发经典管线', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      var legacyCalled = false;
      controller.onSmartLayoutInk = (request) async {
        legacyCalled = true;
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.article,
            confidence: 0.85,
            elements: [
              _visionElement('title', '文章标题', ['m1']),
              _visionElement('body', '第一段内容', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull, reason: 'article 应由视觉管线产出计划');
      expect(legacyCalled, isFalse);
      expect(plan!.style, SmartLayoutStyle.article);
      final addedTexts =
          plan.addElements.whereType<TextElement>().map((e) => e.text);
      expect(addedTexts, containsAll(['文章标题', '第一段内容']));
    });

    testWidgets('in_place 判定：文字在原稿位置附近原地转换', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.inPlace,
            confidence: 0.6,
            elements: [
              _visionElement('body', '零散字一', ['m1']),
              _visionElement('body', '零散字二', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull);
      expect(plan!.style, SmartLayoutStyle.inPlace);
      // 原 in_place 语义：新增文本落在原稿附近（不移动物品、删除笔迹）
      expect(plan.moveDeltas, isEmpty);
      expect(plan.removeIds.map((id) => id.value), containsAll(['k-s1', 'k-s2']));
      for (final element in plan.addElements.whereType<TextElement>()) {
        final nearS1 = (element.x - 500).abs() < 400;
        expect(nearS1, isTrue, reason: '文本应留在原稿 ${element.x} 附近');
      }
    });

    testWidgets('mindmap 判定：VLM 树 + 整页 VLM 文本 → 导图节点与连线', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      var myScriptCalls = 0;
      controller.onRecognizeInk = (request) async {
        myScriptCalls++;
        throw StateError('整页 VLM 文本可用时不应调用 MyScript');
      };
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.mindmap,
            confidence: 0.88,
            mindmapStructure: MindmapStructure(root: MindmapStructureNode(
              text: '主题树根',
              children: [
                const MindmapStructureNode(text: '', blockIds: ['e0'], children: []),
                const MindmapStructureNode(text: '固定分支', blockIds: ['e1'], children: []),
              ],
            )),
            elements: [
              _visionElement('body', '手写要点甲', ['m1'], id: 'e0'),
              _visionElement('body', '手写要点乙', ['m2'], id: 'e1'),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull, reason: 'mindmap 应由视觉管线产出计划');
      expect(myScriptCalls, 0, reason: '整页 VLM 文本优先，无需逐块转写');
      expect(plan!.style, SmartLayoutStyle.mindmap);
      expect(plan.moveDeltas, isEmpty, reason: '导图为全新元素整体布置');
      final nodeCount = plan.addElements
          .whereType<RectangleElement>()
          .where((e) => !_isObstacleLike(e))
          .length;
      expect(nodeCount, greaterThanOrEqualTo(3));
      expect(
        plan.addElements.whereType<ArrowElement>().length,
        greaterThanOrEqualTo(2),
        reason: '根到两分支应有连线',
      );
      final texts =
          plan.addElements.whereType<TextElement>().map((e) => e.text).join('|');
      expect(texts, contains('手写要点甲'), reason: '导图节点文字来自整页 VLM 文本');
      expect(texts, contains('手写要点乙'));
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
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.inPlace,
            elements: [
              _visionElement('body', 'VLM正文', ['m1']),
              _visionElement('body', '', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull);
      final texts = plan!
          .addElements
          .whereType<TextElement>()
          .map((e) => e.text)
          .toList();
      expect(texts, contains('VLM正文'), reason: 'VLM 有文本时直接采用');
      expect(texts, isNot(contains('MyScript正文')));
      expect(myScriptCalls, 0, reason: '智能排版已完全摘除 MyScript');
      expect(result.hasFailures, isTrue, reason: 'VLM 无文本项按失败进红区');
      expect(
        plan.failedStrokeIds.map((id) => id.value),
        contains('k-s2'),
        reason: '无文本项的原笔迹留在红区待用户处置',
      );
      expect(
        plan.lowConfidenceTexts,
        isEmpty,
        reason: '失败项不属于低置信校对清单',
      );
    });

    testWidgets('引用未知编号的元素被忽略：对应簇留在红区且不回退经典管线',
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
      var legacyCalled = false;
      controller.onSmartLayoutInk = (request) async {
        legacyCalled = true;
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.ppt,
            elements: [
              _visionElement('figure', '', ['m3']),
              _visionElement('body', '正常认领', ['m1']),
              _visionElement('body', '编造编号', ['m99']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan;
      expect(plan, isNotNull);
      expect(legacyCalled, isFalse);
      expect(
        plan!.failedStrokeIds.map((id) => id.value),
        contains('k-s2'),
        reason: '无有效认领的簇按未识别进红区',
      );
      expect(
        plan.addElements.whereType<TextElement>().map((e) => e.text),
        ['正常认领'],
      );
    });

    testWidgets(
      '低置信标注：VLM 自报把握不足 → 计划携带橙色校对清单与场景矩形',
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
        controller.onSmartLayoutInk = (request) async {
          throw StateError('不应回退');
        };
        controller.onVisionSmartLayout = (request) async =>
            SmartLayoutVisionResponse(
              style: SmartLayoutStyle.ppt,
              confidence: 0.9,
              elements: [
                _visionElement('title', '手工记账', ['m1']),
                _visionElement(
                  'caption',
                  '流水明细一整段',
                  ['m2'],
                  pairId: 'pair-1',
                  confidence: 0.2,
                ),
                _visionElement('figure', '', ['m3'], pairId: 'pair-1'),
              ],
            );
        final SmartLayoutPlanResult result =
            (await tester.runAsync(
              () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
            ))!;
        final plan = result.plan!;
        expect(plan.lowConfidenceTexts, hasLength(1));
        expect(plan.lowConfidenceTexts.single.confidence, 0.2);
        // 场景矩形可定位（PPT 家族保留原元素 id），且为有效矩形
        expect(plan.lowConfidenceRects, hasLength(1));
        expect(plan.lowConfidenceRects.single.isFinite, isTrue);
        expect(plan.lowConfidenceRects.single.width, greaterThan(0));
      },
    );

    testWidgets('低置信标注：in_place 引擎重建元素后按 blockId 直查校对清单',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.inPlace,
            elements: [
              _visionElement('body', '零散字一', ['m1'], confidence: 0.2),
              _visionElement('body', '零散字二', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan!;
      expect(plan.lowConfidenceTexts, hasLength(1));
      expect(plan.lowConfidenceTexts.single.confidence, 0.2);
      // legacy 引擎重建了元素 id：blockId 直查后仍能定位出场景矩形
      expect(plan.lowConfidenceRects, hasLength(1));
      expect(plan.lowConfidenceRects.single.isFinite, isTrue);
    });

    testWidgets('低置信标注：article 多行段落拆行后整段行元素一并标注',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onSmartLayoutInk = (request) async {
        throw StateError('不应回退');
      };
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(
            style: SmartLayoutStyle.article,
            elements: [
              _visionElement('body', '第一行内容\n第二行内容', ['m1'],
                  confidence: 0.2),
              _visionElement('body', '把握十足', ['m2']),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan!;
      // "e0-line-0/-line-1" 两行元素都继承同一低置信来源，全部标注
      expect(plan.lowConfidenceTexts, hasLength(2));
      expect(plan.lowConfidenceRects, hasLength(2));
    });

    testWidgets('vision 接口抛异常 → 自动回退经典管线并成功', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async {
        throw StateError('HTTP 502');
      };
      controller.onSmartLayoutInk = (request) async {
        return SmartLayoutResponse(
          document: const SmartLayoutDocument(version: 1, generatedAt: 1, blocks: []),
          blocks: [
            for (final block in request.blocks)
              SmartLayoutRecognizedBlock(
                id: block.id,
                type: 'text',
                text: '经典识别 ${block.id}',
                pageId: 'page-1',
                bounds: block.bounds,
              ),
          ],
          pages: const [
            SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
          ],
        );
      };
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      expect(result.plan, isNotNull, reason: 'vision 失败应回退经典管线');
    });
  });
}

bool _isObstacleLike(RectangleElement element) => false;

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
