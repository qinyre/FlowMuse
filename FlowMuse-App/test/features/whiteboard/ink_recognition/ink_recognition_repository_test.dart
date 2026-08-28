import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/ink_recognition_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 识别仓库非 2xx 错误映射：用户看到中文提示，原始响应体不进异常消息。
/// HTTP 走 NativeHttpClient → flow_muse/http 平台通道，测试用 mock 通道
/// 返回状态码，不访问真实网络。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flow_muse/http');

  InkRecognitionRepository buildRepository() => InkRecognitionRepository(
    // 本地假配置：测试不产生真实外发请求（通道已被 mock 拦截）
    config: const CollaborationConfig(
      serverUrl: 'http://127.0.0.1:48931',
      shareOrigin: 'https://example.invalid/FlowMuse',
    ),
  );

  void respondWith(int statusCode, String body) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{'statusCode': statusCode, 'body': body};
        });
  }

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('非 2xx 状态码 → 用户可读中文（不含原始响应体）', () {
    for (final (status, expected) in const [
      (401, '识别服务鉴权失败，请检查服务配置'),
      (403, '识别服务鉴权失败，请检查服务配置'),
      (404, '识别服务版本过旧，请联系管理员升级服务端'),
      (500, '识别服务异常（状态码 500），请稍后重试'),
      (503, '识别服务异常（状态码 503），请稍后重试'),
      (429, '识别服务请求失败（状态码 429）'),
      (302, '识别服务请求失败（状态码 302）'),
    ]) {
      test('裁剪重问 HTTP $status →「$expected」', () async {
        respondWith(status, '{"error":"raw server detail leaked"}');
        final repository = buildRepository();
        await expectLater(
          repository.transcribeCrop(
            const SmartLayoutTranscribeRequest(imageBase64: 'aGk='),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              expected,
            ),
          ),
        );
      });
    }

    test('异常消息不携带原始响应体内容（脱敏）', () async {
      respondWith(500, '{"error":"raw server detail leaked"}');
      final repository = buildRepository();
      await expectLater(
        repository.transcribeCrop(
          const SmartLayoutTranscribeRequest(imageBase64: 'aGk='),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            isNot(contains('raw server detail')),
          ),
        ),
      );
    });
  });

  group('同一映射覆盖视觉排版与手写识别入口', () {
    test('视觉排版 500 → 中文提示', () async {
      respondWith(500, 'Internal Server Error');
      final repository = buildRepository();
      await expectLater(
        repository.visionSmartLayout(
          const SmartLayoutVisionRequest(pageId: 'p-1', imageBase64: 'aGk='),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '识别服务异常（状态码 500），请稍后重试',
          ),
        ),
      );
    });

    test('手写识别 403 → 中文提示', () async {
      respondWith(403, 'forbidden');
      final repository = buildRepository();
      await expectLater(
        repository.recognize(
          const InkRecognitionRequest(
            sessionId: 's-1',
            strokes: [
              InkRecognitionStroke(
                id: 'stroke-1',
                points: [InkRecognitionPoint(x: 0, y: 0)],
              ),
            ],
            bounds: InkRecognitionBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '识别服务鉴权失败，请检查服务配置',
          ),
        ),
      );
    });
  });

  group('2xx 正常解析不受影响', () {
    test('单块转写 200 → 解析 text 与 confidence', () async {
      respondWith(200, '{"text":"勾股定理","confidence":0.92}');
      final repository = buildRepository();
      final response = await repository.transcribeCrop(
        const SmartLayoutTranscribeRequest(imageBase64: 'aGk='),
      );
      expect(response.text, '勾股定理');
      expect(response.confidence, closeTo(0.92, 1e-9));
    });

    test('视觉排版 200 → 解析 elements', () async {
      respondWith(200, '''
        {
          "elements": [
            {"id": "e0", "role": "title", "text": "标题", "markIds": ["m1"], "confidence": 0.9}
          ]
        }
      ''');
      final repository = buildRepository();
      final response = await repository.visionSmartLayout(
        const SmartLayoutVisionRequest(pageId: 'p-1', imageBase64: 'aGk='),
      );
      expect(response.elements, hasLength(1));
      expect(response.elements.first.text, '标题');
    });
  });
}
