import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';

void main() {
  test('生产与子目录链接正确拼接且密钥只在 fragment 中', () {
    final room = CollaborationRoom.newRoom();
    for (final entry in {
      'https://app.flowmuse.cloud/': '/whiteboard/collaboration',
      'https://qinyre.github.io/FlowMuse/':
          '/FlowMuse/whiteboard/collaboration',
      'http://localhost:8080/': '/whiteboard/collaboration',
    }.entries) {
      final uri = Uri.parse(
        room.toLink(origin: entry.key, path: '/whiteboard/collaboration'),
      );
      expect(uri.path, entry.value);
      expect(uri.query, isEmpty);
      expect(uri.removeFragment().toString().contains(room.roomKey), isFalse);
      expect(
        CollaborationRoom.parse(uri.toString()).room?.roomKey == room.roomKey,
        isTrue,
      );
    }
    for (final value in [room.toRoomValue(), '#room=${room.toRoomValue()}']) {
      expect(
        CollaborationRoom.parse(value).room?.roomKey == room.roomKey,
        isTrue,
      );
    }
  });

  test('creates and parses an Excalidraw-style collaboration room link', () {
    final room = CollaborationRoom.newRoom();
    final link = room.toLink(origin: 'https://flowmuse.local', path: '/board');

    final parsed = CollaborationRoom.tryParseLink(link);

    expect(parsed, isNotNull);
    expect(parsed!.roomId, room.roomId);
    expect(parsed.roomKey, room.roomKey);
    expect(link.contains('#room='), isTrue);
  });

  test('rejects invalid room links', () {
    expect(
      CollaborationRoom.tryParseLink('https://flowmuse.local/board'),
      isNull,
    );
    expect(
      CollaborationRoom.tryParseLink(
        'https://flowmuse.local/board#room=abc,short',
      ),
      isNull,
    );
  });
}
