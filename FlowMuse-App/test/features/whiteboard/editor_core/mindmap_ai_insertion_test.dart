import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI 思维导图作为一次场景变更插入并可一次撤销', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;

    controller.insertMindmap(
      MindmapNode(
        text: '中心主题',
        children: [
          MindmapNode(text: '分支一'),
          MindmapNode(text: '分支二'),
        ],
      ),
    );

    final elements = controller.editorState.scene.activeElements
        .where((element) => !element.isCanvasPage)
        .toList();
    expect(elements.whereType<RectangleElement>(), hasLength(3));
    expect(elements.whereType<TextElement>(), hasLength(3));
    expect(elements.whereType<ArrowElement>(), hasLength(2));
    expect(sceneChanges, 1);

    final bounds = elements
        .map(
          (element) => Rect.fromLTWH(
            element.x,
            element.y,
            element.width,
            element.height,
          ),
        )
        .reduce((left, right) => left.expandToInclude(right));
    expect(bounds.center.dx, closeTo(400, 0.001));
    expect(bounds.center.dy, closeTo(300, 0.001));

    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  test('宽度超过视口时从可见区域左边距开始布局', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);

    controller.insertMindmap(
      MindmapNode(
        text: '第一层',
        children: [
          MindmapNode(
            text: '第二层',
            children: [
              MindmapNode(
                text: '第三层',
                children: [MindmapNode(text: '第四层')],
              ),
            ],
          ),
        ],
      ),
    );

    final left = controller.editorState.scene.activeElements
        .map((element) => element.x)
        .reduce((left, right) => left < right ? left : right);
    expect(left, closeTo(48, 0.001));
  });

  test('连续插入三棵导图会避让旋转元素和零高度线', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    final rotated = RectangleElement(
      id: ElementId('rotated'),
      x: 260,
      y: 180,
      width: 280,
      height: 80,
      angle: 0.7853981633974483,
    );
    final line = LineElement(
      id: ElementId('line'),
      x: 32,
      y: 480,
      width: 736,
      height: 0,
      points: const [Point(0, 0), Point(736, 0)],
    );
    controller.applyResult(AddElementResult(rotated));
    controller.applyResult(AddElementResult(line));

    final insertedBounds = <Bounds>[];
    for (var index = 0; index < 3; index++) {
      final before = {
        for (final element in controller.editorState.scene.activeElements)
          element.id,
      };
      controller.insertMindmap(
        MindmapNode(
          text: '主题 $index',
          children: [MindmapNode(text: '分支 $index')],
        ),
      );
      final inserted = controller.editorState.scene.activeElements
          .where((element) => !before.contains(element.id))
          .toList();
      insertedBounds.add(_visualUnion(inserted));
    }

    final rotatedBounds = AlignmentUtils.visualBounds(rotated);
    final lineBounds = Bounds.fromLTWH(32, 476, 736, 8);
    for (final bounds in insertedBounds) {
      expect(bounds.intersects(rotatedBounds), isFalse);
      expect(bounds.intersects(lineBounds), isFalse);
    }
    expect(insertedBounds[0].intersects(insertedBounds[1]), isFalse);
    expect(insertedBounds[0].intersects(insertedBounds[2]), isFalse);
    expect(insertedBounds[1].intersects(insertedBounds[2]), isFalse);
  });

  test('视口中心在页间时从主要可见的第二页插入并保持绑定归属', () {
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
            CanvasPage(
              id: 'page-2',
              index: 1,
              bounds: Rect.fromLTWH(0, 596, 800, 500),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.setViewport(const ViewportState(offset: Offset(0, 270)));

    controller.insertMindmap(
      MindmapNode(
        text: '第二页主题',
        children: [MindmapNode(text: '子节点')],
      ),
    );
    controller.mindmapAddChild();

    final elements = controller.editorState.scene.activeElements
        .where((element) => !element.isCanvasPage)
        .toList();
    _expectMindmapIntegrity(elements, 'page-2');
    final encoded = ExcalidrawJsonCodec.serialize(
      MarkdrawDocument(sections: [SketchSection(elements)]),
    );
    _expectMindmapIntegrity(
      ExcalidrawJsonCodec.parse(
        encoded,
      ).value.allElements.where((element) => !element.isCanvasPage).toList(),
      'page-2',
    );
  });

  test('满页后按最后一页真实边界追加标准页并聚焦根节点', () {
    const secondPage = Rect.fromLTWH(40, 596, 900, 700);
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
            CanvasPage(
              id: 'page-2',
              index: 1,
              bounds: secondPage,
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.setViewport(const ViewportState(offset: Offset(40, 650)));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('full-page'),
          x: secondPage.left + 72,
          y: secondPage.top + 72,
          width: secondPage.width - 144,
          height: secondPage.height - 144,
          customData: const {
            'flowMuse': {'pageId': 'page-2'},
          },
        ),
      ),
    );

    controller.insertMindmap(
      MindmapNode(
        text: '追加页主题',
        children: [MindmapNode(text: '分支')],
      ),
    );

    expect(controller.layout.pages, hasLength(3));
    final appended = controller.layout.pages.last;
    expect(
      appended.bounds.top,
      closeTo(secondPage.bottom + CanvasLayout.pageGap, 0.001),
    );
    final rootId = controller.editorState.selectedIds.single;
    final root = controller.editorState.scene.getElementById(rootId)!;
    expect(root.pageId, appended.id);
    final visible = controller.editorState.viewport.visibleRect(
      const Size(800, 600),
    );
    expect(visible.contains(Offset(root.x, root.y)), isTrue);
    expect(
      visible.contains(Offset(root.x + root.width, root.y + root.height)),
      isTrue,
    );

    controller.undo();
    expect(controller.layout.pages, hasLength(2));
    expect(controller.editorState.selectedIds, isEmpty);
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => element.pageId == appended.id,
      ),
      isEmpty,
    );

    controller.redo();
    expect(controller.layout.pages, hasLength(3));
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => element.pageId == appended.id,
      ),
      isNotEmpty,
    );
    expect(
      controller.editorState.selectedIds.every(
        (id) => controller.editorState.scene.getElementById(id) != null,
      ),
      isTrue,
    );
  });

  test('RTL 混合尺寸页面按最后一页真实左边界追加', () {
    const lastPage = Rect.fromLTWH(-1100, 40, 900, 700);
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pageFlow: CanvasPageFlow.rightToLeft,
          pages: const [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 800, 500),
              template: CanvasPageTemplate.blank,
              pageFlow: CanvasPageFlow.rightToLeft,
            ),
            CanvasPage(
              id: 'page-2',
              index: 1,
              bounds: lastPage,
              template: CanvasPageTemplate.blank,
              pageFlow: CanvasPageFlow.rightToLeft,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.setViewport(const ViewportState(offset: Offset(-1100, 80)));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('full-rtl-page'),
          x: lastPage.left + 72,
          y: lastPage.top + 72,
          width: lastPage.width - 144,
          height: lastPage.height - 144,
          customData: const {
            'flowMuse': {'pageId': 'page-2'},
          },
        ),
      ),
    );

    controller.insertMindmap(
      MindmapNode(
        text: 'RTL 追加页',
        children: [MindmapNode(text: '分支')],
      ),
    );

    final appended = controller.layout.pages.last;
    expect(
      appended.bounds.right,
      closeTo(lastPage.left - CanvasLayout.pageGap, 0.001),
    );
    expect(appended.bounds.overlaps(lastPage), isFalse);
  });

  test('分页超大导图受控失败且不污染历史', () {
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
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;
    controller.insertPlainText('旧编辑');
    final changesBeforeFailure = sceneChanges;

    expect(
      () => controller.insertMindmap(
        MindmapNode(
          text: '超大主题',
          children: [for (var i = 0; i < 50; i++) MindmapNode(text: '分支 $i')],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('思维导图超出页面，请减少分支'),
        ),
      ),
    );
    expect(sceneChanges, changesBeforeFailure);
    expect(controller.layout.pages, hasLength(1));

    controller.undo();
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => !element.isCanvasPage,
      ),
      isEmpty,
    );
    controller.redo();
    expect(
      controller.editorState.scene.activeElements.whereType<TextElement>(),
      hasLength(1),
    );
  });

  test('无限画布超视口导图在有限步骤内落到相邻区域并聚焦根节点', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('below'),
          x: 0,
          y: 620,
          width: 800,
          height: 300,
        ),
      ),
    );

    controller.insertMindmap(
      MindmapNode(
        text: '超视口主题',
        children: [for (var i = 0; i < 20; i++) MindmapNode(text: '分支 $i')],
      ),
    );

    final root = controller.editorState.scene.getElementById(
      controller.editorState.selectedIds.single,
    )!;
    final visible = controller.editorState.viewport.visibleRect(
      const Size(800, 600),
    );
    expect(visible.contains(Offset(root.x, root.y)), isTrue);
    expect(
      visible.contains(Offset(root.x + root.width, root.y + root.height)),
      isTrue,
    );
    final inserted = controller.editorState.scene.activeElements.where(
      (element) => element.id.value != 'below',
    );
    expect(
      _visualUnion(inserted).intersects(Bounds.fromLTWH(0, 620, 800, 300)),
      isFalse,
    );
  });

  test('无限画布忽略远处元素并使用当前视口的下一相邻区域', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('current-full'),
          x: 0,
          y: 0,
          width: 800,
          height: 600,
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('far-away'),
          x: 0,
          y: 1000000,
          width: 800,
          height: 100,
        ),
      ),
    );

    controller.insertMindmap(
      MindmapNode(
        text: '相邻主题',
        children: [MindmapNode(text: '分支')],
      ),
    );

    final root = controller.editorState.scene.getElementById(
      controller.editorState.selectedIds.single,
    )!;
    expect(root.y, greaterThan(600));
    expect(root.y, lessThan(2000));
  });

  test('分页导图连续 reflow 后仍完整位于内容区并避让普通元素', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: const [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 1000, 900),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(1000, 900);
    controller.insertMindmap(
      MindmapNode(
        text: '可扩展主题',
        children: [MindmapNode(text: '初始分支')],
      ),
    );
    final blocker = RectangleElement(
      id: ElementId('reflow-blocker'),
      x: 700,
      y: 72,
      width: 228,
      height: 756,
      customData: const {
        'flowMuse': {'pageId': 'page-1'},
      },
    );
    controller.applyResult(AddElementResult(blocker));

    controller.mindmapAddChild();
    for (var i = 0; i < 3; i++) {
      controller.mindmapAddSibling();
    }

    final mindmap = controller.editorState.scene.activeElements
        .where(
          (element) =>
              element.id.value != blocker.id.value && !element.isCanvasPage,
        )
        .toList();
    final bounds = _visualUnion(mindmap);
    final content = const Rect.fromLTWH(0, 0, 1000, 900).deflate(72);
    expect(content.contains(Offset(bounds.left, bounds.top)), isTrue);
    expect(content.contains(Offset(bounds.right, bounds.bottom)), isTrue);
    expect(bounds.intersects(AlignmentUtils.visualBounds(blocker)), isFalse);
    _expectMindmapIntegrity(mindmap, 'page-1');
  });

  test('分页导图 reflow 无空间时不抛异常并通过统一回调提示', () {
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
    controller.lastCanvasSize = const Size(800, 500);
    controller.insertMindmap(
      MindmapNode(
        text: '主题',
        children: [MindmapNode(text: '分支')],
      ),
    );
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('no-space'),
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
    String? message;
    controller.onMindmapOperationError = (value) => message = value;
    final idsBefore = {
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    };

    expect(controller.mindmapAddChild, returnsNormally);
    expect(message, contains('当前页面没有足够空间'));
    expect({
      for (final element in controller.editorState.scene.activeElements)
        element.id,
    }, idsBefore);

    controller.undo();
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => !element.isCanvasPage,
      ),
      isEmpty,
    );
  });
}

