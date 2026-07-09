# 成熟办公书写产品的笔迹平滑技术调研

> 调研日期：2026-07-09  
> 适用项目：FlowMuse / Markdraw（Flutter，优先适配 HarmonyOS 压感笔）  
> 目标：解释成熟书写产品为何能得到光滑、柔顺且低延迟的笔迹，并指出本项目当前实现与成熟方案的关键差距。

## 1. 结论摘要

成熟书写产品通常不会只使用一种“平滑算法”，而是采用完整的数字墨水流水线：

1. **完整采样**：保留位置、时间戳、压力、倾角、方向等原始信息，避免只处理二维坐标。
2. **输入建模**：去除硬件测量噪声，并根据速度、加速度或曲率动态调整平滑强度。
3. **低延迟湿墨**：书写过程中快速渲染临时笔迹，必要时加入预测点以追上笔尖。
4. **稳定干墨**：抬笔后只用真实采样点重新生成稳定的最终几何，替换湿墨。
5. **曲线或网格成形**：中心线一般使用 B-spline、Bezier 或其他连续曲线；笔刷再根据压力等属性生成连续轮廓或三角网格。
6. **高质量渲染**：使用曲线路径、抗锯齿和稳定的端帽/连接处理，而不是直接用折线连接所有轮廓顶点。

本项目已经使用 `perfect_freehand`，方向本身没有问题，但当前存在两个高优先级风险：

- `FreedrawRenderer` 将 `perfect_freehand` 生成的轮廓点直接传给 `Path.addPolygon`。这会以直线段连接离散轮廓点，容易暴露锯齿和形成尖锐转角。`perfect_freehand` 官方示例不是这样渲染，而是用相邻点中点构造连续的二次曲线路径。
- `HarmonyStylusStrokeSmoother` 使用固定系数 EMA，且每次基于上一个平滑点继续追赶原始点。固定 EMA 不考虑时间、速度和曲率，慢写时可能仍有噪声，快速转向时则可能产生滞后、切角和“追赶轨迹”。

因此，现阶段最值得先做的不是继续增大 EMA 强度，而是：

1. 修正 outline 的曲线路径生成方式；
2. 建立可重复的笔迹样本和量化指标；
3. 再将固定 EMA 替换为速度自适应滤波；
4. 最后评估 HarmonyOS 原生预测/低延迟桥接。

## 2. 能公开确认的成熟方案

厂商一般不会公开 Notes、OneNote 等产品的全部私有笔刷算法。下表只陈述其官方框架或公开技术资料可以确认的机制；“对本项目的启示”属于基于公开机制的工程推论。

| 平台/方案 | 官方可确认的处理方式 | 对本项目的启示 |
| --- | --- | --- |
| Apple PencilKit | `PKStrokePath` 以三次均匀 B-spline 控制点表达笔迹，并提供按参数、距离或时间插值的曲线上采样；`PKStrokePoint` 承载位置、时间、尺寸、透明度、力度、方位角和高度角等属性。 | 成熟笔迹的数据模型不是“原始点折线”；位置和笔刷属性沿连续曲线插值。 |
| Microsoft Windows Ink | `InkPresenter` 默认在低延迟后台线程绘制湿墨，抬笔后在 UI/内容层生成干墨；`InkModelerAttributes.PredictionTime` 可控制预测时长，默认目标为 15 ms，并会在高加速度等不利条件下降低预测量。 | 实时显示与最终存储应分离；预测必须随运动状态调整，不能把固定外推结果永久写入最终笔迹。 |
| Android/ChromeOS Ink API | 输入批次包含位置、时间戳以及可选的压力、倾角和方向；`InProgressStroke` 负责低延迟进行中笔迹，完成后得到包含固定几何 `PartitionedMesh` 的不可变 `Stroke`；官方渲染器提供抗锯齿。 | 应把输入、进行中几何、最终几何和渲染分层，而不是每帧从全部原始点生成一个简单多边形。 |
| Android Motion Prediction | 预测器使用位置、压力和时间预测临时 `MotionEvent`；官方要求新真实点到达后替换预测点，并明确禁止将预测点用于最终渲染。 | 预测只解决跟手性，不应污染协同同步和持久化数据。 |
| Huawei Pen Kit | Pen Kit 提供手写套件、笔刷、笔迹编辑和报点预测；`PointPredictor.getPredictionPoint(TouchEvent)` 可得到下一预测点，目标是改善跟手性。 | HarmonyOS 原生能力适合未来湿墨层，但仅接入预测并不能自动消除最终线条锯齿。 |
| perfect-freehand | 先从输入生成 spline points，再生成压感轮廓点；提供 `smoothing`、`streamline`、`thinning` 等参数。官方渲染示例使用轮廓点中点构造二次曲线路径。 | 当前项目可继续使用它，但必须正确渲染轮廓，并独立处理输入噪声和实时/最终状态。 |

