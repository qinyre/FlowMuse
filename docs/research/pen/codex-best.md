# 鸿蒙压感笔笔迹柔顺优化：综合调研与最优方案

> 整合日期：2026-07-09  
> 输入材料：`codex-research.md`、`claude-research.md`、`zcode-research.md`  
> 适用目标：FlowMuse / Markdraw 在 HarmonyOS、Android、iOS、Windows、macOS、Linux 和 Web 上的自由书写  
> 核心约束：测试阶段直接统一升级多端书写管线，优先获得最佳效果和可验证实现，不承担历史笔迹兼容成本

## 1. 最终结论

三份调研共同确认：成熟书写体验来自完整的数字墨水管线，而不是单独调大一个平滑参数。对当前项目，最优路线是：

1. **先修正所有平台新笔迹的轮廓路径渲染**：`perfect_freehand` 已生成平滑轮廓，但当前 `Path.addPolygon` 仍以直线连接离散轮廓点。应按官方示例改为相邻轮廓点中点驱动的二次曲线路径。
2. **建立跨平台输入建模层**：使用统一样本格式和带时间戳的速度自适应滤波，按 stylus、touch、mouse 分别配置，并增加转角保护和抬笔终点 flush。
3. **建立湿墨/干墨两阶段**：书写中采用低成本增量渲染；抬笔后只用真实点生成稳定最终笔迹。预测点永不进入持久化和协同数据。
4. **最后评估 HarmonyOS Pen Kit 报点预测**：它解决跟手性，不是最终锯齿的首要修复手段。

不推荐当前直接：

- 只把 `smoothing` 改成 `0.8`、`streamline` 改成 `0.7`；
- 在实时输入链路加入 RDP；
- 立刻通过 FFI 替换成 Google Ink Stroke Modeler；
- 未经 A/B 就同时修改渲染、滤波和参数，导致无法判断实际收益来源。

这些做法要么缺乏真机数据依据，要么改变其他平台行为，要么扩大范围却没有先修复当前最明确的几何问题。

## 2. 三份调研的综合比较

| 维度 | codex-research | claude-research | zcode-research | 综合判定 |
| --- | --- | --- | --- | --- |
| 对正式白板源码的定位 | 准确识别 `perfect_freehand`、固定 EMA 和 `addPolygon` | 正确识别 `perfect_freehand` 和 EMA，但遗漏 `addPolygon` 的首要影响 | 主要分析 `spike_canvas.dart` 和原生 Spike 链路 | 以 codex 为主 |
| 成熟平台架构 | 覆盖 Apple、Windows Ink、Android Ink、Huawei Pen Kit 的官方机制 | 重点覆盖 One Euro、Google Ink 和常用曲线算法 | 四层模型清晰，但产品内部算法推断较多 | 合并 codex 的官方架构与 zcode 的分层表达 |
| 对根因的严谨性 | 区分输入噪声、轮廓几何、预测和渲染 | 把默认参数偏低作为主要根因，证据不足 | 宣称“确定的单点根因”，但指向当前分支不存在的文件 | 根因必须经 A/B 数据验证，不能预设为单一原因 |
| 参数建议 | 不预设魔法参数，强调测试 | 直接推荐 `0.8/0.7`、One Euro 固定参数 | 给出通用参数和效果百分比 | 参数只能作为实验起点，不能直接作为产品值 |
| 多端一致性 | 原稿偏向 HarmonyOS stylus，需要扩展 | 建议在 `FreedrawTool` 前全局接入 | 主要面向 Spike，未覆盖正式白板多端链路 | 使用统一最终算法 + 按设备类型配置的输入策略 |
| 实时/最终分层 | 明确 wet/dry 和预测点替换 | 提到抬笔后重算 | 提到实时降级和抬笔重算 | 纳入最终架构 |
| 协同和持久化 | 明确预测点不能同步 | 基本未展开 | 基本未展开 | 只同步真实的稳定 points/pressures，不同步预测点 |
| 实施风险 | 分阶段、强调量化指标 | Google Ink 路线过重，RDP 顺序值得质疑 | 可操作性强，但目标代码链路不匹配 | 使用分阶段、可回退实施 |

### 2.1 `codex-research` 中应保留的内容

