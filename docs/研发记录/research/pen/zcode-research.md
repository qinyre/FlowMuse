# 笔迹线条平滑方案调研：成熟产品如何处理书写线条

日期：2026-07-09

用途：调研成熟办公/书写产品（GoodNotes、Notability、Procreate、tldraw、Excalidraw、Sketchbook 等）如何把手写笔/手指的原始采样点渲染成光滑、柔顺的线条；定位当前项目线条锯齿、转角尖锐的根因，并给出可直接落地的改进路线。

受众：本项目后续 AI/开发者。结论先行，所有代码引用都标注了 `file:line`，便于直接跳转。

---

## 结论先行（TL;DR）

1. **当前项目线条锯齿的根因是确定的、单点的**：`lib/features/whiteboard/widgets/spike_canvas.dart:54-56` 用一个 `path.lineTo` 循环把**每一个原始采样点**连成直线段，没有任何曲线平滑、没有任何压感/速度驱动的宽度变化。这样画出来的是一条折线（polyline），锯齿和尖锐转角是几何上的必然结果，与本项目 Stage-1 的验收记录一致（`docs/研发记录/plans/2026-07-06-pen-spike-stage1-result.md:56` 明确写"模拟点画出折线"）。

2. **成熟产品的"光滑感"不是来自单一魔法，而是 4 层叠加**（输入采集 → 点云预处理 → 曲线拟合 → 变宽轮廓渲染），本项目目前**只做了第 1 层的采集和第 4 层的最简 stroked 直线**，中间两层完全缺失。

3. **行业事实标准算法是 perfect-freehand**（Steve Ruiz，tldraw 作者开源），它 = Catmull-Rom 样条平滑中心线 + 压感/速度驱动的变宽 + 垂直偏移生成闭合多边形（fill 而不是 stroke）。Excalidraw、tldraw、以及本项目的姊妹工程 `FlowMuse-App` 都在用。

4. **最小改动见效**：不引入任何新依赖，把 `lineTo` 循环换成 **Catmull-Rom → 三次贝塞尔** 转换，锯齿即可消除 70%+。**推荐改动**：引入 `perfect_freehand`（或已有 Dart port `freehand`）+ 压感通道，达到与 GoodNotes 同档的观感。两条路在本项目都已有现成参考实现。

---

## 一、问题确认：当前实现到底哪里不行

### 1.1 渲染代码（根因所在）

`lib/features/whiteboard/widgets/spike_canvas.dart:52-57`：

```dart
final path = Path();
path.moveTo(stroke.points.first.x, stroke.points.first.y);
for (int i = 1; i < stroke.points.length; i++) {
  path.lineTo(stroke.points[i].x, stroke.points[i].y);   // ← 直线段连点
}
canvas.drawPath(path, paint);
```

每两个采样点之间都是一段**直线**。手写笔/触摸输入天然带有抖动（手指微颤、屏幕采样噪声、预测点误差），这些抖动被原封不动地呈现为折线的顶点，肉眼即表现为锯齿。两段直线在顶点处夹角是硬折，即"转角尖锐"。

### 1.2 已做的努力及其局限

| 已有措施 | 位置 | 作用 | 为什么不够 |
| --- | --- | --- | --- |
| `StrokeCap.round` | `spike_canvas.dart:33` | 圆头线帽 | 只美化线段**两端**，不改变中段几何 |
| `StrokeJoin.round` | `spike_canvas.dart:34` | 圆角连接 | 用圆角"打磨"折点外侧，但相邻两段仍是直线，折角本身没消失 |
| 固定 `strokeWidth = 4` | `spike_canvas.dart:32` | 等宽 | 没有任何粗细变化，丢失了书写的"柔顺"质感 |
| Skia 默认边缘 AA | Skia 内建 | 抗锯齿 | 只反走样像素边缘，不能消除几何上的折线 |

### 1.3 数据链路里完全没有平滑

- 采集侧（`ohos/entry/.../plugin_manager.cpp:18-66`）：用 `OH_NativeXComponent_GetHistoricalPoints` 批量取历史点 + `HMS_HandWrite_GetPredictPoint` 取预测点，原始 `[x,y,force,ts]` 直接进 `PointBuffer`。
- 桥接侧（`ohos/entry/.../SpikePlugin.ets:20-25`）：`setInterval` 每 8ms 轮询拉点，经 EventChannel 推到 Dart。
- 渲染侧（`spike_canvas.dart`）：直接 `lineTo`。

