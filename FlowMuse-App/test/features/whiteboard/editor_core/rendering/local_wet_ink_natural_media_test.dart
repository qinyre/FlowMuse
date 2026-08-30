import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/property_panel_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_plan.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_sampler.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';

import '../fixtures/brush_stroke_fixtures.dart';
import 'natural_media/natural_media_image_metrics.dart';
import 'natural_media_visual_sheet_support.dart';

// ---------------------------------------------------------------------------
// T6：统一静态画布和本地湿墨（计划任务卡）。
//
// - 工作项 1/3：ActiveFreedrawView 落笔冻结 renderVersion，layered
//   LocalWetInkPainter 与静态提交元素共用同一 dispatch；
// - 工作项 2：默认 preview 路径的 v2 一致性已由 wet_ink_preview_rendering
//   B1/B2 锁定（本文件只测 layered painter 路径，不重复替代）；
// - 工作项 5/6：已确认前缀 primitive key 稳定（本地无预测点机制，
//   _previewPoints 即实际点活视图，等价覆盖"回撤不移动已确认 primitive"）；
// - 工作项 7/验收：isComplete 只影响尾端——弧长前 90% mask 像素差 ≤1%。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpModeler() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  MarkdrawController makeLayeredController(BrushType brush) {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: true),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = brush;
    return controller;
  }

  test('T6-1 落笔冻结 renderVersion；中途切笔不改变当前笔', () async {
    for (final brush in BrushType.values) {
      final controller = makeLayeredController(brush);
      controller.onPointerDown(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset.zero,
          pressure: 0.6,
        ),
      );
      controller.onPointerMove(
        const PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(30, 0),
          pressure: 0.6,
          timeStamp: Duration(milliseconds: 20),
        ),
      );
      await pumpModeler();
      final tool = controller.activeTool as FreedrawTool;
      final view = tool.activeView!;
      expect(
        view.renderVersion,
        defaultRenderVersionForNewStroke(brush),
        reason: '$brush 落笔冻结默认渲染版本',
      );

      // 中途切笔：view 的笔型/版本保持落笔值（T6 工作项 8）。
      controller.activeBrushType = BrushType.highlighter;
      final after = (controller.activeTool as FreedrawTool).activeView!;
      expect(after.brushType, brush, reason: '$brush 中途切笔不改笔型');
      expect(
        after.renderVersion,
        defaultRenderVersionForNewStroke(brush),
        reason: '$brush 中途切笔不改渲染版本',
      );
    }
  });

  test('T6-2 layered painter 与静态渲染同管线逐字节一致（v2/v1）', () async {
    for (final brush in [
      BrushType.pencil,
      BrushType.brushPen,
      BrushType.fountainPen,
    ]) {
      final f = brush == BrushType.pencil
          ? pencilPressureRamp
          : brush == BrushType.brushPen
          ? brushNa
          : slowArc;
      final placed = fitFixtureToCell(f);
      final renderVersion = defaultRenderVersionForNewStroke(brush);
      final state = LocalWetInkState();
      addTearDown(state.dispose);
      state.publish(
        LocalWetInkFrame(
          strokeEpoch: 1,
          view: ActiveFreedrawView(
            strokeId: const ElementId('t6-layered'),
            points: placed,
            pressures: f.pressures,
            simulatePressure: false,
            brushType: brush,
            renderVersion: renderVersion,
          ),
          style: const ElementStyle(strokeColor: '#000000', strokeWidth: 6),
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Offset.zero & const ui.Size(kCellWidth, kCellHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      LocalWetInkPainter(
        state: state,
        adapter: RoughCanvasAdapter(),
        viewport: const ViewportState(),
      ).paint(canvas, const ui.Size(kCellWidth, kCellHeight));
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        kCellWidth.round(),
        kCellHeight.round(),
      );
      picture.dispose();
      final wetBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      // 静态侧：与 painter 完全相同的元素构造（同 id/points/pressures/
      // customData/isComplete=false），ElementRenderer 直渲。
      final staticElement = FreedrawElement(
        id: const ElementId('t6-layered'),
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        points: placed,
        pressures: f.pressures,
        simulatePressure: false,
        isComplete: false,
        customData: customDataWithFreedrawRender(
          null,
          brush,
          renderVersion: renderVersion,
        ),
        strokeWidth: 6,
      );
      final recorder2 = ui.PictureRecorder();
      final canvas2 = ui.Canvas(recorder2);
      canvas2.drawRect(
        ui.Offset.zero & const ui.Size(kCellWidth, kCellHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      ElementRenderer.render(canvas2, staticElement, RoughCanvasAdapter());
      final picture2 = recorder2.endRecording();
      final image2 = await picture2.toImage(
        kCellWidth.round(),
        kCellHeight.round(),
      );
      picture2.dispose();
      final staticBytes = await image2.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image2.dispose();

      expect(
        wetBytes!.buffer.asUint8List(),
        equals(staticBytes!.buffer.asUint8List()),
        reason: '$brush layered 湿墨必须与静态渲染逐字节一致',
      );
    }
  });

  test('T6-3 isComplete 只影响尾端：弧长前 90% mask 像素差 ≤1%', () async {
    for (final (name, f, brush) in [
      ('铅笔', pencilPressureRamp, BrushType.pencil),
      ('毛笔', brushNa, BrushType.brushPen),
    ]) {
      final placed = fitFixtureToCell(f);
      final element = placedElement(placed, f.pressures, brush, 't6complete');
      final wet = element.copyWithFreedraw(isComplete: false);
      Future<NaturalMediaRaster> rasterize(FreedrawElement e) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Offset.zero & const ui.Size(kCellWidth, kCellHeight),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        ElementRenderer.render(canvas, e, RoughCanvasAdapter());
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          kCellWidth.round(),
          kCellHeight.round(),
        );
        picture.dispose();
        final raster = await NaturalMediaRaster.fromImage(image);
        image.dispose();
        return raster;
      }

      final wetRaster = await rasterize(wet);
      final doneRaster = await rasterize(element);
      final geom = StrokeArcGeometry(placed);
      final diff = PixelDiff.differingInkRatio(
        wetRaster,
        doneRaster,
        mask: ArcPrefixMask.default90(geom).containsPixel,
      );
      expect(
        diff,
        lessThanOrEqualTo(0.01),
        reason:
            '$name 抬笔（isComplete）只允许尾端差异，前 90% 像素差 '
            '$diff 应 ≤1%',
      );
    }
  });

  test('T6-4 已确认前缀 primitive key 稳定：前缀边 key ⊆ 整笔且不位移', () {
    for (final (name, f, brush) in [
      ('铅笔', pencilPressureRamp, BrushType.pencil),
      ('毛笔', brushZhe, BrushType.brushPen),
    ]) {
      final placed = fitFixtureToCell(f);
      NaturalMediaStrokePlan samplePrefix(int pointCount) =>
          NaturalMediaStrokeSampler.sample(
            strokeId: 't6-prefix',
            points: placed.sublist(0, pointCount),
            pressures: f.pressures.sublist(0, pointCount),
            strokeWidth: kNominalWidth,
            brushType: brush,
            isComplete: false,
          );

      final full = samplePrefix(placed.length);
      // 前缀帧（前 60% 点）：排除移动前沿的最后一条边（它是湿墨尾，
      // 尚未确认），其余边的 key 必须与整笔逐值一致。
      final prefixPointCount = (placed.length * 0.6).round();
      final prefix = samplePrefix(prefixPointCount);
      final confirmedEdgeEnd = prefix.edges[prefix.edges.length - 2].index;

      String fingerprint(NaturalMediaStrokePlan plan, int edgeIndex) => [
        for (final p in plan.primitives)
          if (p.edgeIndex <= edgeIndex)
            '${p.edgeIndex}:${p.ordinal}:${p.channel}:${p.kind.name}'
                ':${p.center?.x.toStringAsFixed(9)}'
                ':${p.center?.y.toStringAsFixed(9)}',
      ].join(';');

      final prefixKeys = prefix
          .primitiveKeyDigest()
          .where((k) => int.parse(k.split(':').first) <= confirmedEdgeEnd)
          .toSet();
      final fullKeys = full.primitiveKeyDigest().toSet();
      expect(
        prefixKeys,
        everyElement(isIn(fullKeys)),
        reason: '$name 前缀帧已确认边的 key 必须原样出现在整笔中',
      );
      expect(
        fingerprint(prefix, confirmedEdgeEnd),
        equals(fingerprint(full, confirmedEdgeEnd)),
        reason: '$name 前缀帧已确认边与整笔逐值一致（不随书写位移）',
      );
    }
  });

  test('T6-5 提交沿 live strokeId：layered 帧 view 与提交元素同 id 同版本', () async {
    final controller = makeLayeredController(BrushType.pencil);
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset.zero,
        pressure: 0.5,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(40, 10),
        pressure: 0.5,
        timeStamp: Duration(milliseconds: 20),
      ),
    );
    await pumpModeler();
    final view = (controller.activeTool as FreedrawTool).activeView!;
    expect(
      controller.localWetInkState.frame,
      isNotNull,
      reason: 'layered 模式书写中必须发布湿墨帧',
    );
    expect(controller.localWetInkState.frame!.view, same(view));

    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(80, 20),
        pressure: 0.5,
        timeStamp: Duration(milliseconds: 40),
      ),
    );
    await pumpModeler();
    final committed = controller.currentScene.elements
        .whereType<FreedrawElement>()
        .last;
    expect(
      committed.id,
      view.strokeId,
      reason: '提交元素必须沿用 live strokeId（T4 已修，layered 侧复锁）',
    );
    expect(
      brushRenderVersionFromCustomData(committed.customData),
      view.renderVersion,
      reason: '提交元素渲染版本必须与湿墨帧冻结值一致',
    );
    // 抬笔后湿墨帧清空（生命周期完整）。
    expect(
      controller.localWetInkState.frame,
      isNull,
      reason: '抬笔后 layered 湿墨帧必须清空',
    );
  });
}
