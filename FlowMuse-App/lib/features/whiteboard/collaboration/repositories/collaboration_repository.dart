import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../../editor_core/src/core/serialization/canonical_json.dart';

import '../models/collaboration_message.dart';
import '../config/live_ink_flags.dart';
import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/excalidraw_scene.dart';
import '../models/live_ink_chunk.dart';
import '../models/room_collaborator.dart';
import '../models/received_live_ink_frame.dart';
import 'collaboration_owner_key_store.dart';
import '../services/collaboration_crypto.dart';
import '../services/collaboration_debug_log.dart';
import '../services/collaboration_performance_probe.dart';
import '../services/collaboration_file_manager.dart';
import '../services/collaboration_file_store.dart';
import '../services/encrypted_scene_store.dart';
import '../services/live_ink_receive_scheduler.dart';
import '../services/realtime_transport.dart';
import '../services/change_accumulator.dart';
import '../services/scene_reconciler.dart';

class _VersionRecord {
  const _VersionRecord(this.version, this.versionNonce);
  final int version;
  final int versionNonce;
}

class CollaborationRepository {
  CollaborationRepository({
    RealtimeTransport? transport,
    EncryptedSceneStore? sceneStore,
    CollaborationFileStore? fileStore,
    CollaborationOwnerKeyStore? ownerKeyStore,
    CollaborationCrypto? crypto,
    SceneReconciler? reconciler,
    CollaborationPerformanceProbe? performanceProbe,
    this.flags = liveInkFlags,
  }) : _transport = transport ?? const DisconnectedRealtimeTransport(),
       _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
       _fileStore = fileStore,
       _ownerKeyStore = ownerKeyStore ?? CollaborationOwnerKeyStore(),
       _crypto = crypto ?? CollaborationCrypto(),
       _reconciler = reconciler ?? SceneReconciler(),
       _performanceProbe = performanceProbe,
       _accumulator = ChangeAccumulator(
         reconciler: reconciler ?? SceneReconciler(),
       ) {
    _accumulator.onFlush = _onAccumulatorFlush;
  }

  static const Duration fullSceneSyncInterval = Duration(seconds: 20);
  static const Duration fileUploadTimeout = Duration(milliseconds: 300);

  final RealtimeTransport _transport;
  final EncryptedSceneStore _sceneStore;
  final CollaborationFileStore? _fileStore;
  final CollaborationOwnerKeyStore _ownerKeyStore;
  final CollaborationCrypto _crypto;
  final SceneReconciler _reconciler;
  final CollaborationPerformanceProbe? _performanceProbe;
  final LiveInkFlags flags;
  final ChangeAccumulator _accumulator;
  final CollaborationFileManager _fileManager = CollaborationFileManager();
  final math.Random _random = math.Random();
  final Map<String, _VersionRecord> _broadcastedElementVersions = {};
  final Map<String, Map<String, Object?>> _pendingLatestElements = {};
  final Map<String, Map<String, Object?>> _pendingReliableElements = {};
  bool _reliableSendQueued = false;
  final StreamController<String> _repositoryErrors =
      StreamController<String>.broadcast();
  final StreamController<RealtimeConnectionStatus> _modeStatus =
      StreamController<RealtimeConnectionStatus>.broadcast();
  final StreamController<CollaborationMessage> _messages =
      StreamController<CollaborationMessage>.broadcast();
  final StreamController<ExcalidrawScene> _fileStatusScenes =
      StreamController<ExcalidrawScene>.broadcast();
  final StreamController<DecodedLiveInkChunk> _liveInkChunks =
      StreamController<DecodedLiveInkChunk>.broadcast();
  final List<CollaborationMessage> _messageBacklog = [];

  Timer? _fullSceneSyncTimer;
  Timer? _fileUploadTimer;
  Timer? _snapshotTimer;
  bool _snapshotSaving = false;
  bool _snapshotDirty = false;
  int _snapshotFailures = 0;
  static const Duration _snapshotIdle = Duration(seconds: 2);
  static const Duration _snapshotMaxInterval = Duration(seconds: 30);
  DateTime _lastSnapshotTime = DateTime.now();

  // Phase 0 诊断开关和指标
  static bool fullSceneSyncEnabled = true;
  int _fullSceneSyncCount = 0;
  int _batchSendCount = 0;
  int _batchElementTotal = 0;
  int _batchEncryptedBytesTotal = 0;
  final Stopwatch _batchSendStopwatch = Stopwatch();
  int _snapshotDurationAccumMs = 0;
  int _snapshotCount = 0;
  int _snapshot409Count = 0;
  DateTime _lastMetricsReport = DateTime.now();
  StreamSubscription<EncryptedPayload>? _transportMessageSubscription;
  StreamSubscription<ReceivedLiveInkFrame>? _liveInkFrameSubscription;
  StreamSubscription<DecodedLiveInkChunk>? _liveInkChunkSubscription;
  StreamSubscription<String>? _newUserSubscription;
  StreamSubscription<List<RoomCollaborator>>? _roomUsersSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _connectionSubscription;
  final Set<String> _memberIds = {};
  final Map<String, bool> _peerLiveInk = {};
  Timer? _repairTimer;
  ExcalidrawScene? _hashedScene;
  String? _sceneHash;
  int sceneRepairCount = 0;
  bool _needsReconnectRepair = false;
  LiveInkReceiveScheduler? _liveInkScheduler;
  Future<void> _messageDecodeQueue = Future<void>.value();
  int _roomSessionGeneration = 0;
  Future<void> _sendQueue = Future<void>.value();
  bool _latestSendQueued = false;
  int _sendGeneration = 0;
  CollaborationRoom? _activeRoom;
  String? _endingRoomId;
  ExcalidrawScene _latestScene = ExcalidrawScene.empty();

  String get socketId => _transport.socketId ?? 'local-client';

  bool get effectiveLiveInk =>
      flags.effectiveFor(_transport.serverLiveInkProtocolVersion);

  // Unknown/legacy peers must still see the ordinary in-progress elements.
  bool get shouldUseLiveInkV2 =>
      effectiveLiveInk &&
      _memberIds
          .where((id) => id != socketId)
          .every((id) => _peerLiveInk[id] == true);

  String get collaborationMode => shouldUseLiveInkV2 ? '实时墨迹 V2' : '兼容同步';

  String _currentSceneHash() {
    if (!identical(_hashedScene, _latestScene)) {
      final elements = List<Map<String, Object?>>.of(_latestScene.elements)
        ..sort((a, b) => _id(a).compareTo(_id(b)));
      _sceneHash = sha256
          .convert(utf8.encode(canonicalValue(elements)))
          .toString();
      _hashedScene = _latestScene;
    }
    return _sceneHash!;
  }