- 正式白板当前已经使用 `perfect_freehand`，不需要重新引入另一份同类库；
- `addPolygon(outline, true)` 与 `perfect_freehand` 官方二次曲线路径示例存在关键差异；
- 固定 EMA 不考虑采样时间、速度和曲率，容易在快速转向时滞后或切角；
- `up()` 仍走 EMA，最终点可能不收敛到真实抬笔点；
- 预测只属于湿墨，不应进入最终笔迹、持久化或协同；
- 应使用真实样本和量化指标，不应只凭主观观感调参数。

### 2.2 `claude-research` 中应保留的内容

- One Euro Filter 是适合实时输入的低成本速度自适应滤波方案；
- Google Ink Stroke Modeler 可作为长期专业级技术储备；
- RDP、Catmull-Rom、二次中点法分别解决不同问题，不能混为“平滑”；
- 应采用渐进式方案，而不是一次替换整个书写引擎。

需要修正的表述：

- `perfect_freehand.smoothing` 的官方定义是软化笔迹边缘，`streamline` 是减少输入点变化；不能简单描述为“高斯平滑”和“前瞻预测”；
- `0.8/0.7` 没有本项目真机数据支持，只能作为候选实验参数；
- Google Ink Stroke Modeler 主要生成平滑的笔尖状态/中心轨迹，并不天然替代变宽轮廓和笔刷渲染；
- RDP 会删点但不会去除所有噪声，实时递归简化还可能破坏转角、压力对齐和增量稳定性。

### 2.3 `zcode-research` 中应保留的内容

- “采样、预处理、曲线/轨迹建模、笔刷轮廓”四层划分清晰；
- 抗锯齿只能改善像素边缘，不能修复几何折线；
- 压力、速度、端帽和 taper 是“柔顺感”的组成部分；
- 先低风险验证，再逐步进入专业级方案的思路正确。

需要排除的内容：

- 当前分支不存在文档所引用的 `spike_canvas.dart`、`plugin_manager.cpp` 和 `SpikePlugin.ets` 跟踪文件；
- 正式白板并非“完全没有 L2/L3/L4”，它已经有 Harmony stylus EMA、`perfect_freehand` 和真实 pressure；
- “接入 perfect_freehand”不是待办事项，正式白板已依赖 `perfect_freehand: ^2.5.0`；
- “Catmull-Rom 当天消除 70%+”“达到 GoodNotes 同档”等百分比和产品档位判断缺乏可复现实验；
- 商业产品私有算法未公开时，不能把推断写成已确认事实。

## 3. 当前正式白板的真实链路

当前主链路是：

```text
Flutter PointerEvent
  -> MarkdrawController
  -> HarmonyStylusStrokeSmoother（仅 OHOS stylus freedraw）
  -> FreedrawTool（points + pressures）
  -> FreedrawElement
  -> FreedrawRenderer
  -> perfect_freehand.getStroke
  -> outline 点
  -> Path.addPolygon
  -> Canvas fill
```

已确认的关键文件：

| 职责 | 当前文件 |
| --- | --- |
| Harmony stylus 前置平滑 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/harmony_stylus_stroke_smoother.dart` |
| 输入路由与平台隔离 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` |
| points/pressures 收集 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart` |
| 变宽轮廓生成与绘制 | `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart` |
| pressure 到 thinning | `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart` |
| 依赖 | `FlowMuse-App/pubspec.yaml` |

### 3.1 最可能的视觉问题来源

按优先级排序：

1. **轮廓折线化**：`perfect_freehand` 输出的离散 outline 被 `addPolygon` 直连；
2. **固定 EMA 的速度无关滞后**：慢速与快速共用 `positionAlpha=0.35`；
3. **抬笔终点未 flush**：结束点可能只向真实位置移动一次 EMA；
4. **进行中和完成态未分离**：renderer 固定以完成态生成尾部；
5. **pressure 变化过快**：压力只做固定 EMA，缺少宽度变化速率约束；
6. **采样或桥接问题**：需要原始数据证据后才能判断，不能由当前源码直接下结论。

## 4. 最优架构

### 4.1 数据流

```text
各平台 PointerEvent
  -> 样本规范化 StrokeInputSample (x, y, time, pressure, kind, phase)
  -> 输入策略 (stylus / touch / mouse)
  -> 去重/最小距离门限
  -> One Euro 位置滤波 + 独立 pressure 滤波
  -> 转角保护
  -> 实时真实点
       -> 湿墨：isComplete=false + 可选临时预测尾
       -> 干墨：抬笔 flush 真实终点，isComplete=true
  -> perfect_freehand outline
  -> 二次中点曲线路径
  -> Canvas fill
