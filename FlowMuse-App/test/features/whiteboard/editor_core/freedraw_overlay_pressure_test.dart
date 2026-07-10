import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

// 用 controller 驱动（ToolContext 需要 scene/viewport，直接造 tool 太重；参考既有测试模式）。
// 注意：此测试在阶段 2 编写时，controller 签名仍是旧的 Offset+kind+pressure 形式；
// 阶段 3 改造为方案 A（收 PointerEvent）后，需把 onPointerDown/Move 调用改为构造
// PointerDownEvent/PointerMoveEvent（见 stroke_modeler_integration_test.dart 的构造方式）。
// 阶段 2 提交时用下方"旧签名"形式；阶段 3 Step 6 全量回归时同步迁移。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview overlay carries pressures and isComplete=false during a stroke', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);

    controller.onPointerDown(PointerDownEvent(
      pointer: 1,
      position: const Offset(0, 0),
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      timeStamp: Duration.zero,
    ));
    controller.onPointerMove(PointerMoveEvent(
      pointer: 1,
      position: const Offset(10, 0),
      delta: const Offset(10, 0),
      kind: PointerDeviceKind.stylus,
      pressure: 0.6,
      timeStamp: const Duration(milliseconds: 16),
    ));

    // 进行中：controller 暴露的预览 overlay 应带 pressure 且 isComplete=false。
    final overlay = controller.activeTool.overlay;
    expect(overlay, isNotNull);
    expect(overlay!.creationPressures, isNotNull);
    expect(overlay.creationPressures!.length, greaterThanOrEqualTo(2));
    expect(overlay.creationIsComplete, isFalse);
  });
}
