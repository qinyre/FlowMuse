import 'dart:math' as math;
import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InkTextSizing.estimateFontSize', () {
    test('CJK 主导文本按 0.9 高度系数估算', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 200,
          inkHeight: 100,
          text: '你好',
        ),
        closeTo(90, 0.001),
      );
    });

    test('拉丁文本按 0.72 高度系数且不用宽度兜底', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 300,
          inkHeight: 40,
          text: 'hello',
        ),
        closeTo(28.8, 0.001),
      );
    });

    test('中英混排按 CJK 占比插值系数', () {
      // 你好abc：CJK 占比 2/5 → 系数 0.72 + 0.18×0.4 = 0.792
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 260,
          inkHeight: 100,
          text: '你好abc',
        ),
        closeTo(79.2, 0.001),
      );
    });

    test('多行按行数均分高度', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 300,
          inkHeight: 200,
          text: '你好\n世界',
        ),
        closeTo(90, 0.001),
      );
    });

    test('单个 CJK 扁平字迹启用宽度兜底并限幅 160', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 800,
          inkHeight: 6,
          text: '一',
        ),
        160,
      );
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 120,
          inkHeight: 6,
          text: '一',
        ),
        closeTo(120, 0.001),
      );
    });

    test('多字符 CJK 不启用宽度兜底（宽度含字距噪声）', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 400,
          inkHeight: 80,
          text: '你好',
        ),
        closeTo(72, 0.001),
      );
    });

    test('字号下限 12、上限 400', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 8,
          inkHeight: 4,
          text: 'ok',
        ),
        12,
      );
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 500,
          inkHeight: 250,
          text: '标题',
        ),
        closeTo(225, 0.001),
      );
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 600,
          inkHeight: 900,
          text: '标题',
        ),
        400,
      );
    });

    test('math 分支与智能排版公式启发式一致', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 80,
          inkHeight: 120,
          text: r'\frac{a}{b}',
          isMath: true,
        ),
        40,
      );
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 40,
          inkHeight: 18,
          text: 'x',
          isMath: true,
        ),
        16,
      );
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 40,
          inkHeight: 30,
          text: 'x',
          isMath: true,
        ),
        closeTo(21.6, 0.001),
      );
    });

    test(r'\r\n 归一化后按行数估算', () {
      expect(
        InkTextSizing.estimateFontSize(
          inkWidth: 100,
          inkHeight: 100,
          text: 'a\r\nb',
        ),
        closeTo(36, 0.001),
      );
      expect(InkTextSizing.normalizeLines('a\r\nb\rc'), ['a', 'b', 'c']);
    });
  });

  group('手写转文字文本框尺寸', () {
    MarkdrawController buildController() {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
      return controller;
    }

    Future<TextElement> convertSingleInk(
      MarkdrawController controller, {
      required InkRecognizedElement recognized,
      FreedrawElement? stroke,
    }) async {
      final source =
          stroke ??
          _stroke(
            's1',
            recognized.x,
            recognized.y,
            recognized.width,
            recognized.height,
          );
      controller.applyResult(AddElementResult(source));
      controller.applyResult(SetSelectionResult({source.id}));
      controller.onRecognizeInk =
          (request) async => InkRecognitionResult(elements: [recognized]);
      await controller.convertSelectedInkToText();
      return controller.currentScene.activeElements
          .whereType<TextElement>()
          .single;
    }

    test('横排文本紧包裹、字号跟随笔迹、保色且不被笔迹盒撑大', () async {
      final controller = buildController();
      final text = await convertSingleInk(
        controller,
        recognized: _recognized(
          text: '你好',
          x: 100,
          y: 100,
          width: 400,
          height: 80,
        ),
        stroke: _stroke('s1', 100, 100, 400, 80, '#e03131'),
      );

      expect(text.fontSize, closeTo(72, 0.001)); // 80 × 0.9
      expect(text.strokeColor, '#e03131'); // 源笔迹颜色保留
      expect(text.x, 100); // 水平原位（左对齐笔迹）
      final (measuredWidth, measuredHeight) = TextRenderer.measure(text);
      expect(text.width, closeTo(math.max(measuredWidth + 4, 20.0), 0.001));
      expect(
        text.height,
        closeTo(
          math.max(measuredHeight, text.fontSize * text.lineHeight),
          0.001,
        ),
      );
      expect(text.width, lessThan(400)); // 关键：不再被笔迹包围盒撑大
      expect(
        text.y,
        closeTo(100 + (80 - text.height) / 2, 0.001), // 垂直居中于笔迹
      );
    });

    test('sticky 默认字号不覆盖笔迹推导字号', () async {
      final controller = buildController();
      controller.applyStyleChange(
        const ElementStyle(fontFamily: 'Excalifont', fontSize: 28),
      );
      final text = await convertSingleInk(
        controller,
        recognized: _recognized(
          text: '你好',
          x: 100,
          y: 100,
          width: 400,
          height: 80,
        ),
      );
      expect(text.fontSize, closeTo(72, 0.001));
    });

    test('math 公式字号跟随笔迹且框高含防裁剪余量', () async {
      final controller = buildController();
      final text = await convertSingleInk(
        controller,
        recognized: InkRecognizedElement(
          type: 'math',
          latex: r'\frac{a}{b}',
          x: 60,
          y: 60,
          width: 120,
          height: 90,
        ),
      );
      expect(text.fontSize, 40); // clamp(90×0.72, 16, 40)
      expect(text.height, greaterThanOrEqualTo(40 * 2.4 - 0.001));
      expect(text.width, greaterThanOrEqualTo(120)); // 框不小于笔迹盒
    });

    test('多元素识别结果各自紧包裹', () async {
      final controller = buildController();
      controller.applyResult(AddElementResult(_stroke('s1', 50, 50, 300, 40)));
      controller.applyResult(AddElementResult(_stroke('s2', 50, 100, 300, 40)));
      controller.applyResult(
        SetSelectionResult({ElementId('s1'), ElementId('s2')}),
      );
      controller.onRecognizeInk =
          (request) async => InkRecognitionResult(
            elements: [
              _recognized(text: '第一行', x: 50, y: 50, width: 300, height: 40),
              _recognized(text: '第二行', x: 50, y: 100, width: 300, height: 40),
            ],
          );
      await controller.convertSelectedInkToText();

      final texts = controller.currentScene.activeElements
          .whereType<TextElement>()
          .toList();
      expect(texts, hasLength(2));
      for (final text in texts) {
        final (measuredWidth, _) = TextRenderer.measure(text);
        expect(text.width, closeTo(math.max(measuredWidth + 4, 20.0), 0.001));
        expect(text.width, lessThan(300));
      }
      expect(texts.first.y, lessThan(texts.last.y));
    });

    test('竖排模板锚点保持既有尺寸语义（未被紧包裹收窄）', () async {
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(
          initialLayout: CanvasLayout(
            type: CanvasLayoutType.paged,
            pages: const [
              CanvasPage(
                id: 'page-1',
                index: 0,
                bounds: Rect.fromLTWH(0, 0, 800, 800),
                template: CanvasPageTemplate.ancientBook,
              ),
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
      controller.smartInkLayoutMode = true;

      // 古籍栏宽 88、fontSize 61.6；笔迹放在最右列（crossAxis≈660）附近
      controller.applyResult(
        AddElementResult(_stroke('s1', 630, 150, 60, 300)),
      );
      controller.applyResult(SetSelectionResult({ElementId('s1')}));
      controller.onRecognizeInk =
          (request) async => InkRecognitionResult(
            elements: [
              _recognized(
                text: '床前明月',
                x: 630,
                y: 150,
                width: 60,
                height: 300,
              ),
            ],
          );
      await controller.convertSelectedInkToText();

      final text = controller.currentScene.activeElements
          .whereType<TextElement>()
          .single;
      final flowMuse = text.customData!['flowMuse']! as Map;
      expect(flowMuse['writingMode'], 'vertical');
      expect(text.fontSize, closeTo(61.6, 0.001));
      // 竖排高度按字数 × lineHeight（88），保持旧语义
      expect(text.height, greaterThanOrEqualTo(4 * 88 - 0.001));
    });
  });
}

FreedrawElement _stroke(
  String id,
  double x,
  double y,
  double width,
  double height, [
  String color = '#1e1e1e',
]) {
  return FreedrawElement(
    id: ElementId(id),
    x: x,
    y: y,
    width: width,
    height: height,
    points: [Point(0, 0), Point(width, height)],
    strokeColor: color,
  );
}

InkRecognizedElement _recognized({
  required String text,
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  return InkRecognizedElement(
    type: 'text',
    text: text,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}
