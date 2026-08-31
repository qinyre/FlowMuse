import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_public_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromEditor 组装出可用的 editor 与 http gateway', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final entry = SmartLayoutPublicEntry.fromEditor(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:48931'),
    );
    expect(entry.editor, isA<SmartLayoutEditorGateway>());
    expect(entry.http, isA<SmartLayoutHttpGateway>());
    expect(entry.http.serverUri, Uri.parse('http://127.0.0.1:48931'));
    expect(
      identical(entry.editor.currentScene, controller.currentScene),
      isTrue,
    );
  });

  test('注入的 fake post 传输直达 http gateway', () async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var called = false;
    final entry = SmartLayoutPublicEntry.fromEditor(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:48931'),
      post:
          ({
            required url,
            headers = const {},
            required body,
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            called = true;
            return const NativeHttpResponse(statusCode: 200, body: '{}');
          },
    );
    final responseBody = await entry.http.postJson(path: '/x', body: '{}');
    expect(called, isTrue);
    expect(responseBody, '{}');
  });

  test('dispose 幂等并翻转 isDisposed', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final entry = SmartLayoutPublicEntry.fromEditor(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:48931'),
    );
    expect(entry.isDisposed, isFalse);
    entry.dispose();
    entry.dispose();
    expect(entry.isDisposed, isTrue);
  });

  test('入口不改变旧公开入口签名：v2 prepare/commit API 仍可用', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    SmartLayoutPublicEntry.fromEditor(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:48931'),
    );
    // v2 公开入口行为不受 v3 入口构造影响。
    expect(controller.isDisposed, isFalse);
    expect(controller.currentScene, isA<Scene>());
    expect(() => controller.cancelSmartLayoutPreparation(), returnsNormally);
  });
}