**全程无任何：去重、抽稀、滑动平均、曲线拟合。** 压力 `force`/`pressure` 字段一路采集到了 Dart（`models/stroke_point.dart:33-38`），但渲染时被完全忽略。

> 设计文档本来就要做平滑：`docs/研发记录/specs/2026-07-06-harmonyos-pen-whiteboard-design-v2.md` 第 196-209 行的"笔刷渲染：perfect_freehand"小节、数据流图（124-133 行）末端的"perfect_freehand 把 points 转成轮廓多边形"，都是 Stage-1 主动延后、尚未实现的。所以这不是"漏了"，而是"还没到"，现在正是补上它的时候。

---

## 二、成熟产品笔迹光滑感的四层来源

把成熟产品拆开看，"光滑柔顺"是下面 4 层叠加的结果。任何一层缺失都会让线条"差一口气"。下表先给全景，后面逐层展开。

| 层 | 做什么 | 典型技术 | 代表产品 | 本项目现状 |
| --- | --- | --- | --- | --- |
| L1 高密度采样 | 每帧拿多个历史点 + 预测点 | coalesced/historical points、报点预测 | Apple Pencil、HarmonyOS Pen Kit | ✅ 已做（`plugin_manager.cpp`） |
| L2 点云预处理 | 去抖动、抽稀、轻量滤波 | 滑动平均、RDP 简化、时间加权 | 几乎所有专业 App | ❌ 完全缺失 |
| L3 曲线拟合 | 把折线变成 C¹/C² 连续曲线 | Catmull-Rom、三次贝塞尔、B 样条 | tldraw、Excalidraw、Procreate | ❌ 完全缺失 |
| L4 变宽轮廓 | 用压感/速度驱动宽度，画填充多边形 | perfect-freehand outline、笔锋模型 | GoodNotes、Procreate、Notability | ❌ 用的是固定宽 stroke |

### L1：高密度采样（减少信息丢失）

成熟产品首先保证**输入端不丢点**。屏幕刷新率（60/120Hz）远低于触控报点率（Apple Pencil、HarmonyOS 手写笔可达 120–240Hz），如果每帧只取一个点，会把大量中间点丢掉，导致后续无论怎么拟合都"锯"。成熟做法是：

- **Coalesced / Historical points**：单次 UI 事件回调里取出该帧内**全部**原始报点（iOS `getCoalescedTouches`、Win32 `RealTimeStylus`、HarmonyOS `OH_NativeXComponent_GetHistoricalPoints`）。
- **预测点（Predictive point）**：基于近期运动外推 1–2 个未来点，提前渲染以降低端到端延迟感（HarmonyOS 的 `HMS_HandWrite_GetPredictPoint`、Android `MotionEvent.getPredicted`、iOS `predictedTouches`）。

> 本项目 L1 已达标（`plugin_manager.cpp:21,42`），这是好消息——说明数据源是足够密的，锯齿不是"点太少"，而是"没拟合"。

### L2：点云预处理（去抖、抽稀、轻量滤波）

原始点带噪声，直接拟合成曲线会把噪声也"光滑地"放大成波浪。成熟产品会先过一道预处理：

- **滑动平均 / 指数加权（EMA）**：对每个点的坐标与前后若干点做加权平均，压制高频抖动。代价是引入微小延迟，需窗口控制（通常 3–5 点）。这是 Procreate「StreamLine」、Adobe Substance「Lazy Mouse」的本质——用一个"跟随延迟"换来视觉平滑。
- **RDP（Ramer–Douglas–Peucker）抽稀**：在允许误差内去掉几乎共线的冗余点，降低后续拟合负担，也减少"折点数量"。
- **时间加权 / 速度阈值**：对停留过久的点降权，避免笔尖静止时堆叠噪声。

Lazy Mouse / StreamLine 的"手感"本质就是 **位置平滑**：渲染点 ≠ 光标点，渲染点以一定弹性追赶光标，路径自然被拉直、去抖。

### L3：曲线拟合（折线 → 光滑曲线）

这是消除"锯齿/尖锐转角"最关键的一层。核心思路：相邻采样点之间不再用直线，而用**曲线**连接，并保证在连接点处**一阶/二阶导数连续**（C¹/C²），转角就被"圆滑过渡"掉了。