## 3. 成熟数字墨水流水线

### 3.1 输入采样与清洗

一条有效采样至少应包含：

```text
(x, y, timestamp, pressure, tilt, orientation, pointerId, phase)
```

时间戳非常重要。没有时间戳，只能按“事件个数”滤波；不同设备、不同采样率或发生事件合并时，同一参数会产生不同结果。

常见清洗包括：

- 丢弃完全重复或距离极近、时间也极短的测量噪声；
- 检查时间戳单调性和异常坐标；
- 对压力单独去噪，不把位置滤波参数直接套到压力；
- 保留原始点，派生平滑点，避免不可逆地覆盖原始输入。

Android Ink 的更新记录也特别提到：过多彼此过近的 modeled inputs 会造成渲染伪影。这说明“点越多越光滑”并不成立，点密度、数值精度和几何生成必须共同控制。

### 3.2 速度自适应平滑

固定移动平均或固定 EMA 存在天然矛盾：

- 系数小：慢速更稳，但快速书写滞后明显；
- 系数大：快速跟手，但慢速抖动保留较多；
- 急转弯：滤波器可能切掉转角或在转角后形成追赶曲线。

更成熟的实时方案会根据速度、加速度或曲率动态调节。一个适合工程落地的公开方案是 **One Euro Filter**：

- 低速时降低截止频率，抑制手抖和测量噪声；
- 高速时提高截止频率，减少延迟；
- 只需要少量状态，适合逐点实时处理。

但速度自适应滤波仍需增加“转角保护”：当方向变化显著时临时提高响应速度，避免把汉字折笔和尖角误当成噪声抹平。

### 3.3 重采样与曲线拟合

硬件通常按时间采样，但几何渲染更关心空间分布。若点在慢速区域极密、快速区域极疏，直接连线会造成：

- 局部轮廓抖动；
- 宽度变化不均；
- 急转处出现过长或过短的线段；
- 缩放后锯齿更明显。

常用处理是按弧长进行适度重采样，再用连续曲线表达中心线：

- **B-spline**：PencilKit 明确使用三次均匀 B-spline；
- **Catmull-Rom 转 Bezier**：实现简单、局部性好，但需控制端点和急转弯过冲；
- **误差约束的分段三次 Bezier 拟合**：例如 Schneider 曲线拟合，根据允许误差递归分段，适合抬笔后的最终几何压缩；
- **二次中点曲线**：对已经生成的密集轮廓点，用相邻点中点作为端点，可快速消除多边形折角，`perfect_freehand` 官方示例采用此方式。

实时湿墨不宜使用开销大、会频繁重写整条曲线的全局拟合；抬笔后的干墨可以进行更稳定的全笔画处理。

### 3.4 压感笔刷成形

中心线平滑并不等于最终笔迹光滑。成熟笔刷还会处理：

- 压力到宽度/透明度的非线性映射；
- 压力的独立滤波；
- 宽度变化速率限制，避免相邻截面突然变宽或变窄；
- 圆形或椭圆笔尖的方向；
- join、cap、taper 和自交；
- 最终轮廓的连续曲线或网格化。

`perfect_freehand` 的 `thinning` 控制压力对宽度的影响，`smoothing` 主要软化轮廓边缘，`streamline` 主要调整中心轨迹。三者职责不同，不能只提高一个参数来解决所有锯齿。

### 3.5 湿墨、预测与干墨

成熟产品把“看起来跟手”和“最终形状正确”分成两件事：

```text
真实输入 -> 清洗/建模 -> 湿墨几何 ----> 屏幕临时层
                   \-> 预测点 ------/

真实输入 -> 最终平滑/曲线/笔刷 -> 干墨几何 -> 文档、同步、导出
```

预测点只存在于临时显示层。真实事件到达后，应撤销旧预测尾部并重绘。抬笔时最终笔迹只使用真实输入。这一点在 Android 官方文档中有明确要求，也与 Windows Ink 的 wet/dry 模型一致。

## 4. 本项目现状诊断

### 4.1 已有能力

