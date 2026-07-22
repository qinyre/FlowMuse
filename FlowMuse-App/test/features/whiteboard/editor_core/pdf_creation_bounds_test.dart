import 'dart:ui';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pagedLayout = CanvasLayout(
    type: CanvasLayoutType.paged,
    pages: [
      CanvasPage(
        id: 'page-1',
        index: 0,
        bounds: const Rect.fromLTWH(0, 0, 400, 800),
        template: CanvasPageTemplate.blank,
        source: 'blank',
      ),
    ],
  );

  test('paged layout only allows creation inside a page', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(initialLayout: pagedLayout),
    );
    addTearDown(controller.dispose);

    expect(controller.canCreateAt(const Point(10, 10)), isTrue);
    expect(controller.canCreateAt(const Point(401, 10)), isFalse);
    expect(controller.canCreateAt(const Point(10, 801)), isFalse);
  });

  test('unbounded layout keeps creation unrestricted', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);

    expect(controller.canCreateAt(const Point(10000, 10000)), isTrue);
  });

  test('pointer creation outside a paged page is ignored', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(initialLayout: pagedLayout),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.rectangle);

    controller.onPointerDown(
      const PointerDownEvent(
        position: Offset(1000, 1000),
        kind: PointerDeviceKind.mouse,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        position: Offset(1050, 1050),
        delta: Offset(50, 50),
        kind: PointerDeviceKind.mouse,
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        position: Offset(1050, 1050),
        kind: PointerDeviceKind.mouse,
      ),
    );

    expect(
      controller.editorState.scene.activeElements.where(
        (element) => !element.isCanvasPage,
      ),
      isEmpty,
    );
  });

  test(
    'paged rendering clips a stroke that crosses the page boundary',
    () async {
      final scene = Scene().addElement(
        FreedrawElement(
        id: ElementId('crossing-stroke'),
        x: 50,
        y: 50,
        width: 430,
        height: 1,
        points: const [Point(0, 0), Point(430, 0)],
          strokeColor: '#FF0000',
          strokeWidth: 10,
        ),
      );
      final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    StaticCanvasPainter(
      scene: scene,
      adapter: RoughCanvasAdapter(),
        viewport: const ViewportState(),
        layout: pagedLayout,
        renderPageShadows: false,
    ).paint(canvas, const Size(500, 200));
    final image = await recorder.endRecording().toImage(500, 200);
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      addTearDown(image.dispose);

    expect(_alphaAt(bytes!, 75, 50, 500), 255);
    expect(_alphaAt(bytes, 450, 50, 500), 0);
    },
  );
}

int _alphaAt(ByteData bytes, int x, int y, int width) {
  return bytes.getUint8((y * width + x) * 4 + 3);
}
