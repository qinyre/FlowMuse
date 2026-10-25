import 'dart:async';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/ui/color_picker.dart';
import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('连续悬停和拖动取色只读取一次整张图像', (tester) async {
    final image = _TrackedImage();
    var renders = 0;
    String? selected;
    await _showPicker(
      tester,
      render: (_) async {
        renders++;
        return image;
      },
      onSelect: (color) => selected = color,
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(350, 210));
    for (var i = 0; i < 100; i++) {
      await mouse.moveTo(Offset(350 + i % 20, 210));
    }
    await mouse.down(const Offset(350, 210));
    for (var i = 0; i < 100; i++) {
      await mouse.moveTo(Offset(350 + i % 20, 210));
    }
    await mouse.up();
    await tester.pump();

    expect(selected, '#000000');
    expect(renders, 1);
    expect(image.reads, 1, reason: '移动次数不能变成整张画布的读取次数');
    expect(image.disposals, 1);
    await mouse.removePointer();
  });

  testWidgets('抬起位置决定颜色并正确换算画布全局偏移', (tester) async {
    final image = _TrackedImage()
      ..setPixel(230, 150, 0xff0000)
      ..setPixel(250, 150, 0x00ff00);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(pointer: 1, position: Offset(350, 210)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerUpEvent(pointer: 1, position: Offset(370, 210)),
    );
    await tester.pump();

    expect(selected, '#00ff00');
    expect(image.reads, 1);
  });

  testWidgets('画布外抬起不沿用画布内的旧颜色', (tester) async {
    final image = _TrackedImage()..setPixel(230, 150, 0xff0000);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(pointer: 1, position: Offset(350, 210)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerUpEvent(pointer: 1, position: Offset(700, 210)),
    );
    await tester.pump();

    expect(selected, isNull);
  });

  testWidgets('等待截图时取消会丢弃并释放迟到的图像', (tester) async {
    final pending = Completer<ui.Image?>();
    final image = _TrackedImage();
    await _showPicker(tester, render: (_) => pending.future);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    pending.complete(image);
    await tester.pump();
    await tester.pump();

    expect(image.disposals, 1);
    expect(image.reads, 0);
    expect(
      find
          .byType(MouseRegion)
          .evaluate()
          .any(
            (element) =>
                (element.widget as MouseRegion).cursor ==
                SystemMouseCursors.precise,
          ),
      isFalse,
    );
  });

  testWidgets('等待截图时关闭弹层也会释放迟到的图像', (tester) async {
    final pending = Completer<ui.Image?>();
    final image = _TrackedImage();
    await _showPicker(tester, render: (_) => pending.future);
    await tester.pumpWidget(const SizedBox());
    pending.complete(image);
    await tester.pump();

    expect(image.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('准备期间快速点击会在像素就绪后按该位置选色', (tester) async {
    final pending = Completer<ByteData?>();
    final image = _TrackedImage(onRead: () => pending.future)
      ..setPixel(230, 150, 0x228be6);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.tapAt(const Offset(350, 210));
    expect(selected, isNull);
    pending.complete(image.pixels);
    await tester.pump();

    expect(selected, '#228be6');
    expect(image.reads, 1);
    expect(image.disposals, 1);
  });

  testWidgets('取消准备中的点击不会在读取结束后误选颜色', (tester) async {
    final pending = Completer<ByteData?>();
    final image = _TrackedImage(onRead: () => pending.future);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.tapAt(const Offset(350, 210));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    pending.complete(image.pixels);
    await tester.pump();

    expect(selected, isNull);
    expect(image.disposals, 1);
  });

  testWidgets('重入取色后旧像素读取不能覆盖新截图', (tester) async {
    final pending = Completer<ByteData?>();
    final oldImage = _TrackedImage(onRead: () => pending.future)
      ..setPixel(230, 150, 0xff0000);
    final newImage = _TrackedImage()..setPixel(230, 150, 0x00ff00);
    var renders = 0;
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => ++renders == 1 ? oldImage : newImage,
      onSelect: (color) => selected = color,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    pending.complete(oldImage.pixels);
    await tester.pump();
    await tester.tapAt(const Offset(350, 210));

    expect(renders, 2);
    expect(selected, '#00ff00');
    expect(oldImage.disposals, 1);
    expect(newImage.disposals, 1);
  });

  testWidgets('像素读取中销毁弹层会释放图像且不触发选色', (tester) async {
    final pending = Completer<ByteData?>();
    final image = _TrackedImage(onRead: () => pending.future);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(image.pixels);
    await tester.pump();

    expect(selected, isNull);
    expect(image.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布右下边缘使用像素所属位置而不是四舍五入出界', (tester) async {
    final image = _TrackedImage()..setPixel(499, 399, 0x010203);
    String? selected;
    await _showPicker(
      tester,
      render: (_) async => image,
      onSelect: (color) => selected = color,
    );
    await tester.tapAt(const Offset(619.8, 459.8));

    expect(selected, '#010203');
  });

  for (final failure in ['empty snapshot', 'empty pixels', 'read error']) {
    testWidgets('取色失败后可继续用调色板选择颜色：$failure', (tester) async {
      final image = _TrackedImage(
        onRead: () async {
          if (failure == 'read error') {
            throw StateError('synthetic read failure');
          }
          return null;
        },
      );
      String? selected;
      await _showPicker(
        tester,
        render: (_) async => failure == 'empty snapshot' ? null : image,
        onSelect: (color) => selected = color,
      );
      expect(selected, isNull);
      await tester.enterText(find.byType(TextField), '#abcdef');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(selected, '#abcdef');
      expect(image.disposals, failure == 'empty snapshot' ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _showPicker(
  WidgetTester tester, {
  required Future<ui.Image?> Function(Size) render,
  ValueChanged<String>? onSelect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ColorPaletteOverlay(
          anchor: const Offset(30, 30),
          currentColor: '#123456',
          onSelect: onSelect ?? (_) {},
          onDismiss: () {},
          onRenderScene: render,
          canvasSize: const Size(500, 400),
          canvasGlobalOffset: const Offset(120, 60),
          autoActivateEyedropper: true,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _TrackedImage extends Fake implements ui.Image {
  _TrackedImage({this.onRead});

  final ByteData pixels = ByteData(500 * 400 * 4);
  final Future<ByteData?> Function()? onRead;
  int reads = 0;
  int disposals = 0;

  @override
  int get width => 500;

  @override
  int get height => 400;

  void setPixel(int x, int y, int rgb) {
    final offset = (y * width + x) * 4;
    pixels.setUint8(offset, (rgb >> 16) & 0xff);
    pixels.setUint8(offset + 1, (rgb >> 8) & 0xff);
    pixels.setUint8(offset + 2, rgb & 0xff);
    pixels.setUint8(offset + 3, 0xff);
  }

  @override
  Future<ByteData?> toByteData({
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
  }) async {
    expect(disposals, 0);
    expect(format, ui.ImageByteFormat.rawRgba);
    reads++;
    if (onRead != null) return onRead!();
    return pixels;
  }

  @override
  void dispose() {
    disposals++;
    expect(disposals, 1);
  }
}
