import 'dart:async';
import 'dart:typed_data';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../account/models/collaboration_identity.dart';
import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/room_collaborator.dart';
import 'realtime_transport.dart';

class SocketIoRealtimeTransport implements RealtimeTransport {
  SocketIoRealtimeTransport({required this.serverUrl, required this.identity});

  static const String _eventJoinRoom = 'join-room';
  static const String _eventInitRoom = 'init-room';
  static const String _eventFirstInRoom = 'first-in-room';
  static const String _eventNewUser = 'new-user';
  static const String _eventRoomUserChange = 'room-user-change';
  static const String _eventRoomError = 'room-error';
  static const String _eventLeaveRoom = 'leave-room';
  static const String _eventEndRoom = 'end-room';
  static const String _eventRoomEnded = 'room-ended';
  static const String _eventServerBroadcast = 'server-broadcast';
  static const String _eventServerVolatileBroadcast =
      'server-volatile-broadcast';
  static const String _eventClientBroadcast = 'client-broadcast';

  final String serverUrl;
  final CollaborationIdentity identity;
  final StreamController<EncryptedPayload> _messages =
      StreamController<EncryptedPayload>.broadcast();
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

  io.Socket? _socket;
  String? _roomId;

  @override
  Stream<EncryptedPayload> get messages => _messages.stream;

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
  String? get socketId => _socket?.id;

