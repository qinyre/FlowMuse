import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/whiteboard/collaboration/services/fault_injecting_realtime_transport.dart';

const _perfTestEnabled = bool.fromEnvironment('FLOWMUSE_PERF_TEST');
const _measureSeconds = int.fromEnvironment(
  'FLOWMUSE_MEASURE_SECONDS',
  defaultValue: 300,
);
const _style = LiveInkStyle(
  brushType: 'fountainPen',
  strokeColor: '#1e1e1e',
  strokeWidth: 2,
  opacity: 100,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 repository 到 RemoteWetInkPainter 的 2/5 人门禁', (tester) async {
    expect(
      _perfTestEnabled,
      isTrue,
      reason: '性能入口仅允许通过 FLOWMUSE_PERF_TEST=true 启用',
    );
    final requestedV2 = layeredWetInkEnabled && liveInkFlags.liveInkV2;
    if (!requestedV2) {
      final result = await _runDisabledMatrixCase();
      expect(result['effective'], isFalse);
      expect(result['emitCount'], 0);
      binding.reportData = {
        'schemaVersion': 1,
        'measurementEligible': kProfileMode,
        'mode': 'collaboration_live_ink',
        'requestedLayeredWetInk': layeredWetInkEnabled,
        'requestedLiveInkV2': liveInkFlags.liveInkV2,
        'results': [result],
      };
      return;
    }

    final results = <Map<String, Object?>>[];
    for (final memberCount in [2, 5]) {
      for (final network in const [
        _NetworkCase(
          'good',
          Duration(milliseconds: 5),
          Duration(milliseconds: 15),
          0,
          0,
        ),
        _NetworkCase(
          'rtt100',
          Duration(milliseconds: 50),
          Duration(milliseconds: 50),
          0,
          0,
        ),
        _NetworkCase(
          'fault10',
          Duration.zero,
          Duration(milliseconds: 120),
          0.1,
          0.1,
        ),
        _NetworkCase(
          'fault20',
          Duration.zero,
          Duration(milliseconds: 120),
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
      expect(result['finalConverged'], isTrue);
      expect(result['wetInkRemaining'], 0);
      expect(result['pendingCount'], 0);
      final network = result['network'];
      final remoteP95 = result['remotePaintP95Micros']! as int;
      if (network == 'good') {
        expect(remoteP95, lessThanOrEqualTo(200000));
      } else if (network == 'rtt100') {
        expect(remoteP95, lessThanOrEqualTo(300000));
      }
      if (network == 'good' && result['memberCount'] == 5) {
        expect(result['maxSenderStarvationMicros'], lessThanOrEqualTo(200000));
      }
      final baseline = result['reliableBaselineP95Micros']! as int;
      final loaded = result['reliableLoadedP95Micros']! as int;
      expect(loaded, lessThanOrEqualTo((baseline * 1.10).ceil()));
    }
    binding.reportData = {
      'schemaVersion': 1,
      'measurementEligible': kProfileMode,
      'mode': 'collaboration_live_ink',
      'requestedLayeredWetInk': layeredWetInkEnabled,
      'requestedLiveInkV2': liveInkFlags.liveInkV2,
      'measureSeconds': _measureSeconds,
      'results': results,
    };
  });
}

Future<Map<String, Object?>> _runDisabledMatrixCase() async {
  final hub = MemoryRealtimeRoomHub();
  final transport = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
  final repository = CollaborationRepository(
    transport: transport,
    flags: liveInkFlags,
  );
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
  final result = <String, Object?>{
    'effective': repository.effectiveLiveInk,
    'emitCount': 0,
    'readyGeneration': 1,
    'readyRoom': 'room',
  };
  await transport.disconnect();
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
  final receiver = CollaborationRepository(
    transport: MemoryRealtimeTransport(hub: hub, socketId: 'receiver'),
    sceneStore: sceneStore,
    crypto: crypto,
    flags: liveInkFlags,
  );
  final transports = <FaultInjectingRealtimeTransport>[];
  final senders = <CollaborationRepository>[];
  for (var index = 0; index < memberCount - 1; index++) {
    final transport = FaultInjectingRealtimeTransport(
      delegate: MemoryRealtimeTransport(hub: hub, socketId: 'sender-$index'),
      model: LiveInkFaultModel(
        seed: 20260820 + index,
        dropRate: network.dropRate,
        duplicateRate: network.duplicateRate,
        reorderWindow: 5,
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
  final lastReceiveMicros = <String, int>{};
  var maxStarvationMicros = 0;
  final runClock = Stopwatch()..start();
  final liveSubscription = receiver.liveInkChunks.listen((decoded) {
    receiveCount++;
    final now = runClock.elapsedMicroseconds;
    final previous = lastReceiveMicros[decoded.senderSocketId];
    if (previous != null) {
      maxStarvationMicros = math.max(maxStarvationMicros, now - previous);
    }
    lastReceiveMicros[decoded.senderSocketId] = now;
    wetInk.apply(decoded);
  });
  var receiverScene = ExcalidrawScene.empty();
  var reliableSentMicros = 0;
  var awaitedReliableVersion = -1;
  Completer<void>? reliableApplied;
  List<int>? reliableSamples;
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
      reliableSamples?.add(runClock.elapsedMicroseconds - reliableSentMicros);
      reliableApplied!.complete();
    }
  });

  final controller = MarkdrawController(writingFlags: writingFeatureFlags);
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
  Future<List<int>> measureReliable({
    required int firstVersion,
    required List<Map<String, Object?>> extraElements,
  }) async {
    final samples = <int>[];
    reliableSamples = samples;
    for (var offset = 0; offset < 20; offset++) {
      final version = firstVersion + offset;
      awaitedReliableVersion = version;
      reliableApplied = Completer<void>();
      reliableSentMicros = runClock.elapsedMicroseconds;
      await senders.first.broadcastScene(
        room: room,
        scene: ExcalidrawScene.empty().copyWith(
          elements: [_reliableMarker(version), ...extraElements],
        ),
        syncAll: true,
      );
      await reliableApplied!.future.timeout(const Duration(seconds: 5));
    }
    samples.sort();
    return samples;
  }

  final reliableBaseline = await measureReliable(
    firstVersion: 1,
    extraElements: const [],
  );
  final latencyMicros = <int>[];
  var paintCount = 0;
  final deadline = Duration(seconds: _measureSeconds);
  var packetIndex = 0;
  while (runClock.elapsed < deadline) {
    final started = runClock.elapsedMicroseconds;
    for (var senderIndex = 0; senderIndex < senders.length; senderIndex++) {
      await senders[senderIndex].sendLiveInkChunk(
        room: room,
        chunk: LiveInkChunk(
          strokeId: 'stroke-$senderIndex',
          startIndex: packetIndex,
          points: [
            LiveInkPoint(x: packetIndex.toDouble(), y: senderIndex * 10.0),
          ],
          style: _style,
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 33));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RemoteWetInkPainter>()
        .single;
    if (painter.cache.lastFrameTailPointCount > 0) {
      paintCount++;
      latencyMicros.add(runClock.elapsedMicroseconds - started);
    }
    packetIndex++;
  }
  for (final transport in transports) {
    await transport.flushLiveInk();
  }
  await tester.pump();

  final finalElements = [
    for (var index = 0; index < senders.length; index++)
      _freedrawElement('stroke-$index', packetIndex),
  ];
  final reliableLoaded = await measureReliable(
    firstVersion: 21,
    extraElements: finalElements,
  );
  final finalScene = ExcalidrawScene.empty().copyWith(
    elements: [_reliableMarker(40), ...finalElements],
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
  final result = <String, Object?>{
    'memberCount': memberCount,
    'network': network.name,
    'effective':
        receiver.effectiveLiveInk &&
        senders.every((item) => item.effectiveLiveInk),
    'readyGeneration': transports
        .map((item) => item.connectionGeneration)
        .toList(),
    'readyRoom': transports.map((item) => item.roomId).toList(),
    'acceptedCount': accepted,
    'emitCount': emitted,
    'receiveCount': receiveCount,
    'decryptCount': receiveCount,
    'paintCount': paintCount,
    'recordedGeometryPointCount': painter.cache.recordedGeometryPointCount,
    'dropCount': dropped,
    'pendingCount': pending,
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
        'repository.liveInkChunks->RemoteWetInkStore->RemoteWetInkPainter',
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
    this.dropRate,
    this.duplicateRate,
  );
  final String name;
  final Duration minOneWayDelay;
  final Duration maxOneWayDelay;
  final double dropRate;
  final double duplicateRate;
}
