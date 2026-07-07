import 'dart:async';
import 'dart:typed_data';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/encrypted_payload.dart';
import 'realtime_transport.dart';

class SocketIoRealtimeTransport implements RealtimeTransport {
  SocketIoRealtimeTransport({required this.serverUrl});

  static const String _eventJoinRoom = 'join-room';
  static const String _eventInitRoom = 'init-room';
  static const String _eventFirstInRoom = 'first-in-room';
  static const String _eventNewUser = 'new-user';
  static const String _eventRoomUserChange = 'room-user-change';
  static const String _eventRoomError = 'room-error';
  static const String _eventLeaveRoom = 'leave-room';
  static const String _eventServerBroadcast = 'server-broadcast';
  static const String _eventServerVolatileBroadcast =
      'server-volatile-broadcast';
  static const String _eventClientBroadcast = 'client-broadcast';

  final String serverUrl;
  final StreamController<EncryptedPayload> _messages =
      StreamController<EncryptedPayload>.broadcast();
  final StreamController<String> _newUsers = StreamController<String>.broadcast();
  final StreamController<List<String>> _roomUsers =
      StreamController<List<String>>.broadcast();
  final StreamController<void> _firstInRoom = StreamController<void>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();

  io.Socket? _socket;
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
  String? get socketId => _socket?.id;

  @override
  Future<void> connect(String roomId) async {
    _roomId = roomId;
    final existing = _socket;
    if (existing != null && existing.connected) {
      existing.emit(_eventJoinRoom, roomId);
      return;
    }

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    final connected = Completer<void>();
    socket.onConnect((_) {
      if (!connected.isCompleted) {
        connected.complete();
      }
    });
    socket.on(_eventInitRoom, (_) {
      socket.emit(_eventJoinRoom, roomId);
    });
    socket.on(_eventFirstInRoom, (_) {
      if (!_firstInRoom.isClosed) {
        _firstInRoom.add(null);
      }
    });
    socket.on(_eventNewUser, (data) {
      if (data is String && !_newUsers.isClosed) {
        _newUsers.add(data);
      }
    });
    socket.on(_eventRoomUserChange, (data) {
      final socketIds = _socketIdsFromRoomUsers(data);
      if (!_roomUsers.isClosed) {
        _roomUsers.add(socketIds);
      }
    });
    socket.on(_eventRoomError, (data) {
      if (!_errors.isClosed) {
        _errors.add(data?.toString() ?? '协作房间错误');
      }
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
        Uint8List.fromList(payload.encryptedBuffer),
        Uint8List.fromList(payload.iv),
      ],
    );
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

  List<String> _socketIdsFromRoomUsers(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String)
          item
        else if (item is Map && item['socketId'] is String)
          item['socketId']! as String,
    ];
  }
}