主流算法（按使用频率）：

| 算法 | 连续性 | 是否经过控制点 | 适合场景 | 备注 |
| --- | --- | --- | --- | --- |
| **Catmull-Rom 样条** | C¹ | ✅ 经过所有点 | 通用笔迹平滑首选 | 笔迹最常用；推荐用**向心参数化（centripetal, α=0.5）**避免自交/尖刺 |
| 三次贝塞尔（由 Catmull-Rom 转换） | C¹（拼接处） | 否（控制点偏移） | 渲染输出 | Canvas/SVG 原生支持；由 Catmull-Rom 推导控制点 |
| B 样条（B-spline） | C² | 否（逼近） | 想要更柔、不必精确过点 | 更柔顺，但"不经过采样点"会让笔迹略偏原意图 |
| Chaikin 角切分 | C¹（极限） | 否 | 快速近似 | 递归切角，实现极简，效果近似均匀 B 样条 |

**Catmull-Rom → 三次贝塞尔**的标准转换公式（本项目可直接套用）：

给定四个相邻点 P0、P1、P2、P3，在 P1→P2 之间画一段三次贝塞尔，控制点为：

```
C1 = P1 + (P2 - P0) / 6
C2 = P2 - (P3 - P1) / 6
```

端点用虚拟点（复制首/末点）补齐即可。这一招就能把当前的折线变成 C¹ 连续的光滑曲线。姊妹工程 `FlowMuse-App` 的 `_buildBezierPath`（`.../rendering/rough/freedraw_renderer.dart:110-128`）就是这个实现，可直接参考。

### L4：变宽轮廓渲染（让线条"有生命"）

最高级的"柔顺感"来自**宽度随压感/速度变化**，并用**填充多边形**而非描边来画。这是 GoodNotes、Procreate、Notability 与普通"画线 App"拉开档位差距的地方。

- **压感驱动**：压感大 → 笔画粗；抬笔 → 收尖。需要 L1 采集的 `force/pressure` 通道。
- **速度模拟压感**：无压感设备（手指/普通触控笔）时，用**速度反推**等效压感（速度快 → 力轻 → 细；速度慢 → 力重 → 粗），效果接近真实书写。
- **轮廓多边形**：沿平滑后的中心线，在每个点计算法向量，向两侧偏移"当前半宽"，生成一条闭合外轮廓，**fill 而不是 stroke**。这样宽度可逐点变化，且天然 C¹ 连续、无 join 毛刺。

**perfect-freehand** 就是把 L2+L3+L4 打包成一行 `getStroke(points, options)` 的开源实现，输出即"外轮廓点数组"，交给 Canvas fill 即可。

---

## 三、核心算法详解：perfect-freehand（行业事实标准）

### 3.1 它是什么

