# 手写线条平滑技术调研报告

> 调研日期：2026-07-09
> 目的：分析成熟办公书写产品的线条渲染技术，为改善本项目书写线条的锯齿和尖锐转角问题提供参考

---

## 1. 当前项目现状

### 1.1 渲染管线

```
触控/鼠标事件 → FreedrawElement(原始点序列) → FreedrawRenderer → Canvas
                                                    ↓
                                            perfect_freehand.getStroke()
                                                    ↓
                                            闭合多边形轮廓 → fill 绘制
```

### 1.2 使用参数

| 参数 | 当前值 | 范围 | 作用 |
|------|--------|------|------|
| `smoothing` | 0.5 | 0–1 | 输入点平滑程度 |
| `streamline` | 0.5 | 0–1 | 预测/跟手延迟平衡 |
| `thinning` | 0.5（无压感默认） | 0–1 | 宽度随速度/压力的变化程度 |
| `simulatePressure` | 无压感时 true | — | 用速度模拟笔压 |
| `isComplete` | true | — | 笔尾自动收尖 |

### 1.3 现有不足

1. **无输入预处理**：原始触控点直接喂入 `getStroke()`，没有做抖动消除和冗余点简化
2. **smoothing 参数偏低**：0.5 的默认值偏向"精确跟随"，手抖和锯齿被保留
3. **streamline 未针对书写优化**：0.5 的预测不足以消除慢速书写时的自然抖动
4. **无 RDP 简化步骤**：密集采样点的微小抖动被 `getStroke()` 多边形化后体现为锯齿边
5. **仅鸿蒙+手写笔有 EMA 前置平滑**：`HarmonyStylusStrokeSmoother`（alpha=0.35），其他平台完全没有

---

## 2. 技术方案横向对比

### 2.1 总览

| 维度 | OneEuro Filter | Google Ink Stroke Modeler | RDP + Catmull-Rom | Quadratic Bézier 中点法 | 调高 perfect_freehand 参数 |
|------|:---:|:---:|:---:|:---:|:---:|
| **解决抖动** | ★★★★★ | ★★★★★ | ★★☆（间接） | ★☆☆ | ★★★☆ |
| **转角平滑** | ★★★☆ | ★★★★★ | ★★★★ | ★★★ | ★★★★ |
| **宽度变化** | — | ★★★★（样式插值） | — | — | ★★★★（内置） |
| **跟手延迟** | 极低 | 低（Kalman 预测补偿） | 零 | 零 | 略有增加 |
| **算法复杂度** | O(1) | O(n) + ODE 积分 | O(n log n) (RDP) + O(n) | O(n) | 已集成，零开发 |
| **实现难度** | 低（~80行 Dart） | 高（C++ FFI） | 低（~50行 Dart） | 极低（~15行 Dart） | 极低（改两个数） |
| **适用场景** | 实时书写前置滤波 | 专业书写/绘画产品 | 通用曲线平滑 | 简单涂鸦 | 当前项目最速改善 |
| **本项目集成方式** | `FreedrawTool` 收集点之前 | 替换 `perfect_freehand` | 替换 Catmull-Rom 段 | 替换 Catmull-Rom 段 | 改 `StrokeOptions` 参数 |

### 2.2 各方案核心思路

| 方案 | 一句话 | 什么时候用 |
|------|--------|------------|
| **调参数** | perfect_freehand 的 smoothing/streamline 从 0.5 调到 0.8/0.7 | 立刻见效，零风险 |
| **OneEuro** | 速度自适应低通滤波：慢写时强滤波去抖，快写时弱滤波跟手 | 手抖/锯齿是主要问题时 |
| **RDP + Catmull-Rom** | 先简化掉冗余抖动点，再用样条通过剩余关键点生成曲线 | 采样率高但噪声多时 |
| **Quad Bézier 中点法** | 不连原始点，连原始点之间的中点，以原始点为控制点 | 需要最简实现时 |
| **Google Ink** | 把笔尖当物理弹簧-质量-阻尼系统模拟，天生平滑 | 需要工业级品质时 |

### 2.3 延迟与平滑的权衡

```
平滑度 ↑
        │  Google Ink (Kalman 预测)
        │  ╱
        │ OneEuro (速度自适应)
        │╱
        │  perfect_freehand (调参后)
        │
        │  perfect_freehand (默认)  ← 本项目当前
        │
        │  RDP+Catmull-Rom
        │
        │  Quad Bézier 中点法
        │
        └──────────────────────→ 跟手延迟
```

- **右上区域**：平滑 + 低延迟（理想方向），如 Google Ink（物理建模+预测补偿）
- **左下区域**：简单直接但有锯齿，如 Quad Bézier 中点法
- **本项目当前**：偏左下，需要向右上移动

---

## 3. 关键技术详解

### 3.1 OneEuro Filter（1欧元滤波器）

**论文**：Casiez et al., CHI 2012 — *"One Euro Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems"*

