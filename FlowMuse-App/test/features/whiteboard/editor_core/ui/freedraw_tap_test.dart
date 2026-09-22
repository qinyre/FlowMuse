import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brush in BrushType.values) {
    for (final layered in [false, true]) {
      for (final zoom in [0.5, 1.0, 2.0]) {
        test(
          '${brush.name} 点触抬笔、撤销重做与重开可见 (layered=$layered, zoom=$zoom)',
          () async {
            for (final drift in [0.0, 0.01, 0.1, 0.5]) {
              final controller = MarkdrawController(
                writingFlags: WritingFeatureFlags(layeredWetInk: layered),
              );
              final reopened = MarkdrawController();
              try {
                controller.setViewport(ViewportState(zoom: zoom));
                controller.switchTool(ToolType.freedraw);
                controller.activeBrushType = brush;
                controller.onPointerDown(
                  const PointerDownEvent(
                    pointer: 1,
                    kind: ui.PointerDeviceKind.stylus,
                    position: ui.Offset(32, 32),
                    pressure: 0.3,
                  ),
                );
                final preview =
                    controller.buildPreviewElement(
                          controller.activeTool.overlay,
                        )!
                        as FreedrawElement;
                final downPressures = List<double>.of(preview.pressures);
                final before = await _inkAlpha(preview);
                controller.onPointerUp(
                  PointerUpEvent(
                    pointer: 1,
                    kind: ui.PointerDeviceKind.stylus,
                    position: ui.Offset(32 + drift, 32),
                    pressure: 0,
                    timeStamp: const Duration(milliseconds: 60),
                  ),
                );
                final element =
                    controller.currentScene.activeElements.single
                        as FreedrawElement;
                final after = await _inkAlpha(element);
                expect(before, greaterThan(0));
                expect(
                  after,
                  greaterThanOrEqualTo(before * 0.5),
                  reason: '抬笔漂移 $drift: 墨量 $before -> $after',
                );
                expect(element.points, [Point.zero]);
                expect(element.pressures, downPressures, reason: '抬笔零压不覆盖落笔压力');
                expect(element.x, 32 / zoom);
                expect(element.y, 32 / zoom);
                controller.undo();
                expect(controller.currentScene.activeElements, isEmpty);
                controller.redo();
                reopened.loadFromContent(
                  controller.serializeScene(format: DocumentFormat.excalidraw),
                  'tap.excalidraw',
                );
                expect(
                  await _inkAlpha(reopened.currentScene.activeElements.single),
                  after,
                );
              } finally {
                reopened.dispose();
                controller.dispose();
              }
            }
          },
        );
      }
    }
  }

  test('点触中的轻微抖动回到起点后仍可见', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = BrushType.fountainPen;
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: ui.PointerDeviceKind.stylus,
        position: ui.Offset(32, 32),
        pressure: 0.3,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: ui.PointerDeviceKind.stylus,
        position: ui.Offset(32.65, 32),
        pressure: 0.4,
        timeStamp: Duration(milliseconds: 8),
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: ui.PointerDeviceKind.stylus,
        position: ui.Offset(32, 32),
        pressure: 0,
        timeStamp: Duration(milliseconds: 60),
      ),
    );
    expect(
      await _inkAlpha(controller.currentScene.activeElements.single),
      greaterThan(0),
    );
  });

  test('停留点的同位置报点不丢失，真实短线与回到起点的笔画保留终点', () async {
    for (final positions in [
      const [ui.Offset(32, 32), ui.Offset(32, 32), ui.Offset(32.1, 32)],
      const [ui.Offset(33, 32)],
      const [ui.Offset(33, 32), ui.Offset(32.1, 32)],
      const [ui.Offset(50, 40), ui.Offset(32, 32)],
    ]) {
      final controller = MarkdrawController();
      try {
        controller.switchTool(ToolType.freedraw);
        controller.activeBrushType = BrushType.fountainPen;
        controller.onPointerDown(
          const PointerDownEvent(
            pointer: 1,
            kind: ui.PointerDeviceKind.stylus,
            position: ui.Offset(32, 32),
            pressure: 0.3,
          ),
        );
        for (var i = 0; i < positions.length - 1; i++) {
          controller.onPointerMove(
            PointerMoveEvent(
              pointer: 1,
              kind: ui.PointerDeviceKind.stylus,
              position: positions[i],
              pressure: 0.7,
              timeStamp: Duration(milliseconds: (i + 1) * 300),
            ),
          );
        }
        controller.onPointerUp(
          PointerUpEvent(
            pointer: 1,
            kind: ui.PointerDeviceKind.stylus,
            position: positions.last,
            pressure: 0,
            timeStamp: Duration(milliseconds: positions.length * 300),
          ),
        );
        final element =
            controller.currentScene.activeElements.single as FreedrawElement;
        if (positions.first == const ui.Offset(32, 32)) {
          expect(element.points, [Point.zero]);
          expect(
            element.customData![recognitionStrokePointTimesKey],
            hasLength(1),
          );
        } else {
          expect(element.points.length, greaterThan(1));
          expect(element.x + element.points.last.x, positions.last.dx);
          expect(element.y + element.points.last.y, positions.last.dy);
        }
        expect(await _inkAlpha(element), greaterThan(0));
      } finally {
        controller.dispose();
      }
    }
  });
}

Future<int> _inkAlpha(Element element) async {
  final first = (element as FreedrawElement).points.first;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(32 - element.x - first.x, 32 - element.y - first.y);
  ElementRenderer.render(canvas, element, RoughCanvasAdapter());
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final pixels = (await image.toByteData())!.buffer.asUint8List();
  var alpha = 0;
  for (var i = 3; i < pixels.length; i += 4) {
    alpha += pixels[i];
  }
  image.dispose();
  picture.dispose();
  return alpha;
}