Bounds _visualUnion(Iterable<Element> elements) => elements
    .map(AlignmentUtils.visualBounds)
    .reduce((left, right) => left.union(right));

void _expectMindmapIntegrity(List<Element> elements, String pageId) {
  final byId = {for (final element in elements) element.id.value: element};
  expect(elements, isNotEmpty);
  for (final element in elements) {
    expect(element.pageId, pageId);
    if (element is TextElement) {
      expect(element.containerId, isNotNull);
      final rectangle = byId[element.containerId];
      expect(rectangle, isA<RectangleElement>());
      expect(rectangle!.pageId, pageId);
      expect(
        rectangle.boundElements.any(
          (binding) => binding.id == element.id.value && binding.type == 'text',
        ),
        isTrue,
      );
    } else if (element is ArrowElement) {
      expect(element.startBinding, isNotNull);
      expect(element.endBinding, isNotNull);
      expect(
        element.startBinding!.elementId,
        isNot(element.endBinding!.elementId),
      );
      final start = byId[element.startBinding!.elementId];
      final end = byId[element.endBinding!.elementId];
      expect(start, isA<RectangleElement>());
      expect(end, isA<RectangleElement>());
      expect(MindmapUtils.isMindmapNode(start!), isTrue);
      expect(MindmapUtils.isMindmapNode(end!), isTrue);
    }
  }
  for (final rectangle in elements.whereType<RectangleElement>()) {
    final textBindings = rectangle.boundElements.where(
      (binding) => binding.type == 'text',
    );
    expect(textBindings, hasLength(1));
    final text = byId[textBindings.single.id];
    expect(text, isA<TextElement>());
    expect((text! as TextElement).containerId, rectangle.id.value);
  }
}
