import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarkdrawController controller;
  late MarkdrawFileHandler handler;

  setUp(() {
    controller = MarkdrawController();
    handler = MarkdrawFileHandler(controller: controller);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    controller.dispose();
  });

  test('安卓将完整绘图交给系统保存，取消时返回 false', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final picker = _SavePicker();
    FilePicker.platform = picker;

    expect(await handler.saveAs(), isTrue);
    expect(picker.fileName, 'drawing.markdraw');
    expect(
      utf8.decode(picker.bytes!),
      controller.serializeSceneForExternalExport(),
    );
    expect(handler.currentFilePath, isNull);

    picker.destination = null;
    expect(await handler.saveAs(), isFalse);
  });

  test('鸿蒙另存为请求选择位置并区分保存成功、取消和失败', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
    const channel = MethodChannel('flow_muse/file_save');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? destination = 'file://docs/Download/drawing.markdraw';
    var fail = false;
    MethodCall? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = call;
      if (fail) throw PlatformException(code: 'FILE_SAVE_FAILED');
      return destination;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await handler.saveAs(), isTrue);
    expect(request?.method, 'saveFile');
    expect(request?.arguments, {
      'fileName': 'drawing.markdraw',
      'bytes': utf8.encode(controller.serializeSceneForExternalExport()),
      'chooseLocation': true,
    });

    destination = null;
    expect(await handler.saveAs(), isFalse);
    fail = true;
    await expectLater(handler.saveAs(), throwsA(isA<PlatformException>()));
  });
}

class _SavePicker extends FilePicker {
  String? destination = '/system-managed/drawing.markdraw';
  String? fileName;
  Uint8List? bytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.fileName = fileName;
    this.bytes = bytes;
    return destination;
  }
}
