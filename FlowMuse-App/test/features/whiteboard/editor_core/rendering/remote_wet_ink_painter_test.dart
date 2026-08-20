import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/draw_style.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('冻结历史录入有界 picture，重复 paint 只遍历 64 点 tail', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    for (var start = 0; start < 640; start += 64) {
      store.apply(_decoded('stroke', startIndex: start, count: 64));
    }
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );
    expect(cache.paintedMaxPointIndex('stroke'), isNull);

    _paint(painter);
    final recordedAfterFirstPaint = cache.recordedGeometryPointCount;
    expect(cache.pictureLayerCount, lessThanOrEqualTo(9));
    expect(cache.lastFrameTailPointCount, 64);
    expect(recordedAfterFirstPaint, greaterThan(0));
    expect(cache.paintedMaxPointIndex('stroke'), 639);

    adapter.calls = 0;
    adapter.totalPoints = 0;
    adapter.paths.clear();
    adapter.pressures.clear();
    _paint(painter);
    expect(cache.recordedGeometryPointCount, recordedAfterFirstPaint);
    expect(cache.lastFrameTailPointCount, 64);
    expect(adapter.totalPoints, 65);
  });

  test('普通增量只重录当前有界冻结块，不重录完整 prefix', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    for (var start = 0; start < 960; start += 64) {
      store.apply(_decoded('stroke', startIndex: start, count: 64));
    }
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );
    _paint(painter);
    final before = cache.recordedGeometryPointCount;

    store.apply(_decoded('stroke', startIndex: 960, count: 64));
    _paint(painter);
    final newlyRecorded = cache.recordedGeometryPointCount - before;

    expect(
      newlyRecorded,
      lessThanOrEqualTo(RemoteWetInkStore.frozenBlockPointCapacity),
    );
    expect(cache.pictureLayerCount, lessThanOrEqualTo(9));
  });

  test('逐点 apply+paint 的累计录制成本随 N 线性增长', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    var recordedAt2048 = 0;
    for (var index = 0; index < 4096; index++) {
      store.apply(_decoded('stroke', startIndex: index, count: 1));
      _paint(painter);
      adapter.paths.clear();
      adapter.pressures.clear();
      if (index == 2047) {
        recordedAt2048 = cache.recordedGeometryPointCount;
      }
    }

    expect(recordedAt2048, greaterThan(0));
    expect(cache.recordedGeometryPointCount / recordedAt2048, lessThan(2.6));
    expect(
      cache.recordedGeometryPointCount,
      lessThanOrEqualTo(RemoteWetInkStore.maxIncrementalSegments * 4096),
    );
    expect(cache.pictureLayerCount, lessThanOrEqualTo(8));
  });

  test('延迟到达不能在 painter 真正 paint 前产生关联标记', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _RecordingAdapter(),
      viewport: const ViewportState(),
    );
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    const acceptedMicros = 1000;
    store.apply(_decoded('delayed', startIndex: 0, count: 1));

    expect(cache.paintedMaxPointIndex('delayed'), isNull);
    const paintMicros = acceptedMicros + 500000;
    _paint(painter);

    expect(cache.paintedMaxPointIndex('delayed'), 0);
    expect(paintMicros - acceptedMicros, 500000);
  });

  test('缺口拆成独立子路径，样式和压力传给现有 renderer', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    store.apply(_decoded('stroke', startIndex: 0, count: 2, pressure: 0.4));
    store.apply(_decoded('stroke', startIndex: 4, count: 2, pressure: 0.8));
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );

    _paint(painter);

    expect(adapter.paths, hasLength(2));
    expect(adapter.paths.first.map((point) => point.x), [0, 1]);
    expect(adapter.paths.last.map((point) => point.x), [4, 5]);
    expect(adapter.pressures.first, [0.4, 0.4]);
    expect(adapter.style?.strokeColor, const Color(0xff123456));
    expect(adapter.style?.strokeWidth, 3);
    expect(adapter.style?.opacity, 0.5);
    expect(cache.wasPointPainted('stroke', 0), isTrue);
    expect(cache.wasPointPainted('stroke', 2), isFalse);
    expect(cache.wasPointPainted('stroke', 4), isTrue);
  });

  test('连续点跨 64 点冻结边界仍绘制 63→64 连接边', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    store.apply(_decoded('stroke', startIndex: 0, count: 64));
    store.apply(_decoded('stroke', startIndex: 64, count: 64));
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );

    _paint(painter);

    expect(
      adapter.paths,
      contains(
        predicate<List<Point>>(
          (path) => path.length >= 2 && path.first.x == 63 && path[1].x == 64,
        ),
      ),
    );
  });

  test('多个活跃冻结块按最小绝对索引播放', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _RecordingAdapter(),
      viewport: const ViewportState(),
    );
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    for (final start in [192, 128, 64, 0]) {
      store.apply(_decoded('stroke', startIndex: start, count: 64));
    }

    _paint(painter);

    expect(cache.pictureMinStartIndices('stroke'), [0, 64]);
  });

  test('新到点只有实际 paint 后才进入 O(1) painted index', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _RecordingAdapter(),
      viewport: const ViewportState(),
    );
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });

    store.apply(_decoded('stroke', startIndex: 0, count: 1));
    _paint(painter);
    store.apply(_decoded('stroke', startIndex: 1, count: 1));

    expect(cache.wasPointPainted('stroke', 0), isTrue);
    expect(cache.wasPointPainted('stroke', 1), isFalse);
    _paint(painter);
    expect(cache.wasPointPainted('stroke', 1), isTrue);
  });

  test('final 接管立即清 picture 且不留残影', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    for (var start = 0; start < 256; start += 64) {
      store.apply(_decoded('stroke', startIndex: start, count: 64));
    }
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );
    _paint(painter);
    expect(cache.pictureLayerCount, greaterThan(0));
    expect(cache.paintedMaxPointIndex('stroke'), 255);

    store.finalizeStroke('stroke');
    adapter.calls = 0;
    _paint(painter);

    expect(cache.pictureLayerCount, 0);
    expect(adapter.calls, 0);
    expect(cache.paintedMaxPointIndex('stroke'), isNull);
  });

  test('16k 长笔的 retained picture 始终为单层且估算缓存有界', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    final adapter = _RecordingAdapter();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    for (var start = 0; start < 16384; start += 64) {
      store.apply(_decoded('stroke', startIndex: start, count: 64));
    }
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: adapter,
      viewport: const ViewportState(),
    );

    _paint(painter);

    expect(cache.maxPictureNestingDepth, 1);
    expect(cache.pictureLayerCount, lessThanOrEqualTo(9));
    expect(cache.retainedGeometryPointCount, lessThanOrEqualTo(16320));
    expect(
      cache.estimatedRetainedBytes,
      lessThan(RemoteWetInkStore.maxEstimatedRenderBytes),
    );
  });

  test('1×16k、4×16k 与 64×1024 三组房间压力边界可实际绘制', () {
    for (final scenario in const [
      (strokeCount: 1, pointsPerStroke: 16384),
      (strokeCount: 4, pointsPerStroke: 16384),
      (strokeCount: 64, pointsPerStroke: 1024),
    ]) {
      final store = RemoteWetInkStore(autoCleanup: false);
      final cache = RemoteWetInkRenderCache();
      final adapter = _RecordingAdapter();
      for (var stroke = 0; stroke < scenario.strokeCount; stroke++) {
        for (
          var start = 0;
          start < scenario.pointsPerStroke;
          start += LiveInkChunk.maxPoints
        ) {
          expect(
            store
                .apply(
                  _decoded(
                    'stroke-$stroke',
                    startIndex: start,
                    count: LiveInkChunk.maxPoints,
                  ),
                )
                .accepted,
            isTrue,
          );
        }
      }
      final painter = RemoteWetInkPainter(
        store: store,
        cache: cache,
        adapter: adapter,
        viewport: const ViewportState(),
      );

      _paint(painter);

      expect(
        store.roomPointCount,
        scenario.strokeCount * scenario.pointsPerStroke,
      );
      expect(
        cache.pictureLayerCount,
        lessThanOrEqualTo(
          scenario.strokeCount * RemoteWetInkStore.maxIncrementalSegments,
        ),
      );
      expect(cache.maxPictureNestingDepth, 1);
      expect(
        cache.estimatedRetainedBytes,
        lessThan(RemoteWetInkStore.maxEstimatedRenderBytes),
      );
      cache.dispose();
      store.dispose();
    }
  });
}

