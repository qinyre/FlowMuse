import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/draw_style.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';
import '../fixtures/brush_stroke_fixtures.dart';

/// 铅笔纹理与确定性降级（Issue #5 T5 / A9、A10）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DrawStyle pencilStyle(double strokeWidth) => DrawStyle(
    strokeColor: const ui.Color(0xFF1E1E1E),
    backgroundColor: const ui.Color(0x00000000),
    fillStyle: FillStyle.solid,
    strokeWidth: strokeWidth,
    strokeStyle: StrokeStyle.solid,
    roughness: 0,
    opacity: 1,
    seed: 1,
  );

  void drawPencil(ui.Canvas canvas, List<Point> points, double width) {
    FreedrawRenderer.draw(
      canvas,
      points,
      pencilStyle(width),
      pressures: List<double>.filled(points.length, 0.5),
      pressureEncoded: true,
      brushType: BrushType.pencil,
      outlineRenderMode: OutlineRenderMode.quadratic,
    );
  }

  Future<Uint8List> render(List<Point> points, double width) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 300, 120),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.translate(20, 40);
    drawPencil(canvas, points, width);
    final picture = recorder.endRecording();
    final image = await picture.toImage(300, 120);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  tearDown(() {
    PencilShader.loader = (assetKey) => throw StateError('forced unavailable');
    PencilShader.resetForTesting();
    PencilShader.loader = ui.FragmentProgram.fromAsset;
  });

  group('shader 路径（测试环境真实编译产物）', () {
    setUp(() async {
      PencilShader.resetForTesting();
      await PencilShader.init();
    });

    test('A9: 同一元素连续重绘像素摘要逐字节一致', () async {
      final a = await render(slowArc.points, 4);
      final b = await render(slowArc.points, 4);
      expect(a, equals(b), reason: 'shader 纹理必须确定（无每帧随机）');
    });

    test('A9: 连续 100 次命令摘要一致（drawCall/blend/shader 计数）', () {
      final recorder = ui.PictureRecorder();
      final spy = SpyCanvas(ui.Canvas(recorder));
      final first = <Object?>[];
      for (var i = 0; i < 100; i++) {
        spy.drawCallCount = 0;
        spy.shaderPathCount = 0;
        drawPencil(spy, cornerPolyline.points, 4);
        final summary = [spy.drawCallCount, spy.shaderPathCount];
        if (first.isNotEmpty) {
          expect(summary, equals(first), reason: '第 $i 次重绘命令摘要漂移');
        } else {
          first.addAll(summary);
        }
      }
      expect(first[0], lessThanOrEqualTo(2), reason: '铅笔最多 1 主绘 + 1 纹理');
      expect(first[1], 1, reason: 'shader 路径挂 shader 的绘制恰一次');
      recorder.endRecording().dispose();
    });

    test('A9: 不同几何的纹理分布不同，主体轮廓 bounds 稳定', () async {
      final a = await render(slowArc.points, 4);
      final b = await render(fastArc.points, 4);
      // 几何不同 → 纹理与轮廓都不同（字节级差异非恒真：同几何已证逐字节一致）
      expect(a, isNot(equals(b)));

      final outlineA = FreedrawRenderer.buildOutline(
        slowArc.points,
        strokeWidth: 4,
        pressures: List<double>.filled(slowArc.points.length, 0.5),
        pressureEncoded: true,
        brushType: BrushType.pencil,
      );
      final outlineA2 = FreedrawRenderer.buildOutline(
        slowArc.points,
        strokeWidth: 4,
        pressures: List<double>.filled(slowArc.points.length, 0.5),
        pressureEncoded: true,
        brushType: BrushType.pencil,
      );
      expect(
        outlineA2.map((o) => '${o.dx},${o.dy}').toList(),
        equals(outlineA.map((o) => '${o.dx},${o.dy}').toList()),
        reason: '主体轮廓不因纹理失控',
      );
    });
  });

  group('降级路径（shader 强制失败）', () {
    setUp(() {
      PencilShader.loader = (assetKey) =>
          throw StateError('forced unavailable');
      PencilShader.resetForTesting();
    });

    test('A10: shader 失败仍可绘制且确定（逐字节一致）', () async {
      expect(PencilShader.isAvailable, isFalse);
      final a = await render(slowArc.points, 4);
      final b = await render(slowArc.points, 4);
      expect(a, equals(b), reason: '降级颗粒必须确定（无每帧随机）');
      // 有实际内容（非空白）
      expect(a.any((byte) => byte != 255), isTrue, reason: '必须画出笔迹');
    });

    test('A10: 额外绘制调用有固定上限（≤2），不逐点 draw', () {
      final recorder = ui.PictureRecorder();
      final spy = SpyCanvas(ui.Canvas(recorder));
      // 长笔迹（261 点）——颗粒并入一条 Path，只允许一次额外 drawPath
      final long = [
        for (var i = 0; i < 261; i++)
          Point(1.0 * i, 10 * (i % 7 - 3).toDouble()),
      ];
      drawPencil(spy, long, 6);
      expect(spy.drawCallCount, lessThanOrEqualTo(2));
      expect(spy.drawCallCount, greaterThanOrEqualTo(1));
      expect(spy.shaderPathCount, 0);
      recorder.endRecording().dispose();
    });

    test('A10: 降级颗粒不越出主体轮廓（bounds 受控）', () {
      final recorder = ui.PictureRecorder();
      final spy = SpyCanvas(ui.Canvas(recorder));
      drawPencil(spy, slowArc.points, 6);
      expect(spy.pathOrder.length, 2, reason: '主体 + 颗粒两条 path');
      final mainBounds = spy.pathOrder.first;
      final grainBounds = spy.pathOrder.last;
      // 颗粒线段在主体轮廓外扩 2.5px 内：颗粒半长按未收锋半径
      // （≤0.9×size/2），而轮廓两端有 4×size 收锋变窄，允许该半径差
      // 的越出余量；几何中段仍完全在轮廓内。
      expect(grainBounds.left, greaterThanOrEqualTo(mainBounds.left - 2.5));
      expect(grainBounds.right, lessThanOrEqualTo(mainBounds.right + 2.5));
      expect(grainBounds.top, greaterThanOrEqualTo(mainBounds.top - 2.5));
      expect(grainBounds.bottom, lessThanOrEqualTo(mainBounds.bottom + 2.5));
      recorder.endRecording().dispose();
    });

    test('A10: 降级纹理与光滑钢笔线可区分（非完全光滑）', () async {
      PencilShader.loader = ui.FragmentProgram.fromAsset;
      PencilShader.resetForTesting();
      // 用降级口径渲染铅笔
      PencilShader.loader = (assetKey) =>
          throw StateError('forced unavailable');
      PencilShader.resetForTesting();
      final pencilBytes = await render(slowArc.points, 4);

      // 同几何同宽的钢笔（无纹理）对照
      Future<Uint8List> renderFountain() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 300, 120),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        canvas.translate(20, 40);
        FreedrawRenderer.draw(
          canvas,
          slowArc.points,
          pencilStyle(4),
          pressures: List<double>.filled(slowArc.points.length, 0.5),
          pressureEncoded: true,
          brushType: BrushType.fountainPen,
          outlineRenderMode: OutlineRenderMode.quadratic,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 120);
        picture.dispose();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      final fountainBytes = await renderFountain();
      // 尺寸不同（sizeScale 0.82 vs 1.0）本就不同；关键是降级铅笔自身
      // 有颗粒（与自身主体光滑面差异）——已由“颗粒 path 存在”与确定性
      // 用例证明，这里再锁一道：两者字节不同且铅笔侧有中间调像素。
      expect(pencilBytes, isNot(equals(fountainBytes)));
      var midTonePencil = 0;
      for (var i = 0; i < pencilBytes.length; i += 4) {
        final v = pencilBytes[i];
        if (v > 60 && v < 220) midTonePencil++;
      }
      expect(midTonePencil, greaterThan(0), reason: '降级铅笔必须有颗粒中间调（不完全光滑）');
    });
  });

  test('PencilGrainHash 确定性与区分度', () {
    final a = PencilGrainHash.hash(10, 20, 4, 7);
    final b = PencilGrainHash.hash(10, 20, 4, 7);
    expect(a, equals(b));
    expect(PencilGrainHash.hash(11, 20, 4, 7), isNot(a));
    expect(PencilGrainHash.hash(10, 20, 4, 8), isNot(a));
    expect(a, inInclusiveRange(0.0, 1.0));
  });
}