```

各平台共享相同的最终轮廓和渲染算法，但输入策略按设备类型配置：

- stylus：使用真实 pressure，启用位置与 pressure 自适应滤波；
- touch：无可靠 pressure 时由 `perfect_freehand` 模拟压力，采用较保守的位置滤波；
- mouse：默认不做强滤波，只进行去重和最小距离处理，避免直线操作产生拖尾；
- 平台原生预测点只进入湿墨层，不写入统一最终数据。

### 4.2 测试阶段的全局替换策略

当前不需要兼容历史笔迹，因此不新增 `renderProfile`，也不保留 `legacy` 渲染分支：

- `FreedrawRenderer` 全局切换到二次中点轮廓路径；
- 测试阶段保留运行时 `OutlineRenderMode.polygon/quadratic`，用于同一输入的快速 A/B；
- 所有平台 freedraw 使用统一最终几何和笔刷参数；
- 当前 HarmonyOS 固定 EMA 迁移到统一 `StrokeInputModeler`，避免两套平滑叠加；
- stylus、touch、mouse 只在输入策略上不同，最终渲染保持一致；
- 协同继续同步稳定的 points/pressures，不同步预测点；
- 测试客户端必须使用同一算法版本，避免不同构建之间的显示差异。

这种方案比 profile 分支更简单，测试覆盖更集中，也便于快速比较新旧算法。进入正式发布前，再根据已有用户数据和协议演进需求决定是否引入版本字段。

### 4.3 四层实现模型

吸收 `zcode-best` 的分层表达，但以当前正式白板实际能力为准：

| 层 | 目标 | 本轮方案 |
| --- | --- | --- |
| L1 输入采样 | 不丢位置、时间、压力等信息 | 统一规范化 `PointerEvent`，保留单调时间戳和有效 pressure |
| L2 输入建模 | 去重、低速去抖、快速跟手 | 最小距离门限 + One Euro + pressure 独立滤波 + 转角保护 |
| L3 轨迹与轮廓 | 生成连续中心轨迹和变宽轮廓 | 保留 `perfect_freehand`，不重复引入另一套 Catmull-Rom |
| L4 高质量渲染 | 避免轮廓折线和端帽跳变 | 二次中点 Path + wet/dry 完成态 + Canvas fill |

### 4.4 输入滤波

建议使用 One Euro Filter 处理位置，并封装为平台无关的 `StrokeInputModeler`：

```text
cutoff = minCutoff + beta * |filteredVelocity|
```

- 低速：降低截止频率，抑制测量噪声和手抖；
- 高速：提高截止频率，减少跟手延迟；
- 使用统一单调时间基准计算真实 `dt`；
- X/Y 共用速度幅值确定 cutoff，避免两个轴响应不同；
- pressure 使用独立滤波参数；
- `dt <= 0`、超长间隔和异常点必须重置或旁路。

参数不在文档中定死。吸收 `claude-best` 的参数建议作为实验起点，而不是产品结论：

- One Euro：以 `minCutoff=1.0`、`beta=0.007`、`dCutoff=1.0` 附近开始网格搜索；
- `perfect_freehand`：保留当前 `0.5/0.5` 作为基线，对比 `smoothing=0.65/0.8` 与 `streamline=0.6/0.7`；
- stylus、touch、mouse 分别选参，不假设同一组参数适合所有输入；
- 以多平台录制数据离线回放，先过几何指标，再做盲测选择。

具体数值受坐标单位、采样率和实现细节影响，不能直接照搬论文或其他产品。

### 4.5 转角保护

纯低通滤波容易把汉字折笔磨圆。建议根据连续方向向量夹角处理：

- 方向变化较小时使用正常自适应滤波；
- 方向变化超过阈值时临时提高响应速度；
- 不对单个异常点立即触发，应结合最小移动距离和连续样本；
- 保护的是用户真实折笔，不是把所有尖角保留下来。

转角保护必须通过 `L/V/Z` 和汉字样本验证，不能只用圆和 S 曲线调参。

### 4.6 轮廓路径

1. 调用 `perfect_freehand.getStroke` 得到 outline；
2. 从第一个 outline 点开始；
3. 以当前 outline 点作为二次曲线控制点；
4. 以当前点和下一点的中点作为终点；
5. 处理尾部并闭合；
6. 使用 fill 绘制。

这与 `perfect_freehand` 官方渲染示例一致，能避免直接暴露 outline 折线边，并保证各平台采用相同最终几何。

注意：二次中点法主要修复轮廓边缘，不替代输入去噪。两层都需要，但必须分别做 A/B，以确定各自贡献。

### 4.7 湿墨与干墨

湿墨：

- 只增量更新最近一段；
- `isComplete=false`；
- 可接受轻微临时形态变化；
- 未来接入预测时，预测点只存在于此层。

干墨：

- 抬笔时追加真实最终点，不再对终点只做一次低通；
- 删除/覆盖预测尾；
- 使用全部真实稳定点重算；
- `isComplete=true`；
- 只有干墨 points、pressures 进入持久化及协同。
- 若全量重算影响帧率，吸收 `zcode-best` 的降级思路：湿墨只增量重算最近 N 段，抬笔后全量重算。

## 5. 分阶段实施顺序

### 阶段 0：建立基线与可重复样本

先记录同一设备、同一缩放、同一笔宽下的：

- 极慢直线、快速直线；
- 大圆、小圆、连续 8 字；
- `L/V/Z`；
- 汉字”永””我””流”；
- 轻到重再到轻；
- 快速抬笔。

**录制工具链**（不只是单一 `StrokeRecorder`）：

| 组件 | 职责 |
|------|------|
| `StrokeRecorder` | 原始位置、时间戳、pressure、`PointerDeviceKind`、事件阶段（down/move/up/cancel） |
| `StrokeInputModelerTrace` | 过滤后位置、pressure、被丢弃原因 |
| `StrokeRenderMetrics` | outline 点数、`getStroke` 耗时、路径构建耗时、绘制耗时 |
| `StrokeReplayRunner` | 用相同事件序列重复运行不同算法参数，输出上述所有指标 |

约束：

- 保存**规范化输入样本**（`StrokeInputSample`），不直接序列化 Flutter `PointerEvent` 对象。离线测试不应依赖 Flutter 手势事件的构造细节；
- 保持事件顺序、down/move/up/cancel、pointer/stroke id 和原始时间间隔；
- 每次结果记录算法参数、渲染模式、平台/设备信息和构建版本；
- recorder、trace 和实验入口只在 debug/test 构建启用；
- 回放应同时生成指标和图像，避免每次依赖人工重画；
- 先验证 recorder/replay 对同一算法能得到确定性结果，再开始阶段 1。

没有这一步，后续无法区分参数改善还是书写样本变化。

### 阶段 1：轮廓曲线路径 A/B

用运行时枚举控制渲染模式，不依赖人工重画做对比：

```dart
enum OutlineRenderMode { polygon, quadratic }
```

规则：

- 一笔开始后固定模式，不能在笔画中途切换。
- 录制结果必须标注使用的模式。
- 模式可通过 debug 实验面板或回放配置切换，不需要修改代码重新编译。
- 仅在 debug/实验入口暴露；正式版本直接使用确定后的模式。
- **同一录制样本离线同时输出 polygon/quadratic**，不需要人工重画来做 A/B。

A：当前 `addPolygon`（`OutlineRenderMode.polygon`）；
B：二次中点曲线路径（`OutlineRenderMode.quadratic`）。

若 B 明显降低边缘锯齿且不引入自交、缺口和端帽异常，则全局替换当前 renderer。

### 阶段 2：终点 flush 与完成态修正

- `up` 保证最终真实坐标进入最终点列；
- 进行中使用 `isComplete=false`；
- 完成后使用 `isComplete=true`；
- 验证尾部不缩短、不回弹、不跳变。

### 阶段 3：跨平台 One Euro + 转角保护 + 统一 Pointer 输入层

**前置事实**：当前 `HarmonyStylusStrokeSmoother` 是 **Dart 侧文件**（[harmony_stylus_stroke_smoother.dart](FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/harmony_stylus_stroke_smoother.dart)），由 [markdraw_controller.dart](FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart) 调用，不是 native 层代码。因此不需要绕过 native EMA，但需要重构 pointer 路由。

**新的 pointer 输入层路由**：

```text
PointerEvent
  -> 规范化 StrokeInputSample (x, y, time, pressure, kind, phase)
  -> 按 kind 选择 InputPolicy (stylus / touch / mouse)
  -> StrokeInputModeler (One Euro + 转角保护)
  -> FreedrawTool