**核心思路**：截止频率随速度动态调整，低速强滤波、高速弱滤波，同时解决手抖和延迟两个矛盾需求。

| 状态 | 截止频率 | 效果 |
|------|----------|------|
| 低速/静止 | 降低 → 趋近 `minCutoff` | 强滤波，大幅抑制手抖 |
| 高速移动 | 自动升高 | 弱滤波，几乎无延迟跟手 |

**参数**：

| 参数 | 含义 | 推荐值 | 调大→更平滑 | 调小→更跟手 |
|------|------|--------|:---:|:---:|
| `minCutoff` | 最小截止频率 | 1.0 Hz | ✓ | |
| `beta` | 速度自适应灵敏度 | 0.007 | | ✓ |
| `dCutoff` | 导数（速度）截止频率 | 1.0 Hz | 通常不动 | 通常不动 |

**Dart 参考实现**（~80 行，零依赖）：

```dart
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  final double minCutoff, beta, dCutoff;
  double _prevX = 0, _prevDx = 0;
  double? _prevT;

  double filter(double x, double t) {
    if (_prevT == null) { _prevX = x; _prevT = t; return x; }

    final dt = t - _prevT!;
    final dx = (x - _prevX) / dt;
    final dxHat = _lowPass(dx, _prevDx, dt, dCutoff);
    final cutoff = minCutoff + beta * dxHat.abs();
    final xHat = _lowPass(x, _prevX, dt, cutoff);

    _prevX = xHat; _prevDx = dxHat; _prevT = t;
    return xHat;
  }

  double _lowPass(double x, double prev, double dt, double cutoff) {
    final alpha = (2 * 3.1415926535 * cutoff * dt);
    return prev + (alpha / (alpha + 1)) * (x - prev);
  }
}
```

**在本项目中的集成点**：`FreedrawTool` 接收原始点之前，作为前置滤波器。对 X、Y 坐标分别滤波。

---

### 3.2 Google Ink Stroke Modeler

