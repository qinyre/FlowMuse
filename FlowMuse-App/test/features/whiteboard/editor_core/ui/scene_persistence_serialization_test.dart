import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [8, 2 * 1024 * 1024]) {
    test('本地保存捕获快照，图片字节完整，后续清空不影响保存，字节=$size', () async {
      final c = MarkdrawController();
      addTearDown(c.dispose);
      final bytes = Uint8List(size)..fillRange(0, size, 7);
      c.loadScene(
        Scene()
            .addFile('page', ImageFile(mimeType: 'image/png', bytes: bytes))
            .addElement(
              ImageElement(
                id: ElementId('page-element'),
                x: 0,
                y: 0,
                width: 100,
                height: 100,
                fileId: 'page',
                customData: const {
                  'flowMuse': {'testMetadata': '中文𝑥'},
                },
              ),
            )
            .addElement(
              FreedrawElement(
                id: ElementId('annotation'),
                x: 10,
                y: 10,
                width: 40,
                height: 10,
                points: const [Point.zero, Point(40, 10)],
                pressures: const [.3, .7],
                isComplete: true,
                customData: customDataWithFreedrawRender(
                  null,
                  BrushType.pencil,
                  renderVersion: BrushRenderVersion.naturalMediaV2,
                ),
              ),
            )
            .addElement(
              TextElement(
                id: ElementId('caption'),
                x: 20,
                y: 30,
                width: 80,
                height: 24,
                text: '合成笔记𝑥',
                fontFamily: 'Excalifont',
              ),
            ),
      );
      final expected =
          jsonDecode(c.serializeScene(format: DocumentFormat.excalidraw))
              as Map<String, dynamic>;
      final saving = c.serializeSceneForPersistence();
      c.loadScene(Scene());
      final actual = jsonDecode(await saving) as Map<String, dynamic>;
      (expected['files']['page'] as Map).remove('created');
      (actual['files']['page'] as Map).remove('created');
      expect(actual, expected);
      final dataUrl = actual['files']['page']['dataURL'] as String;
      expect(
        base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
        orderedEquals(bytes),
      );
      expect(c.currentScene.elements, isEmpty);
    });
  }

  test('离开画布释放控制器后，在途大场景保存仍能完成', () async {
    final c = MarkdrawController();
    c.loadScene(
      Scene().addFile(
        'page',
        ImageFile(mimeType: 'image/png', bytes: Uint8List(1024 * 1024)),
      ),
    );
    final saving = c.serializeSceneForPersistence();
    c.dispose();
    final result = jsonDecode(await saving) as Map<String, dynamic>;
    expect(result['files'], contains('page'));
    expect(result['type'], 'excalidraw');
  });
}
