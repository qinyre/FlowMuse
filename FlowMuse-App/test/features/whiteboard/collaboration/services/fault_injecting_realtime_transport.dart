import 'dart:async';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/received_live_ink_frame.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/room_collaborator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

class LiveInkFaultModel {
  const LiveInkFaultModel({
    this.seed = 1,
    this.dropRate = 0,
    this.duplicateRate = 0,
    this.reorderWindow = 1,
    this.minDelay = Duration.zero,
    this.maxDelay = Duration.zero,
  }) : assert(dropRate >= 0 && dropRate <= 1),
       assert(duplicateRate >= 0 && duplicateRate <= 1),
       assert(reorderWindow > 0);

  final int seed;
  final double dropRate;
  final double duplicateRate;
  final int reorderWindow;
  final Duration minDelay;
  final Duration maxDelay;
}

/// Test-only wrapper. Reliable messages bypass the injected live faults.
class FaultInjectingRealtimeTransport implements RealtimeTransport {
  FaultInjectingRealtimeTransport({
    required RealtimeTransport delegate,
    required LiveInkFaultModel model,
  }) : _delegate = delegate,
       _model = model,
       _random = math.Random(model.seed);

  final RealtimeTransport _delegate;
  final LiveInkFaultModel _model;
  final math.Random _random;
  final List<_PendingLiveFrame> _pending = [];
  final Set<Future<void>> _scheduled = {};
  int _generation = 0;
  String? _roomId;

  int acceptedCount = 0;
  int emittedCount = 0;
  int droppedCount = 0;
  int duplicateCount = 0;
  int maxPendingCount = 0;
  int connectionGeneration = 0;

  String? get roomId => _roomId;
  int get pendingCount => _pending.length + _scheduled.length;

  @override
  Stream<EncryptedPayload> get messages => _delegate.messages;

  @override
  Stream<ReceivedLiveInkFrame> get liveInkFrames => _delegate.liveInkFrames;

  @override
  Stream<String> get newUsers => _delegate.newUsers;

  @override
  Stream<List<RoomCollaborator>> get roomUsers => _delegate.roomUsers;

  @override
  Stream<CollaborationRoomMetadata> get roomEnded => _delegate.roomEnded;

  @override
  Stream<void> get firstInRoom => _delegate.firstInRoom;

  @override
  Stream<String> get errors => _delegate.errors;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatus =>
      _delegate.connectionStatus;

  @override
  String? get socketId => _delegate.socketId;

  @override
  int get serverLiveInkProtocolVersion =>
      _delegate.serverLiveInkProtocolVersion;

  @override
  int get liveInkTransportNotWritableDrops =>
      _delegate.liveInkTransportNotWritableDrops;

  @override
  Future<void> connect(String roomId) async {
    _dropPending();
    connectionGeneration++;
    _roomId = roomId;
    await _delegate.connect(roomId);
  }

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) =>
      _delegate.send(payload, volatile: volatile);

  @override
  Future<void> sendLiveInk(EncryptedPayload payload) async {
    acceptedCount++;
    if (_random.nextDouble() < _model.dropRate) {
      droppedCount++;
      return;
    }
    _pending.add(_PendingLiveFrame(payload, _generation));
    if (_random.nextDouble() < _model.duplicateRate) {
      duplicateCount++;
      _pending.add(_PendingLiveFrame(payload, _generation));
    }
    maxPendingCount = math.max(maxPendingCount, _pending.length);
    if (_pending.length >= _model.reorderWindow) {
      _scheduleOne();
    }
  }

  Future<void> flushLiveInk() async {
    while (_pending.isNotEmpty) {
      _scheduleOne();
    }
    while (_scheduled.isNotEmpty) {
      await Future.wait(_scheduled.toList(growable: false));
    }
  }

  void _scheduleOne() {
    final index = _random.nextInt(_pending.length);
    final pending = _pending.removeAt(index);
    final minMicros = _model.minDelay.inMicroseconds;
    final spreadMicros =
        _model.maxDelay.inMicroseconds - _model.minDelay.inMicroseconds;
    final delay = Duration(
      microseconds:
          minMicros +
          (spreadMicros == 0 ? 0 : _random.nextInt(spreadMicros + 1)),
    );
    late final Future<void> scheduled;
    scheduled = Future<void>.delayed(delay, () async {
      if (pending.generation != _generation || _roomId == null) {
        droppedCount++;
        return;
      }
      await _delegate.sendLiveInk(pending.payload);
      emittedCount++;
    }).whenComplete(() => _scheduled.remove(scheduled));
    _scheduled.add(scheduled);
  }

  @override
  Future<void> endRoom({String? ownerKey}) async {
    _dropPending();
    _roomId = null;
    await _delegate.endRoom(ownerKey: ownerKey);
  }

  @override
  Future<void> disconnect() async {
    _dropPending();
    _roomId = null;
    await _delegate.disconnect();
  }

  void _dropPending() {
    _generation++;
    droppedCount += _pending.length;
    _pending.clear();
  }
}

class _PendingLiveFrame {
  const _PendingLiveFrame(this.payload, this.generation);

  final EncryptedPayload payload;
  final int generation;
}
