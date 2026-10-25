import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final template in CanvasPageTemplate.values) {
    test('重置 ${template.name} 后建房、导入与撤销重做保留两页版式', () {
      final host = MarkdrawController()
        ..setLayout(
          CanvasLayout(
            type: CanvasLayoutType.paged,
            template: template,
            pageFlow: template == CanvasPageTemplate.ancientBook
                ? CanvasPageFlow.rightToLeft
                : CanvasPageFlow.topToBottom,
          ),
        )
        ..insertBlankPage();
      final guest = MarkdrawController();
      final reopened = MarkdrawController();
      addTearDown(host.dispose);
      addTearDown(guest.dispose);
      addTearDown(reopened.dispose);
      host.applyResult(AddElementResult(_content));
      final originalLayout = host.layout;
      final pageIds = originalLayout.pages.map((page) => page.id).toList();

      host.resetCanvas();

      expect(
        host.currentScene.activeElements.every((e) => e.isCanvasPage),
        isTrue,
      );
      expect(host.currentScene.activeElements, hasLength(2));
      WhiteboardCollaborationAdapter(
        guest,
      ).applyRemoteScene(WhiteboardCollaborationAdapter(host).currentScene());
      reopened.loadFromContent(
        host.serializeScene(format: DocumentFormat.excalidraw),
        'reset.excalidraw',
      );
      for (final controller in [host, guest, reopened]) {
        expect(controller.layout.type, CanvasLayoutType.paged);
        expect(controller.layout.template, template);
        expect(controller.layout.pageFlow, originalLayout.pageFlow);
        expect(controller.layout.pages.map((page) => page.id), pageIds);
        expect(
          controller.layout.pages.map((page) => page.bounds),
          originalLayout.pages.map((page) => page.bounds),
        );
      }
      host.undo();
      expect(host.currentScene.getElementById(_content.id), isNotNull);
      host.redo();
      expect(host.currentScene.getElementById(_content.id), isNull);
      expect(host.currentScene.activeElements, hasLength(2));
      host.resetCanvas();
      expect(host.layout.pages.map((page) => page.id), pageIds);
      expect(host.currentScene.activeElements, hasLength(2));
    });
  }

  test('重置保留页面扩展字段和版本，移除内容文件并可撤销', () {
    final controller = MarkdrawController()
      ..setLayout(const CanvasLayout(type: CanvasLayoutType.paged));
    addTearDown(controller.dispose);
    final originalPage = controller.currentScene.elements.single;
    final page = originalPage.copyWith(
      version: 7,
      versionNonce: 123,
      customData: {
        ...originalPage.customData!,
        'extension': {
          'unknown': [1, 2],
        },
      },
    );
    controller.loadScene(
      Scene()
          .addElement(page)
          .addElement(_content)
          .addFile(
            'unused-image',
            ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList([1, 2])),
          ),
    );

    controller.resetCanvas();

    final retained = controller.currentScene.activeElements.single;
    expect(retained.id, page.id);
    expect(retained.customData, page.customData);
    expect(retained.version, 7);
    expect(retained.versionNonce, 123);
    expect(controller.currentScene.files, isEmpty);
    controller.undo();
    expect(controller.currentScene.files, contains('unused-image'));
    expect(controller.currentScene.getElementById(_content.id), isNotNull);
    controller.redo();
    expect(
      controller.currentScene.activeElements.single.customData,
      page.customData,
    );
    expect(controller.currentScene.files, isEmpty);
  });

  test('无限画布重置、加入与重做仍是无限画布', () {
    final controller = MarkdrawController();
    final guest = MarkdrawController();
    addTearDown(controller.dispose);
    addTearDown(guest.dispose);
    controller.applyResult(AddElementResult(_content));
    controller.resetCanvas();
    WhiteboardCollaborationAdapter(guest).applyRemoteScene(
      WhiteboardCollaborationAdapter(controller).currentScene(),
    );
    expect(guest.layout.type, CanvasLayoutType.unbounded);
    expect(controller.currentScene.elements, isEmpty);
    controller.undo();
    expect(controller.currentScene.getElementById(_content.id), isNotNull);
    controller.redo();
    expect(controller.currentScene.elements, isEmpty);
  });
}

final _content = RectangleElement(
  id: const ElementId('reset-content'),
  x: 100,
  y: 100,
  width: 40,
  height: 30,
);
