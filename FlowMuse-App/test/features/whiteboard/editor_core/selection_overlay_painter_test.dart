import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counting canvas proxy that records which [Rect]s were stroked and counts
/// [drawLine] calls, so tests can assert on the selection overlay painting
/// without rendering pixels.
class _RecordingCanvas implements Canvas {
  final List<Rect> strokedRects = <Rect>[];
  int lineCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #drawRect) {
      final args = invocation.positionalArguments;
      if (args.isNotEmpty && args.first is Rect) {
        strokedRects.add(args.first as Rect);
      }
    } else if (invocation.memberName == #drawLine) {
      lineCount++;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(String id, double x, double y) => RectangleElement(
        id: ElementId(id),
        x: x,
        y: y,
        width: 10,
        height: 10,
      );

  const mode = InteractionMode.pointer;
  // Pointer-mode selection padding (selectionPaddingFor(pointer)).
  const pad = 6.0;

  group('InteractiveCanvasPainter 多选外框', () {
    test('多选只画 union 虚线框，不画逐元素内部框', () {
      // Given 两个独立的未分组矩形元素被同时选中（普通多选）
      final elements = [rect('a', 0, 0), rect('b', 100, 150)];
      final overlay = SelectionOverlay.fromElements(elements, mode: mode);
      expect(overlay!.elementBounds, isNotEmpty);

      final recording = _RecordingCanvas();
      final painter = InteractiveCanvasPainter(
        viewport: const ViewportState(zoom: 1.0, offset: Offset.zero),
        interactionMode: mode,
        selection: overlay,
      );

      // When 绘制选中覆盖层
      painter.paint(recording, const Size(400, 400));

      // Then 不出现"元素包围盒 ± padding"大小的矩形（即不再画逐元素轮廓）
      final elementRects = {
        Rect.fromLTWH(0 - pad, 0 - pad, 10 + pad * 2, 10 + pad * 2),
        Rect.fromLTWH(100 - pad, 150 - pad, 10 + pad * 2, 10 + pad * 2),
      };
      for (final r in recording.strokedRects) {
        expect(
          elementRects.contains(r),
          isFalse,
          reason: '多选不应绘制逐元素框，却绘制了 $r',
        );
      }
      // 且 union 虚线外框仍然产生（虚线矩形由多段 drawLine 组成 + 旋转手柄连线）
      expect(recording.lineCount, greaterThanOrEqualTo(8));
    });

    test('单选一个矩形仍绘制单一实线框（无逐元素框）', () {
      final overlay =
          SelectionOverlay.fromElements([rect('a', 0, 0)], mode: mode);
      expect(overlay!.elementBounds, isEmpty);

      final recording = _RecordingCanvas();
      final painter = InteractiveCanvasPainter(
        viewport: const ViewportState(zoom: 1.0, offset: Offset.zero),
        interactionMode: mode,
        selection: overlay,
      );
      painter.paint(recording, const Size(400, 400));

      // 单选仍应出现选中框矩形（命中元素矩形本身，由 drawRect 实线绘制）
      final selectionRect =
          Rect.fromLTWH(0 - pad, 0 - pad, 10 + pad * 2, 10 + pad * 2);
      expect(recording.strokedRects.contains(selectionRect), isTrue);
    });
  });

  group('SelectionOverlay 契约', () {
    test('多选保留 elementBounds（驱动虚线外框判定）', () {
      final overlay = SelectionOverlay.fromElements(
        [rect('a', 0, 0), rect('b', 100, 150)],
        mode: mode,
      );
      expect(overlay!.elementBounds, isNotEmpty);
      expect(overlay.bounds.size.width, greaterThanOrEqualTo(110));
      expect(overlay.bounds.size.height, greaterThanOrEqualTo(160));
    });

    test('单选 elementBounds 为空', () {
      final overlay = SelectionOverlay.fromElements([rect('a', 0, 0)]);
      expect(overlay!.elementBounds, isEmpty);
    });
  });
}
