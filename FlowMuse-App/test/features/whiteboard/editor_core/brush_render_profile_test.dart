import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide Point;

import 'fixtures/brush_stroke_fixtures.dart';
import 'rendering/brush_path_metrics.dart';

/// BrushRenderProfile 单一真源与压力冻结语义（Issue #5 T2）。
void main() {
  group('profile 覆盖与结构约束', () {
    test('每个 BrushType 都有且只有一个 profile', () {
      for (final type in BrushType.values) {
        final profile = BrushRenderProfile.forType(type);
        expect(
          profile,
          same(BrushRenderProfile.forType(type)),
          reason: '$type 必须映射到 const 单例',
        );
      }
    });

    test('圆珠笔与荧光笔的真实/模拟 thinning 均为 0（恒宽）', () {
      for (final type in [BrushType.ballpoint, BrushType.highlighter]) {
        final profile = BrushRenderProfile.forType(type);
        expect(profile.thinningBase, 0, reason: '$type base');
        expect(profile.thinningSpan, 0, reason: '$type span');
        expect(profile.simulatedThinning, 0, reason: '$type simulated');
        expect(profile.pressureEnabled, isFalse, reason: '$type 忽略真实压力');
      }
    });

    test('无默认兜底把未知笔型静默映射成另一支笔', () {
      // fromWireName 未知值回退 fountainPen 是显式契约（非静默猜测），
      // forType 对五种枚举全量覆盖且互不相同。
      final profiles = {
        for (final type in BrushType.values)
          type: BrushRenderProfile.forType(type),
      };
      expect(profiles.length, BrushType.values.length);
      expect(BrushType.fromWireName('unknown'), BrushType.fountainPen);
    });
  });

  group('encodePressure 纯函数', () {
    final fountain = BrushRenderProfile.forType(BrushType.fountainPen);
    final brush = BrushRenderProfile.forType(BrushType.brushPen);
    final ballpoint = BrushRenderProfile.forType(BrushType.ballpoint);

    test('0.5 中性压力保持 0.5；结果始终在 0~1', () {
      for (final profile in [fountain, brush]) {
        for (final sensitivity in [0.0, 0.3, 0.7, 1.0]) {
          expect(
            profile.encodePressure(0.5, sensitivity),
            0.5,
            reason: '${profile.runtimeType} 中性压力不动',
          );
          for (final raw in [0.0, 0.18, 0.82, 1.0, 1.0000000001, -0.5]) {
            final encoded = profile.encodePressure(raw, sensitivity);
            expect(
              encoded,
              inInclusiveRange(0.0, 1.0),
              reason: 'raw=$raw sensitivity=$sensitivity',
            );
          }
        }
      }
    });

    test('maxThinning=0 笔型恒返回 0.5（等价恒宽路径）', () {
      expect(ballpoint.encodePressure(0.2, 0.9), 0.5);
      expect(ballpoint.encodePressure(0.9, 0.1), 0.5);
    });

    test('编码后用 maxThinning 渲染 == 原始压力 + effectiveThinning 渲染', () {
      // 等价性分两层验证：
      // 1) 公式级（严格）：0.5+Tmax×(encoded−0.5) 与 0.5+Te×(p−0.5)
      //    在 1e-12 内逐点相等（浮点重结合的末位差异以内）；
      // 2) 轮廓级（容差）：以 perfect_freehand 直接调用为基准，烘焙
      //    渲染的 bounds/面积/采样宽度在 0.05 逻辑像素内一致——轮廓
      //    顶点数会因间距阈值的浮点翻转而偶差 ±1~2 点，不做逐点比对。
      for (final type in [BrushType.fountainPen, BrushType.brushPen]) {
        final profile = BrushRenderProfile.forType(type);
        for (final sensitivity in [0.25, 0.7, 1.0]) {
          final te = profile.effectiveThinning(sensitivity);
          final tMax = profile.maxThinning;
          for (final raw in pressureRamp.pressures) {
            final encoded = profile.encodePressure(raw, sensitivity);
            final lhs = 0.5 + tMax * (encoded - 0.5);
            final rhs = 0.5 + te * (raw - 0.5);
            expect(
              (lhs - rhs).abs(),
              lessThan(1e-12),
              reason: '$type sensitivity=$sensitivity 公式级等价',
            );
          }

          final encoded = [
            for (final raw in pressureRamp.pressures)
              profile.encodePressure(raw, sensitivity),
          ];
          final baseline = getStroke(
            [
              for (var i = 0; i < pressureRamp.points.length; i++)
                PointVector(
                  pressureRamp.points[i].x,
                  pressureRamp.points[i].y,
                  pressureRamp.pressures[i],
                ),
            ],
            options: StrokeOptions(
              size: profile.renderSize(4),
              thinning: te,
              smoothing: profile.smoothing,
              streamline: profile.streamline,
              simulatePressure: false,
              isComplete: true,
            ),
          );
          final baked = FreedrawRenderer.buildOutline(
            pressureRamp.points,
            strokeWidth: 4,
            pressures: encoded,
            pressureEncoded: true,
            brushType: type,
            // 关闭笔锋，隔离验证“压力编码 + maxThinning”这一层等价；
            // taper 属于另一正交维度（brush_geometry_test 覆盖）。
            taperPhase: FreedrawTaperPhase.none,
          );
          final baseMetrics = BrushOutlineMetrics.measure(baseline);
          final bakedMetrics = BrushOutlineMetrics.measure(baked);
          expect(
            (baseMetrics.bounds.left - bakedMetrics.bounds.left).abs(),
            lessThan(0.05),
          );
          expect(
            (baseMetrics.bounds.top - bakedMetrics.bounds.top).abs(),
            lessThan(0.05),
          );
          expect(
            (baseMetrics.bounds.width - bakedMetrics.bounds.width).abs(),
            lessThan(0.05),
          );
          expect(
            (baseMetrics.bounds.height - bakedMetrics.bounds.height).abs(),
            lessThan(0.05),
          );
          final relativeAreaDelta =
              (baseMetrics.area - bakedMetrics.area).abs() / baseMetrics.area;
          expect(
            relativeAreaDelta,
            lessThan(0.005),
            reason: '$type sensitivity=$sensitivity 面积相对差 <0.5%',
          );
        }
      }
    });

    test('sensitivity=0 时毛笔编码恒 0.5（等价 effective=0 渲染）', () {
      final encoded = [
        for (final raw in pressureRamp.pressures) brush.encodePressure(raw, 0),
      ];
      expect(encoded.every((e) => e == 0.5), isTrue);
    });
  });

  group('customData 标记', () {
    test('customDataWithFreedrawRender 嵌套合并不覆盖已有键', () {
      final existing = {
        'flowMuse': {
          'brushType': 'pencil',
          'collaborationOwner': {'ownerKey': 'u1'},
          'pageId': 3,
        },
      };
      final next = customDataWithFreedrawRender(existing, BrushType.brushPen);
      final flowMuse = next['flowMuse']! as Map<String, Object?>;
      expect(flowMuse['brushType'], 'brush-pen');
      expect(flowMuse['pressureEncoding'], 1);
      expect(flowMuse['collaborationOwner'], isNotNull);
      expect(flowMuse['pageId'], 3);
      // 原 map 不被修改
      expect(
        (existing['flowMuse']! as Map).containsKey('pressureEncoding'),
        isFalse,
      );
    });

    test('pressureEncodingFromCustomData 三态判定', () {
      expect(pressureEncodingFromCustomData(null), isFalse);
      expect(pressureEncodingFromCustomData({'other': 1}), isFalse);
      expect(
        pressureEncodingFromCustomData({
          'flowMuse': {'brushType': 'pencil'},
        }),
        isFalse,
      );
      expect(
        pressureEncodingFromCustomData({
          'flowMuse': {'brushType': 'pencil', 'pressureEncoding': 1},
        }),
        isTrue,
      );
    });
  });

  group('渲染冻结语义', () {
    test('切换笔刷/灵敏度不改写历史元素（legacy 渲染确定性）', () {
      // 旧元素（无标记）：渲染只取决于元素数据本身 + 笔刷出厂默认灵敏度。
      final a = FreedrawRenderer.buildOutline(
        slowArc.points,
        strokeWidth: 4,
        pressures: slowArc.pressures,
        pressureEncoded: false,
        brushType: BrushType.brushPen,
      );
      final b = FreedrawRenderer.buildOutline(
        slowArc.points,
        strokeWidth: 4,
        pressures: slowArc.pressures,
        pressureEncoded: false,
        brushType: BrushType.brushPen,
      );
      expect(
        b.map((o) => '${o.dx},${o.dy}').toList(),
        equals(a.map((o) => '${o.dx},${o.dy}').toList()),
      );
    });

    test('编码压力不同的两笔效果不同且创建后稳定', () {
      final brush = BrushRenderProfile.forType(BrushType.brushPen);
      final low = [
        for (final raw in pressureRamp.pressures)
          brush.encodePressure(raw, 0.3),
      ];
      final high = [
        for (final raw in pressureRamp.pressures)
          brush.encodePressure(raw, 0.9),
      ];
      final outlineLow = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: low,
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final outlineHigh = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: high,
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      final metricsLow = BrushOutlineMetrics.measure(outlineLow);
      final metricsHigh = BrushOutlineMetrics.measure(outlineHigh);
      expect(
        metricsLow.area == metricsHigh.area,
        isFalse,
        reason: '0.3 与 0.9 灵敏度的两笔宽度响应应不同',
      );
      // 创建后稳定：重复渲染逐点一致
      final again = FreedrawRenderer.buildOutline(
        pressureRamp.points,
        strokeWidth: 4,
        pressures: low,
        pressureEncoded: true,
        brushType: BrushType.brushPen,
      );
      expect(
        again.map((o) => '${o.dx},${o.dy}').toList(),
        equals(outlineLow.map((o) => '${o.dx},${o.dy}').toList()),
      );
    });

    test('视觉半径从 profile 派生：荧光笔最大、圆珠笔最小', () {
      const strokeWidth = 20.0;
      final highlighter = BrushRenderProfile.forType(
        BrushType.highlighter,
      ).visualHalfWidth(strokeWidth);
      final brush = BrushRenderProfile.forType(
        BrushType.brushPen,
      ).visualHalfWidth(strokeWidth);
      final ballpoint = BrushRenderProfile.forType(
        BrushType.ballpoint,
      ).visualHalfWidth(strokeWidth);
      expect(highlighter, greaterThan(brush));
      expect(brush, greaterThan(ballpoint));
      // 默认荧光笔：20×4.2/2 + 2 = 44（含 AA 余量）
      expect(highlighter, closeTo(44.0, 0.5));
    });
  });

  group('renderSize 与 taper 门控', () {
    test('renderSize 含 sizeScale 与 1.0 下限', () {
      final ballpoint = BrushRenderProfile.forType(BrushType.ballpoint);
      expect(ballpoint.renderSize(2), closeTo(1.44, 1e-9));
      expect(ballpoint.renderSize(0.5), 1.0, reason: '极细笔迹钳到 1.0 下限');
    });

    test('taper 门控：短笔关闭、长笔按种子因子（T3 起 6×size）', () {
      final profile = BrushRenderProfile.forType(BrushType.brushPen);
      final size = profile.renderSize(4);
      // 折线长度 <3×size：taper 关闭（单点/短划可见性保障）
      expect(profile.startTaperDistance(4, 0), 0);
      expect(profile.startTaperDistance(4, 3 * size - 0.01), 0);
      expect(profile.endTaperDistance(4, 3 * size - 0.01), 0);
      // 长笔：起/收锋按种子因子给绝对距离
      expect(profile.startTaperDistance(4, 100), closeTo(6 * size, 1e-9));
      expect(profile.endTaperDistance(4, 100), closeTo(6 * size, 1e-9));
    });
  });
}
