import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 降级颗粒布点（P1-3 回归）：必须按弧长等距布点（插值到精确弧长位置），
/// 颗粒密度与输入点采样率/书写速度无关——输入链只有最小距离过滤，
/// 按点下标取样会随设备报点率漂移。
void main() {
  int contourCount(Path path) => path.computeMetrics().length;

  test('P1-3: 同一轨迹不同采样密度产出相同颗粒数量', () {
    // 120px 直线，size=6 → 步长 2 → 弧长阈值 0..120 共 61 个颗粒位。
    // 稀疏采样（点距 8 > 步长 2）必须靠插值补齐，而不是每点一颗。
    final dense = [
      for (var x = 0.0; x <= 120.0; x += 1.0) Point(x, 0),
    ];
    final sparse = [
      for (var x = 0.0; x <= 120.0; x += 8.0) Point(x, 0),
    ];
    final densePath = FreedrawRenderer.buildPencilGrainPath(dense, 6);
    final sparsePath = FreedrawRenderer.buildPencilGrainPath(sparse, 6);
    expect(contourCount(densePath), 61);
    expect(
      contourCount(sparsePath),
      contourCount(densePath),
      reason: '颗粒密度不得随报点率漂移',
    );
  });

  test('P1-3: 同输入两次重绘逐段一致（确定性）', () {
    final points = [
      for (var x = 0.0; x <= 90.0; x += 3.5) Point(x, (x / 30).abs()),
    ];
    final a = FreedrawRenderer.buildPencilGrainPath(points, 6);
    final b = FreedrawRenderer.buildPencilGrainPath(points, 6);
    final ma = a.computeMetrics().toList();
    final mb = b.computeMetrics().toList();
    expect(ma.length, mb.length);
    for (var i = 0; i < ma.length; i++) {
      expect(ma[i].length, mb[i].length);
    }
  });

  test('P1-3: 单点输入输出空 Path', () {
    final path = FreedrawRenderer.buildPencilGrainPath(
      const [Point(0, 0)],
      6,
    );
    expect(contourCount(path), 0);
  });

  test('P1: 超长两点笔迹颗粒数量有界（硬上限）', () {
    // 外部导入/无限画布可达的超长笔迹：两个点、长度 1,000,000。若
    // 步长固定为 size/3 会生成数十万子路径阻塞单帧；步长按总长扩大
    // 后子路径数必须落在硬上限附近。
    final path = FreedrawRenderer.buildPencilGrainPath(
      const [Point(0, 0), Point(1000000, 0)],
      6,
    );
    final count = contourCount(path);
    expect(count, greaterThan(0));
    expect(count, lessThanOrEqualTo(FreedrawRenderer.maxGrainCount + 1));
  });
}
