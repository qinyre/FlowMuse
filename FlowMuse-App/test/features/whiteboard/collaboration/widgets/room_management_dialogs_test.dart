import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/room_collaborator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/create_room_dialog.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/room_members_dialog.dart';

void main() {
  Future<void> openCreate(
    WidgetTester tester,
    void Function(int?) result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<int>(
                  context: context,
                  builder: (_) => const CreateRoomDialog(),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('创建默认不限人数，取消与不限人数有不同结果', (tester) async {
    int? result = -1;
    await openCreate(tester, (value) => result = value);
    expect(find.text('不限人数'), findsOneWidget);
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    expect(result, 0);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('创建可选择含房主的在线上限', (tester) async {
    int? result;
    await openCreate(tester, (value) => result = value);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 人').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    expect(result, 4);
  });

  const owner = RoomCollaborator(
    socketId: 'owner',
    username: '房主样例',
    isGuest: true,
    role: 'owner',
  );
  const member = RoomCollaborator(
    socketId: 'member',
    username: '访客样例',
    isGuest: true,
  );

  Future<void> openMembers(
    WidgetTester tester,
    StreamController<List<RoomCollaborator>> stream,
    Future<void> Function(String) remove,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoomMembersDialog(
          users: stream.stream,
          initialUsers: const [owner, member],
          selfSocketId: 'owner',
          maxParticipants: 2,
          onRemove: remove,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('房主不能移出自己，取消不调用接口，确认后实时刷新成员', (tester) async {
    final stream = StreamController<List<RoomCollaborator>>.broadcast();
    addTearDown(stream.close);
    final removed = <String>[];
    await openMembers(tester, stream, (id) async {
      removed.add(id);
      stream.add(const [owner]);
    });
    expect(find.byKey(const ValueKey('remove-owner')), findsNothing);
    expect(find.text('在线 2 / 2 人（含房主）'), findsOneWidget);
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移出'));
    await tester.pumpAndSettle();
    expect(removed, ['member']);
    expect(find.text('在线 1 / 2 人（含房主）'), findsOneWidget);
    expect(find.text('访客样例'), findsNothing);
  });

  testWidgets('移出失败可重试，等待期间不可重复提交，关闭后忽略迟到完成', (tester) async {
    final stream = StreamController<List<RoomCollaborator>>.broadcast();
    addTearDown(stream.close);
    final pending = Completer<void>();
    var calls = 0;
    await openMembers(tester, stream, (_) async {
      calls++;
      if (calls == 1) throw StateError('请求失败');
      await pending.future;
    });
    Future<void> confirm() async {
      await tester.tap(find.text('移出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认移出'));
      await tester.pumpAndSettle();
    }

    await confirm();
    expect(find.textContaining('请求失败'), findsOneWidget);
    await confirm();
    expect(find.text('移出中…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('remove-member')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls, 2);
  });
}
