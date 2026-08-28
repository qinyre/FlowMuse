import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视觉优先管线：模型解析、坐标映射/元素匹配纯函数、四风格分发与回退。
/// 文字转写为整页 VLM 单引擎（智能排版不使用 MyScript）；
/// VLM 无文本的项按失败进红区，低把握项进低置信校对清单。
void main() {
  group('SmartLayoutVisionElement 模型', () {
    test('解析 box 并钳制到 0-1000、交换倒置坐标、携带引用 id', () {
      final element = SmartLayoutVisionElement.fromJson({
        'id': 'e2',
        'role': 'caption',
        'text': '小羊睡觉',
        'vertical': true,
        'pairId': 'pair-1',
        'box': [-20, 1200, 500, 300],
      });
      expect(element.id, 'e2');
      expect(element.role, 'caption');
      expect(element.vertical, isTrue);
      expect(element.x1, 0);
      expect(element.y2, 1000);
      // y 倒置交换后 y1 <= y2
      expect(element.y1, lessThanOrEqualTo(element.y2));
    });

    test('sceneRect 把归一化框映射进页面矩形', () {
      const element = SmartLayoutVisionElement(
        role: 'body',
        text: '你好',
        x1: 100,
        y1: 50,
        x2: 600,
        y2: 250,
      );
      final pageBounds = Bounds.fromLTWH(0, 0, 1588, 2246);
      final rect = element.sceneRect(pageBounds);
      expect(rect.left, closeTo(158.8, 0.01));
      expect(rect.top, closeTo(112.3, 0.01));
      expect(rect.width, closeTo(1588 * 0.5, 0.01));
      expect(rect.height, closeTo(2246 * 0.2, 0.01));
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
          {'id': 'e0', 'role': 'body', 'text': '主题', 'box': [0, 0, 10, 10]},
          {'id': 'e1', 'role': 'body', 'text': '分支', 'box': [0, 20, 10, 30]},
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

  group('SmartLayoutVisionMatcher', () {
    final pageBounds = Offset.zero & const Size(1000, 1000);

    SmartLayoutVisionElement elem(
      String role,
      double x1,
      double y1,
      double x2,
      double y2, {
      String? text,
      String? pairId,
    }) => SmartLayoutVisionElement(
      role: role,
      text: text ?? (role == 'figure' ? null : '文字'),
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      pairId: pairId,
    );

    test('归一化框按页面坐标映射后认领覆盖率达标的所有笔迹簇', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [elem('body', 0, 0, 1000, 400)],
        pageBounds: pageBounds,
        inkClusters: {
          'a': const Rect.fromLTWH(100, 100, 200, 40),
          'b': const Rect.fromLTWH(800, 380, 200, 40),
          'c': const Rect.fromLTWH(850, 900, 100, 40),
        },
        figureUnits: {},
      );
      expect(match.textClaims[0], ['a', 'b']);
      expect(match.unclaimedClusterKeys, {'c'});
      expect(match.matchedItemCount, 1);
    });

    test('中心点容差认领：覆盖率不足但簇中心落在框外扩 8pt 内也认领', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [elem('body', 0, 0, 500, 400)],
        pageBounds: pageBounds,
        inkClusters: {
          'edge': const Rect.fromLTWH(490, 40, 30, 20),
          'far': const Rect.fromLTWH(600, 40, 30, 20),
        },
        figureUnits: {},
      );
      expect(match.textClaims[0], ['edge']);
      expect(match.unclaimedClusterKeys, {'far'});
    });

    test('二次合并：拆簇后大半落在已认领项并集框内的残簇并入同项', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [elem('body', 0, 0, 200, 100)],
        pageBounds: pageBounds,
        inkClusters: {
          'a': const Rect.fromLTWH(10, 10, 180, 120),
          'b': const Rect.fromLTWH(0, 90, 200, 80),
          'other': const Rect.fromLTWH(800, 900, 50, 50),
        },
        figureUnits: {},
      );
      expect(match.textClaims[0], ['a', 'b']);
      expect(match.unclaimedClusterKeys, {'other'});
    });

    test('图形项按 interArea/min 面积最大者唯一匹配场景单元', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [elem('figure', 0, 0, 600, 600)],
        pageBounds: pageBounds,
        inkClusters: {},
        figureUnits: {
          'img-a': const Rect.fromLTWH(0, 0, 600, 600),
          'img-b': const Rect.fromLTWH(550, 550, 450, 450),
        },
      );
      expect(match.figureClaims[0], 'img-a');
      final second = SmartLayoutVisionMatcher.match(
        elements: [
          elem('figure', 0, 0, 600, 600),
          elem('figure', 10, 10, 700, 700),
        ],
        pageBounds: pageBounds,
        inkClusters: {},
        figureUnits: {'img-a': const Rect.fromLTWH(0, 0, 600, 600)},
      );
      expect(second.figureClaims.keys.toList(), [0]);
    });

    test('认领与失败区互补：无匹配时全部簇进入失败集合', () {
      final match = SmartLayoutVisionMatcher.match(
        elements: [],
        pageBounds: pageBounds,
        inkClusters: {
          'a': const Rect.fromLTWH(0, 0, 10, 10),
        },
        figureUnits: {},
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
        return SmartLayoutVisionResponse(
          style: SmartLayoutStyle.ppt,
          confidence: 0.92,
          elements: [
            _boxCovering(
              'title',
              '手工记账',
              200,
              150,
              300,
              60,
              id: 'e0',
            ),
            _boxCovering(
              'caption',
              '流水明细一整段',
              250,
              400,
              280,
              56,
              id: 'e1',
              pairId: 'pair-1',
            ),
            _boxCovering(
              'figure',
              '',
              700,
              600,
              600,
              600,
              id: 'e2',
              pairId: 'pair-1',
            ),
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
              _boxCovering('title', '手工记账', 200, 150, 300, 60),
              _boxCovering('body', '流水明细一整段', 250, 400, 280, 56),
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
              _boxCovering('title', '文章标题', 200, 150, 300, 60),
              _boxCovering('body', '第一段内容', 250, 400, 280, 56),
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
              _boxCovering('body', '零散字一', 200, 150, 300, 60),
              _boxCovering('body', '零散字二', 250, 400, 280, 56),
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
              _boxCovering('body', '手写要点甲', 200, 150, 300, 60, id: 'e0'),
              _boxCovering('body', '手写要点乙', 250, 400, 280, 56, id: 'e1'),
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
              _boxCovering('body', 'VLM正文', 200, 150, 300, 60),
              _boxCovering('body', '', 250, 400, 280, 56),
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

    test('响应解析：元素 confidence 缺省 0.9 并钳制到 0-1', () {
      final response = SmartLayoutVisionResponse.fromJson({
        'style': 'in_place',
        'elements': [
          {'role': 'body', 'text': '未自报', 'box': [0, 0, 10, 10]},
          {'role': 'body', 'text': '过分自信', 'box': [0, 20, 10, 30], 'confidence': 2.5},
          {'role': 'body', 'text': '低把握', 'box': [0, 40, 10, 50], 'confidence': 0.25},
        ],
      });
      expect(response.elements[0].confidence, 0.9);
      expect(response.elements[1].confidence, 1);
      expect(response.elements[2].confidence, 0.25);
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
                _boxCovering('title', '手工记账', 200, 150, 300, 60),
                _boxCovering(
                  'caption',
                  '流水明细一整段',
                  250,
                  400,
                  280,
                  56,
                  pairId: 'pair-1',
                  confidence: 0.2,
                ),
                _boxCovering(
                  'figure',
                  '',
                  700,
                  600,
                  600,
                  600,
                  pairId: 'pair-1',
                ),
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

    testWidgets('低置信标注：in_place 引擎重建元素后按文本回填校对清单',
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
              _boxCovering('body', '零散字一', 200, 150, 300, 60,
                  confidence: 0.2),
              _boxCovering('body', '零散字二', 250, 400, 280, 56),
            ],
          );
      final SmartLayoutPlanResult result =
          (await tester.runAsync(
            () => controller.buildSmartLayoutPlan(pageId: 'page-1'),
          ))!;
      final plan = result.plan!;
      expect(plan.lowConfidenceTexts, hasLength(1));
      expect(plan.lowConfidenceTexts.single.confidence, 0.2);
      // legacy 引擎重建了元素 id：按原转写文本回填后仍能定位出场景矩形
      expect(plan.lowConfidenceRects, hasLength(1));
      expect(plan.lowConfidenceRects.single.isFinite, isTrue);
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

/// 由场景矩形反推 0-1000 归一化框（页面固定 1588x2246）。
SmartLayoutVisionElement _boxCovering(
  String role,
  String text,
  double left,
  double top,
  double width,
  double height, {
  String? id,
  String? pairId,
  double confidence = 0.9,
}) => SmartLayoutVisionElement(
  id: id,
  role: role,
  text: text.isEmpty ? null : text,
  x1: left / 1588 * 1000 - 5,
  y1: top / 2246 * 1000 - 5,
  x2: (left + width) / 1588 * 1000 + 5,
  y2: (top + height) / 2246 * 1000 + 5,
  pairId: pairId,
  confidence: confidence,
);
