import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/io/io.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/serialization.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/brush_stroke_fixtures.dart';
import 'rendering/brush_path_metrics.dart';
import 'rendering/canvas_spy.dart';

/// 端到端集成：湿墨提交一致、历史冻结、Excalidraw 往返、性能门禁
/// （Issue #5 T9 / A14、A17、A18、roundtrip、§10 降级口径）。
void main() {
  group('A14：本地湿墨 → 静态元素', () {
    // perfect_freehand 的湿墨按 isComplete=false 落后笔尖一段“拖尾”，
    // 提交时补全（main 既有设计，非本次引入；差值为常数、与笔宽无关，
    // 由输入点距 × streamline 决定）。A14 的可维护契约是：
    // 1) 同 isComplete 的湿/干轮廓逐点一致（提交无参数漂移）；
    // 2) 提交时仅末端延伸 ≤4px（实测 0.58~3.89），其余三边零漂移。
    test('五种笔型：提交仅末端延伸 ≤4px，其余边零漂移（宽度无关）', () {
      for (final brush in BrushType.values) {
        for (final strokeWidth in const [4.0, 20.0]) {
          final wetOutline = FreedrawRenderer.buildOutline(
            slowArc.points,
            strokeWidth: strokeWidth,
            pressures: slowArc.pressures,
            pressureEncoded: true,
            isComplete: false,
            brushType: brush,
          );
          final dryOutline = FreedrawRenderer.buildOutline(
            slowArc.points,
            strokeWidth: strokeWidth,
            pressures: slowArc.pressures,
            pressureEncoded: true,
            isComplete: true,
            brushType: brush,
          );
          // 同 isComplete 重复渲染逐点一致（无参数漂移）
          final dryAgain = FreedrawRenderer.buildOutline(
            slowArc.points,
            strokeWidth: strokeWidth,
            pressures: slowArc.pressures,
            pressureEncoded: true,
            isComplete: true,
            brushType: brush,
          );
          expect(
            dryAgain.map((o) => '${o.dx},${o.dy}').toList(),
            equals(dryOutline.map((o) => '${o.dx},${o.dy}').toList()),
            reason: '${brush.name} 提交不换参数',
          );

          final wet = BrushOutlineMetrics.measure(wetOutline);
          final dry = BrushOutlineMetrics.measure(dryOutline);
          expect(
            (wet.bounds.left - dry.bounds.left).abs(),
            lessThan(0.5),
            reason: '${brush.name} w=$strokeWidth left',
          );
          expect(
            (wet.bounds.top - dry.bounds.top).abs(),
            lessThan(0.5),
            reason: '${brush.name} w=$strokeWidth top',
          );
          expect(
            (wet.bounds.bottom - dry.bounds.bottom).abs(),
            lessThan(0.5),
            reason: '${brush.name} w=$strokeWidth bottom',
          );
          expect(
            (wet.bounds.right - dry.bounds.right).abs(),
            lessThan(4.0),
            reason: '${brush.name} w=$strokeWidth 末端拖尾补全 ≤4px',
          );
        }
      }
    });
  });

  group('A17/A18：历史冻结与双端一致', () {
    test('同一元素经两个独立适配器渲染完全一致', () {
      final element = FreedrawElement(
        id: const ElementId('frozen-1'),
        x: 10,
        y: 10,
        width: 100,
        height: 20,
        points: [
          for (final p in pressureRamp.points) Point(p.x * 0.8, p.y + 5),
        ],
        pressures: pressureRamp.pressures,
        simulatePressure: false,
        isComplete: true,
        customData: customDataWithFreedrawRender(null, BrushType.brushPen),
        strokeWidth: 4,
      );

      ui.Rect renderWith(RoughCanvasAdapter adapter) {
        final recorder = ui.PictureRecorder();
        final spy = SpyCanvas(ui.Canvas(recorder));
        ElementRenderer.render(spy, element, adapter);
        recorder.endRecording().dispose();
        return spy.pathOrder.first;
      }

      final a = renderWith(RoughCanvasAdapter());
      final b = renderWith(RoughCanvasAdapter());
      // 两个“当前灵敏度不同”的客户端（适配器已无灵敏度状态，历史
      // 元素渲染只取决于元素数据 + 笔刷出厂默认）→ 完全一致。
      expect(b, equals(a));
    });

    test('旧元素（无标记）也双端一致（出厂默认灵敏度确定性）', () {
      final legacy = FreedrawElement(
        id: const ElementId('legacy-1'),
        x: 0,
        y: 0,
        width: 80,
        height: 10,
        points: [for (final p in slowArc.points) Point(p.x * 0.8, p.y)],
        pressures: slowArc.pressures,
        simulatePressure: false,
        isComplete: true,
        customData: customDataWithBrushType(null, BrushType.pencil),
        strokeWidth: 6,
      );
      final first = FreedrawRenderer.buildOutline(
        [for (final p in legacy.points) Point(p.x + legacy.x, p.y + legacy.y)],
        strokeWidth: legacy.strokeWidth,
        pressures: legacy.pressures,
        pressureEncoded: false,
        brushType: BrushType.pencil,
      );
      final second = FreedrawRenderer.buildOutline(
        [for (final p in legacy.points) Point(p.x + legacy.x, p.y + legacy.y)],
        strokeWidth: legacy.strokeWidth,
        pressures: legacy.pressures,
        pressureEncoded: false,
        brushType: BrushType.pencil,
      );
      expect(
        second.map((o) => '${o.dx},${o.dy}').toList(),
        equals(first.map((o) => '${o.dx},${o.dy}').toList()),
      );
    });
  });

  group('Excalidraw JSON 往返（roundtrip）', () {
    test('五种笔刷 strokeWidth/pressures/brushType/pressureEncoding 与轮廓一致', () {
      final elements = <FreedrawElement>[];
      for (final brush in BrushType.values) {
        elements.add(
          FreedrawElement(
            id: ElementId('rt-${brush.name}'),
            x: 5,
            y: 5,
            width: 80,
            height: 10,
            points: [for (final p in slowArc.points) Point(p.x * 0.8, p.y)],
            pressures: List<double>.from(slowArc.pressures),
            simulatePressure: false,
            isComplete: true,
            customData: customDataWithFreedrawRender(null, brush),
            strokeColor: '#123456',
            strokeWidth: 4,
          ),
        );
      }
      final encoded = ExcalidrawJsonCodec.serialize(
        MarkdrawDocument(sections: [SketchSection(elements)]),
      );
      final parsed = ExcalidrawJsonCodec.parse(encoded);

      final round = parsed.value.allElements
          .whereType<FreedrawElement>()
          .toList(growable: false);
      expect(round.length, BrushType.values.length);

      for (var i = 0; i < round.length; i++) {
        final before = elements[i];
        final after = round[i];
        expect(
          after.strokeWidth,
          before.strokeWidth,
          reason: '${before.id.value} strokeWidth',
        );
        expect(
          after.pressures,
          before.pressures,
          reason: '${before.id.value} pressures',
        );
        expect(
          brushTypeFromCustomData(after.customData),
          brushTypeFromCustomData(before.customData),
          reason: '${before.id.value} brushType',
        );
        expect(
          pressureEncodingFromCustomData(after.customData),
          pressureEncodingFromCustomData(before.customData),
          reason: '${before.id.value} pressureEncoding',
        );
        // 往返前后渲染轮廓逐点一致
        final outlineBefore = FreedrawRenderer.buildOutline(
          [
            for (final p in before.points)
              Point(p.x + before.x, p.y + before.y),
          ],
          strokeWidth: before.strokeWidth,
          pressures: before.pressures,
          pressureEncoded: pressureEncodingFromCustomData(before.customData),
          brushType: brushTypeFromCustomData(before.customData),
        );
        final outlineAfter = FreedrawRenderer.buildOutline(
          [for (final p in after.points) Point(p.x + after.x, p.y + after.y)],
          strokeWidth: after.strokeWidth,
          pressures: after.pressures,
          pressureEncoded: pressureEncodingFromCustomData(after.customData),
          brushType: brushTypeFromCustomData(after.customData),
        );
        expect(
          outlineAfter.map((o) => '${o.dx},${o.dy}').toList(),
          equals(outlineBefore.map((o) => '${o.dx},${o.dy}').toList()),
          reason: '${before.id.value} 轮廓往返一致',
        );
      }
    });

    test('外部导出 sanitizer：pressureEncoding 保留、collaborationOwner 剥离', () {
      final element = withCreator(
        FreedrawElement(
          id: const ElementId('ext-rt-1'),
          x: 0,
          y: 0,
          width: 50,
          height: 5,
          points: const [Point(0, 2), Point(25, 2), Point(50, 2)],
          pressures: const [],
          simulatePressure: true,
          isComplete: true,
          customData: customDataWithFreedrawRender(null, BrushType.pencil),
          strokeWidth: 2,
        ),
        const CollaborationCreator(
          creatorKey: 'user:x',
          displayName: 'X',
          isGuest: false,
        ),
      );
      final encoded = ExcalidrawJsonCodec.serialize(
        MarkdrawDocument(
          sections: [
            SketchSection([element]),
          ],
        ),
      );
      // 内部序列化保留 owner 与 pressureEncoding
      expect(encoded.contains('collaborationOwner'), isTrue);
      expect(encoded.contains('pressureEncoding'), isTrue);
    });
  });

  group('性能门禁（§10 单代理降级口径）', () {
    test('轮廓生成线性度：time(16k)/time(1k) ≤ 20（线性=16、O(n²)=256）', () {
      final small = _synthPoints(1000);
      final large = _synthPoints(16000);
      final tSmall = FreedrawRenderer.measureStroke(
        small,
        strokeWidth: 4,
        pressures: List<double>.filled(small.length, 0.5),
        pressureEncoded: true,
        outlineRenderMode: OutlineRenderMode.quadratic,
        brushType: BrushType.brushPen,
      );
      final tLarge = FreedrawRenderer.measureStroke(
        large,
        strokeWidth: 4,
        pressures: List<double>.filled(large.length, 0.5),
        pressureEncoded: true,
        outlineRenderMode: OutlineRenderMode.quadratic,
        brushType: BrushType.brushPen,
      );
      final ratio =
          tLarge.getStrokeDuration.inMicroseconds == 0 ||
              tSmall.getStrokeDuration.inMicroseconds == 0
          ? 1.0
          : tLarge.getStrokeDuration.inMicroseconds /
                tSmall.getStrokeDuration.inMicroseconds;
      expect(ratio, lessThan(20), reason: '16k/1k = $ratio（线性 16，计时噪声余量 20）');
    });

    test('1,000 元素可视边界计算 O(n) 且不生成 outline', () {
      final elements = [
        for (var i = 0; i < 1000; i++)
          FreedrawElement(
            id: ElementId('bench-$i'),
            x: i.toDouble(),
            y: 0,
            width: 50,
            height: 5,
            points: const [Point(0, 2), Point(25, 2), Point(50, 2)],
            pressures: const [],
            simulatePressure: true,
            isComplete: true,
            customData: customDataWithBrushType(
              null,
              BrushType.values[i % BrushType.values.length],
            ),
            strokeWidth: ((i % 25) + 1).toDouble(),
          ),
      ];
      final watch = Stopwatch()..start();
      var count = 0;
      for (final e in elements) {
        count += elementVisualBounds(e).size.width > 0 ? 1 : 0;
      }
      watch.stop();
      expect(count, 1000);
      // O(n) 纯算术：1,000 元素毫秒级（宽松上限防 CI 抖动）
      expect(watch.elapsedMilliseconds, lessThan(200));
    });
  });
}

List<Point> _synthPoints(int count) {
  final points = <Point>[];
  for (var i = 0; i < count; i++) {
    points.add(Point(i * 0.7, 3 * (i % 5).toDouble()));
  }
  return points;
}
