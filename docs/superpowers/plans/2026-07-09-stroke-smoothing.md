# 笔迹平滑书写管线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 FlowMuse-App 跨平台统一书写管线，消除生产 App 笔迹的锯齿与尖锐转角，达成慢速边缘光滑、转角保真、抬笔到位、压感连续。

**Architecture:** 分 6 个子系统、按 spec §7 的 7 个阶段递进。每阶段独立 A/B、可测试、可回退。核心是：新增平台无关 `StrokeInputModeler`（OneEuro 滤波 + 转角保护）吸收并替换现有鸿蒙固定 EMA；`OutlinePathBuilder` 用二次中点法替换 `addPolygon`；wet/dry 完成态分离；录制回放工具链支撑量化验收。`perfect_freehand` 保留，`FreedrawTool` 接口不变。

**Tech Stack:** Flutter (Dart, sdk ^3.11.1)、`perfect_freehand: ^2.5.0`、One Euro Filter（自研纯 Dart，零依赖）、`flutter_test`、`flutter_lints: ^6.0.0`。

## Global Constraints

> 摘自 spec §2.2/§3/§4，所有任务隐含遵守。

- 只有 freedraw 工具经过 `StrokeInputModeler`；选择/擦除/平移走原始坐标，完全不受影响。
- 单活动绘制 pointer：pointer-down 获取绘制所有权，其他 pointer 不进入该笔。本轮不扩展多 pointer 同绘。
- 滤波坐标系固定为 **EditorCanvas local logical pixels**；先在 local 空间建模，再 `screenToScene` 转 scene 坐标。
- 预测点只进湿墨层，永不进持久化/协同；数据流预留 `StrokeSampleSource.predicted`。
- 协同/持久化只发**建模后的稳定干墨 points/pressures**；接收端不重跑滤波器。
- 运行时开关：`OutlineRenderMode { polygon, quadratic }`（debug/test 全局模式，活动笔画期间禁止切换）；滤波用 feature flag 可回退固定 EMA。
- `dt <= 0`/超长间隔/异常坐标 → 旁路滤波直出原始点，不抛异常。
- pressure 缺失保持 null，由 `perfect_freehand` `simulatePressure` 处理，不伪造真实 pressure。
- `PointerCancelEvent` → reset modeler 与 `FreedrawTool`，丢弃未提交笔画，释放活动 pointer。
- pressure 模式锁定：down 时由 InputPolicy 决定本笔是否真实压感；禁止一笔中途切换。
- 二次闭合路径必须显式处理最后一点到第一点的接缝；不产生 NaN/Infinity。
- `FreedrawRenderer` 把 outline 生成与 Path 构建拆成可独立调用的纯函数；debug/test 下由可空 `StrokeRenderMetricsSink` 接收耗时，release 下 sink 为 null 不分配。
- 测试目录约定：`test/features/whiteboard/editor_core/`（已有先例 `harmony_stylus_stroke_smoother_test.dart`）。

## Code Map（实施前必读的现有代码事实）

> 这些是探索阶段已核实的 load-bearing 事实，每个任务都会引用。所有路径相对 `FlowMuse-App/`。

| 事实 | 位置 |
| --- | --- |
| `Point` 类：immutable，含 `+ - * distanceTo`，`const Point(x,y)` | `lib/features/whiteboard/editor_core/src/core/math/point.dart` |
| `EditorCanvas` 的 `Listener` 是原始 PointerEvent 入口，回调在 `:114-170`（含 hover/down/move/up/signal，无 cancel） | `lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart:114` |
| `screenToScene` 会 `roundToDouble()` 两轴；freedraw 必须新增并使用不取整的变换，其他工具可保留整数对齐 | `lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart:33-36` |
| `MarkdrawController` pointer 路由 `onPointerDown/Move/Up` 在 `:1491/1577/1610` | `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` |
| smoother 单实例 `:98`，调用点 down`:1504` move`:1584` up`:1616` | 同上 |
| `_pressureSensitivity` 字段 + setter 同步到 adapter：`:117,253-256` | 同上（`outlineRenderMode` 照此模式新增） |
| `FreedrawTool`：`_points/_pressures/_hasRealPressure/_isDrawing`，commit 在 `onPointerUp` | `lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart` |
| `FreedrawTool.overlay` **不带 pressures**（实时预览无压感）`:117` | 同上 |
| `Tool` 抽象接口 `onPointerDown/Move/Up + overlay + reset` | `lib/features/whiteboard/editor_core/src/editor/tools/tool.dart` |
| `HarmonyStylusStrokeSmoother`：down/move/up/reset，gate=`ohos&&(stylus\|\|invertedStylus)&&freedraw`；`up()` 位置已 flush 真实终点（不再 EMA），仅 pressure 做一次 EMA | `lib/features/whiteboard/editor_core/src/ui/harmony_stylus_stroke_smoother.dart` |
| `FreedrawRenderer.draw(...)`，`isComplete` 硬编码 true 在 `buildOutline()` 内 `:68`，`addPolygon` 在 `:107`；`buildOutline()` 纯函数已提取（`:43-72`） | `lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart` |
| `pointer_pressure.dart`：`reliableStylusPressure`（pressureMin/Max 归一化）+ `shouldDispatchToCreationTool`（touch 抑制），在 `EditorCanvas` Listener 回调中调用 | `lib/features/whiteboard/editor_core/src/ui/pointer_pressure.dart` |
| `RoughCanvasAdapter.drawFreedraw` 在 `:717`，`pressureSensitivity` 字段在 `:714` | `lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart` |
| `element_renderer.dart:159` 调 `adapter.drawFreedraw(..., element.simulatePressure, ...)` | `lib/features/whiteboard/editor_core/src/rendering/element_renderer.dart` |
| `ToolOverlay` 不含 pressures/isComplete | `lib/features/whiteboard/editor_core/src/editor/tool_result.dart:101-137` |
| `FreedrawElement` 无 isComplete 字段 | `lib/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart` |
| 序列化：toJson `excalidraw_json_codec.dart:141-147`，`_parseFreedraw:910` | `lib/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart` |
| `ToolContext` 构造需 `scene`+`viewport`+`selectedIds`（`:77-100`） | `lib/features/whiteboard/editor_core/src/editor/tool_result.dart` |
| 既有测试驱动 controller 而非直接造 tool：`controller.onPointerDown/Move/Up` | `test/features/whiteboard/editor_core/element_creation_bounds_test.dart:56-66` |
| `perfect_freehand: ^2.5.0` | `pubspec.yaml:56` |
| HarmonyOS C 报点预测需 `6.0.0(20)+`，函数 `HMS_HandWrite_GetPredictPoint`，lib `libhandwrite_ndk.z.so`，需 XComponent 取历史点；ArkTS `PointPredictor.getPredictionPoint(TouchEvent)`；不可调预测程度；不支持模拟器；仅中国大陆设备 | `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发指导（C-C++）/pen-point-prediction-c.md` 等 |

---

## 文件结构总览

新建文件（平台无关核心，放 `src/input/`，与 `src/ui/`、`src/rendering/` 平级）：

| 文件 | 职责 |
| --- | --- |
| `src/input/stroke_input_sample.dart` | `StrokeInputSample` + 4 个 enum |
| `src/input/one_euro_filter.dart` | 单轴 One Euro Filter |
| `src/input/stroke_input_modeler.dart` | `StrokeInputModeler`（位置+pressure+转角保护）|
| `src/input/input_policy.dart` | `InputPolicy` + `InputPolicySelector` |
| `src/input/stroke_input_normalizer.dart` | `PointerEvent → StrokeInputSample` |
| `src/input/outline_render_mode.dart` | `OutlineRenderMode` enum |
| `src/input/stroke_render_metrics.dart` | `StrokeRenderMetrics` + `StrokeRenderMetricsSink`（debug/test）|
| `src/input/stroke_recorder.dart` | `StrokeRecorder` + trace（debug/test）|
| `src/input/stroke_replay_runner.dart` | `StrokeReplayRunner`（debug/test）|

修改文件：
- `src/rendering/rough/freedraw_renderer.dart`（OutlinePathBuilder + isComplete 参数 + 纯函数拆分）
- `src/rendering/rough/rough_canvas_adapter.dart`（outlineRenderMode 字段 + isComplete 透传）
- `src/rendering/element_renderer.dart`（透传 isComplete）
- `src/core/elements/freedraw_element.dart`（运行时 isComplete，不入 JSON）
- `src/editor/tool_result.dart`（ToolOverlay 增 pressures）
- `src/editor/tools/freedraw_tool.dart`（overlay 带 pressures + isComplete）
- `src/ui/markdraw_controller.dart`（接入 modeler，移除旧 smoother 路由，buildPreviewElement 带 pressure）
- `src/ui/editor_canvas.dart`（插入 normalizer + cancel + pointer 所有权）
- `src/persistence/excalidraw_json_codec.dart`（确认 isComplete 不入 JSON 的回归测试）

---

## 阶段 0：录制回放基线 + StrokeInputSample（S1+S5）

> 目标：建立可重复样本与确定性回放，作为后续所有 A/B 的度量基础。此阶段 normalizer 只服务 recorder，不动正式绘制路由。

### Task 0.1: StrokeInputSample 模型与枚举

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_input_sample.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart`

**Interfaces:**
- Produces: `StrokeInputSample`、`StrokeInputKind`、`StrokePhase`、`StrokeSampleSource`（见下）

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';

void main() {
  group('StrokeInputSample', () {
    test('constructs with required fields', () {
      const s = StrokeInputSample(
        pointerId: 1,
        x: 10.0,
        y: 20.0,
        time: Duration(milliseconds: 16),
        pressure: 0.5,
        kind: StrokeInputKind.stylus,
        phase: StrokePhase.move,
        source: StrokeSampleSource.actual,
      );
      expect(s.pointerId, 1);
      expect(s.x, 10.0);
      expect(s.y, 20.0);
      expect(s.time, const Duration(milliseconds: 16));
      expect(s.pressure, 0.5);
      expect(s.kind, StrokeInputKind.stylus);
      expect(s.phase, StrokePhase.move);
      expect(s.source, StrokeSampleSource.actual);
    });

    test('pressure may be null', () {
      const s = StrokeInputSample(
        pointerId: 1, x: 0, y: 0, time: Duration.zero,
        pressure: null, kind: StrokeInputKind.mouse,
        phase: StrokePhase.down, source: StrokeSampleSource.actual,
      );
      expect(s.pressure, isNull);
    });

    test('value equality', () {
      const a = StrokeInputSample(
        pointerId: 1, x: 1, y: 2, time: Duration(milliseconds: 5),
        pressure: 0.3, kind: StrokeInputKind.touch,
        phase: StrokePhase.up, source: StrokeSampleSource.actual,
      );
      const b = StrokeInputSample(
        pointerId: 1, x: 1, y: 2, time: Duration(milliseconds: 5),
        pressure: 0.3, kind: StrokeInputKind.touch,
        phase: StrokePhase.up, source: StrokeSampleSource.actual,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart`
Expected: FAIL — Target of URI doesn't exist / `StrokeInputSample` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_input_sample.dart

/// 与 Flutter `PointerDeviceKind` 解耦的输入设备分类。
enum StrokeInputKind { stylus, invertedStylus, touch, mouse, unknown }

/// 笔画事件阶段。
enum StrokePhase { down, move, up, cancel }

/// 样本来源：真实采样 or 预测点（仅湿墨层）。
enum StrokeSampleSource { actual, predicted }

