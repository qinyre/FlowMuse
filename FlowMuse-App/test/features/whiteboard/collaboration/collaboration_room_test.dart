import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';

void main() {
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
