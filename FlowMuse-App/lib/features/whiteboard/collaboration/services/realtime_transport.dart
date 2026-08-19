import 'dart:async';

import '../models/encrypted_payload.dart';
import '../models/collaboration_room.dart';
import '../models/room_collaborator.dart';
import '../models/received_live_ink_frame.dart';

enum RealtimeConnectionStatus {
  idle,
  connecting,
  joined,
  reconnecting,
  disconnected,
  failed,
}

abstract interface class RealtimeTransport {
  Stream<EncryptedPayload> get messages;

  Stream<ReceivedLiveInkFrame> get liveInkFrames;

  Stream<String> get newUsers;

  Stream<List<RoomCollaborator>> get roomUsers;

  Stream<CollaborationRoomMetadata> get roomEnded;

  Stream<void> get firstInRoom;

  Stream<String> get errors;

  Stream<RealtimeConnectionStatus> get connectionStatus;

  String? get socketId;

  int get serverLiveInkProtocolVersion;

  int get liveInkTransportNotWritableDrops;

  Future<void> connect(String roomId);

  Future<void> send(EncryptedPayload payload, {bool volatile = false});

  Future<void> sendLiveInk(EncryptedPayload payload);

  Future<void> endRoom({String? ownerKey});

  Future<void> disconnect();
}

class DisconnectedRealtimeTransport implements RealtimeTransport {
  const DisconnectedRealtimeTransport();

  @override
  Stream<EncryptedPayload> get messages => const Stream.empty();

  @override
  Stream<ReceivedLiveInkFrame> get liveInkFrames => const Stream.empty();

  @override
  Stream<String> get newUsers => const Stream.empty();

  @override
  Stream<List<RoomCollaborator>> get roomUsers => const Stream.empty();

  @override
  Stream<CollaborationRoomMetadata> get roomEnded => const Stream.empty();

  @override
  Stream<void> get firstInRoom => const Stream.empty();

  @override
  Stream<String> get errors => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatus => const Stream.empty();

  @override
  String? get socketId => null;

  @override
  int get serverLiveInkProtocolVersion => 0;

  @override
  int get liveInkTransportNotWritableDrops => 0;

  @override
  Future<void> connect(String roomId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> endRoom({String? ownerKey}) async {}

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {}

  @override
  Future<void> sendLiveInk(EncryptedPayload payload) async {}
}

class MemoryRealtimeRoomHub {
  MemoryRealtimeRoomHub({this.liveInkProtocolVersion = 2});

  final int liveInkProtocolVersion;
  final Map<String, List<MemoryRealtimeTransport>> _rooms = {};

