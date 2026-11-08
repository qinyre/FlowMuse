import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic root and multi-selection drag CPU benchmark', () {
    for (final multi in [false, true]) {
      for (final count in [40, 160, 400]) {
        final controller = MarkdrawController();
        final elements = multi
            ? <Element>[
                for (var i = 0; i < count; i++)
                  RectangleElement(
                    id: ElementId('rect-$i'),
                    x: (i % 20) * 50.0,
                    y: (i ~/ 20) * 50.0,
                    width: 30,
                    height: 30,
                  ),
              ]
            : MindmapLayout.treeToElements(
                MindmapNode(
                  text: 'root',
                  children: List.generate(
                    count,
                    (i) => MindmapNode(text: 'node $i'),
                  ),
                ),
              );
        controller.loadScene(
          Scene().upsertRemoteElements([
            ...elements,
            if (multi)
              for (var i = 0; i < 2000; i++)
                RectangleElement(
                  id: ElementId('background-$i'),
                  x: 5000,
                  y: i * 50.0,
                  width: 30,
                  height: 30,
                ),
          ]),
        );
        if (multi) {
          controller.applyResult(
            SetSelectionResult(elements.map((e) => e.id).toSet()),
          );
        }
        final label = multi
            ? null
            : elements.whereType<TextElement>().firstWhere(
                (e) => e.text == 'root',
              );
        final root = multi
            ? elements.first
            : controller.currentScene.getElementById(
                ElementId(label!.containerId!),
              )!;
        final point = Point(root.x + root.width / 2, root.y + root.height / 2);
        final tool = SelectTool();
        ToolContext context() => ToolContext(
          scene: controller.currentScene,
          viewport: const ViewportState(),
          selectedIds: controller.editorState.selectedIds,
        );
        tool.onPointerDown(point, context());
        final times = <int>[];
        for (var i = 1; i <= 25; i++) {
          final watch = Stopwatch()..start();
          controller.applyResult(
            tool.onPointerMove(point + Point(i * 3.0, i * 2.0), context()),
          );
          watch.stop();
          if (i > 5) times.add(watch.elapsedMicroseconds);
        }
        times.sort();
        expect(
          controller.currentScene.getElementById(root.id)!.x,
          closeTo(root.x + 75, .001),
        );
        if (multi) {
          for (final element in elements) {
            final moved = controller.currentScene.getElementById(element.id)!;
            expect(moved.x, closeTo(element.x + 75, .001));
            expect(moved.y, closeTo(element.y + 50, .001));
          }
          expect(
            controller.currentScene
                .getElementById(ElementId('background-0'))!
                .x,
            5000,
          );
        }
        stdout.writeln(
          jsonEncode({
            'scenario': multi ? 'multi-selection' : 'mindmap-root',
            'nodes': multi ? count : count + 1,
            'elements': controller.currentScene.elements.length,
            'medianUs': times[times.length ~/ 2],
            'p95Us': times[(times.length * .95).ceil() - 1],
          }),
        );
        controller.dispose();
      }
    }
  });
}
