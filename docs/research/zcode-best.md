# 笔迹平滑最优方案（GLM-Best）：三份调研的整合结论

日期：2026-07-09
整合来源：`codex-research.md`、`claude-research.md`、`zcode-research.md`（同目录）
分析对象：**生产 App `FlowMuse-App`**（`2024-se-17-markdraw-probe/FlowMuse-App/`）

> ⚠️ **关于分析对象的更正**：此前的 `zcode-research.md` 把根因定位到了 spike 原型 `2024-se-17/lib/.../spike_canvas.dart` 的 `lineTo` 折线。那是早期可行性验证原型，不是生产代码。**生产 App（FlowMuse-App）已经在用 `perfect_freehand` 做变宽轮廓渲染**，所以问题不是"没有平滑算法"，而是"已有的平滑管线存在具体缺陷"。本最优方案以生产 App 为准重新定位根因，所有 `file:line` 引用均指向 FlowMuse-App。

---

## 结论先行（TL;DR）

1. **生产 App 已经用了 perfect-freehand，方向正确**。锯齿/尖锐转角是管线里**三处具体缺陷**叠加的结果，不是缺算法。

2. **三份文档合起来看，问题被精确定位到 4 个根因，按严重程度排序**：

   | 排序 | 根因 | 谁发现的 | 源码位置（已核实） |
   |---|---|---|---|
   | **P0** | outline 用 `addPolygon` **直线段**渲染，把平滑后的轮廓顶点又变回多边形折线 | codex（独有，且最关键） | `freedraw_renderer.dart:103` |
   | **P1** | 鸿蒙侧固定 EMA `positionAlpha=0.35`，无时间戳/速度/曲率自适应 | codex | `harmony_stylus_stroke_smoother.dart:22,136-139` |
   | **P1** | `up()` 只把最后一点平滑 35% 就 reset，笔迹**到不了真实终点** | codex（独有） | `harmony_stylus_stroke_smoother.dart:96-98` |
   | **P1** | 实时与最终笔迹都固定 `isComplete=true`，新增点时尾部形态跳变 | codex | `freedraw_renderer.dart:89` |

3. **修正顺序的依据**：`claude-research.md` 把"调高 smoothing/streamline 参数"列为 P0，但**那只对"完全没做平滑"的原型有效**；生产 App 已经在 perfect-freehand 内部做了平滑，P0 的真正瓶颈是**轮廓渲染方式**（addPolygon 把平滑成果浪费了）。所以最优方案采用 **codex 的排序**：先修渲染，再修滤波，最后做湿/干墨分层。

4. **claude 和 zcode 的贡献作为补充手段**：OneEuro Filter（替代固定 EMA）、RDP 抽稀、Google Ink Modeler（工业级备选）、四层理论框架（L1–L4）、Catmull-Rom→贝塞尔公式、FlowMuse 参考代码清单——这些都是有效的工程弹药，但应用在 P0/P1 修好之后。

5. **最佳落地路径（4 阶段，按性价比排序）**：
   - **阶段 1（P0，最高优先）**：把 outline 的 `addPolygon` 换成**二次贝塞尔中点法**（官方 recommended 渲染方式），~15 行代码。
   - **阶段 2（P1）**：固定 EMA → **OneEuro Filter**（速度自适应）；`up()` 强制收敛到真实终点；实时用 `isComplete=false`。
   - **阶段 3（P2）**：建立**湿墨/干墨双阶段** + RDP 抽稀 + 量化验收样本。
   - **阶段 4（可选）**：HarmonyOS 原生报点预测接入湿墨层；或 FFI 集成 Google Ink Modeler 达到工业级。

---

## 一、为什么三份文档结论不完全一致：分析方法论对比

三份文档的差异，本质是**分析对象和切入点不同**。下表先厘清，避免混淆。

