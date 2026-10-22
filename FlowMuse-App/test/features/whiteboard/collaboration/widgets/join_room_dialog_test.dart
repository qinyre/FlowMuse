import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/join_room_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required Future<CollaborationRoom?> Function(BuildContext) scanner,
    required void Function(CollaborationRoom?) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  onResult(
                    await showDialog<CollaborationRoom>(
                      context: context,
                      builder: (_) => JoinRoomDialog(scanner: scanner),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('扫码成功返回同一房间且等待期间不会重复开启', (tester) async {
    final pending = Completer<CollaborationRoom?>();
    final room = CollaborationRoom.newRoom();
    CollaborationRoom? result;
    var calls = 0;
    await open(
      tester,
      scanner: (_) {
        calls++;
        return pending.future;
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('扫码加入房间'));
    await tester.pump();
    await tester.tap(find.text('正在扫码…'));
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '加入'))
          .onPressed,
      isNull,
    );
    pending.complete(room);
    await tester.pumpAndSettle();
    expect(identical(result, room), isTrue);
    expect(find.byType(JoinRoomDialog), findsNothing);
  });

  testWidgets('取消扫码后仍可粘贴加入，无效输入不会关闭', (tester) async {
    final room = CollaborationRoom.newRoom();
    CollaborationRoom? result;
    await open(
      tester,
      scanner: (_) async => null,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('扫码加入房间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a room');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入完整房间链接'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      room.toLink(
        origin: 'https://app.flowmuse.cloud',
        path: '/whiteboard/collaboration',
      ),
    );
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    expect(result?.roomKey == room.roomKey, isTrue);
  });

  testWidgets('扫码异常保留粘贴入口并显示通用提示', (tester) async {
    await open(
      tester,
      scanner: (_) async => throw StateError('test-only'),
      onResult: (_) {},
    );
    await tester.tap(find.text('扫码加入房间'));
    await tester.pumpAndSettle();
    expect(find.text('扫码暂不可用，请重试或粘贴房间链接。'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭加入对话框后忽略迟到的扫码结果', (tester) async {
    final pending = Completer<CollaborationRoom?>();
    var results = 0;
    await open(
      tester,
      scanner: (_) => pending.future,
      onResult: (_) => results++,
    );
    await tester.tap(find.text('扫码加入房间'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    pending.complete(CollaborationRoom.newRoom());
    await tester.pumpAndSettle();
    expect(results, 1);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和键盘占位下可滚动到粘贴入口', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.reset);
    await open(tester, scanner: (_) async => null, onResult: (_) {});
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
