import 'dart:async';

import '../models/encrypted_payload.dart';

abstract interface class RealtimeTransport {
  Stream<EncryptedPayload> get messages;

  String? get socketId;

  Future<void> connect(String roomId);

  Future<void> send(EncryptedPayload payload, {bool volatile = false});

  Future<void> disconnect();
}

class DisconnectedRealtimeTransport implements RealtimeTransport {
  const DisconnectedRealtimeTransport();

  @override
  Stream<EncryptedPayload> get messages => const Stream.empty();

  @override
  String? get socketId => null;

  @override
  Future<void> connect(String roomId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {}
}

class MemoryRealtimeRoomHub {
  final Map<String, List<MemoryRealtimeTransport>> _rooms = {};

  void join(String roomId, MemoryRealtimeTransport transport) {
    final transports = _rooms.putIfAbsent(roomId, () => []);
    if (!transports.contains(transport)) {
      transports.add(transport);
    }
  }

  void leave(String roomId, MemoryRealtimeTransport transport) {
    final transports = _rooms[roomId];
    if (transports == null) {
      return;
    }
    transports.remove(transport);
    if (transports.isEmpty) {
      _rooms.remove(roomId);
    }
  }

  void broadcast({
    required String roomId,
    required MemoryRealtimeTransport sender,
    required EncryptedPayload payload,
  }) {
    final transports = _rooms[roomId];
    if (transports == null) {
      return;
    }
    for (final transport in transports) {
      if (identical(transport, sender)) {
        continue;
      }
      transport._receive(payload);
    }
  }
}

class MemoryRealtimeTransport implements RealtimeTransport {
  MemoryRealtimeTransport({required this.hub, required String socketId})
    : _socketId = socketId;

  final MemoryRealtimeRoomHub hub;
  final String _socketId;
  final StreamController<EncryptedPayload> _messages =
      StreamController<EncryptedPayload>.broadcast();
  String? _roomId;

  @override
  Stream<EncryptedPayload> get messages => _messages.stream;

  @override
  String? get socketId => _socketId;

  @override
  Future<void> connect(String roomId) async {
    final previousRoomId = _roomId;
    if (previousRoomId != null) {
      hub.leave(previousRoomId, this);
    }
    _roomId = roomId;
    hub.join(roomId, this);
  }

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    final roomId = _roomId;
    if (roomId == null) {
      return;
    }
    hub.broadcast(roomId: roomId, sender: this, payload: payload);
  }

  @override
  Future<void> disconnect() async {
    final roomId = _roomId;
    if (roomId != null) {
      hub.leave(roomId, this);
      _roomId = null;
    }
  }

  void _receive(EncryptedPayload payload) {
    if (!_messages.isClosed) {
      _messages.add(payload);
    }
  }
}