| 维度 | codex | claude | zcode |
|---|---|---|---|
| **分析对象** | 生产 App（FlowMuse-App）源码 | 生产 App 现状 + 算法横向对比 | ~~spike 原型~~（定位错误） |
| **核心方法** | 源码逐行静态分析 + 平台架构对照 | 算法横向打分矩阵 + 渐进路线 | 行业产品调研 + 四层理论框架 |
| **根因诊断** | 4 个具体代码缺陷（P0/P1） | 参数偏低 + 缺前置滤波 | ~~lineTo 折线~~（适用于原型，不适用于生产 App） |
| **P0 建议** | 修 `addPolygon` 渲染 | 调高 smoothing/streamline | 引入 perfect-freehand |
| **独特贡献** | 湿/干墨分层、验收样本、资料解读边界 | OneEuro 完整 Dart 实现、Google Ink 物理模型详解、延迟-平滑权衡图 | 四层 L1–L4 模型、Catmull-Rom 公式、FlowMuse 参考清单 |
| **对生产 App 的适用度** | ★★★★★（直接对症） | ★★★★（手段有用，排序需调整） | ★★★（理论框架有用，根因定位需更正） |

**整合原则**：以 codex 的**源码级根因诊断和修正排序**为主干（因为它直接命中生产 App 的真实缺陷），把 claude 的**具体算法实现**（OneEuro/Google Ink）和 zcode 的**理论框架与参考代码**作为血肉填进去。

---

## 二、生产 App 的正确根因诊断（已逐行核实源码）

> 下面每条都标注了 FlowMuse-App 的 `file:line`，并标注"已核实"。

### 2.1 渲染管线现状

```
鸿蒙手写笔/触控事件
    ↓
HarmonyStylusStrokeSmoother（仅鸿蒙+stylus+freedraw）   ← P1：固定 EMA
    ↓  smoothedPoint = last + (raw - last) * 0.35
FreedrawElement（points + pressures）                    ← P2：缺 timestamp
    ↓
FreedrawRenderer.draw()
    ↓  getStroke(points, options)   ← perfect-freehand，内部已平滑
outline 点数组
    ↓  Path()..addPolygon(outline, true)   ← P0：直线段！
canvas.drawPath(path, fillPaint)
```

关键矛盾：**perfect-freehand 内部已经做了 spline 平滑并输出了密集的轮廓点，但 `addPolygon` 又把这些点用直线段连起来**，等于把平滑成果在最后一步浪费掉。

### 2.2 根因 P0：轮廓被当作折线多边形渲染（最高优先级）

源码 `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart:103`（已核实）：

```dart
final path = Path()..addPolygon(outline, true);
final paint = style.toStrokePaint()..style = PaintingStyle.fill;
canvas.drawPath(path, paint);
```

`addPolygon` 用**直线段**连接每个离散 outline 顶点。即使中心线已被 perfect-freehand 平滑，最终边缘仍是多段直线；采样稀疏、宽度变化或急转时，锯齿和尖角最为明显。

**这是 codex 最有价值的独到发现**，claude 和 zcode 都没有抓到——因为它们没有逐行看渲染代码。`claude-research.md` 的"调高 smoothing 到 0.8"对这个 bug **完全无效**：smoothing 调得再高，outline 顶点之间仍然是直线。

**官方正确做法**（perfect-freehand README 渲染示例）：以 outline 点为控制点、以相邻 outline 点的中点为二次贝塞尔终点，构造连续曲线闭合路径。

### 2.3 根因 P1-a：固定 EMA 不适应书写速度

源码 `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/harmony_stylus_stroke_smoother.dart:22,136-139`（已核实）：

```dart
this.positionAlpha = 0.35,          // 固定系数
...
final smoothedPoint = Point(
  lastPoint.x + (point.x - lastPoint.x) * positionAlpha,
  lastPoint.y + (point.y - lastPoint.y) * positionAlpha,
);
```

固定 EMA 的固有矛盾（codex §3.2、claude §3.1 都指出）：
- 系数小：慢速稳，但快速书写**滞后明显**；
- 系数大：快速跟手，但慢速**抖动保留**；
- 急转弯：可能**切掉转角**或形成追赶曲线。

