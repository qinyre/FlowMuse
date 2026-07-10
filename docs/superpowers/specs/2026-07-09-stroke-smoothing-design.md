# 笔迹平滑书写管线设计

> 日期：2026-07-09
> 状态：设计（待评审）
> 适用项目：FlowMuse-App（`2024-se-17-markdraw-probe/FlowMuse-App/`），目标多端：HarmonyOS、Android、iOS、Windows、macOS、Linux、Web
> 上游决策依据：`docs/research/codex-best.md`（三份调研的整合最优方案）
> 后续产物：实施计划（writing-plans）

---

## 1. 问题与目标

### 1.1 问题

生产 App 已使用 `perfect_freehand` 生成变宽轮廓，但线条仍存在明显锯齿和尖锐转角。经源码逐行核实，问题不是"没有平滑算法"，而是现有管线存在 4 个需要通过阶段 0/1 A/B 验证的高优先级候选原因：

| 优先级 | 缺陷 | 源码位置（已核实） |
| --- | --- | --- |
| P0 | outline 用 `Path.addPolygon` 直线段渲染，把 perfect-freehand 内部已平滑的轮廓顶点又连成多边形折线 | `freedraw_renderer.dart:107` |
| P1 | 鸿蒙侧固定 EMA `positionAlpha=0.35`，无时间戳/速度/曲率自适应 | `harmony_stylus_stroke_smoother.dart:21,140-143` |
| P1 | `up()` 位置已 flush 真实终点（不再走 EMA），但 pressure 仅做单次 EMA 后 `reset()`；整体仍无时间戳/速度自适应 | `harmony_stylus_stroke_smoother.dart:76-102` |
| P1 | 实时与最终笔迹都固定 `isComplete=true`（在 `buildOutline()` 内硬编码），新增点时尾部端帽跳变 | `freedraw_renderer.dart:68` |

补充背景：
- `FreedrawTool`（`freedraw_tool.dart`）只接收 `Point + pressure`，没有时间戳、没有设备类型——它已经是输入的下游，所以平滑只能加在它的上游（pointer 路由处）。
- 新代码已将 `getStroke` 逻辑提取为独立纯函数 `FreedrawRenderer.buildOutline()`（`:43-72`），`draw()` 委托它获取 outline 后仍用 `addPolygon`（`:107`）渲染。这为阶段 1 的 `OutlinePathBuilder` 改造提供了更干净的基础。
- 新代码新增 `pointer_pressure.dart`：`reliableStylusPressure()` 使用 `pressureMin/Max` 归一化压感，`shouldDispatchToCreationTool()` 替代旧 `_isStylusDown` 防误触。阶段 3 的 `StrokeInputNormalizer` 需吸收/替换这些逻辑以避免重复。
- 旧 controller 中"up 后补发 move"的 quirk（原 `:1271-1281`）已在新代码中移除，阶段 3 无需额外处理。

### 1.2 目标

建立跨平台统一书写管线，消除上述缺陷，达成：

- 慢速书写边缘锯齿明显减少；
- 转角（汉字折笔、L/V/Z）保真，不被过度磨圆；
- 快速书写无可感知的额外拖尾；
- 抬笔终点准确到位，不缩短、不回弹；
- 压感粗细连续，无相邻宽度突跳。

### 1.3 范围

核心交付覆盖阶段 0-5：录制/回放工具链、渲染修复、终点 flush、统一输入建模层和协同一致性验证。阶段 6 的 HarmonyOS 原生报点预测是独立、带准入门槛的后续 spike，不阻塞本设计核心交付完成。

### 1.4 不在范围

- 不替换 `perfect_freehand`，不重复引入同类曲线库；
- 不引入 Google Ink Stroke Modeler 作为本轮主引擎（列为未来独立 spike）；
- 不切换原生 HandwriteComponent 作为主书写引擎。

---

## 2. 整体架构与数据流

### 2.1 目标数据流

