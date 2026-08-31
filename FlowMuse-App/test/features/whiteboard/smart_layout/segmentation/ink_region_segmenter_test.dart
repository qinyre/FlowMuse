import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/ink_region_segmenter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/region_segment.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/segmentation_policy.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/spatial_grid_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = SegmentationPolicy.development;

  FreedrawElement stroke(String id, double x, double y, double w, double h) =>
      FreedrawElement(
        id: ElementId(id),
        x: x,
        y: y,
        width: w,
        height: h,
        points: [Point(x, y), Point(x + w, y + h)],
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      );

  /// 合成文本块：lines 行 × chars 列的小笔画。
  List<FreedrawElement> textBlock(
    String prefix,
    double originX,
    double originY, {
    int lines = 4,
    int chars = 8,
    double charW = 32,
    double charH = 9,
    double charGap = 5,
    double lineGap = 13,
  }) {
    return [
      for (var l = 0; l < lines; l++)
        for (var c = 0; c < chars; c++)
          stroke(
            '$prefix-l$l-c$c',
            originX + c * (charW + charGap),
            originY + l * (charH + lineGap),
            charW,
            charH,
          ),
    ];
  }

  /// 把分段结果折叠成可比对的花名册（每段一行排序 id）。
  List<String> rosterOf(List<dynamic> segments) {
    final lines = [
      for (final segment in segments)
        (segment.strokeIds as List<String>).join(','),
    ]..sort();
    return lines;
  }

  test('空输入与单笔画', () {
    final segmenter = InkRegionSegmenter();
    expect(segmenter.segment([]), isEmpty);
    final one = segmenter.segment([stroke('s1', 0, 0, 12, 8)]);
    expect(one, hasLength(1));
    expect(one.single.strokeIds, ['s1']);
    expect(one.single.lineDirection, SegmentLineDirection.horizontal);
  });

  test('重复 id 构造失败', () {
    final segmenter = InkRegionSegmenter();
    expect(
      () => segmenter.segment([
        stroke('dup', 0, 0, 5, 5),
        stroke('dup', 50, 50, 5, 5),
      ]),
      throwsArgumentError,
    );
  });

  test('确定性：同输入两次分段完全一致（含段 id）', () {
    final strokes = [...textBlock('a', 0, 0), ...textBlock('b', 400, 0)];
    final segmenter = InkRegionSegmenter();
    final first = segmenter.segment(strokes);
    final second = segmenter.segment(strokes);
    expect(
      [for (final s in first) s.toString()],
      [for (final s in second) s.toString()],
    );
  });

  test('双栏保持分离且列号 0/1', () {
    final strokes = [...textBlock('a', 0, 0), ...textBlock('b', 600, 0)];
    final segments = InkRegionSegmenter().segment(strokes);
    expect(segments.length, 2, reason: '两栏应为两个区域');
    final columnIndexes = {for (final s in segments) s.columnIndex};
    expect(columnIndexes, {0, 1});
    for (final segment in segments) {
      expect(
        segment.strokeIds.every(
          (id) => id.startsWith(segment.columnIndex == 0 ? 'a-' : 'b-'),
        ),
        isTrue,
        reason: '栏内不得混入另一栏笔画',
      );
    }
  });

  test('缩放/平移不变量：membership、列数、方向均不变', () {
    final base = [...textBlock('a', 0, 0), ...textBlock('b', 600, 0)];
    final scaled = [
      for (final e in base)
        stroke(e.id.value, e.x * 3, e.y * 3, e.width * 3, e.height * 3),
    ];
    final translated = [
      for (final e in base)
        stroke(e.id.value, e.x + 10000, e.y + 5000, e.width, e.height),
    ];
    final segmenter = InkRegionSegmenter();
    final baseRoster = rosterOf(segmenter.segment(base));
    expect(rosterOf(segmenter.segment(scaled)), baseRoster);
    expect(rosterOf(segmenter.segment(translated)), baseRoster);

    final baseSegments = segmenter.segment(base);
    final scaledSegments = segmenter.segment(scaled);
    expect(scaledSegments.length, baseSegments.length);
    expect(
      [for (final s in scaledSegments) s.lineDirection],
      [for (final s in baseSegments) s.lineDirection],
    );
  });

  test('倾斜不变量：整体旋转 7° 后 membership 不变，skew 估计非零', () {
    final base = textBlock('a', 0, 0);
    final radians = 7 * math.pi / 180;
    final cosR = math.cos(radians);
    final sinR = math.sin(radians);
    (double, double) rotate(double x, double y) =>
        (x * cosR - y * sinR, x * sinR + y * cosR);
    final tilted = <FreedrawElement>[];
    for (final e in base) {
      final corners = [
        rotate(e.x, e.y),
        rotate(e.x + e.width, e.y),
        rotate(e.x, e.y + e.height),
        rotate(e.x + e.width, e.y + e.height),
      ];
      final minX = corners.map((c) => c.$1).reduce(math.min);
      final maxX = corners.map((c) => c.$1).reduce(math.max);
      final minY = corners.map((c) => c.$2).reduce(math.min);
      final maxY = corners.map((c) => c.$2).reduce(math.max);
      tilted.add(stroke(e.id.value, minX, minY, maxX - minX, maxY - minY));
    }
    final segmenter = InkRegionSegmenter();
    final baseRoster = rosterOf(segmenter.segment(base));
    final tiltedSegments = segmenter.segment(tilted);
    expect(
      rosterOf(tiltedSegments),
      baseRoster,
      reason: 'deskew 应把倾斜文本归位到与水平文本相同的分组',
    );
    expect(
      tiltedSegments.first.skewRadians,
      greaterThan(0.03),
      reason: '7° 倾斜应被估计出来',
    );
  });

  test('竖排几何：窄高堆叠笔画判为 vertical', () {
    final vertical = [
      for (var i = 0; i < 8; i++) stroke('v-$i', 100, i * 26.0, 10, 16),
    ];
    final segments = InkRegionSegmenter().segment(vertical);
    expect(segments, hasLength(1));
    expect(segments.single.lineDirection, SegmentLineDirection.vertical);
  });

  test('小样本与全配对 oracle 等价（确定性随机 120 笔画）', () {
    final random = math.Random(42);
    final strokes = <FreedrawElement>[
      for (var i = 0; i < 120; i++)
        stroke(
          'r-${i.toString().padLeft(3, '0')}',
          random.nextDouble() * 900,
          random.nextDouble() * 1200,
          6 + random.nextDouble() * 40,
          5 + random.nextDouble() * 14,
        ),
    ];
    final oracle = oraclePartition(strokes, policy);
    final actual = rosterOf(InkRegionSegmenter().segment(strokes));
    expect(actual, oracle, reason: '网格邻接必须与全配对 oracle 逐组等价');
  });

  test('3000 笔画不跑 O(N²)：网格评估次数线性-ish 上界', () {
    final random = math.Random(7);
    // 300 行 × 10 列模拟高密度手写页
    final strokes = <FreedrawElement>[];
    var n = 0;
    for (var line = 0; line < 300; line++) {
      for (var c = 0; c < 10; c++) {
        strokes.add(
          stroke(
            'p-${n++}',
            60 + c * 46 + random.nextDouble() * 4,
            40 + line * 23 + random.nextDouble() * 4,
            30,
            8 + random.nextDouble() * 4,
          ),
        );
      }
    }
    expect(strokes.length, 3000);
    final segmenter = InkRegionSegmenter();
    final segments = segmenter.segment(strokes);
    expect(segments, isNotEmpty);
    // N²=9,000,000；线性-ish 上界断言（网格每查询常数候选）。
    // 上界取 N×800：oracle 等价已由上一用例保证，这里只看复杂度形态。
    expect(
      segmenter.lastEvaluationCount,
      lessThan(3000 * 800),
      reason: '评估次数必须远低于 N²，否则退化为全配对',
    );
  });
}