- Flutter `PointerEvent` 的 stylus 类型和 pressure 已传入工具层；
- 鸿蒙 stylus 已有独立的 `HarmonyStylusStrokeSmoother`，不会改变其他平台；
- `FreedrawElement` 保存 points 和 pressures，满足协同同步的基础需求；
- `FreedrawRenderer` 已使用 `perfect_freehand` 生成变宽轮廓；
- 压感与位置点数量一致时关闭模拟压力，使用真实压力。

### 4.2 关键问题

#### P0：轮廓被当作折线多边形渲染

当前实现：

```dart
final path = Path()..addPolygon(outline, true);
canvas.drawPath(path, paint);
```

这会直接连接每个离散 outline 顶点。即使中心线已被 `perfect_freehand` 平滑，最终边缘仍是多段直线；采样稀疏、宽度变化或急转时尤其容易出现锯齿和尖角。

`perfect_freehand` 官方 README 的渲染示例会：

1. 从第一个轮廓点开始；
2. 以轮廓点作为控制点；
3. 以相邻轮廓点的中点作为二次曲线终点；
4. 闭合路径后填充。

这与当前 `addPolygon` 存在实质差异，应当优先验证。

#### P1：固定 EMA 不适应书写速度

当前位置公式为：

```text
smoothed = previousSmoothed + alpha * (raw - previousSmoothed)
alpha = 0.35
```

它没有时间戳、速度或曲率输入。连续快速移动时，平滑点会长期落后于笔尖；方向突然改变时，之前累积的滞后会把转角拉出异常形态。增加平滑强度会进一步加重该问题。

#### P1：抬笔点不一定到达真实终点

`up()` 仍调用同一 EMA，仅向最终原始点移动 `35%`，随后立即 reset。若最后一个 move 与 up 相距较远，最终笔迹可能停在真实终点之前，或尾部方向不自然。成熟方案通常在结束时明确收敛到真实终点，再由笔刷 taper/cap 控制视觉收尾。

#### P1：实时与最终笔迹使用同一份完成态几何

`FreedrawRenderer` 固定设置 `isComplete: true`。进行中笔迹和完成笔迹应使用不同完成状态，否则实时尾部可能被当作最终端帽处理，每次新增点时出现尾部形态跳变。

#### P2：缺少时间戳和原始/建模点双轨数据

当前 `FreedrawElement` 只保存位置和 pressure。没有 timestamp，无法实现采样率无关的速度滤波、可靠预测或按时间回放；若直接保存经过 EMA 的点，也会丢失后续重新建模的可能。

#### P2：没有针对笔迹质量的自动化指标

只靠“看起来更顺”容易导致参数反复摆动。至少需要固定输入样本和以下指标：

- 直线横向抖动 RMS；
- 圆/椭圆拟合误差；
- 原始点到平滑曲线的最大偏差；
- 急转角位置偏移和角度保真；
- 输入到显示的估算延迟；
- 点数、轮廓点数和单帧处理耗时。

## 5. 推荐改进路线

### 第一阶段：先修正最终轮廓渲染

目标：用最小改动验证锯齿是否主要来自 `addPolygon`。

1. 将 `perfect_freehand` outline 转成平滑的二次曲线闭合路径；
2. 保持输入点、压力、同步协议和其他平台逻辑不变；
3. 用同一组真机笔迹对比 polygon 与 quadratic outline；
4. 检查小字号汉字、圆、慢速斜线和快速 S 曲线。

这是当前收益最高、风险最低的一步。它修复的是渲染方式，不会通过更强滤波改变用户字形。

### 第二阶段：把固定 EMA 改为速度自适应滤波

目标：慢写稳定、快写跟手、折笔保形。

1. 在 HarmonyOS stylus 专用输入路径保留 timestamp；
2. 使用 One Euro Filter 或等价的速度自适应低通；
3. 位置和 pressure 使用独立参数；
4. 增加方向突变保护；
5. `up` 强制 flush 真实终点；
6. 继续保证非 HarmonyOS、touch、mouse 路径不变。

不建议只把现有 `positionAlpha` 从 `0.35` 调得更小。那通常能减少静态抖动，但会恶化延迟和急转角。

### 第三阶段：建立湿墨/干墨双阶段

目标：同时提高跟手性和最终几何质量。

- 湿墨：增量处理最近一小段，`isComplete=false`，允许临时预测尾；
- 干墨：抬笔后只用真实点重建，`isComplete=true`；
- 协同和持久化：只发送真实输入或稳定干墨，不发送预测点；
- 接收端：使用相同算法和版本参数重建，或同步已确定的几何。