```

**关键约束**：

- 每个 pointer/stroke 独立维护滤波状态（down 初始化、move 累积、up/cancel reset）。
- **非 freedraw 工具不得经过该层**（选择、擦除、平移等保持原始坐标）。
- 避免现有 Harmony smoother 与新 modeler **双重平滑**：阶段 3 上线时移除 `HarmonyStylusStrokeSmoother` 的路由。
- pressure 缺失时使用默认值并标记，不抛异常。
- 时间戳异常（`dt <= 0`、超长间隔）必须旁路滤波，直接输出原始点。
- 事件取消（`PointerCancelEvent`）立即 reset 滤波状态并丢弃当前 stroke。
- `up` 必须输出真实终点后再 reset，不能保留尚未收敛的滤波位置。

**参数策略**：

- 建立统一 `StrokeInputModeler`；
- stylus、touch、mouse 使用独立策略参数；
- pressure 单独滤波；
- 保留当前固定 EMA 作为 feature flag 回退；
- 使用阶段 0 录制的多平台样本离线回放调参；
- 各端检查跟手性、汉字保真和鼠标操作准确性。

### 阶段 4：参数实验与可选干墨抽稀

- 采用小规模参数网格，而不是直接固定 `0.8/0.7`；
- 每组参数使用相同录制输入回放；
- 只有当性能数据表明点数或 outline 规模是瓶颈时，才在干墨阶段尝试 RDP；
- RDP epsilon 必须按画布缩放或场景单位定义，并同步保留 pressure；
- 汉字短折笔和快速转角出现损失时立即取消 RDP。

### 阶段 5：序列化和协同一致性

- JSON 往返保持 points/pressures；
- 接收端使用相同算法构建显示；
- 预测点和湿墨临时状态不进入协同；
- 多端同时书写时，完成笔迹在各端显示一致。

### 阶段 6：原生预测可行性验证

前三阶段达标后再做：

- ArkTS/native 获取 `PointPredictor.getPredictionPoint(TouchEvent)`；
- 预测点标记为 transient；
- 新真实点到达时替换预测尾；
- 测量桥接、对象分配和线程切换成本；
- 若预测收益小于桥接延迟或增加抖动，保持关闭。

## 6. 暂不采用的方案

### 6.1 只调高 perfect_freehand 参数

原因：

- 无法修复 `addPolygon` 的直线轮廓；
- 更强 `streamline` 可能损失折笔和小字细节；
- `0.8/0.7` 没有当前设备的实验依据；
- 参数调优应放在几何修复之后，并对不同输入设备分别验证。

### 6.2 实时 RDP

原因：

- RDP 是几何简化，不是速度自适应去噪；
- 新点加入时，之前保留/删除的点可能变化，导致实时笔迹跳动；
- 需要同步处理 pressure 和 timestamp；
- 可能删除汉字中的短折笔；
- 当前尚无点数或性能证据证明必须简化。

仅当性能数据表明点数过高时，考虑抬笔后的误差受控简化。

### 6.3 Google Ink Stroke Modeler

原因：

- C++ FFI、HarmonyOS 构建和 ABI 维护成本高；
- 它不能替代 pressure 到轮廓/网格的笔刷成形；
- 当前已有纯 Dart 管线，尚未完成低风险修正；
- 会扩大跨平台确定性、协同重建和调试范围。

可作为未来独立 spike，与 One Euro 方案使用同一批录制输入做盲测比较。

### 6.4 直接切换原生 HandwriteComponent

原因：

- 会形成 Flutter 编辑器与原生画布双引擎；
- 选择、擦除、撤销、缩放、序列化和协同都需重新对接；
- 本轮问题是笔迹质量，不足以证明需要替换整个编辑器。

## 7. 测试与验收

### 7.1 自动化测试

多端策略：

- stylus、touch、mouse 进入各自输入策略；
- 相同规范化输入在不同平台生成等价最终数据；
- 不同平台事件频率变化时，滤波输出仍保持接近。

滤波：

- 相同几何、不同采样率下输出接近；
- 慢速噪声幅度下降；
- 快速直线滞后受控；
- 急转角位置和角度不被过度改变；
- `up` 最终点等于真实终点；
- pressures 数量始终与 points 一致。

路径：

- 空、单点、双点和普通笔迹不崩溃；
- 二次轮廓路径闭合；
- 不产生 NaN/Infinity；
- JSON 往返和协同传输后 points、pressures 一致。

回归：

- 各平台统一算法基准截图一致；
- 选择、擦除、缩放和导出后的笔迹几何一致；
- 选择、擦除、撤销、重做和导出继续工作。

### 7.2 量化指标

建议至少记录：

| 指标 | 目的 |
| --- | --- |
| 直线正交方向 RMS | 衡量低速抖动 |
| 圆/椭圆拟合残差 | 衡量曲线稳定性 |
| 原始点到最终中心轨迹的最大/P95 偏差 | 防止过度修形 |
| `L/V/Z` 转角位置和角度偏差 | 衡量折笔保真 |
| 最终点误差 | 检查抬笔 flush |
| 单帧处理 P50/P95/P99 | 检查跟手和卡顿 |
| 每笔 points/outline 数量 | 检查数据规模 |

第一轮建议以“相对当前基线明显改善且无保真回归”为门槛，不预先伪造固定百分比。积累多次真机数据后再固化数值阈值。

### 7.3 真机验收

通过条件：

- 慢速斜线和小圆的边缘锯齿明显低于当前基线；
- 快速书写没有可感知的额外拖尾；
- `L/V/Z` 与汉字折笔位置未被明显磨圆或偏移；
- 快速抬笔不缩短、回弹或产生尖刺；
- 压感粗细连续，无相邻宽度突跳；
- 手指和鼠标仍保持各自当前交互语义；
- 各平台笔迹均得到改善；
- 协同接收端与发送端显示一致。

## 8. 推荐技术决策

最终推荐采用：

```text
跨平台统一书写管线
  + perfect_freehand 保留
  + 二次中点 outline Path
  + 按输入设备配置的 One Euro 位置滤波
  + 独立 pressure 滤波
  + 转角保护
  + up 真实终点 flush
  + wet/dry 分层
  + 预测点仅临时显示
