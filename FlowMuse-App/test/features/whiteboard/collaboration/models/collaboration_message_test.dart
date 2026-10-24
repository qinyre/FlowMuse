import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaborator_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('视口扩展往返保留跟随和提示，旧消息可省略字段', () {
    CollaborationMessage make({String? following, String? attention}) =>
        CollaborationMessage.userVisibleSceneBounds(
          socketId: 'a',
          username: '协作者',
          sceneBounds: const {'x': 0, 'y': 0, 'width': 800, 'height': 600},
          followingSocketId: following,
          attentionId: attention,
        );
    final restored = CollaborationMessage.fromBytes(
      make(following: 'b', attention: 'request-1').toBytes(),
    );
    expect(restored.type, CollaborationMessageType.userVisibleSceneBounds);
    expect(restored.payload['followingSocketId'], 'b');
    expect(restored.payload['attentionId'], 'request-1');
    expect(make().payload.containsKey('followingSocketId'), isFalse);
    expect(make().payload.containsKey('attentionId'), isFalse);
    final presence = const CollaboratorPresence(
      socketId: 'a',
      followingSocketId: 'b',
    );
    expect(
      presence.copyWith(clearFollowingSocketId: true).followingSocketId,
      isNull,
    );
  });
  group('presence creatorKey 扩展', () {
    test('三类 presence 工厂携带 creatorKey 并进入加密前 payload', () {
      final mouse = CollaborationMessage.mouseLocation(
        socketId: 's1',
        pointer: const {'x': 1.0, 'y': 2.0},
        button: 'up',
        selectedElementIds: const {},
        username: '张三',
        creatorKey: 'user:k1',
      );
      expect(mouse.payload['creatorKey'], 'user:k1');

      final idle = CollaborationMessage.idleStatus(
        socketId: 's1',
        userState: 'active',
        username: '张三',
        creatorKey: 'user:k1',
      );
      expect(idle.payload['creatorKey'], 'user:k1');

      final bounds = CollaborationMessage.userVisibleSceneBounds(
        socketId: 's1',
        username: '张三',
        sceneBounds: const {'x': 0.0, 'y': 0.0},
        creatorKey: 'user:k1',
      );
      expect(bounds.payload['creatorKey'], 'user:k1');
    });

    test('creatorKey 缺省时 payload 不含该键（兼容旧客户端字节形态）', () {
      final idle = CollaborationMessage.idleStatus(
        socketId: 's1',
        userState: 'active',
        username: '张三',
      );
      expect(idle.payload.containsKey('creatorKey'), isFalse);
    });

    test('toBytes/fromBytes 往返保留 creatorKey', () {
      final idle = CollaborationMessage.idleStatus(
        socketId: 's1',
        userState: 'active',
        username: '张三',
        creatorKey: 'guest:roomA:u1',
      );
      final restored = CollaborationMessage.fromBytes(idle.toBytes());
      expect(restored.payload['creatorKey'], 'guest:roomA:u1');
    });
  });
}
