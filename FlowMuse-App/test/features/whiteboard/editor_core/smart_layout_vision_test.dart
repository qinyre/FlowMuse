import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视觉优先管线：模型解析、坐标映射/元素匹配纯函数、控制器接线与回退。
void main() {
  group('SmartLayoutVisionElement 模型', () {
    test('解析 box 并钳制到 0-1000、交换倒置坐标', () {
      final element = SmartLayoutVisionElement.fromJson({
        'role': 'caption',
        'text': '小羊睡觉',
        'vertical': true,
        'pairId': 'pair-1',
        'box': [-20, 1200, 500, 300],
      });
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

    test('响应解析：风格白名单外回落 in_place，isSupported 只认三种', () {
      final response = SmartLayoutVisionResponse.fromJson({
        'style': 'diagram',
        'elements': [
          {'role': 'figure', 'box': [0, 0, 10, 10]},
        ],
      });
      expect(response.style, SmartLayoutStyle.inPlace);
      expect(response.isSupported, isTrue);
      expect(
        const SmartLayoutVisionResponse(
          style: SmartLayoutStyle.mindmap,
          elements: [],
        ).isSupported,
        isFalse,
      );
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
      // 页面 1000x1000；簇 A 全在框内、簇 B 一半在内（覆盖率 0.5 达标）、
      // 簇 C 完全在外。
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
      // 第二个图形项不能再认领已占用单元
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
    testWidgets('ppt 判定 + 框覆盖原稿 → 走 pairFlow 模板产出计划', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      // 配图原稿（与 caption 的 pairId 配对后由模板整体平移）
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
        expect(request.pageId, 'page-1');
        expect(request.imageBase64, isNotEmpty);
        return SmartLayoutVisionResponse(
          style: SmartLayoutStyle.ppt,
          confidence: 0.92,
          elements: [
            // 页面 1588x2246：框恰好罩住对应原稿
            _boxCovering('title', '手工记账', 200, 150, 300, 60),
            _boxCovering(
              'caption',
              '流水明细一整段',
              250,
              400,
              280,
              56,
              pairId: 'pair-1',
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

    testWidgets('vision 判定非接管风格（article）→ 回退经典管线', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _buildController();
      addTearDown(controller.dispose);
      _addStrokes(controller);
      controller.onVisionSmartLayout = (request) async =>
          SmartLayoutVisionResponse(style: SmartLayoutStyle.article, elements: []);
      var legacyCalled = false;
      controller.onSmartLayoutInk = (request) async {
        legacyCalled = true;
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
      expect(result.plan, isNotNull);
      expect(legacyCalled, isTrue, reason: 'article 风格应由经典管线处理');
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

/// 由场景矩形反推 0-1000 归一化框（页面固定 1588x2246）。
SmartLayoutVisionElement _boxCovering(
  String role,
  String text,
  double left,
  double top,
  double width,
  double height, {
  String? pairId,
}) => SmartLayoutVisionElement(
  role: role,
  text: text.isEmpty ? null : text,
  x1: left / 1588 * 1000 - 5,
  y1: top / 2246 * 1000 - 5,
  x2: (left + width) / 1588 * 1000 + 5,
  y2: (top + height) / 2246 * 1000 + 5,
  pairId: pairId,
);
