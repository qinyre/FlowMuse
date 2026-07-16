import 'package:flow_muse/features/whiteboard/service_widget/recent_whiteboard_snapshot.dart';
import 'package:flow_muse/features/whiteboard/service_widget/service_widget_channel_ohos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/service_widget');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('updateLastWhiteboard 发送精确参数', () async {
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recorded = call;
          return null;
        });

    await const ServiceWidgetChannelOhos().updateLastWhiteboard(
      const RecentWhiteboardSnapshot(
        noteId: 'note-123',
        title: '线代课堂笔记',
        updatedAt: 1721000000000,
      ),
    );

    expect(recorded?.method, 'updateLastWhiteboard');
    expect(recorded?.arguments['noteId'], 'note-123');
    expect(recorded?.arguments['title'], '线代课堂笔记');
    // updatedAt 以字符串传输，避开鸿蒙 MethodChannel 对 int64 的 BigInt 解码问题。
    expect(recorded?.arguments['updatedAt'], '1721000000000');
  });

  test('takePendingLaunchAction 识别 resumeLastWhiteboard', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takePendingLaunchAction') {
            return 'resumeLastWhiteboard';
          }
          return null;
        });

    expect(
      await const ServiceWidgetChannelOhos().takePendingLaunchAction(),
      ServiceWidgetLaunchAction.resumeLastWhiteboard,
    );
  });

  test('MissingPluginException 时静默降级', () async {
    expect(
      await const ServiceWidgetChannelOhos().takePendingLaunchAction(),
      isNull,
    );
  });

  test('setLaunchListener 在收到 onLaunchActionEnqueued 时触发', () async {
    int callCount = 0;
    const ServiceWidgetChannelOhos().setLaunchListener(() => callCount++);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flow_muse/service_widget',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLaunchActionEnqueued'),
      ),
      (_) {},
    );

    expect(callCount, 1);
  });
}