```
各平台 PointerEvent（Flutter 统一入口）
  ↓
StrokeInputNormalizer       [新建] 在 EditorCanvas 接收完整事件并规范化
  ↓
InputPolicySelector         [新建] 按 kind(stylus/touch/mouse) 选策略
  ↓
StrokeInputModeler          [新建] OneEuro 位置滤波 + 独立 pressure 滤波 + 转角保护
  ↓                          （吸收 HarmonyStylusStrokeSmoother 职责，后者移除路由）
建模后的真实点
  ├→ 湿墨：ToolOverlay(points + pressures + isComplete=false，全量预览)
  └→ 干墨：抬笔 flush 真实终点 + FreedrawElement + isComplete=true
       ↓
       FreedrawTool（接口不变，仍收 Point + pressure）
       ↓
       perfect_freehand.getStroke → outline 点
       ↓
       OutlinePathBuilder       [改造] 二次中点曲线（OutlineRenderMode 枚举切换）
       ↓
       Canvas fill
```

### 2.2 关键边界约束

- **只有 freedraw 工具经过 `StrokeInputModeler`**；选择、擦除、平移等工具走原始坐标，完全不受影响。
- **单活动绘制 pointer**：现有 `FreedrawTool` 只有一份 `_points/_pressures/_isDrawing` 状态。本轮由 pointer-down 获取绘制所有权，其他 pointer 不进入该笔；不在本轮扩展为多 pointer 同时绘制。
- **滤波坐标系固定为 EditorCanvas local logical pixels**：先在 localPosition 空间完成建模，再由 controller 转为 scene coordinates。这样 One Euro 和最小距离参数不随 viewport zoom 改变；录制文件同时保存 viewport 元数据用于回放。
- **预测点只进湿墨层**，永不进入持久化和协同数据。阶段 6 才接入原生预测，但数据流现在就为其预留 transient 标记位置。
- **协同与持久化只发干墨的稳定 points/pressures**。
- **运行时开关**：`OutlineRenderMode { polygon, quadratic }` 用于渲染 A/B；滤波用 feature flag 可回退到固定 EMA。
- `Tool.onPointerDown/Move/Up` 的 `Point + pressure` 调用形式保持不变；但 `ToolOverlay` 必须增加 pressures 和完成态，`FreedrawRenderer.draw` 必须接收 `isComplete`，因此预览/渲染接口会有受控变更。
- 原始事件只进入 recorder/trace；正式 `FreedrawElement` 保存建模后的稳定 points/pressures，保证协同端无需重跑依赖本机采样时序的滤波器。
- **现有基础设施可利用**：新代码已将 `getStroke` 提取为 `FreedrawRenderer.buildOutline()` 纯函数（`:43-72`），并新增 `pointer_pressure.dart` 提供 `reliableStylusPressure`（pressureMin/Max 归一化）和 `shouldDispatchToCreationTool`（touch 抑制）。`StrokeInputNormalizer` 应吸收这些逻辑避免重复实现。

---

## 3. 子系统分解

整个工作分为 6 个边界清晰、可独立实现和测试的子系统。每个对应 `codex-best.md` 的一组阶段。

| 子系统 | 职责 | 对应阶段 | 主要改动 |
| --- | --- | --- | --- |
| **S1 输入规范化** | `StrokeInputSample` 模型 + `StrokeInputNormalizer` | 阶段 0（供 recorder 使用） | 新建文件；阶段 3 再接入正式工具路由 |
| **S2 输入建模器** | `StrokeInputModeler`（OneEuro + 转角保护 + pressure 独立滤波）+ `InputPolicySelector` | 阶段 3 | 新建文件；移除 `HarmonyStylusStrokeSmoother` 调用路由 |
| **S3 轮廓渲染** | `OutlinePathBuilder` + `OutlineRenderMode` + wet/dry 完成态和压感预览 | 阶段 1、2 | 改 renderer、`ToolOverlay` 和 preview 构建 |
| **S4 终点 flush** | `up()` 收敛到真实终点，不再只走一次 EMA | 阶段 2 | 含在 S2/S3 |
| **S5 录制回放** | `StrokeRecorder` + `StrokeInputModelerTrace` + `StrokeRenderMetrics` + `StrokeReplayRunner`（仅 debug/test 构建） | 阶段 0 | 新建文件 |
| **S6 协同一致性** | 验证干墨 JSON 往返、预测点隔离和接收端同算法渲染 | 阶段 5 | 原则上不改协议；测试暴露问题时再最小修正 |

