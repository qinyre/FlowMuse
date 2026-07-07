import 'dart:math';

import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';

class CollaborationRoom {
  const CollaborationRoom({required this.roomId, required this.roomKey});

  static final RegExp _roomValuePattern = RegExp(
    r'^([a-zA-Z0-9_-]+),([a-zA-Z0-9_-]{22})$',
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
    return parse(link).room;
  }

  static CollaborationRoomParseResult parse(String value) {
    final input = value.trim();
    if (input.isEmpty) {
      return const CollaborationRoomParseResult.empty();
    }
    final direct = _parseRoomValue(input);
    if (direct != null) {
      return CollaborationRoomParseResult.room(direct);
    }
    if (input.startsWith('#room=')) {
      final room = _parseRoomValue(input.substring('#room='.length));
      return room == null
          ? const CollaborationRoomParseResult.invalid()
          : CollaborationRoomParseResult.room(room);
    }
    if (input.startsWith('room=')) {
      final room = _parseRoomValue(input.substring('room='.length));
      return room == null
          ? const CollaborationRoomParseResult.invalid()
          : CollaborationRoomParseResult.room(room);
    }

    final uri = Uri.tryParse(input);
    if (uri == null) {
      return const CollaborationRoomParseResult.invalid();
    }
    final fragment = uri.fragment;
    if (fragment.startsWith('room=')) {
      final room = _parseRoomValue(fragment.substring('room='.length));
      return room == null
          ? const CollaborationRoomParseResult.invalid()
          : CollaborationRoomParseResult.room(room);
    }
    return const CollaborationRoomParseResult.invalid();
  }

  static CollaborationRoom? _parseRoomValue(String value) {
    final match = _roomValuePattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return CollaborationRoom(roomId: match.group(1)!, roomKey: match.group(2)!);
  }
}

enum CollaborationRoomParseError { empty, invalid }

class CollaborationRoomParseResult {
  const CollaborationRoomParseResult._({this.room, this.error});

  const CollaborationRoomParseResult.empty()
    : this._(error: CollaborationRoomParseError.empty);

  const CollaborationRoomParseResult.invalid()
    : this._(error: CollaborationRoomParseError.invalid);

  const CollaborationRoomParseResult.room(CollaborationRoom room)
    : this._(room: room);

  final CollaborationRoom? room;
  final CollaborationRoomParseError? error;

  bool get isValid => room != null;
}
