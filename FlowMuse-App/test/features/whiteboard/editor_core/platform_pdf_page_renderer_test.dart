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

  for (final cancel in [false, true]) {
    test('鸿蒙导入进度回传、取消=$cancel，并释放回调通道', () async {
      const channel = MethodChannel('flow_muse/pdf_progress_test');
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var cancelled = false;
      var progressName = '';
      final received = <int>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        progressName = (call.arguments as Map)['progressChannel'] as String;
        for (var i = 0; i <= 3; i++) {
          Object? keepGoing;
          await messenger.handlePlatformMessage(
            progressName,
            codec.encodeMethodCall(
              MethodCall('progress', {'completed': i, 'total': 3}),
            ),
            (reply) => keepGoing = codec.decodeEnvelope(reply!),
          );
          if (cancel && i == 2) {
            expect(keepGoing, isFalse);
            break;
          }
          expect(keepGoing, isTrue);
        }
        return <Object?>[];
      });
      final result = PlatformPdfPageRenderer(channel: channel).render(
        PdfImportSource(name: 'progress.pdf', bytes: Uint8List(1)),
        PdfRenderOptions(
          onProgress: (done, total) {
            expect(total, 3);
            received.add(done);
            if (cancel && done == 1) cancelled = true;
          },
          isCancelled: () => cancelled,
        ),
      );
      if (cancel) {
        await expectLater(result, throwsStateError);
        expect(received, [0, 1]);
      } else {
        expect(await result, isEmpty);
        expect(received, [0, 1, 2, 3]);
      }
      await messenger.handlePlatformMessage(
        progressName,
        codec.encodeMethodCall(const MethodCall('progress')),
        (reply) => expect(reply, isNull, reason: '结束后没有残留 handler'),
      );
    });
  }
}
