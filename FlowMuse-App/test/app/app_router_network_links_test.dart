import 'package:flow_muse/app/app_router.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('直达、旧 hash、邮件与房间链接路由不丢参数', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final router = createAppRouter();
    addTearDown(router.dispose);
    final room = CollaborationRoom.newRoom();
    final roomPath = '/whiteboard/collaboration#room=${room.toRoomValue()}';
    final cases = {
      '/': '/library',
      '/#/library': '/library',
      '/#/settings?section=other': '/settings?section=other',
      '/#/settings?section=a%26b': '/settings?section=a%26b',
      '/#//untrusted.example/': '/library',
      '/auth/verify-email?token=test-only':
          '/auth/verify-email?token=test-only',
      '/#/auth/verify-email?token=test-only':
          '/auth/verify-email?token=test-only',
      '/auth/verify-email?purpose=bind_email&token=test-only':
          '/auth/verify-email?purpose=bind_email&token=test-only',
      '/#/auth/verify-email?purpose=bind_email&token=test-only':
          '/auth/verify-email?purpose=bind_email&token=test-only',
      '/auth/reset-password?token=test-only':
          '/auth/reset-password?token=test-only',
      '/#/auth/reset-password?token=test-only':
          '/auth/reset-password?token=test-only',
      roomPath: roomPath,
      '/#$roomPath': roomPath,
      '/#room=${room.toRoomValue()}': roomPath,
    };
    var caseIndex = 0;
    for (final entry in cases.entries) {
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse(entry.key)),
            context,
          );
      expect(matches.isError, isFalse);
      // 布尔断言避免失败报告打印携带房间密钥的完整 URL。
      expect(
        matches.uri.toString() == entry.value,
        isTrue,
        reason: 'case $caseIndex',
      );
      if (entry.value == roomPath) {
        final parsed = CollaborationRoom.parse(matches.uri.toString());
        expect(parsed.room?.roomKey == room.roomKey, isTrue);
        expect(matches.uri.query, isEmpty);
      }
      caseIndex++;
    }
  });
}
