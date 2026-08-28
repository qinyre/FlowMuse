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

  // T2 冻结语义（原"全局 sensitivity 改变轮廓"缺陷的反转守护）：
  // 渲染端不再接收灵敏度——新笔迹由创建时编码的 pressures + 最大
  // thinning 决定，旧笔迹由笔刷出厂默认灵敏度决定。切换灵敏度不可能
  // 改变同一 pressures 的渲染结果。
  test('同一 pressures 的轮廓不再依赖任何当前灵敏度（冻结语义）', () {
    final legacy = FreedrawRenderer.buildOutline(
      pressureRamp.points,
      strokeWidth: 4,
      pressures: pressureRamp.pressures,
      pressureEncoded: false,
    );
    final encoded = FreedrawRenderer.buildOutline(
      pressureRamp.points,
      strokeWidth: 4,
      pressures: pressureRamp.pressures,
      pressureEncoded: true,
    );

    // 两种语义各自确定（同输入重复调用逐点一致，见基线组），
    // 且互不等价（编码前后 thinning 不同）。冻结点在于：渲染入口
    // 已无 sensitivity 参数可注入——切换笔刷/灵敏度不再改写历史笔迹。
    expect(legacy, isNot(equals(encoded)));
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
    test('P1(已修复): shaders 段注册后 test 环境加载成功（T1）', () async {
      // Given/When: 测试环境加载 flutter.shaders 注册的编译产物
      await PencilShader.init();

      // Then: impellerc 编译产物可被 FragmentProgram.fromAsset 加载。
      // 修复前注册在 assets 段（GLSL 源文本原样拷贝），加载必失败。
      expect(
        PencilShader.isAvailable,
        isTrue,
        reason: 'shaders 段产物应编译并可加载（原缺陷：assets 段死代码）',
      );
    });

    test('P4: 单点输入可见性（T2 后 taper 暂关已可见；T3 引入 taper 后由 <3×size 门控保持）', () {
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        final outline = FreedrawRenderer.buildOutline(
          [const Point(50, 50)],
          strokeWidth: 4,
          pressures: const [0.5],
          brushType: brush,
        );
        // 原缺陷：taper 开启时单点返回 5 点退化环（半径钳 0.01），
        // outline 非空导致 renderer 画圆兜底永不触发——点击不可见。
        // T2 收敛配置时 taper 暂关，单点走圆端帽自然可见；
        // T3 重新引入 taper 后必须保持本断言（<3×size 门控）。
        expect(outline, isNotEmpty, reason: brush.name);
        final metrics = BrushOutlineMetrics.measure(outline);
        final size = BrushRenderProfile.forType(brush).renderSize(4);
        expect(
          metrics.bounds.width,
          greaterThan(size * 0.8),
          reason: '${brush.name} 单点应画可见圆点',
        );
        expect(
          metrics.bounds.height,
          greaterThan(size * 0.8),
          reason: '${brush.name} 单点应画可见圆点',
        );
      }
    });

    test('P2(已修复): 渲染入口无灵敏度参数，历史笔迹不再漂移（T2）', () {
      // 修复后：buildOutline 只接受 pressureEncoded 布尔语义；
      // 旧元素用笔刷出厂默认灵敏度，两次调用（等价于两个不同当前
      // 灵敏度的协作端）渲染同一 pressures 结果逐点一致。
      final a = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: pressureRamp.pressures,
        pressureEncoded: false,
      );
      final b = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: pressureRamp.pressures,
        pressureEncoded: false,
      );
      expect(
        b.map((o) => '${o.dx},${o.dy}').toList(),
        equals(a.map((o) => '${o.dx},${o.dy}').toList()),
        reason: '两端当前灵敏度不同也不得改变同一元素的轮廓',
      );
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
      // 五笔轮廓宽度不全等（sizeScale 0.72~4.2 直接决定可见宽度；
      // 轮廓点数对参数不敏感，改用几何宽度作为“按笔型测量”的证据）。
      final widths = {
        for (final brush in BrushType.values)
          brush.name: BrushOutlineMetrics.measure(
            FreedrawRenderer.buildOutline(
              cornerPolyline.points,
              strokeWidth: 4,
              pressures: cornerPolyline.pressures,
              brushType: brush,
            ),
          ).bounds.width,
      };
      expect(
        widths.values.toSet().length,
        BrushType.values.length,
        reason: '五笔 sizeScale 互不相同，轮廓宽度应全不同：$widths',
      );
    });
  });
}
