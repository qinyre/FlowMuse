import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets('聚焦长说明不挤动 ${width.toInt()}px 顶部头像和房间入口', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarkdrawController()..renameDocument('协作讨论笔记');
      addTearDown(controller.dispose);
      Widget editor(String? focus) => MaterialApp(
        home: Scaffold(
          body: MarkdrawEditor(
            controller: controller,
            collaborating: true,
            collaborationStatusLabel: '实时协作',
            onStartCollaboration: () async {},
            onLeaveCollaboration: () async {},
            collaborationParticipants: const [
              CollaborationParticipantBadge(username: '甲', isCurrentUser: true),
              CollaborationParticipantBadge(username: '乙'),
            ],
            collaborationFocusLabel: focus,
            onExitCollaborationFocus: () {},
          ),
        ),
      );

      // Given：先记录正常协作顶栏的位置。
      await tester.pumpWidget(editor(null));
      await tester.pumpAndSettle();
      final avatars = tester.getRect(find.byType(ParticipantAvatarStack));
      final room = tester.getRect(
        find.byKey(const ValueKey('collaboration-room-control')),
      );

      // When：聚焦无内容的长名称协作者。
      await tester.pumpWidget(editor('正在聚焦：这是一个很长的协作者名称（该创建者暂无已提交内容）'));
      await tester.pumpAndSettle();

      // Then：状态信息不应挤动固定在右侧的成员与房间入口。
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(ParticipantAvatarStack)), avatars);
      expect(
        tester.getRect(
          find.byKey(const ValueKey('collaboration-room-control')),
        ),
        room,
      );
    });
  }

  for (final width in [360.0, 400.0, 1280.0, 1920.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${width.toInt()}px $scale 倍字号双状态不遮挡头像、标题和操作区', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1920, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = MarkdrawController()..renameDocument('协作讨论笔记');
        addTearDown(controller.dispose);
        Widget editor({String? focus, String? follow}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(1920, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: MarkdrawEditor(
                    controller: controller,
                    onBack: () {},
                    fingerDrawingEnabled: true,
                    onFingerDrawingEnabledChanged: (_) {},
                    socialAction: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                    collaborating: true,
                    collaborationStatusLabel: '实时协作',
                    onStartCollaboration: () async {},
                    onLeaveCollaboration: () async {},
                    collaborationParticipants: [
                      for (var i = 0; i < 6; i++)
                        CollaborationParticipantBadge(username: '成员${i + 1}'),
                    ],
                    collaborationFocusLabel: focus,
                    onExitCollaborationFocus: () {},
                    collaborationFollowLabel: follow,
                    onExitCollaborationFollow: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Given：实际画布可比外层窗口窄，保留完整的左右操作区。
        await tester.pumpWidget(editor());
        await tester.pumpAndSettle();
        final avatars = tester.getRect(find.byType(ParticipantAvatarStack));
        final room = tester.getRect(
          find.byKey(const ValueKey('collaboration-room-control')),
        );
        final finger = tester.getRect(find.byType(Switch));

        // When：长名称聚焦和跟随同时出现。
        await tester.pumpWidget(
          editor(
            focus: '正在聚焦：这是一个很长的协作者名字（该创建者暂无已提交内容）',
            follow: '正在跟随 这是另一个很长的协作者名字 · 操作画布可退出',
          ),
        );
        await tester.pumpAndSettle();

        // Then：固定操作不移动，状态不覆盖头像、标题或手指绘制开关。
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byType(ParticipantAvatarStack)), avatars);
        expect(
          tester.getRect(
            find.byKey(const ValueKey('collaboration-room-control')),
          ),
          room,
        );
        expect(avatars.overlaps(finger), isFalse);
        expect(room.overlaps(finger), isFalse);
        if (width <= 400) {
          expect(
            find.byKey(const ValueKey('collaboration-focus-status')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('collaboration-follow-status')),
            findsNothing,
          );
          await tester.tap(
            find.byKey(const ValueKey('collaboration-room-control')),
          );
          await tester.pumpAndSettle();
          expect(find.text('退出聚焦'), findsOneWidget);
          expect(find.text('退出跟随'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          return;
        }
        for (final id in ['focus', 'follow']) {
          final status = tester.getRect(
            find.byKey(ValueKey('collaboration-$id-status')),
          );
          expect(status.top, greaterThanOrEqualTo(0));
          expect(status.bottom, lessThanOrEqualTo(56));
          expect(status.left, greaterThanOrEqualTo(0));
          expect(status.right, lessThanOrEqualTo(width));
          expect(status.overlaps(avatars), isFalse);
          expect(status.overlaps(finger), isFalse);
          final title = find.text('协作讨论笔记');
          if (title.evaluate().isNotEmpty) {
            expect(status.overlaps(tester.getRect(title)), isFalse);
          }
        }
      });
    }
  }

  for (final width in [360.0, 1280.0]) {
    testWidgets('${width.toInt()}px 状态退出各自生效，专注模式仍可退出跟随', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      var exitedFocus = 0;
      var exitedFollow = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdrawEditor(
              controller: controller,
              collaborationFocusLabel: '聚焦 · 成员A',
              collaborationFocusDescription: '正在聚焦：成员A（该创建者暂无已提交内容）',
              onExitCollaborationFocus: () => exitedFocus++,
              collaborationFollowLabel: '正在跟随 成员B · 操作画布可退出',
              onExitCollaborationFollow: () => exitedFollow++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.pump();
      try {
        expect(find.bySemanticsLabel(RegExp('该创建者暂无已提交内容')), findsWidgets);
      } finally {
        semantics.dispose();
      }
      Finder exit(String id) => find.descendant(
        of: find.byKey(ValueKey('collaboration-$id-status')),
        matching: find.byType(StudioRailIconButton),
      );
      await tester.tap(exit('focus'));
      expect(exitedFocus, 1);
      expect(exitedFollow, 0);
      final pen = await tester.startGesture(
        tester.getCenter(exit('follow')),
        kind: PointerDeviceKind.stylus,
      );
      await pen.up();
      await tester.pump();
      expect(exitedFollow, 1, reason: '笔与 InkWell 的路径不得重复触发');
      controller.toggleZenMode();
      await tester.pumpAndSettle();
      await tester.tap(exit('follow'));
      expect(exitedFollow, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄屏协作菜单分别退出聚焦和跟随，保留另一状态与成员入口', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var focus = true;
    var follow = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
            body: MarkdrawEditor(
              controller: controller,
              collaborating: true,
              collaborationParticipants: const [
                CollaborationParticipantBadge(username: '甲'),
                CollaborationParticipantBadge(username: '乙'),
              ],
              collaborationFocusLabel: focus ? '聚焦 · 甲' : null,
              collaborationFocusDescription: focus
                  ? '正在聚焦：甲（该创建者暂无已提交内容）'
                  : null,
              onExitCollaborationFocus: () => setState(() => focus = false),
              collaborationFollowLabel: follow ? '正在跟随 乙' : null,
              onExitCollaborationFollow: () => setState(() => follow = false),
              onStartCollaboration: () async {},
              onLeaveCollaboration: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final members = tester.getRect(find.byType(ParticipantAvatarStack));
    final roomSemantics = tester.getSemantics(
      find.byKey(const ValueKey('collaboration-room-control')),
    );
    try {
      expect(roomSemantics.label, contains('正在聚焦：甲'));
      expect(roomSemantics.label, contains('正在跟随 乙'));
    } finally {
      semantics.dispose();
    }
    Future<void> menu() async {
      await tester.tap(
        find.byKey(const ValueKey('collaboration-room-control')),
      );
      await tester.pumpAndSettle();
    }

    await menu();
    expect(find.textContaining('暂无已提交内容'), findsOneWidget);
    await tester.tap(find.text('退出聚焦'));
    await tester.pumpAndSettle();
    expect(focus, isFalse);
    expect(follow, isTrue);
    expect(tester.getRect(find.byType(ParticipantAvatarStack)), members);
    await menu();
    expect(find.text('退出聚焦'), findsNothing);
    expect(find.textContaining('操作画布可退出'), findsOneWidget);
    await tester.tap(find.text('退出跟随'));
    await tester.pumpAndSettle();
    expect(follow, isFalse);
    expect(tester.getRect(find.byType(ParticipantAvatarStack)), members);
    expect(tester.takeException(), isNull);
  });
}
