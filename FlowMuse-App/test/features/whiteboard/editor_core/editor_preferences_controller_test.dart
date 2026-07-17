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
      fingerDrawingEnabled: false,
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

  test('开启手指绘制时单指落笔、双指手势锁定缩放或平移', () {
    final controller = MarkdrawController();

    controller.applyEditorPreferences(
      defaultTool: ToolType.freedraw,
      defaultBrush: BrushType.pencil,
      brushStates: const {},
      pressureEnabled: true,
      pressureExponent: 1,
      palmRejectionEnabled: false,
      twoFingerZoomEnabled: false,
      singleFingerPanEnabled: true,
      fingerDrawingEnabled: true,
    );

    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset.zero,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset(8, 8),
        delta: Offset(8, 8),
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset(8, 8),
      ),
    );
    expect(controller.currentScene.activeElements, isNotEmpty);

    controller.onScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(20, 20)),
    );
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: const Offset(40, 20),
        scale: 2,
        pointerCount: 2,
      ),
    );
    expect(controller.editorState.viewport.zoom, 2);
    expect(controller.editorState.viewport.offset, const Offset(10, 10));

    controller.onScaleEnd(ScaleEndDetails());
    controller.onScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(20, 20)),
    );
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: const Offset(40, 20),
        scale: 1,
        pointerCount: 2,
      ),
    );
    expect(controller.editorState.viewport.zoom, 2);
    expect(controller.editorState.viewport.offset, const Offset(0, 10));

    controller.dispose();
  });
}
