import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flow_muse/features/account/models/collaboration_identity.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_creator_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('登录用户键跨房间稳定、不含 roomId、不同用户不同', () {
    final k1 = creatorKeyForUserId('user-1');
    final k2 = creatorKeyForUserId('user-1');
    final k3 = creatorKeyForUserId('user-2');
    expect(k1, k2);
    expect(k1.startsWith('user:'), isTrue);
    expect(k1.contains('room'), isFalse);
    expect(k1, isNot(k3));
    expect(
      k1,
      'user:${sha256.convert(utf8.encode('flowmuse-creator-v1|user-1')).toString()}',
    );
  });

  test('游客键 = guest:roomId:sessionUuid；同会话稳定，换会话改变', () {
    expect(creatorKeyForGuest('roomA', 'uuid-1'), 'guest:roomA:uuid-1');
    expect(
      creatorKeyForGuest('roomA', 'uuid-1'),
      creatorKeyForGuest('roomA', 'uuid-1'),
    );
    expect(
      creatorKeyForGuest('roomA', 'uuid-1'),
      isNot(creatorKeyForGuest('roomA', 'uuid-2')),
    );
    expect(
      creatorKeyForGuest('roomA', 'uuid-1'),
      isNot(creatorKeyForGuest('roomB', 'uuid-1')),
    );
  });

  test('creatorForIdentity 按身份选择键并快照名字', () {
    final guest = CollaborationIdentity.guest('游客甲');
    final guestCreator = creatorForIdentity(
      identity: guest,
      roomId: 'roomA',
      guestSessionId: 'uuid-1',
    );
    expect(guestCreator.creatorKey, 'guest:roomA:uuid-1');
    expect(guestCreator.isGuest, isTrue);
    expect(guestCreator.displayName, '游客甲');

    final user = CollaborationIdentity(
      username: '张三',
      isGuest: false,
      userId: 'user-9',
    );
    final userCreator = creatorForIdentity(
      identity: user,
      roomId: 'roomB',
      guestSessionId: 'ignored',
    );
    expect(userCreator.creatorKey, creatorKeyForUserId('user-9'));
    expect(userCreator.isGuest, isFalse);
  });
}