void _paint(RemoteWetInkPainter painter) {
  final recorder = PictureRecorder();
  painter.paint(Canvas(recorder), const Size(800, 600));
  recorder.endRecording().dispose();
}

DecodedLiveInkChunk _decoded(
  String strokeId, {
  required int startIndex,
  required int count,
  double? pressure,
}) {
  return DecodedLiveInkChunk(
    senderSocketId: 'sender',
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndex,
      points: [
        for (var offset = 0; offset < count; offset++)
          LiveInkPoint(
            x: (startIndex + offset).toDouble(),
            y: 1,
            pressure: pressure,
          ),
      ],
      style: const LiveInkStyle(
        brushType: 'fountainPen',
        strokeColor: '#123456',
        strokeWidth: 3,
        opacity: 50,
      ),
    ),
  );
}

class _RecordingAdapter implements RoughAdapter {
  int calls = 0;
  int totalPoints = 0;
  final List<List<Point>> paths = [];
  final List<List<double>> pressures = [];
  DrawStyle? style;

  @override
  void drawFreedraw(
    Canvas canvas,
    List<Point> points,
    List<double> pressures,
    bool simulatePressure,
    BrushType brushType,
    DrawStyle style, {
    bool isComplete = true,
  }) {
    calls++;
    totalPoints += points.length;
    paths.add(List.of(points));
    this.pressures.add(List.of(pressures));
    this.style = style;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