作者 Steve Ruiz（同时也是 tldraw 的作者），MIT 协议。仓库 [steveruizok/perfect-freehand](https://github.com/steveruizok/perfect-freehand)。Excalidraw、tldraw、大量白板/笔记产品在用。**本项目的姊妹工程 `FlowMuse-App` 已经在用**（`pubspec.yaml:56` → `perfect_freehand: ^2.5.0`）。

### 3.2 `getStroke` 的输出与关键参数

`getStroke(points, options)` 返回的是**外轮廓点数组**——这些点连成一个闭合多边形（"stroke"），包住原始输入点。直接对它做 `canvas.drawPath(..., PaintingStyle.fill)` 即可。

关键 options（来自官方 README）：

| 参数 | 含义 | 调参直觉 |
| --- | --- | --- |
| `size` | 笔画基础粗细（直径，px） | 越大越粗 |
| `thinning` | 压感对粗细的影响程度（±1） | 0=完全等宽；正值压感变粗、负值变细 |
| `smoothing` | 末端平滑（0–1） | 越大越柔，但延迟略增 |
| `streamline` | 路径平滑/抗抖（0–1） | 越大越像 Lazy Mouse，越抗手抖 |
| `simulatePressure` | 无真实压感时是否用速度模拟 | 手指/普通笔设 true |
| `start/end cap/taper` | 起笔/收笔形状（圆头/锥尖） | 控制"笔锋" |

### 3.3 内部流程（L2+L3+L4 的组合）

1. 用 `streamline` 对输入点做位置平滑（L2，类 Lazy Mouse）。
2. 对每个点算"半径"：真实压感或速度模拟压感 × `thinning` × `size`（L4 宽度）。
3. 用 Catmull-Rom 风格样条对中心线插值加密（L3 平滑）。
4. 沿平滑中心线对每个采样点算法向量，按半径向两侧偏移，得到左右两条外轮廓边。
5. 首尾按 cap/taper 参数收口，拼成闭合多边形返回。

> 注意：perfect-freehand 的"精确内部公式"以源码为准（`src/getStrokeOutlinePoints.ts`），上面是工程化抽象。对使用者来说，把 `getStroke` 当黑盒、调好上面 6 个参数即可。

### 3.4 压感缺失时的速度模拟

当设备/输入不提供压感（手指、普通电容笔），成熟产品一律用**速度反推**等效压感。姊妹工程的 `freedraw_tool.dart:12-14, 68-88` 就是典型：有触控笔压感读真实值，否则置 `simulatePressure: true`。完美模仿"快写细、慢写粗"。

---

## 四、成熟产品做法速览

| 产品 | 主要手段（公开/可推断） | 说明 |
| --- | --- | --- |
| **tldraw / Excalidraw** | perfect-freehand（开源可查） | 事实标准参考实现；Excalidraw 早期自有算法，后也对接 perfect-freehand |
| **GoodNotes** | 笔画稳定（Stroke Stabilization，约 50% 推荐）+ 压感变宽 + 轮廓 fill | 用户可调稳定度；内部算法未公开，但 L2+L3+L4 分层一致 |
| **Procreate** | StreamLine（位置平滑/Lazy Mouse）+ Stabilization（运动滤波）+ QuickShape（抬笔后几何校正）+ 压感笔刷 | 笔刷引擎级；StreamLine 抗抖、Stabilization 拉直、QuickShape 把近似圆/直线规整化 |
| **Notability / Notewise** | 类 StreamLine 的 stabilization + 压感 | 用户体验与 GoodNotes 同档 |
| **Autodesk Sketchbook** | Steady Stroke（连续平滑）+ Predictive Stroke（几何分析，把歪线收拢成规整曲线/圆） | Predictive 偏向"画规整图形"，不是纯自由书写 |
| **ZBrush / Adobe Substance（Lazy Mouse）** | 光标与实际落笔点的空间偏移 + 均值平滑 | 概念源头之一，"笔尖拖着画走" |

共同点：**没有一个成熟产品把原始点直连成折线**。L2/L3/L4 至少做到其中两层。

参考链接：

- perfect-freehand：<https://github.com/steveruizok/perfect-freehand>
- tldraw Draw Shape 文档：<https://tldraw.dev/sdk-features/draw-shape>
- Catmull-Rom 实战教程（含 C++）：<https://qroph.github.io/2018/07/30/smooth-paths-using-catmull-rom-splines.html>
- Catmull–Rom 样条（Wikipedia，向心参数化）：<https://en.wikipedia.org/wiki/Catmull%E2%80%93Rom_spline>
- perfect-freehand 的 Dart/Flutter 移植版（无需 JS 互操作）：<https://pub.dev/documentation/freehand/latest/>
- Procreate StreamLine / Stabilization：<https://www.amikosimonetti.com/life/smooth-lines>
- Sketchbook Steady / Predictive Stroke：<https://help.sketchbook.com/docs/steady-and-predictive-stroke>
- Adobe Substance Lazy Mouse：<https://experienceleague.adobe.com/en/docs/substance-3d-painter/using/painting/lazy-mouse>
- Android 手写笔低延迟：<https://medium.com/androiddevelopers/stylus-low-latency-d4a140a9c982>

---

## 五、针对本项目的改进路线（按性价比排序）

> 三条路线，按"改动量从小到大 / 效果从基础到专业"排列。建议按 A→B→C 渐进，A 当天可验证，B 作为主目标，C 作为专业级目标。

### 路线 A：最小改动 —— Catmull-Rom → 三次贝塞尔（当天见效，0 新依赖）

把 `spike_canvas.dart:54-56` 的 `lineTo` 循环换成：

```
对每个相邻四点组 (P0,P1,P2,P3)：
  C1 = P1 + (P2 - P0) / 6
  C2 = P2 - (P3 - P1) / 6
  path.cubicTo(C1.x, C1.y, C2.x, C2.y, P2.x, P2.y)
首尾用复制点补齐虚拟 P0/P3。
```

- 效果：锯齿/转角尖锐基本消失，线条 C¹ 连续。
- 成本：~20 行 Dart，无新依赖。
- 参考：姊妹工程 `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart:110-128` 的 `_buildBezierPath`。
- 局限：仍是等宽 stroke，没有压感粗细变化。但已经能消除用户反馈的"锯齿/尖锐转角"。

### 路线 B：主目标 —— 接入 perfect-freehand 做变宽轮廓（推荐）

1. `pubspec.yaml` 加 `perfect_freehand: ^2.5.0`（或纯 Dart 的 `freehand` port，避免 JS 引擎依赖）。
2. 渲染端：`getStroke(points, options)` → 外轮廓点 → `canvas.drawPath(..., PaintingStyle.fill)`。
3. 压感通道：把已采集但被忽略的 `StrokePoint.pressure`（`models/stroke_point.dart:33-38`）接进来；手指/普通笔置 `simulatePressure: true`。
4. 参考实现：`FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart:67-105`（`getStroke` + fill）和 `.../tools/freedraw_tool.dart:68-88`（压感/速度模拟切换）。

- 效果：与 GoodNotes/tldraw 同档观感，有粗细变化和笔锋。
- 成本：中等。需把 `StrokePoint` 序列适配成 perfect-freehand 的 `[x, y, pressure]` 格式。
- 注意：实时性需验证（设计文档 Risk #7，`design-v2.md:366`）。高频点流下 `getStroke` 若跟不上帧率，可用"增量重算最后 N 段 + 抬笔后整体重算"策略，或退回路线 A 作为实时降级。

### 路线 C：专业级 —— 补齐 L2 预处理 + 可调稳定度

在 A/B 之上再加：

- **轻量滑动平均**（3–5 点窗口）或 EMA，前置去抖。
- **RDP 抽稀**，去掉几乎共线的冗余点，降低曲线段数。
- **暴露"稳定度"滑块**给用户（仿 GoodNotes/Procreate），背后调 perfect-freehand 的 `streamline` / `smoothing`。
- **抬笔后重算**：书写中用轻量曲线（路线 A）保实时；抬笔后用完整 perfect-freehand 重渲染整笔，兼顾实时性与最终质量。

---

## 六、实施前需验证的点（风险）

| 风险 | 来源 | 建议 |
| --- | --- | --- |
| perfect-freehand 实时性 | `design-v2.md:366` Risk #7 | 真机测帧率；不行则用路线 A 实时 + 路线 B 抬笔重算 |
| 压感 `force` 真机范围未知 | `design-v2.md:354` Risk #1 | 真机打印 `pressure` 分布，定标到 perfect-freehand 期望的 0–1 |
| 采样密度是否够画平滑曲线 | 同上 | L1 已用历史点 + 预测点，密度应够；曲线拟合后若仍发卡，再排查采样 |
| `perfect_freehand` 是否兼容 Flutter OHOS | pub.dev 包为纯 Dart 或带 JS | 优先选纯 Dart 的 `freehand` port，避免 OHOS 上 JS 引擎问题 |
| 预测点导致"末端跳变" | 报点预测特性 | 抬笔时丢弃最后 1–2 个预测点，或用真实点覆盖回弹 |

---

## 七、附：姊妹工程 FlowMuse-App 已实现清单（可直接参考/移植）

| 能力 | 文件 |
| --- | --- |
| perfect-freehand 渲染（getStroke + fill） | `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart:67-105` |
| Catmull-Rom → 贝塞尔兜底 | 同文件 `:110-128`（`_buildBezierPath`） |
| 压感 / 速度模拟切换 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart:12-14, 68-88` |
| 压感灵敏度 → thinning 映射 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart:712-714, 717-734` |
| 依赖声明 | `FlowMuse-App/pubspec.yaml:56`（`perfect_freehand: ^2.5.0`） |

> 结论：本项目要解决"线条锯齿、转角尖锐"，技术上**不需要从零探索**——既有成熟开源算法（perfect-freehand），又有同仓库内可直接移植的 Dart 实现。最小代价（路线 A）当天可见效，主目标（路线 B）有完整参考代码。
