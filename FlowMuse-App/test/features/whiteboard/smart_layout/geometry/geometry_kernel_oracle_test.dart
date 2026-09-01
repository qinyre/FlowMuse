import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_obstacle.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/oriented_layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_geometry_kernel.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-301A 零漏检 oracle：renderer 真实可视边界（elementVisualBounds +
/// conservativeVisualBounds——含笔刷包络与旋转外扩，V3-102A 冻结路径）
/// 逐对暴力全集是 ground truth；几何内核网格索引查询必须覆盖其中每一对。
/// 允许保守假阳性（AABB 语义），漏检必须为 0。
void main() {
  const pageId = 'page-1';

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(scene),
  );

  Map<String, Object?> onPage({String? brushType}) => {
    'flowMuse': {
      'pageId': pageId,
      'brushType': ?brushType,
    },
  };

  /// 混合形态页面：荧光笔迹（包络外扩）、旋转矩形、嵌套、零尺寸线、
  /// 锁定保护对象、近分离对。
  Scene buildFixtureScene() {
    var scene = Scene();
    // 荧光笔迹：visualBounds 超出中心线 AABB（包络）。
    scene = scene.addElement(FreedrawElement(
      id: const ElementId('ink-highlight'),
      x: 100,
      y: 100,
      width: 200,
      height: 20,
      points: const [Point(100, 100), Point(200, 110), Point(300, 120)],
      pressures: const [0.2, 0.8, 0.4],
      strokeWidth: 30,
      seed: 1,
      versionNonce: 1,
      updated: 1,
      customData: onPage(brushType: 'highlighter'),
    ));
    // 旋转 45° 矩形：保守 AABB 显著大于本体。
    scene = scene.addElement(RectangleElement(
      id: const ElementId('rot-45'),
      x: 400,
      y: 50,
      width: 80,
      height: 20,
      angle: 0.7853981633974483,
      seed: 2,
      versionNonce: 2,
      updated: 1,
      customData: onPage(),
    ));
    // 嵌套对：小盒完全在大盒内。
    scene = scene.addElement(RectangleElement(
      id: const ElementId('big-box'),
      x: 600,
      y: 100,
      width: 300,
      height: 200,
      seed: 3,
      versionNonce: 3,
      updated: 1,
      customData: onPage(),
    ));
    scene = scene.addElement(RectangleElement(
      id: const ElementId('small-in-big'),
      x: 700,
      y: 150,
      width: 50,
      height: 40,
      seed: 4,
      versionNonce: 4,
      updated: 1,
      customData: onPage(),
    ));
    // 零尺寸竖线，落在荧光笔迹保守盒内部。
    scene = scene.addElement(FreedrawElement(
      id: const ElementId('ink-degenerate'),
      x: 150,
      y: 105,
      width: 0,
      height: 10,
      points: const [Point(150, 105), Point(150, 115)],
      seed: 5,
      versionNonce: 5,
      updated: 1,
      customData: onPage(),
    ));
    // 锁定保护对象：与旋转矩形保守盒相邻。
    scene = scene.addElement(RectangleElement(
      id: const ElementId('locked-obstacle'),
      x: 430,
      y: 90,
      width: 30,
      height: 30,
      locked: true,
      seed: 6,
      versionNonce: 6,
      updated: 1,
      customData: onPage(),
    ));
    return scene;
  }

  /// 全配对 oracle：visualBounds（renderer 真实可视边界）闭盒相交对。
  Set<(String, String)> oraclePairs(List<LayoutObstacle> obstacles) {
    final pairs = <(String, String)>{};
    for (var i = 0; i < obstacles.length; i++) {
      for (var j = i + 1; j < obstacles.length; j++) {
        final a = obstacles[i];
        final b = obstacles[j];
        if (a.conservativeBounds.intersects(b.conservativeBounds)) {
          pairs.add((a.id, b.id));
        }
      }
    }
    return pairs;
  }

  late List<LayoutObstacle> obstacles;
  late LayoutObstacleIndex index;
  late Set<(String, String)> oracle;

  setUpAll(() {
    final snapshot = const SnapshotExtractor().extract(
      scene: buildFixtureScene(),
      pageId: pageId,
      sceneRevision: revisionOf(buildFixtureScene()),
    );
    obstacles = [
      for (final o in snapshot.objects) LayoutObstacle.fromSnapshotObject(o),
      for (final s in snapshot.inkStrokes) LayoutObstacle.fromSnapshotInkStroke(s),
    ];
    index = SmartLayoutGeometryKernel.buildIndex(obstacles);
    oracle = oraclePairs(obstacles);
  });

  test('fixture 前置：包络/旋转/嵌套/零尺寸/保护对象全部成形', () {
    expect(obstacles.length, 6);
    final ink = obstacles.firstWhere((o) => o.id == 'ink-highlight');
    expect(ink.conservativeBounds.width, greaterThan(200),
        reason: '荧光笔包络外扩后的可视边界');
    final rot = obstacles.firstWhere((o) => o.id == 'rot-45');
    expect(rot.conservativeBounds.width, closeTo(70.71067811865476, 1e-9),
        reason: '(80+20)·cos45° 旋转外扩保守盒');
    final degenerate = obstacles.firstWhere((o) => o.id == 'ink-degenerate');
    expect(degenerate.conservativeBounds.isDegenerate, isFalse,
        reason: '零宽笔迹的 visualBounds 因包络不退化；原语仍支持退化形态');
    expect(oracle, isNotEmpty);
  });

  test('零漏检：索引查询覆盖 oracle 全部相交对（逐源查询）', () {
    var misses = <String>[];
    for (final obstacle in obstacles) {
      final hits = index.queryIntersecting(obstacle.conservativeBounds);
      final hitIds = hits.map((h) => h.id).toSet();
      for (final (a, b) in oracle) {
        final other = a == obstacle.id ? b : (b == obstacle.id ? a : null);
        if (other == null) continue;
        if (!hitIds.contains(other)) {
          misses.add('${obstacle.id} 漏掉 $other');
        }
      }
    }
    expect(misses, isEmpty, reason: 'renderer oracle 漏检必须为 0：$misses');
  });

  test('零漏检：oracle 相交对逐对直接判定', () {
    for (final (a, b) in oracle) {
      final oa = obstacles.firstWhere((o) => o.id == a);
      final ob = obstacles.firstWhere((o) => o.id == b);
      expect(oa.aabbIntersects(ob), isTrue, reason: 'oracle 对 ($a,$b) AABB 漏检');
    }
    // oracle 之外的对允许保守相交（假阳性），但 OBB 精判必须识别旋转近分离。
    final rot = obstacles.firstWhere((o) => o.id == 'rot-45');
    // OBB 精判对旋转障碍自身必须可达（精判链路非空转）。
    expect(index.queryIntersectingObb(rot.obb).map((o) => o.id), contains('rot-45'),
        reason: '旋转障碍与自身保守盒交叠，OBB 精判必命中');
  });

  test('OBB 精判零漏检：真实旋转相交对必须命中', () {
    // 45° 旋转矩形与穿过其本体的轴对齐盒：保守命中，SAT 也必须命中。
    final rot = obstacles.firstWhere((o) => o.id == 'rot-45');
    final query = OrientedLayoutRect(
      centerX: rot.obb.centerX,
      centerY: rot.obb.centerY,
      halfWidth: 20,
      halfHeight: 20,
      rotation: 0,
    );
    final hits = index.queryIntersectingObb(query);
    expect(hits.map((h) => h.id), contains('rot-45'));
  });

  test('间隙查询零漏检：oracle 半径邻域全覆盖', () {
    const radius = 25.0;
    for (final obstacle in obstacles) {
      final within = index.queryWithinGap(obstacle.conservativeBounds, radius);
      final withinIds = within.map((w) => w.id).toSet();
      for (final other in obstacles) {
        if (other.id == obstacle.id) continue;
        final gap = obstacle.conservativeBounds.gapTo(other.conservativeBounds);
        if (gap <= radius) {
          expect(withinIds, contains(other.id),
              reason: '${obstacle.id} 半径 $radius 漏掉 ${other.id}（gap=$gap）');
        }
      }
    }
  });

  test('保护对象命中：overlaps 线性判定与索引一致', () {
    final locked = obstacles.firstWhere((o) => o.id == 'locked-obstacle');
    final hitRect = LayoutRect(
      left: locked.conservativeBounds.left - 5,
      top: locked.conservativeBounds.top - 5,
      width: locked.conservativeBounds.width + 10,
      height: locked.conservativeBounds.height + 10,
    );
    expect(
      SmartLayoutGeometryKernel.overlapsAnyObstacleAabb(hitRect, obstacles),
      isTrue,
    );
    expect(
      SmartLayoutGeometryKernel.overlapsAnyObstacleObb(hitRect, obstacles),
      isTrue,
    );
    final farRect = const LayoutRect(left: 5000, top: 5000, width: 10, height: 10);
    expect(
      SmartLayoutGeometryKernel.overlapsAnyObstacleAabb(farRect, obstacles),
      isFalse,
    );
    // 索引与线性判定一致性。
    expect(
      index.queryIntersecting(hitRect).map((o) => o.id).toSet(),
      contains('locked-obstacle'),
    );
    expect(index.queryIntersecting(farRect), isEmpty);
  });

  test('零尺寸查询盒不漏：笔迹中心点查回包络盒', () {
    final ink = obstacles.firstWhere((o) => o.id == 'ink-highlight');
    final point = LayoutRect(
      left: ink.conservativeBounds.centerX,
      top: ink.conservativeBounds.centerY,
      width: 0,
      height: 0,
    );
    final hits = index.queryIntersecting(point).map((h) => h.id).toSet();
    expect(hits, contains('ink-highlight'), reason: '点在保守盒内必须命中');
  });

  test('索引确定性与快照形态不丢', () {
    final again = SmartLayoutGeometryKernel.buildIndex(obstacles);
    expect(again.all.map((o) => o.id), index.all.map((o) => o.id));
    expect(index.length, obstacles.length);
    // 每次查询结果确定性（重复查询逐 id 相等）。
    final q1 = index.queryIntersecting(obstacles.first.conservativeBounds);
    final q2 = index.queryIntersecting(obstacles.first.conservativeBounds);
    expect(q1.map((o) => o.id), q2.map((o) => o.id));
  });
}