而且这个 EMA **没有时间戳**——只能按"事件个数"滤波，不同设备采样率下表现不一致。这是 `claude-research.md` 推 OneEuro Filter 的对症场景（OneEuro 正是"速度自适应低通"，解决慢写去抖 vs 快写跟手的矛盾）。

### 2.4 根因 P1-b：抬笔点到不了真实终点

源码 `harmony_stylus_stroke_smoother.dart:96-98`（已核实）：

```dart
final sample = _emitSmoothed(point: point, pressure: pressure);  // 只移动 35%
reset();  // 立即重置
return sample;
```

`up()` 仍调用同一个 35% EMA，然后立即 reset。如果最后一个 move 与 up 相距较远，最终笔迹会**停在真实终点之前**，或尾部方向不自然。成熟做法是抬笔时强制收敛到真实终点，再由笔刷 taper/cap 控制视觉收尾。

### 2.5 根因 P1-c：实时与最终用同一份完成态几何

源码 `freedraw_renderer.dart:89`（已核实）：

```dart
isComplete: true,   // 固定，无论是否在书写中
```

进行中笔迹（湿墨）和完成笔迹（干墨）应使用不同完成状态。当前固定 `isComplete=true`，导致每次新增点时尾部端帽被当作最终形态处理，出现**尾部形态跳变**。

### 2.6 根因 P2：缺 timestamp 和质量指标（次要）

- `FreedrawElement` 只存 points + pressures，**没有 timestamp**（codex §4.2 P2）。无法做采样率无关的速度滤波、可靠预测或按时间回放。
- 没有自动化质量指标（codex §4.2 P2、claude §4 间接提及），只靠"看起来更顺"会导致参数反复摆动。

---

## 三、整合后的最优技术方案（4 阶段）

### 阶段 1：修正轮廓渲染方式（P0，最高优先级，~15 行代码）

**目标**：用最小改动验证锯齿是否主要来自 `addPolygon`。这是**收益最高、风险最低**的一步，只改渲染方式，不通过更强滤波改变用户字形。

把 `freedraw_renderer.dart:103` 的：

```dart
final path = Path()..addPolygon(outline, true);
```

改成 perfect-freehand 官方推荐的**二次贝塞尔中点法**：

```dart
Path _buildOutlinePath(List<PointVector> outline) {
  if (outline.length < 3) {
    return Path()..addPolygon(outline, true); // 点太少时兜底
  }
  final path = Path();
  // 从前两个点的中点起笔
  path.moveTo(
    (outline[0].x + outline[1].x) / 2,
    (outline[0].y + outline[1].y) / 2,
  );
  // 以每个 outline 点为控制点，到下一点的中点画二次贝塞尔
  for (var i = 1; i < outline.length - 1; i++) {
    final midX = (outline[i].x + outline[i + 1].x) / 2;
    final midY = (outline[i].y + outline[i + 1].y) / 2;
    path.quadraticBezierTo(outline[i].x, outline[i].y, midX, midY);
  }
  path.close();
  return path;
}
```

**验收**：用同一组真机笔迹对比 polygon 与 quadratic outline，重点看小字号汉字、圆、慢速斜线、快速 S 曲线（验收样本见阶段 3）。

> 这一步同时印证了 `claude-research.md` §2.1 里"Quad Bézier 中点法"的价值——它单独用价值有限，但**用在 outline 渲染这一步**正好对症。

### 阶段 2：速度自适应滤波 + 抬笔收敛（P1）

#### 2.1 固定 EMA → OneEuro Filter

采用 `claude-research.md` §3.1 的 OneEuro Filter（CHI 2012 论文，~80 行 Dart，零依赖），替换 `HarmonyStylusStrokeSmoother` 的固定 EMA。理由：
- **低速强滤波、高速弱滤波**，同时解决手抖和延迟两个矛盾（codex §3.2 的诉求）；
- O(1) 复杂度，逐点实时处理，适合高频点流；
- 需要 timestamp，倒逼补上 P2 的 timestamp 字段。

OneEuro 关键参数（claude §3.1）：
- `minCutoff = 1.0`（调大→更平滑）、`beta = 0.007`（调大→更跟手）、`dCutoff = 1.0`。