/// 全配对 oracle：逐对复刻管线规则（局部尺度/右邻 deskew/旋转帧邻接），
/// 与网格实现无关地计算期望分组。
List<String> oraclePartition(
  List<FreedrawElement> strokes,
  SegmentationPolicy policy,
) {
  final boxes = [
    for (final e in strokes)
      StrokeBox(
        id: e.id.value,
        left: e.x,
        top: e.y,
        width: e.width,
        height: e.height,
      ),
  ]..sort((a, b) => a.id.compareTo(b.id));

  double median(List<double> v) {
    final sorted = [...v]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  final medianHeight = median([for (final b in boxes) b.height]);
  final radius = policy.neighborRadiusFactor * medianHeight;

  final localScale = <String, double>{};
  final rightNeighbor = <String, String>{};
  for (final box in boxes) {
    final near = <StrokeBox>[];
    for (final other in boxes) {
      if (other.id == box.id) continue;
      if (box.gapTo(other) <= radius) near.add(other);
    }
    localScale[box.id] = median([box.height, for (final n in near) n.height]);
    StrokeBox? nearestRight;
    var nearestDistance = double.infinity;
    for (final other in near) {
      final dx = other.centerX - box.centerX;
      final dy = other.centerY - box.centerY;
      if (dx <= 0 || dy.abs() > dx) continue;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestRight = other;
      }
    }
    if (nearestRight != null) rightNeighbor[box.id] = nearestRight.id;
  }

  // deskew 直方图（与实现同规则）
  final votes = <double>[];
  for (final box in boxes) {
    final targetId = rightNeighbor[box.id];
    if (targetId == null) continue;
    final target = boxes.firstWhere((b) => b.id == targetId);
    final angle = math.atan2(
      target.centerY - box.centerY,
      target.centerX - box.centerX,
    );
    if (angle.abs() <= policy.maxDeskewRadians * 2) votes.add(angle);
  }
  var skew = 0.0;
  if (votes.length >= policy.minNeighborVotesForDeskew) {
    final bins = <int, int>{};
    for (final v in votes) {
      final bin = (v / policy.deskewBinRadians).floor();
      bins[bin] = (bins[bin] ?? 0) + 1;
    }
    final bestBin = bins.keys.reduce((a, b) {
      final ca = bins[a]!;
      final cb = bins[b]!;
      if (ca != cb) return ca > cb ? a : b;
      return a < b ? a : b;
    });
    skew = (bestBin + 0.5) * policy.deskewBinRadians;
    skew = math.max(
      -policy.maxDeskewRadians,
      math.min(policy.maxDeskewRadians, skew),
    );
  }

  StrokeBox rotate(StrokeBox box) {
    if (skew == 0) return box;
    final cosR = math.cos(-skew);
    final sinR = math.sin(-skew);
    final pivotX = mean([for (final b in boxes) b.centerX]);
    final pivotY = mean([for (final b in boxes) b.centerY]);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (x, y) in [
      (box.left, box.top),
      (box.right, box.top),
      (box.right, box.bottom),
      (box.left, box.bottom),
    ]) {
      final dx = x - pivotX;
      final dy = y - pivotY;
      final rx = pivotX + dx * cosR - dy * sinR;
      final ry = pivotY + dx * sinR + dy * cosR;
      minX = math.min(minX, rx);
      maxX = math.max(maxX, rx);
      minY = math.min(minY, ry);
      maxY = math.max(maxY, ry);
    }
    return StrokeBox(
      id: box.id,
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  final rotated = {for (final b in boxes) b.id: rotate(b)};
  final parent = <String, String>{};
  String find(String x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]]!;
      x = parent[x]!;
    }
    return x;
  }

  for (final b in boxes) {
    parent.putIfAbsent(b.id, () => b.id);
  }
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i];
      final b = boxes[j];
      final threshold =
          policy.gapFactor * math.max(localScale[a.id]!, localScale[b.id]!);
      if (rotated[a.id]!.gapTo(rotated[b.id]!) <= threshold) {
        parent[find(a.id)] = find(b.id);
      }
    }
  }
  final groups = <String, List<String>>{};
  for (final b in boxes) {
    groups.putIfAbsent(find(b.id), () => []).add(b.id);
  }
  return ([for (final g in groups.values) g.join(',')]..sort());
}