### 第四阶段：HarmonyOS 原生增强

目标：在前三阶段稳定后进一步降低端到端延迟。

- 通过 ArkTS/native 桥接 `PointPredictor.getPredictionPoint(TouchEvent)`；
- 预测点只进入 Flutter 的临时湿墨层；
- 新真实点到达时替换预测尾部；
- 对桥接频率、对象分配、坐标变换和线程切换做性能测试；
- 若 PlatformView/消息桥延迟抵消预测收益，则不应强行接入。

报点预测主要改善“笔尖与线尾之间的空隙”，不是最终锯齿的首要修复手段。

## 6. 建议的验收样本

每个版本均在同一台鸿蒙平板、同一缩放等级、同一笔宽下录制：

| 样本 | 检查重点 |
| --- | --- |
| 极慢速水平线、斜线 | 低速抖动和轮廓锯齿 |
| 快速水平线、斜线 | 跟手性和滞后 |
| 大圆、小圆、连续 8 字 | 曲率连续性、闭合附近跳变 |
| `L`、`V`、`Z` | 转角保真，不能被过度圆滑或拉尖 |
| 汉字“永”“我”“流” | 横竖撇捺、折笔和小尺度细节 |
| 压力由轻到重再到轻 | 宽度连续性、压力噪声 |
| 快速抬笔 | 尾点是否到达、端帽是否跳变 |

验收时同时保留：

- 原始采样点；
- 过滤后中心点；
- `perfect_freehand` outline 点；
- 最终截图或录屏；
- 每帧耗时与点数。

否则无法判断问题究竟来自硬件采样、滤波、轮廓生成还是 Canvas 渲染。

## 7. 技术决策建议

短期推荐继续使用 `perfect_freehand`，但修正其轮廓渲染并改进 HarmonyOS stylus 输入建模。原因：

- 已有数据结构和协同协议可继续使用；
- 改动可严格限制在鸿蒙笔输入与 freedraw 渲染；
- 可以快速验证主要视觉问题是否来自 polygon；
- 不需要立即承担 ArkTS 原生画布与 Flutter 编辑器双引擎同步的复杂度。

只有在完成上述修正后，真机仍明显落后于系统笔记应用，才建议评估“鸿蒙端原生 Pen Kit 画布作为主书写引擎”。否则现在直接切换原生引擎，无法区分收益来自预测、笔刷、渲染还是低延迟合成，也会显著扩大协同、选择、撤销、序列化和跨端一致性的改造范围。

## 8. 参考资料

### 官方平台资料

- Huawei Pen Kit 产品页：<https://developer.huawei.com/consumer/cn/sdk/pen-kit>
- Huawei 报点预测开发指南：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pen-point-prediction>
- 本地镜像：`harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-point-prediction.md`
- Apple `PKStrokePath`：<https://developer.apple.com/documentation/pencilkit/pkstrokepathreference>
- Apple `interpolatedPoints(in:by:)`：<https://developer.apple.com/documentation/pencilkit/pkstrokepath/3595222-interpolatedpoints>
- Microsoft `InkPresenter`：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkpresenter>
- Microsoft `InkModelerAttributes.PredictionTime`：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkmodelerattributes.predictiontime>
- Android 高级手写笔能力：<https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features>
- Android Ink API 模块：<https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules>
- Android Ink API 版本记录：<https://developer.android.com/jetpack/androidx/releases/ink>

### 算法与当前依赖

- perfect-freehand 官方仓库及渲染示例：<https://github.com/steveruizok/perfect-freehand>
- Casiez, Roussel, Vogel, *1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems*, CHI 2012，DOI：<https://doi.org/10.1145/2207676.2208639>
- Schneider, *An Algorithm for Automatically Fitting Digitized Curves*, Graphics Gems, 1990：<https://lhf.impa.br/cursos/tmg/Schneider-1990.pdf>

## 9. 资料解读边界

- Apple、Microsoft、Huawei 和 Google 的公开文档能证明其数据模型、接口和渲染架构，但不能证明某个具体商业应用内部使用了完全相同的私有参数或算法。
- “成熟产品普遍采用分层数字墨水流水线”是根据多个官方平台的一致架构归纳出的工程结论。
- 本文对本项目锯齿来源的判断基于当前源码静态分析；`addPolygon` 和固定 EMA 的实际影响仍需用同一组真机原始点做 A/B 验证。
