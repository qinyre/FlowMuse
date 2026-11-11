import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/font_resolver.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/text_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('随包字体下，中文短行落到最终画布宽度时不多换一行', () async {
    await (FontLoader('Excalifont')..addFont(
          rootBundle.load('assets/fonts/markdraw/Excalifont-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
          'FlowMuseSans',
        )..addFont(rootBundle.load('assets/fonts/ui/FlowMuseSans-Regular.ttf')))
        .load();
    final style = FontResolver.resolve('Excalifont');
    expect(style.fontFamily, 'Excalifont');
    expect(style.fontFamilyFallback?.first, 'FlowMuseSans');

    final measure = TextMeasureAdapter();
    for (final text in ['二叉树遍历', '先序：根，左，右', '中序：D B E A C F']) {
      const maxWidth = 420.0;
      final planned = measure.measure(
        text: text,
        fontFamily: 'Excalifont',
        fontSize: 28,
        maxWidth: maxWidth,
      );
      final element = TextElement(
        id: const ElementId('text'),
        x: 0,
        y: 0,
        width: planned.paintWidth,
        height: planned.height,
        text: text,
        fontSize: 28,
        fontFamily: 'Excalifont',
      );
      final painter = TextRenderer.buildTextPainter(element);
      try {
        painter.layout(maxWidth: element.width);
        expect(planned.paintWidth, lessThanOrEqualTo(maxWidth));
        expect(planned.paintWidth, greaterThan(planned.width));
        expect(painter.computeLineMetrics(), hasLength(1));
        expect(painter.height, closeTo(element.height, .001));
      } finally {
        painter.dispose();
      }
    }
  });
}