```

该方案的优势：

- 修复当前最明确的轮廓几何问题；
- 不推翻现有 `perfect_freehand`、数据模型和编辑器；
- 可用同一套最终算法统一改善多端笔迹；
- points/pressures 可直接用于跨设备一致重建；
- 每阶段都能独立 A/B、测试和回退；
- 为未来 Pen Kit 预测保留正确的湿墨接入点。

## 9. 参考资料

- Huawei Pen Kit：<https://developer.huawei.com/consumer/cn/sdk/pen-kit>
- Huawei 报点预测：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pen-point-prediction>
- Apple `PKStrokePath`：<https://developer.apple.com/documentation/pencilkit/pkstrokepathreference>
- Microsoft `InkPresenter`：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkpresenter>
- Microsoft `PredictionTime`：<https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.inking.inkmodelerattributes.predictiontime>
- Android Ink API：<https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules>
- Android 高级手写笔能力：<https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features>
- perfect-freehand：<https://github.com/steveruizok/perfect-freehand>
- Google Ink Stroke Modeler：<https://github.com/google/ink-stroke-modeler>
- One Euro Filter：<https://doi.org/10.1145/2207676.2208639>

## 10. 文档边界

- 本文是综合技术决策，不代表商业产品公开了其全部私有算法；
- 对商业产品的判断仅采用可公开确认的框架和能力，不把体验推断当作事实；
- 当前根因排序来自源码静态分析，实施前仍须通过相同真机输入做 A/B；
- 本文不包含代码修改，后续应据此另写实施计划并逐阶段验证。
