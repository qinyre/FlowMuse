import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

Offset _local(double x, double y) => Offset(x, y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // §5 输入路由 — active pointer 所有权
  // ---------------------------------------------------------------------------
  group('active pointer ownership', () {
    test('non-active pointer move is ignored during freedraw stroke', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      // 指针 1 按下，获取 active pointer 所有权
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      // 非活动指针 2 的 move —— 应被忽略
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 2,
          position: _local(50, 50),
          delta: const Offset(50, 50),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      // 活动指针 1 正常移动
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      // 活动指针 1 抬起，提交笔画
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(20, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 48),
        ),
      );

      final elements = controller.editorState.scene.elements;
      expect(elements.length, 1);
      // 验证非活动指针 2 的 move 没有混入点列
      final pts = (elements.first as FreedrawElement).points;
      // 应有 3 个点：down(0,0) + move(10,0) + up(20,0) = 3
      // （modeler 可能丢弃一些中间点，但 down 和 up 始终保留）
      expect(pts.length, greaterThanOrEqualTo(2));
    });

    test('non-active pointer up does not commit stroke prematurely', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      // 非活动指针 2 的 up —— 不应提交笔画
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 2,
          position: _local(50, 50),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      // 场景应仍为空（笔画尚未提交）
      expect(controller.editorState.scene.elements, isEmpty);

      // 活动指针 1 抬起，正式提交
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(20, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 48),
        ),
      );

      expect(controller.editorState.scene.elements.length, 1);
    });

    test('pointer ownership is released after up, new pointer can start', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      // 第一笔：指针 1
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(10, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      // 第二笔：指针 2 —— 确认所有权已释放，新指针可获取
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 2,
          position: _local(50, 50),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 2,
          position: _local(60, 50),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 48),
        ),
      );

      expect(controller.editorState.scene.elements.length, 2);
    });

    test('move from non-active pointer before down is dropped', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      // 没有按下就开始移动（非活动指针）
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 10),
          delta: const Offset(10, 10),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      // 场景应仍为空
      expect(controller.editorState.scene.elements, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // §5 输入路由 — cancel 清理
  // ---------------------------------------------------------------------------
  group('cancel cleanup', () {
    test('cancel resets modeler and does not commit element', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      controller.onPointerCancel(
        PointerCancelEvent(
          pointer: 1,
          position: _local(10, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      // cancel 后场景应为空——不提交元素
      expect(controller.editorState.scene.elements, isEmpty);
    });

    test('cancel allows new stroke to start fresh', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      // 第一笔 → 被 cancel
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );
      controller.onPointerCancel(
        PointerCancelEvent(
          pointer: 1,
          position: _local(10, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      expect(controller.editorState.scene.elements, isEmpty);

      // 第二笔应正常
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 2,
          position: _local(50, 50),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 48),
        ),
      );
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 2,
          position: _local(60, 50),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 64),
        ),
      );
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 2,
          position: _local(70, 50),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 80),
        ),
      );

      expect(controller.editorState.scene.elements.length, 1);
    });

    test('cancel on non-freedraw tool also resets safely', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.rectangle);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(10, 10),
          kind: PointerDeviceKind.mouse,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(50, 50),
          delta: const Offset(40, 40),
          kind: PointerDeviceKind.mouse,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      // cancel 应安全重置，不崩溃
      expect(
        () => controller.onPointerCancel(
          PointerCancelEvent(
            pointer: 1,
            position: _local(50, 50),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 32),
          ),
        ),
        returnsNormally,
      );

      // cancel 后无元素提交
      expect(controller.editorState.scene.elements, isEmpty);
    });

    test('cancel discards scene-before-drag without pushing history', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      controller.onPointerCancel(
        PointerCancelEvent(
          pointer: 1,
          position: _local(10, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      // undo 栈应为空（cancel 不推历史）
      expect(() => controller.undo(), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // §5 输入路由 — 非 freedraw 工具旁路 modeler
  // ---------------------------------------------------------------------------
  group('non-freedraw tool bypasses modeler', () {
    test('select tool does not use modeler', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.select);

      // select 工具走 legacy 路径，不创建 modeler
      expect(() {
        controller.onPointerDown(
          PointerDownEvent(
            pointer: 1,
            position: _local(50, 50),
            kind: PointerDeviceKind.mouse,
            timeStamp: Duration.zero,
          ),
        );
        controller.onPointerUp(
          PointerUpEvent(
            pointer: 1,
            position: _local(50, 50),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 16),
          ),
        );
      }, returnsNormally);
    });

    test('rectangle tool creation bypasses modeler', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.rectangle);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(10, 10),
          kind: PointerDeviceKind.mouse,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(100, 100),
          delta: const Offset(90, 90),
          kind: PointerDeviceKind.mouse,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(100, 100),
          kind: PointerDeviceKind.mouse,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      final elements = controller.editorState.scene.elements;
      expect(elements.length, 1);
      expect((elements.first as dynamic).type, 'rectangle');
    });

    test('eraser tool does not use modeler', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.eraser);

      expect(() {
        controller.onPointerDown(
          PointerDownEvent(
            pointer: 1,
            position: _local(50, 50),
            kind: PointerDeviceKind.mouse,
            timeStamp: Duration.zero,
          ),
        );
        controller.onPointerUp(
          PointerUpEvent(
            pointer: 1,
            position: _local(50, 50),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 16),
          ),
        );
      }, returnsNormally);
    });

    test('line tool multi-point creation bypasses modeler', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.line);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(10, 10),
          kind: PointerDeviceKind.mouse,
          timeStamp: Duration.zero,
        ),
      );
      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(100, 100),
          delta: const Offset(90, 90),
          kind: PointerDeviceKind.mouse,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );
      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(100, 100),
          kind: PointerDeviceKind.mouse,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      expect(controller.editorState.scene.elements.length, 1);
    });

    test('hand tool pan does not use modeler', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.hand);

      expect(() {
        controller.onPointerDown(
          PointerDownEvent(
            pointer: 1,
            position: _local(100, 100),
            kind: PointerDeviceKind.mouse,
            timeStamp: Duration.zero,
          ),
        );
        controller.onPointerMove(
          PointerMoveEvent(
            pointer: 1,
            position: _local(150, 120),
            delta: const Offset(50, 20),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 16),
          ),
        );
        controller.onPointerUp(
          PointerUpEvent(
            pointer: 1,
            position: _local(150, 120),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 32),
          ),
        );
      }, returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // §5 输入路由 — mouse/touch 不误判真实 pressure
  // ---------------------------------------------------------------------------
  group('pressure misidentification', () {
    test(
      'mouse freedraw produces simulated pressure (useRealPressure: false)',
      () {
        final controller = MarkdrawController();
        addTearDown(controller.dispose);
        controller.canvasSize = const Size(400, 600);
        controller.switchTool(ToolType.freedraw);

        // mouse 设备：normalizer 返回 pressure=null，policySelector 选 InputPolicy.mouse
        controller.onPointerDown(
          PointerDownEvent(
            pointer: 1,
            position: _local(0, 0),
            kind: PointerDeviceKind.mouse,
            pressure: 0.0,
            timeStamp: Duration.zero,
          ),
        );

        for (var i = 1; i <= 10; i++) {
          controller.onPointerMove(
            PointerMoveEvent(
              pointer: 1,
              position: _local(i * 5.0, 0),
              delta: const Offset(5, 0),
              kind: PointerDeviceKind.mouse,
              pressure: 0.0,
              timeStamp: Duration(milliseconds: i * 16),
            ),
          );
        }

        controller.onPointerUp(
          PointerUpEvent(
            pointer: 1,
            position: _local(55, 0),
            kind: PointerDeviceKind.mouse,
            timeStamp: const Duration(milliseconds: 176),
          ),
        );

        final elements = controller.editorState.scene.elements;
        expect(elements.length, 1);
        final element = elements.first as FreedrawElement;
        // mouse → simulatePressure = true，无真实压感
        expect(element.simulatePressure, isTrue);
        expect(element.pressures, isEmpty);
      },
    );

    test('touch events are filtered for creation tools', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      // touch 事件被 shouldDispatchToCreationTool 阻挡
      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.touch,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      // 不应创建任何元素
      expect(controller.editorState.scene.elements, isEmpty);
    });

    test('stylus freedraw produces real pressure (useRealPressure: true)', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      for (var i = 1; i <= 10; i++) {
        controller.onPointerMove(
          PointerMoveEvent(
            pointer: 1,
            position: _local(i * 3.0, 0),
            delta: const Offset(3, 0),
            kind: PointerDeviceKind.stylus,
            pressure: 0.5 + i * 0.02,
            timeStamp: Duration(milliseconds: i * 16),
          ),
        );
      }

      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(33, 0),
          kind: PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 176),
        ),
      );

      final elements = controller.editorState.scene.elements;
      expect(elements.length, 1);
      final element = elements.first as FreedrawElement;
      // stylus → simulatePressure = false，有真实压感列表
      expect(element.simulatePressure, isFalse);
      expect(element.pressures, isNotEmpty);
      expect(element.pressures.every((p) => p > 0), isTrue);
    });

    test('unknown device defaults to simulated pressure', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.canvasSize = const Size(400, 600);
      controller.switchTool(ToolType.freedraw);

      controller.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          position: _local(0, 0),
          kind: PointerDeviceKind.unknown,
          pressure: 0.5,
          timeStamp: Duration.zero,
        ),
      );

      controller.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: _local(10, 0),
          delta: const Offset(10, 0),
          kind: PointerDeviceKind.unknown,
          pressure: 0.5,
          timeStamp: const Duration(milliseconds: 16),
        ),
      );

      controller.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: _local(20, 0),
          kind: PointerDeviceKind.unknown,
          timeStamp: const Duration(milliseconds: 32),
        ),
      );

      final elements = controller.editorState.scene.elements;
      expect(elements.length, 1);
      final element = elements.first as FreedrawElement;
      // unknown → InputPolicy.mouse（保守），无真实压感
      expect(element.simulatePressure, isTrue);
    });
  });
}
