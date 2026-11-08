import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic root drag CPU benchmark', () {
    for (final count in [40, 160, 400]) {
      final controller = MarkdrawController();
      final elements = MindmapLayout.treeToElements(
        MindmapNode(
          text: 'root',
          children: List.generate(count, (i) => MindmapNode(text: 'node $i')),
        ),
      );
      controller.loadScene(Scene().upsertRemoteElements(elements));
      final label = elements.whereType<TextElement>().firstWhere(
        (e) => e.text == 'root',
      );
      final root = controller.currentScene.getElementById(
        ElementId(label.containerId!),
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
      stdout.writeln(
        jsonEncode({
          'nodes': count + 1,
          'elements': elements.length,
          'medianUs': times[times.length ~/ 2],
          'p95Us': times[(times.length * .95).ceil() - 1],
        }),
      );
      controller.dispose();
    }
  });
}
