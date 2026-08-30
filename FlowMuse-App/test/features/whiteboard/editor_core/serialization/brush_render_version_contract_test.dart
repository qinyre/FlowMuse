import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/document_section.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/markdraw_document.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/sketch_line_parser.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/sketch_line_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// T1：自然介质笔刷版本与格式契约（计划 2026-08-30 §3.1/§3.8/§3.9）。
//
// 覆盖：num 解析语义（VM/dart2js 一致）、非法值/非法组合安全回退、
// 嵌套 flowMuse merge、.markdraw v2 语法往返与未知 render 回退、
// 旧文本/旧语义不补写、LiveInkStyle.renderVersion 混合客户端契约、
// 外部 sanitizer 保留非隐私笔刷字段。
// ---------------------------------------------------------------------------

void main() {
  group('brushRenderVersionFromCustomData：num 解析语义', () {
    Map<String, Object?>? customDataWith(Object? value) => value == null
        ? null
        : {
            'flowMuse': {'brushRenderVersion': value},
          };

    test('合法：1 / 1.0 / 2 / 2.0', () {
      expect(
        brushRenderVersionFromCustomData(customDataWith(1)),
        BrushRenderVersion.classicV1,
      );
      expect(
        brushRenderVersionFromCustomData(customDataWith(1.0)),
        BrushRenderVersion.classicV1,
      );
      expect(
        brushRenderVersionFromCustomData(customDataWith(2)),
        BrushRenderVersion.naturalMediaV2,
      );
      expect(
        brushRenderVersionFromCustomData(customDataWith(2.0)),
        BrushRenderVersion.naturalMediaV2,
      );
    });

    test('非法与缺失：字符串/bool/null/NaN/Infinity/未知数值 → v1', () {
      for (final bad in ['2', '1', true, false, 0, 3, -1, 1.5]) {
        expect(
          brushRenderVersionFromCustomData(customDataWith(bad)),
          BrushRenderVersion.classicV1,
          reason: '$bad 应回退 v1',
        );
      }
      expect(
        brushRenderVersionFromCustomData(customDataWith(double.nan)),
        BrushRenderVersion.classicV1,
      );
      expect(
        brushRenderVersionFromCustomData(customDataWith(double.infinity)),
        BrushRenderVersion.classicV1,
      );
      expect(
        brushRenderVersionFromCustomData(null),
        BrushRenderVersion.classicV1,
        reason: '缺失 = v1',
      );
      expect(
        brushRenderVersionFromCustomData(const {
          'flowMuse': {'brushType': 'pencil'},
        }),
        BrushRenderVersion.classicV1,
      );
    });
  });

  group('effectiveBrushRenderVersion：非法组合回退', () {
    Map<String, Object?> v2Of(String brush) => {
          'flowMuse': {'brushType': brush, 'brushRenderVersion': 2},
        };

    test('v2 仅对 pencil/brushPen 生效', () {
      expect(
        effectiveBrushRenderVersion(v2Of('pencil')),
        BrushRenderVersion.naturalMediaV2,
      );
      expect(
        effectiveBrushRenderVersion(v2Of('brush-pen')),
        BrushRenderVersion.naturalMediaV2,
      );
      for (final brush in ['ballpoint', 'fountain-pen', 'highlighter']) {
        expect(
          effectiveBrushRenderVersion(v2Of(brush)),
          BrushRenderVersion.classicV1,
          reason: '$brush + v2 是非法组合，应回退 v1',
        );
      }
    });

    test('defaultRenderVersionForNewStroke：新笔 pencil/brushPen 默认 v2', () {
      expect(
        defaultRenderVersionForNewStroke(BrushType.pencil),
        BrushRenderVersion.naturalMediaV2,
      );
      expect(
        defaultRenderVersionForNewStroke(BrushType.brushPen),
        BrushRenderVersion.naturalMediaV2,
      );
      expect(
        defaultRenderVersionForNewStroke(BrushType.fountainPen),
        BrushRenderVersion.classicV1,
      );
      expect(
        defaultRenderVersionForNewStroke(BrushType.highlighter),
        BrushRenderVersion.classicV1,
      );
    });
  });

  group('customDataWithFreedrawRender：嵌套 merge 与字段书写', () {
    test('不覆盖 collaborationOwner/pageId 等已有键', () {
      final base = {
        'flowMuse': {
          'collaborationOwner': {'userId': 'u1'},
          'pageId': 'p9',
          'brushType': 'pencil',
          'brushRenderVersion': 2,
        },
      };
      final next = customDataWithFreedrawRender(base, BrushType.brushPen);
      final flowMuse = next['flowMuse'] as Map<String, Object?>;
      expect(flowMuse['collaborationOwner'], {
        'userId': 'u1',
      });
      expect(flowMuse['pageId'], 'p9');
      expect(flowMuse['brushType'], 'brush-pen');
      expect(flowMuse['brushRenderVersion'], 2, reason: '原 v2 保留');
      expect(flowMuse['pressureEncoding'], 1);
      // 原-map 不被改写。
      expect((base['flowMuse'] as Map)['brushType'], 'pencil');
    });

    test('v1 不落字段；pressureEncoded=false 不写 pressureEncoding', () {
      final v1 = customDataWithFreedrawRender(null, BrushType.fountainPen);
      expect((v1['flowMuse'] as Map).containsKey('brushRenderVersion'), isFalse);
      expect(v1['flowMuse'], {
        'brushType': 'fountain-pen',
        'pressureEncoding': 1,
      });

      final legacy = customDataWithFreedrawRender(
        null,
        BrushType.pencil,
        pressureEncoded: false,
      );
      expect(
        (legacy['flowMuse'] as Map).containsKey('pressureEncoding'),
        isFalse,
      );
    });
  });

  group('.markdraw：v2 语法与旧文本兼容', () {
    final serializer = SketchLineSerializer();
    final parser = SketchLineParser();

    FreedrawElement v2PencilElement() => FreedrawElement(
          id: const ElementId('t-v2-pencil'),
          x: 0,
          y: 0,
          width: 10,
          height: 0,
          points: const [Point(0, 0), Point(10, 0)],
          pressures: const [0.3, 0.7],
          simulatePressure: false,
          isComplete: true,
          customData: customDataWithFreedrawRender(
            null,
            BrushType.pencil,
            renderVersion: BrushRenderVersion.naturalMediaV2,
          ),
        );

    test('v2 元素：序列化含 brush/pressure-encoded/render=v2，往返保留全部语义', () {
      final line = serializer.serialize(v2PencilElement());
      expect(line, contains('brush=pencil'));
      expect(line, contains('pressure-encoded'));
      expect(line, contains('render=v2'));
      expect(line, contains('pressure=[0.3,0.7]'));

      final result = parser.parseLine(line, 1);
      expect(result.warnings, isEmpty);
      final element = result.value as FreedrawElement;
      expect(element.pressures, [0.3, 0.7]);
      expect(element.simulatePressure, isFalse);
      expect(brushTypeFromCustomData(element.customData), BrushType.pencil);
      expect(pressureEncodingFromCustomData(element.customData), isTrue);
      expect(
        brushRenderVersionFromCustomData(element.customData),
        BrushRenderVersion.naturalMediaV2,
      );
    });

    test('v1 新式元素（pressureEncoding=1、无版本）：不写 render=，往返不补写', () {
      final element = FreedrawElement(
        id: const ElementId('t-v1-encoded'),
        x: 0,
        y: 0,
        width: 10,
        height: 0,
        points: const [Point(0, 0), Point(10, 0)],
        pressures: const [0.5, 0.5],
        simulatePressure: false,
        isComplete: true,
        customData: customDataWithFreedrawRender(null, BrushType.brushPen),
      );
      final line = serializer.serialize(element);
      expect(line, isNot(contains('render=')));
      expect(line, contains('pressure-encoded'));
      final parsed = parser.parseLine(line, 1).value as FreedrawElement;
      expect(
        brushRenderVersionFromCustomData(parsed.customData),
        BrushRenderVersion.classicV1,
      );
      expect(pressureEncodingFromCustomData(parsed.customData), isTrue);
    });

    test('旧文本（无任何标记）：按 legacy/v1 解释且二次序列化稳定', () {
      const legacyLine =
          'freedraw id=a1 points=[0,0 10,0] pressure=[0.5,0.5] '
          'no-simulate-pressure brush=pencil';
      final result = parser.parseLine(legacyLine, 1);
      expect(result.warnings, isEmpty);
      final element = result.value as FreedrawElement;
      expect(pressureEncodingFromCustomData(element.customData), isFalse,
          reason: '旧文本 pressures 为原始值，不补写编码标记');
      expect(
        brushRenderVersionFromCustomData(element.customData),
        BrushRenderVersion.classicV1,
      );

      final rewritten = serializer.serialize(element, alias: 'a1');
      expect(rewritten, isNot(contains('pressure-encoded')));
      expect(rewritten, isNot(contains('render=')));
      // 二次往返稳定。
      final reparsed =
          parser.parseLine(rewritten, 1).value as FreedrawElement;
      final rewritten2 = serializer.serialize(reparsed, alias: 'a1');
      expect(rewritten2, rewritten);
    });

    test('未知 render 值：ParseWarning 一次并回退 v1，不抛异常', () {
      const line =
          'freedraw id=b1 points=[0,0 10,0] pressure=[0.5,0.5] '
          'no-simulate-pressure brush=pencil pressure-encoded render=v9';
      final result = parser.parseLine(line, 1);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.message, contains('render'));
      expect(result.value, isNotNull);
      final element = result.value as FreedrawElement;
      expect(
        brushRenderVersionFromCustomData(element.customData),
        BrushRenderVersion.classicV1,
      );
      expect(pressureEncodingFromCustomData(element.customData), isTrue);
    });

    test('修复回归：pressureEncoding 不再在 .markdraw 往返中丢失', () {
      // 旧实现的解析端只写 brushType，编码语义往返即丢（二轮审查 F 项）。
      final line = serializer.serialize(v2PencilElement());
      final parsed = parser.parseLine(line, 1).value as FreedrawElement;
      expect(pressureEncodingFromCustomData(parsed.customData), isTrue);
    });
  });

  group('LiveInkStyle.renderVersion：混合客户端契约', () {
    Map<String, Object?> baseStyle(Map<String, Object?> extra) => {
          'brushType': 'pencil',
          'strokeColor': '#000000',
          'strokeWidth': 4,
          'opacity': 100,
          ...extra,
        };

    test('缺失取 1；2 取 2；toJson 只对 v2 写字段', () {
      final missing = LiveInkStyle.fromJson(baseStyle(const {}));
      expect(missing.renderVersion, 1);
      expect(missing.toJson().containsKey('renderVersion'), isFalse);

      final v2 = LiveInkStyle.fromJson(baseStyle(const {'renderVersion': 2}));
      expect(v2.renderVersion, 2);
      expect(v2.toJson()['renderVersion'], 2);

      final v1explicit =
          LiveInkStyle.fromJson(baseStyle(const {'renderVersion': 1}));
      expect(v1explicit.renderVersion, 1);
      expect(v1explicit.toJson().containsKey('renderVersion'), isFalse);
    });

    test('数值语义：1.0/2.0 合法；字符串/3/NaN 拒绝该 chunk', () {
      expect(
        LiveInkStyle.fromJson(baseStyle(const {'renderVersion': 2.0}))
            .renderVersion,
        2,
      );
      expect(
        LiveInkStyle.fromJson(baseStyle(const {'renderVersion': 1.0}))
            .renderVersion,
        1,
      );
      for (final bad in ['2', 3, 0, double.nan, true]) {
        expect(
          () => LiveInkStyle.fromJson(baseStyle({'renderVersion': bad})),
          throwsFormatException,
          reason: '$bad 应拒绝该 live chunk',
        );
      }
    });

    test('非法组合回退：v2 + 非自然介质笔形 → 1（不丢协作数据）', () {
      final style = LiveInkStyle.fromJson(
        baseStyle(const {'brushType': 'highlighter', 'renderVersion': 2}),
      );
      expect(style.renderVersion, 1);
    });
  });

  group('Excalidraw JSON 与外部 sanitizer', () {
    test('Excalidraw JSON 往返保留嵌套版本语义，旧顶层 schema 不变', () {
      final element = FreedrawElement(
        id: const ElementId('t-json-v2'),
        x: 0,
        y: 0,
        width: 10,
        height: 0,
        points: const [Point(0, 0), Point(10, 0)],
        pressures: const [0.4, 0.4],
        simulatePressure: false,
        isComplete: true,
        customData: customDataWithFreedrawRender(
          null,
          BrushType.brushPen,
          renderVersion: BrushRenderVersion.naturalMediaV2,
        ),
      );
      final encoded = ExcalidrawJsonCodec.serialize(
        MarkdrawDocument(sections: [SketchSection([element])]),
      );
      expect(encoded, contains('brushRenderVersion'));
      expect(encoded, contains('"type":"freedraw"'));

      final parsed = ExcalidrawJsonCodec.parse(encoded);
      expect(parsed.warnings, isEmpty);
      final restored =
          parsed.value.allElements.whereType<FreedrawElement>().single;
      expect(
        brushRenderVersionFromCustomData(restored.customData),
        BrushRenderVersion.naturalMediaV2,
      );
      expect(
        pressureEncodingFromCustomData(restored.customData),
        isTrue,
      );
      expect(brushTypeFromCustomData(restored.customData), BrushType.brushPen);
    });

    test('sanitizer 只剥离 collaborationOwner，保留笔刷版本字段', () {
      final element = FreedrawElement(
        id: const ElementId('t-sanitize'),
        x: 0,
        y: 0,
        width: 10,
        height: 0,
        points: const [Point(0, 0), Point(10, 0)],
        pressures: const [0.4, 0.4],
        simulatePressure: false,
        isComplete: true,
        customData: {
          'flowMuse': {
            'brushType': 'pencil',
            'pressureEncoding': 1,
            'brushRenderVersion': 2,
            'collaborationOwner': {'userId': 'u1'},
          },
        },
      );
      final sanitized = withoutCreator(element);
      final flowMuse = sanitized.customData!['flowMuse'] as Map;
      expect(flowMuse.containsKey(kCollaborationOwnerCustomDataKey), isFalse);
      expect(flowMuse['brushRenderVersion'], 2);
      expect(flowMuse['pressureEncoding'], 1);
      expect(flowMuse['brushType'], 'pencil');
    });
  });
}
