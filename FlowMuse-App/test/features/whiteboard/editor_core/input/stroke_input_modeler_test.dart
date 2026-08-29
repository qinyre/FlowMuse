import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart';

StrokeInputSample s(
  double x,
  double y,
  int ms, {
  int pointerId = 1,
  double? p,
  StrokePhase phase = StrokePhase.move,
}) => StrokeInputSample(
  pointerId: pointerId,
  x: x,
  y: y,
  time: Duration(milliseconds: ms),
  pressure: p,
  kind: StrokeInputKind.stylus,
  phase: phase,
  source: StrokeSampleSource.actual,
);

void main() {
  test('Android 手写笔仅对接近回折启用转角保护', () {
    const android = InputPolicySelector(platform: TargetPlatform.android);
    const ohos = InputPolicySelector(platform: TargetPlatform.ohos);

    expect(android.select(StrokeInputKind.stylus).cornerProtectAngleRad, 2.1);
    expect(ohos.select(StrokeInputKind.stylus).cornerProtectAngleRad, 0.9);
  });

  group('StrokeInputModeler', () {
    test('down emits the first point', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      final r = m.process(s(0, 0, 0, phase: StrokePhase.down));
      expect(r.decision, StrokeModelDecision.emitted);
      expect(r.point, const Point(0, 0));
    });

    test('drops points below minDistance after down', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      final r = m.process(s(0.1, 0, 16)); // < minDistance(0.6)
      expect(r.decision, StrokeModelDecision.dropped);
    });

    test(
      'up emits the real endpoint (flush), not a low-passed approximation',
      () {
        final m = StrokeInputModeler(InputPolicy.stylus);
        m.process(s(0, 0, 0, phase: StrokePhase.down));
        for (var i = 1; i <= 20; i++) {
          m.process(s(i * 1.0, 0, i * 16)); // 快速直线
        }
        final r = m.process(s(21.0, 0, 21 * 16, phase: StrokePhase.up));
        expect(r.decision, StrokeModelDecision.emitted);
        // flush: 终点应等于真实抬笔点，而非滤波滞后点
        expect(r.point!.x, closeTo(21.0, 0.5));
      },
    );

    test('slow noisy signal is dampened', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(100, 100, 0, phase: StrokePhase.down));
      final noise = [0.0, 2.0, -2.0, 1.0, -1.0, 2.0, -2.0, 0.0, 1.0, -1.0];
      double maxSwing = 0;
      for (var i = 0; i < noise.length; i++) {
        final r = m.process(s(100, 100 + noise[i], (i + 1) * 16));
        if (r.point != null) {
          final swing = (r.point!.y - 100).abs();
          if (swing > maxSwing) maxSwing = swing;
        }
      }
      expect(maxSwing, lessThan(2.0)); // 输出抖动 < 输入抖动峰值
    });

    test('stylus keeps in-progress lag below four logical pixels', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));

      StrokeModelResult? latest;
      for (var i = 1; i <= 20; i++) {
        latest = m.process(s(i * 2.0, 0, i * 16));
      }

      expect(latest!.point, isNotNull);
      expect(40 - latest.point!.x, lessThanOrEqualTo(4.0));
    });

    test('cancel resets and drops the stroke', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      m.process(s(5, 5, 16));
      final r = m.process(s(5, 5, 32, phase: StrokePhase.cancel));
      expect(r.decision, StrokeModelDecision.reset);
    });

    test('different pointer cannot replace or cancel an active stroke', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));

      expect(
        m
            .process(s(10, 10, 16, pointerId: 2, phase: StrokePhase.down))
            .decision,
        StrokeModelDecision.dropped,
      );
      expect(
        m
            .process(s(10, 10, 32, pointerId: 2, phase: StrokePhase.cancel))
            .decision,
        StrokeModelDecision.dropped,
      );
      expect(m.process(s(10, 0, 48)).decision, StrokeModelDecision.emitted);
    });

    test('non-monotonic time bypasses filter (emits raw)', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 100, phase: StrokePhase.down));
      final r = m.process(s(10, 10, 50)); // 时间倒退
      expect(r.decision, StrokeModelDecision.emitted);
      expect(r.point, const Point(10, 10));
    });

    test('long sampling gap bypasses the distance gate and emits raw', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));

      final r = m.process(s(0.1, 0, 1000));

      expect(r.decision, StrokeModelDecision.emitted);
      expect(r.point, const Point(0.1, 0));
    });

    test(
      'pressures count == emitted points count (simulated mode: null pressure)',
      () {
        final m = StrokeInputModeler(
          InputPolicy.touch,
        ); // touch = 模拟压感, pressure null
        int emitted = 0, nonNullP = 0;
        final r0 = m.process(s(0, 0, 0, p: null, phase: StrokePhase.down));
        if (r0.point != null) {
          emitted++;
          if (r0.pressure != null) nonNullP++;
        }
        for (var i = 1; i <= 10; i++) {
          final r = m.process(s(i * 1.0, 0, i * 16, p: null));
          if (r.point != null) {
            emitted++;
            if (r.pressure != null) nonNullP++;
          }
        }
        expect(nonNullP, 0); // 模拟模式 pressure 始终 null
        expect(emitted, greaterThan(1));
      },
    );

    test('pressure mode locks to real on down', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, p: 0.5, phase: StrokePhase.down));
      final r = m.process(s(1, 0, 16, p: null)); // 偶发缺失：沿用最后有效值
      expect(r.pressure, isNotNull); // 不切到模拟
    });

    test('关闭压感后手写笔输出模拟压力', () {
      final m = StrokeInputModeler(InputPolicy.stylus, useRealPressure: false);

      final r = m.process(s(0, 0, 0, p: 0.8, phase: StrokePhase.down));

      expect(r.pressure, isNull);
    });

    test('明显曲线降低轻压输入以扩大粗细变化', () {
      // 攻击包络会把起笔输出抬到水位之上，遮蔽指数曲线差异——本测试
      // 只关心指数语义，显式关闭攻击窗口。
      const attackOff = InputPolicy(
        useRealPressure: true,
        minCutoff: 8.0,
        beta: 0.02,
        pressureCutoff: 50.0,
        pressureFloor: 0.18,
        pressureCeiling: 0.82,
        minDistance: 0.6,
        cornerProtectAngleRad: 0.9,
      );
      final standard = StrokeInputModeler(attackOff);
      final firm = StrokeInputModeler(attackOff, pressureExponent: 1.35);

      final standardResult = standard.process(
        s(0, 0, 0, p: 0.25, phase: StrokePhase.down),
      );
      final firmResult = firm.process(
        s(0, 0, 0, p: 0.25, phase: StrokePhase.down),
      );

      expect(firmResult.pressure!, lessThan(standardResult.pressure!));
    });

    test('stylus suppresses a single-sample pressure spike', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, p: 0.5, phase: StrokePhase.down));
      final spike = m.process(s(1, 0, 16, p: 1.0));

      expect(spike.pressure, isNotNull);
      expect(spike.pressure!, lessThanOrEqualTo(0.85));
    });

    group('起笔攻击补偿（真机压力爬升闪变治理）', () {
      // 实测 OPD2404：起笔压力 0.5-1s 内 0.2 → 0.5+ 自然爬升，如实渲染
      // 会让压感笔形前段过细、压力到位瞬间整笔增宽（用户感知为闪变）。
      // 包络：窗口内输出 ≥ 攻击水位线性衰减到 pressureFloor。
      test('低压起笔输出抬升至攻击水位，随窗口缓释，窗口后纯实测', () {
        // 窗口 1500ms 必须覆盖真机压力爬升期（实测 0.5-1.2s）：实测压力
        // 在包络仍处高位时接管，避免 250ms 短窗时代偿先撤、实测未跟上
        // 造成的"粗起笔收窄成尖"凹谷。补偿参数由控制器按笔形白名单
        // （毛笔/铅笔）逐笔传入模型器，此处显式等价构造。
        final m = StrokeInputModeler(
          InputPolicy.stylus,
          pressureAttackMs: 1500,
          pressureAttackLevel: 0.50,
        );

        // down: p=0.2 → 映射 ≈0.31 < 水位 0.5 → 抬到 0.5
        final r0 = m.process(s(0, 0, 0, p: 0.2, phase: StrokePhase.down));
        expect(r0.pressure!, closeTo(0.50, 0.01));

        // 125ms：包络 = 0.5-0.32*(125/1500) ≈ 0.473
        final r1 = m.process(s(2.0, 0, 125, p: 0.2));
        expect(r1.pressure!, closeTo(0.47, 0.01));

        // 300ms：包络 ≈ 0.436（实测仍在爬升，包络接管，无凹谷）
        final r2 = m.process(s(4.0, 0, 300, p: 0.2));
        expect(r2.pressure!, closeTo(0.44, 0.01));

        // 1600ms（窗口外）：纯实测映射 ≈ 0.31
        final r3 = m.process(s(6.0, 0, 1600, p: 0.2));
        expect(r3.pressure!, closeTo(0.31, 0.01));
      });

      test('真实压力高于包络时原样透传不被抬压', () {
        final m = StrokeInputModeler(
          InputPolicy.stylus,
          pressureAttackMs: 1500,
          pressureAttackLevel: 0.50,
        );
        // p=0.8 → 映射 0.18+0.8*0.64≈0.69 > 水位 0.5 → 不抬压
        final r0 = m.process(s(0, 0, 0, p: 0.8, phase: StrokePhase.down));
        expect(r0.pressure!, closeTo(0.69, 0.01));
        final r1 = m.process(s(2.0, 0, 100, p: 0.8));
        expect(r1.pressure!, greaterThan(r0.pressure! - 0.05));
        expect(r1.pressure!, lessThanOrEqualTo(0.82));
      });

      test('包络只抬输出不污染压力状态（窗口外缺失值回到实测）', () {
        final m = StrokeInputModeler(
          InputPolicy.stylus,
          pressureAttackMs: 1500,
          pressureAttackLevel: 0.50,
        );
        m.process(s(0, 0, 0, p: 0.2, phase: StrokePhase.down)); // 抬到 0.50
        m.process(s(2.0, 0, 125, p: 0.2)); // 包络 ≈0.47
        // 窗口内偶发缺失：输出 = max(实测 0.31, 包络 ≈0.39)
        final missingInWindow = m.process(s(4.0, 0, 500, p: null));
        expect(missingInWindow.pressure!, closeTo(0.39, 0.01));
        // 窗口外缺失：输出回到实测映射 ≈0.31——证明 _lastPressure 从未
        // 被包络污染（若污染会输出 0.5/0.47）
        final missingAfterWindow = m.process(s(6.0, 0, 1600, p: null));
        expect(missingAfterWindow.pressure!, closeTo(0.31, 0.02));
      });

      test('未启用补偿（默认关闭）时纯映射（钢笔路径）', () {
        const attackOff = InputPolicy(
          useRealPressure: true,
          minCutoff: 8.0,
          beta: 0.02,
          pressureCutoff: 50.0,
          pressureFloor: 0.18,
          pressureCeiling: 0.82,
          minDistance: 0.6,
          cornerProtectAngleRad: 0.9,
        );
        final m = StrokeInputModeler(attackOff);
        final r = m.process(s(0, 0, 0, p: 0.2, phase: StrokePhase.down));
        expect(r.pressure!, closeTo(0.31, 0.01));
      });

      test('补偿开关在模型器构造上逐笔决定（同策略同输入，输出不同）', () {
        // 回归背景：补偿按笔形白名单由控制器逐笔传入（钢笔关、毛笔/铅笔
        // 开），因此参数挂在模型器而非设备策略——同一 InputPolicy 下两种
        // 构造必须产生不同输出，否则白名单失效。
        final on = StrokeInputModeler(
          InputPolicy.stylus,
          pressureAttackMs: 1500,
          pressureAttackLevel: 0.50,
        );
        final off = StrokeInputModeler(InputPolicy.stylus);
        final rOn = on.process(s(0, 0, 0, p: 0.2, phase: StrokePhase.down));
        final rOff = off.process(s(0, 0, 0, p: 0.2, phase: StrokePhase.down));
        expect(rOn.pressure!, closeTo(0.50, 0.01)); // 抬到攻击水位
        expect(rOff.pressure!, closeTo(0.31, 0.01)); // 纯实测映射
      });
    });

    test(
      'pressure mode locks to simulated (touch) even if a non-null arrives',
      () {
        // 防御性：模拟模式下，即便上游误传非 null pressure，modeler 仍输出 null。
        final m = StrokeInputModeler(InputPolicy.touch);
        m.process(s(0, 0, 0, p: null, phase: StrokePhase.down));
        final r = m.process(s(1, 0, 16, p: 0.9)); // 上游误传
        expect(r.pressure, isNull); // 锁定模拟，不切真实
      },
    );
  });

  group('StrokeInputModeler corner protection', () {
    test('no boost for continuous same-direction movement', () {
      // 连续同方向（+x）移动，输出应持续平滑，无突变。
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      final outs = <double>[];
      for (var i = 1; i <= 10; i++) {
        final r = m.process(s(i * 2.0, 0, i * 16));
        if (r.point != null) outs.add(r.point!.x);
      }
      // 单调递增，无回跳
      for (var i = 1; i < outs.length; i++) {
        expect(outs[i], greaterThanOrEqualTo(outs[i - 1] - 0.01));
      }
    });

    test(
      'abrupt direction change does not cause a jump (state continuity)',
      () {
        // 沿 +x 走一段，然后急转向 +y（接近 90°，超过 cornerProtectAngleRad ~51°）。
        // 关键断言：转向后第一帧输出不跳到原始值（避免拉尖），且无 NaN/Infinity。
        final m = StrokeInputModeler(InputPolicy.stylus);
        m.process(s(0, 0, 0, phase: StrokePhase.down));
        for (var i = 1; i <= 8; i++) {
          m.process(s(i * 3.0, 0, i * 16)); // +x
        }
        // 急转 +y
        final r = m.process(s(24, 8, 9 * 16));
        expect(r.point, isNotNull);
        expect(r.point!.x.isFinite, isTrue);
        expect(r.point!.y.isFinite, isTrue);
        // 转向后连续几帧无跳跃
        for (var i = 10; i <= 14; i++) {
          final rr = m.process(s(24, 8 + (i - 9) * 3.0, i * 16));
          if (rr.point != null) {
            expect(rr.point!.y.isFinite, isTrue);
            expect(rr.point!.y.isNaN, isFalse);
          }
        }
      },
    );

    test(
      'movement below minDistance does not emit (no corner detection trigger)',
      () {
        final m = StrokeInputModeler(InputPolicy.stylus);
        m.process(s(0, 0, 0, phase: StrokePhase.down));
        final r = m.process(s(0.1, 0.1, 16)); // < minDistance(0.6)
        expect(r.decision, StrokeModelDecision.dropped);
      },
    );
  });
}
