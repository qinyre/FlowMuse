import 'dart:async';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_performance_probe.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

const List<CollaborationPerformanceScenario> collaborationPerformanceScenarios =
    [
      CollaborationPerformanceScenario(memberCount: 2),
      CollaborationPerformanceScenario(memberCount: 5),
    ];

class CollaborationPerformanceScenario {
  const CollaborationPerformanceScenario({
    required this.memberCount,
    this.warmupIterations = 100,
    this.measuredIterations = 1000,
  });

  final int memberCount;
  final int warmupIterations;
  final int measuredIterations;

  CollaborationPerformanceScenario copyWith({
    int? warmupIterations,
    int? measuredIterations,
  }) {
    return CollaborationPerformanceScenario(
      memberCount: memberCount,
      warmupIterations: warmupIterations ?? this.warmupIterations,
      measuredIterations: measuredIterations ?? this.measuredIterations,
    );
  }
}

class CollaborationStageSummary {
  const CollaborationStageSummary({
    required this.sampleCount,
    required this.totalMicros,
    required this.p50Micros,
    required this.p95Micros,
    required this.maxMicros,
    required this.byteCount,
    required this.itemCount,
  });

  final int sampleCount;
  final int totalMicros;
  final int p50Micros;
  final int p95Micros;
  final int maxMicros;
  final int byteCount;
  final int itemCount;

  Map<String, Object?> toJson() => {
    'sampleCount': sampleCount,
    'totalMicros': totalMicros,
    'p50Micros': p50Micros,
    'p95Micros': p95Micros,
    'maxMicros': maxMicros,
    'byteCount': byteCount,
    'itemCount': itemCount,
  };
}

class CollaborationPerformanceResult {
  const CollaborationPerformanceResult({
    required this.memberCount,
    required this.warmupIterations,
    required this.measuredIterations,
    required this.errors,
    required this.finalSceneHashes,
    required this.stages,
  });

  final int memberCount;
  final int warmupIterations;
  final int measuredIterations;
  final int errors;
  final List<String> finalSceneHashes;
  final Map<CollaborationPerformanceStage, CollaborationStageSummary> stages;

  bool get converged => finalSceneHashes.toSet().length == 1;

  int get allocationBytesApprox => stages.entries
      .where(
        (entry) =>
            entry.key == CollaborationPerformanceStage.jsonEncode ||
            entry.key == CollaborationPerformanceStage.encrypt ||
            entry.key == CollaborationPerformanceStage.decrypt ||
            entry.key == CollaborationPerformanceStage.jsonDecode,
      )
      .fold(0, (sum, entry) => sum + entry.value.byteCount);

  Map<String, Object?> toJson() => {
    'mode': 'collaboration_cpu_non_ui',
    'memberCount': memberCount,
    'warmupIterations': warmupIterations,
    'measuredIterations': measuredIterations,
    'errors': errors,
    'converged': converged,
    'finalSceneHashes': finalSceneHashes,
    'allocationBytesApprox': allocationBytesApprox,
    'allocationApproximation':
        'sum of observed JSON and AES-GCM input/output bytes; not heap usage',
    'stages': {
      for (final entry in stages.entries) entry.key.name: entry.value.toJson(),
    },
  };
}

