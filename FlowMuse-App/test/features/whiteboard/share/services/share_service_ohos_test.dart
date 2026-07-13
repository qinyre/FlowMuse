import 'package:flow_muse/features/whiteboard/share/models/share_payload.dart';
import 'package:flow_muse/features/whiteboard/share/models/share_result.dart';
import 'package:flow_muse/features/whiteboard/share/services/share_service_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/system_share');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('鸿蒙分享传递文件类型与文件参数', () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (value) async {
          call = value;
          return 'dismissed';
        });

    final result = await const OhosShareService().share(
      ShareFilePayload(
        title: '白板',
        contentType: ShareContentType.png,
        filePath: '/tmp/drawing.png',
        fileName: 'drawing.png',
        mimeType: 'image/png',
      ),
    );

    expect(result, ShareResult.dismissed);
    expect(call!.method, 'share');
    expect(call!.arguments['kind'], 'png');
    expect(call!.arguments['fileName'], 'drawing.png');
  });

  test('缺少鸿蒙通道时返回不可用', () async {
    expect(
      await const OhosShareService().share(
        ShareTextPayload(title: '协作邀请', text: 'https://flowmuse.local'),
      ),
      ShareResult.unavailable,
    );
  });
}