  @override
  Future<void> connect(String roomId) async {
    _roomId = roomId;
    _emitStatus(RealtimeConnectionStatus.connecting);
    final existing = _socket;
    if (existing != null && existing.connected) {
      existing.emit(_eventJoinRoom, roomId);
      await _waitForRoomJoin();
      _emitStatus(RealtimeConnectionStatus.joined);
      return;
    }

    final options = io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .disableAutoConnect()
        .enableReconnection();
    final token = identity.token;
    if (token != null && token.isNotEmpty) {
      options.setExtraHeaders({'Authorization': 'Bearer $token'});
      options.setAuth({'token': token});
    }
    final socket = io.io(serverUrl, options.build());
    _socket = socket;

    final connected = Completer<void>();
    final joined = Completer<void>();
    socket.onConnect((_) {
      if (!connected.isCompleted) {
        connected.complete();
      }
    });
    socket.onReconnect((_) {
      final activeRoomId = _roomId;
      if (activeRoomId == null) {
        return;
      }
      _emitStatus(RealtimeConnectionStatus.reconnecting);
      socket.emit(_eventJoinRoom, activeRoomId);
    });
    socket.onReconnectAttempt((_) {
      _emitStatus(RealtimeConnectionStatus.reconnecting);
    });
    socket.onReconnectError((error) {
      _emitStatus(RealtimeConnectionStatus.failed);
      if (!_errors.isClosed) {
        _errors.add('协作重连失败: $error');
      }
    });
    socket.onDisconnect((_) {
      if (_roomId != null) {
        _emitStatus(RealtimeConnectionStatus.disconnected);
      }
    });
    socket.on(_eventInitRoom, (_) {
      socket.emit(_eventJoinRoom, roomId);
    });
    socket.on(_eventFirstInRoom, (_) {
      if (!_firstInRoom.isClosed) {
        _firstInRoom.add(null);
      }
      if (!joined.isCompleted) {
        joined.complete();
      }
    });
    socket.on(_eventNewUser, (data) {
      final socketId = _socketIdFromEvent(data);
      if (socketId != null && !_newUsers.isClosed) {
        _newUsers.add(socketId);
      }
    });
    socket.on(_eventRoomUserChange, (data) {
      final roomUsers = _roomUsersFromEvent(data);
      final socketIds = roomUsers.map((item) => item.socketId).toList();
      if (!_roomUsers.isClosed) {
        _roomUsers.add(roomUsers);
      }
      if (!joined.isCompleted && socketIds.contains(socket.id)) {
        joined.complete();
      }
      if (socketIds.contains(socket.id)) {
        _emitStatus(RealtimeConnectionStatus.joined);
      }
    });
    socket.on(_eventRoomError, (data) {
      final message = data?.toString() ?? '协作房间错误';
      if (!_errors.isClosed) {
        _errors.add(message);
      }
      if (!joined.isCompleted) {
        joined.completeError(StateError(message));
      }
      _emitStatus(RealtimeConnectionStatus.failed);
    });
    socket.on(_eventRoomEnded, (data) {
      final metadata = _metadataFromEvent(data);
      if (!_roomEnded.isClosed) {
        _roomEnded.add(metadata);
      }
      _roomId = null;
      if (!_roomUsers.isClosed) {
        _roomUsers.add(const []);
      }
      _emitStatus(RealtimeConnectionStatus.disconnected);
    });
    socket.onConnectError((error) {
      if (!connected.isCompleted) {
        connected.completeError(StateError('Socket.IO connect failed: $error'));
      }
    });
    socket.onError((error) {
      if (!connected.isCompleted) {
        connected.completeError(StateError('Socket.IO error: $error'));
      }
    });
    socket.on(_eventClientBroadcast, (data) {
      final payload = _payloadFromEventData(data);
      if (payload != null && !_messages.isClosed) {
        _messages.add(payload);
      }
    });
    socket.connect();

    await connected.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('Socket.IO connect timed out'),
    );
    socket.emit(_eventJoinRoom, roomId);
    await joined.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('Socket.IO join room timed out'),
    );
    _emitStatus(RealtimeConnectionStatus.joined);
  }

  Future<void> _waitForRoomJoin() async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('协作连接未建立');
    }
    final joined = Completer<void>();
    late void Function(dynamic) roomUserHandler;
    late void Function(dynamic) roomErrorHandler;
    roomUserHandler = (data) {
      final socketIds = _roomUsersFromEvent(
        data,
      ).map((item) => item.socketId).toList();
      if (socketIds.contains(socket.id) && !joined.isCompleted) {
        joined.complete();
      }
    };
    roomErrorHandler = (data) {
      if (!joined.isCompleted) {
        joined.completeError(StateError(data?.toString() ?? '协作房间错误'));
      }
    };
    socket.on(_eventRoomUserChange, roomUserHandler);
    socket.on(_eventRoomError, roomErrorHandler);
    try {
      await joined.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('Socket.IO join room timed out'),
      );
      _emitStatus(RealtimeConnectionStatus.joined);
    } finally {
      socket.off(_eventRoomUserChange, roomUserHandler);
      socket.off(_eventRoomError, roomErrorHandler);
    }
  }

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    final roomId = _roomId;
    final socket = _socket;
    if (roomId == null || socket == null || !socket.connected) {
      throw StateError('协作连接未建立');
    }
    socket.emit(
      volatile ? _eventServerVolatileBroadcast : _eventServerBroadcast,
      [
        roomId,
        {
          'encryptedBuffer': Uint8List.fromList(payload.encryptedBuffer),
          'iv': Uint8List.fromList(payload.iv),
        },
      ],
    );
  }

  @override
  Future<void> endRoom() async {
    final roomId = _roomId;
    final socket = _socket;
    if (roomId == null || socket == null || !socket.connected) {
      throw StateError('协作连接未建立');
    }
    socket.emit(_eventEndRoom, roomId);
  }

  @override
  Future<void> disconnect() async {
    final roomId = _roomId;
    final socket = _socket;
    if (roomId != null && socket != null && socket.connected) {
      socket.emit(_eventLeaveRoom, roomId);
    }
    _roomId = null;
    _socket = null;
    socket?.dispose();
    _emitStatus(RealtimeConnectionStatus.disconnected);
  }

  void _emitStatus(RealtimeConnectionStatus status) {
    if (!_connectionStatus.isClosed) {
      _connectionStatus.add(status);
    }
  }

  EncryptedPayload? _payloadFromEventData(Object? data) {
    if (data is List && data.length >= 2) {
      return EncryptedPayload(
        encryptedBuffer: _bytes(data[0]),
        iv: _bytes(data[1]),
      );
    }
    if (data is Map) {
      return EncryptedPayload.fromJson(Map<String, Object?>.from(data));
    }
    return null;
  }

  List<int> _bytes(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return value;
    }
    if (value is List) {
      return [for (final item in value) (item as num).toInt()];
    }
    throw FormatException('Invalid Socket.IO binary payload: $value');
  }

  List<RoomCollaborator> _roomUsersFromEvent(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String)
          RoomCollaborator.fromSocketId(item)
        else if (item is Map && item['socketId'] is String)
          RoomCollaborator.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  String? _socketIdFromEvent(Object? value) {
    if (value is String) {
      return value;
    }
    if (value is Map && value['socketId'] is String) {
      return value['socketId']! as String;
    }
    return null;
  }

  CollaborationRoomMetadata _metadataFromEvent(Object? value) {
    if (value is Map) {
      return CollaborationRoomMetadata.fromJson(
        Map<String, Object?>.from(value),
      );
    }
    return CollaborationRoomMetadata(
      roomId: _roomId ?? '',
      role: CollaborationRoomRole.unknown,
      ended: true,
    );
  }
}
