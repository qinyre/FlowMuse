import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('控制器应用默认工具、笔形和手势开关', () {
    final controller = MarkdrawController();
    final pencil = BrushState.defaults[BrushType.pencil]!.copyWith(
      strokeColor: '#e03131',
      strokeWidth: 6,
    );

    controller.applyEditorPreferences(
      defaultTool: ToolType.freedraw,
      defaultBrush: BrushType.pencil,
      brushStates: {BrushType.pencil: pencil},
      pressureEnabled: true,
      pressureExponent: 1,
      palmRejectionEnabled: true,
      twoFingerZoomEnabled: false,
      singleFingerPanEnabled: false,
    );

    expect(controller.editorState.activeToolType, ToolType.freedraw);
    expect(controller.activeBrushType, BrushType.pencil);
    expect(controller.defaultStyle.strokeColor, '#e03131');
    expect(controller.defaultStyle.strokeWidth, 6);
    expect(controller.canPanPagedViewportWithTouch, isFalse);

    controller.onScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(20, 20)),
    );
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: const Offset(20, 20),
        scale: 2,
        pointerCount: 2,
      ),
    );
    expect(controller.editorState.viewport.zoom, 1);

    controller.dispose();
  });
}
