import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';

import '../fixtures/brush_stroke_fixtures.dart';

// ---------------------------------------------------------------------------
// 真机盲测反馈诊断（临时，不进验收矩阵）：合成"真实书写特征"笔画——
// 高密度点（~0.8px 间距，120Hz 手写 + minDistance 0.6）+ 窄压力动态
//（中等力度 0.45-0.55，经 InputPolicy floor/ceiling 与 encodePressure
// 两级压缩后的典型区间）+ 6× 场景（等效 610% 画布观看）——渲染 PNG
// 复现"等宽胶囊/收笔节点裂缝"两个平板实测问题。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 沿折线按 [step] 重采样（线性插值），模拟真实高密度输入。
  List<Point> densify(List<Point> src, double step) {
    final out = <Point>[src.first];
    for (var i = 1; i < src.length; i++) {
      final a = src[i - 1], b = src[i];
      final d = math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
      );
      final n = math.max(1, (d / step).ceil());
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        out.add(Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    return out;
  }

  Future<void> render(String name, List<Point> pts, List<double> prs) async {
    const scale = 6.0; // 等效 610% 观看的场景放大
    final w = (900 * scale).round(), h = (150 * scale).round();
    final element = FreedrawElement(
      id: ElementId('repro-$name'),
      x: 0,
      y: 0,
      width: 0,
      height: 0,
      points: [for (final p in pts) Point(p.x * scale, p.y * scale)],
      pressures: prs,
      simulatePressure: false,
      isComplete: true,
      strokeColor: '#000000',
      strokeWidth: 6 * scale,
      opacity: 1.0,
      customData: customDataWithFreedrawRender(
        null,
        BrushType.brushPen,
        renderVersion: BrushRenderVersion.naturalMediaV2,
      ),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Offset.zero & ui.Size(w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFDF4),
    );
    ElementRenderer.render(canvas, element, RoughCanvasAdapter());
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('build/inspect_realinput')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  test('合成真实输入复现：等宽/裂缝诊断图', () async {
    for (final (name, f) in [
      ('na', brushNa),
      ('zhe', brushZhe),
      ('scurve', brushSCurve),
    ]) {
      // fixture 点已是 cell 坐标（经 fitFixtureToCell 同源布局：直接用
      // fixture 原始形状归一到 900x150 再 densify）。
      final xs = f.points.map((p) => p.x);
      final ys = f.points.map((p) => p.y);
      final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
      final spanX = math.max(maxX - minX, 1e-6);
      final spanY = math.max(maxY - minY, 1e-6);
      var s = math.min(780 / spanX, 90 / spanY).clamp(0.0, 3.0);
      final placed = [
        for (final p in f.points)
          Point(60 + (p.x - minX) * s, 30 + (p.y - minY) * s),
      ];
      final dense = densify(placed, 0.8);
      // 窄压力 A：恒定 0.5（极端——信号死）；B：0.45-0.55 慢摆（窄动态）。
      final flat = List<double>.filled(dense.length, 0.5);
      final narrow = [
        for (var i = 0; i < dense.length; i++)
          // 归一弧长位置的慢正弦，全幅 0.45-0.55。
          0.5 + 0.05 * math.sin(2 * math.pi * i / dense.length),
      ];
      await render('${name}_dense_flat', dense, flat);
      await render('${name}_dense_narrow', dense, narrow);
      // 收笔抬笔：末 25% 弧长压力从 0.5 斜坡降到 0.08（触发 tailDrop
      // 收锋楔形），且收笔段点距拉大（快速抬笔：每 4 点抽 1 点）。
      final tailRamp = [
        for (var i = 0; i < dense.length; i++)
          i < dense.length * 0.75
              ? 0.5
              : math.max(
                  0.08,
                  0.5 -
                      0.42 * (i - dense.length * 0.75) / (dense.length * 0.25),
                ),
      ];
      final sparseTail = <Point>[dense[0]];
      final sparseTailPrs = <double>[tailRamp[0]];
      for (var i = 1; i < dense.length; i++) {
        final inTail = i >= dense.length * 0.75;
        if (!inTail || i % 4 == 0) {
          sparseTail.add(dense[i]);
          sparseTailPrs.add(tailRamp[i]);
        }
      }
      await render('${name}_dense_tailramp', sparseTail, sparseTailPrs);
    }
  });
}
