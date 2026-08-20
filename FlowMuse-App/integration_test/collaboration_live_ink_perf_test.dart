import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_performance_probe.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_sender.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_report.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/writing_performance_manifest.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/whiteboard/collaboration/services/fault_injecting_realtime_transport.dart';

const _perfTestEnabled = bool.fromEnvironment('FLOWMUSE_PERF_TEST');
const _measureSeconds = int.fromEnvironment(
  'FLOWMUSE_MEASURE_SECONDS',
  defaultValue: 300,
);
const _localEventTargetMicros = int.fromEnvironment(
  'FLOWMUSE_EVENT_TO_PAINT_TARGET_MICROS',
);
const _p1BaselineP95Micros = int.fromEnvironment(
  'FLOWMUSE_P1_BASELINE_P95_MICROS',
);
const _deviceClass = String.fromEnvironment('FLOWMUSE_DEVICE_CLASS');
const _deviceId = String.fromEnvironment('FLOWMUSE_DEVICE_ID');
const _physicalDevice = bool.fromEnvironment('FLOWMUSE_PHYSICAL_DEVICE');
const _style = LiveInkStyle(
  brushType: 'fountainPen',
  strokeColor: '#1e1e1e',
  strokeWidth: 2,
  opacity: 100,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 repository 到 RemoteWetInkPainter 的 2/5 sender 门禁', (
    tester,
  ) async {
    expect(
      _perfTestEnabled,
      isTrue,
      reason: '性能入口仅允许通过 FLOWMUSE_PERF_TEST=true 启用',
    );
    final requestedV2 = layeredWetInkEnabled && liveInkFlags.liveInkV2;
    final refreshHz = ui
        .PlatformDispatcher
        .instance
        .views
        .first
        .display
        .refreshRate
        .round();
    if (!requestedV2) {
      final result = await _runDisabledMatrixCase();
      expect(result['effective'], isFalse);
      expect(result['emitCount'], 0);
      binding.reportData = {
        'schemaVersion': 1,
        'measurementEligible': kProfileMode,
        'buildMode': kProfileMode ? 'profile' : 'not_profile',
        'platform': defaultTargetPlatform.name,
        'physicalDevice': _physicalDevice,
        'deviceId': _deviceId,
        'deviceClass': _deviceClass,
        'refreshHz': refreshHz,
        'mode': 'collaboration_live_ink',
        'requestedLayeredWetInk': layeredWetInkEnabled,
        'requestedLiveInkV2': liveInkFlags.liveInkV2,
        'results': [result],
      };
      return;
    }
    expect(
      _measureSeconds,
      greaterThanOrEqualTo(60),
      reason: 'live ink Profile 门禁至少持续 60 秒',
    );
    expect(
      _localEventTargetMicros,
      frozenEventToPaintTargetMicros(refreshHz),
      reason: 'P0 event-to-paint 目标必须由实测刷新率的冻结 manifest 推导',
    );
    expect(
      _p1BaselineP95Micros,
      greaterThan(0),
      reason: '真机门禁必须显式传入冻结的 P1 P95',
    );

    final senderScaleEvidence = await _measureSenderScaleEvidence();
    for (final row
        in senderScaleEvidence['raw']! as List<Map<String, Object?>>) {
      expect(
        row['pointEntries'],
        lessThanOrEqualTo(3 * (row['acceptedPoints']! as int)),
      );
      expect(row['maxRepeats'], lessThanOrEqualTo(3));
    }
    expect(senderScaleEvidence['bytesRSquared'], greaterThanOrEqualTo(0.99));
    expect(
      senderScaleEvidence['pointEntriesRSquared'],
      greaterThanOrEqualTo(0.99),
    );
    final results = <Map<String, Object?>>[];
    for (final memberCount in [2, 5]) {
      for (final network in const [
        _NetworkCase(
          'good',
          Duration(milliseconds: 5),
          Duration(milliseconds: 15),
          1,
          0,
          0,
        ),
        _NetworkCase(
          'rtt100',
          Duration(milliseconds: 50),
          Duration(milliseconds: 50),
          1,
          0,
          0,
        ),
        _NetworkCase(
          'fault10',
          Duration.zero,
          Duration(milliseconds: 120),
          5,
          0.1,
          0.1,
        ),
        _NetworkCase(
          'fault20',
          Duration.zero,
          Duration(milliseconds: 120),
          5,
          0.2,
          0.1,
        ),
      ]) {
        results.add(
          await _runScenario(
            tester,
            memberCount: memberCount,
            network: network,
          ),
        );
      }
    }
    for (final result in results) {
      expect(result['effective'], isTrue);
      expect(result['emitCount'], greaterThan(0));
      expect(result['paintCount'], greaterThan(0));
      expect(result['localAcceptedCount'], greaterThan(0));
      expect(result['localPaintedCount'], greaterThan(0));
      expect(result['finalConverged'], isTrue);
      expect(result['wetInkRemaining'], 0);
      expect(result['pendingCount'], 0);
      expect(result['receiverPendingCount'], 0);
      expect(result['receiverInFlight'], isFalse);
      expect(result['liveEmitsWhileReliablePending'], greaterThan(0));
      expect(result['liveReceivesWhileReliablePending'], greaterThan(0));
      expect(result['reliableLoadedOverlapSamples'], 20);
      expect(result['reconnectCount'], 1);
      final network = result['network'];
      final remoteP95 = result['remotePaintP95Micros']! as int;
      if (network == 'good') {
        expect(remoteP95, lessThanOrEqualTo(200000));
      } else if (network == 'rtt100') {
        expect(remoteP95, lessThanOrEqualTo(300000));
      }
      if (network == 'good' || network == 'rtt100') {
        expect(result['remotePaintSampleCoverage'], greaterThanOrEqualTo(0.95));
      }
      if (network == 'good' && result['memberCount'] == 5) {
        expect(result['maxSenderStarvationMicros'], lessThanOrEqualTo(200000));
      }
      final baseline = result['reliableBaselineP95Micros']! as int;
      final loaded = result['reliableLoadedP95Micros']! as int;
      expect(loaded, lessThanOrEqualTo((baseline * 1.10).ceil()));
      final localP95 = result['localEventToPaintP95Micros']! as int;
      expect(localP95, lessThanOrEqualTo(_localEventTargetMicros));
      expect(localP95, lessThanOrEqualTo((_p1BaselineP95Micros * 1.05).ceil()));
    }
    binding.reportData = {
      'schemaVersion': 1,
      'measurementEligible': kProfileMode,
      'buildMode': kProfileMode ? 'profile' : 'not_profile',
      'platform': defaultTargetPlatform.name,
      'physicalDevice': _physicalDevice,
      'deviceId': _deviceId,
      'deviceClass': _deviceClass,
      'refreshHz': refreshHz,
      'mode': 'collaboration_live_ink',
      'requestedLayeredWetInk': layeredWetInkEnabled,
      'requestedLiveInkV2': liveInkFlags.liveInkV2,
      'measureSeconds': _measureSeconds,
      'senderScaleEvidence': senderScaleEvidence,
      'results': results,
    };
  });
}

