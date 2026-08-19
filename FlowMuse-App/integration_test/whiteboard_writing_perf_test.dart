import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_report.dart';
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

    final probe = ActivePreviewMetricsProbe();
    final frameTimings = FrameTimingMetricsCollector()..start();
    addTearDown(frameTimings.stop);
    final controller = MarkdrawController(activePreviewMetricsProbe: probe);
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
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.currentScene.elements, isNotEmpty);
    final performance = WritingPerformanceReport.capture(
      activePreview: probe,
      frames: frameTimings.frames,
    );
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
      'performance': performance.toJson(),
      'note': 'P0-2 event-to-paint proxy with FrameTiming by frameNumber.',
    };
  });
}