**转角保护**（codex §3.2 强调）：方向突变时临时提高响应速度，避免把汉字折笔/尖角误当噪声抹平。

位置和压力用**独立参数**分别滤波（codex §3.1、claude 同步）。

#### 2.2 `up()` 强制收敛到真实终点

改 `harmony_stylus_stroke_smoother.dart:96-98`：`up()` 时**直接用真实终点**（或 flush 若干步快速收敛），再做 taper/cap 视觉收尾，而不是只走 35% 就 reset。

#### 2.3 实时用 `isComplete=false`，抬笔后切 true

改 `freedraw_renderer.dart:89`：书写中传 `isComplete=false`（避免尾部端帽跳变），抬笔后用 `isComplete=true` 重渲整笔。这自然引出阶段 3 的湿/干墨分层。

> **关键约束（codex §5 第二阶段）**：只改鸿蒙 stylus + freedraw 路径，保证非 HarmonyOS、touch、mouse 路径完全不变。不建议只把 `positionAlpha` 从 0.35 调更小——那能减静态抖动，但会恶化延迟和急转角。

### 阶段 3：湿墨/干墨双阶段 + RDP + 量化验收（P2）

#### 3.1 湿/干墨分层（codex §3.5、§5 第三阶段）

成熟产品把"看起来跟手"和"最终形状正确"分开（Windows Ink、Android Ink 官方架构一致）：

```
真实输入 → 清洗/OneEuro → 湿墨几何(isComplete=false) ──┐
                   └→ 预测点(临时) ──────────────────────┴→ 屏幕临时层

真实输入 → 最终平滑/曲线/笔刷 → 干墨几何(isComplete=true) → 文档/同步/导出
```

- **湿墨**：增量处理最近一小段，允许临时预测尾，保实时性；
- **干墨**：抬笔后只用真实点重建，可上更重的全局拟合（如 Schneider 误差约束分段贝塞尔，codex §3.3）；
- **协同/持久化**：只发真实输入或稳定干墨，**绝不发预测点**（Android 官方明确禁止预测点进最终渲染，codex §2 表格）。

#### 3.2 RDP 抽稀（claude §3.3）

在 OneEuro 之后、perfect-freehand 之前加一层 RDP 简化（ε≈1.0–2.0），去掉几乎共线的冗余点，使曲线更"干净"，也降低 outline 点数、提升性能。Android Ink 版本记录特别提到"过多过近的 modeled inputs 会造成渲染伪影"（codex §3.1）。

#### 3.3 量化验收样本（codex §6，整合三份都没有的工程纪律）

每个版本在同一台鸿蒙平板、同一缩放、同一笔宽下录制：

| 样本 | 检查重点 |
|---|---|
| 极慢速水平线/斜线 | 低速抖动、轮廓锯齿 |
| 快速水平线/斜线 | 跟手性、滞后 |
| 大圆、小圆、连续 8 字 | 曲率连续、闭合跳变 |
| `L`、`V`、`Z` | 转角保真，不过度圆滑也不拉尖 |
| 汉字"永""我""流" | 横竖撇捺、折笔、小尺度细节 |
| 压力由轻到重再到轻 | 宽度连续、压力噪声 |
| 快速抬笔 | 尾点是否到位、端帽是否跳变 |

验收时同时保留：原始采样点、OneEuro 后中心点、outline 点、截图/录屏、每帧耗时与点数。否则无法判断问题来自硬件采样、滤波、轮廓生成还是渲染。

### 阶段 4：原生增强 / 工业级（可选，前三阶段稳定后再考虑）

#### 路线 A：HarmonyOS 报点预测接入湿墨层（codex §5 第四阶段）
通过 ArkTS/native 桥接 `PointPredictor.getPredictionPoint(TouchEvent)`，**只进湿墨层**，新真实点到达时替换预测尾。注意：若 PlatformView/消息桥延迟抵消预测收益，不应强行接入。**报点预测只改善跟手性，不消除最终锯齿**（codex 反复强调，避免把它当万能药）。

