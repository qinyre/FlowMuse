import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders PDF pages through the platform channel contract', () async {
    const channel = MethodChannel('flow_muse/pdf_import_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'renderPdfPages');
      expect(call.arguments, containsPair('name', 'paper.pdf'));
      expect(call.arguments, containsPair('targetPageWidth', 800.0));
      return [
        <String, Object?>{
          'bytes': Uint8List.fromList([1, 2, 3]),
          'mimeType': 'image/png',
          'width': 800.0,
          'height': 1200.0,
          'pageNumber': 1,
        },
      ];
    });

    final renderer = PlatformPdfPageRenderer(channel: channel);
    final pages = await renderer.render(
      PdfImportSource(name: 'paper.pdf', bytes: Uint8List.fromList([9])),
      const PdfRenderOptions(targetPageWidth: 800),
    );

    expect(pages, hasLength(1));
    expect(pages.single.bytes, Uint8List.fromList([1, 2, 3]));
    expect(pages.single.width, 800);
    expect(pages.single.height, 1200);
    expect(pages.single.pageNumber, 1);
  });
}
