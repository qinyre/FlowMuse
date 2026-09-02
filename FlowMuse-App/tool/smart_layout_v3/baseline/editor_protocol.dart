/// V3-003B 固定编辑协议（AI surrogate 整理基线的重放实现）。
///
/// 协议规则（与 evidence/baseline/ai-surrogate/protocol.json 逐条一致；
/// 两名 AI 专家代理按书面协议独立执行，本实现用于机器重放校验）：
/// - 内容元素（text/shape/image）按 (floor(center_y/64), bbox.x, id) 排序；
/// - 依序装列：margin 24、段间距 12、列间距 16；列数从 1 起逐 1 自增
///   （上限 100）直到总堆叠高/列数≤可用高，列宽=(可用宽-16*(列数-1))/列数，
///   元素宽超列宽截断；
/// - 元素装不下列剩余高度即换列；笔迹/装饰线/绑定一律原位；
/// - 操作步骤只记录 bbox 变化的内容元素；修改次数=步骤数。
library;

import 'dart:convert';

class EditorProtocol {
  const EditorProtocol._();

  static const double margin = 24;
  static const double gap = 12;
  static const double gutter = 16;

  static const Set<String> contentTypes = {'text', 'shape', 'image'};

  static EditorOutcome apply(Map<String, Object?> scene) {
    final page = scene['page'] as Map<String, Object?>;
    final pageW = (page['width'] as num).toDouble();
    final pageH = (page['height'] as num).toDouble();
    final elements = (scene['elements'] as List).cast<Map<String, Object?>>();

    final content = <Map<String, Object?>>[];
    final passthrough = <Map<String, Object?>>[];
    for (final element in elements) {
      if (contentTypes.contains(element['type'])) {
        content.add(jsonDecode(jsonEncode(element)) as Map<String, Object?>);
      } else {
        passthrough.add(element);
      }
    }

    int row(Map<String, Object?> e) {
      final b = (e['bbox'] as List).cast<num>();
      return ((b[1].toDouble() + b[3].toDouble() / 2) / 64).floor();
    }

    content.sort((a, b) {
      final ra = row(a), rb = row(b);
      if (ra != rb) return ra.compareTo(rb);
      final xa = (a['bbox'] as List).cast<num>()[0].toDouble();
      final xb = (b['bbox'] as List).cast<num>()[0].toDouble();
      if (xa != xb) return xa.compareTo(xb);
      return (a['id'] as String).compareTo(b['id'] as String);
    });

    final usableW = pageW - margin * 2;
    final usableH = pageH - margin * 2;
    final stackH = content.fold<double>(0, (acc, e) {
      final b = (e['bbox'] as List).cast<num>();
      return acc + b[3].toDouble() + gap;
    });
    var columns = 1;
    while (columns < 100 &&
        _columnWidth(usableW, columns) > 0 &&
        stackH / columns > usableH) {
      columns++;
    }
    final colW = _columnWidth(usableW, columns);

    final steps = <Map<String, Object?>>[];
    var columnIndex = 0;
    var cursorY = margin;
    for (final element in content) {
      final b = (element['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList();
      var w = b[2] > colW ? colW : b[2];
      final h = b[3];
      if (cursorY + h > pageH - margin && columnIndex + 1 < columns) {
        columnIndex++;
        cursorY = margin;
      }
      final x = margin + columnIndex * (colW + gutter);
      element['bbox'] = [x, cursorY, w, h];
      final changed = x != b[0] || cursorY != b[1] || w != b[2];
      if (changed) {
        steps.add({
          'element_id': element['id'],
          'from': [b[0], b[1], b[2], b[3]],
          'to': [x, cursorY, w, h],
        });
      }
      cursorY += h + gap;
    }

    return EditorOutcome(
      scene: {
        'page': jsonDecode(jsonEncode(page)) as Map<String, Object?>,
        'elements': [...passthrough, ...content],
      },
      steps: steps,
      modificationCount: steps.length,
      columns: columns,
    );
  }

  static double _columnWidth(double usableW, int columns) =>
      (usableW - gutter * (columns - 1)) / columns;
}

class EditorOutcome {
  const EditorOutcome({
    required this.scene,
    required this.steps,
    required this.modificationCount,
    required this.columns,
  });
  final Map<String, Object?> scene;
  final List<Map<String, Object?>> steps;
  final int modificationCount;
  final int columns;
}