  Future<void> cancelLiveInk({
    required CollaborationRoom room,
    required String strokeId,
  }) async {
    if (strokeId.isEmpty || strokeId.length > 256) return;
    try {
      await _send(
        room: room,
        message: CollaborationMessage(
          type: CollaborationMessageType.inkCancel,
          payload: {'strokeId': strokeId},
        ),
      );
    } catch (error) {
      if (_activeRoom?.roomId == room.roomId) {
        _addRepositoryError('取消笔迹同步失败：$error');
      }
    }
  }

  Future<void> _sendSyncStatus(CollaborationRoom room) async {
    final generation = _roomSessionGeneration;
    try {
      await _send(
        room: room,
        message: CollaborationMessage(
          type: CollaborationMessageType.syncStatus,
          payload: {
            'protocol': 1,
            'socketId': socketId,
            'liveInkV2': flags.layeredWetInk && flags.liveInkV2,
            'sceneHash': _currentSceneHash(),
          },
        ),
      );
    } catch (error) {
      if (_isCurrentRoomSession(room, generation)) {
        _addRepositoryError('协作校验发送失败：$error');
      }
    }
  }

  Future<void> checkSynchronization() async {
    final room = _activeRoom;
    if (room == null) return;
    final generation = _roomSessionGeneration;
    await _sendSyncStatus(room);
    if (!_isCurrentRoomSession(room, generation)) return;
    final peers = _memberIds.where((id) => id != socketId);
    if (peers.any((id) => !_peerLiveInk.containsKey(id))) {
      await broadcastScene(room: room, scene: _latestScene, syncAll: true);
    }
  }

  void _receiveSyncStatus(
    CollaborationRoom room,
    CollaborationMessage message,
  ) {
    final peer = message.payload['socketId'];
    final hash = message.payload['sceneHash'];
    if (message.payload['protocol'] != 1 ||
        peer is! String ||
        peer == socketId ||
        !_memberIds.contains(peer) ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      return;
    }
    final firstStatus = !_peerLiveInk.containsKey(peer);
    final previousMode = shouldUseLiveInkV2;
    _peerLiveInk[peer] = message.payload['liveInkV2'] == true;
    if (previousMode != shouldUseLiveInkV2) {
      _modeStatus.add(RealtimeConnectionStatus.joined);
    }
    if (firstStatus) unawaited(_sendSyncStatus(room));
    if (hash == _currentSceneHash() || _repairTimer != null) return;
    final generation = _roomSessionGeneration;
    // Debounce concurrent joins/edits; one bounded repair includes tombstones.
    _repairTimer = Timer(const Duration(milliseconds: 600), () async {
      _repairTimer = null;
      if (!_isCurrentRoomSession(room, generation) ||
          hash == _currentSceneHash()) {
        return;
      }
      sceneRepairCount++;
      await broadcastScene(room: room, scene: _latestScene, syncAll: true);
    });
  }

  Stream<ReceivedLiveInkFrame> get liveInkFrames => _transport.liveInkFrames;

  Stream<DecodedLiveInkChunk> get liveInkChunks => _liveInkChunks.stream;

  int get liveInkReceiveSenderLimitDrops =>
      _liveInkScheduler?.senderLimitDrops ?? 0;

  int get liveInkReceiveDecodeErrors => _liveInkScheduler?.decodeErrors ?? 0;

  int get liveInkPendingSenderCount =>
      _liveInkScheduler?.pendingSenderCount ?? 0;

  bool get liveInkReceiveInFlight => _liveInkScheduler?.inFlight ?? false;

  int get liveInkDecodeAttempts => _liveInkScheduler?.decodeAttempts ?? 0;

  int get liveInkDecodeSuccesses => _liveInkScheduler?.decodeSuccesses ?? 0;

  int get liveInkDecodeErrors => _liveInkScheduler?.decodeErrors ?? 0;

  int get liveInkTransportNotWritableDrops =>
      _transport.liveInkTransportNotWritableDrops;

  Stream<String> get newUsers => _transport.newUsers;

  Future<bool> sendLiveInk(EncryptedPayload payload) async {
    if (!effectiveLiveInk) return false;
    return _transport.sendLiveInk(payload);
  }

