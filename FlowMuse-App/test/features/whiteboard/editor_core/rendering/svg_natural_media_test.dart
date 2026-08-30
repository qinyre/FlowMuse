import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/export/svg_element_renderer.dart';

// ---------------------------------------------------------------------------
// T9：SVG 与文本格式保真（计划任务卡）：v2 元素消费共享 plan 输出真实
// <path>（铅笔 ≤4 / 毛笔 ≤2）、16k 点字节预算与线性耗时、确定性。
// markdraw/Excalidraw 往返契约在 brush_render_version_contract_test
//（T1/T2）锁定，此处不重复。
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String renderSvg(FreedrawElement element) {
    final buf = StringBuffer()
      ..write(
        '<svg xmlns="http://www.w3.org/2000/svg" width="900" '
        'height="150" viewBox="0 0 900 150">',
      );
    buf.write(SvgElementRenderer.render(element));
    buf.write('</svg>');
    return buf.toString();
  }

  int pathNodeCount(String svg) => RegExp(r'<path[\s>]').allMatches(svg).length;

  FreedrawElement v2Element(
    BrushType brush,
    List<Point> points,
    List<double> pressures,
  ) => FreedrawElement(
    id: ElementId('svg-v2'),
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    points: points,
    pressures: pressures,
    simulatePressure: false,
    isComplete: true,
    strokeColor: '#000000',
    customData: customDataWithFreedrawRender(
      null,
      brush,
      renderVersion: BrushRenderVersion.naturalMediaV2,
    ),
    strokeWidth: 6,
  );

  List<Point> wave(int n) => [
    for (var i = 0; i < n; i++) Point(i * 3.0, 60 + 20 * math.sin(i / 9.0)),
  ];
  List<double> prs(int n) => [
    for (var i = 0; i < n; i++)
      (0.35 + 0.3 * math.sin(i / 11.0)).clamp(0.05, 1.0),
  ];

  test('T9-a v2 path 节点数：铅笔 ≤4（基底+密度桶）、毛笔 ≤2（包络+毫丝）', () {
    final pencilSvg = renderSvg(
      v2Element(BrushType.pencil, wave(200), prs(200)),
    );
    final brushSvg = renderSvg(
      v2Element(BrushType.brushPen, wave(200), prs(200)),
    );
    expect(
      pathNodeCount(pencilSvg),
      lessThanOrEqualTo(4),
      reason: '铅笔 v2 主要 path 应 ≤4，实测 ${pathNodeCount(pencilSvg)}',
    );
    expect(
      pathNodeCount(brushSvg),
      lessThanOrEqualTo(2),
      reason: '毛笔 v2 主要 path 应 ≤2，实测 ${pathNodeCount(brushSvg)}',
    );
    // v1 元素（classicV1）不受影响：outline + pattern 覆盖层 = 2 path。
    final v1Svg = renderSvg(
      v2Element(BrushType.pencil, wave(50), prs(50)).copyWith(
        customData: customDataWithFreedrawRender(
          null,
          BrushType.pencil,
          renderVersion: BrushRenderVersion.classicV1,
        ),
      ),
    );
    expect(pathNodeCount(v1Svg), 2, reason: 'v1 铅笔 SVG 结构不变');
  });

  test('T9-b 16k 点字节预算：铅笔 ≤512KiB、毛笔 ≤256KiB，生成线性', () {
    final outDir = Directory('build/natural_media_baseline/svg_v2');
    outDir.createSync(recursive: true);
    final timings = <int, double>{};
    for (final n in [2048, 8192, 16384]) {
      final points = wave(n);
      final pressures = prs(n);
      final sw = Stopwatch()..start();
      final pencilSvg = renderSvg(
        v2Element(BrushType.pencil, points, pressures),
      );
      final brushSvg = renderSvg(
        v2Element(BrushType.brushPen, points, pressures),
      );
      sw.stop();
      timings[n] = sw.elapsedMicroseconds / 1000;
      if (n == 16384) {
        File('${outDir.path}/pencil_16k.svg').writeAsStringSync(pencilSvg);
        File('${outDir.path}/brush_16k.svg').writeAsStringSync(brushSvg);
        final pencilKiB = pencilSvg.length / 1024;
        final brushKiB = brushSvg.length / 1024;
        expect(
          pencilKiB,
          lessThanOrEqualTo(512),
          reason: '16k 点铅笔 SVG ${pencilKiB.toStringAsFixed(0)}KiB 应 ≤512KiB',
        );
        expect(
          brushKiB,
          lessThanOrEqualTo(256),
          reason: '16k 点毛笔 SVG ${brushKiB.toStringAsFixed(0)}KiB 应 ≤256KiB',
        );
      }
    }
    // 线性：8 倍点数的耗时应远低于 8×（O(n) 采样 + 上限颗粒）；粗检
    // 16k/2k 比 ≤ 12（允许抖动，超线性即失败）。
    final ratio = timings[16384]! / math.max(timings[2048]!, 0.001);
    expect(ratio, lessThanOrEqualTo(12), reason: '16k/2k 生成耗时比 $ratio 应保持线性量级');
  });

  test('T9-c SVG 确定性：同元素两次导出逐字节一致', () {
    final a = renderSvg(v2Element(BrushType.brushPen, wave(120), prs(120)));
    final b = renderSvg(v2Element(BrushType.brushPen, wave(120), prs(120)));
    expect(a, equals(b));
    final c = renderSvg(v2Element(BrushType.pencil, wave(120), prs(120)));
    final d = renderSvg(v2Element(BrushType.pencil, wave(120), prs(120)));
    expect(c, equals(d));
  });

  test('T9-d 探针导出（Chromium 视觉验收素材）', () {
    final outDir = Directory('build/natural_media_baseline/svg_v2');
    outDir.createSync(recursive: true);
    List<Point> line(int n) => [
      for (var i = 0; i < n; i++) Point(60 + 9.0 * i, 75),
    ];
    for (final (name, brush, p) in [
      ('lightPencil', BrushType.pencil, 0.2),
      ('heavyPencil', BrushType.pencil, 0.8),
      ('lightBrush', BrushType.brushPen, 0.2),
      ('heavyBrush', BrushType.brushPen, 0.8),
    ]) {
      final svg = renderSvg(
        v2Element(brush, line(41), List<double>.filled(41, p)),
      );
      File('${outDir.path}/probe_$name.svg').writeAsStringSync(svg);
    }
  });
}
