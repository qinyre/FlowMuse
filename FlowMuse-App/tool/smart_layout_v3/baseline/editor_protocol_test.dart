import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'editor_protocol.dart';

/// V3-003B 契约测试：固定编辑协议 R1~R6 的机器重放语义。
void main() {
  Map<String, Object?> scene(List<Map<String, Object?>> elements,
          {int width = 720, int height = 1280}) =>
      {'page': {'width': width, 'height': height}, 'elements': elements};

  Map<String, Object?> el(String id, String type, List<num> bbox) =>
      {'id': id, 'type': type, 'bbox': bbox, 'rotation': 0};

  test('R1：内容元素按 (band, x, id) 升序进入重放序列', () {
    // b1 中心 y=200/64→band 3；b2 中心 y=150/64→band 2；b3 与 b2 同 band 但 x 更大。
    final outcome = EditorProtocol.apply(scene([
      el('e-late', 'text', [0, 160, 100, 80]), // center 200 → band 3
      el('e-wide', 'text', [300, 120, 100, 60]), // center 150 → band 2
      el('e-narrow', 'text', [100, 120, 100, 60]), // center 150 → band 2, x 更小
    ]));
    final contentIds = (outcome.scene['elements'] as List)
        .cast<Map<String, Object?>>()
        .map((e) => e['id'] as String)
        .toList();
    expect(contentIds, ['e-narrow', 'e-wide', 'e-late']);
  });

  test('R2：单列可容纳时列数为 1，列宽=可用宽', () {
    final outcome = EditorProtocol.apply(scene([
      el('e1', 'text', [0, 0, 100, 40]),
      el('e2', 'text', [0, 0, 100, 40]),
    ]));
    expect(outcome.columns, 1);
    final boxes = (outcome.scene['elements'] as List)
        .cast<Map<String, Object?>>()
        .map((e) => (e['bbox'] as List).cast<num>())
        .toList();
    // 可用宽 = 720-48 = 672；首元素 y=margin=24，间距 12。
    expect(boxes[0], [24, 24, 100, 40]);
    expect(boxes[1], [24, 24 + 40 + 12, 100, 40]);
  });

  test('R2：堆叠高超过可用高时扩到 2 列，列宽扣除 gutter', () {
    // 可用高 = 1280-48 = 1232；总堆叠 = 3*(700+12) = 2136 > 1232 → 2 列。
    final outcome = EditorProtocol.apply(scene([
      el('e1', 'text', [0, 0, 300, 700]),
      el('e2', 'text', [0, 0, 300, 700]),
      el('e3', 'text', [0, 0, 300, 700]),
    ]));
    expect(outcome.columns, 2);
    final byId = {
      for (final e in (outcome.scene['elements'] as List).cast<Map<String, Object?>>())
        e['id'] as String: (e['bbox'] as List).cast<num>(),
    };
    // 列宽 = (672-16)/2 = 328；元素宽 300 未超列宽不截断；第二列 x = 24+328+16 = 368。
    // e1 后 cursorY=736：e2 的 736+700=1436 > 1256 → 换第二列；e3 在第二列 y=736。
    expect(byId['e1'], [24, 24, 300, 700]);
    expect(byId['e2'], [368, 24, 300, 700]);
    expect(byId['e3'], [368, 24 + 700 + 12, 300, 700]);
  });

  test('R3：元素宽超列宽截断为列宽，高不变', () {
    final outcome = EditorProtocol.apply(scene([
      el('e1', 'text', [0, 0, 2000, 40]),
    ]));
    final bbox =
        ((outcome.scene['elements'] as List).cast<Map<String, Object?>>().first['bbox'] as List)
            .cast<num>();
    expect(bbox, [24, 24, 672, 40]);
    // 截断即修改：steps 含 from[2]=2000 → to[2]=672。
    expect(outcome.steps.single['to'], [24, 24, 672, 40]);
  });

  test('R4：笔迹/装饰线/绑定原位且附加字段逐字保留', () {
    final stroke = {'id': 's1', 'type': 'stroke', 'bbox': [500, 900, 40, 30], 'points': [
      [1, 2],
      [3, 4]
    ]};
    final outcome = EditorProtocol.apply(scene([
      stroke,
      el('d1', 'decorative_line', [0, 1000, 100, 4]),
      el('b1', 'binding', [10, 20, 5, 5]),
      el('e1', 'text', [600, 10, 100, 40]),
    ]));
    final elements = (outcome.scene['elements'] as List).cast<Map<String, Object?>>();
    // R6：原位元素在前（原相对顺序），重排内容元素在后。
    expect(elements.map((e) => e['id']).toList(), ['s1', 'd1', 'b1', 'e1']);
    final outStroke = elements.first;
    expect(jsonEncode(outStroke), jsonEncode(stroke));
    expect(outcome.steps.map((s) => s['element_id']).toList(), ['e1']);
  });

  test('R5：bbox 未变化的内容元素不记步骤；modification_count=步骤数', () {
    final outcome = EditorProtocol.apply(scene([
      el('e1', 'text', [24, 24, 100, 40]), // 恰在目标位 → 不记
      el('e2', 'text', [24, 24 + 40 + 12, 100, 40]), // 也恰在目标位 → 不记
    ]));
    expect(outcome.steps, isEmpty);
    expect(outcome.modificationCount, 0);
  });

  test('重放确定性：同一输入两次应用输出逐字节一致', () {
    final input = scene([
      el('e1', 'text', [700, 60, 250, 50]),
      el('e2', 'image', [10, 1200, 100, 60]),
      el('s1', 'stroke', [300, 400, 80, 80]),
      el('e3', 'shape', [40, 40, 900, 30]),
    ]);
    final a = EditorProtocol.apply(jsonDecode(jsonEncode(input)) as Map<String, Object?>);
    final b = EditorProtocol.apply(jsonDecode(jsonEncode(input)) as Map<String, Object?>);
    expect(jsonEncode(b.scene), jsonEncode(a.scene));
    expect(jsonEncode(b.steps), jsonEncode(a.steps));
    expect(b.modificationCount, a.modificationCount);
    expect(b.columns, a.columns);
  });
}