  Future<bool> sendLiveInkChunk({
    required CollaborationRoom room,
    required LiveInkChunk chunk,
  }) async {
    if (!effectiveLiveInk || _activeRoom?.roomId != room.roomId) return false;
    final sessionGeneration = _roomSessionGeneration;
    final encrypted = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: CollaborationMessage.inkChunk(chunk).toBytes(),
    );
    if (!_isCurrentRoomSession(room, sessionGeneration)) return false;
    return sendLiveInk(encrypted);
  }

  Stream<List<RoomCollaborator>> get roomUsers => _transport.roomUsers;

  Stream<CollaborationRoomMetadata> get roomEnded => _transport.roomEnded
      .where(
        (metadata) =>
            metadata.ended &&
            metadata.roomId == _activeRoom?.roomId &&
            metadata.roomId != _endingRoomId,
      )
      .asyncMap((metadata) async {
        // The room is already closed: cancel pending snapshots without saving.
        await _resetLocalState();
        await _transport.disconnect();
        return metadata;
      });

  Stream<void> get firstInRoom => _transport.firstInRoom;

  Stream<String> get errors {
    return Stream.multi((controller) {
      final transportErrors = _transport.errors.listen(controller.add);
      final repositoryErrors = _repositoryErrors.stream.listen(controller.add);
      controller.onCancel = () async {
        await transportErrors.cancel();
        await repositoryErrors.cancel();
      };
    });
  }

  Stream<RealtimeConnectionStatus> get connectionStatus =>
      Stream.multi((controller) {
        final connection = _transport.connectionStatus.listen(controller.add);
        final modes = _modeStatus.stream.listen(controller.add);
        controller.onCancel = () async {
          await connection.cancel();
          await modes.cancel();
        };
      });

  Stream<CollaborationMessage> encryptedMessages(CollaborationRoom room) {
    return Stream.multi((controller) {
      if (_activeRoom?.roomId != room.roomId) {
        controller.close();
        return;
      }
      final pending = List<CollaborationMessage>.of(_messageBacklog);
      _messageBacklog.clear();
      for (final message in pending) {
        controller.add(message);
      }
      final subscription = _messages.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Stream<ExcalidrawScene> get fileStatusScenes => _fileStatusScenes.stream;

  Future<CollaborationRoom> startNewRoom({
    required ExcalidrawScene initialScene,
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    final ownerKey = _crypto.generateRoomKey();
    final ownerKeyHash = _crypto.hashOwnerKey(
      roomId: room.roomId,
      ownerKey: ownerKey,
    );
    final roomScene = _markSavedImagesPending(initialScene);
    final syncableScene = roomScene.copyWith(
      elements: _reconciler.getSyncableElements(roomScene.elements),
    );
    await _sceneStore.createRoom(
      room: room,
      scene: syncableScene.copyWith(files: const {}),
      ownerKeyHash: ownerKeyHash,
    );
    await _ownerKeyStore.writeOwnerKey(room.roomId, ownerKey);
    _activeRoom = room;
    _latestScene = syncableScene;
    _broadcastedElementVersions.clear();
    _rememberBroadcasted(syncableScene.elements);
    CollaborationDebugLog.write('repo', 'start_room', {
      'room': _shortRoomId(room.roomId),
      'elements': syncableScene.elements.length,
      'sceneVersion': _reconciler.getSceneVersion(syncableScene.elements),
      'summary': CollaborationDebugLog.elementSummary(syncableScene.elements),
    });
    await _startRoomSession(room);
    try {
      await _transport.connect(room.roomId);
    } catch (_) {
      await _resetLocalState();
      rethrow;
    }
    await _send(
      room: room,
      message: CollaborationMessage.sceneInit(elements: syncableScene.elements),
    );
    _scheduleFileUpload(room);
    _startFullSceneSync();
    return room;
  }

  Future<CollaborationRoomMetadata> loadMetadata(CollaborationRoom room) {
    return _sceneStore.loadMetadata(room);
  }

  Future<CollaborationJoinResult> joinRoom({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
    bool Function()? isCurrent,
  }) async {
    final generation = _roomSessionGeneration;
    void checkOpening() {
      if (generation != _roomSessionGeneration ||
          !(isCurrent?.call() ?? true)) {
        throw StateError('加入协作已取消');
      }
    }

    final storedScene = await _sceneStore.loadScene(room);
    checkOpening();
    if (storedScene == null) {
      throw StateError('房间不存在或尚未创建');
    }
    final metadata = await _sceneStore.joinRoom(room);
    checkOpening();
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(storedScene.elements),
    );
    _latestScene = nextScene;
    _broadcastedElementVersions.clear();
    _rememberBroadcasted(nextScene.elements);
    _activeRoom = room;
    CollaborationDebugLog.write('repo', 'join_room', {
      'room': _shortRoomId(room.roomId),
      'localElements': localScene.elements.length,
      'storedElements': storedScene.elements.length,
      'mergedElements': 0,
      'joinedElements': nextScene.elements.length,
      'sceneVersion': _reconciler.getSceneVersion(nextScene.elements),
      'summary': CollaborationDebugLog.elementSummary(nextScene.elements),
    });
    await _startRoomSession(room);
    try {
      if (!identical(_activeRoom, room) || !(isCurrent?.call() ?? true)) {
        throw StateError('加入协作已取消');
      }
      await _transport.connect(room.roomId);
      if (!identical(_activeRoom, room) || !(isCurrent?.call() ?? true)) {
        throw StateError('加入协作已取消');
      }
    } catch (_) {
      if (identical(_activeRoom, room)) {
        await _resetLocalState();
        await _transport.disconnect();
      }
      rethrow;
    }
    _startFullSceneSync();
    return CollaborationJoinResult(scene: nextScene, metadata: metadata);
  }

  Future<CollaborationRoomMetadata> endRoom() async {
    final room = _activeRoom;
    if (room == null) {
      throw StateError('协作连接未建立');
    }
    final ownerKey = await _ownerKeyStore.readOwnerKey(room.roomId);
    if (ownerKey == null || ownerKey.isEmpty) {
      throw StateError('本机缺少房主密钥，无法结束协作');
    }
    _endingRoomId = room.roomId;
    try {
      final metadata = await _sceneStore.endRoom(room, ownerKey: ownerKey);
      try {
        await _transport.endRoom(ownerKey: ownerKey);
      } catch (_) {}
      await _ownerKeyStore.clearOwnerKey(room.roomId);
      await _resetLocalState();
      await _transport.disconnect();
      return metadata;
    } finally {
      _endingRoomId = null;
    }
  }

  Future<ExcalidrawScene?> refreshFromSnapshot({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
  }) async {
    final storedScene = await _sceneStore.loadScene(room);
    if (storedScene == null) {
      return null;
    }
    final reconcileStarted = _performanceProbe?.nowMicros();
    final reconciledElements = kReleaseMode
        ? _reconciler.reconcile(
            localElements: localScene.elements,
            remoteElements: storedScene.elements,
          )
        : developer.Timeline.timeSync(
            'collaboration.reconcile',
            () => _reconciler.reconcile(
              localElements: localScene.elements,
              remoteElements: storedScene.elements,
            ),
            arguments: {
              'localElements': localScene.elements.length,
              'remoteElements': storedScene.elements.length,
            },
          );
    if (reconcileStarted != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.reconcile,
        reconcileStarted,
        itemCount: localScene.elements.length + storedScene.elements.length,
      );
    }
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(reconciledElements),
      files: {...localScene.files, ...storedScene.files},
    );
    _latestScene = nextScene;
    _rememberBroadcasted(nextScene.elements);
    return nextScene;
  }

  Future<void> broadcastScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
    bool initial = false,
    bool syncAll = false,
  }) async {
    final syncableElements = _reconciler.getSyncableElements(scene.elements);
    final syncableScene = scene.copyWith(elements: syncableElements);
    _latestScene = syncableScene;

    if (syncAll) {
      _accumulator.dispose();
      await _onAccumulatorFlush(syncableElements, initial, syncAll: true);
      return;
    }
    _accumulator.schedule(syncableScene, bypass: initial, isInitial: initial);
  }

  Future<void> broadcastElements({
    required CollaborationRoom room,
    required List<Map<String, Object?>> elements,
    bool latestOnly = false,
  }) async {
    if (_activeRoom?.roomId != room.roomId) return;
    if (elements.isEmpty) return;
    var syncable = _reconciler.getSyncableElements(elements);
    if (syncable.isEmpty) return;

    if (latestOnly) {
      final currentById = {
        for (final element in _latestScene.elements) _id(element): element,
      };
      syncable = [
        for (final element in syncable)
          if (_isAtLeastAsNew(element, currentById[_id(element)])) element,
      ];
      if (syncable.isEmpty) return;
    }

    final updates = {for (final element in syncable) _id(element): element};
    final merged = <Map<String, Object?>>[
      for (final element in _latestScene.elements)
        updates.remove(_id(element)) ?? element,
      ...updates.values,
    ];
    _latestScene = _latestScene.copyWith(
      elements: _reconciler.getSyncableElements(merged),
    );

    // Cancellation tombstones must survive congestion, just like pen-up edits.
    if (latestOnly &&
        syncable.every((element) => element['isDeleted'] != true)) {
      for (final element in syncable) {
        _pendingLatestElements[_id(element)] = element;
      }
      _queueLatestElements();
      return;
    }

    for (final element in syncable) {
      _pendingLatestElements.remove(_id(element));
    }
    _accumulator.scheduleElements(syncable);
  }

  bool _isAtLeastAsNew(
    Map<String, Object?> candidate,
    Map<String, Object?>? current,
  ) {
    if (current == null) return true;
    final candidateVersion = (candidate['version'] as num).toInt();
    final currentVersion = (current['version'] as num).toInt();
    if (candidateVersion != currentVersion) {
      return candidateVersion > currentVersion;
    }
    return (candidate['versionNonce'] as num).toInt() <=
        (current['versionNonce'] as num).toInt();
  }

  void _queueLatestElements() {
    if (_latestSendQueued || _pendingLatestElements.isEmpty) return;
    _latestSendQueued = true;
    final generation = _sendGeneration;
    final roomId = _activeRoom?.roomId;
    _sendQueue = _sendQueue
        .then<void>((_) async {
          if (_sendGeneration != generation || _activeRoom?.roomId != roomId) {
            return;
          }
          final elements = _pendingLatestElements.values.toList();
          _pendingLatestElements.clear();
          await _doAccumulatorFlush(elements, false, volatile: true);
        })
        .catchError((Object error, StackTrace stack) {
          if (_sendGeneration == generation) {
            _handleSendQueueError(error, stack);
          }
        })
        .whenComplete(() {
          if (_sendGeneration != generation) return;
          _latestSendQueued = false;
          _queueLatestElements();
        });
  }

  Future<void> _onAccumulatorFlush(
    List<Map<String, Object?>> elements,
    bool isInitial, {
    bool syncAll = false,
  }) {
    if (!isInitial && !syncAll) {
      for (final element in elements) {
        final id = _id(element);
        if (_isAtLeastAsNew(element, _pendingReliableElements[id])) {
          _pendingReliableElements[id] = element;
        }
      }
      if (_reliableSendQueued || _pendingReliableElements.isEmpty)
        return _sendQueue;
      _reliableSendQueued = true;
      final generation = _sendGeneration;
      _sendQueue = _sendQueue
          .then<void>((_) async {
            while (_sendGeneration == generation &&
                _pendingReliableElements.isNotEmpty) {
              final batch = _pendingReliableElements.values.toList();
              _pendingReliableElements.clear();
              await _doAccumulatorFlush(batch, false);
            }
          })
          .catchError((Object error, StackTrace stack) {
            if (_sendGeneration == generation)
              _handleSendQueueError(error, stack);
          })
          .whenComplete(() {
            if (_sendGeneration != generation) return;
            _reliableSendQueued = false;
            if (_pendingReliableElements.isNotEmpty)
              unawaited(_onAccumulatorFlush(const [], false));
          });
      return _sendQueue;
    }
    // Serialize sends: chain onto queue so the next flush can't start until
    // _rememberBroadcasted has completed, preventing duplicate sends.
    final generation = _sendGeneration;
    _sendQueue = _sendQueue
        .then<void>((_) async {
          if (generation != _sendGeneration) return;
          await _doAccumulatorFlush(elements, isInitial, syncAll: syncAll);
        })
        .catchError((Object error, StackTrace stack) {
          if (_sendGeneration == generation) {
            _handleSendQueueError(error, stack);
          }
        });
    return _sendQueue;
  }

  void _handleSendQueueError(Object error, StackTrace stack) {
    CollaborationDebugLog.write('repo', 'send_queue_failed', {
      'error': error.toString(),
    });
    if (!_repositoryErrors.isClosed) {
      _repositoryErrors.add('协作发送失败：$error');
    }
  }

  Future<void> _doAccumulatorFlush(
    List<Map<String, Object?>> elements,
    bool isInitial, {
    bool volatile = false,
    bool syncAll = false,
  }) async {
    final room = _activeRoom;
    if (room == null) return;
    final sessionGeneration = _roomSessionGeneration;

    final changed = isInitial || syncAll
        ? elements
        : _changedElements(elements);
    if (changed.isEmpty && !isInitial) return;

    final message = isInitial
        ? CollaborationMessage.sceneInit(elements: changed)
        : CollaborationMessage.sceneUpdate(elements: changed);

    final sentBytes = await _send(
      room: room,
      message: message,
      volatile: volatile,
    );
    if (!_isCurrentRoomSession(room, sessionGeneration)) return;
    // A dropped preview must not suppress a later reliable send of this version.
    if (!volatile) _rememberBroadcasted(changed);

    _scheduleFileUpload(room);

    _batchSendCount++;
    _batchElementTotal += changed.length;
    _batchEncryptedBytesTotal += sentBytes;
    if (!_batchSendStopwatch.isRunning) {
      _batchSendStopwatch.start();
    }

    final now = DateTime.now();
    if (now.difference(_lastMetricsReport).inSeconds >= 60) {
      final snapshotAvgMs = _snapshotCount > 0
          ? _snapshotDurationAccumMs ~/ _snapshotCount
          : 0;
      CollaborationDebugLog.write('metrics', 'phase0_summary', {
        'batchSendCount': _batchSendCount,
        'batchElementTotal': _batchElementTotal,
        'batchEncryptedBytesTotal': _batchEncryptedBytesTotal,
        'batchAvgBytes': _batchSendCount > 0
            ? _batchEncryptedBytesTotal ~/ _batchSendCount
            : 0,
        'batchElapsedMs': _batchSendStopwatch.elapsedMilliseconds,
        'fullSyncCount': _fullSceneSyncCount,
        'snapshotCount': _snapshotCount,
        'snapshotAvgMs': snapshotAvgMs,
        'snapshot409Count': _snapshot409Count,
        'snapshotDirty': _snapshotDirty,
        'snapshotSaving': _snapshotSaving,
      });
      _lastMetricsReport = now;
    }

    _scheduleSnapshot();
  }

  Future<void> broadcastMouseLocation({
    required CollaborationRoom room,
    required Map<String, Object?> pointer,
    required String button,
    required Map<String, bool> selectedElementIds,
    required String username,
    String? userId,
    String? avatarUrl,
    String? creatorKey,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.mouseLocation(
        socketId: socketId,
        pointer: pointer,
        button: button,
        selectedElementIds: selectedElementIds,
        username: username,
        userId: userId,
        avatarUrl: avatarUrl,
        creatorKey: creatorKey,
      ),
    );
  }

  Future<void> broadcastIdleStatus({
    required CollaborationRoom room,
    required String userState,
    required String username,
    String? userId,
    String? avatarUrl,
    String? creatorKey,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.idleStatus(
        socketId: socketId,
        userState: userState,
        username: username,
        userId: userId,
        avatarUrl: avatarUrl,
        creatorKey: creatorKey,
      ),
    );
  }

  Future<void> broadcastVisibleSceneBounds({
    required CollaborationRoom room,
    required String username,
    required Map<String, Object?> sceneBounds,
    String? userId,
    String? avatarUrl,
    String? creatorKey,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.userVisibleSceneBounds(
        socketId: socketId,
        username: username,
        sceneBounds: sceneBounds,
        userId: userId,
        avatarUrl: avatarUrl,
        creatorKey: creatorKey,
      ),
    );
  }

  ExcalidrawScene reconcileRemoteScene({
    required ExcalidrawScene localScene,
    required List<Map<String, Object?>> remoteElements,
    Set<String> protectedElementIds = const {},
  }) {
    final localById = {
      for (final element in localScene.elements) _id(element): element,
    };
    final remoteWinners = [
      for (final remote in remoteElements)
        if (_remoteWins(
          localById[_id(remote)],
          remote,
          protectedElementIds.contains(_id(remote)),
        ))
          remote,
    ];
    final reconcileStarted = _performanceProbe?.nowMicros();
    final reconciled = kReleaseMode
        ? _reconciler.reconcile(
            localElements: localScene.elements,
            remoteElements: remoteElements,
            protectedElementIds: protectedElementIds,
          )
        : developer.Timeline.timeSync(
            'collaboration.reconcile',
            () => _reconciler.reconcile(
              localElements: localScene.elements,
              remoteElements: remoteElements,
              protectedElementIds: protectedElementIds,
            ),
            arguments: {
              'localElements': localScene.elements.length,
              'remoteElements': remoteElements.length,
            },
          );
    if (reconcileStarted != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.reconcile,
        reconcileStarted,
        itemCount: localScene.elements.length + remoteElements.length,
      );
    }
    final nextScene = localScene.copyWith(elements: reconciled);
    _latestScene = nextScene.copyWith(
      elements: _reconciler.getSyncableElements(nextScene.elements),
    );
    _rememberBroadcasted(remoteWinners);
    return nextScene;
  }

  List<Map<String, Object?>> reconcileRemoteElements({
    required List<Map<String, Object?>> remoteElements,
    Set<String> protectedElementIds = const {},
  }) {
    final localScene = _latestScene;
    final localById = {
      for (final element in localScene.elements) _id(element): element,
    };
    final reconciled = reconcileRemoteScene(
      localScene: localScene,
      remoteElements: remoteElements,
      protectedElementIds: protectedElementIds,
    );
    // Include owner/index/bound-text repairs made by the reconciler, even
    // when the repaired element was not a raw remote winner.
    return [
      for (final element in reconciled.elements)
        if (!protectedElementIds.contains(_id(element)) &&
            !identical(element, localById[_id(element)]))
          element,
    ];
  }

  bool _remoteWins(
    Map<String, Object?>? local,
    Map<String, Object?> remote,
    bool isProtected,
  ) {
    if (local == null) return true;
    if (isProtected) return false;
    final localVersion = (local['version'] as num).toInt();
    final remoteVersion = (remote['version'] as num).toInt();
    if (remoteVersion != localVersion) return remoteVersion > localVersion;
    return (remote['versionNonce'] as num).toInt() <
        (local['versionNonce'] as num).toInt();
  }

  Future<CollaborationLoadedFilesResult> loadMissingFiles({
    required CollaborationRoom room,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) async {
    final ids = {
      for (final fileId in fileIds)
        if (!existingFileIds.contains(fileId) &&
            !_fileManager.isFileTracked(fileId))
          fileId,
    };
    final files = await _fileManager.getFiles(
      fileStore: _fileStore,
      roomId: room.roomId,
      roomKey: room.roomKey,
      fileIds: ids,
    );
    final encoded = <String, dynamic>{};
    for (final entry in files.loadedFiles.entries) {
      encoded[entry.key] = {
        'mimeType': entry.value.mimeType,
        'id': entry.key,
        'dataURL':
            'data:${entry.value.mimeType};base64,${base64Encode(entry.value.bytes)}',
        'created': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return CollaborationLoadedFilesResult(
      files: encoded,
      erroredFileIds: files.erroredFileIds,
    );
  }

  Future<void> _startRoomSession(CollaborationRoom room) async {
    await _stopRoomSession();
    _sendGeneration++;
    _pendingLatestElements.clear();
    _pendingReliableElements.clear();
    _reliableSendQueued = false;
    _latestSendQueued = false;
    _sendQueue = Future<void>.value();
    final sessionGeneration = _roomSessionGeneration;
    _accumulator.dispose();
    _accumulator.onFlush = _onAccumulatorFlush;
    _messageBacklog.clear();
    _messageDecodeQueue = Future<void>.value();
    final liveInkScheduler = LiveInkReceiveScheduler(
      decode: (frame) => _decodeLiveInkFrame(room, frame),
    );
    _liveInkScheduler = liveInkScheduler;
    _liveInkChunkSubscription = liveInkScheduler.chunks.listen((decoded) {
      if (_activeRoom?.roomId == room.roomId) {
        _liveInkChunks.add(decoded);
      }
    });
    _liveInkFrameSubscription = _transport.liveInkFrames.listen((frame) {
      if (_activeRoom?.roomId == room.roomId && effectiveLiveInk) {
        liveInkScheduler.add(frame);
      }
    });
    _transportMessageSubscription = _transport.messages.listen(
      (payload) {
        final enqueuedMicros = _performanceProbe?.nowMicros();
        final liveInkWorkAtEnqueue =
            liveInkScheduler.inFlight ||
            liveInkScheduler.pendingSenderCount > 0;
        CollaborationDebugLog.write('wire', 'payload_received', {
          'room': _shortRoomId(room.roomId),
          'encryptedBytes': payload.encryptedBuffer.length,
          'ivBytes': payload.iv.length,
        });
        _messageDecodeQueue = _messageDecodeQueue
            .then(
              (_) => _handleEncryptedPayload(
                room,
                payload,
                sessionGeneration,
                enqueuedMicros,
                liveInkWorkAtEnqueue,
              ),
            )
            .catchError((Object error) {
              CollaborationDebugLog.write('repo', 'message_queue_failed', {
                'error': error,
              });
              _addRepositoryError('协作消息处理失败：$error');
            });
      },
      onError: (Object error) {
        CollaborationDebugLog.write('repo', 'message_stream_failed', {
          'error': error,
        });
        _addRepositoryError('协作消息接收失败：$error');
      },
    );
    _newUserSubscription = _transport.newUsers.listen((newSocketId) {
      final activeRoom = _activeRoom;
      if (activeRoom == null ||
          activeRoom.roomId != room.roomId ||
          _latestScene.elements.isEmpty) {
        return;
      }
      unawaited(
        Future<void>.delayed(Duration.zero, () async {
          if (!_isCurrentRoomSession(room, sessionGeneration)) return;
          final providers = _memberIds.where((id) => id != newSocketId).toList()
            ..sort();
          if (providers.isNotEmpty && providers.first != socketId) return;
          await _sendSceneInitToNewUser(activeRoom, newSocketId);
        }),
      );
    });
    _roomUsersSubscription = _transport.roomUsers.listen((users) {
      _memberIds
        ..clear()
        ..addAll(users.map((user) => user.socketId));
      _peerLiveInk.removeWhere((id, _) => !_memberIds.contains(id));
      unawaited(_sendSyncStatus(room));
    });
    _connectionSubscription = _transport.connectionStatus.listen((status) {
      if (status == RealtimeConnectionStatus.disconnected ||
          status == RealtimeConnectionStatus.reconnecting) {
        _needsReconnectRepair = true;
        _peerLiveInk.clear();
      } else if (status == RealtimeConnectionStatus.joined &&
          _needsReconnectRepair) {
        _needsReconnectRepair = false;
        unawaited(checkSynchronization());
      }
    });
  }

  Future<void> _handleEncryptedPayload(
    CollaborationRoom room,
    EncryptedPayload payload,
    int sessionGeneration,
    int? enqueuedMicros,
    bool liveInkWorkAtEnqueue,
  ) async {
    if (!_isCurrentRoomSession(room, sessionGeneration)) {
      return;
    }
    if (enqueuedMicros != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.reliableQueueWait,
        enqueuedMicros,
        itemCount: liveInkWorkAtEnqueue ? 1 : 0,
        byteCount: payload.encryptedBuffer.length + payload.iv.length,
      );
    }
    try {
      final decryptStarted = _performanceProbe?.nowMicros();
      final decryptTask = kReleaseMode
          ? null
          : (developer.TimelineTask()..start(
              'collaboration.decrypt',
              arguments: {
                'room': _shortRoomId(room.roomId),
                'encryptedBytes': payload.encryptedBuffer.length,
              },
            ));
      late final List<int> bytes;
      try {
        bytes = await _crypto.decrypt(
          roomKey: room.roomKey,
          encryptedPayload: payload,
        );
      } finally {
        decryptTask?.finish();
      }
      if (!_isCurrentRoomSession(room, sessionGeneration)) return;
      if (decryptStarted != null) {
        _performanceProbe!.recordSince(
          CollaborationPerformanceStage.decrypt,
          decryptStarted,
          byteCount: payload.encryptedBuffer.length + payload.iv.length,
        );
      }
      final decodeStarted = _performanceProbe?.nowMicros();
      final message = kReleaseMode
          ? CollaborationMessage.fromBytes(bytes)
          : developer.Timeline.timeSync(
              'collaboration.json_decode',
              () => CollaborationMessage.fromBytes(bytes),
              arguments: {'plainBytes': bytes.length},
            );
      if (decodeStarted != null) {
        _performanceProbe!.recordSince(
          CollaborationPerformanceStage.jsonDecode,
          decodeStarted,
          itemCount: message.elements.length,
          byteCount: bytes.length,
        );
      }
      if (!_isCurrentRoomSession(room, sessionGeneration)) return;
      final target = message.payload['targetSocketId'];
      if (message.type == CollaborationMessageType.sceneInit &&
          target is String &&
          target != socketId) {
        return;
      }
      if (message.type == CollaborationMessageType.syncStatus) {
        _receiveSyncStatus(room, message);
        return;
      }
      CollaborationDebugLog.write('crypto', 'decoded', {
        'room': _shortRoomId(room.roomId),
        'type': message.type.wireName,
        'elements': message.elements.length,
        'summary': CollaborationDebugLog.elementSummary(message.elements),
      });
      if (_messages.hasListener) {
        _messages.add(message);
      } else {
        CollaborationDebugLog.write('repo', 'message_backlogged', {
          'type': message.type.wireName,
        });
        _messageBacklog.add(message);
      }
    } catch (error) {
      if (!_isCurrentRoomSession(room, sessionGeneration)) return;
      CollaborationDebugLog.write('crypto', 'decrypt_failed', {
        'room': _shortRoomId(room.roomId),
        'error': error,
      });
      _addRepositoryError('协作消息解密失败：$error');
    }
  }

  Future<LiveInkChunk> _decodeLiveInkFrame(
    CollaborationRoom room,
    ReceivedLiveInkFrame frame,
  ) async {
    if (_activeRoom?.roomId != room.roomId) {
      throw const FormatException('Live ink room is no longer active');
    }
    final bytes = await _crypto.decrypt(
      roomKey: room.roomKey,
      encryptedPayload: frame.payload,
    );
    if (_activeRoom?.roomId != room.roomId) {
      throw const FormatException('Live ink room changed during decrypt');
    }
    final chunk = CollaborationMessage.fromBytes(bytes).liveInkChunk;
    if (chunk == null) {
      throw const FormatException('Live ink payload is not INK_CHUNK');
    }
    return chunk;
  }

  Future<void> _sendSceneInitToNewUser(
    CollaborationRoom room,
    String targetSocketId,
  ) async {
    try {
      await _send(
        room: room,
        targetSocketId: targetSocketId,
        message: CollaborationMessage(
          type: CollaborationMessageType.sceneInit,
          payload: {
            'elements': _latestScene.elements,
            'targetSocketId': targetSocketId,
          },
        ),
      );
    } catch (error) {
      _addRepositoryError('协作初始化同步失败：$error');
    }
  }

  Future<void> _stopRoomSession() async {
    _roomSessionGeneration++;
    _repairTimer?.cancel();
    _repairTimer = null;
    _memberIds.clear();
    _peerLiveInk.clear();
    _hashedScene = null;
    _sceneHash = null;
    _needsReconnectRepair = false;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _snapshotSaving = false;
    _snapshotDirty = false;
    _snapshotFailures = 0;
    _lastSnapshotTime = DateTime.now();
    final transportMessages = _transportMessageSubscription;
    _transportMessageSubscription = null;
    final liveInkFrames = _liveInkFrameSubscription;
    _liveInkFrameSubscription = null;
    final liveInkChunks = _liveInkChunkSubscription;
    _liveInkChunkSubscription = null;
    final liveInkScheduler = _liveInkScheduler;
    _liveInkScheduler = null;
    final newUsers = _newUserSubscription;
    _newUserSubscription = null;
    await Future.wait([
      if (_roomUsersSubscription != null) _roomUsersSubscription!.cancel(),
      if (_connectionSubscription != null) _connectionSubscription!.cancel(),
      if (transportMessages != null) transportMessages.cancel(),
      if (liveInkFrames != null) liveInkFrames.cancel(),
      if (liveInkChunks != null) liveInkChunks.cancel(),
      if (newUsers != null) newUsers.cancel(),
    ]);
    _roomUsersSubscription = null;
    _connectionSubscription = null;
    if (liveInkScheduler != null) await liveInkScheduler.close();
    _messageDecodeQueue = Future<void>.value();
    _messageBacklog.clear();
  }

  bool _isCurrentRoomSession(CollaborationRoom room, int sessionGeneration) =>
      _roomSessionGeneration == sessionGeneration &&
      _activeRoom?.roomId == room.roomId;

  void _addRepositoryError(String message) {
    if (!_repositoryErrors.isClosed) {
      _repositoryErrors.add(message);
    }
  }

  Future<int> _send({
    required CollaborationRoom room,
    required CollaborationMessage message,
    bool volatile = false,
    String? targetSocketId,
  }) async {
    final sessionGeneration = _roomSessionGeneration;
    if (!_isCurrentRoomSession(room, sessionGeneration)) return 0;
    final encodeStarted = _performanceProbe?.nowMicros();
    final plainBytes = kReleaseMode
        ? message.toBytes()
        : developer.Timeline.timeSync(
            'collaboration.json_encode',
            message.toBytes,
            arguments: {
              'type': message.type.wireName,
              'elements': message.elements.length,
            },
          );
    if (encodeStarted != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.jsonEncode,
        encodeStarted,
        itemCount: message.elements.length,
        byteCount: plainBytes.length,
      );
    }
    final encryptStarted = _performanceProbe?.nowMicros();
    final encryptTask = kReleaseMode
        ? null
        : (developer.TimelineTask()..start(
            'collaboration.encrypt',
            arguments: {
              'room': _shortRoomId(room.roomId),
              'plainBytes': plainBytes.length,
            },
          ));
    late final EncryptedPayload encrypted;
    try {
      encrypted = await _crypto.encrypt(
        roomKey: room.roomKey,
        plainBytes: plainBytes,
      );
    } finally {
      encryptTask?.finish();
    }
    if (!_isCurrentRoomSession(room, sessionGeneration)) return 0;
    if (encryptStarted != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.encrypt,
        encryptStarted,
        byteCount: encrypted.encryptedBuffer.length + encrypted.iv.length,
      );
    }
    CollaborationDebugLog.write('wire', 'send_message', {
      'room': _shortRoomId(room.roomId),
      'type': message.type.wireName,
      'volatile': volatile,
      'elements': message.elements.length,
      'encryptedBytes': encrypted.encryptedBuffer.length,
      'ivBytes': encrypted.iv.length,
      'summary': CollaborationDebugLog.elementSummary(message.elements),
    });
    final transportStarted = _performanceProbe?.nowMicros();
    final transportTask = kReleaseMode
        ? null
        : (developer.TimelineTask()..start(
            'collaboration.transport_send',
            arguments: {
              'room': _shortRoomId(room.roomId),
              'encryptedBytes': encrypted.encryptedBuffer.length,
              'volatile': volatile,
            },
          ));
    try {
      final transport = _transport;
      if (targetSocketId != null && transport is TargetedRealtimeTransport) {
        await (transport as TargetedRealtimeTransport).sendTo(
          encrypted,
          targetSocketId,
        );
      } else {
        await transport.send(encrypted, volatile: volatile);
      }
    } finally {
      transportTask?.finish();
    }
    if (transportStarted != null) {
      _performanceProbe!.recordSince(
        CollaborationPerformanceStage.transportSend,
        transportStarted,
        byteCount: encrypted.encryptedBuffer.length + encrypted.iv.length,
      );
    }
    return encrypted.encryptedBuffer.length + encrypted.iv.length;
  }

  void _scheduleFileUpload(CollaborationRoom room) {
    if (_fileUploadTimer?.isActive ?? false) {
      return;
    }
    _fileUploadTimer = Timer(fileUploadTimeout, () {
      _fileUploadTimer = null;
      unawaited(_flushQueuedFileUpload(room));
    });
  }

  Future<void> _flushQueuedFileUpload(CollaborationRoom room) async {
    if (_activeRoom?.roomId != room.roomId) {
      return;
    }
    try {
      final result = await _fileManager.saveFiles(
        fileStore: _fileStore,
        roomId: room.roomId,
        roomKey: room.roomKey,
        elements: _latestScene.elements,
        filesJson: _latestScene.files,
      );
      if (result.savedFileIds.isEmpty && result.erroredFileIds.isEmpty) {
        return;
      }
      final nextScene = _updateImageStatuses(
        _latestScene,
        savedFileIds: result.savedFileIds,
        erroredFileIds: result.erroredFileIds,
      );
      if (identical(nextScene, _latestScene)) {
        return;
      }
      _latestScene = nextScene;
      if (!_fileStatusScenes.isClosed) {
        _fileStatusScenes.add(nextScene);
      }
      unawaited(broadcastScene(room: room, scene: nextScene));
    } catch (error) {
      _addRepositoryError('图片文件同步失败，图形和文字会继续同步：$error');
    }
  }

  Future<ExcalidrawScene> _saveSceneResolvingConflict({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    try {
      await _sceneStore.saveScene(
        room: room,
        scene: scene.copyWith(files: const {}),
      );
      return scene;
    } on StaleSceneSnapshotException {
      _snapshot409Count++;
      final storedScene = await _sceneStore.loadScene(room);
      if (storedScene == null) {
        rethrow;
      }
      final reconcileStarted = _performanceProbe?.nowMicros();
      final reconciledElements = kReleaseMode
          ? _reconciler.reconcile(
              localElements: scene.elements,
              remoteElements: storedScene.elements,
            )
          : developer.Timeline.timeSync(
              'collaboration.reconcile',
              () => _reconciler.reconcile(
                localElements: scene.elements,
                remoteElements: storedScene.elements,
              ),
              arguments: {
                'localElements': scene.elements.length,
                'remoteElements': storedScene.elements.length,
              },
            );
      if (reconcileStarted != null) {
        _performanceProbe!.recordSince(
          CollaborationPerformanceStage.reconcile,
          reconcileStarted,
          itemCount: scene.elements.length + storedScene.elements.length,
        );
      }
      final mergedScene = scene.copyWith(
        elements: _reconciler.getSyncableElements(reconciledElements),
      );
      await _sceneStore.saveScene(
        room: room,
        scene: mergedScene.copyWith(files: const {}),
      );
      return mergedScene;
    }
  }

  void _scheduleSnapshot() {
    _snapshotDirty = true;
    // New edits must not defeat an active failure backoff.
    if (_snapshotSaving ||
        (_snapshotFailures > 0 && (_snapshotTimer?.isActive ?? false))) {
      return;
    }
    _snapshotTimer?.cancel();

    final sinceLast = DateTime.now().difference(_lastSnapshotTime);
    final delay = _snapshotFailures > 0
        ? Duration(seconds: math.min(1 << _snapshotFailures, 30))
        : sinceLast >= _snapshotMaxInterval
        ? Duration.zero
        : _snapshotIdle;

    _snapshotTimer = Timer(delay, _flushSnapshot);
  }

  Future<void> _flushSnapshot() async {
    _snapshotTimer = null;
    if (!_snapshotDirty) return;
    if (_snapshotSaving) return; // single-flight

    final room = _activeRoom;
    if (room == null) return;

    final sessionGeneration = _roomSessionGeneration;
    _snapshotSaving = true;
    _snapshotDirty = false;
    final sw = Stopwatch()..start();
    try {
      final scene = _latestScene;
      await _saveSceneResolvingConflict(
        room: room,
        scene: scene.copyWith(files: const {}),
      );
      if (!_isCurrentRoomSession(room, sessionGeneration)) return;
      _lastSnapshotTime = DateTime.now();
      _snapshotFailures = 0;
    } catch (error) {
      if (!_isCurrentRoomSession(room, sessionGeneration)) return;
      _snapshotFailures = math.min(_snapshotFailures + 1, 5);
      if (!_repositoryErrors.isClosed) {
        _repositoryErrors.add('协作快照保存失败：$error');
      }
      _snapshotDirty = true;
    } finally {
      sw.stop();
      if (_isCurrentRoomSession(room, sessionGeneration)) {
        _snapshotDurationAccumMs += sw.elapsedMilliseconds;
        _snapshotCount++;
        _snapshotSaving = false;
        if (_snapshotDirty) {
          _scheduleSnapshot();
        }
      }
    }
  }

  Future<void> forceFlushSnapshot() async {
    while (_snapshotSaving) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    if (_snapshotDirty) {
      await _flushSnapshot();
    }
    while (_snapshotSaving) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  ExcalidrawScene _markSavedImagesPending(ExcalidrawScene scene) {
    var changed = false;
    final elements = <Map<String, Object?>>[];
    for (final element in scene.elements) {
      if (element['type'] == 'image' && element['status'] == 'saved') {
        changed = true;
        elements.add(_bumpElement({...element, 'status': 'pending'}));
      } else {
        elements.add(element);
      }
    }
    return changed ? scene.copyWith(elements: elements) : scene;
  }

  ExcalidrawScene _updateImageStatuses(
    ExcalidrawScene scene, {
    required Set<String> savedFileIds,
    required Set<String> erroredFileIds,
  }) {
    var changed = false;
    final elements = [
      for (final element in scene.elements)
        _updatedImageStatusElement(
          element,
          savedFileIds: savedFileIds,
          erroredFileIds: erroredFileIds,
          onChanged: () => changed = true,
        ),
    ];
    if (!changed) {
      return scene;
    }
    CollaborationDebugLog.write('file_manager', 'status_scene_updated', {
      'saved': savedFileIds.map(_shortFileId).toList(),
      'errored': erroredFileIds.map(_shortFileId).toList(),
      'sceneVersion': _reconciler.getSceneVersion(elements),
    });
    return scene.copyWith(elements: elements);
  }

  Map<String, Object?> _updatedImageStatusElement(
    Map<String, Object?> element, {
    required Set<String> savedFileIds,
    required Set<String> erroredFileIds,
    required void Function() onChanged,
  }) {
    if (element['type'] != 'image') {
      return element;
    }
    final fileId = element['fileId'];
    if (fileId is! String) {
      return element;
    }
    final nextStatus = savedFileIds.contains(fileId)
        ? 'saved'
        : erroredFileIds.contains(fileId)
        ? 'error'
        : null;
    if (nextStatus == null || element['status'] == nextStatus) {
      return element;
    }
    onChanged();
    return _bumpElement({...element, 'status': nextStatus});
  }

  Map<String, Object?> _bumpElement(Map<String, Object?> element) {
    final version = (element['version'] as num?)?.toInt() ?? 1;
    return {
      ...element,
      'version': version + 1,
      'versionNonce': _random.nextInt(1 << 31),
      'updated': DateTime.now().millisecondsSinceEpoch,
    };
  }

  List<Map<String, Object?>> _changedElements(
    List<Map<String, Object?>> elements,
  ) {
    return [
      for (final element in elements)
        if (!_broadcastedElementVersions.containsKey(_id(element)) ||
            _isNewerThanBroadcasted(element))
          element,
    ];
  }

  bool _isNewerThanBroadcasted(Map<String, Object?> element) {
    final record = _broadcastedElementVersions[_id(element)]!;
    final v = (element['version'] as num).toInt();
    final n = (element['versionNonce'] as num).toInt();
    if (v > record.version) return true;
    if (v < record.version) return false;
    return n < record.versionNonce; // 同版本 nonce 小者胜（对齐 _shouldKeepLocal）
  }

  void _rememberBroadcasted(List<Map<String, Object?>> elements) {
    for (final element in elements) {
      _broadcastedElementVersions[_id(element)] = _VersionRecord(
        (element['version'] as num).toInt(),
        (element['versionNonce'] as num).toInt(),
      );
    }
  }

  void _startFullSceneSync() {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final room = _activeRoom;
      if (room == null) return;
      if (!fullSceneSyncEnabled) return;
      if (_snapshotSaving) return;

      _fullSceneSyncCount++;
      CollaborationDebugLog.write('scene', 'full_sync_triggered', {
        'room': _shortRoomId(room.roomId),
        'count': _fullSceneSyncCount,
        'elements': _latestScene.elements.length,
      });
      unawaited(checkSynchronization());
    });
  }

  String _id(Map<String, Object?> element) => element['id']! as String;

  String _shortRoomId(String roomId) =>
      roomId.length > 8 ? roomId.substring(0, 8) : roomId;

  String _shortFileId(String fileId) =>
      fileId.length > 8 ? fileId.substring(0, 8) : fileId;

  Future<void> stop() async {
    await forceFlushSnapshot();
    await _resetLocalState();
    await _transport.disconnect();
  }

  Future<void> _resetLocalState() async {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = null;
    _fileUploadTimer?.cancel();
    _fileUploadTimer = null;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _snapshotSaving = false;
    _snapshotDirty = false;
    await _stopRoomSession();
    _activeRoom = null;
    _latestScene = ExcalidrawScene.empty();
    _broadcastedElementVersions.clear();
    _pendingLatestElements.clear();
    _pendingReliableElements.clear();
    _reliableSendQueued = false;
    _fileManager.reset();
    _accumulator.dispose();
    _sendGeneration++;
    _latestSendQueued = false;
    _sendQueue = Future<void>.value();
  }
}

class CollaborationJoinResult {
  const CollaborationJoinResult({required this.scene, required this.metadata});

  final ExcalidrawScene scene;
  final CollaborationRoomMetadata metadata;
}

class CollaborationLoadedFilesResult {
  const CollaborationLoadedFilesResult({
    required this.files,
    required this.erroredFileIds,
  });

  final Map<String, dynamic> files;
  final Set<String> erroredFileIds;
}
