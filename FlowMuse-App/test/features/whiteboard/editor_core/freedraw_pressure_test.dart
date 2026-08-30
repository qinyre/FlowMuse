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
  group('T3：v2 响应曲线收进 BrushRenderProfile 单一真源', () {
    final pencil = BrushRenderProfile.forType(BrushType.pencil);
    final brush = BrushRenderProfile.forType(BrushType.brushPen);

    test('铅笔宽度响应温和：p .2→.8 宽度比 ≤1.35（理论 1.18，留量化余量）', () {
      final wLight = pencil.pencilNaturalMediaLocalWidth(6, 0.2);
      final wHeavy = pencil.pencilNaturalMediaLocalWidth(6, 0.8);
      // 0.26 宽度项（T4 冻结）：N3 的 1px 法向扫描量化余量。
      expect(wLight, closeTo(6 * (0.82 + 0.26 * 0.2), 1e-9));
      expect(wHeavy / wLight, lessThanOrEqualTo(1.35));
    });

    test('铅笔密度响应单调且覆盖目标量程（p=.8 比 p=.2 深 ≥35%）', () {
      var prev = -1.0;
      for (var p = 0.0; p <= 1.0 + 1e-9; p += 0.05) {
        final d = pencil.pencilNaturalMediaDensity(p);
        expect(d, greaterThan(prev), reason: '单调 p=$p');
        prev = d;
      }
      final light = pencil.pencilNaturalMediaDensity(0.2);
      final heavy = pencil.pencilNaturalMediaDensity(0.8);
      expect(heavy, greaterThan(light * 1.35), reason: 'N2 曲线量程');
    });

    test('毛笔接触宽度：p .2→.8 比 ≥2.2 且轻压可见（≥0.16 底）', () {
      final hwLight = brush.brushNaturalMediaContactHalfWidth(6, 0.2);
      final hwHeavy = brush.brushNaturalMediaContactHalfWidth(6, 0.8);
      expect(hwLight, greaterThan(0), reason: '轻压不消失');
      expect(hwHeavy / hwLight, greaterThan(2.2), reason: 'N6 提按量程');
      expect(
        brush.brushNaturalMediaContactHalfWidth(6, 0.0),
        closeTo(BrushRenderProfile.brushV2MinContactHalfWidth, 1e-9),
        reason:
            'T5 可见下限：p→0 时公式全宽 ~0.96px 在斜向 AA 下断线，'
            '冻结下限 0.7px（§3.5 最低有效宽度仍可见）',
      );
    });

    test('压力越界钳制 [0,1]，曲线对非法输入安全', () {
      expect(
        pencil.pencilNaturalMediaLocalWidth(6, 1.7),
        pencil.pencilNaturalMediaLocalWidth(6, 1.0),
      );
      expect(
        brush.brushNaturalMediaContactHalfWidth(6, -0.5),
        brush.brushNaturalMediaContactHalfWidth(6, 0.0),
      );
      expect(pencil.pencilNaturalMediaDensity(2.0), closeTo(0.18 + 0.72, 1e-9));
    });
  });

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

  test('controller 在创建时烘焙灵敏度并写入 pressureEncoding 标记（T2）', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = BrushType.brushPen;
    controller.pressureSensitivity = 0.5;

    // Given/When: 手写笔划一笔
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset.zero,
        pressure: 0.8,
        timeStamp: Duration.zero,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(30, 0),
        pressure: 0.8,
        timeStamp: Duration(milliseconds: 20),
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(60, 0),
        pressure: 0.8,
        timeStamp: Duration(milliseconds: 40),
      ),
    );

    // Then: 场景中的新元素 pressures 为编码值（不等于原始 0.8；模型器会
    // 先把压力映射进 [0.18,0.82] 再编码，断言“非原始且在 0~1”最稳），
    // customData 带 pressureEncoding=1 与 brushType。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final strokes = controller.currentScene.elements
        .whereType<FreedrawElement>()
        .toList(growable: false);
    expect(strokes, isNotEmpty);
    final stroke = strokes.last;
    expect(stroke.pressures, isNotEmpty);
    expect(
      stroke.pressures.every((p) => p != 0.8),
      isTrue,
      reason: '原始压力不应原样落盘',
    );
    expect(stroke.pressures.every((p) => p >= 0 && p <= 1), isTrue);
    expect(pressureEncodingFromCustomData(stroke.customData), isTrue);
    expect(brushTypeFromCustomData(stroke.customData), BrushType.brushPen);

    // And: 圆珠笔忽略压力 —— pressures 为空（编码点返回 null）
    final ballpointController = MarkdrawController();
    addTearDown(ballpointController.dispose);
    ballpointController.switchTool(ToolType.freedraw);
    ballpointController.activeBrushType = BrushType.ballpoint;
    ballpointController.onPointerDown(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset.zero,
        pressure: 0.9,
        timeStamp: Duration.zero,
      ),
    );
    ballpointController.onPointerUp(
      const PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(20, 0),
        pressure: 0.9,
        timeStamp: Duration(milliseconds: 30),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ballStrokes = ballpointController.currentScene.elements
        .whereType<FreedrawElement>()
        .toList(growable: false);
    expect(
      ballStrokes.last.pressures,
      isEmpty,
      reason: '圆珠笔应向工具传 null pressure',
    );
    expect(ballStrokes.last.simulatePressure, isTrue);
  });

  test('P2-2: 书写中切笔/改灵敏度不影响本笔（pointer-down 冻结）', () async {
    // 干净参照：全程毛笔 0.85 的笔画。
    final reference = MarkdrawController();
    addTearDown(reference.dispose);
    reference.switchTool(ToolType.freedraw);
    reference.activeBrushType = BrushType.brushPen;
    reference.pressureSensitivity = 0.85;
    _stroke(reference, pointer: 1);

    // 干扰组：pointer-down 后、抬笔前切到铅笔并把灵敏度改成 0.1。
    final disturbed = MarkdrawController();
    addTearDown(disturbed.dispose);
    disturbed.switchTool(ToolType.freedraw);
    disturbed.activeBrushType = BrushType.brushPen;
    disturbed.pressureSensitivity = 0.85;
    disturbed.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset.zero,
        pressure: 0.8,
        timeStamp: Duration.zero,
      ),
    );
    disturbed.activeBrushType = BrushType.pencil;
    disturbed.pressureSensitivity = 0.1;
    disturbed.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(30, 0),
        pressure: 0.8,
        timeStamp: Duration(milliseconds: 20),
      ),
    );
    disturbed.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(60, 0),
        pressure: 0.8,
        timeStamp: Duration(milliseconds: 40),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final refStroke = reference.currentScene.elements
        .whereType<FreedrawElement>()
        .single;
    final disturbedStroke = disturbed.currentScene.elements
        .whereType<FreedrawElement>()
        .single;
    expect(
      brushTypeFromCustomData(disturbedStroke.customData),
      BrushType.brushPen,
      reason: '最终元素笔型取 pointer-down 冻结值',
    );
    expect(
      disturbedStroke.pressures,
      refStroke.pressures,
      reason: '压力编码须与全程未切笔的笔画逐点一致',
    );
    expect(disturbedStroke.points, refStroke.points);

    // 抬笔后冻结解除：下一笔使用切换后的铅笔。
    _stroke(disturbed, pointer: 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final nextStroke = disturbed.currentScene.elements
        .whereType<FreedrawElement>()
        .last;
    expect(
      brushTypeFromCustomData(nextStroke.customData),
      BrushType.pencil,
      reason: '笔画终止后恢复正常实时笔型',
    );
  });
}

void _stroke(MarkdrawController controller, {required int pointer}) {
  controller.onPointerDown(
    PointerDownEvent(
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: Offset.zero,
      pressure: 0.8,
      timeStamp: Duration.zero,
    ),
  );
  controller.onPointerMove(
    PointerMoveEvent(
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: const Offset(30, 0),
      pressure: 0.8,
      timeStamp: const Duration(milliseconds: 20),
    ),
  );
  controller.onPointerUp(
    PointerUpEvent(
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: const Offset(60, 0),
      pressure: 0.8,
      timeStamp: const Duration(milliseconds: 40),
    ),
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
