import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// 湿墨预览 WYSIWYG 回归（计划书 §3.2 A 组：
/// docs/研发记录/plans/2026-08-29-wet-ink-brush-fidelity.md）。
///
/// 修复前：buildPreviewElement 的 freedraw 预览缺 customData，渲染端
/// 双重回退（brush_type.dart 缺省钢笔 profile + legacy thinning 解释已
/// 编码压力）——非钢笔笔形书写中一律呈钢笔态，松手后才"变身"。本组
/// 验证预览元素携带与提交端（freedraw_tool._buildElement）同源的笔型
/// 标记，且冻结/广播/形状工具路径不受波及。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const previewIdValue = '__preview__';

  // 模型器为异步批处理（对齐既有节流用例 100ms 口径，取 150ms 留裕量）。
  Future<void> pumpModeler() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  MarkdrawController controllerFor(
    BrushType brush, {
    double sensitivity = 0.7,
  }) {
    final controller = MarkdrawController();
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = brush;
    controller.pressureSensitivity = sensitivity;
    return controller;
  }

  PointerDownEvent downEvent(
    int pointer, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    double pressure = 0.8,
  }) => PointerDownEvent(
    pointer: pointer,
    kind: kind,
    position: Offset.zero,
    pressure: pressure,
    timeStamp: Duration.zero,
  );

  PointerMoveEvent moveEvent(
    int pointer,
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int ms = 20,
    double pressure = 0.8,
  }) => PointerMoveEvent(
    pointer: pointer,
    kind: kind,
    position: at,
    pressure: pressure,
    timeStamp: Duration(milliseconds: ms),
  );

  PointerUpEvent upEvent(
    int pointer,
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) => PointerUpEvent(
    pointer: pointer,
    kind: kind,
    position: at,
    pressure: 0.8,
    timeStamp: const Duration(milliseconds: 40),
  );

  /// 落笔并移动一点，返回书写中的预览元素（不抬笔）。
  Future<FreedrawElement> previewMidStroke(
    MarkdrawController controller, {
    int pointer = 1,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    controller.onPointerDown(downEvent(pointer, kind: kind));
    controller.onPointerMove(moveEvent(pointer, const Offset(30, 0), kind: kind));
    await pumpModeler();
    final overlay = (controller.activeTool as FreedrawTool).overlay!;
    return controller.buildPreviewElement(overlay)! as FreedrawElement;
  }

  test('A1: 书写中预览逐笔形携带冻结笔型与 pressureEncoding=1', () async {
    for (final brush in BrushType.values) {
      final controller = controllerFor(brush);
      addTearDown(controller.dispose);
      final preview = await previewMidStroke(controller);
      expect(preview.id.value, previewIdValue, reason: '$brush');
      expect(
        brushTypeFromCustomData(preview.customData),
        brush,
        reason: '$brush 预览笔型必须与落笔笔形一致',
      );
      expect(
        pressureEncodingFromCustomData(preview.customData),
        isTrue,
        reason: '$brush 预览压力须按创建时编码语义渲染',
      );
    }
  });

  test('A2: 中途切笔预览仍为落笔冻结笔形，抬笔后恢复新笔形', () async {
    final controller = controllerFor(BrushType.pencil);
    addTearDown(controller.dispose);
    final preview = await previewMidStroke(controller);
    expect(brushTypeFromCustomData(preview.customData), BrushType.pencil);

    controller.activeBrushType = BrushType.highlighter;
    final overlay = (controller.activeTool as FreedrawTool).overlay!;
    final afterSwitch =
        controller.buildPreviewElement(overlay)! as FreedrawElement;
    expect(
      brushTypeFromCustomData(afterSwitch.customData),
      BrushType.pencil,
      reason: '书写中切笔不得改变本笔预览（与提交端同一冻结快照）',
    );

    controller.onPointerUp(upEvent(1, const Offset(60, 0)));
    await pumpModeler();

    final nextPreview = await previewMidStroke(controller, pointer: 2);
    expect(
      brushTypeFromCustomData(nextPreview.customData),
      BrushType.highlighter,
      reason: '笔画终止后预览恢复正常实时笔型',
    );
  });

  test('A3: 无压感路径（鼠标+圆珠笔/荧光笔）：pressures 空、simulatePressure=true', () async {
    for (final brush in [BrushType.ballpoint, BrushType.highlighter]) {
      final controller = controllerFor(brush);
      addTearDown(controller.dispose);
      // 鼠标事件经 reliableStylusPressure 恒返回 null → 编码点返回 null。
      final preview = await previewMidStroke(
        controller,
        pointer: 3,
        kind: PointerDeviceKind.mouse,
      );
      expect(preview.pressures, isEmpty, reason: '$brush 无压感预览 pressures 应为空');
      expect(preview.simulatePressure, isTrue, reason: '$brush 无压感预览走速度模拟');
      expect(brushTypeFromCustomData(preview.customData), brush, reason: '$brush');
    }
  });

  test('A4: 单点 overlay 不产出预览（≥2 点门槛）', () {
    final controller = controllerFor(BrushType.fountainPen);
    addTearDown(controller.dispose);
    final preview = controller.buildPreviewElement(
      const ToolOverlay(
        creationPoints: [Point(1, 1)],
        creationPressures: [0.5],
      ),
    );
    expect(preview, isNull, reason: '单点不崩溃也不产出预览');
  });

  test('A5: 预览 id 恒定、连续构建互不污染、抬笔不入场景', () async {
    final controller = controllerFor(BrushType.fountainPen);
    addTearDown(controller.dispose);
    final p1Live = await previewMidStroke(controller, pointer: 4);
    expect(p1Live.id.value, previewIdValue);
    // 预览持工具 _points 活视图（抬笔即清空），先拍快照再继续输入。
    final p1 = p1Live.copyWithFreedraw(
      points: List.of(p1Live.points),
      pressures: List.of(p1Live.pressures),
    );

    controller.onPointerMove(moveEvent(4, const Offset(60, 0), ms: 40));
    await pumpModeler();
    final overlay = (controller.activeTool as FreedrawTool).overlay!;
    final p2 = controller.buildPreviewElement(overlay)! as FreedrawElement;
    expect(p2.id.value, previewIdValue);
    expect(
      p2.points.length,
      greaterThan(p1.points.length),
      reason: '第二次构建必须反映最新点位（连续构建互不污染）',
    );

    controller.onPointerUp(upEvent(4, const Offset(60, 0)));
    await pumpModeler();
    expect(
      controller.currentScene.elements.any((e) => e.id.value == previewIdValue),
      isFalse,
      reason: '预览元素从不入场景',
    );
    expect(
      controller.currentScene.elements.whereType<FreedrawElement>(),
      isNotEmpty,
      reason: '提交元素正常入库',
    );
  });

  test('A6: 协作实况广播元素仍自带笔型 customData（R4 波及锁）', () async {
    final controller = controllerFor(BrushType.brushPen);
    addTearDown(controller.dispose);
    final emitted = <FreedrawElement>[];
    controller.onLiveFreedrawChanged = emitted.add;

    controller.onPointerDown(downEvent(5));
    controller.onPointerMove(moveEvent(5, const Offset(12, 0)));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(emitted, isNotEmpty, reason: 'legacy 实况通道照常广播');
    expect(
      brushTypeFromCustomData(emitted.last.customData),
      BrushType.brushPen,
      reason: '广播走 buildLiveElement，须保持自带笔型标记',
    );
    expect(pressureEncodingFromCustomData(emitted.last.customData), isTrue);
  });

  test('A7: 形状工具预览零回归，eraser/laser 无预览（R3 波及锁）', () async {
    final shapeCases = <ToolType, Type>{
      ToolType.rectangle: RectangleElement,
      ToolType.ellipse: EllipseElement,
      ToolType.diamond: DiamondElement,
      ToolType.line: LineElement,
      ToolType.arrow: ArrowElement,
    };
    for (final entry in shapeCases.entries) {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.switchTool(entry.key);
      controller.onPointerDown(downEvent(6, kind: PointerDeviceKind.mouse));
      controller.onPointerMove(
        moveEvent(6, const Offset(80, 60), kind: PointerDeviceKind.mouse),
      );
      await pumpModeler();
      final overlay = controller.activeTool.overlay;
      final preview = overlay == null
          ? null
          : controller.buildPreviewElement(overlay);
      expect(preview, isNotNull, reason: '${entry.key} 应有创建预览');
      expect(preview!.runtimeType, entry.value, reason: '${entry.key} 预览类不变');
      expect(
        preview.customData,
        isNull,
        reason: '${entry.key} 形状预览不带笔型标记',
      );
    }
    for (final toolType in [ToolType.eraser, ToolType.laser]) {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.switchTool(toolType);
      expect(controller.activeTool.overlay, isNull, reason: '$toolType 无创建预览');
    }
  });

  test('A8: 预览 customData 只含笔型标记，不携带 recognition keys', () async {
    final controller = controllerFor(BrushType.pencil);
    addTearDown(controller.dispose);
    final preview = await previewMidStroke(controller);
    final flowMuse = preview.customData?[flowMuseCustomDataKey];
    expect(flowMuse, isA<Map>());
    expect(
      (flowMuse! as Map).keys.toSet(),
      {'brushType', 'pressureEncoding'},
      reason: 'recognition keys 只写提交元素（预览从不入场景）',
    );
  });

  group('起笔攻击补偿按笔形生效（钢笔不补偿）', () {
    // 真机回归：攻击包络曾全局开启，轻力度写钢笔时 0.4-0.6s 短笔画全程
    // 被 0.50 攻击水位压平，粗细变化消失（钢笔的粗细动态全靠压力）。补偿
    // 改为控制器按笔形白名单传入模型器：仅毛笔/铅笔（低压起笔渲染为细线、
    // 压力到位突然增宽的闪变笔形）开启，钢笔忠实透传实测压力。
    //
    // 断言依据：encodePressure 是 raw 的单调增仿射映射（0.5 + k*(raw-0.5)），
    // 模型器域的抬压/不抬压在编码域保序。恒定轻压 0.35 经映射
    // （floor 0.18 + 0.35×0.64）≈ 0.404：
    // - 不抬压（钢笔）：模型器输出 < 0.50 → 编码后严格 < 0.5；
    // - 抬压（毛笔/铅笔）：down 时刻包络恰为水位 0.50 → 编码后恰为 0.5。
    Future<List<double>> strokePressures(
      BrushType brush, {
      double pressure = 0.35,
    }) async {
      final controller = controllerFor(brush);
      addTearDown(controller.dispose);
      controller.onPointerDown(downEvent(1, pressure: pressure));
      controller.onPointerMove(
        moveEvent(1, const Offset(30, 0), pressure: pressure),
      );
      await pumpModeler();
      final overlay = (controller.activeTool as FreedrawTool).overlay!;
      final preview =
          controller.buildPreviewElement(overlay)! as FreedrawElement;
      // 预览持有工具点列的活视图，抬笔即清空——读取前快照。
      return List.of(preview.pressures);
    }

    test('钢笔：轻力度全程不被抬到攻击水位（粗细变化保留）', () async {
      final pressures = await strokePressures(BrushType.fountainPen);
      expect(pressures, isNotEmpty);
      for (final p in pressures) {
        expect(
          p,
          lessThan(0.5),
          reason: '钢笔不得套攻击包络（轻力度粗细变化会被压平）: $pressures',
        );
      }
    });

    test('毛笔/铅笔：起笔输出抬到攻击水位（闪变治理保持）', () async {
      for (final brush in [BrushType.brushPen, BrushType.pencil]) {
        final pressures = await strokePressures(brush);
        expect(pressures, isNotEmpty, reason: '$brush');
        expect(
          pressures.first,
          closeTo(0.5, 0.001),
          reason: '$brush 起笔应被包络抬到攻击水位（编码域 0.5）: $pressures',
        );
      }
    });
  });
}
