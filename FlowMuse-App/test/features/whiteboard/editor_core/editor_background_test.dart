import 'dart:async';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final layout in CanvasLayoutType.values) {
    testWidgets('${layout.name} 更换背景及恢复主题时，工具栏留白与画布同色', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      // 隔离工具栏偏好的磁盘读取，只验证编辑器的背景绘制。
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        (_) => Completer<Object?>().future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        ),
      );
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(initialLayout: CanvasLayout(type: layout)),
      );
      addTearDown(controller.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            home: MarkdrawEditor(
              controller: controller,
              canvasThemeBackground: '#f2ebe0',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.setViewport(const ViewportState(zoom: 0.2));

      Future<void> expectBackground(Color expected) async {
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (final y in [85, 200]) {
              final offset = (y * image.width + 12) * 4;
              expect(
                bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 4),
                [
                  (expected.toARGB32() >> 16) & 255,
                  (expected.toARGB32() >> 8) & 255,
                  expected.toARGB32() & 255,
                  255,
                ],
                reason: '左侧 y=$y 的实际绘制背景应同步',
              );
            }
          } finally {
            image.dispose();
          }
        });
      }

      controller.canvasBackgroundColor = '#d8eaf8';
      await expectBackground(const Color(0xffd8eaf8));
      controller.canvasBackgroundColor = '#182b3a';
      await expectBackground(const Color(0xff182b3a));
      controller.followThemeCanvasBackground();
      await expectBackground(const Color(0xfff2ebe0));
      expect(tester.takeException(), isNull);
    });
  }
}
