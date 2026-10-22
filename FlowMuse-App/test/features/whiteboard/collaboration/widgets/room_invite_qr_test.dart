import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/widgets/room_invite_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('窄屏二维码保留完整 HTTPS 邀请，白底留白且不朗读密钥', (tester) async {
    final room = CollaborationRoom.newRoom();
    final link = room.toLink(
      origin: 'https://app.flowmuse.cloud',
      path: '/whiteboard/collaboration',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: RoomInviteQr(roomLink: link)),
          ),
        ),
      ),
    );
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(
      tester.widget<RoomInviteQr>(find.byType(RoomInviteQr)).roomLink == link,
      isTrue,
    );
    expect(qr.backgroundColor, Colors.white);
    expect(qr.padding, const EdgeInsets.all(20));
    expect(qr.semanticsLabel, '协作房间邀请二维码');
    expect(tester.getSize(find.byType(QrImageView)).width, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无效链接和非网页房间码不生成不可打开的二维码', (tester) async {
    final room = CollaborationRoom.newRoom();
    for (final value in [
      'https://app.flowmuse.cloud/library',
      room.toRoomValue(),
      'javascript:alert(1)#room=${room.toRoomValue()}',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RoomInviteQr(roomLink: value)),
        ),
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('邀请链接不可用，请复制房间码加入。'), findsOneWidget);
    }
  });
}
