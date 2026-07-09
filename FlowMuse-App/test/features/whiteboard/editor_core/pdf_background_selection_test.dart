import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clicking a PDF background image does not select it', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        ImageElement(
          id: ElementId('pdf-page-1'),
          x: 0,
          y: 0,
          width: 400,
          height: 600,
          fileId: 'page-1',
          mimeType: 'image/png',
          locked: true,
          customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
        ),
      ),
    );

    controller.onPointerDown(const Offset(200, 300));
    controller.onPointerUp(const Offset(200, 300));

    expect(controller.editorState.selectedIds, isEmpty);
  });

  test('marquee selection skips PDF background images', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene()
          .addElement(
            ImageElement(
              id: ElementId('pdf-page-1'),
              x: 0,
              y: 0,
              width: 400,
              height: 600,
              fileId: 'page-1',
              mimeType: 'image/png',
              locked: true,
              customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
            ),
          )
          .addElement(
            RectangleElement(
              id: ElementId('annotation'),
              x: 100,
              y: 100,
              width: 80,
              height: 60,
            ),
          ),
    );

    controller.onPointerDown(const Offset(-10, -10));
    controller.onPointerMove(const Offset(500, 700), const Offset(510, 710));
    controller.onPointerUp(const Offset(500, 700));

    expect(controller.editorState.selectedIds, {ElementId('annotation')});
  });

  test('select all skips PDF background images', () {
    final tool = SelectTool();
    final scene = Scene()
        .addElement(
          ImageElement(
            id: ElementId('pdf-page-1'),
            x: 0,
            y: 0,
            width: 400,
            height: 600,
            fileId: 'page-1',
            mimeType: 'image/png',
            locked: true,
            customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
          ),
        )
        .addElement(
          RectangleElement(
            id: ElementId('annotation'),
            x: 100,
            y: 100,
            width: 80,
            height: 60,
          ),
        );

    final result = tool.onKeyEvent(
      'a',
      ctrl: true,
      context: ToolContext(
        scene: scene,
        viewport: const ViewportState(),
        selectedIds: const {},
        clipboard: const [],
        interactionMode: InteractionMode.pointer,
        isEditingLinear: false,
      ),
    );

    expect(result, isA<SetSelectionResult>());
    expect((result! as SetSelectionResult).selectedIds, {
      ElementId('annotation'),
    });
  });

  test('PDF background marker survives scene serialization', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(
      Scene().addElement(
        ImageElement(
          id: ElementId('pdf-page-1'),
          x: 0,
          y: 0,
          width: 400,
          height: 600,
          fileId: 'page-1',
          mimeType: 'image/png',
          locked: true,
          customData: CanvasLayout.pdfBackgroundCustomData('page-1'),
        ),
      ),
    );

    final serialized = controller.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    final reloaded = MarkdrawController();
    addTearDown(reloaded.dispose);
    reloaded.loadFromContent(serialized, 'note.excalidraw');

    final image = reloaded.currentScene.activeElements.single as ImageElement;
    expect(image.isPdfBackground, isTrue);
    expect(
      reloaded.currentScene.getElementAtPoint(const Point(200, 300)),
      isNull,
    );
  });
}
