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
}