### 3.1 S1：StrokeInputSample 模型

规范化样本，是整个管线的通用货币。不直接序列化 Flutter `PointerEvent`，避免离线测试依赖手势事件构造细节。

```dart
enum StrokeInputKind { stylus, invertedStylus, touch, mouse, unknown }
enum StrokePhase { down, move, up, cancel }
enum StrokeSampleSource { actual, predicted }

class StrokeInputSample {
  final int pointerId;               // 当前活动绘制 pointer 的身份
  final double x, y;                 // EditorCanvas local logical pixels
  final Duration time;               // 单调时间戳（采样率无关滤波的关键）
  final double? pressure;            // null = 无可靠真实压感
  final StrokeInputKind kind;        // 与 Flutter 类型解耦
  final StrokePhase phase;           // down / move / up / cancel
  final StrokeSampleSource source;   // actual / predicted
}
```

`StrokeInputNormalizer` 位于 `EditorCanvas` 的 Listener 边界，接收完整 `PointerEvent`，而不是等 controller 丢失信息后再恢复。它负责：

- 传递 `event.pointer`、`event.timeStamp`、kind 和 phase；
- 在 local logical-pixel 坐标完成建模；modeler 输出后再调用 viewport `screenToScene`；
- recorder 额外记录 viewport zoom/transform，确保离线回放可还原 scene geometry；
- 仅在设备确实提供可靠压感时输出非 null pressure。使用 `pressureMin/pressureMax` 归一化（吸收现有 `reliableStylusPressure()` 算法，该函数位于 `pointer_pressure.dart`）；mouse pressure、无可靠范围的 touch pressure 不得被误判为真实压感；
- 在 `Listener.onPointerCancel` 生成 cancel 样本；
- 将 Flutter `PointerDeviceKind` 映射为纯 Dart `StrokeInputKind`，使 modeler 不依赖 Flutter。

### 3.2 S2：StrokeInputModeler

平台无关纯 Dart 组件，只依赖项目自有 `StrokeInputKind`，可在测试里直接喂数据，便于 S5 回放。

```dart
enum StrokeModelDecision { emitted, dropped, reset }

class StrokeModelResult {
  final ModeledPoint? output;         // dropped/reset 时为 null
  final StrokeModelDecision decision;
  final String? reason;               // 仅供 debug trace
}

class ModeledPoint {
  final Point point;
  final double? pressure;
}

abstract class StrokeInputModeler {
  // 单个活动 stroke：down 获取 pointer 所有权，up/cancel 释放
  StrokeModelResult process(StrokeInputSample sample);
  void reset({String? reason});
}
```

**OneEuro 位置滤波**（核心）：

```
cutoff = minCutoff + beta * |filteredVelocity|
```

- 低速：降低截止频率，抑制测量噪声和手抖；
- 高速：提高截止频率，减少跟手延迟；
- X/Y 共用速度幅值确定 cutoff，避免两轴响应不同；
- 使用统一单调时间基准计算真实 `dt`。

**pressure 独立滤波**：位置和 pressure 使用独立参数分别滤波。

**pressure 模式锁定**：down 时由 `InputPolicy` 决定本笔是否使用真实 pressure。真实压感模式下，偶发缺失值沿用最后一个有效值；模拟压感模式下整笔保持 pressure=null，最终 `pressures` 为空并由 `perfect_freehand` 模拟。禁止一笔中途从模拟切到真实，保证 `pressures.length == points.length` 或 `pressures.isEmpty`。

**转角保护**：根据连续方向向量夹角处理——方向变化较小时用正常自适应滤波；超过阈值时临时提高响应速度；不对单个异常点立即触发，需结合最小移动距离和连续样本。目的是保护用户真实折笔，而不是保留所有尖角。

