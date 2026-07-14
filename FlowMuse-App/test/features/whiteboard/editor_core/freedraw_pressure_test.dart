import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ToolContext context;

  setUp(() {
    context = ToolContext(
      scene: Scene(),
      viewport: const ViewportState(),
      selectedIds: const {},
    );
  });

  test('stores aligned pressure samples for a pressure-enabled stroke', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.2);
    final live = tool.onPointerMove(const Point(5, 2), context, pressure: 0.6);
    expect(live, isNull);
    final result = tool.onPointerUp(const Point(10, 4), context, pressure: 0.8);

    final element = _createdElement(result);
    expect(element.points, hasLength(3));
    expect(element.pressures, [0.2, 0.6, 0.8]);
    expect(element.simulatePressure, isFalse);
  });

  test('keeps pressure empty when the stroke has no reliable pressure', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context);
    final live = tool.onPointerMove(const Point(5, 2), context);
    expect(live, isNull);
    final result = tool.onPointerUp(const Point(10, 4), context);

    final element = _createdElement(result);
    expect(element.points, hasLength(3));
    expect(element.pressures, isEmpty);
    expect(element.simulatePressure, isTrue);
  });

  test('keeps freedraw active after completing a stroke', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.3);
    final result = tool.onPointerUp(const Point(2, 2), context, pressure: 0.4);

    expect(result, isA<AddElementResult>());
  });

  test('绘制期间生成递增版本的实时笔画，并在抬笔时完成它', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context);
    tool.onPointerMove(const Point(4, 0), context);
    expect(tool.liveElement, isNull);
    final live = tool.buildLiveElement(context)!;
    expect(live.isComplete, isFalse);

    tool.onPointerMove(const Point(8, 0), context);
    expect(tool.liveElement, same(live));
    final update = tool.buildLiveElement(context)!;
    expect(update.id, live.id);
    expect(update.version, greaterThan(live.version));

    final completed = _createdElement(
      tool.onPointerUp(const Point(8, 0), context),
    );
    expect(completed.id, live.id);
    expect(completed.version, greaterThan(update.version));
    expect(completed.isComplete, isTrue);
  });

  test('取消绘制会生成实时笔画的删除墓碑', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context);
    tool.onPointerMove(const Point(4, 0), context);
    final live = tool.buildLiveElement(context)!;
    final cancel = tool.cancelStroke();

    expect(cancel, isNotNull);
    expect(cancel!.id, live.id);
    expect(cancel.isDeleted, isTrue);
  });

  test('does not request a raw polyline overlay while drawing', () {
    final tool = FreedrawTool();

    tool.onPointerDown(const Point(0, 0), context, pressure: 0.3);
    tool.onPointerMove(const Point(2, 2), context, pressure: 0.4);

    expect(tool.overlay!.showCreationPreviewLine, isFalse);
  });

  test(
    'controller throttles collaboration snapshots outside PointerMove',
    () async {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.switchTool(ToolType.freedraw);
      final emitted = <FreedrawElement>[];
      controller.onLiveFreedrawChanged = emitted.add;

      controller.onPointerDown(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset.zero,
          timeStamp: Duration.zero,
        ),
      );
      controller.onPointerMove(
        const PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(12, 0),
          timeStamp: Duration(milliseconds: 16),
        ),
      );

      expect(emitted, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted, hasLength(1));
      expect(emitted.single.isComplete, isFalse);
    },
  );
}

FreedrawElement _createdElement(ToolResult? result) {
  final mutation = switch (result) {
    CompoundResult(:final results) =>
      results
          .where(
            (result) =>
                result is AddElementResult || result is UpdateElementResult,
          )
          .single,
    _ => result,
  };
  return switch (mutation) {
    AddElementResult(:final element) => element as FreedrawElement,
    _ => throw StateError('Expected a freedraw element result'),
  };
}
