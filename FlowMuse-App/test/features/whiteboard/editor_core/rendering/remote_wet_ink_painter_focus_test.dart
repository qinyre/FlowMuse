import 'dart:io';
import 'dart:ui';

import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_spy.dart';

DecodedLiveInkChunk _chunk(
  String strokeId,
  String senderSocketId, {
  double strokeWidth = 3,
}) {
  return DecodedLiveInkChunk(
    senderSocketId: senderSocketId,
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: 0,
      points: const [LiveInkPoint(x: 10, y: 10), LiveInkPoint(x: 20, y: 20)],
      style: LiveInkStyle(
        brushType: 'fountainPen',
        strokeColor: '#123456',
        strokeWidth: strokeWidth,
        opacity: 50,
      ),
    ),
  );
}

final _sharedAdapter = RoughCanvasAdapter();

/// 64 点/包的连续长笔 chunk：点 i 坐标 (i%400, i%300)。
DecodedLiveInkChunk _longChunk(
  String strokeId,
  String senderSocketId,
  int startIndex,
) {
  return DecodedLiveInkChunk(
    senderSocketId: senderSocketId,
    chunk: LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndex,
      points: [
        for (var i = startIndex; i < startIndex + 64; i++)
          LiveInkPoint(x: i % 400, y: i % 300),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('聚焦下：目标外 stroke 产生 1 个 bounds saveLayer；目标内/未知 sender 全亮 0 层', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    store.apply(_chunk('x', 's-other'));
    store.apply(_chunk('y', 's-target'));
    store.apply(_chunk('z', 's-unknown'));
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {
        's-other': 'user:other',
        's-target': 'user:a',
      },
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 1, reason: '只有 s-other 的 stroke 被变淡包裹');
    final bounds = spy.saveLayerBounds.single!;
    expect(
      bounds.width < 1000 || bounds.height < 1000,
      isTrue,
      reason: '禁止全屏层',
    );
  });

  test('无聚焦：saveLayer = 0（零新增）', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    store.apply(_chunk('x', 's-other'));
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    expect(spy.saveLayerCount, 0);
  });

  test('粗笔 bounds 余量：highlighter(sizeScale 4.2) 边缘像素不裁切', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    // highlighter 是 sizeScale 上界（4.2）；粗笔 + 点在 (10,10)-(20,20)
    final chunk = DecodedLiveInkChunk(
      senderSocketId: 's-other',
      chunk: LiveInkChunk(
        strokeId: 'fat',
        startIndex: 0,
        points: const [
          LiveInkPoint(x: 10, y: 10, pressure: 1.0),
          LiveInkPoint(x: 20, y: 20, pressure: 1.0),
        ],
        style: const LiveInkStyle(
          brushType: 'highlighter',
          strokeColor: '#FFFF00',
          strokeWidth: 40,
          opacity: 50,
        ),
      ),
    );
    store.apply(chunk);
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {'s-other': 'user:other'},
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(1000, 1000));
    final bounds = spy.saveLayerBounds.single!;
    // 公式 margin = w × 4.2 × 0.5 × 1.3 + 2；断言用含完整余量的左/右界
    final margin = 40 * 4.2 * 0.5 * 1.3 + 2.0; // 见 Step 14.2 的公式
    expect(bounds.left, lessThanOrEqualTo(10 - margin), reason: '左缘含最大有效线宽余量');
    expect(bounds.right, greaterThanOrEqualTo(20 + margin));
    expect(bounds.width, lessThan(1000));
  });

  test('shouldRepaint：无 focus 时仅 presenceCreatorRevision 变化不触发', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    final cache = RemoteWetInkRenderCache();
    addTearDown(cache.dispose);
    RemoteWetInkPainter painter({int revision = 0}) => RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      presenceCreatorRevision: revision,
    );
    expect(
      painter(revision: 1).shouldRepaint(painter(revision: 2)),
      isFalse,
      reason: '两端都无 focus 时 revision 单独变化不触发重绘',
    );
    RemoteWetInkPainter focusPainter({int revision = 0}) => RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      presenceCreatorRevision: revision,
    );
    expect(
      focusPainter(revision: 1).shouldRepaint(focusPainter(revision: 2)),
      isTrue,
    );
  });

  test('16k 长笔聚焦：bounds 读增量 frozenBounds，重复 paint 不重遍历冻结点', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    // 250 包 × 64 点 = 16000 点（上限 16384）；坐标覆盖 (0,0)-(399,299)。
    for (var start = 0; start < 250 * 64; start += 64) {
      store.apply(_longChunk('long', 's-other', start));
    }
    final snapshot = store.strokes.single;
    expect(snapshot.pointCount, 16000);
    // 冻结包围盒在 store 侧增量维护，极值正确
    expect(snapshot.frozenBounds, isNotNull);
    expect(snapshot.frozenBounds!.minX, 0);
    expect(snapshot.frozenBounds!.minY, 0);
    expect(snapshot.frozenBounds!.maxX, 399);
    expect(snapshot.frozenBounds!.maxY, 299);

    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {'s-other': 'user:other'},
    );
    final margin = 3 * 4.2 * 0.5 * 1.3 + 2.0;
    final first = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(first, const Size(2000, 2000));
    expect(first.saveLayerCount, 1);
    final bounds = first.saveLayerBounds.single!;
    expect(bounds.left, lessThanOrEqualTo(0 - margin));
    expect(bounds.right, greaterThanOrEqualTo(399 + margin));
    expect(bounds.top, lessThanOrEqualTo(0 - margin));
    expect(bounds.bottom, greaterThanOrEqualTo(299 + margin));
    expect(bounds.width, lessThan(2000), reason: '禁止全屏层');
    // 每帧只处理有限 tail（64 点），不随笔长增长
    expect(cache.lastFrameTailPointCount, 64);

    // 重复 paint：bounds 幂等，tail 仍只 64 点（冻结几何不重遍历）
    final second = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(second, const Size(2000, 2000));
    expect(second.saveLayerBounds.single, bounds);
    expect(cache.lastFrameTailPointCount, 64);
  });

  test('64-stroke 满房聚焦：每条非目标笔迹独立 dim 层且 bounds 正确', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    final cache = RemoteWetInkRenderCache();
    addTearDown(() {
      cache.dispose();
      store.dispose();
    });
    // 单 sender 64 条笔（maxStrokes 上限），每条 2 点位于专属坐标带
    for (var i = 0; i < 64; i++) {
      final base = i * 100.0;
      store.apply(
        DecodedLiveInkChunk(
          senderSocketId: 's-other',
          chunk: LiveInkChunk(
            strokeId: 'stroke-$i',
            startIndex: 0,
            points: [
              LiveInkPoint(x: base, y: base),
              LiveInkPoint(x: base + 10, y: base + 10),
            ],
            style: const LiveInkStyle(
              brushType: 'fountainPen',
              strokeColor: '#123456',
              strokeWidth: 3,
              opacity: 50,
            ),
          ),
        ),
      );
    }
    expect(store.strokeCount, 64);
    final painter = RemoteWetInkPainter(
      store: store,
      cache: cache,
      adapter: _sharedAdapter,
      viewport: const ViewportState(),
      focusedCreatorKey: 'user:a',
      socketIdCreatorKeys: const {'s-other': 'user:other'},
    );
    final spy = SpyCanvas(Canvas(PictureRecorder()));
    painter.paint(spy, const Size(5000, 5000));
    expect(spy.saveLayerCount, 64, reason: '每条非目标笔迹一个 dim 层');
    final margin = 3 * 4.2 * 0.5 * 1.3 + 2.0;
    final firstStrokeBounds = spy.saveLayerBounds.first!;
    expect(firstStrokeBounds.left, lessThanOrEqualTo(0 - margin));
    expect(firstStrokeBounds.right, greaterThanOrEqualTo(10 + margin));
  });

  test('源码门禁：_strokeBounds 不得遍历 frozenBlocks（评审 P1 修复）', () {
    final source = File(
      'lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart',
    ).readAsStringSync();
    final match = RegExp(
      r'Rect _strokeBounds\([\s\S]*?\n  \}',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '找不到 _strokeBounds 方法');
    final block = match!.group(0)!;
    expect(
      block.contains('frozenBlocks'),
      isFalse,
      reason:
          '聚焦 bounds 必须消费 store 增量维护的 frozenBounds，'
          '禁止每帧重扫冻结点（最长 16384 点/笔）',
    );
    expect(block.contains('frozenBounds'), isTrue);
  });
}