/// 整个书写管线的通用货币：规范化后的单个输入样本。
///
/// 坐标 [x]/[y] 为 EditorCanvas local logical pixels（未做 screenToScene）。
/// [time] 为单调时间戳，是采样率无关滤波的关键。
class StrokeInputSample {
  const StrokeInputSample({
    required this.pointerId,
    required this.x,
    required this.y,
    required this.time,
    required this.pressure,
    required this.kind,
    required this.phase,
    required this.source,
  });

  final int pointerId;
  final double x;
  final double y;
  final Duration time;
  final double? pressure; // null = 无可靠真实压感
  final StrokeInputKind kind;
  final StrokePhase phase;
  final StrokeSampleSource source;

  StrokeInputSample copyWith({
    int? pointerId, double? x, double? y, Duration? time,
    double? pressure, StrokeInputKind? kind, StrokePhase? phase,
    StrokeSampleSource? source,
  }) => StrokeInputSample(
    pointerId: pointerId ?? this.pointerId,
    x: x ?? this.x, y: y ?? this.y, time: time ?? this.time,
    pressure: pressure ?? this.pressure, kind: kind ?? this.kind,
    phase: phase ?? this.phase, source: source ?? this.source,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeInputSample &&
          pointerId == other.pointerId && x == other.x && y == other.y &&
          time == other.time && pressure == other.pressure &&
          kind == other.kind && phase == other.phase && source == other.source;

  @override
  int get hashCode => Object.hash(pointerId, x, y, time, pressure, kind, phase, source);

  @override
  String toString() =>
      'StrokeInputSample(ptr=$pointerId, $x,$y, t=${time.inMicroseconds}µs, '
      'p=$pressure, $kind, $phase, $source)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/stroke_input_sample.dart \
        test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart
git commit -m "feat(stroke): add StrokeInputSample model and enums"
```

---

### Task 0.2: 单轴 One Euro Filter

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/one_euro_filter.dart`
- Test: `test/features/whiteboard/editor_core/input/one_euro_filter_test.dart`

**Interfaces:**
- Produces: `class OneEuroFilter { OneEuroFilter({double minCutoff=1.0, double beta=0.007, double dCutoff=1.0}); double filter(double value, Duration now); double filterWithCutoff(double value, Duration now, {required double? overrideCutoff}); void reset(); }`
- Consumes: none.

> **关于 `filterWithCutoff`**：转角保护需要"复用主滤波器状态、仅临时提高 cutoff"，而不是新建实例（新实例 `_prevTime==null` 会零滤波且丢弃历史，下一帧回到主滤波器时产生跳跃）。`overrideCutoff != null` 时用 `overrideCutoff` 代替 `minCutoff + beta*|deriv|`，但状态（`_prevValue/_prevDeriv/_prevTime`）正常更新，保证连续性。

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/one_euro_filter_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/one_euro_filter_test.dart`
Expected: FAIL — `OneEuroFilter` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/one_euro_filter.dart
import 'dart:math' as math;

/// 1€ Filter (Casiez et al., CHI 2012)：速度自适应低通滤波。
///
/// 低速强滤波抑制手抖，高速弱滤波减少延迟。单轴；位置 X/Y 各用一实例。
/// 参考: https://doi.org/10.1145/2207676.2208639
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double _prevValue = 0;
  double _prevDeriv = 0;
  Duration? _prevTime;

  /// 对 [value] 在时刻 [now] 滤波，返回滤波后的值。
  /// 当 dt <= 0（时间非单调）时旁路，直接返回 [value]。
  double filter(double value, Duration now) =>
      filterWithCutoff(value, now, overrideCutoff: null);

  /// 同 [filter]，但允许用 [overrideCutoff] 临时替换位置滤波的截止频率。
  ///
  /// 用于转角保护：复用本实例的状态（_prevValue/_prevDeriv/_prevTime 正常更新），
  /// 仅本帧用 overrideCutoff 代替 `minCutoff + beta*|deriv|`。传 null 等价于 [filter]。
  /// 这样转角帧结束后回到 [filter] 不会因状态断裂产生跳跃。
  double filterWithCutoff(double value, Duration now, {required double? overrideCutoff}) {
    final prev = _prevTime;
    if (prev == null) {
      _prevValue = value;
      _prevDeriv = 0;
      _prevTime = now;
      return value;
    }

    final dt = (now - prev).inMicroseconds / 1e6;
    if (dt <= 0) {
      // 时间非单调或零间隔：旁路，直接返回原始值并同步状态。
      _prevValue = value;
      _prevTime = now;
      return value;
    }

    final deriv = (value - _prevValue) / dt;
    final dAlpha = _alpha(dCutoff, dt);
    final filteredDeriv = _prevDeriv + dAlpha * (deriv - _prevDeriv);

    final cutoff = overrideCutoff ?? (minCutoff + beta * filteredDeriv.abs());
    final alpha = _alpha(cutoff, dt);
    final filteredValue = _prevValue + alpha * (value - _prevValue);

    _prevValue = filteredValue;
    _prevDeriv = filteredDeriv;
    _prevTime = now;
    return filteredValue;
  }

  void reset() {
    _prevValue = 0;
    _prevDeriv = 0;
    _prevTime = null;
  }

  // 低通系数 alpha，来自一阶低通的离散形式。
  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return dt / (tau + dt);
  }
}
```

> **公式不变量（必须保留为测试）**：相同 `dt` 下，cutoff 越高，`alpha` 越大、输出越接近原始值；相同 cutoff 下，`dt` 越小，`alpha` 越小、平滑越强。不要写成 `tau / (tau + dt)`，那会将两个单调关系完全反转。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/one_euro_filter_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/one_euro_filter.dart \
        test/features/whiteboard/editor_core/input/one_euro_filter_test.dart
git commit -m "feat(stroke): add single-axis One Euro Filter"
```

---

### Task 0.3: StrokeInputModeler（位置 + pressure + 转角保护）

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart`
- Create: `lib/features/whiteboard/editor_core/src/input/input_policy.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_input_modeler_test.dart`

**Interfaces:**
- Consumes: `StrokeInputSample`（Task 0.1）、`OneEuroFilter`（Task 0.2）、`Point`（现有 `core/math/point.dart`）
- Produces:
  - `class InputPolicy { const InputPolicy({this.useRealPressure, this.minCutoff, this.beta, this.pressureCutoff, this.minDistance, this.cornerProtectAngleRad}); static const stylus=...; static const touch=...; static const mouse=...; }`
  - `class InputPolicySelector { const InputPolicySelector(); InputPolicy select(StrokeInputKind kind); }`
  - `enum StrokeModelDecision { emitted, dropped, reset }`
  - `class StrokeModelResult { final Point? point; final double? pressure; final StrokeModelDecision decision; final String? reason; const StrokeModelResult.emitted(...); const StrokeModelResult.dropped(String reason); const StrokeModelResult.reset(); }`
  - `class StrokeInputModeler { StrokeInputModeler(this.policy); StrokeModelResult process(StrokeInputSample sample); void reset({String? reason}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_input_modeler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart';

StrokeInputSample s(double x, double y, int ms,
    {double? p, StrokePhase phase = StrokePhase.move}) => StrokeInputSample(
  pointerId: 1, x: x, y: y, time: Duration(milliseconds: ms),
  pressure: p, kind: StrokeInputKind.stylus, phase: phase,
  source: StrokeSampleSource.actual,
);

void main() {
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

    test('up emits the real endpoint (flush), not a low-passed approximation', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      for (var i = 1; i <= 20; i++) {
        m.process(s(i * 1.0, 0, i * 16)); // 快速直线
      }
      final r = m.process(s(21.0, 0, 21 * 16, phase: StrokePhase.up));
      expect(r.decision, StrokeModelDecision.emitted);
      // flush: 终点应等于真实抬笔点，而非滤波滞后点
      expect(r.point!.x, closeTo(21.0, 0.5));
    });

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

    test('cancel resets and drops the stroke', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      m.process(s(5, 5, 16));
      final r = m.process(s(5, 5, 32, phase: StrokePhase.cancel));
      expect(r.decision, StrokeModelDecision.reset);
    });

    test('non-monotonic time bypasses filter (emits raw)', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 100, phase: StrokePhase.down));
      final r = m.process(s(10, 10, 50)); // 时间倒退
      expect(r.decision, StrokeModelDecision.emitted);
      expect(r.point, const Point(10, 10));
    });

    test('pressures count == emitted points count (simulated mode: null pressure)', () {
      final m = StrokeInputModeler(InputPolicy.touch); // touch = 模拟压感, pressure null
      int emitted = 0, nonNullP = 0;
      final r0 = m.process(s(0, 0, 0, p: null, phase: StrokePhase.down));
      if (r0.point != null) { emitted++; if (r0.pressure != null) nonNullP++; }
      for (var i = 1; i <= 10; i++) {
        final r = m.process(s(i * 1.0, 0, i * 16, p: null));
        if (r.point != null) { emitted++; if (r.pressure != null) nonNullP++; }
      }
      expect(nonNullP, 0); // 模拟模式 pressure 始终 null
      expect(emitted, greaterThan(1));
    });

    test('pressure mode locks to real on down', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, p: 0.5, phase: StrokePhase.down));
      final r = m.process(s(1, 0, 16, p: null)); // 偶发缺失：沿用最后有效值
      expect(r.pressure, isNotNull); // 不切到模拟
    });

    test('pressure mode locks to simulated (touch) even if a non-null arrives', () {
      // 防御性：模拟模式下，即便上游误传非 null pressure，modeler 仍输出 null。
      final m = StrokeInputModeler(InputPolicy.touch);
      m.process(s(0, 0, 0, p: null, phase: StrokePhase.down));
      final r = m.process(s(1, 0, 16, p: 0.9)); // 上游误传
      expect(r.pressure, isNull); // 锁定模拟，不切真实
    });
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

    test('abrupt direction change does not cause a jump (state continuity)', () {
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
    });

    test('movement below minDistance does not emit (no corner detection trigger)', () {
      final m = StrokeInputModeler(InputPolicy.stylus);
      m.process(s(0, 0, 0, phase: StrokePhase.down));
      final r = m.process(s(0.1, 0.1, 16)); // < minDistance(0.6)
      expect(r.decision, StrokeModelDecision.dropped);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/stroke_input_modeler_test.dart`
Expected: FAIL — `InputPolicy` / `StrokeInputModeler` undefined.

- [ ] **Step 3: Write input_policy.dart**

```dart
// lib/features/whiteboard/editor_core/src/input/input_policy.dart
import 'stroke_input_sample.dart';

/// 单一输入设备的滤波策略。最终渲染算法各端一致，仅输入策略不同。
class InputPolicy {
  const InputPolicy({
    required this.useRealPressure,
    required this.minCutoff,
    required this.beta,
    required this.pressureCutoff,
    required this.minDistance,
    required this.cornerProtectAngleRad,
  });

  /// 本笔是否使用真实压感（down 时锁定）。
  final bool useRealPressure;
  final double minCutoff;
  final double beta;
  final double pressureCutoff;
  /// 最小移动距离门限，低于此距离的 move 被丢弃（去重）。
  final double minDistance;
  /// 转角保护阈值：方向夹角超过此值时临时提高响应速度（弧度）。
  final double cornerProtectAngleRad;

  /// 手写笔：真实压感 + 自适应位置/压感滤波。
  static const stylus = InputPolicy(
    useRealPressure: true,
    minCutoff: 1.0, beta: 0.007,
    pressureCutoff: 1.0,
    minDistance: 0.6,
    cornerProtectAngleRad: 0.9, // ~51°
  );

  /// 手指（未来启用 finger drawing 时）：模拟压感 + 较保守滤波。
  static const touch = InputPolicy(
    useRealPressure: false,
    minCutoff: 1.2, beta: 0.005,
    pressureCutoff: 1.0,
    minDistance: 0.8,
    cornerProtectAngleRad: 0.9,
  );

  /// 鼠标：默认不强滤波，只去重 + 最小距离，避免直线操作拖尾。
  static const mouse = InputPolicy(
    useRealPressure: false,
    minCutoff: 1000, beta: 0.0, // 极高 cutoff ≈ 几乎不滤波
    pressureCutoff: 1000,
    minDistance: 0.5,
    cornerProtectAngleRad: 0.6,
  );
}

class InputPolicySelector {
  const InputPolicySelector();
  InputPolicy select(StrokeInputKind kind) {
    switch (kind) {
      case StrokeInputKind.stylus:
      case StrokeInputKind.invertedStylus:
        return InputPolicy.stylus;
      case StrokeInputKind.touch:
        return InputPolicy.touch;
      case StrokeInputKind.mouse:
        return InputPolicy.mouse;
      case StrokeInputKind.unknown:
        return InputPolicy.mouse; // 未知设备走保守路线
    }
  }
}
```

- [ ] **Step 4: Write stroke_input_modeler.dart**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart
import 'dart:math' as math;
import '../core/math/point.dart';
import 'one_euro_filter.dart';
import 'input_policy.dart';
import 'stroke_input_sample.dart';

enum StrokeModelDecision { emitted, dropped, reset }

class StrokeModelResult {
  final Point? point;
  final double? pressure;
  final StrokeModelDecision decision;
  final String? reason;

  const StrokeModelResult._({
    this.point, this.pressure, required this.decision, this.reason,
  });
  const StrokeModelResult.emitted(Point point, double? pressure)
      : point = point, pressure = pressure, decision = StrokeModelDecision.emitted, reason = null;
  const StrokeModelResult.dropped(String this.reason)
      : point = null, pressure = null, decision = StrokeModelDecision.dropped;
  const StrokeModelResult.reset({String? reason})
      : point = null, pressure = null, decision = StrokeModelDecision.reset, this.reason = reason;
}

/// 平台无关输入建模器：OneEuro 位置滤波 + 独立 pressure 滤波 + 转角保护 + 终点 flush。
///
/// 单个活动 stroke：down 获取 pointer 所有权，up/cancel 释放。无 Flutter 依赖。
class StrokeInputModeler {
  StrokeInputModeler(this.policy);

  final InputPolicy policy;

  OneEuroFilter? _xFilter;
  OneEuroFilter? _yFilter;
  OneEuroFilter? _pressureFilter;

  int? _ownerPointerId;
  Point? _lastEmitted;
  double? _lastPressure;     // 真实模式下沿用最后有效值
  Duration? _lastTime;
  Point? _lastDir;           // 上一段方向向量（转角保护用）

  bool get _isActive => _ownerPointerId != null;

  StrokeModelResult process(StrokeInputSample sample) {
    switch (sample.phase) {
      case StrokePhase.down:
        _initialize(sample);
        return StrokeModelResult.emitted(Point(sample.x, sample.y), _pressureOut(sample.pressure));
      case StrokePhase.move:
        return _move(sample);
      case StrokePhase.up:
        return _up(sample);
      case StrokePhase.cancel:
        reset(reason: 'cancel');
        return const StrokeModelResult.reset(reason: 'cancel');
    }
  }

  void reset({String? reason}) {
    _xFilter = null;
    _yFilter = null;
    _pressureFilter = null;
    _ownerPointerId = null;
    _lastEmitted = null;
    _lastPressure = null;
    _lastTime = null;
    _lastDir = null;
  }

  void _initialize(StrokeInputSample s) {
    _ownerPointerId = s.pointerId;
    _xFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _yFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _pressureFilter = OneEuroFilter(minCutoff: policy.pressureCutoff, beta: 0.0);
    _lastEmitted = Point(s.x, s.y);
    _lastPressure = policy.useRealPressure ? s.pressure : null;
    _lastTime = s.time;
    _lastDir = null;
  }

  StrokeModelResult _move(StrokeInputSample s) {
    if (!_isActive) {
      return const StrokeModelResult.dropped('not active');
    }
    final last = _lastEmitted;
    if (last == null) {
      // 防御：_isActive 为 true 但 _lastEmitted 为 null（理论上 _initialize 已设置）。
      // 按 down 处理：直接发射原始点并初始化滤波器状态。
      _initializeAfterGap(s);
      return StrokeModelResult.emitted(Point(s.x, s.y), _pressureOut(s.pressure));
    }
    // 最小距离门限（相对上一个发射点）
    final raw = Point(s.x, s.y);
    if (raw.distanceTo(last) < policy.minDistance) {
      return const StrokeModelResult.dropped('minDistance');
    }
    final out = _filterPosition(s, raw, boostForCorner: _detectCornerBoost(raw, last));
    _lastEmitted = out;
    _lastTime = s.time;
    return StrokeModelResult.emitted(out, _pressureOut(s.pressure));
  }

  void _initializeAfterGap(StrokeInputSample s) {
    _xFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _yFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _pressureFilter = OneEuroFilter(minCutoff: policy.pressureCutoff, beta: 0.0);
    _lastEmitted = Point(s.x, s.y);
    _lastTime = s.time;
  }

  StrokeModelResult _up(StrokeInputSample s) {
    if (!_isActive) {
      return const StrokeModelResult.dropped('up without active stroke');
    }
    // 终点 flush：直接用真实抬笔点，不做低通截短。
    final real = Point(s.x, s.y);
    _lastTime = s.time;
    // 若真实终点已通过 move 进入点列，调用方负责去重（见 controller 改造）。
    final result = StrokeModelResult.emitted(real, _pressureOut(s.pressure));
    reset(reason: 'up');
    return result;
  }

  /// 位置滤波。转角保护通过 filterWithCutoff 复用主滤波器状态、仅临时提高 cutoff，
  /// 避免新建实例导致状态断裂（见 OneEuroFilter.filterWithCutoff 注释）。
  Point _filterPosition(StrokeInputSample s, Point raw, {required bool boostForCorner}) {
    final override = boostForCorner ? policy.minCutoff * 8 : null;
    final fx = _xFilter!.filterWithCutoff(raw.x, s.time, overrideCutoff: override);
    final fy = _yFilter!.filterWithCutoff(raw.y, s.time, overrideCutoff: override);
    return Point(fx, fy);
  }

  bool _detectCornerBoost(Point raw, Point last) {
    final dir = raw - last;
    if (dir == Point.zero) return false;
    final prev = _lastDir;
    _lastDir = dir;
    if (prev == null || prev == Point.zero) return false;
    final angle = _absAngleBetween(prev, dir);
    return angle > policy.cornerProtectAngleRad;
  }

  /// 两方向向量的绝对夹角 [0, π]。只关心转弯幅度，不关心方向（故用 det.abs()）。
  double _absAngleBetween(Point a, Point b) {
    final dot = a.x * b.x + a.y * b.y;
    final det = a.x * b.y - a.y * b.x;
    return math.atan2(det.abs(), dot);
  }

  double? _pressureOut(double? raw) {
    if (!policy.useRealPressure) return null; // 模拟模式：始终 null，交 perfect_freehand
    if (raw != null) {
      _lastPressure = _pressureFilter!.filter(raw, _lastTime ?? Duration.zero);
    }
    return _lastPressure; // 偶发缺失沿用最后有效值
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/stroke_input_modeler_test.dart`
Expected: PASS (13 tests：8 基础 + 3 转角保护 + 2 pressure 锁定补充). 若 `slow noisy` / `fast step` 边界值不达标，微调 `InputPolicy.stylus` 的 minCutoff/beta 后重跑（参数是实验起点，见 spec §3.2）。

- [ ] **Step 6: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/input_policy.dart \
        lib/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart \
        test/features/whiteboard/editor_core/input/stroke_input_modeler_test.dart
git commit -m "feat(stroke): add StrokeInputModeler (OneEuro + corner protect + flush)

- 转角保护通过 filterWithCutoff 复用主滤波器状态（无状态断裂）
- pressure 模式锁定：down 时锁定真实/模拟，禁止一笔中途切换
- _move 含 _lastEmitted 空指针防护"
```

---

### Task 0.4: OutlineRenderMode 枚举

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/outline_render_mode.dart`
- Test: `test/features/whiteboard/editor_core/input/outline_render_mode_test.dart`

**Interfaces:**
- Produces: `enum OutlineRenderMode { polygon, quadratic }`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/outline_render_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';

void main() {
  test('has polygon and quadratic variants', () {
    expect(OutlineRenderMode.values, contains(OutlineRenderMode.polygon));
    expect(OutlineRenderMode.values, contains(OutlineRenderMode.quadratic));
    expect(OutlineRenderMode.values.length, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/outline_render_mode_test.dart`
Expected: FAIL — `OutlineRenderMode` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/outline_render_mode.dart

/// Outline 渲染模式（debug/test 全局 A/B 开关）。
/// - polygon：现有 addPolygon 直线段（对照基线）。
/// - quadratic：perfect-freehand 官方二次中点法（平滑曲线）。
enum OutlineRenderMode { polygon, quadratic }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/outline_render_mode_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/outline_render_mode.dart \
        test/features/whiteboard/editor_core/input/outline_render_mode_test.dart
git commit -m "feat(stroke): add OutlineRenderMode enum"
```

---

### Task 0.5: StrokeRenderMetrics 与 Sink

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_render_metrics_test.dart`

**Interfaces:**
- Produces:
  - `class StrokeRenderMetrics { final int outlinePointCount; final Duration getStrokeDuration; final Duration pathBuildDuration; const StrokeRenderMetrics(...); }`
  - `abstract class StrokeRenderMetricsSink { void onMetrics(StrokeRenderMetrics m); }`（release 下 renderer 持有 null sink）

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_render_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';

void main() {
  test('StrokeRenderMetrics holds values', () {
    const m = StrokeRenderMetrics(
      outlinePointCount: 42,
      getStrokeDuration: Duration(microseconds: 120),
      pathBuildDuration: Duration(microseconds: 30),
    );
    expect(m.outlinePointCount, 42);
    expect(m.getStrokeDuration, const Duration(microseconds: 120));
    expect(m.pathBuildDuration, const Duration(microseconds: 30));
  });

  test('sink receives metrics', () {
    final captured = <StrokeRenderMetrics>[];
    final sink = _ListSink(captured);
    sink.onMetrics(const StrokeRenderMetrics(
      outlinePointCount: 1,
      getStrokeDuration: Duration.zero,
      pathBuildDuration: Duration.zero,
    ));
    expect(captured.length, 1);
    expect(captured.first.outlinePointCount, 1);
  });
}

class _ListSink extends StrokeRenderMetricsSink {
  _ListSink(this.list);
  final List<StrokeRenderMetrics> list;
  @override
  void onMetrics(StrokeRenderMetrics m) => list.add(m);
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL.

- [ ] **Step 3: Write implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart

/// 单笔渲染的 CPU 性能指标。
///
/// 注意：Canvas.drawPath 的耗时只能衡量命令提交，不代表 GPU/raster；
/// 端到端帧性能应使用 Flutter FrameTiming / DevTools。
class StrokeRenderMetrics {
  const StrokeRenderMetrics({
    required this.outlinePointCount,
    required this.getStrokeDuration,
    required this.pathBuildDuration,
  });
  final int outlinePointCount;
  final Duration getStrokeDuration;
  final Duration pathBuildDuration;

  @override
  String toString() =>
      'StrokeRenderMetrics(outline=$outlinePointCount, '
      'getStroke=${getStrokeDuration.inMicroseconds}µs, '
      'path=${pathBuildDuration.inMicroseconds}µs)';
}

/// debug/test 下接收指标；release 下 renderer 持有 null sink 不分配。
abstract class StrokeRenderMetricsSink {
  void onMetrics(StrokeRenderMetrics metrics);
}
```

- [ ] **Step 4: Run test to verify it passes** → Expected PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart \
        test/features/whiteboard/editor_core/input/stroke_render_metrics_test.dart
git commit -m "feat(stroke): add StrokeRenderMetrics and sink"
```

---

### Task 0.6: StrokeRecorder（debug/test）

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_recorder.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_recorder_test.dart`

**Interfaces:**
- Consumes: `StrokeInputSample`（Task 0.1）
- Produces:
  - `class StrokeRecording { final List<StrokeInputSample> samples; final double viewportZoom; final List<double> viewportTransform; final String? buildVersion; final String? deviceInfo; const StrokeRecording(...); Map<String,dynamic> toJson(); static StrokeRecording fromJson(Map<String,dynamic> json); }`
  - `class StrokeRecorder { void record(StrokeInputSample sample, {required double viewportZoom, required List<double> viewportTransform}); StrokeRecording finish({String? buildVersion, String? deviceInfo}); void clear(); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_recorder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';

StrokeInputSample s(int ms, StrokePhase phase) => StrokeInputSample(
  pointerId: 1, x: ms.toDouble(), y: 0.0, time: Duration(milliseconds: ms),
  pressure: 0.5, kind: StrokeInputKind.stylus, phase: phase,
  source: StrokeSampleSource.actual,
);

void main() {
  test('records samples and viewport metadata, round-trips JSON', () {
    final rec = StrokeRecorder();
    rec.record(s(0, StrokePhase.down), viewportZoom: 1.0, viewportTransform: [1,0,0,1,0,0]);
    rec.record(s(16, StrokePhase.move), viewportZoom: 1.0, viewportTransform: [1,0,0,1,0,0]);
    final rec1 = rec.finish(buildVersion: 'test', deviceInfo: 'unit');

    final json = rec1.toJson();
    final rec2 = StrokeRecording.fromJson(json);

    expect(rec2.samples.length, 2);
    expect(rec2.samples.first.phase, StrokePhase.down);
    expect(rec2.samples.last.x, 16.0);
    expect(rec2.viewportZoom, 1.0);
    expect(rec2.buildVersion, 'test');
    expect(rec2.deviceInfo, 'unit');
    // 确定性：相同输入 → 相同录制
    expect(rec2.samples, rec1.samples);
  });

  test('clear empties the recorder', () {
    final rec = StrokeRecorder();
    rec.record(s(0, StrokePhase.down), viewportZoom: 1, viewportTransform: [1,0,0,1,0,0]);
    rec.clear();
    final r = rec.finish();
    expect(r.samples, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL.

- [ ] **Step 3: Write implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_recorder.dart
import 'dart:convert';
import 'stroke_input_sample.dart';

/// 一段录制：规范化样本序列 + viewport 元数据 + 构建信息。
class StrokeRecording {
  const StrokeRecording({
    required this.samples,
    required this.viewportZoom,
    required this.viewportTransform,
    this.buildVersion,
    this.deviceInfo,
  });

  final List<StrokeInputSample> samples;
  final double viewportZoom;
  /// 仿射变换 [a,b,c,d,e,f]（scene = a*localX + c*localY + e, ...）。
  final List<double> viewportTransform;
  final String? buildVersion;
  final String? deviceInfo;

  Map<String, dynamic> toJson() => {
    'samples': [for (final s in samples) _sampleToJson(s)],
    'viewportZoom': viewportZoom,
    'viewportTransform': viewportTransform,
    'buildVersion': buildVersion,
    'deviceInfo': deviceInfo,
  };

  static StrokeRecording fromJson(Map<String, dynamic> json) => StrokeRecording(
    samples: (json['samples'] as List)
        .map((e) => _sampleFromJson(e as Map<String, dynamic>))
        .toList(),
    viewportZoom: (json['viewportZoom'] as num).toDouble(),
    viewportTransform: (json['viewportTransform'] as List).map((e) => (e as num).toDouble()).toList(),
    buildVersion: json['buildVersion'] as String?,
    deviceInfo: json['deviceInfo'] as String?,
  );

  @override
  String toString() => 'StrokeRecording(${samples.length} samples, zoom=$viewportZoom)';

  static Map<String, dynamic> _sampleToJson(StrokeInputSample s) => {
    'pointerId': s.pointerId, 'x': s.x, 'y': s.y,
    'timeUs': s.time.inMicroseconds, 'pressure': s.pressure,
    'kind': s.kind.name, 'phase': s.phase.name, 'source': s.source.name,
  };
  static StrokeInputSample _sampleFromJson(Map<String, dynamic> m) {
    return StrokeInputSample(
      pointerId: m['pointerId'] as int,
      x: (m['x'] as num).toDouble(), y: (m['y'] as num).toDouble(),
      time: Duration(microseconds: m['timeUs'] as int),
      pressure: (m['pressure'] as num?)?.toDouble(),
      kind: StrokeInputKind.values.byName(m['kind'] as String),
      phase: StrokePhase.values.byName(m['phase'] as String),
      source: StrokeSampleSource.values.byName(m['source'] as String),
    );
  }
}

/// debug/test 用录制器：收集规范化样本与 viewport 元数据。
class StrokeRecorder {
  final List<StrokeInputSample> _samples = [];
  double _zoom = 1.0;
  List<double> _transform = const [1,0,0,1,0,0];

  void record(StrokeInputSample sample, {required double viewportZoom, required List<double> viewportTransform}) {
    _samples.add(sample);
    _zoom = viewportZoom;
    _transform = viewportTransform;
  }

  StrokeRecording finish({String? buildVersion, String? deviceInfo}) => StrokeRecording(
    samples: List.unmodifiable(_samples),
    viewportZoom: _zoom,
    viewportTransform: List.unmodifiable(_transform),
    buildVersion: buildVersion,
    deviceInfo: deviceInfo,
  );

  void clear() { _samples.clear(); _zoom = 1.0; _transform = const [1,0,0,1,0,0]; }
}
```

- [ ] **Step 4: Run test to verify it passes** → Expected PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/stroke_recorder.dart \
        test/features/whiteboard/editor_core/input/stroke_recorder_test.dart
git commit -m "feat(stroke): add StrokeRecorder (debug/test)"
```

---

### Task 0.7: StrokeReplayRunner + 确定性自检门槛

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_replay_runner_test.dart`

**Interfaces:**
- Consumes: `StrokeRecording`（Task 0.6）、`StrokeInputModeler`（Task 0.3）、`StrokeRenderMetricsSink`（Task 0.5）
- Produces:
  - `class ReplayResult { final List<Point> emittedPoints; final List<double?> emittedPressures; final List<StrokeRenderMetrics> perPointMetrics; const ReplayResult(...); }`
  - `class StrokeReplayRunner { ReplayResult run(StrokeRecording recording, {required StrokeInputModeler modeler, StrokeRenderMetricsSink? metricsSink}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_replay_runner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart';

StrokeInputSample s(double x, double y, int ms, StrokePhase phase) => StrokeInputSample(
  pointerId: 1, x: x, y: y, time: Duration(milliseconds: ms),
  pressure: 0.5, kind: StrokeInputKind.stylus, phase: phase,
  source: StrokeSampleSource.actual,
);

StrokeRecording sampleRecording() {
  final r = StrokeRecorder();
  r.record(s(0, 0, 0, StrokePhase.down), viewportZoom: 1, viewportTransform: [1,0,0,1,0,0]);
  for (var i = 1; i <= 30; i++) {
    r.record(s(i.toDouble(), (i % 5) * 0.5, i * 16, StrokePhase.move),
        viewportZoom: 1, viewportTransform: [1,0,0,1,0,0]);
  }
  r.record(s(31, 0, 31 * 16, StrokePhase.up), viewportZoom: 1, viewportTransform: [1,0,0,1,0,0]);
  return r.finish();
}

void main() {
  test('replay is deterministic: same recording + same modeler params => same geometry', () {
    final rec = sampleRecording();
    final runner = const StrokeReplayRunner();
    final a = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    final b = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    expect(b.emittedPoints, a.emittedPoints);
    expect(b.emittedPressures, a.emittedPressures);
  });

  test('replay emits at least down + up', () {
    final rec = sampleRecording();
    final runner = const StrokeReplayRunner();
    final r = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    expect(r.emittedPoints.length, greaterThanOrEqualTo(2));
    expect(r.emittedPoints.first, const Point(0, 0));
    // up flush: 终点接近真实抬笔点
    expect(r.emittedPoints.last.x, closeTo(31, 1.0));
  });

  test('different policy => different geometry', () {
    final rec = sampleRecording();
    final runner = const StrokeReplayRunner();
    final a = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    final b = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.mouse));
    // mouse 几乎不滤波，几何应与 stylus 有差异
    expect(a.emittedPoints, isNot(equals(b.emittedPoints)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL.

- [ ] **Step 3: Write implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart
import '../core/math/point.dart';
import 'stroke_input_sample.dart';
import 'stroke_input_modeler.dart';
import 'stroke_recorder.dart';
import 'stroke_render_metrics.dart';

class ReplayResult {
  const ReplayResult({
    required this.emittedPoints,
    required this.emittedPressures,
    required this.perPointMetrics,
  });
  final List<Point> emittedPoints;
  final List<double?> emittedPressures;
  final List<StrokeRenderMetrics> perPointMetrics;
}

/// 用同一录制样本重复运行不同 modeler 参数，输出几何与指标。
/// 自检门槛：相同 recording + 相同参数 → 确定性几何（见测试）。
class StrokeReplayRunner {
  const StrokeReplayRunner();

  ReplayResult run(
    StrokeRecording recording, {
    required StrokeInputModeler modeler,
    StrokeRenderMetricsSink? metricsSink,
  }) {
    final points = <Point>[];
    final pressures = <double?>[];
    final metrics = <StrokeRenderMetrics>[];
    modeler.reset(reason: 'replay start');
    for (final sample in recording.samples) {
      final r = modeler.process(sample);
      if (r.decision == StrokeModelDecision.emitted && r.point != null) {
        points.add(r.point!);
        pressures.add(r.pressure);
      }
    }
    return ReplayResult(
      emittedPoints: List.unmodifiable(points),
      emittedPressures: List.unmodifiable(pressures),
      perPointMetrics: List.unmodifiable(metrics),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/stroke_replay_runner_test.dart`
Expected: PASS (3 tests) — **这是阶段 0 的自检门槛**：确定性通过才能进入阶段 1。

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart \
        test/features/whiteboard/editor_core/input/stroke_replay_runner_test.dart
git commit -m "feat(stroke): add StrokeReplayRunner with determinism gate"
```

---

## 阶段 1：轮廓曲线路径 A/B（S3）

> 目标：用 `OutlineRenderMode` 在 renderer 内同时支持 polygon（基线）与 quadratic（官方二次中点法），通过运行时枚举切换做 A/B。不动输入路由。

### Task 1.1: OutlinePathBuilder（二次中点法 + polygon 基线）

**Files:**
- Modify: `lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`（新增 `buildOutlinePath` 纯函数，保留现有 `addPolygon` 行为可通过模式切换）
- Test: `test/features/whiteboard/editor_core/rendering/outline_path_builder_test.dart`

**Interfaces:**
- Consumes: `OutlineRenderMode`（Task 0.4）、`perfect_freehand` 的 `PointVector`
- Produces: `Path FreedrawRenderer.buildOutlinePath(List<PointVector> outline, OutlineRenderMode mode)`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/rendering/outline_path_builder_test.dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide Point;
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart';

List<PointVector> poly(int n) => [for (var i = 0; i < n; i++) PointVector(i.toDouble(), (i % 2).toDouble(), 0.5)];

void main() {
  group('FreedrawRenderer.buildOutlinePath', () {
    test('polygon mode closes the path', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(20), OutlineRenderMode.polygon);
      final bounds = path.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(-1)); // 非空
    });

    test('quadratic mode closes the path and is finite', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(20), OutlineRenderMode.quadratic);
      final bounds = path.getBounds();
      expect(bounds.width.isFinite, isTrue);
      expect(bounds.height.isFinite, isTrue);
      expect(bounds.width, greaterThan(0));
    });

    test('quadratic with < 3 points falls back gracefully (no throw)', () {
      expect(() => FreedrawRenderer.buildOutlinePath(poly(2), OutlineRenderMode.quadratic), returnsNormally);
      expect(() => FreedrawRenderer.buildOutlinePath(poly(1), OutlineRenderMode.quadratic), returnsNormally);
      expect(() => FreedrawRenderer.buildOutlinePath(poly(0), OutlineRenderMode.quadratic), returnsNormally);
    });

    test('no NaN/Infinity in quadratic path bounds', () {
      final path = FreedrawRenderer.buildOutlinePath(poly(50), OutlineRenderMode.quadratic);
      final b = path.getBounds();
      expect(b.left.isNaN, isFalse);
      expect(b.top.isNaN, isFalse);
      expect(b.right.isFinite, isTrue);
      expect(b.bottom.isFinite, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL — `buildOutlinePath` undefined.

- [ ] **Step 3: Add buildOutlinePath to FreedrawRenderer**

> **现有基础设施**：新代码已将 `getStroke` 逻辑提取为独立纯函数 `buildOutline()`（`:43-72`），`draw()` 委托其获取 outline 后仍用 `addPolygon`（`:107`）渲染。本 Task 在此基础上新增 `buildOutlinePath()` 纯函数，由 `draw()` 调用替换 `:107` 的 `addPolygon`。

在 `freedraw_renderer.dart` 中（`class FreedrawRenderer` 内，`_buildBezierPath` 附近）新增静态方法。注意需 import `outline_render_mode.dart`。

```dart
/// 由 perfect_freehand 的 outline 点构造闭合 Path。
/// - polygon：现有直线段（对照基线）。
/// - quadratic：官方二次中点法，以 outline 点为控制点、相邻点中点为终点。
/// 显式处理最后一点到第一点的接缝。
static Path buildOutlinePath(List<PointVector> outline, OutlineRenderMode mode) {
  if (outline.isEmpty) return Path();
  if (mode == OutlineRenderMode.polygon || outline.length < 3) {
    return Path()..addPolygon(
      [for (final p in outline) Offset(p.x, p.y)],
      true,
    );
  }
  // quadratic: 官方中点法。每个顶点（包括第 0 个）恰好作为一次控制点，
  // 最后一个顶点连接到 first 的中点，避免闭合接缝遗漏第 0 个控制段。
  final path = Path();
  final first = outline.first;
  path.moveTo(first.x, first.y);
  for (var i = 0; i < outline.length; i++) {
    final cur = outline[i];
    final next = outline[(i + 1) % outline.length];
    final midX = (cur.x + next.x) / 2;
    final midY = (cur.y + next.y) / 2;
    path.quadraticBezierTo(cur.x, cur.y, midX, midY);
  }
  path.close();
  return path;
}
```

> 上述路径从首点到首尾中点后闭合；它不是从首两个点的中点起笔并跳过 `outline[0]`。除 `Path.getBounds()` 外，Task 1.1 还须增加 raster golden 或真机 A/B，专门覆盖闭合缝、端帽和尖角，避免“有限且不抛异常”的测试掩盖几何缺陷。

文件顶部 import：
```dart
import '../../input/outline_render_mode.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/rendering/outline_path_builder_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart \
        test/features/whiteboard/editor_core/rendering/outline_path_builder_test.dart
git commit -m "feat(stroke): add quadratic midpoint OutlinePathBuilder with A/B mode"
```

---

### Task 1.2: 接入 OutlineRenderMode 到 adapter + controller

**Files:**
- Modify: `lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart`（`:714` 附近加 `outlineRenderMode` 字段，`drawFreedraw` `:717-733` 透传）
- Modify: `lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`（`draw` 签名增 `OutlineRenderMode`）
- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（`:235-240` 附近加 `outlineRenderMode` getter/setter，同步到 `_adapter`）
- Test: `test/features/whiteboard/editor_core/rendering/freedraw_render_mode_test.dart`

**Interfaces:**
- Produces: `FreedrawRenderer.draw(..., {required OutlineRenderMode outlineRenderMode})`、`RoughCanvasAdapter.outlineRenderMode` 字段、`MarkdrawController.outlineRenderMode` getter/setter

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/rendering/freedraw_render_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/outline_render_mode.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';

void main() {
  test('RoughCanvasAdapter exposes mutable outlineRenderMode defaulting to quadratic', () {
    final a = RoughCanvasAdapter();
    expect(a.outlineRenderMode, OutlineRenderMode.quadratic);
    a.outlineRenderMode = OutlineRenderMode.polygon;
    expect(a.outlineRenderMode, OutlineRenderMode.polygon);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL — no `outlineRenderMode` field.

- [ ] **Step 3: Wire outlineRenderMode through**

(a) `freedraw_renderer.dart` — 改 `draw` 签名与 outline 路径构造（替换 `:107` 的 `addPolygon`）：

```dart
static void draw(
  Canvas canvas,
  List<Point> points,
  DrawStyle style, {
  List<double>? pressures,
  double pressureSensitivity = 0.7,
  required OutlineRenderMode outlineRenderMode,
  StrokeRenderMetricsSink? metricsSink,
}) {
  // ... (getStroke 调用不变) ...
  // 单点处理不变
  // outline 路径改用 buildOutlinePath：
  final sw = metricsSink == null ? null : Stopwatch()..start();
  final path = buildOutlinePath(outline, outlineRenderMode);
  final pathBuildDuration = sw == null ? Duration.zero : (sw..stop()).elapsed;
  final paint = style.toStrokePaint()..style = PaintingStyle.fill;
  canvas.drawPath(path, paint);
  metricsSink?.onMetrics(StrokeRenderMetrics(
    outlinePointCount: outline.length,
    getStrokeDuration: const Duration.zero, // 由调用方在外层包 Stopwatch 填充，或在此前记录
    pathBuildDuration: pathBuildDuration,
  ));
}
```
（顶部 import 增加 `stroke_render_metrics.dart`。）

(b) `rough_canvas_adapter.dart` — 在 `:714` 的 `pressureSensitivity` 字段旁新增：
```dart
import '../../input/outline_render_mode.dart';
...
OutlineRenderMode outlineRenderMode = OutlineRenderMode.quadratic; // 默认平滑
```
改 `drawFreedraw`（`:717-733`）在调用 `FreedrawRenderer.draw` 时传入 `outlineRenderMode: outlineRenderMode`。

(c) `markdraw_controller.dart` — 在 `:235-240` 的 `pressureSensitivity` setter 旁新增：
```dart
OutlineRenderMode get outlineRenderMode => _adapter.outlineRenderMode;
set outlineRenderMode(OutlineRenderMode mode) {
  _adapter.outlineRenderMode = mode;
  notifyListeners();
}
```
（import `outline_render_mode.dart`。）

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/rendering/freedraw_render_mode_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full freedraw-related test suite to catch regressions**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/`
Expected: 既有测试全 PASS（含 `harmony_stylus_stroke_smoother_test.dart`）。若 `draw` 签名变更导致其他调用点编译失败，按相同方式补传 `outlineRenderMode`。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(stroke): wire OutlineRenderMode through adapter and controller"
```

---

## 阶段 2：终点 flush 与 wet/dry 完成态（S3+S4）

> 目标：renderer 支持 `isComplete` 参数；预览元素带 pressure + isComplete=false；up 时终点准确到位。

### Task 2.1: FreedrawRenderer.draw 支持 isComplete 参数

**Files:**
- Modify: `lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`（`StrokeOptions` 的 `isComplete` 不再硬编码 true）
- Modify: `lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart`（`drawFreedraw` 透传）
- Modify: `lib/features/whiteboard/editor_core/src/rendering/element_renderer.dart`（`:159` 传 element 的完成态）
- Modify: `lib/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart`（新增运行时 `isComplete`，默认 true，**不进 JSON**）
- Test: `test/features/whiteboard/editor_core/rendering/freedraw_iscomplete_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/rendering/freedraw_iscomplete_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart';

void main() {
  test('FreedrawElement has runtime isComplete defaulting to true', () {
    final e = FreedrawElement(
      id: 'x', type: 'freedraw', x: 0, y: 0,
      points: const [/* Point... */], pressures: const [], simulatePressure: true,
    );
    expect(e.isComplete, isTrue);
  });

  test('isComplete is NOT serialized to JSON (stays a render-only field)', () {
    // 通过 copyWithFreedraw 构造 isComplete=false 的预览元素，
    // 确认 toJson 不含 isComplete 键。
    // （具体断言依赖序列化测试；此处只验证字段存在且可变）
    final e = FreedrawElement(
      id: 'x', type: 'freedraw', x: 0, y: 0,
      points: const [], pressures: const [], simulatePressure: true,
    );
    expect(e.isComplete, isTrue);
    final preview = e.copyWithFreedraw(points: const [], isComplete: false);
    expect(preview.isComplete, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL — no `isComplete` field / `copyWithFreedraw` 无此参数。

- [ ] **Step 3: Add isComplete to FreedrawElement (runtime only)**

`freedraw_element.dart`：在 `simulatePressure` 字段后新增 `final bool isComplete;`（默认 true）。构造函数与 `copyWithFreedraw` 增加 `bool isComplete = true` 参数。**不动 toJson/fromJson**（序列化测试 Task 2.3 会回归确认）。

```dart
// 字段
final bool isComplete;
// 构造函数加 this.isComplete = true
// copyWithFreedraw 签名加 {bool? isComplete}，体内 isComplete: isComplete ?? this.isComplete
```

- [ ] **Step 4: Thread isComplete through renderer**

> **注意**：新代码中 `StrokeOptions(..., isComplete: true)` 已提取到 `buildOutline()` 内部（`:68`）。需同时修改 `buildOutline()` 和 `draw()` 两个方法的签名，添加 `bool isComplete = true` 参数，并在 `buildOutline()` 中将 `isComplete` 透传给 `StrokeOptions`。

`freedraw_renderer.dart` 的 `buildOutline()` 和 `draw` 签名均增加 `bool isComplete = true`。
`rough_canvas_adapter.dart` 的 `drawFreedraw` 签名增加 `bool isComplete = true`，透传。
`element_renderer.dart:159` 调用改为传 `element.isComplete`。

- [ ] **Step 5: Run test to verify it passes**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/rendering/freedraw_iscomplete_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(stroke): add runtime isComplete to FreedrawElement and renderer"
```

---

### Task 2.2: ToolOverlay 带 pressures + 预览用相同 points/pressures

**Files:**
- Modify: `lib/features/whiteboard/editor_core/src/editor/tool_result.dart`（`ToolOverlay` `:101-137` 增加 `List<double>? creationPressures` 与 `bool creationIsComplete`）
- Modify: `lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart`（`overlay` getter `:102` 带 pressures + isComplete=false）
- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（`buildPreviewElement` `:1988-2070` 用 overlay 的 pressures 与 isComplete=false）
- Test: `test/features/whiteboard/editor_core/editor/freedraw_overlay_pressure_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/editor/freedraw_overlay_pressure_test.dart
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

// 用 controller 驱动（ToolContext 需要 scene/viewport，直接造 tool 太重；参考既有测试模式）。
// 注意：此测试在阶段 2 编写时，controller 签名仍是旧的 Offset+kind+pressure 形式；
// 阶段 3 改造为方案 A（收 PointerEvent）后，需把 onPointerDown/Move 调用改为构造
// PointerDownEvent/PointerMoveEvent（见 stroke_modeler_integration_test.dart 的构造方式）。
// 阶段 2 提交时用下方"旧签名"形式；阶段 3 Step 6 全量回归时同步迁移。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview overlay carries pressures and isComplete=false during a stroke', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);

    // 阶段 2（旧签名）：
    controller.onPointerDown(const Offset(0, 0), kind: PointerDeviceKind.stylus, pressure: 0.5);
    controller.onPointerMove(const Offset(10, 0), const Offset(10, 0), kind: PointerDeviceKind.stylus, pressure: 0.6);
    // 阶段 3 迁移后改为：
    // controller.onPointerDown(PointerDownEvent(pointer:1, position: Offset(0,0), localPosition: Offset(0,0), kind: PointerDeviceKind.stylus, pressure: 0.5, timeStamp: Duration.zero));
    // controller.onPointerMove(PointerMoveEvent(pointer:1, position: Offset(10,0), localPosition: Offset(10,0), delta: Offset(10,0), kind: PointerDeviceKind.stylus, pressure: 0.6, timeStamp: const Duration(milliseconds:16)));

    // 进行中：controller 暴露的预览 overlay 应带 pressure 且 isComplete=false。
    // （预览 overlay 的访问入口以 controller 公开 API 为准；实施时核对。）
    final overlay = controller.currentCreationOverlay; // 见实施注记
    expect(overlay, isNotNull);
    expect(overlay!.creationPressures, isNotNull);
    expect(overlay.creationPressures!.length, greaterThanOrEqualTo(2));
    expect(overlay.creationIsComplete, isFalse);
  });
}
```
> 实施注记：`controller.currentCreationOverlay` 的真实访问入口以 `markdraw_controller.dart` 为准（预览 overlay 由 `buildPreviewElement`/`overlay` 产生）。若 controller 未公开 overlay getter，本测试改为 `pumpWidget` 渲染 EditorCanvas 后断言 widget 层的预览元素；或先在 controller 暴露一个 `@visibleForTesting` 的 overlay getter。**阶段 2→3 签名迁移**：本测试在阶段 3 Step 6 全量回归时，把旧签名调用改为 `PointerDownEvent/MoveEvent` 构造形式（见 stroke_modeler_integration_test.dart）。

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL — `creationPressures`/`creationIsComplete` 不存在。

- [ ] **Step 3: Add pressures + isComplete to ToolOverlay**

`tool_result.dart` `ToolOverlay`：
```dart
final List<double>? creationPressures;
final bool creationIsComplete; // 默认 false（预览=湿墨）
// 构造函数默认值：creationIsComplete: false
```

`freedraw_tool.dart` `overlay` getter：
```dart
@override
ToolOverlay? get overlay => _points.isEmpty ? null : ToolOverlay(
  creationPoints: List.unmodifiable(_points),
  creationPressures: _hasRealPressure ? List.unmodifiable(_pressures) : const [],
  creationIsComplete: false,
);
```

`markdraw_controller.dart` `buildPreviewElement`：用 `overlay.creationPressures` 与 `isComplete:false` 构造 `FreedrawElement.copyWithFreedraw(..., isComplete: false)`。

- [ ] **Step 4: Run test to verify it passes** → Expected PASS.

- [ ] **Step 5: Run editor regression suite**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(stroke): carry pressures and isComplete in preview overlay"
```

---

### Task 2.3: isComplete 不入 JSON 回归测试 + 修复 copyWith latent bug

**Files:**
- Test: `test/features/whiteboard/editor_core/persistence/freedraw_json_iscomplete_test.dart`
- Modify: `lib/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart`（修复探索发现的 `copyWith` `:126-128` latent bug：points/pressures/simulatePressure 缺 `?? this.x` 兜底）

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/persistence/freedraw_json_iscomplete_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/persistence/excalidraw_json_codec.dart';

void main() {
  test('isComplete is NOT serialized', () {
    final e = FreedrawElement(
      id: 'a', type: 'freedraw', x: 0, y: 0,
      points: const [Point(0,0), Point(1,1)], pressures: const [0.5, 0.6],
      simulatePressure: false,
    );
    final json = ExcalidrawJsonCodec.elementToJson(e);
    expect(json.containsKey('isComplete'), isFalse);
  });

  test('JSON round-trip preserves points/pressures, isComplete stays default true', () {
    final e = FreedrawElement(
      id: 'a', type: 'freedraw', x: 1, y: 2,
      points: const [Point(0,0), Point(3,4)], pressures: const [0.4, 0.5],
      simulatePressure: false,
    );
    final json = ExcalidrawJsonCodec.elementToJson(e);
    // parseElement 返回 Element?；类型断言为 FreedrawElement
    final back = ExcalidrawJsonCodec.parseElement(json) as FreedrawElement;
    expect(back.points, e.points);
    expect(back.pressures, e.pressures);
    expect(back.isComplete, isTrue);
  });

  test('copyWith preserves fields not overridden (latent bug fix)', () {
    final e = FreedrawElement(
      id: 'a', type: 'freedraw', x: 0, y: 0,
      points: const [Point(0,0)], pressures: const [0.5], simulatePressure: false,
    );
    final moved = e.copyWith(x: 10); // 只改 x
    expect(moved.points, e.points);
    expect(moved.pressures, e.pressures);
    expect(moved.simulatePressure, e.simulatePressure);
  });
}
```
> 注：序列化用 `ExcalidrawJsonCodec.elementToJson(Element)`（`:92`）与 `ExcalidrawJsonCodec.parseElement(json)`（`:362`，返回 `Element?`）。

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL（copyWith bug 导致 points 丢失）。

- [ ] **Step 3: Fix copyWith latent bug**

`freedraw_element.dart` `copyWith` `:126-128`：
```dart
points: points ?? this.points,
pressures: pressures ?? this.pressures,
simulatePressure: simulatePressure ?? this.simulatePressure,
isComplete: isComplete ?? this.isComplete,
```

- [ ] **Step 4: Run test to verify it passes** → Expected PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(freedraw): preserve fields in copyWith; keep isComplete out of JSON"
```

---

## 阶段 3：统一输入建模层接入 + 移除旧 smoother（S1+S2）

> 目标：在 EditorCanvas 的 Listener 边界插入 `StrokeInputNormalizer`，freedraw 工具经过 `StrokeInputModeler`；移除 `HarmonyStylusStrokeSmoother` 路由防双重平滑；处理 up 终点 flush。注意：旧"up 补发 move"quirk 已在新代码中移除，无需额外处理。

### Task 3.1: StrokeInputNormalizer

**Files:**
- Create: `lib/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart`
- Test: `test/features/whiteboard/editor_core/input/stroke_input_normalizer_test.dart`

**Interfaces:**
- Consumes: Flutter `PointerEvent`、`StrokeInputSample`（Task 0.1）
- Produces: `class StrokeInputNormalizer { StrokeInputSample? normalize(PointerEvent e, {required StrokePhase phase}); }`（mouse pressure 与无可靠范围的 touch pressure 输出 null）

- [ ] **Step 1: Write the failing test**

```dart
// test/features/whiteboard/editor_core/input/stroke_input_normalizer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart';

PointerEvent mkEvent({
  required Offset localPosition,
  required PointerDeviceKind kind,
  double pressure = 0.0,
  int pointer = 1,
  Duration timeStamp = const Duration(milliseconds: 16),
}) => PointerMoveEvent(
  pointer: pointer, position: localPosition, localPosition: localPosition,
  kind: kind, pressure: pressure, timeStamp: timeStamp, delta: Offset.zero,
);

void main() {
  test('stylus with pressure > 0 yields real pressure', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(10,20), kind: PointerDeviceKind.stylus, pressure: 0.5), phase: StrokePhase.move);
    expect(s, isNotNull);
    expect(s!.pressure, 0.5);
    expect(s.kind, StrokeInputKind.stylus);
  });

  test('mouse pressure is dropped to null', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(1,2), kind: PointerDeviceKind.mouse, pressure: 0.5), phase: StrokePhase.move);
    expect(s!.pressure, isNull);
    expect(s.kind, StrokeInputKind.mouse);
  });

  test('maps device kind to StrokeInputKind', () {
    final n = StrokeInputNormalizer();
    expect(n.normalize(mkEvent(localPosition: Offset.zero, kind: PointerDeviceKind.touch), phase: StrokePhase.down)!.kind, StrokeInputKind.touch);
    expect(n.normalize(mkEvent(localPosition: Offset.zero, kind: PointerDeviceKind.stylus), phase: StrokePhase.down)!.kind, StrokeInputKind.stylus);
  });

  test('passes pointer id, timestamp, local coords', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(5,6), kind: PointerDeviceKind.stylus, pointer: 7, timeStamp: const Duration(milliseconds: 99)), phase: StrokePhase.down)!;
    expect(s.pointerId, 7);
    expect(s.x, 5); expect(s.y, 6);
    expect(s.time, const Duration(milliseconds: 99));
  });
}
```

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL.

- [ ] **Step 3: Write implementation**

```dart
// lib/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart
import 'package:flutter/gestures.dart';
import 'stroke_input_sample.dart';

/// 位于 EditorCanvas 的 Listener 边界：PointerEvent → StrokeInputSample。
/// 在 local logical-pixel 坐标完成（screenToScene 由 controller 在 modeler 之后做）。
class StrokeInputNormalizer {
  StrokeInputSample? normalize(PointerEvent e, {required StrokePhase phase}) {
    return StrokeInputSample(
      pointerId: e.pointer,
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      time: e.timeStamp,
      pressure: _reliablePressure(e),
      kind: _mapKind(e.kind),
      phase: phase,
      source: StrokeSampleSource.actual,
    );
  }

  /// 仅设备确实提供可靠压感时返回非 null。
  /// mouse pressure 与无可靠范围的 touch pressure 一律视为 null。
  /// 使用 pressureMin/Max 归一化，吸收现有 `reliableStylusPressure()` 的算法。
  double? _reliablePressure(PointerEvent e) {
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        final range = e.pressureMax - e.pressureMin;
        if (range <= 0) {
          return e.pressure.clamp(0.0, 1.0);
        }
        return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.touch:
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
      default:
        return null;
    }
  }

  StrokeInputKind _mapKind(PointerDeviceKind k) {
    switch (k) {
      case PointerDeviceKind.stylus: return StrokeInputKind.stylus;
      case PointerDeviceKind.invertedStylus: return StrokeInputKind.invertedStylus;
      case PointerDeviceKind.touch: return StrokeInputKind.touch;
      case PointerDeviceKind.mouse: return StrokeInputKind.mouse;
      default: return StrokeInputKind.unknown;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes** → Expected PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart \
        test/features/whiteboard/editor_core/input/stroke_input_normalizer_test.dart
git commit -m "feat(stroke): add StrokeInputNormalizer (PointerEvent -> sample)"
```

---

### Task 3.2: 接入 modeler 到 controller + 移除旧 smoother 路由

**Files:**
- Modify: `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（`onPointerDown/Move/Up` `:1491/1577/1610`：freedraw 经 modeler；移除 `_harmonyStylusStrokeSmoother` 调用 `:1504/1584/1616`；处理 up 终点 flush；feature flag 回退）
- Modify: `lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`（`:123` Listener：插入 normalizer + cancel + pointer 所有权）
- Modify: `lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart`（新增不取整的 screen→scene 变换，仅供 freedraw 使用）
- Test: `test/features/whiteboard/editor_core/editor/stroke_modeler_integration_test.dart`

> 这是本计划最复杂的改动。分小步验证。

**API 方案选择（评审必须修复项 #2）**：采用**方案 A——controller 的 `onPointerDown/Move/Up` 签名改为接收 `PointerEvent`**。理由：`EditorCanvas` 的 `Listener`（`editor_canvas.dart:123-172`）已持有完整 `PointerEvent`（含 `timeStamp`/`pointer`/`localPosition`/`kind`/`pressure`），只需透传给 controller；controller 内部调 normalizer→modeler→tool。这样 normalizer 能拿到完整事件（含时间戳和 pointer id），且对 EditorCanvas 调用点改动最小（只是把 `event.localPosition + event.pressure + event.kind` 换成 `event`）。**不采用**方案 B（EditorCanvas 内做 normalizer 再传 sample），因为它会让 controller 签名变成非 Flutter 标准类型 `StrokeInputSample`，且 EditorCanvas 也要维护 modeler 状态。

**Interfaces:**
- Consumes: `StrokeInputNormalizer`（Task 3.1）、`StrokeInputModeler`（Task 0.3）、`InputPolicySelector`（Task 0.3）
- Produces:
  - `MarkdrawController.onPointerDown(PointerEvent event)` / `onPointerMove(PointerEvent event)` / `onPointerUp(PointerEvent event)` / `onPointerCancel(PointerEvent event)`（签名变更；旧 `Offset+pressure+kind` 形式移除）
  - controller 内部：freedraw 路径由 modeler 驱动；`HarmonyStylusStrokeSmoother` 路由移除（类保留为 modeler 内部 debug 对照，见 spec §3.2）

- [ ] **Step 1: Write the failing integration test**

```dart
// test/features/whiteboard/editor_core/editor/stroke_modeler_integration_test.dart
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

// 方案 A：controller 收 PointerEvent。测试构造 PointerDownEvent/MoveEvent/UpEvent。
// 用真实 controller 驱动（参考 element_creation_bounds_test.dart:50-72 的模式），
// 验证：freedraw 经 modeler、不再双重平滑、up 终点 flush 到位、cancel 不提交。
Offset _local(double x, double y) => Offset(x, y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('freedraw stroke via controller commits real up endpoint', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);
    // 默认 viewport offset(0,0) zoom 1 → screen == scene。

    controller.onPointerDown(PointerDownEvent(
      pointer: 1, position: _local(0, 0), localPosition: _local(0, 0),
      kind: PointerDeviceKind.stylus, pressure: 0.5, timeStamp: Duration.zero,
    ));
    for (var i = 1; i <= 20; i++) {
      controller.onPointerMove(PointerMoveEvent(
        pointer: 1, position: _local(i.toDouble(), (i % 3).toDouble()),
        localPosition: _local(i.toDouble(), (i % 3).toDouble()),
        delta: const Offset(1, 0),
        kind: PointerDeviceKind.stylus, pressure: 0.5,
        timeStamp: Duration(milliseconds: i * 16),
      ));
    }
    controller.onPointerUp(PointerUpEvent(
      pointer: 1, position: _local(21, 0), localPosition: _local(21, 0),
      kind: PointerDeviceKind.stylus, pressure: 0.5,
      timeStamp: const Duration(milliseconds: 21 * 16),
    ));

    final elements = controller.editorState.scene.elements;
    expect(elements.length, 1);
    // 提交元素的终点接近真实抬笔点（flush，未被低通截短）
    final points = (elements.first as dynamic).points as List;
    expect((points.last as dynamic).x, closeTo(21, 1.0));
  });

  test('cancel does not commit an element', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);
    controller.onPointerDown(PointerDownEvent(
      pointer: 1, position: _local(0, 0), localPosition: _local(0, 0),
      kind: PointerDeviceKind.stylus, timeStamp: Duration.zero,
    ));
    controller.onPointerMove(PointerMoveEvent(
      pointer: 1, position: _local(10, 0), localPosition: _local(10, 0),
      delta: const Offset(10, 0), kind: PointerDeviceKind.stylus,
      timeStamp: const Duration(milliseconds: 16),
    ));
    controller.onPointerCancel(PointerCancelEvent(
      pointer: 1, position: _local(10, 0), localPosition: _local(10, 0),
      kind: PointerDeviceKind.stylus, timeStamp: const Duration(milliseconds: 32),
    ));
    expect(controller.editorState.scene.elements, isEmpty);
  });

  test('non-freedraw tool (select) bypasses modeler (no filtering)', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.select);
    // select 工具不经 modeler：直接用原始坐标，不滤波。
    controller.onPointerDown(PointerDownEvent(
      pointer: 1, position: _local(50, 50), localPosition: _local(50, 50),
      kind: PointerDeviceKind.mouse, timeStamp: Duration.zero,
    ));
    // 不崩溃、无异常即通过（select 不创建元素，无几何断言）。
    expect(() => controller.onPointerUp(PointerUpEvent(
      pointer: 1, position: _local(50, 50), localPosition: _local(50, 50),
      kind: PointerDeviceKind.mouse, timeStamp: const Duration(milliseconds: 16),
    )), returnsNormally);
  });

  test('freedraw preserves subpixel scene coordinates', () {
    final controller = MarkdrawController();
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);
    controller.setViewport(const ViewportState(
      offset: Offset(0.25, 0.5), zoom: 1.5,
    ));
    controller.onPointerDown(PointerDownEvent(
      pointer: 1, position: _local(1, 1), localPosition: _local(1, 1),
      kind: PointerDeviceKind.stylus, pressure: 0.5, timeStamp: Duration.zero,
    ));
    controller.onPointerUp(PointerUpEvent(
      pointer: 1, position: _local(10, 10), localPosition: _local(10, 10),
      kind: PointerDeviceKind.stylus, pressure: 0.5,
      timeStamp: const Duration(milliseconds: 16),
    ));
    final points = (controller.editorState.scene.elements.single as dynamic).points as List;
    // (10 / 1.5 + 0.25, 10 / 1.5 + 0.5)，而不是 (7, 7)。
    expect((points.last as dynamic).x, closeTo(6.9166666667, 1e-6));
    expect((points.last as dynamic).y, closeTo(7.1666666667, 1e-6));
  });
}
```
> 实施注记：本测试驱动真实 `MarkdrawController`（既有测试模式，见 `element_creation_bounds_test.dart:50-72`）。`editorState.scene.elements` 为 controller 公开 API（见 `element_creation_bounds_test.dart:71`）。`PointerDownEvent/MoveEvent/UpEvent/CancelEvent` 为 Flutter 标准类型，构造方式见上。

- [ ] **Step 2: Run test to verify it fails** → Expected FAIL（`_dummyContext` 未实现 / 双重平滑导致终点偏移）。

- [ ] **Step 3: Wire modeler into controller (方案 A：controller 收 PointerEvent)**

在 `markdraw_controller.dart`：
1. **改签名**：`onPointerDown/Move/Up` 从 `(Offset localPosition, {pressure, kind})` 改为 `(PointerEvent event)`。新增 `onPointerCancel(PointerEvent event)`。
2. 新增字段：`final _normalizer = StrokeInputNormalizer();`、`StrokeInputModeler? _modeler;`、`final _policySelector = const InputPolicySelector();`、`int? _activeDrawPointerId;`、`bool _useUnifiedModeler = true;`（feature flag）。
3. 改 `onPointerDown`（`:1491`）：
   - 从 `event.localPosition`/`event.kind` 提取；touch+创作工具的旧抑制逻辑（`:1132`）保留，用 `event.kind`。
   - 若 `_useUnifiedModeler && _activeTool is FreedrawTool`：
     - `final sample = _normalizer.normalize(event, phase: StrokePhase.down)`；
     - `_activeDrawPointerId = sample.pointerId`（获取绘制所有权）；
     - `_modeler = StrokeInputModeler(_policySelector.select(sample.kind))`；
     - `final r = _modeler!.process(sample)`；若 `r.point != null`，用新增的**不取整** `screenToScenePrecise(localPosition)` 转为浮点 scene 坐标后调 `_activeTool.onPointerDown(scenePoint, ctx, pressure: r.pressure)`。
   - 否则（非 freedraw 或 feature flag 关）：非 freedraw 走旧的整数对齐 `toScene`；freedraw 的 feature-flag 回退也必须走 `screenToScenePrecise`，以免 A/B 混入坐标量化差异。
4. 同理改 `onPointerMove`（`:1577`）：仅当 `event.pointer == _activeDrawPointerId` 才经 modeler；否则（非活动 pointer）忽略，防多指污染。
5. 改 `onPointerUp`（`:1610`）：
   - 经 modeler，`up()` 返回真实终点（flush）。
   - **仅当终点尚未进入 tool 点列**（距离判断）才补发一次 `onPointerMove` 给 tool，再调 `onPointerUp` 提交。
   - **旧"up 补发 move"quirk 已在新代码中移除**（原 `:1271-1281` 不存在），无需额外删除。
   - 清除 `_activeDrawPointerId`、`_modeler.reset()`。
6. `onPointerCancel`：调 `_modeler?.reset(reason:'cancel')` 与 `_activeTool.reset()`，丢弃未提交笔画，清除 `_activeDrawPointerId`。
7. **移除** `_harmonyStylusStrokeSmoother.down/move/up` 调用（`:1504/1584/1616`）。保留 `_harmonyStylusStrokeSmoother` 字段以备 debug 对照，但不再路由。
8. 更新所有 controller 内部读取 pressure 的地方：从 `event.pressure` 取（但 normalizer 已负责把 mouse/不可靠 touch pressure 归 null，modeler 内部 InputPolicy 决定是否用真实压感）。
9. 在 `viewport_state.dart` 新增 `screenToScenePrecise(Offset)`：公式与现有 `screenToScene` 相同，但**不调用** `roundToDouble()`；只在 freedraw 的点采集/提交路径使用。为其增加单测：非整数 zoom、offset 与 localPosition 下输出保留小数；并由本任务的 integration test 断言最终 `FreedrawElement.points` 保留小数坐标。

> **注意既有调用点**：controller 的 `onPointer*` 由 `EditorCanvas`（`editor_canvas.dart:122-165`）和测试调用。本步同步更新 EditorCanvas（见 Step 4）。其他既有测试（如 `element_creation_bounds_test.dart:56-66` 用旧 `Offset+kind` 形式）需同步改为构造 `PointerEvent`——在 Step 6 全量回归时一并修正。

- [ ] **Step 4: EditorCanvas 透传 PointerEvent（方案 A）**

> **现有基础设施**：新代码 `EditorCanvas` 的 Listener 回调已调用 `reliableStylusPressure()`（压感归一化）和 `shouldDispatchToCreationTool()`（touch 抑制），均来自 `pointer_pressure.dart`。接入 `StrokeInputNormalizer` 时需吸收/替换这两处调用，避免重复逻辑。

`editor_canvas.dart` `Listener`（`:114`）：
1. `onPointerDown`（`:122`）：`controller.onPointerDown(event)`（不再拆 `event.localPosition/pressure/kind`）。已有的 `reliableStylusPressure` 压感归一化逻辑由 normalizer 内部吸收。
2. `onPointerMove`（`:135`）：`controller.onPointerMove(event)`。
3. `onPointerUp`（`:149`）：`controller.onPointerUp(event)`。
4. **新增 `onPointerCancel`**：`controller.onPointerCancel(event)`。
5. `onPointerHover`（`:115`）与 `onPointerSignal`（`:166`）保持不变（hover/signal 不经 modeler）。
6. pointer 所有权与 cancel 清理由 controller 内部统一负责（Step 3），EditorCanvas 不再单独维护绘制 pointer 状态。

- [ ] **Step 5: Implement _dummyContext and run test to pass**

补全 `_dummyContext()`（参考既有测试），Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/editor/stroke_modeler_integration_test.dart`
Expected: PASS。

- [ ] **Step 6: Migrate existing tests to PointerEvent signature + run full regression**

方案 A 改了 controller 签名，既有测试需同步迁移。具体：
- `test/features/whiteboard/editor_core/element_creation_bounds_test.dart:56-66,81-90,105-...`：把 `controller.onPointerDown(const Offset(x,y), kind: ...)` 等改为构造 `PointerDownEvent/MoveEvent/UpEvent`（参考本任务 Step 1 的构造方式；用 `PointerDeviceKind.mouse`，pressure 可省略）。
- 其他直接调 `controller.onPointer*` 的测试（`grep -rln "onPointerDown\|onPointerMove\|onPointerUp" test/`）逐一迁移。

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/`
Expected: 全 PASS。特别确认：
- `harmony_stylus_stroke_smoother_test.dart` 仍 PASS（它测的是 smoother 单元，不调 controller，路由移除不影响）；
- `element_creation_bounds_test.dart` 迁移后仍验证创建边界守卫；
- `stroke_modeler_integration_test.dart` PASS（含 cancel 与 select 旁路用例）。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(stroke): integrate unified StrokeInputModeler; remove old smoother route"
```

---

### Task 3.3: 输入路由测试（所有权/cancel/旁路/pressure 误判）

**Files:**
- Test: `test/features/whiteboard/editor_core/editor/input_routing_test.dart`

- [ ] **Step 1: Write tests covering spec §5 输入路由项**

覆盖：active pointer 所有权、非活动 pointer 的 move/up 被忽略、cancel 清理、非 freedraw 工具旁路 modeler（不滤波）、mouse/touch 不误判真实 pressure。用 Task 3.2 暴露的 controller/EditorCanvas 入口构造事件序列断言。

- [ ] **Step 2: Run tests to verify they pass** → Expected PASS。

- [ ] **Step 3: Commit**

```bash
git add test/features/whiteboard/editor_core/editor/input_routing_test.dart
git commit -m "test(stroke): input routing ownership/cancel/bypass/pressure"
```

---

## 阶段 4：参数实验（stylus/touch/mouse 分别选参）

> 目标：用阶段 0 的录制样本离线回放做小规模参数网格，选最优参数。**无新代码任务**——是实验/调参阶段。本阶段产出参数表更新到 `InputPolicy` 默认值。

### Task 4.1: 参数网格回放实验

- [ ] **Step 1: 在真机录制验收样本集**（spec §6.3 的 8 类样本：极慢/快速直线、大/小圆、8 字、L/V/Z、汉字永/我/流、压力轻-重-轻、快速抬笔），用 `StrokeRecorder` 导出 JSON。

- [ ] **Step 2: 写离线回放脚本**

Create: `test/tools/stroke_param_sweep.dart`（dev-only，不进 CI）。遍历 `InputPolicy` 的 minCutoff∈{0.5,1.0,1.5,2.0}、beta∈{0.003,0.007,0.012} 组合，对每个录制样本用 `StrokeReplayRunner` 回放，输出 spec §6.1 的量化指标（直线正交 RMS、圆拟合残差、P95 偏差、转角偏差、最终点误差）。

- [ ] **Step 3: 分析结果，更新 InputPolicy 默认值**

根据盲测与指标，更新 `input_policy.dart` 中 `stylus/touch/mouse` 的 minCutoff/beta/minDistance/cornerProtectAngleRad。保留旧值作为注释对照。

- [ ] **Step 4: 确定性回归**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/input/`
Expected: 全 PASS（参数变化后确定性测试仍通过）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(stroke): tune InputPolicy defaults via offline param sweep"
```

---

## 阶段 5：协同与序列化一致性（S6）

> 目标：验证干墨 JSON 往返、接收端同算法渲染、预测点隔离。

### Task 5.1: 协同一致性回归测试

**Files:**
- Test: `test/features/whiteboard/editor_core/collaboration/freedraw_collab_consistency_test.dart`

- [ ] **Step 1: Write tests**

覆盖：
1. 干墨 `FreedrawElement` JSON 往返 points/pressures/simulatePressure 一致（含 isComplete 不出现）；
2. 接收端用相同 renderer 参数（outlineRenderMode + pressureSensitivity）重建，几何与发送端一致（容差内）；
3. 预测点（`source=predicted`）样本**不进入** FreedrawElement（构造一个含 predicted 样本的 stroke，确认提交后 element.points 不含预测点）。

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/collaboration/freedraw_collab_consistency_test.dart`
Expected: PASS。若测试暴露真实协议问题，按 spec §3.6 做最小修正（原则上不改协议）。

- [ ] **Step 3: Commit**

```bash
git add test/features/whiteboard/editor_core/collaboration/freedraw_collab_consistency_test.dart
git commit -m "test(stroke): collaboration consistency and prediction isolation"
```

---

## 阶段 6：HarmonyOS 原生报点预测可行性验证（独立 spike，可选）

> 准入门槛：阶段 0–5 验收通过后才能启动。目标：评估原生预测对跟手性的收益是否大于桥接延迟。**解决的是跟手性，不是锯齿**。

### 技术约束（来自 harmonyos-guides，必读）

- 关键文档：
  - `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发指导（C-C++）/pen-point-prediction-c.md`
  - `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-point-prediction.md`
  - `harmonyos-guides/应用框架/ArkUI（方舟UI框架）/UI开发 (基于NDK构建UI)/添加事件响应/ndk-bind-input-events.md`
  - `harmonyos-guides/应用框架/ArkUI（方舟UI框架）/UI开发 (ArkTS声明式开发范式)/添加组件/napi-xcomponent-guidelines.md`
- **版本门槛**：C API `HMS_HandWrite_GetPredictPoint` 需 HarmonyOS **6.0.0(20)+**；ArkTS `PointPredictor.getPredictionPoint(TouchEvent)` 更早可用。
- **C API**：header `handwrite/native_handwrite_api.h`，链接 `libhandwrite_ndk.z.so`，签名 `int32_t HMS_HandWrite_GetPredictPoint(const HandWrite_HistoricalPoint* event, int32_t size, float* predictX, float* predictY)`，struct `HandWrite_HistoricalPoint { x, y, timeStamp, force }`。
- **历史点获取**：必须经 XComponent 触摸回调 `OH_NativeXComponent_GetHistoricalPoints`（返回 `OH_NativeXComponent_HistoricalPoint`，同样含 x/y/timeStamp/force），逐字段拷入 `HandWrite_HistoricalPoint`。
- **不可调预测程度**（`pen-faq-7.md`）；**不支持模拟器，需真机+手写笔**；**仅中国大陆设备**（不含港澳台）。
- **触摸重采样**（`arkts-interaction-development-guide-touch-screen.md`）：系统按屏幕刷新率重采样，原始点经 `getHistoricalPoints()` 可取；预测点只在 `TouchType.Move` 调用。
- **替换 vs 增量**：文档模型是"用预测点立即绘制 + 真实点到达后修正"。对 FlowMuse：预测点作为 `StrokeSampleSource.predicted` 进湿墨层，真实点到达后替换预测尾。

### Task 6.1: Spike — 评估原生预测接入路径

- [ ] **Step 1: 写 spike 结论文档**

Create: `docs/superpowers/specs/2026-07-09-harmonyos-prediction-spike.md`，评估两条路径：
- **路径 A（ArkTS）**：Flutter 侧 PointerEvent 已丢失 native `TouchEvent` 结构；ArkTS `PointPredictor` 需要 ArkUI `TouchEvent`。需评估是否能在 Flutter OHOS Embedder 层拦截 native touch 事件喂给 PointPredictor，或经 Platform Channel 桥接。
- **路径 B（C/NDK + XComponent）**：原生侧用 XComponent 触摸回调取历史点 + `HMS_HandWrite_GetPredictPoint` 预测，经 EventChannel/FFI 推到 Dart。这是 `2024-se-17` spike 原型已验证过的路径（`plugin_manager.cpp` 已用 `OH_NativeXComponent_GetHistoricalPoints`）。
- 评估每条路径的桥接延迟、对象分配、线程切换成本；与现有 Flutter pointer pipeline 的采样率对比。

- [ ] **Step 2: 在真机（6.0.0(20)+，手写笔）跑最小 spike**

复用 `2024-se-17` 的 native 取点链路，增加 `HMS_HandWrite_GetPredictPoint` 调用，把预测点经 EventChannel 推到 Dart 一个 debug overlay 上绘制。测量：预测点相对真实点的提前时间、准确度、桥接延迟。

- [ ] **Step 3: 产出 go/no-go 结论**

在 spike 文档写明：预测收益是否 > 桥接延迟？是否增加抖动？
- **若 go**：预测点作为 `StrokeSampleSource.predicted` 经 normalizer 进入湿墨层（数据流已在阶段 3 预留），真实点到达时 controller 替换预测尾。新增阶段 6.2 实施任务。
- **若 no-go**：保持关闭，spike 文档归档。阶段 6 不阻塞核心交付。

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-09-harmonyos-prediction-spike.md
git commit -m "docs(spike): HarmonyOS point prediction feasibility assessment"
```

---

## 阶段验收门槛（汇总）

| 阶段 | 门槛 | 验证方式 |
| --- | --- | --- |
| 0 | recorder/replay 确定性 | `stroke_replay_runner_test.dart` PASS |
| 1 | quadratic 无自交/缺口/端帽异常，边缘锯齿低于 polygon | `outline_path_builder_test.dart` + 真机 A/B |
| 2 | up 终点到位、预览带 pressure、isComplete 不入 JSON | `freedraw_iscomplete_test`、`freedraw_overlay_pressure_test`、`freedraw_json_iscomplete_test` |
| 3 | 无双重平滑、终点 flush、cancel/所有权正确、非 freedraw 工具旁路 | `stroke_modeler_integration_test`、`input_routing_test` |
| 4 | 参数网格选定，确定性回归通过 | param_sweep 输出 + input 测试 PASS |
| 5 | 干墨 JSON 往返一致、预测点隔离、接收端同算法渲染一致 | `freedraw_collab_consistency_test` |
| 6 | go/no-go 结论 | spike 文档 |

最终人工验收（spec §6.2）：慢速边缘锯齿明显减少、转角保真、无额外拖尾、抬笔到位、压感连续、手指/鼠标交互语义不变、各端改善、协同收发一致。