Future<CollaborationPerformanceResult> runCollaborationPerformanceScenario(
  CollaborationPerformanceScenario scenario,
) async {
  if (scenario.memberCount < 2) {
    throw ArgumentError.value(scenario.memberCount, 'memberCount');
  }
  const room = CollaborationRoom(
    roomId: 'writing-performance-room',
    roomKey: 'AAAAAAAAAAAAAAAAAAAAAA',
  );
  final initial = ExcalidrawScene.empty().copyWith(
    elements: [_element(version: 1)],
  );
  final crypto = CollaborationCrypto();
  final store = MemoryEncryptedSceneStore();
  await store.createRoom(room: room, scene: initial, ownerKeyHash: 'fixture');
  final hub = MemoryRealtimeRoomHub();
  final probes = [
    for (var index = 0; index < scenario.memberCount; index++)
      CollaborationPerformanceProbe(),
  ];
  final repositories = [
    for (var index = 0; index < scenario.memberCount; index++)
      CollaborationRepository(
        transport: MemoryRealtimeTransport(
          hub: hub,
          socketId: 'fixture-peer-$index',
        ),
        sceneStore: store,
        crypto: crypto,
        performanceProbe: probes[index],
      ),
  ];
  final scenes = [
    for (var index = 0; index < scenario.memberCount; index++) initial,
  ];
  final subscriptions = <StreamSubscription<CollaborationMessage>>[];
  final previousFullSceneSyncEnabled =
      CollaborationRepository.fullSceneSyncEnabled;
  CollaborationRepository.fullSceneSyncEnabled = false;
  var awaitedVersion = 0;
  var delivered = 0;
  Completer<void>? delivery;
  var errors = 0;
  CollaborationPerformanceResult? result;

  try {
    for (final repository in repositories) {
      await repository.joinRoom(room: room, localScene: initial);
    }
    for (var index = 1; index < repositories.length; index++) {
      final receiverIndex = index;
      subscriptions.add(
        repositories[index].encryptedMessages(room).listen((message) {
          if (message.type != CollaborationMessageType.sceneUpdate ||
              message.elements.isEmpty) {
            return;
          }
          final version = (message.elements.single['version'] as num).toInt();
          scenes[receiverIndex] = repositories[receiverIndex]
              .reconcileRemoteScene(
                localScene: scenes[receiverIndex],
                remoteElements: message.elements,
              );
          if (version != awaitedVersion) return;
          delivered++;
          if (delivered == scenario.memberCount - 1) {
            delivery?.complete();
          }
        }, onError: (_) => errors++),
      );
    }
    await Future<void>.delayed(Duration.zero);

    var version = 1;
    Future<void> runIteration() async {
      version++;
      awaitedVersion = version;
      delivered = 0;
      delivery = Completer<void>();
      final scene = ExcalidrawScene.empty().copyWith(
        elements: [_element(version: version)],
      );
      scenes[0] = scene;
      await repositories.first.broadcastScene(
        room: room,
        scene: scene,
        syncAll: true,
      );
      try {
        await delivery!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        errors++;
        rethrow;
      }
    }

    for (var index = 0; index < scenario.warmupIterations; index++) {
      await runIteration();
    }
    for (final probe in probes) {
      probe.clear();
    }
    errors = 0;
    for (var index = 0; index < scenario.measuredIterations; index++) {
      await runIteration();
    }

    final samples = probes.expand((probe) => probe.samples).toList();
    result = CollaborationPerformanceResult(
      memberCount: scenario.memberCount,
      warmupIterations: scenario.warmupIterations,
      measuredIterations: scenario.measuredIterations,
      errors: errors,
      finalSceneHashes: [for (final scene in scenes) scene.collaborationHash()],
      stages: {
        for (final stage in CollaborationPerformanceStage.values)
          stage: _summarize(
            samples.where((sample) => sample.stage == stage).toList(),
          ),
      },
    );
  } finally {
    CollaborationRepository.fullSceneSyncEnabled = previousFullSceneSyncEnabled;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final repository in repositories) {
      await repository.stop();
    }
  }
  return result;
}

CollaborationStageSummary _summarize(
  List<CollaborationPerformanceSample> samples,
) {
  if (samples.isEmpty) {
    return const CollaborationStageSummary(
      sampleCount: 0,
      totalMicros: 0,
      p50Micros: 0,
      p95Micros: 0,
      maxMicros: 0,
      byteCount: 0,
      itemCount: 0,
    );
  }
  final durations = samples.map((sample) => sample.durationMicros).toList()
    ..sort();
  return CollaborationStageSummary(
    sampleCount: samples.length,
    totalMicros: durations.fold(0, (sum, duration) => sum + duration),
    p50Micros: _nearestRank(durations, 0.50),
    p95Micros: _nearestRank(durations, 0.95),
    maxMicros: durations.last,
    byteCount: samples.fold(0, (sum, sample) => sum + sample.byteCount),
    itemCount: samples.fold(0, (sum, sample) => sum + sample.itemCount),
  );
}

int _nearestRank(List<int> sorted, double percentile) {
  final index = math.max(0, (percentile * sorted.length).ceil() - 1);
  return sorted[index];
}

Map<String, Object?> _element({required int version}) {
  return {
    'id': 'fixture-stroke',
    'type': 'freedraw',
    'version': version,
    'versionNonce': 1000000 - version,
    'updated': 1700000000000 + version,
    'isDeleted': false,
    'index': 'a0',
    'x': 0,
    'y': 0,
    'width': 120,
    'height': 40,
    'points': [
      [0, 0],
      [version % 120, version % 40],
      [120, 40],
    ],
  };
}
