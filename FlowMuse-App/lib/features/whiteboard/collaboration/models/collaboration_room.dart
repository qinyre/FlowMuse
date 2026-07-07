import 'dart:math';

import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';

class CollaborationRoom {
  const CollaborationRoom({required this.roomId, required this.roomKey});

  static final RegExp _roomHashPattern = RegExp(
    r'^#room=([a-zA-Z0-9_-]+),([a-zA-Z0-9_-]{22})$',
  );
  static const int _roomIdBytes = 10;
  static final Random _random = Random.secure();

  final String roomId;
  final String roomKey;

  factory CollaborationRoom.newRoom({CollaborationCrypto? crypto}) {
    final idBytes = List<int>.generate(
      _roomIdBytes,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return CollaborationRoom(
      roomId: idBytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      roomKey: (crypto ?? CollaborationCrypto()).generateRoomKey(),
    );
  }

  String toLink({required String origin, required String path}) {
    return '$origin$path#room=$roomId,$roomKey';
  }

  String toRoomValue() {
    return '$roomId,$roomKey';
  }

  static CollaborationRoom? tryParseLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) {
      return null;
    }
    final match = _roomHashPattern.firstMatch(
      uri.fragment.isEmpty ? '' : '#${uri.fragment}',
    );
    if (match == null) {
      return null;
    }
    return CollaborationRoom(roomId: match.group(1)!, roomKey: match.group(2)!);
  }
}
