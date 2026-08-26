import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('badge 点击触发 onTap；禁用态（无 creatorKey）不触发', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ParticipantAvatarStack(
              participants: [
                CollaborationParticipantBadge(
                  username: 'A',
                  creatorKey: 'user:a',
                  onTap: () => tapped++,
                ),
                // 禁用态用户名用单字：头像只渲染首字符（AccountAvatar 取
                // username 首字渲染），多字名 find.text 找不到完整串
                const CollaborationParticipantBadge(username: '客'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('A'), findsWidgets);
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(tapped, 1);

    // 禁用态：旧游客（无 creatorKey、无 onTap）点击无任何效果、不抛异常
    await tester.tap(find.text('客'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('+N 打开完整参与者列表并可点击第 6+ 位聚焦', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ParticipantAvatarStack(
              participants: [
                for (var i = 0; i < 5; i++)
                  CollaborationParticipantBadge(
                    username: 'P$i',
                    creatorKey: 'user:p$i',
                    onTap: () => tapped++,
                  ),
                CollaborationParticipantBadge(
                  username: '第六人',
                  creatorKey: 'user:p5',
                  onTap: () => tapped++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    // 完整列表包含被折叠的第 6 位
    expect(find.text('第六人'), findsOneWidget);
    await tester.tap(find.text('第六人'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