**InputPolicySelector**：按设备类型配置不同策略，最终渲染算法各端一致：

- stylus：真实 pressure，启用位置与 pressure 自适应滤波；
- touch：保留当前“创作工具下手指用于平移、不绘制”的默认交互；仅在未来启用 finger drawing 时使用模拟 pressure 和较保守的位置滤波；
- mouse：默认不做强滤波，只去重和最小距离处理，避免直线操作产生拖尾。

**与现有 HarmonyStylusStrokeSmoother 的关系**：S2 上线时吸收其职责，并移除 `markdraw_controller` 中对它的调用路由，避免双重平滑。固定 EMA 只保留为 modeler 内部的 debug 对照策略，不继续走旧 Harmony 专属调用链。

### 3.3 S3：OutlinePathBuilder

> **现有基础设施**：新代码已将 `getStroke` 逻辑提取为 `FreedrawRenderer.buildOutline()` 纯函数（`:43-72`），`draw()` 委托它获取 outline。本子系统在此基础上新增 `buildOutlinePath()`，替换 `draw()` 中 `:107` 的 `addPolygon`。

```dart
enum OutlineRenderMode { polygon, quadratic }   // 运行时 A/B 切换

Path buildOutlinePath(List<PointVector> outline, OutlineRenderMode mode);
```

- `quadratic`：perfect-freehand 官方二次中点法——以 outline 点为控制点、以相邻 outline 点中点为终点构造连续二次贝塞尔闭合路径；
- `polygon`：现有 `addPolygon`（作为对照基线，验证期保留）。

规则：`OutlineRenderMode` 是 debug/test 全局模式；活动笔画期间禁止切换，切换后允许测试场景中的全部笔迹一起重绘，不为此增加持久化字段。同一录制样本离线可同时输出两种模式做 A/B。

**wet/dry 完成态和压感预览**：

- `ToolOverlay` 为 freedraw 暴露 `creationPoints`、`creationPressures` 和 `isComplete=false`；
- `buildPreviewElement` 用相同 points/pressures 创建预览，避免当前预览无 pressure、完成后突然变宽的差异；
- `FreedrawElement` 增加运行时 `isComplete`，默认 true；preview 构造时设为 false。该字段不进入 JSON，正式场景元素始终为 true；
- `FreedrawRenderer.buildOutline(..., isComplete:)` 和 `draw(..., isComplete:)` 不再固定 true；
- 场景中的 `FreedrawElement` 按完成态渲染，预览元素按湿墨态渲染；
- `RoughCanvasAdapter` 持有 debug/test 全局 `outlineRenderMode` 并传给 `FreedrawRenderer`，controller 的实验设置负责同步；正式构建固定为验证后的模式；
- 第一版沿用当前 preview element 机制，每次用全部 creationPoints 重建湿墨；只有指标证明超出帧预算时，才另行设计最近 N 段缓存/增量渲染；
- 二次闭合路径必须显式处理最后一点到第一点的接缝，并加入 seam、自交和小点数测试。

### 3.4 S4：终点 flush

`up()` 的 modeler 结果必须包含未经低通截短的真实终点。controller 在调用 `FreedrawTool.onPointerUp` 前，只有当该终点尚未进入工具点列时才补发一次 move（注意：旧代码中补偿 smoother 的"up 后补发 move"quirk 已在新代码中移除，此处仅指 modeler flush 后的去重补发）。随后 `onPointerUp` 只负责提交元素并释放活动 pointer。

### 3.5 S5：录制回放工具链（仅 debug/test）

| 组件 | 职责 |
| --- | --- |
| `StrokeRecorder` | local logical-pixel 位置、时间戳、pressure、`StrokeInputKind`、phase、pointer id、viewport 元数据 |
| `StrokeInputModelerTrace` | 过滤后位置、pressure、被丢弃原因 |
| `StrokeRenderMetrics` | outline 点数、`getStroke` CPU 耗时、Path 构建耗时、Canvas 命令提交 CPU 耗时、Flutter frame timings |
| `StrokeReplayRunner` | 用相同事件序列重复运行不同算法参数，输出上述所有指标 |

