import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('整理稿在 PDF 后续页并一次撤销，原稿和页标记完整保留', () {
    final controller = MarkdrawController()..canvasSize = const Size(900, 760);
    addTearDown(controller.dispose);
    const originalId = 'original-pdf';
    final background = ImageElement(
      id: const ElementId('pdf'),
      x: 0,
      y: 0,
      width: 740,
      height: 900,
      fileId: 'fixture',
      mimeType: 'image/png',
      customData: CanvasLayout.pdfBackgroundCustomData(originalId),
    );
    controller.loadScene(Scene().addElement(background));
    final originalBounds = controller.layout.pages.single.bounds;
    var edits = 0;
    controller.onSceneChanged = (_, _) => edits++;

    controller.insertNoteDraft(
      parseNoteDraft(
        [
          '# 讲义整理',
          '## 核心概念',
          '- 定义及使用条件',
        ...List.filled(70, '推导步骤'),
        ].join('\n'),
      ),
    );

    final pages = controller.layout.pages;
    expect(pages.length, greaterThan(2));
    expect(pages.first.bounds, originalBounds);
    expect(edits, 1);
    final texts = controller.currentScene.activeElements
        .whereType<TextElement>();
    final title = texts.singleWhere((item) => item.text == '讲义整理');
    final section = texts.singleWhere((item) => item.text == '核心概念');
    final bullet = texts.singleWhere((item) => item.text.startsWith('•'));
    expect(title.fontSize, greaterThan(section.fontSize));
    expect(section.fontSize, greaterThan(bullet.fontSize));
    expect(bullet.x, greaterThan(section.x));
    for (final text in texts) {
      final page = pages.singleWhere((page) => page.id == text.pageId);
      expect(text.y + text.height, lessThanOrEqualTo(page.bounds.bottom));
    }
    expect(
      CanvasLayout.fromScene(
        controller.currentScene.elements,
      ).pages.map((page) => page.id),
      pages.map((page) => page.id),
    );

    controller.undo();
    expect(controller.layout.pages.single.id, originalId);
    expect(controller.currentScene.activeElements.whereType<ImageElement>().single.id, background.id);
    expect(controller.currentScene.activeElements.whereType<TextElement>(), isEmpty);
  });

  test('无限画布的整理稿在原内容旁生成独立纸面', () {
    final controller = MarkdrawController()..canvasSize = const Size(800, 600);
    addTearDown(controller.dispose);
    final original = RectangleElement(
      id: const ElementId('original'),
      x: 0,
      y: 0,
      width: 180,
      height: 100,
    );
    controller.loadScene(Scene().addElement(original));
    controller.insertNoteDraft(parseNoteDraft('# 记录\n## 结论\n已完成复核'));
    final paper = controller.currentScene.activeElements
        .whereType<RectangleElement>()
        .singleWhere((element) => element.backgroundColor == '#FAFBF7');
    expect(paper.x, greaterThan(original.x + original.width));
    expect(paper.locked, isTrue);
    expect(controller.layout.isPaged, isFalse);
    controller.undo();
    expect(controller.currentScene.activeElements.single, same(original));
  });
}
