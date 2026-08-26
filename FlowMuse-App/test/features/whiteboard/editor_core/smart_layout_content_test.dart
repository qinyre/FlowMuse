import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_content.dart';
import 'package:flutter_test/flutter_test.dart';

TextElement text(String content, {double x = 0, double y = 0, bool vertical = false}) {
  final element = TextElement(
    id: ElementId.generate(),
    x: x,
    y: y,
    width: 200,
    height: 28,
    text: content,
  );
  if (!vertical) return element;
  return element.copyWith(
    customData: {
      'flowMuse': {
        ...?element.customData?['flowMuse'] as Map<String, Object?>?,
        'writingMode': 'vertical',
      },
    },
  );
}

ImageElement image(String id, double x, double y, double w, double h) =>
    ImageElement(
      id: ElementId(id),
      x: x,
      y: y,
      width: w,
      height: h,
      fileId: 'file-$id',
    );

SmartLayoutStructureInput input({
  required List<SmartLayoutPptGroup> groups,
  Map<String, TextElement> texts = const {},
  Map<String, Rect> textBounds = const {},
  Map<String, Element> elements = const {},
  Map<String, Rect> elementBounds = const {},
}) =>
    SmartLayoutStructureInput(
      groups: groups,
      textByKey: texts,
      textSourceBounds: textBounds,
      elementByKey: elements,
      elementSourceBounds: elementBounds,
    );

void main() {
  test('配对：垂直间距最小 + 水平重叠率达标者胜出，互为唯一', () {
    // 图1 (72,200,400,300)；图2 (72,900,400,300)
    final img1 = image('img-1', 72, 200, 400, 300);
    final img2 = image('img-2', 72, 900, 400, 300);
    // 文A 在图1 下方紧邻；文B 在图2 下方紧邻；文C 在图2 下方但更远
    final texts = {
      'a': text('图一说明', x: 100, y: 520),
      'b': text('图二说明', x: 100, y: 1220),
      'c': text('远处的字', x: 100, y: 1400),
    };
    final textBounds = {
      'a': const Rect.fromLTWH(100, 520, 200, 28),
      'b': const Rect.fromLTWH(100, 1220, 200, 28),
      'c': const Rect.fromLTWH(100, 1400, 200, 28),
    };
    final content = SmartLayoutStructureBuilder.build(
      input(
        groups: const [
          SmartLayoutPptGroup(role: 'figure', elementIds: ['img-1', 'img-2']),
          SmartLayoutPptGroup(role: 'body', elementIds: ['a', 'b', 'c']),
        ],
        texts: texts,
        textBounds: textBounds,
        elements: {'img-1': img1, 'img-2': img2},
        elementBounds: {
          'img-1': const Rect.fromLTWH(72, 200, 400, 300),
          'img-2': const Rect.fromLTWH(72, 900, 400, 300),
        },
      ),
      pageId: 'page-1',
      contentArea: const Rect.fromLTWH(72, 72, 1444, 2102),
    );
    expect(content.pairs, hasLength(2));
    // 图1 配文A（垂直间距 20 < 图2 与文A 的 380）
    expect(content.pairs[0].figure.key, 'img-1');
    expect(content.pairs[0].caption.key, 'a');
    // 图2 配文B（间距 20，比文C 的 80 更近）
    expect(content.pairs[1].figure.key, 'img-2');
    expect(content.pairs[1].caption.key, 'b');
    // 文C 未配对
    expect(content.looseTexts.map((u) => u.key), ['c']);
    expect(content.looseFigures, isEmpty);
  });

  test('水平重叠率不足（<0.3）不配对', () {
    final img = image('img-1', 72, 200, 400, 300);
    final content = SmartLayoutStructureBuilder.build(
      input(
        groups: const [
          SmartLayoutPptGroup(role: 'figure', elementIds: ['img-1']),
          SmartLayoutPptGroup(role: 'body', elementIds: ['far-text']),
        ],
        texts: {'far-text': text('角落的字', x: 1300, y: 520)},
        textBounds: {
          // 与图(72..472)水平重叠 = 0
          'far-text': const Rect.fromLTWH(1300, 520, 200, 28),
        },
        elements: {'img-1': img},
        elementBounds: {'img-1': const Rect.fromLTWH(72, 200, 400, 300)},
      ),
      pageId: 'page-1',
      contentArea: const Rect.fromLTWH(72, 72, 1444, 2102),
    );
    expect(content.pairs, isEmpty);
    expect(content.looseFigures.map((u) => u.key), ['img-1']);
    expect(content.looseTexts.map((u) => u.key), ['far-text']);
  });

  test('title 置顶提取且不参与配对', () {
    final img = image('img-1', 72, 400, 400, 300);
    final titleText = text('反思总结', x: 100, y: 100);
    final caption = text('图一说明', x: 100, y: 720);
    final content = SmartLayoutStructureBuilder.build(
      input(
        groups: const [
          SmartLayoutPptGroup(role: 'title', elementIds: ['title-1']),
          SmartLayoutPptGroup(role: 'figure', elementIds: ['img-1']),
          SmartLayoutPptGroup(role: 'body', elementIds: ['caption-1']),
        ],
        texts: {'title-1': titleText, 'caption-1': caption},
        textBounds: {
          'title-1': const Rect.fromLTWH(100, 100, 200, 28),
          'caption-1': const Rect.fromLTWH(100, 720, 200, 28),
        },
        elements: {'img-1': img},
        elementBounds: {'img-1': const Rect.fromLTWH(72, 400, 400, 300)},
      ),
      pageId: 'page-1',
      contentArea: const Rect.fromLTWH(72, 72, 1444, 2102),
    );
    expect(content.title, isNotNull);
    expect(content.title!.key, 'title-1');
    // title 不参与配对：图配的是 caption 而非 title
    expect(content.pairs, hasLength(1));
    expect(content.pairs.first.caption.key, 'caption-1');
    expect(content.looseTexts, isEmpty);
  });

  test('竖排文本块带 vertical 标记', () {
    final unitText = text('惬意小猫', vertical: true);
    final content = SmartLayoutStructureBuilder.build(
      input(
        groups: const [
          SmartLayoutPptGroup(role: 'body', elementIds: ['v-1']),
        ],
        texts: {'v-1': unitText},
        textBounds: {'v-1': const Rect.fromLTWH(500, 200, 40, 160)},
      ),
      pageId: 'page-1',
      contentArea: const Rect.fromLTWH(72, 72, 1444, 2102),
    );
    expect(content.looseTexts, hasLength(1));
    expect(content.looseTexts.first.vertical, isTrue);
  });
}
