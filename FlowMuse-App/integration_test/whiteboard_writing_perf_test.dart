import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:integration_test/integration_test.dart';

const _perfTestEnabled = bool.fromEnvironment('FLOWMUSE_PERF_TEST');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 EditorCanvas 可接收自由笔输入', (tester) async {
    expect(
      _perfTestEnabled,
      isTrue,
      reason: '性能入口仅允许通过 FLOWMUSE_PERF_TEST=true 启用',
    );

    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdrawEditor(
            controller: controller,
            config: const MarkdrawEditorConfig(
              showToolbar: false,
              showPropertyPanel: false,
              showZoomControls: false,
              showHelpButton: false,
              showLibraryPanel: false,
              showMarkdownButton: false,
              showMenu: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byType(EditorCanvas);
    expect(canvas, findsOneWidget);
    final rect = tester.getRect(canvas);
    final start = rect.center - const Offset(80, 20);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(start + const Offset(60, 20));
    await gesture.moveTo(start + const Offset(120, -10));
    await gesture.up();
    await tester.pump();

    expect(controller.currentScene.elements, isNotEmpty);
    binding.reportData = <String, Object?>{
      'schemaVersion': 1,
      'measurementEligible': kProfileMode,
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'platform': defaultTargetPlatform.name,
      'elementsAfterSmokeStroke': controller.currentScene.elements.length,
      'note': 'P0-0 runner smoke only; frame metrics are added by P0-1/P0-2.',
    };
  });
}
