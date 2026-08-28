import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/brush_stroke_fixtures.dart';
import 'rendering/brush_path_metrics.dart';

void main() {
  const points = [Point(0, 0), Point(4, 3), Point(8, 2), Point(12, 6)];

  test('builds a finite outline from real pressure samples', () {
    final outline = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
    );

    expect(outline, isNotEmpty);
    expect(
      outline.every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
  });

  test('falls back to simulated pressure when samples are misaligned', () {
    final outline = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.5],
    );

    expect(outline, isNotEmpty);
  });

  // 缺陷复现证据（T2 修复后本用例反转为"轮廓不变"）：全局
  // pressureSensitivity 参与渲染会让切换灵敏度改写历史笔迹。
  test('pressure sensitivity changes the generated outline', () {
    final low = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
      pressureSensitivity: 0,
    );
    final high = FreedrawRenderer.buildOutline(
      points,
      strokeWidth: 4,
      pressures: const [0.2, 0.4, 0.7, 1.0],
      pressureSensitivity: 1,
    );

    expect(high, isNot(equals(low)));
  });

  group('T0 基线：五笔 × 五夹具', () {
    for (final brush in BrushType.values) {
      for (final fixture in allBrushStrokeFixtures) {
        test('${brush.name} × ${fixture.name} 生成有限非空轮廓', () {
          final outline = FreedrawRenderer.buildOutline(
            fixture.points,
            strokeWidth: 4,
            pressures: fixture.pressures,
            brushType: brush,
          );
          final metrics = BrushOutlineMetrics.measure(outline);
          expect(outline, isNotEmpty, reason: fixture.name);
          expect(metrics.isFinite, isTrue, reason: fixture.name);
        });

        test('${brush.name} × ${fixture.name} 同输入两次结果逐点一致', () {
          final first = FreedrawRenderer.buildOutline(
            fixture.points,
            strokeWidth: 4,
            pressures: fixture.pressures,
            brushType: brush,
          );
          final second = FreedrawRenderer.buildOutline(
            fixture.points,
            strokeWidth: 4,
            pressures: fixture.pressures,
            brushType: brush,
          );
          expect(
            second.map((o) => '${o.dx},${o.dy}').toList(),
            equals(first.map((o) => '${o.dx},${o.dy}').toList()),
            reason: fixture.name,
          );
        });
      }
    }
  });

  group('T0 缺陷探针（复现证据，后续任务修复后反转）', () {
    test('P1: pencil.frag 注册在 assets 段，shader 运行时不可用（T1 修复）', () async {
      // Given/When: 测试环境加载当前注册方式的 shader 资产
      await PencilShader.init();

      // Then: assets 段只原样拷贝 GLSL 源文本，fromAsset 必然失败并降级
      expect(
        PencilShader.isAvailable,
        isFalse,
        reason: 'pencil.frag 注册在 flutter.assets（未编译），加载必失败',
      );
    });

    test('P4: 单点输入 + taper 笔型生成不可见退化环（T3 修复）', () {
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        final outline = FreedrawRenderer.buildOutline(
          [const Point(50, 50)],
          strokeWidth: 4,
          pressures: const [0.5],
          brushType: brush,
        );
        // 现状：单点返回 5 点退化环（半径钳 0.01），outline 非空导致
        // renderer 的画圆兜底永不触发——点击不可见。
        expect(outline, isNotEmpty, reason: brush.name);
        final metrics = BrushOutlineMetrics.measure(outline);
        expect(
          metrics.bounds.width,
          lessThan(1.0),
          reason: '${brush.name} 单点轮廓应退化为不可见（复现证据）',
        );
        expect(
          metrics.bounds.height,
          lessThan(1.0),
          reason: '${brush.name} 单点轮廓应退化为不可见（复现证据）',
        );
      }
    });

    test('P2: 同一 pressures 用不同全局灵敏度渲染轮廓不同（T2 修复）', () {
      final low = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: pressureRamp.pressures,
        pressureSensitivity: 0.1,
      );
      final high = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: pressureRamp.pressures,
        pressureSensitivity: 0.9,
      );
      final lowMetrics = BrushOutlineMetrics.measure(low);
      final highMetrics = BrushOutlineMetrics.measure(high);
      // 现状证据：bounds 逐边不同（面积差异即轮廓不同）
      final differs =
          (lowMetrics.bounds.left - highMetrics.bounds.left).abs() > 0.01 ||
          (lowMetrics.bounds.top - highMetrics.bounds.top).abs() > 0.01 ||
          lowMetrics.area != highMetrics.area;
      expect(differs, isTrue, reason: '同一历史 pressures 被当前全局灵敏度改写渲染（缺陷）');
    });

    test('基线补充：measureStroke 按 brushType 输出五笔独立指标', () {
      for (final brush in BrushType.values) {
        final metrics = FreedrawRenderer.measureStroke(
          cornerPolyline.points,
          strokeWidth: 4,
          pressures: cornerPolyline.pressures,
          outlineRenderMode: OutlineRenderMode.quadratic,
          brushType: brush,
        );
        expect(metrics.outlinePointCount, greaterThan(0), reason: brush.name);
      }
      // 五笔指标不全等（现状 sizeScale/opacityScale 已有差异，T3 起差异
      // 将显著拉大——此处只冻结"按笔型测量"能力本身）。
      final sizes = {
        for (final brush in BrushType.values)
          brush.name: FreedrawRenderer.measureStroke(
            cornerPolyline.points,
            strokeWidth: 4,
            pressures: cornerPolyline.pressures,
            outlineRenderMode: OutlineRenderMode.polygon,
            brushType: brush,
          ).outlinePointCount,
      };
      expect(sizes.values.toSet().length, greaterThan(1));
    });
  });
}
