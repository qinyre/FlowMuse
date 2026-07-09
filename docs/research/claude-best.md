# 笔迹线条平滑 — 三份调研综合最优方案

> 综合：[claude-research.md](claude-research.md)、[codex-research.md](codex-research.md)、[zcode-research.md](zcode-research.md)
> 产出日期：2026-07-09
> 目标：去重取精，输出可直接执行的单一最优路线

---

## 1. 三份调研共识

| 共识点 | claude | codex | zcode |
|--------|:---:|:---:|:---:|
| perfect_freehand 方向正确，继续用 | ✓ | ✓ | ✓ |
| 当前 smoothing/streamline=0.5 偏低 | ✓ | ✓ | ✓ |
| 加 OneEuro 速度自适应滤波替代固定 EMA | ✓ | ✓ | ✓（隐含在 L2） |
| 需要 RDP 或等价点简化 | ✓ | — | ✓ |
| 鸿蒙原生 Pen Kit 预测只改善延迟，不解决锯齿 | ✓ | ✓ | — |
| 需要湿墨/干墨分层 | — | ✓ | — |

---

## 2. 三份调研关键差异

| 维度 | claude | codex | zcode |
|------|--------|-------|-------|
| **主要关注点** | FlowMuse-App FreedrawRenderer | FlowMuse-App FreedrawRenderer | spike_canvas.dart（另一个画布） |
| **P0 定位** | 调参数 | **修复 `addPolygon` 渲染方式** | Catmull-Rom 替代 lineTo |
| **对 perfect_freehand 的使用评价** | 集成正确，仅需调参 | **集成有 bug**：轮廓用折线渲染 | 未使用（在 spike 画布上） |
| **深度** | 算法横向对比全面 | 管线诊断最深入 | 算法原理 + 姊妹工程参考最完整 |

---

## 3. codex 发现的致命问题（claude/zcode 均遗漏）

`FreedrawRenderer.draw()` 当前代码：

```dart
final path = Path()..addPolygon(outline, true);  // ← 直线段连接所有轮廓顶点
canvas.drawPath(path, paint);
```

`perfect_freehand.getStroke()` 返回的是外轮廓的**离散采样顶点**。`addPolygon` 把这些顶点用**直线段**逐一连接。即使 `perfect_freehand` 内部中心线已经是 C¹ 连续的，最终渲染的边缘仍然是折线。**视觉锯齿不是来自算法不够平滑，而是来自渲染阶段把连续轮廓又离散化了。**

`perfect_freehand` 官方 README 的渲染方式是用**相邻轮廓点的中点作为二次贝塞尔曲线终点**：

```
从第一个轮廓点开始
→ 以轮廓点 P[i] 作为控制点
→ 以 P[i] 和 P[i+1] 的中点作为曲线终点
→ quadraticBezierTo(控制点, 中点)
→ 闭合后 fill
```

这与 `addPolygon` 有实质差异，是锯齿的首要来源。

---

## 4. 最优方案

### 三阶段，严格按顺序执行（每阶段验证后再进下一阶段）

---

### 阶段 1：修复轮廓渲染（P0，1–2 小时）

**改什么**：`FreedrawRenderer.draw()` 中把 `addPolygon` 换成 quadratic Bézier 中点路径。

**为什么优先**：
- 三个调研一致认为当前最大的锯齿来源是渲染方式
- 不改变任何输入处理逻辑，不改参数，不改数据结构
- 改动范围极小（~15 行），可以直接 A/B 对比同一条笔迹的前后效果

**怎么验证**：
- 同一组真机笔迹，录屏对比 polygon 与 quadratic outline
- 检查慢速斜线、快速 S 曲线、小字号汉字
- 验证鸿蒙 + 手写笔、Android + 手指、鼠标三场景

**参考代码**：`perfect_freehand` 官方 README 示例

---

### 阶段 2：输入滤波升级（P1，3–5 小时）

**改什么**：
1. `HarmonyStylusStrokeSmoother` 的固定 EMA（alpha=0.35）替换为 **OneEuro Filter**（X/Y 各自独立滤波）
2. 给压力值单独加轻量 EMA（alpha=0.45），不与位置共用参数
3. 在 `up()` 时强制 flush 到真实终点

