import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';

Scene buildScene(List<Element> elements) =>
    elements.fold(Scene(), (s, e) => s.addElement(e));

RectangleElement owned(String id, String key, {String? index}) =>
    withCreator(
          RectangleElement(
            id: ElementId(id),
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            index: index ?? id,
          ),
          CollaborationCreator(
            creatorKey: key,
            displayName: key,
            isGuest: false,
          ),
        )
        as RectangleElement;

RectangleElement plain(String id) => RectangleElement(
  id: ElementId(id),
  x: 0,
  y: 0,
  width: 10,
  height: 10,
  index: id,
);

final _sharedAdapter = RoughCanvasAdapter();

StaticCanvasPainter painterFor(
  Scene scene, {
  String? focusedCreatorKey,
  bool history = false,
  Set<ElementId> highlight = const {},
  int revision = 0,
}) => StaticCanvasPainter(
  scene: scene,
  adapter: _sharedAdapter,
  viewport: const ViewportState(),
  focusedCreatorKey: focusedCreatorKey,
  focusHistoricalContent: history,
  locallyHighlightedElementIds: highlight,
  localHighlightRevision: revision,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无 focus：saveLayer = 0，draw-call 数与绘制顺序同基线（z 序证据）', () {
    final scene = buildScene([
      owned('a', 'user:a'),
      plain('b'),
      owned('c', 'user:c'),
    ]);
    final baseline = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(baseline, const Size(1000, 1000));
    final focusOff = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(focusOff, const Size(1000, 1000));
    // 纯矩形场景无 frame/箭头标签/pending，基线 saveLayer 必须为 0
    expect(baseline.saveLayerCount, 0);
    expect(focusOff.saveLayerCount, 0, reason: '无 focus 路径零新增 saveLayer');
    expect(focusOff.drawCallCount, baseline.drawCallCount);
    // z 序结构化证据：矩形经 rough adapter 走 drawPath，pathOrder 记录
    // 每个元素 path 包围盒的出现顺序，逐一相同
    expect(focusOff.pathOrder, baseline.pathOrder);
    // 每个矩形经 rough generator 产生填充+描边两条 drawPath：3 元素 = 6 条
    expect(baseline.pathOrder.length, 6);
  });

  test('聚焦不改变绘制顺序：pathOrder 与无 focus 完全一致（v4 §7.3）', () {
    final scene = buildScene([
      owned('a', 'user:a'),
      plain('b'),
      owned('c', 'user:a'),
    ]);
    final noFocus = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(noFocus, const Size(1000, 1000));
    final focused = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
    ).paint(focused, const Size(1000, 1000));
    expect(
      focused.pathOrder,
      noFocus.pathOrder,
      reason: '目标元素不得浮到遮挡者上方——绘制顺序不变',
    );
  });

  test('全 dim 且无本地高亮：dim saveLayer = 1', () {
    final scene = buildScene([owned('a', 'user:a'), owned('b', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:other',
    ).paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1);
  });

  test('全部目标：dim saveLayer = 0', () {
    final scene = buildScene([owned('a', 'user:a'), owned('b', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
    ).paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 0);
  });

  test('交替目标/非目标：saveLayer 数 = 连续 dim 段数（2 段）；元素只画一次', () {
    final scene = buildScene([
      owned('a', 'user:a'),
      plain('b'),
      owned('c', 'user:a'),
      plain('d'),
    ]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
    ).paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 2);
    // drawCall 数与无 focus 基线一致（每元素最多 render 一次）
    final baseline = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(baseline, const Size(1000, 1000));
    expect(spy.drawCallCount, baseline.drawCallCount);
  });

  test('本地高亮元素全亮并打断 dim 段', () {
    final scene = buildScene([
      owned('a', 'user:a'),
      plain('b'),
      owned('c', 'user:c'),
    ]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
      highlight: {const ElementId('b')},
    ).paint(spy, const Size(1000, 1000));
    // a 全亮、b 高亮全亮、c dim → 1 段
    expect(spy.saveLayerCount, 1);
  });

  test('history focus：无 owner 全亮、有 owner 变淡', () {
    final scene = buildScene([plain('old'), owned('new', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene, history: true).paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1);
  });

  test('PDF 背景元素始终全亮', () {
    final pdf = RectangleElement(
      id: const ElementId('pdf'),
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      customData: const {
        'flowMuse': {'pageId': 'p', 'pdfBackground': true},
      },
    );
    final scene = buildScene([pdf, owned('a', 'user:a')]);
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:other',
    ).paint(spy, const Size(1000, 1000));
    // 只有 a 一个 dim 段；pdf 全亮不参与
    expect(spy.saveLayerCount, 1);
  });

  test(
    'shouldRepaint：focus 标量与（focus 中）revision 触发；无 focus 时仅 revision 变化不触发',
    () {
      final scene = buildScene([owned('a', 'user:a')]);
      final p0 = painterFor(scene);
      final p1 = painterFor(scene, focusedCreatorKey: 'user:a');
      expect(p0.shouldRepaint(p1), isTrue);

      final f0 = painterFor(
        scene,
        focusedCreatorKey: 'user:a',
        highlight: const {},
        revision: 1,
      );
      final f1 = painterFor(
        scene,
        focusedCreatorKey: 'user:a',
        highlight: const {},
        revision: 2,
      );
      expect(f0.shouldRepaint(f1), isTrue);

      final n0 = painterFor(scene, revision: 1);
      final n1 = painterFor(scene, revision: 2);
      expect(
        n0.shouldRepaint(n1),
        isFalse,
        reason: '两端都无 focus 时 revision 单独变化不触发重绘',
      );
    },
  );

  Scene alternatingScene(int count) {
    var scene = Scene();
    for (var i = 0; i < count; i++) {
      final index = i.toString().padLeft(8, '0');
      final element = i.isEven
          ? owned('e$i', 'user:a', index: index)
          : owned('e$i', 'user:b', index: index);
      scene = scene.addElement(element);
    }
    return scene;
  }

  void stressCase(int count) {
    final scene = alternatingScene(count);
    // 基线（无 focus）：saveLayer 必须为 0
    final baseline = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(scene).paint(baseline, const Size(2000, 2000));
    expect(baseline.saveLayerCount, 0);
    // creator focus 'user:a'：被 dim 的是奇数位（user:b）。每个奇数位元素
    // 被前后偶数位目标元素隔开成独立 dim 段；0..count-1 中奇数索引个数
    // 恒为 count ~/ 2（count 奇偶无关——5001 时为 2500）。
    final focused = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
    ).paint(focused, const Size(2000, 2000));
    expect(focused.saveLayerCount, count ~/ 2);
    expect(focused.drawCallCount, baseline.drawCallCount, reason: '每元素最多绘制一次');
  }

  test('1000 元素交替作者', () => stressCase(1000));
  test(
    '5000 元素交替作者',
    () => stressCase(5000),
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('999 元素交替作者（奇数锁死段数公式）', () => stressCase(999));

  test('focus × 跨 owner 多选：高亮打断 dim 段且不增加元素绘制', () {
    final scene = alternatingScene(1000);
    // 高亮奇数位（user:b，即 dim 方向）元素：i % 4 == 1 使约 1/4 的 dim
    // 元素全亮并打断连续段
    final highlight = <ElementId>{
      for (var i = 1; i < 1000; i += 4) ElementId('e$i'),
    };
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
      highlight: highlight,
    ).paint(spy, const Size(2000, 2000));
    final noHighlight = SpyCanvas(Canvas(PictureRecorder()));
    painterFor(
      scene,
      focusedCreatorKey: 'user:a',
    ).paint(noHighlight, const Size(2000, 2000));
    expect(
      spy.saveLayerCount,
      lessThan(noHighlight.saveLayerCount),
      reason: '高亮移除了部分 dim 元素，段数严格减少',
    );
    expect(spy.drawCallCount, noHighlight.drawCallCount);
  });
}
