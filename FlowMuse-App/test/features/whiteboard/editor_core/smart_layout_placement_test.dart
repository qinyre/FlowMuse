import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('智能排版 article 与普通识别块都会避让场景视觉占用', () async {
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
            CanvasPage(
              id: 'page-2',
              index: 1,
              bounds: Rect.fromLTWH(0, 896, 800, 800),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    final pageOneBlocker = RectangleElement(
      id: ElementId('page-1-blocker'),
      x: 72,
      y: 72,
      width: 420,
      height: 120,
      angle: 0.2,
      customData: const {
        'flowMuse': {'pageId': 'page-1'},
      },
    );
    final pageTwoBlocker = LineElement(
      id: ElementId('page-2-blocker'),
      x: 72,
      y: 968,
      width: 656,
      height: 0,
      points: const [Point(0, 0), Point(656, 0)],
      customData: const {
        'flowMuse': {'pageId': 'page-2'},
      },
    );
    controller.applyResult(AddElementResult(pageOneBlocker));
    controller.applyResult(AddElementResult(pageTwoBlocker));
    controller.applyResult(
      AddElementResult(_stroke('stroke-1', 's1', 90, 90, 'page-1')),
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke-2', 's2', 90, 990, 'page-2')),
    );
    controller.onSmartLayoutInk = (request) async {
      final pageOne = request.blocks.singleWhere(
        (block) => block.pageId == 'page-1',
      );
      final pageTwo = request.blocks.singleWhere(
        (block) => block.pageId == 'page-2',
      );
      return SmartLayoutResponse(
        document: SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [
            SmartLayoutBlock(
              id: 'article',
              type: 'paragraph',
              text: '文章段落',
              pageId: 'page-1',
              bounds: Bounds.fromLTWH(72, 72, 320, 40),
            ),
          ],
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: pageOne.id,
            type: 'text',
            text: '文章段落',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(72, 72, 320, 40),
          ),
          SmartLayoutRecognizedBlock(
            id: pageTwo.id,
            type: 'text',
            text: '普通识别块',
            pageId: 'page-2',
            bounds: Bounds.fromLTWH(72, 968, 320, 40),
          ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: 'page-1', mode: 'article'),
          SmartLayoutPageDecision(pageId: 'page-2', mode: 'in_place'),
        ],
      );
    };

    expect(await controller.runGlobalSmartLayout(), isTrue);

    final generated = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .where((element) => _flowMuse(element)['smartLayout'] == true)
        .toList();
    expect(generated, hasLength(2));
    final article = generated.singleWhere(
      (element) => element.pageId == 'page-1',
    );
    final ordinary = generated.singleWhere(
      (element) => element.pageId == 'page-2',
    );
    expect(
      AlignmentUtils.visualBounds(
        article,
      ).intersects(AlignmentUtils.visualBounds(pageOneBlocker)),
      isFalse,
    );
    expect(
      AlignmentUtils.visualBounds(
        ordinary,
      ).intersects(Bounds.fromLTWH(72, 964, 656, 8)),
      isFalse,
    );
  });

  test('智能排版无合法空位时原子失败且不增加历史', () async {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: const [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 800, 500),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.insertPlainText('旧编辑');
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('full-content'),
          x: 72,
          y: 72,
          width: 656,
          height: 356,
          customData: const {
            'flowMuse': {'pageId': 'page-1'},
          },
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke', 's1', 90, 90, 'page-1')),
    );
    final beforeIds = {
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    };
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          blocks: [],
          generatedAt: 1,
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            text: '没有空位',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(72, 72, 320, 40),
          ),
        ],
      );
    };

    await expectLater(
      controller.runGlobalSmartLayout(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '智能排版没有足够的空白区域',
        ),
      ),
    );
    expect({
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    }, beforeIds);
    expect(sceneChanges, 0);

    controller.undo();
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => !element.isCanvasPage,
      ),
      isEmpty,
    );
  });

  test('智能排版向下无空间时会使用右侧合法空位', () async {
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
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('left-column'),
          x: 96,
          y: 96,
          width: 320,
          height: 608,
          customData: const {
            'flowMuse': {'pageId': 'page-1'},
          },
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(_stroke('stroke', 's1', 110, 110, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          blocks: [],
          generatedAt: 1,
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            text: '右侧内容',
            pageId: 'page-1',
            bounds: Bounds.fromLTWH(96, 96, 280, 40),
          ),
        ],
      );
    };

    expect(await controller.runGlobalSmartLayout(), isTrue);
    final generated = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .single;
    expect(generated.x, greaterThan(416));
    expect(generated.x + generated.width, lessThanOrEqualTo(704));
  });

  test('无限画布智能排版避让旋转元素和零高度线并可一次撤销', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    final rotated = RectangleElement(
      id: ElementId('unbounded-rotated'),
      x: 80,
      y: 80,
      width: 320,
      height: 100,
      angle: 0.35,
    );
    final line = LineElement(
      id: ElementId('unbounded-line'),
      x: 40,
      y: 240,
      width: 600,
      height: 0,
      points: const [Point(0, 0), Point(600, 0)],
    );
    controller.applyResult(AddElementResult(rotated));
    controller.applyResult(AddElementResult(line));
    controller.applyResult(
      AddElementResult(_stroke('stroke', 's1', 100, 100, 'page-1')),
    );
    controller.onSmartLayoutInk = (request) async {
      final block = request.blocks.single;
      return SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          blocks: [],
          generatedAt: 1,
        ),
        blocks: [
          SmartLayoutRecognizedBlock(
            id: block.id,
            type: 'text',
            text: '无限画布内容',
            pageId: block.pageId,
            bounds: Bounds.fromLTWH(100, 100, 280, 40),
          ),
        ],
      );
    };

    expect(await controller.runGlobalSmartLayout(), isTrue);
    final generated = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .single;
    final bounds = AlignmentUtils.visualBounds(generated);
    expect(bounds.intersects(AlignmentUtils.visualBounds(rotated)), isFalse);
    expect(bounds.intersects(Bounds.fromLTWH(40, 236, 600, 8)), isFalse);

    controller.undo();
    expect(
      controller.editorState.scene.activeElements.whereType<TextElement>(),
      isEmpty,
    );
    expect(
      controller.editorState.scene.activeElements.whereType<FreedrawElement>(),
      hasLength(1),
    );
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
