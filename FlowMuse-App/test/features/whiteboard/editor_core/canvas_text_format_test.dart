import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/math_text_utils.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/positioned_math_text.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('白板文本保留 Markdown 源码，测量使用实际显示样式', () {
    final element = _text(
      r'# 标题'
      '\n'
      r'- **重点**与 *斜体*、\*字面星号'
      '\n'
      r'key_part_name',
    );
    final painter = TextRenderer.buildTextPainter(element);
    addTearDown(painter.dispose);
    expect(painter.text?.toPlainText(), '标题\n•  重点与 斜体、*字面星号\nkey_part_name');
    final spans = (painter.text! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == '重点').style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      spans.singleWhere((span) => span.text == '斜体').style?.fontStyle,
      FontStyle.italic,
    );
    expect(TextRenderer.measure(element).$2, greaterThan(element.fontSize * 3));
    expect(element.text, startsWith('# '));
  });

  testWidgets('独立 LaTeX 退出编辑后渲染并保留可往返的原始源码', (tester) async {
    final controller = MarkdrawController()..canvasSize = const Size(600, 400);
    addTearDown(controller.dispose);
    final original = _text('原文');
    controller.loadScene(Scene().addElement(original));
    controller.startTextEditingExisting(original);
    const source = r'$$\frac{x_1}{y}$$';
    controller.textEditingController.text = source;
    controller.commitTextEditing();

    final formula =
        controller.currentScene.activeElements.single as TextElement;
    expect(formula.text, source);
    expect(MathTextUtils.latex(formula), r'\frac{x_1}{y}');
    expect(MathTextUtils.latex(_text(r'合计 $12，另有 $5')), isNull);
    expect(formula.height, greaterThan(formula.fontSize * 2));
    final exported = ExcalidrawJsonCodec.serialize(
      MarkdrawDocument(
        sections: [
          SketchSection([formula]),
        ],
      ),
    );
    final restored =
        ExcalidrawJsonCodec.parse(exported).value.allElements.single
            as TextElement;
    expect(restored.text, source);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            PositionedMathText(
              element: restored,
              viewport: const ViewportState(),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(Math), findsOneWidget);
    expect(find.text(source), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('整理稿的多行公式作为一个独立块写入', () {
    const formula =
        r'$$'
        '\n'
        r'\begin{aligned} a &= b \\ c &= d \end{aligned}'
        '\n'
        r'$$';
    final blocks = parseNoteDraft('# 公式\n## 推导\n$formula\n结论');
    expect(
      blocks.where((block) => block.role == NoteDraftRole.formula).single.text,
      formula,
    );

    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.insertNoteDraft(blocks);
    final written = controller.currentScene.activeElements
        .whereType<TextElement>()
        .where(MathTextUtils.isMathText)
        .single;
    expect(written.text, formula);
    expect(written.height, greaterThan(written.fontSize * 2));
  });
}

TextElement _text(String text) => TextElement(
  id: const ElementId('text'),
  x: 20,
  y: 20,
  width: 400,
  height: 80,
  text: text,
  fontFamily: 'Helvetica',
);
