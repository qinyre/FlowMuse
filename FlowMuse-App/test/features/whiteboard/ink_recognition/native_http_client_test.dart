import 'dart:convert';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flow_muse/http');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('协作请求通过鸿蒙原生通道保留方法、请求体和二进制响应', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return <String, Object>{
            'statusCode': 201,
            'bodyBytes': Uint8List.fromList(utf8.encode('{"ok":true}')),
            'headersJson': '{"content-type":"application/json"}',
          };
        });

    final client = HarmonyAwareHttpClient();
    final response = await client.put(
      Uri.parse('https://api.flowmuse.cloud/api/rooms/test/scene'),
      headers: {'Content-Type': 'application/json'},
      body: '{"scene":1}',
    );
    client.close();

    expect(captured?.method, 'request');
    final arguments = captured?.arguments as Map<Object?, Object?>;
    expect(arguments['method'], 'PUT');
    expect(utf8.decode(arguments['bodyBytes'] as Uint8List), '{"scene":1}');
    expect(response.statusCode, 201);
    expect(response.body, '{"ok":true}');
  });
}
