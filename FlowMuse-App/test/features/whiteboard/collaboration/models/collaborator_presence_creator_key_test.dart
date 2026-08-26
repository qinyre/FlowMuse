import 'package:flow_muse/features/whiteboard/collaboration/models/collaborator_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CollaboratorPresence 新增可空 creatorKey 并可 copyWith', () {
    const presence = CollaboratorPresence(socketId: 's1', username: '张三');
    expect(presence.creatorKey, isNull);
    final updated = presence.copyWith(creatorKey: 'user:k1');
    expect(updated.creatorKey, 'user:k1');
    expect(updated.socketId, 's1');
    expect(updated.username, '张三');
    // 不传时保留
    expect(presence.copyWith(username: '李四').creatorKey, isNull);
    expect(updated.copyWith(username: '李四').creatorKey, 'user:k1');
  });
}