**为什么在阶段 1 之后**：
- 阶段 1 修复的是"输出端"的直线连接问题，阶段 2 修复的是"输入端"的噪声问题
- 必须先确认输出端正确，再调输入端——否则调参时无法判断改善来自渲染还是滤波
- OneEuro 需要时间戳，需先在 `FreedrawElement` 或工具层补上 timestamp 字段

**关键细节**（来自 codex）：
- 压力独立滤波，不要用位置滤波参数套到压力上
- 方向突变保护：转角时临时提高截止频率，避免把折笔误抹平
- 保留原始点、派生平滑点，不覆盖原始输入（方便后续重算）

**参考代码**：claude-research 中的 `OneEuroFilter` Dart 实现（~80 行）

---

### 阶段 3：参数调优 + 湿墨/干墨分层（P2，3–5 小时）

**改什么**：
1. `smoothing` 0.5 → 0.8，`streamline` 0.5 → 0.7
2. 湿墨（书写中）：`isComplete: false`，允许增量重算最近一段
3. 干墨（抬笔后）：`isComplete: true`，用真实点全量重算最终几何
4. 协同同步：只发送真实输入或稳定干墨，不发送预测点

**为什么在最后**：
- 参数调优效果依赖前两阶段正确——如果轮廓还在折线渲染，调平滑参数只能掩盖问题
- 湿墨/干墨分层涉及数据流改动（同步协议、预览状态），复杂度最高
- 阶段 1+2 已经能解决 90% 的视觉问题，阶段 3 是品质天花板

---

## 5. 为什么不优先做的

| 方案 | 原因 |
|------|------|
| **直接调高 smoothing** | 当前 `addPolygon` 折线渲染会把任何平滑效果吃掉；必须先修渲染方式再调参 |
| **只把 positionAlpha 从 0.35 调得更小** | 静态抖动可能减少，但延迟和急转角更差（codex 警告） |
| **Catmull-Rom 替代 perfect_freehand** | perfect_freehand 本身已内置 Catmull-Rom 平滑中心线，问题在渲染端不在算法选择 |
| **RDP 点简化** | 有用但非紧急；阶段 1+2 之后如果密度仍然过高再加 |
| **Google Ink Stroke Modeler** | 工业级方案但 FFI 成本高；完成阶段 1-3 后再评估是否值得 |
| **鸿蒙原生 Pen Kit 画布** | 引入双引擎同步复杂度，收益无法归因；阶段 1-3 稳定后再评估 |

---

## 6. 验收标准

每个阶段完成后，在同一台鸿蒙平板、同一缩放、同一笔宽下验证：

| 样本 | 检查什么 |
|------|----------|
| 极慢水平线、斜线 | 低速抖动和轮廓锯齿 |
| 快速水平线、斜线 | 跟手性和滞后 |
| 大圆、小圆、连续 8 字 | 曲率连续性 |
| L、V、Z 折线 | 转角保真（不能过度圆滑也不能拉尖） |
| 汉字"永""我""流" | 横竖撇捺、折笔和小尺度细节 |
| 压力由轻到重再到轻 | 宽度连续性 |
| 快速抬笔 | 尾点是否到达、端帽是否跳变 |

---

## 7. 参考资料

| 资源 | 链接 |
|------|------|
| perfect_freehand 官方仓库及渲染示例 | https://github.com/steveruizok/perfect-freehand |
| OneEuro Filter 论文 | Casiez et al., CHI 2012 — DOI: 10.1145/2207676.2208639 |
| Google Ink Stroke Modeler | https://github.com/google/ink-stroke-modeler |
| Apple PencilKit PKStrokePath | https://developer.apple.com/documentation/pencilkit/pkstrokepathreference |
| Microsoft InkPresenter | https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkpresenter |
| Android Ink API | https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules |
| HarmonyOS Pen Kit | https://developer.huawei.com/consumer/cn/sdk/pen-kit |
| 姊妹工程参考实现 | `FlowMuse-App/.../freedraw_renderer.dart` `FlowMuse-App/.../freedraw_tool.dart` |