约束：保存规范化 `StrokeInputSample`；保持事件顺序、phase、pointer/stroke id、原始时间间隔；每次结果记录算法参数、渲染模式、平台/设备、构建版本；仅 debug/test 构建启用；回放同时生成指标和图像。`Canvas.drawPath` 的 Stopwatch 只能衡量 CPU 命令提交，不能冒充 GPU/raster 耗时；端到端帧性能使用 `FrameTiming`/DevTools。**自检门槛**：同一算法对同一录制样本得到确定性几何结果，才能开始后续阶段；跨渲染后端图像只要求容差内一致，不要求像素逐位相同。

为避免把性能采集散落在 painter 中，`FreedrawRenderer` 将 outline 生成和 Path 构建拆成可独立调用的纯函数；debug/test 下由可空 `StrokeRenderMetricsSink` 接收阶段耗时和点数，release 下 sink 为 null 且不执行 trace 分配。

### 3.6 S6：协同一致性

- JSON 往返保持建模后的 points/pressures；
- 接收端使用相同 renderer 参数构建显示，不重新运行输入滤波；
- 预测点和湿墨临时状态不进入协同；
- 多端同时书写时，完成笔迹在各端显示一致。

阶段 6 的原生预测点作为 `StrokeInputSample.source=predicted` 进入湿墨层，不污染 S6 协同数据。该阶段单独产出 spike 结论，不属于阶段 0-5 的完成条件。

---

## 4. 错误处理

来自 `codex-best.md §4.4/§7.1`，关键鲁棒性约束：

- `dt <= 0`、超长间隔、异常坐标 → **旁路滤波**，直接输出原始点，不抛异常；
- pressure 缺失 → 保持 null，由 `perfect_freehand simulatePressure` 处理，不伪造真实 pressure；
- `PointerCancelEvent` → reset modeler 和 `FreedrawTool`，丢弃未提交的当前 stroke，并释放活动 pointer；
- 非活动 pointer 的 move/up/cancel → 忽略，不得污染当前笔画；
- 空/单点/双点笔迹 → 不崩溃；单点画圆点、双点画直线（保留现有逻辑）；
- 二次轮廓路径 → 不产生 NaN/Infinity。

---

## 5. 测试策略

- **S2 单元测试**（纯 Dart，可离线跑）：相同几何不同采样率输出接近；慢速噪声下降、快速滞后受控、转角不被磨圆；`up` 终点等于真实终点；pressures 数量始终等于 points。
- **S3 单元测试**：空/单点/双点不崩；二次路径闭合；闭合 seam 连续；无 NaN/Infinity；湿墨预览与干墨使用相同 points/pressures，差异仅来自完成态。
- **S5 回放测试**：同一录制样本、相同算法参数 → 确定性输出（阶段 0 自检门槛）。
- **输入路由测试**：active pointer 所有权、非活动 pointer 忽略、cancel 清理、非 freedraw 工具旁路、mouse/touch 不误判真实 pressure。
- **回归测试**：选择/擦除/缩放/撤销/导出后笔迹几何一致；JSON 往返 points/pressures 一致。

---

## 6. 成功标准（双轨）

### 6.1 量化指标

由 S5 工具链生成。门槛为"相对当前基线明显改善且无保真回归"，不预设固定百分比，积累多次真机数据后再固化数值阈值。

| 指标 | 目的 |
| --- | --- |
| 直线正交方向 RMS | 低速抖动 |
| 圆/椭圆拟合残差 | 曲线稳定性 |
| 原始点到最终中心轨迹 P95 偏差 | 防过度修形 |
| L/V/Z 转角位置和角度偏差 | 折笔保真 |
| 最终点误差 | 抬笔 flush |
| 单帧处理 P50/P95/P99 | 跟手和卡顿 |
| 每笔 points/outline 数量 | 数据规模 |

### 6.2 人工验收清单（真机）

