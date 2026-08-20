import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

void main() {
  testWidgets('flag=true 将 Freedraw 放在静态与交互画层之间且不重复预览', (tester) async {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: true),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);

    await tester.pumpWidget(_canvas(controller));

    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    expect(
      customPaints.where((paint) => paint.painter is LocalWetInkPainter),
      hasLength(1),
    );
    final staticPainter = customPaints
        .map((paint) => paint.painter)
        .whereType<StaticCanvasPainter>()
        .single;
    expect(staticPainter.previewElement, isNull);
  });

  testWidgets('flag=false 不创建专用画层并保留原 Freedraw 预览', (tester) async {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: false),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    await tester.pumpWidget(_canvas(controller));

    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(10, 10),
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(30, 30),
        delta: Offset(20, 20),
      ),
    );
    await tester.pumpWidget(_canvas(controller));

    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    expect(
      customPaints.where((paint) => paint.painter is LocalWetInkPainter),
      isEmpty,
    );
    final staticPainter = customPaints
        .map((paint) => paint.painter)
        .whereType<StaticCanvasPainter>()
        .single;
    expect(staticPainter.previewElement, isA<FreedrawElement>());
    controller.onPointerCancel(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
    );
  });

  testWidgets('远端湿墨位于静态 Scene 与本地湿墨之间', (tester) async {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: true),
    );
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(() {
      store.dispose();
      controller.dispose();
    });
    controller.switchTool(ToolType.freedraw);

    await tester.pumpWidget(_canvas(controller, remoteWetInkStore: store));

    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    final staticLayer = customPaints
        .where((paint) => paint.painter is StaticCanvasPainter)
        .single;
    final remoteLayer = staticLayer.child! as CustomPaint;
    final localLayer = remoteLayer.child! as CustomPaint;
    expect(remoteLayer.painter, isA<RemoteWetInkPainter>());
    expect(localLayer.painter, isA<LocalWetInkPainter>());
    expect(staticLayer.foregroundPainter, isA<InteractiveCanvasPainter>());
  });
}

Widget _canvas(
  MarkdrawController controller, {
  RemoteWetInkStore? remoteWetInkStore,
}) => MaterialApp(
  home: Scaffold(
    body: EditorCanvas(
      controller: controller,
      remoteWetInkStore: remoteWetInkStore,
    ),
  ),
);
