import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('非抓手模式下单指拉过底部边界会新建页面', (tester) async {
    final controller = MarkdrawController(
      config: const MarkdrawEditorConfig(
        initialLayout: CanvasLayout(type: CanvasLayoutType.paged),
      ),
    )..switchTool(ToolType.freedraw);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: EditorCanvas(controller: controller),
        ),
      ),
    );
    await tester.pump();
    controller.scrollPagedViewportBy(100000);

    final before = controller.layout.pages.length;
    final gesture = await tester.startGesture(
      const Offset(200, 380),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveTo(const Offset(200, 0));
    await gesture.up();
    await tester.pump();

    expect(controller.editorState.activeToolType, ToolType.freedraw);
    expect(controller.layout.pages.length, before + 1);
    controller.dispose();
  });
}