  bool join(String roomId, MemoryRealtimeTransport transport) {
    final transports = _rooms.putIfAbsent(roomId, () => []);
    if (!transports.contains(transport)) {
      transports.add(transport);
    }
    final users = transports
        .map((item) => RoomCollaborator.fromSocketId(item.socketId ?? ''))
        .toList();
    for (final item in transports) {
      if (!identical(item, transport)) {
        item._receiveNewUser(transport.socketId ?? '');
      }
      item._receiveRoomUsers(users);
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
    final users = transports
        .map((item) => RoomCollaborator.fromSocketId(item.socketId ?? ''))
        .toList();
    for (final item in transports) {
      item._receiveRoomUsers(users);
    }
  }

  void end(String roomId, MemoryRealtimeTransport sender) {
    final transports = _rooms.remove(roomId);
    if (transports == null) {
      return;
    }
    final metadata = CollaborationRoomMetadata.localOwner(roomId);
    for (final transport in transports) {
      transport._roomId = null;
      transport._serverLiveInkProtocolVersion = 0;
      transport._receiveRoomEnded(metadata);
      transport._receiveRoomUsers(const []);
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

  void broadcastLiveInk({
    required String roomId,
    required MemoryRealtimeTransport sender,
    required EncryptedPayload payload,
  }) {
    final transports = _rooms[roomId];
    if (transports == null) return;
    for (final transport in transports) {
      if (!identical(transport, sender)) {
        transport._receiveLiveInk(
          ReceivedLiveInkFrame(
            senderSocketId: sender.socketId ?? '',
            payload: payload,
          ),
        );
      }
    }
  }
}

class LiveInkNegotiation {
  Timer? _timer;
  String? _roomId;
  bool _accepting = false;
  int _generation = 0;
  int _version = 0;

  int get generation => _generation;
  int get version => _version;

  void begin(String roomId) {
    _generation++;
    _roomId = roomId;
    _version = 0;
    _accepting = false;
    _timer?.cancel();
    _timer = null;
  }

  void arm({Duration timeout = const Duration(seconds: 1)}) {
    _accepting = true;
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(timeout, () {
      if (generation == _generation) _accepting = false;
    });
  }

  bool accept(Object? data) {
    if (!_accepting) return false;
    _accepting = false;
    _timer?.cancel();
    _timer = null;
    if (data is! Map) return false;
    final roomId = data['roomId'];
    final version = data['liveInkProtocolVersion'];
    if (roomId != _roomId || version is! num || version.toInt() < 2) {
      return false;
    }
    _version = version.toInt();
    return true;
  }

  void reset() {
    _generation++;
    _roomId = null;
    _version = 0;
    _accepting = false;
    _timer?.cancel();
    _timer = null;
  }
}

class MemoryRealtimeTransport implements RealtimeTransport {
  MemoryRealtimeTransport({required this.hub, required String socketId})
    : _socketId = socketId;

  final MemoryRealtimeRoomHub hub;
  final String _socketId;
  final StreamController<EncryptedPayload> _messages =
      StreamController<EncryptedPayload>.broadcast();
  final StreamController<ReceivedLiveInkFrame> _liveInkFrames =
      StreamController<ReceivedLiveInkFrame>.broadcast();
  final StreamController<String> _newUsers =
      StreamController<String>.broadcast();
  final StreamController<List<RoomCollaborator>> _roomUsers =
      StreamController<List<RoomCollaborator>>.broadcast();
  final StreamController<CollaborationRoomMetadata> _roomEnded =
      StreamController<CollaborationRoomMetadata>.broadcast();
  final StreamController<void> _firstInRoom =
      StreamController<void>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final StreamController<RealtimeConnectionStatus> _connectionStatus =
      StreamController<RealtimeConnectionStatus>.broadcast();
  String? _roomId;
  int _serverLiveInkProtocolVersion = 0;
  int _liveInkTransportNotWritableDrops = 0;

  @override
  Stream<EncryptedPayload> get messages => _messages.stream;

  @override
  Stream<ReceivedLiveInkFrame> get liveInkFrames => _liveInkFrames.stream;

  @override
  Stream<String> get newUsers => _newUsers.stream;

  @override
  Stream<List<RoomCollaborator>> get roomUsers => _roomUsers.stream;

  @override
  Stream<CollaborationRoomMetadata> get roomEnded => _roomEnded.stream;

  @override
  Stream<void> get firstInRoom => _firstInRoom.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatus =>
      _connectionStatus.stream;

  @override
  String? get socketId => _socketId;

  @override
  int get serverLiveInkProtocolVersion => _serverLiveInkProtocolVersion;

  @override
  int get liveInkTransportNotWritableDrops => _liveInkTransportNotWritableDrops;

  @override
  Future<void> connect(String roomId) async {
    _serverLiveInkProtocolVersion = 0;
    _connectionStatus.add(RealtimeConnectionStatus.connecting);
    final previousRoomId = _roomId;
    if (previousRoomId != null) {
      hub.leave(previousRoomId, this);
    }
    _roomId = roomId;
    final first = hub.join(roomId, this);
    _serverLiveInkProtocolVersion = hub.liveInkProtocolVersion;
    if (first) {
      _firstInRoom.add(null);
    }
    _connectionStatus.add(RealtimeConnectionStatus.joined);
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
  Future<void> sendLiveInk(EncryptedPayload payload) async {
    final roomId = _roomId;
    if (roomId == null) {
      _liveInkTransportNotWritableDrops++;
      return;
    }
    hub.broadcastLiveInk(roomId: roomId, sender: this, payload: payload);
  }

  @override
  Future<void> endRoom({String? ownerKey}) async {
    final roomId = _roomId;
    if (roomId == null) {
      throw StateError('协作连接未建立');
    }
    hub.end(roomId, this);
    _serverLiveInkProtocolVersion = 0;
    _connectionStatus.add(RealtimeConnectionStatus.disconnected);
  }

  @override
  Future<void> disconnect() async {
    final roomId = _roomId;
    if (roomId != null) {
      hub.leave(roomId, this);
      _roomId = null;
    }
    _serverLiveInkProtocolVersion = 0;
    _connectionStatus.add(RealtimeConnectionStatus.disconnected);
  }

  void _receive(EncryptedPayload payload) {
    if (!_messages.isClosed) {
      _messages.add(payload);
    }
  }

  void _receiveLiveInk(ReceivedLiveInkFrame frame) {
    if (!_liveInkFrames.isClosed) {
      _liveInkFrames.add(frame);
    }
  }

  void _receiveNewUser(String socketId) {
    if (!_newUsers.isClosed) {
      _newUsers.add(socketId);
    }
  }

  void _receiveRoomUsers(List<RoomCollaborator> users) {
    if (!_roomUsers.isClosed) {
      _roomUsers.add(users);
    }
  }

  void _receiveRoomEnded(CollaborationRoomMetadata metadata) {
    if (!_roomEnded.isClosed) {
      _roomEnded.add(metadata);
    }
  }
}