**仓库**：[github.com/google/ink-stroke-modeler](https://github.com/google/ink-stroke-modeler)
**语言**：C++（最小依赖：C++ Standard Library + Abseil）

**核心思路**：把笔尖当成一个有质量、连在弹簧上、受阻尼的物理小球来模拟——物理系统天生产生平滑轨迹。

**三级管线**：

| 阶段 | 组件 | 做什么 |
|------|------|--------|
| 1 | `WobbleSmoother` | 速度自适应移动平均，消除高频量化噪声 |
| 2 | `PositionModeler` | **核心**：弹簧-质量-阻尼 ODE 模拟笔尖运动 |
| 3 | `StylusStateModeler` | 把压力/倾斜/方向沿平滑路径重采样 |

**物理弹簧模型**（核心公式）：

```
d²s/dt² = (Φ(t) - s(t)) / M - k_d · ds/dt

s(t)   = 笔尖位置（模型输出）
Φ(t)   = 锚点位置（原始输入重采样后）
M      = 质量/弹簧常数比（≈ 0.00034）
k_d    = 阻尼常数（≈ 72.0）
```

- **弹簧力** `(Φ - s) / M`：把笔尖拉向原始输入位置
- **阻尼力** `k_d · ds/dt`：阻止笔尖运动过快
- 净效果：笔尖平滑地"追着"原始输入走

因为物理惯性，笔尖天然落后于原始输入 → 用 **Kalman 滤波器预测** 来补偿这个延迟。

**设计哲学**（官方原话）："优先产生平滑好看的曲线，而不是精确重现输入。"

**关键参数**：spring_mass_constant ≈ 0.00034, drag_constant = 72.0, 输出上采样至 180Hz。

**在本项目中的位置**：如果集成，将替换 `FreedrawRenderer` 中的 `perfect_freehand`，作为核心引擎。需通过 `dart:ffi` 调用 C++。

---

### 3.3 Ramer-Douglas-Peucker (RDP) + Catmull-Rom 管道

**核心思路**：两步走——先删掉"没用"的冗余点（RDP），再用样条曲线通过剩余关键点（Catmull-Rom）。

| 步骤 | 算法 | 干什么 | 怎么调 |
|------|------|--------|--------|
| 1. 简化 | RDP (ε 参数) | 移除共线/冗余点，保留拐点 | ε 越大删越多 |
| 2. 平滑插值 | Catmull-Rom → Cubic Bézier | 通过剩余点生成光滑曲线 | tension α 控制转角锐度 |

**RDP ε 参数指南**：

| ε | 效果 | 适用 |
|----|------|------|
| 0.5–1.0 | 轻度，保留细节 | 精细书写 |
| 1.0–2.0 | 中度 | 一般手写 |
| 2.0–5.0 | 强力 | 快速草图 |

**Catmull-Rom tension α**：

| α | 类型 | 转角 |
|---|------|------|
| 0 | uniform | 偏锐 |
| 0.5 | centripetal | 最自然 |
| 1 | chordal | 偏圆 |

**优势**：两步职责清晰，各自独立调参；代码量小。

**局限**：RDP 只删点不产生新点，曲线段之间的连续性不如物理模型方案。且无宽度变化能力，需额外叠加宽度引擎。

---

### 3.4 Quadratic Bézier 中点法

**核心思路**：不直接连线，而是连相邻原始点的中点，用原始点做控制点。

```
原始点 P0, P1, P2
  → 中点 M01 = (P0+P1)/2, M12 = (P1+P2)/2
  → quadraticBezierTo(控制点=P1, 终点=M12)
```

**优势**：实现最简单，~15 行代码。
**劣势**：只是让折线"看起来像曲线"，对真正的抖动和锯齿几乎无能为力，转角处仍有细微折痕。

---

### 3.5 perfect_freehand 参数调优

本项目已使用 `perfect_freehand`，内部三步：

**Step 1 — smoothing**：对点序列做高斯平滑，值越大曲线越圆滑，但延迟也越大。

**Step 2 — streamline**："前瞻预测"，使笔锋向前延伸。值越大笔锋越主动，能补偿 smoothing 带来的延迟，但转弯处可能漂移。

**Step 3 — thinning**：控制宽度变化幅度。值越大粗细变化越明显。

**当前 vs 书写推荐**：

| 参数 | 当前（默认） | 书写推荐 | 变化 | 效果预期 |
|------|:---:|:---:|:---:|------|
| `smoothing` | 0.5 | **0.8** | +60% | 大幅降低锯齿抖动 |
| `streamline` | 0.5 | **0.7** | +40% | 转角过渡更柔和，补偿平滑延迟 |
| `thinning` | 0.5 | **0.3–0.5** | 不变或略降 | 书写线条不宜粗细变化过大 |

---

## 4. 锯齿与尖锐转角的根因分析

### 4.1 锯齿来源

```
触控采样 (120Hz) → 原始点序列含 ±2px 抖动
        ↓
无预处理直接入 perfect_freehand
        ↓
smoothing=0.5 保留了约一半的抖动幅度
        ↓
getStroke() 将抖动转化为多边形轮廓的微小波动
        ↓
→ 视觉上的锯齿感
```

### 4.2 尖锐转角来源

```
快速转弯 → 采样点分布极不均匀（弯内侧密，外侧稀）
        ↓
streamline=0.5 预测不足 → 曲线紧贴稀疏采样点
        ↓
弯内侧曲率被迫过大 → 不自然的锐角
        ↓
→ 视觉上的尖锐转角
```

### 4.3 方案优先级

| 优先级 | 方案 | 解决什么 | 效果预期 | 工作量 |
|:---:|------|------|:---:|:---:|
| **P0** | 调高 smoothing + streamline | 锯齿 + 转角 | 改善 60% | 改两行 |
| **P1** | 加 OneEuro 前置滤波 | 抖动 | 消除 90% | ~80 行 Dart |
| **P2** | 加 RDP 简化 | 冗余点 + 间接改善转角 | 改善 20% + 性能 | ~50 行 Dart |
| **P3** | Catmull-Rom 加 tension | 转角可控 | 改善 15% | 已有代码改参数 |
| **P4** | 集成 Google Ink | 全部 | 工业级 | C++ FFI（大） |

---

## 5. 推荐渐进路线

### 阶段 A：立刻（改两行）

```dart
// freedraw_renderer.dart — StrokeOptions
smoothing: 0.8,     // 0.5 → 0.8
streamline: 0.7,    // 0.5 → 0.7
```

### 阶段 B：短期（加 OneEuro 前置滤波）

在 `FreedrawTool` 收集点之前，X/Y 坐标各自通过 `OneEuroFilter`，消除触控抖动后再喂给 perfect_freehand。

### 阶段 C：中期（加 RDP 简化）

在 OneEuro 之后、perfect_freehand 之前，加一层 RDP 点简化，减少冗余采样点，使曲线更"干净"，也给后续处理减负。

### 阶段 D：长期（可选）

通过 FFI 集成 Google Ink Stroke Modeler，获得物理建模级别的平滑和 Kalman 预测补偿。

---

## 6. 参考资料

| 资源 | 链接 |
|------|------|
| Google Ink Stroke Modeler | https://github.com/google/ink-stroke-modeler |
| OneEuro Filter 论文 | Casiez et al., CHI 2012 — DOI: 10.1145/2207676.2208639 |
| perfect_freehand (tldraw/Excalidraw) | https://pub.dev/packages/perfect_freehand |
| @stroke-stabilizer (JS 平滑库) | https://www.npmjs.com/package/@stroke-stabilizer/core |
| Wacom WILL SDK | https://developer-docs.wacom.com/docs/sdk-for-ink/WILL2/ |
| Samsung 手写增强 (IEEE 2024) | https://ieeexplore.ieee.org/document/10552742 |
