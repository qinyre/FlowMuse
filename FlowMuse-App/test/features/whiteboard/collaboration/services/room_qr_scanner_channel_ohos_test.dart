import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/room_qr_scanner_channel_ohos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/room_qr_scanner');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<BuildContext> host(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('扫码测试'))),
    );
    return tester.element(find.text('扫码测试'));
  }

  testWidgets('鸿蒙扫码结果复用房间解析且不执行外部地址', (tester) async {
    // Given: 系统通道返回公开假房间，全部通过 mock，不请求相机或网络。
    final room = CollaborationRoom.newRoom();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scan');
      calls++;
      return room.toLink(
        origin: 'https://app.flowmuse.cloud',
        path: '/whiteboard/collaboration',
      );
    });
    final context = await host(tester);
    // When
    final result = await scanRoomQrOhos(context);
    // Then: 不在失败断言中输出密钥。
    expect(result?.roomKey == room.roomKey, isTrue);
    expect(result?.roomId == room.roomId, isTrue);
    expect(calls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('取消原生扫码不显示错误', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final context = await host(tester);
    expect(await scanRoomQrOhos(context), isNull);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final value in ['https://untrusted.example', '', 'x' * 4097]) {
    testWidgets('无效或超长原生结果保留页面和粘贴入口 长度${value.length}', (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      final context = await host(tester);
      expect(await scanRoomQrOhos(context), isNull);
      await tester.pump();
      expect(find.textContaining('这不是有效的协作房间二维码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final code in ['permission_denied', 'scan_failed', 'unavailable']) {
    testWidgets('原生错误降级且不回显通道异常 $code', (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: code, message: 'must-not-display');
      });
      final context = await host(tester);
      expect(await scanRoomQrOhos(context), isNull);
      await tester.pump();
      expect(
        find.textContaining(code == 'permission_denied' ? '未获得相机权限' : '扫码暂不可用'),
        findsOneWidget,
      );
      expect(find.textContaining('must-not-display'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('缺失插件安全降级', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });
    final context = await host(tester);
    expect(await scanRoomQrOhos(context), isNull);
    await tester.pump();
    expect(find.textContaining('当前版本未提供鸿蒙扫码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
