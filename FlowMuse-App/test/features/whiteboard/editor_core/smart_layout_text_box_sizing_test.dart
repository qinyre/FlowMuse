import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(
      'Excalifont',
    )..addFont(rootBundle.load('assets/fonts/markdraw/Excalifont-Regular.ttf'));
    await loader.load();
  });

  testWidgets('旧版转写三模板紧框，校对后重测，提交与撤销保留原稿', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: const [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 1588, 2246),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    for (final (id, y, height) in [
      ('title', 120.0, 24.0),
      ('body', 320.0, 180.0),
    ]) {
      controller.applyResult(
        AddElementResult(
          FreedrawElement(
            id: ElementId(id),
            x: 120,
            y: y,
            width: 600,
            height: height,
            points: [const Point(0, 0), Point(600, height)],
            customData: const {
              'flowMuse': {'pageId': 'page-1'},
            },
          ),
        ),
      );
    }
    final original = controller.editorState.scene;
    controller.onVisionSmartLayout = (_) async => SmartLayoutVisionResponse(
      elements: [
        SmartLayoutVisionElement(
          id: 'title',
          role: 'title',
          text: 'Title',
          markIds: ['m1'],
          confidence: 0.95,
        ),
        SmartLayoutVisionElement(
          id: 'body',
          role: 'body',
          text: 'OK',
          markIds: ['m2'],
          confidence: 0.95,
        ),
      ],
    );
    final preparation = await tester.runAsync(
      () => controller.prepareSmartLayoutTemplates(pageId: 'page-1'),
    );
    expect(preparation, isNotNull);
    expect(controller.editorState.scene, same(original));
    await tester.runAsync(() => _capture(preparation!));

    for (final unit in preparation!.content.textUnits) {
      _expectTight(unit.textElement!);
      expect(unit.textElement!.width, lessThan(unit.sourceBounds.width));
    }
    for (final kind in SmartLayoutTemplateKind.values) {
      final layout = preparation.layouts[kind];
      expect(layout, isNotNull, reason: kind.name);
      final texts = layout!.addElements.whereType<TextElement>().toList();
      expect(texts, hasLength(2));
      for (final text in texts) {
        _expectTight(text);
      }
      expect(layout.previewRects[0].overlaps(layout.previewRects[1]), isFalse);
      if (kind != SmartLayoutTemplateKind.inplace) {
        expect(texts.first.fontSize, 28); // 原字号策略未改，标题仅由模板放大。
      }
    }
    final inplace = preparation.layouts[SmartLayoutTemplateKind.inplace]!;
    for (final (index, unit) in preparation.content.textUnits.indexed) {
      expect(inplace.previewRects[index].center, unit.sourceBounds.center);
    }
    final kept = preparation.layoutsKeepInk[SmartLayoutTemplateKind.inplace]!;
    expect(kept.addElements, isEmpty);
    expect(
      kept.previewRects,
      preparation.content.textUnits.map((u) => u.sourceBounds),
    );

    final plan = controller
        .buildSmartLayoutPlanForTemplate(
          preparation,
          SmartLayoutTemplateKind.inplace,
        )
        .plan!;
    controller.enterSmartLayoutDraft(plan);
    final body = plan.addElements.whereType<TextElement>().last;
    for (final text in ['A much longer line\nSecond line', 'OK']) {
      expect(controller.reviseSmartLayoutDraftText(body.id, text), isTrue);
      final revised = controller.editorState.scene.activeElements
          .whereType<TextElement>()
          .singleWhere((e) => e.id == body.id);
      _expectTight(revised);
      expect(Offset(revised.x, revised.y), Offset(body.x, body.y));
    }
    expect(controller.commitSmartLayoutDraft(plan), isTrue);
    for (final text
        in controller.editorState.scene.activeElements
            .whereType<TextElement>()) {
      _expectTight(text);
    }
    controller.undo();
    expect(controller.editorState.scene, original);
  });

  test('讲义压缩字号时同步缩框，才能放进较矮的内容区', () {
    final text = _generatedText();
    final result = SmartLayoutTemplateEngine.layout(
      kind: SmartLayoutTemplateKind.handout,
      content: SmartLayoutContent(
        pageId: 'page-1',
        contentArea: const Rect.fromLTWH(0, 0, 600, 40),
        looseTexts: [_unit(text)],
      ),
    );
    expect(result, isNotNull);
    final placed = result!.addElements.whereType<TextElement>().single;
    expect(placed.fontSize, lessThan(text.fontSize));
    _expectTight(placed);
    expect(placed.y + placed.height, lessThanOrEqualTo(40));
  });

  test('单字、多行和中英混排按实际渲染测量，保留元数据', () {
    for (final text in ['i', '中英 mixed', '第一行\nSecond line']) {
      final input = _generatedText().copyWithText(text: text, fontSize: 12);
      final measured = SmartLayoutTemplateEngine.measureTemplateText(input);
      _expectTight(measured);
      expect(measured.customData, input.customData);
      expect(measured.id, input.id);
      expect(Offset(measured.x, measured.y), Offset(input.x, input.y));
    }
  });

  test('普通手动文本、手动定宽、绑定文本、公式及竖排不缩框', () {
    final generated = _generatedText();
    final exceptions = [
      generated.copyWith(customData: const {}),
      generated.copyWith(
        customData: const {
          'flowMuse': {'smartLayout': true},
        },
      ),
      generated.copyWithText(autoResize: false),
      generated.copyWithText(containerId: 'container'),
      for (final extra in [
        {'smartLayoutType': 'math'},
        {'writingMode': 'vertical'},
      ])
        generated.copyWith(
          customData: {
            'flowMuse': {'smartLayout': true, 'blockId': 'block-1', ...extra},
          },
        ),
    ];
    for (final input in exceptions) {
      final measured = SmartLayoutTemplateEngine.measureTemplateText(input);
      expect(measured.width, input.width);
      expect(measured.height, input.height);
      expect(measured.customData, input.customData);
      expect(measured.autoResize, input.autoResize);
      expect(measured.containerId, input.containerId);
    }
  });
}

