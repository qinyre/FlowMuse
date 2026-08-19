import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('100 个 move 只线性通知 wet notifier，整 controller 只在 final 通知', () {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: true),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    var controllerNotifications = 0;
    var wetNotifications = 0;
    controller.addListener(() => controllerNotifications++);
    controller.localWetInkState.addListener(() => wetNotifications++);

    _down(controller);
    for (var index = 1; index <= 100; index++) {
      _move(controller, index);
    }
    _up(controller, 100);

    expect(wetNotifications, 101);
    expect(controllerNotifications, 1);
    expect(controller.localWetInkState.frame, isNull);
    expect(controller.currentScene.elements, hasLength(1));
    expect(controller.historyManager.undoCount, 1);
  });

  test('flag=false 保留逐 move 的整 controller 通知', () {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: false),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    var controllerNotifications = 0;
    var wetNotifications = 0;
    controller.addListener(() => controllerNotifications++);
    controller.localWetInkState.addListener(() => wetNotifications++);

    _down(controller);
    for (var index = 1; index <= 10; index++) {
      _move(controller, index);
    }
    _up(controller, 10);

    expect(controllerNotifications, 11);
    expect(wetNotifications, 0);
    expect(controller.currentScene.elements, hasLength(1));
  });

  test('Cancel、工具切换和 dispose 清除活动状态且不提交元素', () {
    final flags = const WritingFeatureFlags(layeredWetInk: true);
    final cancelController = MarkdrawController(writingFlags: flags);
    addTearDown(cancelController.dispose);
    cancelController.switchTool(ToolType.freedraw);
    _down(cancelController);
    _move(cancelController, 1);
    cancelController.onPointerCancel(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
    );
    expect(cancelController.localWetInkState.frame, isNull);
    expect(cancelController.currentScene.elements, isEmpty);

    final switchController = MarkdrawController(writingFlags: flags);
    addTearDown(switchController.dispose);
    switchController.switchTool(ToolType.freedraw);
    _down(switchController);
    switchController.switchTool(ToolType.select);
    expect(switchController.localWetInkState.frame, isNull);
    expect(switchController.currentScene.elements, isEmpty);

    final disposeController = MarkdrawController(writingFlags: flags);
    disposeController.switchTool(ToolType.freedraw);
    _down(disposeController);
    disposeController.dispose();
    expect(disposeController.localWetInkState.frame, isNull);
  });
}

void _down(MarkdrawController controller) {
  controller.onPointerDown(
    const PointerDownEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: Offset.zero,
      timeStamp: Duration.zero,
    ),
  );
}

void _move(MarkdrawController controller, int index) {
  controller.onPointerMove(
    PointerMoveEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: Offset(index * 2, index.toDouble()),
      delta: const Offset(2, 1),
      timeStamp: Duration(milliseconds: index * 8),
    ),
  );
}

void _up(MarkdrawController controller, int index) {
  controller.onPointerUp(
    PointerUpEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: Offset(index * 2, index.toDouble()),
      timeStamp: Duration(milliseconds: (index + 1) * 8),
    ),
  );
}
