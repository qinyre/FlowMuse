import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pdfLayout = CanvasLayout(
    type: CanvasLayoutType.paged,
    pages: [
      CanvasPage(
        id: 'page-1',
        index: 0,
        bounds: const Rect.fromLTWH(0, 0, 400, 800),
        template: CanvasPageTemplate.blank,
        source: 'pdf',
      ),
    ],
  );

  test('PDF layout only allows creation inside a page', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(initialLayout: pdfLayout),
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

  test('pointer creation outside a PDF page is ignored', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(initialLayout: pdfLayout),
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
}
