import 'package:flow_muse/features/whiteboard/editor_core/src/ui/file_picker_channel_ohos.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/file_save_channel_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'OHOS picker channel sends filters and decodes selected bytes',
    () async {
      const channel = MethodChannel('flow_muse/file_picker');
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return [
              {
                'name': 'image.png',
                'bytes': Uint8List.fromList([1, 2, 3]),
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final files = await pickFilesViaOhosChannel(
        suffixFilters: const ['图片(.png)|.png'],
      );

      expect(captured?.method, 'pickFiles');
      expect(
        (captured?.arguments as Map<Object?, Object?>)['fileSuffixFilters'],
        ['图片(.png)|.png'],
      );
      expect(files.single.name, 'image.png');
      expect(files.single.bytes, Uint8List.fromList([1, 2, 3]));
    },
  );

  test('OHOS save channel sends bytes and returns the saved path', () async {
    const channel = MethodChannel('flow_muse/file_save');
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return '/data/storage/el2/base/files/drawing.svg';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final path = await saveFileViaOhosChannel(
      'drawing.svg',
      Uint8List.fromList([4, 5, 6]),
    );

    expect(captured?.method, 'saveFile');
    expect(
      (captured?.arguments as Map<Object?, Object?>)['fileName'],
      'drawing.svg',
    );
    expect(path, endsWith('drawing.svg'));
  });
}
