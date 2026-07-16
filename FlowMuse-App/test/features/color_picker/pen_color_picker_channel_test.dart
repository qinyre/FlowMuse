import 'package:flow_muse/features/color_picker/pen_color_picker_channel_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/pen_color_picker');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('鸿蒙全局取色返回规范化颜色', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {'status': 'picked', 'color': '#12AB34'};
        });

    final result = await const PenColorPickerChannelOhos().pickColor();

    expect(captured?.method, 'pickColor');
    expect(result, (color: '#12ab34', unavailable: false));
  });

  test('鸿蒙全局取色不可用时标记需要画布降级', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'unavailable'},
        );

    expect(await const PenColorPickerChannelOhos().pickColor(), (
      color: null,
      unavailable: true,
    ));
  });

  test('用户取消或返回无效颜色时保持原颜色', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 'dismissed'},
    );
    expect(await const PenColorPickerChannelOhos().pickColor(), (
      color: null,
      unavailable: false,
    ));

    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 'picked', 'color': 'not-a-color'},
    );
    expect(await const PenColorPickerChannelOhos().pickColor(), (
      color: null,
      unavailable: false,
    ));
  });

  test('缺少鸿蒙通道时降级，其他平台异常时保持原颜色', () async {
    expect(await const PenColorPickerChannelOhos().pickColor(), (
      color: null,
      unavailable: true,
    ));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'picker_failed'),
        );
    expect(await const PenColorPickerChannelOhos().pickColor(), (
      color: null,
      unavailable: false,
    ));
  });
}
