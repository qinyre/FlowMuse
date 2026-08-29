import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';
import '../fixtures/brush_stroke_fixtures.dart';

/// 湿墨预览 WYSIWYG 渲染回归（计划书 §3.2 B/C 组）。
///
/// 关键口径：
/// - **必须经 `ElementRenderer.render` 渲染**——brushType/pressureEncoded
///   解析发生在 element_renderer.dart（customData 驱动），直调
///   FreedrawRenderer 传参则测不出本缺陷；
/// - 提交侧以 `copyWithFreedraw(isComplete: false)` 归一化（收针差异是
///   书写固有，见计划书 §2.2），其余字段渲染入参等价；
/// - 像素回读一律裸 test()（testWidgets 的 fake-async 内 toImage 永不
///   完成，先例 highlighter_rendering_test.dart）；铅笔用 PencilShader
///   真实加载，tearDown 恢复（先例 pencil_rendering_test.dart）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PencilShader.resetForTesting();
    await PencilShader.init();
  });
  tearDown(() {
    PencilShader.loader =
        (assetKey) => throw StateError('forced unavailable');
    PencilShader.resetForTesting();
    PencilShader.loader = ui.FragmentProgram.fromAsset;
  });

  Future<void> pumpModeler() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  MarkdrawController makeController(BrushType brush) {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = brush;
    return controller;
  }

  /// 预览元素持有工具 _points/_pressures 的活视图，抬笔即被清空
  /// （生产上预览只在书写中被渲染）。测试需在抬笔后渲染预览，先拍
  /// 不可变快照。
  FreedrawElement snapshot(FreedrawElement live) => live.copyWithFreedraw(
    points: List.of(live.points),
    pressures: List.of(live.pressures),
  );

  /// 真实生产路径的一对元素：书写中预览 + 抬笔提交元素（isComplete
  /// 归一化为 false）。customData 笔型标记同源。
  ///
  /// [committedAtPreviewInputs]：按计划书 §2.2「渲染入参等价」口径，把
  /// 提交元素的点位/压力/模拟标志对齐到预览快照（预览是书写中间态，
  /// 点位天然少于终稿；customData/样式保持提交端）——WYSIWYG 断言即
  /// 「同渲染入参下，预览管线与提交管线输出一致」。
  Future<
    ({
      FreedrawElement preview,
      FreedrawElement committed,
      FreedrawElement committedAtPreviewInputs,
    })
  >
  strokePair(BrushType brush) async {
    final controller = makeController(brush);
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
    await pumpModeler();
    final overlay = (controller.activeTool as FreedrawTool).overlay!;
    final preview = snapshot(
      controller.buildPreviewElement(overlay)! as FreedrawElement,
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
    await pumpModeler();
    final committedFull = controller.currentScene.elements
        .whereType<FreedrawElement>()
        .last;
    final committed = committedFull.copyWithFreedraw(isComplete: false);
    final committedAtPreviewInputs = committed.copyWithFreedraw(
      points: List.of(preview.points),
      pressures: List.of(preview.pressures),
      simulatePressure: preview.simulatePressure,
    );
    return (
      preview: preview,
      committed: committed,
      committedAtPreviewInputs: committedAtPreviewInputs,
    );
  }

  ({Object digest, SpyCanvas spy}) renderCommands(Element element) {
    final recorder = ui.PictureRecorder();
    final spy = SpyCanvas(ui.Canvas(recorder));
    ElementRenderer.render(spy, element, RoughCanvasAdapter());
    recorder.endRecording().dispose();
    final digest = [
      spy.drawCallCount,
      spy.saveLayerCount,
      spy.shaderPathCount,
      spy.pathBlendModes.toList(),
      spy.pathAlphas.toList(),
      spy.pathOrder
          .map((r) => [r.left, r.top, r.right, r.bottom])
          .toList(),
    ];
    return (digest: digest, spy: spy);
  }

  Future<Uint8List> pixelDigest(Element element) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Offset.zero & const ui.Size(300, 200),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    ElementRenderer.render(canvas, element, RoughCanvasAdapter());
    final picture = recorder.endRecording();
    final image = await picture.toImage(300, 200);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  test('B1: 五笔命令摘要逐笔一致（预览 vs 提交管线·同渲染入参）', () async {
    for (final brush in BrushType.values) {
      final pair = await strokePair(brush);
      final r1 = renderCommands(pair.preview);
      final r2 = renderCommands(pair.committedAtPreviewInputs);
      expect(r1.digest, r2.digest, reason: '$brush 同入参下预览与提交管线必须一致');
      if (brush == BrushType.pencil) {
        expect(
          r2.spy.drawCallCount,
          lessThanOrEqualTo(2),
          reason: '铅笔主绘+可选颗粒互斥，不得叠加',
        );
        expect(r2.spy.saveLayerCount, 0);
      }
      if (brush == BrushType.highlighter) {
        expect(
          r2.spy.pathBlendModes.contains(ui.BlendMode.darken),
          isTrue,
          reason: '荧光笔 darken 直绘',
        );
        expect(r2.spy.saveLayerCount, 0, reason: 'darken 无需 saveLayer');
      }
    }
  });

  test('B2: 五笔像素摘要逐笔一致（同渲染入参）', () async {
    for (final brush in BrushType.values) {
      final pair = await strokePair(brush);
      final p1 = await pixelDigest(pair.preview);
      final p2 = await pixelDigest(pair.committedAtPreviewInputs);
      expect(p1, p2, reason: '$brush 同入参下预览与终稿像素必须逐字节一致');
    }
  });

  test('B3: 突变哨兵——无 customData 的旧预览在非钢笔四笔上渲染必不同', () {
    // 修复前旧预览形态：字段相同但缺 customData → 渲染端双重回退
    // （钢笔 profile + legacy thinning）。恒压 0.5 是 encodePressure
    // 仿射映射的不动点，钢笔预览/提交本就逐字节相同，故只对非钢笔四笔
    // 断言差异；后人勿"补全"钢笔哨兵后误判测试失效。
    final points = slowArc.points;
    final pressures = List<double>.filled(points.length, 0.5);
    FreedrawElement replica(BrushType brush, {required bool withMark}) =>
        FreedrawElement(
          id: const ElementId('__preview__'),
          x: 0,
          y: 0,
          width: 0,
          height: 0,
          points: points,
          pressures: pressures,
          simulatePressure: false,
          isComplete: false,
          seed: 42,
          customData: withMark
              ? customDataWithFreedrawRender(null, brush)
              : null,
        );
    for (final brush in BrushType.values.where(
      (b) => b != BrushType.fountainPen,
    )) {
      expect(
        renderCommands(replica(brush, withMark: false)).digest,
        isNot(renderCommands(replica(brush, withMark: true)).digest),
        reason: '$brush：缺笔型标记必须被本测试组捕获（防假绿）',
      );
    }
  });

  test('B4: 真压感笔形预览拿到编码压力且与提交同管线', () async {
    final pair = await strokePair(BrushType.brushPen);
    expect(pair.preview.pressures, isNotEmpty, reason: '预览 overlay 携带压力');
    expect(pair.committed.pressures, isNotEmpty, reason: '提交元素携带压力');
    expect(
      pair.preview.pressures.length,
      lessThanOrEqualTo(pair.committed.pressures.length),
      reason: '预览是中间态，压力序列为提交端前缀',
    );
    expect(
      pair.preview.pressures.every((p) => p >= 0 && p <= 1 && p != 0.8),
      isTrue,
      reason: '预览压力为编码值（非原始 0.8）',
    );
    expect(
      pair.committed.pressures.every((p) => p >= 0 && p <= 1 && p != 0.8),
      isTrue,
      reason: '提交压力为编码值（非原始 0.8）',
    );
  });

  test('C1: measureStroke 轮廓点数 O(n) 有界且确定（铅笔/荧光笔）', () {
    final points = [for (var i = 0; i <= 120; i++) Point(i * 2.0, 50.0)];
    final pressures = List<double>.filled(points.length, 0.5);
    for (final brush in [BrushType.pencil, BrushType.highlighter]) {
      final a = FreedrawRenderer.measureStroke(
        points,
        strokeWidth: 8,
        pressures: pressures,
        pressureEncoded: true,
        outlineRenderMode: OutlineRenderMode.quadratic,
        brushType: brush,
      );
      final b = FreedrawRenderer.measureStroke(
        points,
        strokeWidth: 8,
        pressures: pressures,
        pressureEncoded: true,
        outlineRenderMode: OutlineRenderMode.quadratic,
        brushType: brush,
      );
      expect(b.outlinePointCount, a.outlinePointCount, reason: '$brush 确定性');
      expect(
        a.outlinePointCount,
        lessThanOrEqualTo(points.length * 4 + 16),
        reason: '$brush 轮廓点数 O(n) 有界（live 逐帧成本护栏）',
      );
    }
  });

  test('C2: 铅笔渲染分支互斥门禁（shader 可用=1 次；强制降级=主绘+颗粒 2 次）', () async {
    // shader 可用：主绘挂 shader，无颗粒第二 path、无 saveLayer。
    final onPair = await strokePair(BrushType.pencil);
    final on = renderCommands(onPair.preview);
    expect(on.spy.shaderPathCount, 1, reason: 'shader 可用时主绘挂 shader');
    expect(on.spy.drawCallCount, 1, reason: '互斥：不触发颗粒 Path');
    expect(on.spy.saveLayerCount, 0);

    // 强制降级：主绘 + 一次颗粒 drawPath，无 shader。
    PencilShader.loader = (assetKey) => throw StateError('forced unavailable');
    PencilShader.resetForTesting();
    final offPair = await strokePair(BrushType.pencil);
    final off = renderCommands(offPair.preview);
    expect(off.spy.shaderPathCount, 0);
    expect(off.spy.drawCallCount, 2, reason: '主绘 + 一次颗粒 drawPath');
  });
}
