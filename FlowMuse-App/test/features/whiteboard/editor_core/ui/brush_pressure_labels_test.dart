import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/toolbar_palette_buttons.dart';

// T10：压感滑块语义标签——铅笔"浓淡响应"、毛笔"提按响应"、其余笔
// 保持"压感"；v2 笔形的模拟压感文案可解释且不承诺未实现能力。

void main() {
  test('压力滑块标签按笔形映射', () {
    expect(pressureLabelFor(BrushType.pencil), '浓淡响应');
    expect(pressureLabelFor(BrushType.brushPen), '提按响应');
    expect(pressureLabelFor(BrushType.fountainPen), '压感');
    expect(pressureLabelFor(BrushType.ballpoint), '压感');
    expect(pressureLabelFor(BrushType.highlighter), '压感');
  });

  test('模拟压感文案只对 v2 笔形给出且不含能力承诺', () {
    expect(simulatedPressureCaptionFor(BrushType.pencil), contains('模拟'));
    expect(simulatedPressureCaptionFor(BrushType.brushPen), contains('模拟'));
    expect(simulatedPressureCaptionFor(BrushType.fountainPen), isEmpty);
    // 不出现硬度/纸张/枯湿等未实现控件的字样。
    for (final brush in BrushType.values) {
      final caption = simulatedPressureCaptionFor(brush);
      expect(caption, isNot(contains('硬度')));
      expect(caption, isNot(contains('纸张')));
      expect(caption, isNot(contains('枯湿')));
    }
  });
}
