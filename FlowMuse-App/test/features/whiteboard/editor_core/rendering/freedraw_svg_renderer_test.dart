import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/export/svg_element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/export/svg_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/brush_stroke_fixtures.dart';

/// 自由笔画 SVG 导出：真实轮廓与笔刷语义（Issue #5 T7 / A11–A13）。
///
/// 说明：XML 语法合法性由 T9 的 Web 端验收以真实浏览器打开导出 SVG
/// 复核（Chrome 解析即证据）；本文件做结构/语义断言与 id 唯一性检查。
void main() {
  FreedrawElement strokeOf(
    BrushType brush, {
    List<double>? pressures,
    double strokeWidth = 4,
    String id = 'stroke-1',
    Map<String, Object?>? customData,
  }) => FreedrawElement(
    id: ElementId(id),
    x: 10,
    y: 10,
    width: 100,
    height: 4,
    points: pressureRamp.points
        .map((p) => Point(p.x * 0.4, p.y))
        .toList(growable: false),
    pressures: pressures ?? pressureRamp.pressures,
    simulatePressure: false,
    isComplete: true,
    customData: customDataWithFreedrawRender(customData, brush),
    strokeColor: brush == BrushType.highlighter ? '#ffff00' : '#1e1e1e',
    strokeWidth: strokeWidth,
  );

  test('A11: 五种笔刷输出填充轮廓 path，不再导出等宽中心线', () {
    for (final brush in BrushType.values) {
      final svg = SvgElementRenderer.render(strokeOf(brush));
      expect(svg, contains('fill='), reason: '${brush.name} 填充语义');
      expect(svg, contains('d="M'), reason: '${brush.name} 真实轮廓 path');
      // 旧中心线表达的标志属性必须消失
      expect(
        svg,
        isNot(contains('stroke-linecap')),
        reason: '${brush.name} 不得再走中心线 stroke',
      );
      expect(
        svg,
        isNot(contains('stroke-width')),
        reason: '${brush.name} 无第二套宽度',
      );
    }
  });

  test('A1: 圆珠笔不同压力的 SVG 输出一致（恒宽）', () {
    final low = SvgElementRenderer.render(
      strokeOf(BrushType.ballpoint, pressures: List.filled(16, 0.15)),
    );
    final high = SvgElementRenderer.render(
      strokeOf(BrushType.ballpoint, pressures: List.filled(16, 0.95)),
    );
    expect(low, equals(high));
  });

  test('A12: 毛笔/钢笔压力差异在 SVG 保留（d 随压力变化）', () {
    for (final brush in [BrushType.fountainPen, BrushType.brushPen]) {
      final low = SvgElementRenderer.render(
        strokeOf(brush, pressures: List.filled(16, 0.15)),
      );
      final high = SvgElementRenderer.render(
        strokeOf(brush, pressures: List.filled(16, 0.95)),
      );
      expect(high, isNot(equals(low)), reason: '${brush.name} 的 SVG 轮廓应保留压力差异');
    }
    // 收锋语义来自与画布共用的 buildOutline（taper 已在 brush_geometry_test
    // 的 A4 覆盖），此处锁定毛笔与钢笔同输入输出不同（粗细/收锋差异）。
    final brushSvg = SvgElementRenderer.render(strokeOf(BrushType.brushPen));
    final fountainSvg = SvgElementRenderer.render(
      strokeOf(BrushType.fountainPen),
    );
    expect(brushSvg, isNot(equals(fountainSvg)));
  });

  test('A13: 荧光笔包含 darken 混合声明与正确 opacity', () {
    final svg = SvgElementRenderer.render(
      strokeOf(BrushType.highlighter, strokeWidth: 20),
    );
    expect(svg, contains('mix-blend-mode:darken'));
    expect(svg, contains('opacity="0.3"'), reason: '0.30 opacityScale');
    expect(svg, contains('fill="#ffff00"'));
  });

  test('铅笔：稳定且唯一的 pattern 引用 + 重复导出文本稳定', () {
    final a = SvgElementRenderer.render(
      strokeOf(BrushType.pencil, id: 'pencil-a'),
    );
    final aAgain = SvgElementRenderer.render(
      strokeOf(BrushType.pencil, id: 'pencil-a'),
    );
    final b = SvgElementRenderer.render(
      strokeOf(BrushType.pencil, id: 'pencil-b'),
    );
    expect(a, equals(aAgain), reason: '重复导出文本稳定');
    expect(a, contains('id="pencil-grain-pencil-a"'));
    expect(a, contains('url(#pencil-grain-pencil-a)'));
    expect(b, contains('id="pencil-grain-pencil-b"'), reason: '文档内唯一');
    // pattern 是轻量小 tile（不随点数线性膨胀）
    expect(a.length, lessThan(20000));
  });

  test('单点与空点的显式输出规则', () {
    final dot = SvgElementRenderer.render(
      FreedrawElement(
        id: const ElementId('dot-1'),
        x: 5,
        y: 5,
        width: 1,
        height: 1,
        points: const [Point(0, 0)],
        pressures: const [0.5],
        simulatePressure: false,
        isComplete: true,
        customData: customDataWithFreedrawRender(null, BrushType.fountainPen),
        strokeWidth: 4,
      ),
    );
    expect(dot, contains('<circle'));
    expect(dot, contains('cx="5"'));

    final empty = SvgElementRenderer.render(
      FreedrawElement(
        id: const ElementId('empty-1'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        points: const [],
        pressures: const [],
        simulatePressure: true,
        isComplete: true,
        customData: customDataWithFreedrawRender(null, BrushType.fountainPen),
      ),
    );
    expect(empty, isEmpty);
  });

  test('整文档导出：freedraw 轮廓存在且 pattern id 无重复', () {
    final scene = Scene()
        .addElement(strokeOf(BrushType.pencil, id: 'p-a'))
        .addElement(strokeOf(BrushType.pencil, id: 'p-b'))
        .addElement(strokeOf(BrushType.highlighter, id: 'hl-1'))
        .addElement(strokeOf(BrushType.brushPen, id: 'brush-1'));
    final svg = SvgExporter.export(scene, embedMarkdraw: false);

    expect(svg, contains('mix-blend-mode:darken'));
    final ids = RegExp(
      'pencil-grain-([a-z0-9-]+)',
    ).allMatches(svg).map((m) => m.group(1)!).toList();
    final distinct = ids.toSet();
    // 每个 id 恰出现两次（defs 定义 + url 引用），无跨元素重复定义
    for (final suffix in distinct) {
      final count = RegExp('pencil-grain-$suffix').allMatches(svg).length;
      expect(count, 2, reason: 'id pencil-grain-$suffix 应恰一次定义+一次引用');
    }
    expect(distinct.length, 2);
  });

  test('旧元素（无 pressureEncoding 标记）按出厂默认灵敏度导出', () {
    final legacyBase = strokeOf(
      BrushType.brushPen,
      customData: const {
        'flowMuse': {'brushType': 'brush-pen'},
      },
    );
    // 旧元素：customData 只有 brushType（无 marker），用 copyWith 重建
    final legacy = legacyBase.copyWith(
      customData: customDataWithBrushType(null, BrushType.brushPen),
    );
    expect(pressureEncodingFromCustomData(legacy.customData), isFalse);
    final legacySvg = SvgElementRenderer.render(legacy);
    final legacyAgain = SvgElementRenderer.render(legacy);
    expect(legacySvg, equals(legacyAgain), reason: '旧元素导出确定性');
    // 与新元素（编码渲染）不同——语义不同但都确定
    final encoded = SvgElementRenderer.render(
      strokeOf(BrushType.brushPen, pressures: pressureRamp.pressures),
    );
    expect(legacySvg, isNot(equals(encoded)));
  });
}
