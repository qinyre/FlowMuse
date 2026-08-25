import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