- 慢速斜线和小圆的边缘锯齿明显低于当前基线；
- 快速书写没有可感知的额外拖尾；
- L/V/Z 与汉字折笔位置未被明显磨圆或偏移；
- 快速抬笔不缩短、回弹或产生尖刺；
- 压感粗细连续，无相邻宽度突跳；
- 手指和鼠标仍保持各自当前交互语义；
- 各平台笔迹均得到改善；
- 协同接收端与发送端显示一致。

### 6.3 验收样本

每个版本在同一台设备、同一缩放、同一笔宽下录制：极慢直线、快速直线、大圆、小圆、连续 8 字、L/V/Z、汉字"永""我""流"、压力由轻到重再到轻、快速抬笔。验收时同时保留：原始采样点、滤波后中心点、outline 点、截图/录屏、每帧耗时与点数。

---

## 7. 实施顺序（与 codex-best 阶段对应）

> 详细步骤由后续 writing-plans 产出，这里只给高层顺序，确保每阶段可独立 A/B、测试和回退。

1. **阶段 0（S1+S5）**：先建立最小 `StrokeInputSample/Normalizer`，再完成基线与录制回放工具链。此时 normalizer 只服务 recorder，不改变正式绘制路由；先验证 recorder/replay 对同一算法得到确定性结果。
2. **阶段 1（S3）**：轮廓曲线路径 A/B（`OutlineRenderMode` 枚举）。若 quadratic 明显降低边缘锯齿且无自交/缺口/端帽异常，全局替换。
3. **阶段 2（S3+S4）**：终点 flush 与完成态修正。
4. **阶段 3（S1+S2）**：跨平台 OneEuro + 转角保护 + 统一 pointer 输入层；移除 HarmonyStylusStrokeSmoother 路由防双重平滑。
5. **阶段 4**：参数实验（小规模网格，stylus/touch/mouse 分别选参）；仅当性能数据表明点数过高时，在干墨阶段尝试误差受控 RDP。
6. **阶段 5（S6）**：序列化和协同一致性。
7. **阶段 6（独立 spike，可选）**：HarmonyOS 原生报点预测可行性验证；阶段 0-5 验收后才能启动，若预测收益小于桥接延迟或增加抖动，保持关闭。

---

## 8. 暂不采用的方案（及原因）

- **只调高 perfect_freehand 参数（0.8/0.7）**：无法修复 `addPolygon` 直线轮廓；更强 streamline 可能损失折笔和小字细节；无真机实验依据。
- **实时 RDP**：是几何简化非速度自适应去噪；新点加入时保留/删除点可能变化，导致实时笔迹跳动；可能删除汉字短折笔；当前无点数/性能证据证明必须简化。仅当性能数据表明必要时，考虑抬笔后误差受控简化。
- **Google Ink Stroke Modeler**：C++ FFI 和 HarmonyOS 构建维护成本高；不替代 pressure→轮廓的笔刷成形；当前纯 Dart 管线尚未完成低风险修正。列为未来独立 spike。
- **直接切换原生 HandwriteComponent**：形成 Flutter 编辑器与原生画布双引擎；选择/擦除/撤销/缩放/序列化/协同都需重对接；本轮问题是笔迹质量，不足以证明替换整个编辑器。

---

## 9. 参考资料

- 上游整合方案：`docs/research/codex-best.md`
- 三份原始调研：`docs/research/codex-research.md`、`claude-research.md`、`zcode-research.md`
- perfect-freehand（含官方渲染示例）：<https://github.com/steveruizok/perfect-freehand>
- One Euro Filter（Casiez et al., CHI 2012）：<https://doi.org/10.1145/2207676.2208639>
- Windows Ink wet/dry 模型：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkpresenter>
- Android Ink API（预测点替换规则）：<https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules>
- HarmonyOS 报点预测：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pen-point-prediction>

---

## 10. 文档边界

- 本设计基于生产 App（FlowMuse-App）源码静态分析，根因排序在实施前仍须通过相同真机输入做 A/B 验证；
- 不代表商业产品公开了其全部私有算法；对商业产品的判断仅采用可公开确认的框架和能力；
- 本文是技术设计，不含代码修改；后续由 writing-plans 产出实施计划并逐阶段验证。
