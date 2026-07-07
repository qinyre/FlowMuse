import 'dart:async';

import '../models/encrypted_payload.dart';

abstract interface class RealtimeTransport {
  Stream<EncryptedPayload> get messages;

  Stream<String> get newUsers;

  Stream<List<String>> get roomUsers;

  Stream<void> get firstInRoom;

  Stream<String> get errors;

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
  Stream<String> get newUsers => const Stream.empty();

  @override
  Stream<List<String>> get roomUsers => const Stream.empty();

  @override
  Stream<void> get firstInRoom => const Stream.empty();

  @override
  Stream<String> get errors => const Stream.empty();

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

  bool join(String roomId, MemoryRealtimeTransport transport) {
    final transports = _rooms.putIfAbsent(roomId, () => []);
    if (!transports.contains(transport)) {
      transports.add(transport);
    }
    final socketIds = transports.map((item) => item.socketId ?? '').toList();
    for (final item in transports) {
      if (!identical(item, transport)) {
        item._receiveNewUser(transport.socketId ?? '');
      }
      item._receiveRoomUsers(socketIds);
    }
    return transports.length == 1;
  }

  void leave(String roomId, MemoryRealtimeTransport transport) {
    final transports = _rooms[roomId];
    if (transports == null) {
      return;
    }
    transports.remove(transport);
    if (transports.isEmpty) {
      _rooms.remove(roomId);
      return;
    }
    final socketIds = transports.map((item) => item.socketId ?? '').toList();
    for (final item in transports) {
      item._receiveRoomUsers(socketIds);
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
  final StreamController<String> _newUsers = StreamController<String>.broadcast();
  final StreamController<List<String>> _roomUsers =
      StreamController<List<String>>.broadcast();
  final StreamController<void> _firstInRoom = StreamController<void>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  String? _roomId;

  @override
  Stream<EncryptedPayload> get messages => _messages.stream;

  @override
  Stream<String> get newUsers => _newUsers.stream;

  @override
  Stream<List<String>> get roomUsers => _roomUsers.stream;

  @override
  Stream<void> get firstInRoom => _firstInRoom.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  String? get socketId => _socketId;

  @override
  Future<void> connect(String roomId) async {
    final previousRoomId = _roomId;
    if (previousRoomId != null) {
      hub.leave(previousRoomId, this);
    }
    _roomId = roomId;
    final first = hub.join(roomId, this);
    if (first) {
      _firstInRoom.add(null);
    }
  }

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    final roomId = _roomId;
    if (roomId == null) {
      throw StateError('协作连接未建立');
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

  void _receiveNewUser(String socketId) {
    if (!_newUsers.isClosed) {
      _newUsers.add(socketId);
    }
  }

  void _receiveRoomUsers(List<String> socketIds) {
    if (!_roomUsers.isClosed) {
      _roomUsers.add(socketIds);
    }
  }
}