TextElement _generatedText() => TextElement(
  id: ElementId('generated'),
  x: 10,
  y: 20,
  width: 600,
  height: 180,
  text: 'OK',
  fontSize: 48,
  fontFamily: 'Excalifont',
  lineHeight: 1.25,
  customData: const {
    'flowMuse': {'smartLayout': true, 'blockId': 'block-1', 'pageId': 'page-1'},
  },
);

LayoutUnit _unit(TextElement text) => LayoutUnit(
  key: text.id.value,
  sourceBounds: Rect.fromLTWH(text.x, text.y, text.width, text.height),
  size: Size(text.width, text.height),
  kind: LayoutUnitKind.text,
  textElement: text,
);

void _expectTight(TextElement text) {
  final (width, height) = TextRenderer.measure(text);
  expect(text.width, closeTo(math.max(width + 4, 20), 0.001));
  expect(
    text.height,
    closeTo(math.max(height, text.fontSize * text.lineHeight), 0.001),
  );
  final painter = TextRenderer.buildTextPainter(text)
    ..layout(maxWidth: text.width);
  expect(painter.computeLineMetrics(), hasLength(text.text.split('\n').length));
  expect(painter.height, lessThanOrEqualTo(text.height + 0.001));
  painter.dispose();
}

/// 可选桌面渲染证据：真实准备/模板产物 + 命中框，非实机截图或 OCR 评测。
Future<void> _capture(SmartLayoutTemplatePreparation preparation) async {
  const output = String.fromEnvironment('ISSUE14_CAPTURE');
  if (output.isEmpty) return;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFCF3), BlendMode.src);
  for (final (index, kind) in SmartLayoutTemplateKind.values.indexed) {
    canvas.save();
    canvas.translate(index * 800, 0);
    TextRenderer.draw(
      canvas,
      _generatedText()
          .copyWithText(text: kind.name, fontSize: 24)
          .copyWith(x: 24, y: 8, width: 300, height: 36),
    );
    final rects = preparation.layouts[kind]!.previewRects;
    canvas.translate(
      24 - rects.map((rect) => rect.left).reduce(math.min),
      56 - rects.map((rect) => rect.top).reduce(math.min),
    );
    for (final text
        in preparation.layouts[kind]!.addElements.whereType<TextElement>()) {
      TextRenderer.draw(canvas, text);
      canvas.drawRect(
        Rect.fromLTWH(text.x, text.y, text.width, text.height),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF159A82),
      );
    }
    canvas.restore();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(2400, 400);
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final file = File(output)..parent.createSync(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
