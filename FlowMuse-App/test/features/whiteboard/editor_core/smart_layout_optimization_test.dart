import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MarkdrawController buildController() {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: const [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 800, 800),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    return controller;
  }

  test('in_place 计划：构建后应用一次可撤销', () async {
    final controller = buildController();
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            text: '测试文字',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(90, 90, 200, 28),
          ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
      );
    };

    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull);
    expect(result.plan!.style, SmartLayoutStyle.inPlace);
    expect(result.plan!.addElements, isNotEmpty);
    expect(result.plan!.removeIds, hasLength(1)); // 原笔迹

    expect(controller.applySmartLayoutPlan(result.plan!), isTrue);
    final texts = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .where((element) => element.text == '测试文字');
    expect(texts, isNotEmpty);
    // 笔迹已被删除
    expect(
      controller.editorState.scene.activeElements
          .where((element) => element.id == ElementId('stroke-1')),
      isEmpty,
    );

    // 一次撤销恢复：文本消失、笔迹回归
    controller.undo();
    expect(
      controller.editorState.scene.activeElements
          .whereType<TextElement>()
          .where((element) => element.text == '测试文字'),
      isEmpty,
    );
    expect(
      controller.editorState.scene.activeElements
          .where((element) => element.id == ElementId('stroke-1')),
      isNotEmpty,
    );
  });

  test('mindmap 风格：计划包含树元素，应用后手写被替换为导图', () async {
    final controller = buildController();
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke-2', 's2', 150, 90, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          for (final block in request.blocks)
            SmartLayoutRecognizedBlock(
              id: block.id,
              type: 'text',
              text: block.id.endsWith('s1') ? '主题' : '分支',
              pageId: 'page-1',
              bounds: Bounds.fromLTWH(
                block.bounds.left,
                block.bounds.top,
                200,
                28,
              ),
            ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
        layout: SmartLayoutLayoutDecision(
          style: SmartLayoutStyle.mindmap,
          confidence: 0.9,
          mindmapStructure: const MindmapStructure(
            root: MindmapStructureNode(
              text: '主题',
              children: [MindmapStructureNode(text: '分支', children: [])],
            ),
          ),
        ),
      );
    };

    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    expect(result.plan, isNotNull);
    expect(result.plan!.style, SmartLayoutStyle.mindmap);
    expect(
      result.plan!.addElements.whereType<RectangleElement>(),
      isNotEmpty,
    );
    expect(result.plan!.description, contains('思维导图'));

    expect(controller.applySmartLayoutPlan(result.plan!), isTrue);
    final rects = controller.editorState.scene.activeElements
        .whereType<RectangleElement>()
        .where((element) => !element.isCanvasPage)
        .where((element) => _flowMuse(element)['role'] == 'mindmap-node');
    // 根 + 分支 = 2 个矩形节点
    expect(rects.length, 2);
    // 手写笔迹全部被替换
    expect(
      controller.editorState.scene.activeElements
          .where((element) => element.id == ElementId('stroke-1')),
      isEmpty,
    );
    expect(
      controller.editorState.scene.activeElements
          .where((element) => element.id == ElementId('stroke-2')),
      isEmpty,
    );
  });

  test('识别失败：无成功块时计划为空并携带失败信息', () async {
    final controller = buildController();
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(90, 90, 200, 28),
            error: '识别失败',
          ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
      );
    };

    final result = await controller.buildSmartLayoutPlan(pageId: 'page-1');
    // 无成功块 → 无计划（整页失败语义）
    expect(result.plan, isNull);
    expect(result.failures, isNotEmpty);
    expect(result.failures.first.blockId, isNotEmpty);
    expect(result.failures.first.error, '识别失败');
    // 场景未被改动（all-or-nothing）
    expect(
      controller.editorState.scene.activeElements
          .where((element) => element.id == ElementId('stroke-1')),
      isNotEmpty,
    );
  });

  test('compose 抛错时计划构建向上抛且场景不变', () async {
    final controller = buildController();
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    final beforeIds = {
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    };
    controller.onSmartLayoutInk = (request) async {
      throw StateError('智能排版没有足够的空白区域');
    };

    await expectLater(
      controller.buildSmartLayoutPlan(pageId: 'page-1'),
      throwsA(isA<StateError>()),
    );
    expect({
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    }, beforeIds);
  });

  test('幽灵预览状态可设置与清除', () {
    final controller = buildController();
    expect(controller.smartLayoutGhost.value, isNull);
    controller.setSmartLayoutGhost(
      const SmartLayoutGhostSpec.preview(
        previewRects: [Rect.fromLTWH(0, 0, 10, 10)],
        removalRects: [],
      ),
    );
    expect(controller.smartLayoutGhost.value, isNotNull);
    expect(controller.smartLayoutGhost.value!.isFailure, isFalse);
    controller.setSmartLayoutGhost(
      const SmartLayoutGhostSpec.failures(
        failureRects: [Rect.fromLTWH(0, 0, 10, 10)],
      ),
    );
    expect(controller.smartLayoutGhost.value!.isFailure, isTrue);
    controller.setSmartLayoutGhost(null);
    expect(controller.smartLayoutGhost.value, isNull);
  });

  test('指定 requestedStyle 时优先于服务端判定', () async {
    final controller = buildController();
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            text: '测试文字',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(90, 90, 200, 28),
          ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'in_place'),
        ],
      );
    };

    // 服务端判定 in_place，但用户强制 article
    final result = await controller.buildSmartLayoutPlan(
      pageId: 'page-1',
      requestedStyle: SmartLayoutStyle.article,
    );
    expect(result.plan, isNotNull);
    expect(result.plan!.style, SmartLayoutStyle.article);
  });
}

FreedrawElement _stroke(
  String id,
  String sessionId,
  double x,
  double y,
  String pageId,
) => FreedrawElement(
  id: ElementId(id),
  x: x,
  y: y,
  width: 40,
  height: 20,
  points: const [Point(0, 0), Point(40, 20)],
  customData: {
    recognitionStrokeSessionKey: sessionId,
    'flowMuse': {'pageId': pageId},
  },
);

Map<String, Object?> _flowMuse(Element element) =>
    Map<String, Object?>.from(element.customData!['flowMuse']! as Map);
