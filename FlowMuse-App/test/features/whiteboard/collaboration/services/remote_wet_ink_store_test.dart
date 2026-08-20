import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

void main() {
  test('第 9 个 sender 被拒绝，leave 后重新准入', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);

    for (var sender = 0; sender < 8; sender++) {
      expect(store.apply(_decoded('s$sender', 'p$sender')).accepted, isTrue);
    }
    final rejected = store.apply(_decoded('s8', 'p8'));
    expect(rejected.reason, RemoteWetInkDropReason.senderLimit);
    expect(store.senderCount, 8);

    store.removeSender('s0');
    expect(store.apply(_decoded('s8', 'p8')).accepted, isTrue);
    expect(store.senderCount, 8);
  });

  test('第 65 个 stroke 被拒绝且不驱逐现有笔画', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);

    for (var stroke = 0; stroke < 64; stroke++) {
      expect(store.apply(_decoded('sender', 'p$stroke')).accepted, isTrue);
    }
    final rejected = store.apply(_decoded('sender', 'p64'));

    expect(rejected.reason, RemoteWetInkDropReason.strokeLimit);
    expect(store.strokeCount, 64);
  });

  test('stroke 16384 点边界整包接收，16385 整包拒绝', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    _fillStroke(store, sender: 'sender', strokeId: 'stroke');

    expect(store.roomPointCount, RemoteWetInkStore.maxPointsPerStroke);
    final rejected = store.apply(
      _decoded('sender', 'stroke', startIndex: 16384),
    );
    expect(rejected.reason, RemoteWetInkDropReason.strokePointLimit);
    expect(store.roomPointCount, RemoteWetInkStore.maxPointsPerStroke);
  });

  test('room 65536 点边界后整包拒绝，重复包不增加计数', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    for (var stroke = 0; stroke < 4; stroke++) {
      _fillStroke(store, sender: 'sender', strokeId: 'p$stroke');
    }

    expect(store.roomPointCount, RemoteWetInkStore.maxPointsPerRoom);
    final duplicate = store.apply(
      _decoded('sender', 'p0', startIndex: 0, count: 64),
    );
    expect(duplicate.accepted, isTrue);
    expect(duplicate.addedPoints, 0);
    expect(store.roomPointCount, RemoteWetInkStore.maxPointsPerRoom);

    final rejected = store.apply(_decoded('sender', 'overflow'));
    expect(rejected.reason, RemoteWetInkDropReason.roomPointLimit);
    expect(store.roomPointCount, RemoteWetInkStore.maxPointsPerRoom);
  });

  test('TTL 同步释放 sender、stroke 和 room 点计数', () {
    var now = 1000;
    final store = RemoteWetInkStore(nowMs: () => now, autoCleanup: false);
    addTearDown(store.dispose);
    store.apply(_decoded('sender', 'stroke', count: 4));

    now += const Duration(seconds: 5).inMilliseconds;
    store.cleanup();

    expect(store.senderCount, 0);
    expect(store.strokeCount, 0);
    expect(store.roomPointCount, 0);
    expect(store.apply(_decoded('new-sender', 'new-stroke')).accepted, isTrue);
  });

  test('final 先写 completed/finalized 再清 preview，迟到包永不复活', () {
    var now = 1000;
    final store = RemoteWetInkStore(nowMs: () => now, autoCleanup: false);
    addTearDown(store.dispose);
    store.apply(_decoded('sender', 'stroke', count: 4));

    store.finalizeStroke('stroke');
    expect(store.strokeCount, 0);
    expect(store.completedCacheCount, 1);
    expect(store.isFinalized('stroke'), isTrue);

    now += 100;
    expect(
      store.apply(_decoded('sender', 'stroke')).reason,
      RemoteWetInkDropReason.finalized,
    );
    now += const Duration(seconds: 11).inMilliseconds;
    store.cleanup();
    expect(store.completedCacheCount, 0);
    expect(
      store.apply(_decoded('sender', 'stroke')).reason,
      RemoteWetInkDropReason.finalized,
    );
  });

  test('初始 final ID 直接阻止 terminal-before-preview', () {
    final store = RemoteWetInkStore(autoCleanup: false)
      ..seedFinalizedStrokeIds(['existing']);
    addTearDown(store.dispose);

    expect(
      store.apply(_decoded('sender', 'existing')).reason,
      RemoteWetInkDropReason.finalized,
    );
    expect(store.senderCount, 0);
    expect(store.strokeCount, 0);
  });

  test('长笔渲染快照始终不超过 1+8+1 层', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);

    for (var start = 0; start < 16384; start += 64) {
      store.apply(_decoded('sender', 'stroke', startIndex: start, count: 64));
      expect(store.strokes.single.layerCount, lessThanOrEqualTo(10));
      expect(
        store.strokes.single.incrementalSegments,
        hasLength(lessThanOrEqualTo(8)),
      );
      expect(
        store.strokes.single.tailSegments
            .expand((segment) => segment.points)
            .length,
        lessThanOrEqualTo(64),
      );
    }
  });

  test('单点小包更新只检查新增点与 64 点 tail，不扫描历史前缀', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);

    for (var index = 0; index < RemoteWetInkStore.maxPointsPerStroke; index++) {
      expect(
        store.apply(_decoded('sender', 'stroke', startIndex: index)).accepted,
        isTrue,
      );
      expect(
        store.lastApplyExaminedPointCount,
        lessThanOrEqualTo(LiveInkChunk.maxPoints + 2),
      );
    }
    expect(store.strokes.single.pointCount, 16384);
    expect(store.strokes.single.maxPointIndex, 16383);
  });

  test('completed cache 清理按秒限频，不随每个 live 包全表扫描', () {
    var now = 1000;
    final store = RemoteWetInkStore(nowMs: () => now, autoCleanup: false);
    addTearDown(store.dispose);
    for (var index = 0; index < 5000; index++) {
      store.finalizeStroke('final-$index');
    }

    for (var index = 0; index < 150; index++) {
      store.apply(_decoded('sender', 'stroke', startIndex: index));
    }

    expect(store.completedCacheCount, 5000);
    expect(store.cleanupPassCount, 1);
    now += 1000;
    store.apply(_decoded('sender', 'stroke', startIndex: 150));
    expect(store.cleanupPassCount, 2);
  });
}

void _fillStroke(
  RemoteWetInkStore store, {
  required String sender,
  required String strokeId,
}) {
  for (var start = 0; start < 16384; start += 64) {
    final result = store.apply(
      _decoded(sender, strokeId, startIndex: start, count: 64),
    );
    expect(result.accepted, isTrue);
  }
}

DecodedLiveInkChunk _decoded(
  String sender,
  String strokeId, {
  int startIndex = 0,
  int count = 1,
}) {
  return DecodedLiveInkChunk(
    senderSocketId: sender,
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndex,
      points: [
        for (var offset = 0; offset < count; offset++)
          LiveInkPoint(
            x: (startIndex + offset).toDouble(),
            y: (startIndex + offset).toDouble(),
          ),
      ],
      style: const LiveInkStyle(
        brushType: 'fountainPen',
        strokeColor: '#1e1e1e',
        strokeWidth: 2,
        opacity: 100,
      ),
    ),
  );
}
