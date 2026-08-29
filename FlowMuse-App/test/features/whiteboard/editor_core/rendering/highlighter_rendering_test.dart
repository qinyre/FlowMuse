import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/draw_style.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brush_path_metrics.dart';
import 'canvas_spy.dart';

/// 荧光笔渲染：恒宽平头 + darken 叠加（Issue #5 T4 / A5–A7、结构门禁）。
///
/// 像素回读一律用普通 test()（fake-async 的 testWidgets 区内 toImage
/// 永不完成）。flutter test 为软件光栅：本组断言是 darken 合成语义的
/// 证据；真实后端（Web canvasKit / OHOS Impeller）随构建验收另证。
void main() {
  const white = ui.Color(0xFFFFFFFF);
  const black = ui.Color(0xFF000000);

  // 荧光笔水平长划：y=100，x∈[30,270]，strokeWidth 20 → size 84，恒压。
  final points = [for (var i = 0; i <= 60; i++) Point(30 + 4.0 * i, 100.0)];
  List<double> pressuresOf(int n) => List<double>.filled(n, 0.5);

  // 荧光笔默认色 #ffff00（以 Color 形式供 DrawStyle 使用）
  DrawStyle highlighterStyle(double strokeWidth, {double opacity = 1}) =>
      DrawStyle(
        strokeColor: const ui.Color(0xFFFFFF00),
        backgroundColor: const ui.Color(0x00000000),
        fillStyle: FillStyle.solid,
        strokeWidth: strokeWidth,
        strokeStyle: StrokeStyle.solid,
        roughness: 0,
        opacity: opacity,
        seed: 1,
      );

  Future<ui.Image> renderScene(
    ui.Size size,
    void Function(ui.Canvas canvas) painter,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = white);
    painter(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    picture.dispose();
    return image;
  }

  Future<ByteData> pixels(ui.Image image) async =>
      (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;

  (int, int, int) at(ByteData d, int width, int x, int y) {
    final o = (y * width + x) * 4;
    return (d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
  }

  void drawHighlighter(ui.Canvas canvas, {double strokeWidth = 20}) {
    FreedrawRenderer.draw(
      canvas,
      points,
      highlighterStyle(strokeWidth),
      pressures: pressuresOf(points.length),
      pressureEncoded: true,
      brushType: BrushType.highlighter,
      outlineRenderMode: OutlineRenderMode.quadratic,
    );
  }

  test('A5: 白底同色双层重叠区比单层更深', () async {
    final image = await renderScene(const ui.Size(300, 200), (canvas) {
      drawHighlighter(canvas); // 第一层
      drawHighlighter(canvas); // 第二层（完全重叠）
    });
    addTearDown(image.dispose);
    final data = await pixels(image);

    // 中心线正下方（y=115，半宽 42 内）为重叠区
    final overlap = at(data, 300, 150, 115);
    // 单层对照：同 y 但第一层单独渲染
    final singleImage = await renderScene(const ui.Size(300, 200), (canvas) {
      drawHighlighter(canvas);
    });
    addTearDown(singleImage.dispose);
    final singleData = await pixels(singleImage);
    final single = at(singleData, 300, 150, 115);

    // 白底上黄色 darken：B 通道被压暗；双层 (1,1,0.7²) 比单层 (…,0.7) 更深
    expect(single.$3, lessThan(255), reason: '单层即已变黄变深');
    expect(overlap.$3, lessThan(single.$3), reason: '重叠必须更深');
    expect(overlap.$1, greaterThan(200), reason: 'R 仍接近满（黄色语义）');
    expect(overlap.$2, greaterThan(200), reason: 'G 仍接近满（黄色语义）');
  });

  test('A6: 覆盖纯黑路径：黑色不提亮、路径仍可辨', () async {
    final image = await renderScene(const ui.Size(300, 200), (canvas) {
      // 黑色粗线（模拟文字/笔迹）
      final line = ui.Paint()
        ..color = black
        ..strokeWidth = 14
        ..style = ui.PaintingStyle.stroke;
      canvas.drawLine(
        const ui.Offset(20, 100),
        const ui.Offset(280, 100),
        line,
      );
      drawHighlighter(canvas);
    });
    addTearDown(image.dispose);
    final data = await pixels(image);

    // 黑线上取点：darken(黄, 黑) = 黑 —— 不得提亮
    final onInk = at(data, 300, 150, 100);
    expect(onInk.$1, lessThan(60), reason: '黑色 R 不得被提亮');
    expect(onInk.$2, lessThan(60), reason: '黑色 G 不得被提亮');
    expect(onInk.$3, lessThan(60), reason: '黑色 B 不得被提亮');
    // 黑线之外的荧光笔区域仍是黄色（路径两侧可辨）
    final beside = at(data, 300, 150, 130);
    expect(beside.$1, greaterThan(180), reason: '黑线旁仍为黄色高亮');
  });

  test('A7: 透明 saveLayer 内绘制再合成，不消失', () async {
    final image = await renderScene(const ui.Size(300, 200), (canvas) {
      // Issue #8 聚焦同款：透明离屏层内绘制高亮，再合成回白底
      canvas.saveLayer(const ui.Rect.fromLTWH(0, 50, 300, 100), ui.Paint());
      drawHighlighter(canvas);
      canvas.restore();
    });
    addTearDown(image.dispose);
    final data = await pixels(image);

    final inside = at(data, 300, 150, 115);
    expect(inside.$3, lessThan(250), reason: '透明层内的高亮合成后不得消失');
    expect(inside.$1, greaterThan(180), reason: '仍呈黄色');
  });

  test('dim 0.22 层内高亮仍可见（Issue #8 变淡兼容）', () async {
    final image = await renderScene(const ui.Size(300, 200), (canvas) {
      canvas.saveLayer(
        const ui.Rect.fromLTWH(0, 50, 300, 100),
        ui.Paint()..color = const ui.Color(0x38FFFFFF),
      );
      drawHighlighter(canvas);
      canvas.restore();
    });
    addTearDown(image.dispose);
    final data = await pixels(image);

    final dimmed = at(data, 300, 150, 115);
    final outside = at(data, 300, 150, 190);
    // dim 层内高亮 vs 层外白底：必须有可辨差异
    expect(
      (dimmed.$3 - outside.$3).abs(),
      greaterThan(8),
      reason: 'dim 层内高亮仍可辨',
    );
  });

  test('结构门禁：一条荧光笔一次 drawPath、darken、无 saveLayer、非 multiply/modulate', () {
    final recorder = ui.PictureRecorder();
    final inner = ui.Canvas(recorder);
    final spy = SpyCanvas(inner);
    drawHighlighter(spy);

    expect(spy.drawCallCount, 1, reason: '一条荧光笔恰好一次主要绘制');
    expect(spy.saveLayerCount, 0, reason: '荧光笔热路径不得新增 saveLayer');
    expect(spy.pathBlendModes.single, ui.BlendMode.darken);
    expect(
      spy.pathBlendModes,
      everyElement(isNot(anyOf(ui.BlendMode.multiply, ui.BlendMode.modulate))),
      reason: '禁止 multiply/modulate',
    );
    // 最终透明度 ≈ opacityScale 0.30
    expect(spy.pathAlphas.single, closeTo(0.30, 0.02));
    expect(spy.shaderPathCount, 0);
    recorder.endRecording().dispose();
  });

  test('平头端帽：终端弧长处宽度 ≈ 中段宽度（平截面而非圆/针尖）', () {
    final outline = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 20,
      pressures: pressuresOf(points.length),
      pressureEncoded: true,
      brushType: BrushType.highlighter,
    );
    final midWidth = BrushOutlineMetrics.widthAtArc(points, outline, 0.5);
    final nearEndWidth = BrushOutlineMetrics.widthAtArc(points, outline, 0.995);
    final nearStartWidth = BrushOutlineMetrics.widthAtArc(
      points,
      outline,
      0.005,
    );
    expect(midWidth, greaterThan(60), reason: '恒宽 84 的中段宽度');
    // 平头：贴近端点处仍保持 ≥85% 中段宽度（圆头会收敛、针尖趋 0）
    expect(
      nearEndWidth / midWidth,
      greaterThan(0.85),
      reason:
          '收端平截面 end=${nearEndWidth.toStringAsFixed(1)}'
          ' mid=${midWidth.toStringAsFixed(1)}',
    );
    expect(
      nearStartWidth / midWidth,
      greaterThan(0.85),
      reason: '起端平截面 start=${nearStartWidth.toStringAsFixed(1)}',
    );
  });

  test('恒宽：不同压力输入轮廓一致（A1 荧光笔口径）', () {
    final low = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 20,
      pressures: List<double>.filled(points.length, 0.1),
      pressureEncoded: true,
      brushType: BrushType.highlighter,
    );
    final high = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 20,
      pressures: List<double>.filled(points.length, 0.95),
      pressureEncoded: true,
      brushType: BrushType.highlighter,
    );
    expect(
      high.map((o) => '${o.dx},${o.dy}').toList(),
      equals(low.map((o) => '${o.dx},${o.dy}').toList()),
    );
  });

  test('深色底上“不提亮、不消失”（已知局限：darken 深底弱可见为数学预期）', () async {
    final image = await renderScene(const ui.Size(300, 200), (canvas) {
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 300, 200),
        ui.Paint()..color = const ui.Color(0xFF404040),
      );
      drawHighlighter(canvas);
    });
    addTearDown(image.dispose);
    final data = await pixels(image);

    final onHighlight = at(data, 300, 150, 115);
    final background = at(data, 300, 150, 190);
    // darken 在深底上：结果 = min(灰底, 黄)≈灰底 —— 不得比底更亮
    expect(
      onHighlight.$1,
      lessThanOrEqualTo(background.$1 + 4),
      reason: '深底不得被提亮',
    );
    expect(
      onHighlight.$3,
      lessThanOrEqualTo(background.$3 + 4),
      reason: '深底不得被提亮（B 通道）',
    );
    // 不消失：与底色仍存在（可能有轻微 alpha srcOver 贡献的）差异或相同
    // —— 语义证据以白底/黑底/透明层用例为准，这里只锁定“不提亮”。
  });
}
