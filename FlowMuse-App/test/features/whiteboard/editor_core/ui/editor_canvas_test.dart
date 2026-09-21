import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_path_cache.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

void main() {
  testWidgets('湿墨更新不遍历重绘静态笔迹，提交与撤销及时失效', (tester) async {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: true),
    );
    addTearDown(controller.dispose);
    NaturalMediaPathCache.resetForTesting();
    controller.applyResult(
      AddElementResult(
        FreedrawElement(
          id: ElementId('static-pencil'),
          x: 20,
          y: 20,
          width: 80,
          height: 40,
          points: const [Point.zero, Point(40, 5)],
          pressures: const [0.7, 0.7],
          simulatePressure: false,
          isComplete: true,
          strokeWidth: 6,
          customData: customDataWithFreedrawRender(
            null,
            BrushType.pencil,
            renderVersion: BrushRenderVersion.naturalMediaV2,
          ),
        ),
      ),
      applyDefaultStyle: false,
    );
    controller.switchTool(ToolType.freedraw);
    controller.activeBrushType = BrushType.ballpoint;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => EditorCanvas(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = NaturalMediaPathCache.hitCount;
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(50, 100),
        pressure: 0.7,
      ),
    );
    await tester.pump();
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(80, 110),
        pressure: 0.7,
        timeStamp: Duration(milliseconds: 16),
      ),
    );
    await tester.pump();
    expect(
      NaturalMediaPathCache.hitCount,
      before,
      reason: '下层静态 Picture 被重放，不再遍历静态元素',
    );
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 110),
        timeStamp: Duration(milliseconds: 32),
      ),
    );
    await tester.pump();
    expect(NaturalMediaPathCache.hitCount, greaterThan(before));
    final afterCommit = NaturalMediaPathCache.hitCount;
    controller.undo();
    await tester.pump();
    expect(NaturalMediaPathCache.hitCount, greaterThan(afterCommit));
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('flag=false 首点可见，指针取消与 Escape 立即移除预览', (tester) async {
    final controller = MarkdrawController(
      writingFlags: const WritingFeatureFlags(layeredWetInk: false),
    );
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => EditorCanvas(controller: controller),
        ),
      ),
    );
    StaticCanvasPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<StaticCanvasPainter>()
        .single;

    for (final terminal in ['cancel', 'dispatch', 'keyboard']) {
      final gesture = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      expect(painter().previewElement, isA<FreedrawElement>());
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((paint) => paint.painter is LocalWetInkPainter),
        isEmpty,
      );
      if (terminal == 'dispatch') {
        controller.dispatchKey('Escape');
      } else if (terminal == 'keyboard') {
        expect(
          handleKeyEvent(
            event: const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.escape,
              logicalKey: LogicalKeyboardKey.escape,
              timeStamp: Duration.zero,
            ),
            controller: controller,
            getCanvasSize: () => const Size(800, 600),
            onSave: () {},
            onSaveAs: () {},
            onOpen: () {},
            onExportPng: () {},
            onImportImage: () {},
            onThemeToggle: (_) {},
            getCurrentThemeMode: () => ThemeMode.light,
            context: tester.element(find.byType(EditorCanvas)),
          ),
          isTrue,
        );
      } else {
        await gesture.cancel();
      }
      await tester.pump();
      expect(painter().previewElement, isNull);
      expect(controller.currentScene.elements, isEmpty);
      if (terminal != 'cancel') await gesture.cancel();
    }
    await tester.pumpWidget(const SizedBox.shrink());
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