Future<Map<String, Object?>> _runDisabledMatrixCase() async {
  final hub = MemoryRealtimeRoomHub();
  final transport = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
  final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
  final repository = CollaborationRepository(
    transport: transport,
    flags: liveInkFlags,
  );
  var emitCount = 0;
  await receiver.connect('room');
  final subscription = receiver.liveInkFrames.listen((_) => emitCount++);
  await transport.connect('room');
  await repository.sendLiveInkChunk(
    room: const CollaborationRoom(
      roomId: 'room',
      roomKey: 'AAAAAAAAAAAAAAAAAAAAAA',
    ),
    chunk: const LiveInkChunk(
      strokeId: 'disabled',
      startIndex: 0,
      points: [LiveInkPoint(x: 0, y: 0)],
      style: _style,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  final result = <String, Object?>{
    'effective': repository.effectiveLiveInk,
    'emitCount': emitCount,
    'readyGeneration': transport.liveInkNegotiationGeneration,
    'readyRoom': transport.liveInkNegotiatedRoomId,
    'readyVersion': transport.serverLiveInkProtocolVersion,
  };
  await subscription.cancel();
  await transport.disconnect();
  await receiver.disconnect();
  return result;
}

Future<Map<String, Object?>> _runScenario(
  WidgetTester tester, {
  required int memberCount,
  required _NetworkCase network,
}) async {
  final crypto = CollaborationCrypto();
  final room = CollaborationRoom.newRoom(crypto: crypto);
  final sceneStore = MemoryEncryptedSceneStore();
  await sceneStore.createRoom(
    room: room,
    scene: ExcalidrawScene.empty(),
    ownerKeyHash: 'fixture',
  );
  final hub = MemoryRealtimeRoomHub();
  final runClock = Stopwatch()..start();
  final receiverProbe = CollaborationPerformanceProbe(
    nowMicros: () => runClock.elapsedMicroseconds,
  );
  final receiver = CollaborationRepository(
    transport: MemoryRealtimeTransport(hub: hub, socketId: 'receiver'),
    sceneStore: sceneStore,
    crypto: crypto,
    flags: liveInkFlags,
    performanceProbe: receiverProbe,
  );
  final transports = <FaultInjectingRealtimeTransport>[];
  final senders = <CollaborationRepository>[];
  for (var index = 0; index < memberCount; index++) {
    final transport = FaultInjectingRealtimeTransport(
      delegate: MemoryRealtimeTransport(hub: hub, socketId: 'sender-$index'),
      model: LiveInkFaultModel(
        seed: 20260820 + index,
        dropRate: network.dropRate,
        duplicateRate: network.duplicateRate,
        reorderWindow: network.reorderWindow,
        minDelay: network.minOneWayDelay,
        maxDelay: network.maxOneWayDelay,
      ),
    );
    transports.add(transport);
    senders.add(
      CollaborationRepository(
        transport: transport,
        sceneStore: sceneStore,
        crypto: crypto,
        flags: liveInkFlags,
      ),
    );
  }
  await receiver.joinRoom(room: room, localScene: ExcalidrawScene.empty());
  for (final sender in senders) {
    await sender.joinRoom(room: room, localScene: ExcalidrawScene.empty());
  }

  final wetInk = RemoteWetInkStore();
  var receiveCount = 0;
  var reliableLoadActive = false;
  var liveReceivesWhileReliablePending = 0;
  final lastReceiveMicros = <String, int>{};
  var maxStarvationMicros = 0;
  final liveSubscription = receiver.liveInkChunks.listen((decoded) {
    receiveCount++;
    if (reliableLoadActive) {
      liveReceivesWhileReliablePending++;
    }
    final now = runClock.elapsedMicroseconds;
    final previous = lastReceiveMicros[decoded.senderSocketId];
    if (previous != null) {
      maxStarvationMicros = math.max(maxStarvationMicros, now - previous);
    }
    lastReceiveMicros[decoded.senderSocketId] = now;
    wetInk.apply(decoded);
  });
  var receiverScene = ExcalidrawScene.empty();
  var awaitedReliableVersion = -1;
  var reliableLoadedOverlapSamples = 0;
  Completer<void>? reliableApplied;
  final messageSubscription = receiver.encryptedMessages(room).listen((
    message,
  ) {
    if (message.type != CollaborationMessageType.sceneUpdate) return;
    wetInk.finalizeStrokes(
      message.elements
          .where((element) => element['type'] == 'freedraw')
          .map((element) => element['id'])
          .whereType<String>(),
    );
    receiverScene = receiver.reconcileRemoteScene(
      localScene: receiverScene,
      remoteElements: message.elements,
    );
    final marker = message.elements
        .where((element) => element['id'] == 'reliable-marker')
        .firstOrNull;
    if (marker?['version'] == awaitedReliableVersion &&
        reliableApplied?.isCompleted == false) {
      reliableApplied!.complete();
    }
  });

  final localProbe = ActivePreviewMetricsProbe();
  final controller = MarkdrawController(
    writingFlags: writingFeatureFlags,
    activePreviewMetricsProbe: localProbe,
  );
  controller.switchTool(ToolType.freedraw);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarkdrawEditor(
          controller: controller,
          remoteWetInkStore: wetInk,
          config: const MarkdrawEditorConfig(
            showToolbar: false,
            showPropertyPanel: false,
            showZoomControls: false,
            showHelpButton: false,
            showLibraryPanel: false,
            showMarkdownButton: false,
            showMenu: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final canvasRect = tester.getRect(find.byType(EditorCanvas));
  Future<List<int>> measureReliable({
    required int firstVersion,
    required List<Map<String, Object?>> extraElements,
    int iterations = 20,
    Duration interSampleDelay = Duration.zero,
    bool requireLiveDecodeOverlap = false,
  }) async {
    final samples = <int>[];
    var probeCursor = receiverProbe.samples.length;
    for (var offset = 0; offset < iterations; offset++) {
      final version = firstVersion + offset;
      var liveWorkAtSampleStart = false;
      if (requireLiveDecodeOverlap) {
        for (var attempt = 0; attempt < 1000; attempt++) {
          liveWorkAtSampleStart =
              receiver.liveInkReceiveInFlight ||
              receiver.liveInkPendingSenderCount > 0;
          if (liveWorkAtSampleStart) break;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      awaitedReliableVersion = version;
      reliableApplied = Completer<void>();
      await senders.first.broadcastScene(
        room: room,
        scene: ExcalidrawScene.empty().copyWith(
          elements: [_reliableMarker(version), ...extraElements],
        ),
        syncAll: true,
      );
      await reliableApplied!.future.timeout(const Duration(seconds: 5));
      final newSamples = receiverProbe.samples
          .skip(probeCursor)
          .where(
            (sample) =>
                sample.stage == CollaborationPerformanceStage.reliableQueueWait,
          );
      expect(newSamples, isNotEmpty);
      samples.add(newSamples.last.durationMicros);
      probeCursor = receiverProbe.samples.length;
      if (requireLiveDecodeOverlap) {
        expect(
          liveWorkAtSampleStart,
          isTrue,
          reason: '每个 loaded reliable 样本开始时必须已有真实 live 解密或排队工作',
        );
        reliableLoadedOverlapSamples++;
      }
      if (interSampleDelay > Duration.zero) {
        await Future<void>.delayed(interSampleDelay);
      }
    }
    samples.sort();
    return samples;
  }

  final reliableBaseline = await measureReliable(
    firstVersion: 1,
    extraElements: const [],
  );
  final frameTimings = FrameTimingMetricsCollector()..start();
  final localGesture = await tester.startGesture(
    canvasRect.topLeft + const Offset(30, 30),
    kind: PointerDeviceKind.stylus,
  );
  final latencyMicros = <int>[];
  final acceptedMicros = <String, Map<int, int>>{};
  var acceptedPaintMarkerCount = 0;
  var liveEmitsWhileReliablePending = 0;
  final senderPoints = <List<LiveInkPoint>>[
    for (var index = 0; index < senders.length; index++) <LiveInkPoint>[],
  ];
  final liveSenders = <LiveInkSender>[
    for (var senderIndex = 0; senderIndex < senders.length; senderIndex++)
      LiveInkSender(
        emit: (chunk) async {
          await senders[senderIndex].sendLiveInkChunk(room: room, chunk: chunk);
          if (reliableLoadActive) {
            liveEmitsWhileReliablePending++;
          }
        },
      ),
  ];
  for (var senderIndex = 0; senderIndex < liveSenders.length; senderIndex++) {
    liveSenders[senderIndex].start(
      strokeId: 'stroke-$senderIndex',
      style: _style,
    );
  }
  Future<List<int>>? reliableLoadedFuture;
  var paintCount = 0;
  final lastPaintedRevision = <String, int>{};
  void collectPaintSamples(RemoteWetInkRenderCache cache) {
    final paintedAtMicros = runClock.elapsedMicroseconds;
    for (var senderIndex = 0; senderIndex < senders.length; senderIndex++) {
      final strokeId = 'stroke-$senderIndex';
      final paintedRevision = cache.paintedRevision(strokeId);
      if (paintedRevision == null ||
          paintedRevision == lastPaintedRevision[strokeId]) {
        continue;
      }
      lastPaintedRevision[strokeId] = paintedRevision;
      final markers = acceptedMicros[strokeId];
      if (markers == null) continue;
      final paintedMarkers = markers.entries
          .where((entry) => cache.wasPointPainted(strokeId, entry.key))
          .toList(growable: false);
      for (final marker in paintedMarkers) {
        markers.remove(marker.key);
        paintCount++;
        latencyMicros.add(paintedAtMicros - marker.value);
      }
    }
  }

  var maxReceiverPendingSenders = 0;
  var receiverInFlightObserved = false;
  var maxTransportPending = 0;
  var reconnectCount = 0;
  final deadline = Duration(seconds: _measureSeconds);
  final liveClock = Stopwatch()..start();
  var packetIndex = 0;
  while (liveClock.elapsed < deadline) {
    for (var senderIndex = 0; senderIndex < senders.length; senderIndex++) {
      final points = senderPoints[senderIndex];
      final strokeId = 'stroke-$senderIndex';
      acceptedPaintMarkerCount++;
      acceptedMicros.putIfAbsent(strokeId, () => <int, int>{})[points.length] =
          runClock.elapsedMicroseconds;
      points.add(
        LiveInkPoint(x: packetIndex.toDouble(), y: senderIndex * 10.0),
      );
      final tailStart = math.max(0, points.length - LiveInkChunk.maxPoints);
      liveSenders[senderIndex].offerTail(
        totalCount: points.length,
        startIndex: tailStart,
        points: points.sublist(tailStart),
      );
    }
    final usableWidth = math.max(1.0, canvasRect.width - 60);
    final usableHeight = math.max(1.0, canvasRect.height - 60);
    await localGesture.moveTo(
      canvasRect.topLeft +
          Offset(
            30 + (packetIndex * 3.0) % usableWidth,
            30 + (packetIndex * 2.0) % usableHeight,
          ),
    );
    await tester.pump(const Duration(milliseconds: 33));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RemoteWetInkPainter>()
        .single;
    collectPaintSamples(painter.cache);
    maxReceiverPendingSenders = math.max(
      maxReceiverPendingSenders,
      receiver.liveInkPendingSenderCount,
    );
    receiverInFlightObserved =
        receiverInFlightObserved || receiver.liveInkReceiveInFlight;
    if (reliableLoadedFuture == null && receiver.liveInkDecodeSuccesses > 0) {
      reliableLoadActive = true;
      reliableLoadedFuture = measureReliable(
        firstVersion: 21,
        extraElements: const [],
        interSampleDelay: const Duration(milliseconds: 250),
        requireLiveDecodeOverlap: true,
      ).whenComplete(() => reliableLoadActive = false);
    }
    maxTransportPending = math.max(
      maxTransportPending,
      transports.fold(0, (sum, item) => sum + item.pendingCount),
    );
    if (reconnectCount == 0 &&
        liveClock.elapsedMicroseconds >= deadline.inMicroseconds ~/ 2) {
      await transports.last.disconnect();
      await transports.last.connect(room.roomId);
      reconnectCount++;
    }
    packetIndex++;
  }
  await localGesture.up();
  await tester.pump();
  frameTimings.stop();
  for (var senderIndex = 0; senderIndex < liveSenders.length; senderIndex++) {
    final points = senderPoints[senderIndex];
    final tailStart = math.max(0, points.length - LiveInkChunk.maxPoints);
    liveSenders[senderIndex].finishTail(
      totalCount: points.length,
      startIndex: tailStart,
      points: points.sublist(tailStart),
    );
  }
  while (liveSenders.any((sender) => sender.inFlight || sender.hasPending)) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    reliableLoadedFuture,
    isNotNull,
    reason: 'loaded reliable 门禁必须在真实 live 解密 warm-up 后启动',
  );
  final reliableLoaded = await reliableLoadedFuture!;
  for (final transport in transports) {
    await transport.flushLiveInk();
  }
  for (var attempt = 0; attempt < 5000; attempt++) {
    if (!receiver.liveInkReceiveInFlight &&
        receiver.liveInkPendingSenderCount == 0) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pump();
  final flushedPainter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<RemoteWetInkPainter>()
      .single;
  collectPaintSamples(flushedPainter.cache);

  final finalElements = [
    for (var index = 0; index < senders.length; index++)
      _freedrawElement('stroke-$index', packetIndex),
  ];
  await measureReliable(
    firstVersion: 41,
    extraElements: finalElements,
    iterations: 1,
  );
  final finalScene = ExcalidrawScene.empty().copyWith(
    elements: [_reliableMarker(41), ...finalElements],
  );
  await tester.pump();
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<RemoteWetInkPainter>()
      .single;

  final accepted = transports.fold(0, (sum, item) => sum + item.acceptedCount);
  final emitted = transports.fold(0, (sum, item) => sum + item.emittedCount);
  final dropped = transports.fold(0, (sum, item) => sum + item.droppedCount);
  final pending = transports.fold(0, (sum, item) => sum + item.pendingCount);
  latencyMicros.sort();
  final localPerformance = WritingPerformanceReport.capture(
    activePreview: localProbe,
    frames: frameTimings.frames,
  );
  final localEventToPaint =
      localProbe.samples
          .map((sample) => sample.eventToPaintMicros)
          .whereType<int>()
          .toList()
        ..sort();
  final result = <String, Object?>{
    'memberCount': memberCount,
    'senderCount': senders.length,
    'participantCount': senders.length + 1,
    'network': network.name,
    'effective':
        receiver.effectiveLiveInk &&
        senders.every((item) => item.effectiveLiveInk),
    'readyGeneration': transports
        .map((item) => item.liveInkNegotiationGeneration)
        .toList(),
    'readyRoom': transports
        .map((item) => item.liveInkNegotiatedRoomId)
        .toList(),
    'readyVersion': transports
        .map((item) => item.serverLiveInkProtocolVersion)
        .toList(),
    'acceptedCount': accepted,
    'emitCount': emitted,
    'receiveCount': receiveCount,
    'liveDecryptAttemptCount': receiver.liveInkDecodeAttempts,
    'liveDecryptSuccessCount': receiver.liveInkDecodeSuccesses,
    'liveDecryptErrorCount': receiver.liveInkDecodeErrors,
    'paintCount': paintCount,
    'localAcceptedCount': localPerformance.accepted,
    'localPaintedCount': localPerformance.painted,
    'localEventToPaintP95Micros': _nearestRank(localEventToPaint, 0.95),
    'localEventTargetMicros': _localEventTargetMicros,
    'p1BaselineP95Micros': _p1BaselineP95Micros,
    'localPerformance': localPerformance.toJson(),
    'recordedGeometryPointCount': painter.cache.recordedGeometryPointCount,
    'dropCount': dropped,
    'pendingCount': pending,
    'receiverPendingCount': receiver.liveInkPendingSenderCount,
    'receiverInFlight': receiver.liveInkReceiveInFlight,
    'maxTransportPending': maxTransportPending,
    'maxReceiverPendingSenders': maxReceiverPendingSenders,
    'receiverInFlightObserved': receiverInFlightObserved,
    'reconnectCount': reconnectCount,
    'liveEmitsWhileReliablePending': liveEmitsWhileReliablePending,
    'liveReceivesWhileReliablePending': liveReceivesWhileReliablePending,
    'reliableLoadedOverlapSamples': reliableLoadedOverlapSamples,
    'remotePaintMarkerCount': acceptedPaintMarkerCount,
    'remotePaintSampleCoverage': acceptedPaintMarkerCount == 0
        ? 0.0
        : latencyMicros.length / acceptedPaintMarkerCount,
    'remotePaintP95Micros': _nearestRank(latencyMicros, 0.95),
    'maxSenderStarvationMicros': maxStarvationMicros,
    'reliableBaselineP95Micros': _nearestRank(reliableBaseline, 0.95),
    'reliableLoadedP95Micros': _nearestRank(reliableLoaded, 0.95),
    'pictureLayerCount': painter.cache.pictureLayerCount,
    'tailPointCount': painter.cache.lastFrameTailPointCount,
    'wetInkRemaining': wetInk.strokeCount,
    'finalConverged':
        receiverScene.collaborationHash() == finalScene.collaborationHash(),
    'rawPath':
        'LiveInkSender->repository.liveInkChunks->RemoteWetInkStore->RemoteWetInkPainter.paint',
  };

  await messageSubscription.cancel();
  await liveSubscription.cancel();
  for (final sender in senders) {
    await sender.stop();
  }
  await receiver.stop();
  wetInk.dispose();
  controller.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
  return result;
}

int _nearestRank(List<int> sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  return sorted[math.max(0, (percentile * sorted.length).ceil() - 1)];
}

Future<Map<String, Object?>> _measureSenderScaleEvidence() async {
  final rows = <Map<String, Object?>>[];
  for (final count in [250, 500, 1000, 2000]) {
    final chunks = <LiveInkChunk>[];
    final sender = LiveInkSender(emit: (chunk) async => chunks.add(chunk));
    sender.start(strokeId: 'scale-$count', style: _style);
    final points = <LiveInkPoint>[];
    for (var index = 0; index < count; index++) {
      points.add(LiveInkPoint(x: index.toDouble(), y: (index % 10).toDouble()));
      if ((index + 1) % 8 != 0 && index + 1 != count) continue;
      final start = math.max(0, points.length - LiveInkChunk.maxPoints);
      sender.offerTail(
        totalCount: points.length,
        startIndex: start,
        points: points.sublist(start),
      );
      while (sender.inFlight || sender.hasPending) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    final repeats = <int, int>{};
    var pointEntries = 0;
    var bytes = 0;
    for (final chunk in chunks) {
      pointEntries += chunk.points.length;
      bytes += utf8.encode(jsonEncode(chunk.toJson())).length;
      for (final point in chunk.indexedPoints) {
        repeats.update(point.index, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    rows.add({
      'acceptedPoints': count,
      'pointEntries': pointEntries,
      'bytes': bytes,
      'maxRepeats': repeats.values.fold<int>(
        0,
        (maximum, value) => value > maximum ? value : maximum,
      ),
    });
  }
  final byteFit = _linearFit(rows, 'bytes');
  final pointFit = _linearFit(rows, 'pointEntries');
  return {
    'raw': rows,
    'bytesSlope': byteFit.$1,
    'bytesRSquared': byteFit.$2,
    'pointEntriesSlope': pointFit.$1,
    'pointEntriesRSquared': pointFit.$2,
  };
}

(double, double) _linearFit(List<Map<String, Object?>> rows, String field) {
  final meanX =
      rows.fold(0.0, (sum, row) => sum + (row['acceptedPoints']! as int)) /
      rows.length;
  final meanY =
      rows.fold(0.0, (sum, row) => sum + (row[field]! as int)) / rows.length;
  var covariance = 0.0;
  var varianceX = 0.0;
  var totalY = 0.0;
  for (final row in rows) {
    final x = (row['acceptedPoints']! as int).toDouble();
    final y = (row[field]! as int).toDouble();
    covariance += (x - meanX) * (y - meanY);
    varianceX += (x - meanX) * (x - meanX);
    totalY += (y - meanY) * (y - meanY);
  }
  final slope = covariance / varianceX;
  final intercept = meanY - slope * meanX;
  var residual = 0.0;
  for (final row in rows) {
    final x = (row['acceptedPoints']! as int).toDouble();
    final y = (row[field]! as int).toDouble();
    final delta = y - (intercept + slope * x);
    residual += delta * delta;
  }
  return (slope, totalY == 0 ? 1 : 1 - residual / totalY);
}

Map<String, Object?> _reliableMarker(int version) => {
  'id': 'reliable-marker',
  'type': 'rectangle',
  'version': version,
  'versionNonce': 1000000 - version,
  'updated': 1700000000000 + version,
  'isDeleted': false,
  'index': 'a0',
  'x': 0,
  'y': 0,
  'width': 1,
  'height': 1,
};

Map<String, Object?> _freedrawElement(String id, int pointCount) => {
  'id': id,
  'type': 'freedraw',
  'version': 1,
  'versionNonce': 1,
  'updated': 1700000000000,
  'isDeleted': false,
  'index': 'a0',
  'x': 0,
  'y': 0,
  'width': pointCount.toDouble(),
  'height': 1,
  'points': [
    [0, 0],
    [pointCount.toDouble(), 1],
  ],
};

class _NetworkCase {
  const _NetworkCase(
    this.name,
    this.minOneWayDelay,
    this.maxOneWayDelay,
    this.reorderWindow,
    this.dropRate,
    this.duplicateRate,
  );
  final String name;
  final Duration minOneWayDelay;
  final Duration maxOneWayDelay;
  final int reorderWindow;
  final double dropRate;
  final double duplicateRate;
}
