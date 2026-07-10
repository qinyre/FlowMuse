import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/one_euro_filter.dart';

void main() {
  group('OneEuroFilter', () {
    test('first value passes through', () {
      final f = OneEuroFilter();
      final v = f.filter(5.0, const Duration(seconds: 1));
      expect(v, 5.0);
    });

    test('smooths a noisy low-speed signal', () {
      // 慢速移动 + 小幅抖动：滤波后幅度应小于输入抖动幅度。
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      final base = 100.0;
      final noise = [0.0, 2.0, -2.0, 1.0, -1.0, 2.0, -2.0, 0.0, 1.0, -1.0];
      var t = const Duration(seconds: 1);
      double lastOut = f.filter(base, t);
      double maxInSwing = 0, maxOutSwing = 0;
      for (final n in noise) {
        t += const Duration(milliseconds: 16);
        final out = f.filter(base + n, t);
        maxInSwing = maxInSwing > n.abs() ? maxInSwing : n.abs();
        maxOutSwing = maxOutSwing > (out - base).abs() ? maxOutSwing : (out - base).abs();
        lastOut = out;
      }
      expect(maxOutSwing, lessThan(maxInSwing));
      expect(lastOut, closeTo(base, 2.0));
    });

    test('follows a fast step with low lag', () {
      // 高速阶跃：滤波输出应在少数采样后接近目标。
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      var t = const Duration(seconds: 1);
      f.filter(0.0, t);
      for (var i = 0; i < 5; i++) {
        t += const Duration(milliseconds: 8);
        f.filter(100.0, t);
      }
      t += const Duration(milliseconds: 8);
      final out = f.filter(100.0, t);
      expect(out, greaterThan(90.0));
    });

    test('bypasses on non-monotonic time', () {
      final f = OneEuroFilter();
      f.filter(10.0, const Duration(seconds: 2));
      // dt <= 0: 直接返回新输入值（旁路）
      final out = f.filter(20.0, const Duration(seconds: 1));
      expect(out, 20.0);
    });

    test('higher cutoff follows the same input more closely', () {
      // One Euro 的关键单调性：高 cutoff = 弱滤波，不能被 alpha 公式写反。
      final low = OneEuroFilter(minCutoff: 1.0, beta: 0.0);
      final high = OneEuroFilter(minCutoff: 8.0, beta: 0.0);
      const t0 = Duration(seconds: 1);
      const t1 = Duration(seconds: 1, milliseconds: 16);
      low.filter(0, t0);
      high.filter(0, t0);
      final lowOut = low.filter(100, t1);
      final highOut = high.filter(100, t1);
      expect(highOut, greaterThan(lowOut));
      expect(highOut, lessThan(100));
    });

    test('reset clears state', () {
      final f = OneEuroFilter();
      f.filter(10.0, const Duration(seconds: 1));
      f.reset();
      expect(f.filter(30.0, const Duration(seconds: 2)), 30.0);
    });

    test('filterWithCutoff reuses state across override (no jump after boost)', () {
      // 关键：转角保护用 overrideCutoff，结束后回到正常 filter 不应跳跃。
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      var t = const Duration(seconds: 1);
      f.filter(0.0, t);
      // 正常帧
      for (var i = 0; i < 5; i++) {
        t += const Duration(milliseconds: 16);
        f.filter(i.toDouble(), t);
      }
      final prevBeforeBoost = t;
      final outBeforeBoost = f.filter(5.0, prevBeforeBoost);
      // 转角帧：overrideCutoff（高 cutoff = 弱滤波）
      t += const Duration(milliseconds: 16);
      final outBoost = f.filterWithCutoff(20.0, t, overrideCutoff: 8.0);
      expect(outBoost, greaterThan(outBeforeBoost)); // boost 帧更贴近原始值（弱滤波）
      // 回到正常 filter：状态连续，输出应介于 boost 原始值与之前之间，无 NaN/Infinity
      t += const Duration(milliseconds: 16);
      final outAfter = f.filter(21.0, t);
      expect(outAfter.isFinite, isTrue);
      expect(outAfter, greaterThan(outBoost - 5.0));
    });

    test('filterWithCutoff(null override) behaves like filter', () {
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      final t = const Duration(seconds: 1);
      f.filter(10.0, t);
      final a = f.filterWithCutoff(20.0, t + const Duration(milliseconds: 16), overrideCutoff: null);
      // 与另一新实例的 filter 输出一致
      final f2 = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      f2.filter(10.0, t);
      final b = f2.filter(20.0, t + const Duration(milliseconds: 16));
      expect(a, closeTo(b, 1e-9));
    });
  });
}
double max(double a, double b) => a > b ? a : b;
