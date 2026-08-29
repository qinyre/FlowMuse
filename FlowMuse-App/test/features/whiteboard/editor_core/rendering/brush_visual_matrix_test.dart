import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';

/// 五笔同轨迹视觉矩阵（Issue #5 验收材料 + 两两差异自动门禁）。
///
/// 行序固定为 BrushType.values 声明序（铅笔/圆珠笔/钢笔/毛笔/荧光笔），
/// 五行使用完全相同的轨迹与名义笔宽，产物写入 build/brush_visual_matrix/
/// （matrix.png + matrix.svg），供视觉审查与浏览器核对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rowHeight = 150.0;
  const rowWidth = 900.0;
  const nominalWidth = 6.0;

  List<Point> normalizedTrajectory() {
    final xs = slowArc.points.map((p) => p.x);
    final ys = slowArc.points.map((p) => p.y);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final scale = math.min(
      (rowWidth - 120) / (maxX - minX),
      (rowHeight - 60) / (maxY - minY),
    );
    final dx = (rowWidth - (maxX - minX) * scale) / 2;
    final dy = (rowHeight - (maxY - minY) * scale) / 2;
    return [
      for (final p in slowArc.points)
        Point(dx + (p.x - minX) * scale, dy + (p.y - minY) * scale),
    ];
  }

  FreedrawElement brushElement(BrushType brush, List<Point> absPoints, int i) {
    // 生产不变量：freedraw 的 points 相对元素原点 (x,y)，渲染器/SVG
    // 导出按 points + (x,y) 还原绝对坐标（违反即双重偏移、导出裁剪）。
    final xs = absPoints.map((p) => p.x);
    final ys = absPoints.map((p) => p.y);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    return FreedrawElement(
      id: ElementId('visual-${brush.name}-$i'),
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: [for (final p in absPoints) Point(p.x - minX, p.y - minY)],
      pressures: List<double>.from(slowArc.pressures),
      simulatePressure: false,
      isComplete: true,
      customData: customDataWithFreedrawRender(null, brush),
      strokeWidth: nominalWidth,
    );
  }

  Future<ui.Image> renderMatrix(List<Point> points) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, rowWidth, rowHeight * BrushType.values.length),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    for (var i = 0; i < BrushType.values.length; i++) {
      canvas.save();
      canvas.translate(0, rowHeight * i);
      ElementRenderer.render(
        canvas,
        brushElement(BrushType.values[i], points, i),
        RoughCanvasAdapter(),
      );
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      rowWidth.round(),
      (rowHeight * BrushType.values.length).round(),
    );
    picture.dispose();
    return image;
  }

  test('五笔视觉矩阵：产物生成 + 两两像素差异下限', () async {
    final points = normalizedTrajectory();
    final image = await renderMatrix(points);
    addTearDown(image.dispose);

    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(png, isNotNull);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);

    final outDir = Directory('build/brush_visual_matrix');
    outDir.createSync(recursive: true);
    File(
      '${outDir.path}/matrix.png',
    ).writeAsBytesSync(png!.buffer.asUint8List());

    // 两两差异门禁：五行同轨迹同名义笔宽，任两行着墨像素差占"并集
    // 着墨面积"之比须超过 5%。门禁目标是拦截"退回共用管线"类回归
    //（渲染塌缩为相同时差异归零）；细笔型间颗粒/边缘差异占比天然偏小，
    // 观感区分度由视觉审查另行盲判。
    const w = 900;
    const h = 150;
    bool isInk(int row, int x, int y) {
      final o = ((row * h + y) * w + x) * 4;
      return 255 - rgba!.getUint8(o + 2) > 8; // 蓝通道偏离白底度量着墨
    }

    (int, int) pairDiff(int a, int b) {
      var differing = 0;
      var union = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final da = isInk(a, x, y);
          final db = isInk(b, x, y);
          if (da != db) differing++;
          if (da || db) union++;
        }
      }
      return (differing, union);
    }

    final brushes = BrushType.values;
    for (var a = 0; a < brushes.length; a++) {
      var inkCount = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x += 3) {
          if (isInk(a, x, y)) inkCount++;
        }
      }
      expect(
        inkCount,
        greaterThan(200),
        reason: '${brushes[a].name} 行应着墨（实测 $inkCount 采样点）',
      );
      for (var b = a + 1; b < brushes.length; b++) {
        final (differing, union) = pairDiff(a, b);
        final ratio = differing / union;
        expect(
          ratio,
          greaterThan(0.05),
          reason:
              '${brushes[a].name} vs ${brushes[b].name} 着墨差异占并集 '
              '${(ratio * 100).toStringAsFixed(1)}%（$differing/$union）应 > 5%',
        );
      }
    }
  });

  test('五笔 SVG 产物：同一场景经 exportSvg 导出', () async {
    final points = normalizedTrajectory();
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    // SVG 无画布 translate 可用：直接按行偏移点位，避免五元素叠加
    for (var i = 0; i < BrushType.values.length; i++) {
      controller.applyResult(
        AddElementResult(
          brushElement(BrushType.values[i], [
            for (final p in points) Point(p.x, p.y + rowHeight * i),
          ], i),
        ),
      );
    }
    final svg = controller.exportSvg(selectedOnly: false);
    expect(svg, isNotNull);
    expect(svg, contains('mix-blend-mode:darken'));
    expect(svg, contains('pencil-grain-'));

    final outDir = Directory('build/brush_visual_matrix');
    outDir.createSync(recursive: true);
    File('${outDir.path}/matrix.svg').writeAsStringSync(svg);
  });
}