#### 路线 B：Google Ink Stroke Modeler（claude §3.2，工业级备选）
通过 `dart:ffi` 集成 [google/ink-stroke-modeler](https://github.com/google/ink-stroke-modeler)，把笔尖当弹簧-质量-阻尼物理系统模拟（`d²s/dt² = (Φ-s)/M - k_d·ds/dt`），天生平滑，配 Kalman 预测补偿延迟。设计哲学"优先产生平滑好看的曲线，而非精确重现输入"。代价是 C++ FFI 集成成本高，**只在阶段 1–3 修完后真机仍明显落后系统笔记时才评估**。

#### 路线 C：原生 Pen Kit 画布作为主书写引擎（codex §7，最后选项）
仅当前述都做完、真机仍落后系统笔记应用时才考虑。否则现在直接切原生引擎，无法区分收益来源，且会大幅扩大协同、选择、撤销、序列化、跨端一致性的改造范围。

---

## 四、技术决策总览

### 4.1 算法选型矩阵（整合三份）

| 算法 | 解决什么 | 用在本方案哪里 | 来源 |
|---|---|---|---|
| **二次贝塞尔中点法** | outline 渲染锯齿（P0） | 阶段 1，替换 addPolygon | codex（官方示例）+ claude §3.4 |
| **OneEuro Filter** | 速度自适应去抖（P1） | 阶段 2.1，替换固定 EMA | claude §3.1（完整 Dart 实现） |
| **Catmull-Rom→贝塞尔** | 无压感等粗退化路径 | 已有 `_buildBezierPath` 兜底 | zcode §二 L3 + FlowMuse 现有代码 |
| **RDP 抽稀** | 冗余点、间接改善转角 | 阶段 3.2 | claude §3.3 |
| **Schneider 分段贝塞尔拟合** | 干墨最终几何压缩 | 阶段 3.1 干墨重建 | codex §3.3 |
| **Google Ink Modeler** | 工业级物理平滑 | 阶段 4 路线 B（可选） | claude §3.2 |
| **perfect-freehand** | 变宽轮廓（L4） | **保留**，是主干 | 三份一致 |
| **HarmonyOS 报点预测** | 跟手性（不治锯齿） | 阶段 4 路线 A（可选） | codex §2、zcode §L1 |

### 4.2 延迟-平滑权衡（claude §2.3 的图，标注本项目当前位置）

```
平滑度 ↑
        │  Google Ink (物理建模+Kalman 预测)   ← 阶段4路线B
        │  ╱
        │ OneEuro (速度自适应)                 ← 阶段2
        │╱
        │  perfect-freehand + 二次贝塞尔渲染    ← 阶段1+2 后的目标位置
        │
        │  perfect-freehand + addPolygon(当前)  ← 生产 App 当前 ← 病灶在渲染层
        │
        │  固定 EMA alpha=0.35(当前鸿蒙侧)
        │
        └──────────────────────→ 跟手延迟
```

本项目当前"偏左下"的主因**不是滤波不够强**（perfect-freehand 内部已有 spline 平滑），而是 **addPolygon 把平滑成果在渲染层浪费掉了**。所以阶段 1 的渲染修复能让项目"垂直上跳"一大截，几乎不增加延迟。

### 4.3 短期 vs 长期技术决策

**短期（阶段 1–3）**：继续用 `perfect_freehand`，修正其轮廓渲染 + 改进鸿蒙 stylus 输入建模。理由（codex §7）：
- 已有数据结构和协同协议可继续使用；
- 改动严格限制在渲染 + 鸿蒙笔输入，风险可控；
- 能快速验证主要视觉问题是否来自 polygon；
- 不必立即承担 ArkTS 原生画布与 Flutter 编辑器双引擎同步的复杂度。

**长期**：只有阶段 1–3 完成后、真机仍明显落后系统笔记，才评估原生 Pen Kit 画布或 Google Ink Modeler。

---

## 五、实施前必须验证的风险点

| 风险 | 来源 | 验证/缓解 |
|---|---|---|
| 二次贝塞尔渲染是否真能消除锯齿 | codex §9 资料解读边界 | 阶段 1 用同一组真机原始点做 polygon vs quadratic 的 A/B |
| OneEuro 在 HarmonyOS 真机的参数 | 新引入滤波 | 真机调 minCutoff/beta；保留固定 EMA 作为可回退开关 |
| 转角过度圆滑（把折笔/尖角抹平） | codex §3.2、claude 未充分讨论 | OneEuro 加方向突变保护；用 `L`/`V`/`Z`/汉字样本验收 |
| 压感 `force` 真机范围未知 | zcode §六、设计文档 Risk #1 | 真机打印 pressure 分布，定标到 perfect-freehand 期望的 0–1 |
| 预测点导致末端跳变 | zcode §六、Android 官方禁令 | 预测点只进湿墨层，抬笔丢弃/用真实点覆盖 |
| perfect_freehand 实时性 | 设计文档 Risk #7 | 湿墨用轻量渲染，干墨抬笔后整体重算 |

---

## 六、参考资料（去重整合）

### 官方平台资料
- Huawei Pen Kit：<https://developer.huawei.com/consumer/cn/sdk/pen-kit>
- Huawei 报点预测：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pen-point-prediction>
- Apple PencilKit `PKStrokePath`：<https://developer.apple.com/documentation/pencilkit/pkstrokepathreference>
- Microsoft `InkModelerAttributes.PredictionTime`：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkmodelerattributes.predictiontime>
- Android 高级手写笔：<https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features>
- Android Ink API 版本记录：<https://developer.android.com/jetpack/androidx/releases/ink>

### 算法与依赖
- perfect-freehand（含官方渲染示例）：<https://github.com/steveruizok/perfect-freehand>
- perfect-freehand Dart/Flutter port：<https://pub.dev/documentation/freehand/latest/>
- Google Ink Stroke Modeler：<https://github.com/google/ink-stroke-modeler>
- OneEuro Filter 论文（Casiez et al., CHI 2012）：<https://doi.org/10.1145/2207676.2208639>
- Schneider 曲线拟合（Graphics Gems 1990）：<https://lhf.impa.br/cursos/tmg/Schneider-1990.pdf>
- Catmull-Rom 实战教程（含 C++）：<https://qroph.github.io/2018/07/30/smooth-paths-using-catmull-rom-splines.html>
- Catmull–Rom 样条（Wikipedia，向心参数化）：<https://en.wikipedia.org/wiki/Catmull%E2%80%93Rom_spline>

### 成熟产品参考
- tldraw Draw Shape：<https://tldraw.dev/sdk-features/draw-shape>
- Procreate StreamLine / Stabilization：<https://www.amikosimonetti.com/life/smooth-lines>
- Sketchbook Steady / Predictive Stroke：<https://help.sketchbook.com/docs/steady-and-predictive-stroke>

---

## 附：各文档的贡献归属（便于回溯）

| 贡献 | 来自 |
|---|---|
| 源码级根因诊断（addPolygon / 固定EMA / up不收敛 / isComplete）、湿干墨分层、验收样本、资料解读边界、修正排序 | **codex**（主干） |
| OneEuro 完整 Dart 实现、Google Ink Modeler 物理模型详解、算法横向打分矩阵、延迟-平滑权衡图、RDP+Catmull-Rom 管道、Quad 贝塞尔中点法 | **claude**（具体算法弹药） |
| 四层 L1–L4 理论框架、Catmull-Rom→贝塞尔公式、成熟产品做法速览、FlowMuse 参考代码清单（注：原定位到 spike 原型，本方案已更正到生产 App） | **zcode**（理论框架与落地参考） |

> **一句话总结**：生产 App 的锯齿不是"没做平滑"，而是"平滑管线的最后一步渲染（addPolygon）和鸿蒙侧滤波（固定EMA+up不收敛）有具体缺陷"。按 codex 的排序（先修渲染→再修滤波→再做湿干墨分层），用 claude 的 OneEuro 替换固定 EMA、用官方二次贝塞尔中点法替换 addPolygon，即可在不换引擎、不破坏协同的前提下把线条质量拉到 GoodNotes 同档。
