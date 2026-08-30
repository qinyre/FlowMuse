# 铅笔与毛笔自然介质效果专项调研

> 日期：2026-08-30
> 代码基线：`main@3eb2b97`
> 适用范围：FlowMuse-App 的铅笔与毛笔（`BrushType.pencil` / `BrushType.brushPen`）
> 关联计划：[2026-08-30-pencil-brush-natural-media-redesign.md](../plans/2026-08-30-pencil-brush-natural-media-redesign.md)

## 1. 结论先行

当前实现没有明显的功能性错误，但产品目标只达到了“笔形可区分”，没有达到“介质可信”：

- 铅笔是一个填充了噪声透明度的平滑灰色轮廓，笔压仍主要改变宽度，缺少石墨沉积、纸纹显露、边缘破碎和重复覆盖变深；
- 毛笔是一个加粗、强压感、两端对称收尖的 `perfect_freehand` 轮廓，缺少笔头方向、笔肚铺展、转折蓄力和少量毫丝层次，视觉上更像粗马克笔或叶片形笔触；
- 现有测试只证明两种输出与其他笔“像素不同”，没有证明它们像铅笔或毛笔；
- 最近为真机起笔闪变加入的 1.5 秒压力下限能稳定宽度，却会把轻触笔画抬到中等压力，直接削弱铅笔轻重层次和毛笔提按表达。

本次不继续做参数微调。建议把铅笔和毛笔从“统一实体轮廓 + 少量特判”升级为两个确定性的自然介质渲染器，同时保留当前经典渲染器给旧元素和其他三支笔使用。

目标也必须收窄：

- 铅笔首版定位为 **HB 日常书写铅笔**，兼顾少量排线，不承诺完整素描铅笔或侧锋涂抹；
- 毛笔首版定位为 **软头毛笔笔/Brush Pen**，适合中文书写和 lettering，不承诺宣纸渗化、含墨量扩散和真实多毫物理模拟。

这两个目标在现有 Flutter/Excalidraw/协作架构内可实现，且效果会比继续调整 `thinning`、`taper` 和噪声透明度明显得多。

## 2. 当前代码事实

### 2.1 两支笔仍共用同一个几何引擎

`brush_render_profile.dart` 只为笔形提供缩放、透明度、thinning、smoothing、streamline 和 taper 参数；`freedraw_renderer.dart` 最终仍把两支笔交给 `perfect_freehand.getStroke()` 生成一个实心闭合多边形。

当前主要差异：

| 项目 | 铅笔 | 毛笔 |
| --- | --- | --- |
| `sizeScale` | 0.82 | 1.15 |
| `opacityScale` | 0.68 | 1.0 |
| 压感跨度 | 0.45 | 1.0 |
| 模拟压感 | 0.32 | 0.82 |
| 起/收笔 taper | 3× / 4× | 6× / 6× |
| 纹理 | shader 或颗粒降级 | 无 |

这套参数能把轮廓做得不同，但不能表达不同介质的生成机制。

### 2.2 铅笔纹理只是轮廓内的标量噪声

`shaders/pencil.frag` 以 `FlutterFragCoord()` 计算五层 FBM，再把噪声映射为 alpha。它没有以下输入：

- 纸张纹理；
- 笔画切线和法线；
- 每点压力场；
- 笔尖姿态；
- 稳定的笔画种子；
- 重复沉积状态。

因此它只能让平滑轮廓内部出现亮暗噪声，无法让纹理沿轨迹组织，也无法表现石墨颗粒在纸峰/纸谷中的沉积。Flutter 官方文档说明 `FlutterFragCoord` 是本地坐标，因此本报告不把它误判为 screen-space；问题不在坐标 API，而在纹理模型过于单一。

shader 不可用时的降级路径沿中心线绘制一组垂直短线。它有确定性和硬上限，但这些短线不是石墨颗粒，视觉上容易成为规则的鱼骨纹。

### 2.3 毛笔只有“圆形笔头半径变化”

当前毛笔的压力变化最终仍是圆形截面的半径变化，并使用固定、对称的 6×size 起收 taper。缺失：

- 笔头接触面的方向和长短轴；
- 切线变化时的笔头滞后；
- 转折处的笔肚铺展；
- 实际压力和抬笔决定的非对称起收；
- 轻量、确定性的毫丝层次。

所以视觉矩阵中的毛笔是“较粗、两头尖的黑色带状线”，不是中文用户直觉中的软头毛笔笔触。

### 2.4 输入模型丢弃了姿态信息

`StrokeInputSample` 当前只保存坐标、时间、压力、设备类型、阶段和预测状态。Flutter `PointerEvent` 已提供 `tilt` 与 `orientation`，但规范化层没有采集它们。

这不意味着本期应立刻修改元素 schema。鸿蒙、Web 和 Windows 对姿态字段的实际可靠性尚未形成设备证据；没有探针数据就持久化姿态，会引入体积、兼容和协作成本，却可能一直得到 0。

本期渲染只使用已经可靠保存的坐标、点序和压力。姿态作为独立能力探针，证明确有价值后再进入后续版本。

### 2.5 起笔攻击补偿与自然介质目标冲突

`MarkdrawController` 仅对铅笔和毛笔启用：

- `pressureAttackMs = 1500`；
- `pressureAttackLevel = 0.50`。

它的来源合理：真机 OPD2404 在起笔约 0.5–1.2 秒内从约 0.2 爬升到约 0.5，短窗口会造成反向变细。但当前策略等价于在长达 1.5 秒内给压力加一个逐渐下降的下限。

后果：

- 用户想轻写时，铅笔开头仍被抬成中等浓度/宽度；
- 毛笔的轻落、轻提和细线难以表达；
- 不同书写速度下，相同空间长度受时间包络影响不同；
- 该补偿已烘焙进 points 的 pressure，后续渲染器无法恢复真实输入。

新方案必须用笔形响应曲线和短时稳定器替代硬下限，不能简单删除保护，也不能继续保留 1.5 秒地板。

### 2.6 `.markdraw` 往返已有一个相关缺口

`.markdraw` 会写入 `brush=` 和 pressure 数组，但解析时只恢复 `brushType`，不会恢复 `customData.flowMuse.pressureEncoding=1`。已编码压力在往返后会被当成旧数据再次按默认灵敏度解释。

自然介质版本若只写进 `customData`，同样会在分屏文本编辑后丢失。新版计划必须把压力编码和渲染版本都纳入 `.markdraw` 明文语法，并为旧文本保留默认值。

### 2.7 远端湿墨按 64 点冻结，天然存在连续性风险

远端湿墨将长笔分成冻结 Picture 和有限 tail。当前 taper 已通过 `FreedrawTaperPhase` 避免每块重复收尖，但自然介质纹理还需要稳定的随机种子和分段无关的采样归属。

如果每个块从头采样或重新播种，将产生：

- 周期性颗粒接缝；
- 每 64 点重复的毫丝纹理；
- 冻结块与 tail 交界处变深或露白；
- 提交静态元素后纹理重排。

因此“分块连续性”是架构任务，不是最后的视觉调参。

### 2.8 现有视觉门禁不足以发现问题

已实跑：

```text
flutter test test/features/whiteboard/editor_core/rendering/brush_visual_matrix_test.dart
2 tests passed
```

生成的矩阵中：

- 铅笔仍是一条平滑、均匀的灰线，石墨质感很弱；
- 毛笔仍是一条宽黑带，带对称矛尖。

但测试仅要求各笔形墨迹像素的并集差异超过 5%，两者都能通过。这类断言适合防止“五笔完全同形”，不适合作为自然介质验收。

## 3. 成熟产品和技术方案启示

### 3.1 Goodnotes：先把笔形语义说清楚

Goodnotes 将 Fountain Pen 定义为压感书写，Ball Pen 定义为恒宽，Brush Pen 定义为高度压感的艺术书写；毛笔只暴露压力灵敏度。其价值不是某组参数，而是用户能预期每支笔为何不同。

对 FlowMuse 的启示：毛笔应围绕提按和中文笔画形态构建，不应靠“更多噪声”与铅笔区分。

来源：[Goodnotes - Using the Pen tool](https://support.goodnotes.com/hc/en-us/articles/7353756785679-Using-the-Pen-tool)

### 3.2 Procreate：自然笔刷是 Shape + Grain + 输入映射

Procreate 将笔刷描述为沿路径拖动的 Shape，内部承载 Grain，并允许压力和倾斜分别驱动属性。它还提供实时测试画板和压力预览。

对 FlowMuse 的启示：

- 铅笔至少需要“轨迹形状”和“颗粒/纸纹”两个层次；
- 压力应映射到浓度、宽度等不同属性，而不是只驱动一个 thinning；
- 在代码实现前先用固定压力坡道预览锁定目标。

来源：[Procreate Brush Studio](https://help.procreate.com/procreate/handbook/5.3/brushes/brush-studio)、[Brush Studio Settings](https://help.procreate.com/procreate/handbook/5.3/brushes/brush-studio-settings)

### 3.3 Wacom WILL：颗粒笔刷与实体矢量笔刷应分开

Wacom 的 Raster Ink 示例为铅笔配置 shape texture、fill texture、spacing、scattering 和 rotation；其 Web `BrushGL` 文档也明确把表现型笔刷描述为沿轨迹分布的大量小纹理粒子。Vector Ink 则用可变换的笔头多边形生成几何。

对 FlowMuse 的启示：

- 铅笔适合确定性颗粒/印章思路；
- 毛笔适合方向性接触面和矢量包络；
- 不应继续要求同一个圆形截面算法同时承担两种介质。

来源：[Wacom Ink Geometry Pipeline & Rendering](https://developer-docs.wacom.com/docs/sdk-for-ink/guides/rendering/)、[Wacom BrushGL](https://developer-docs.wacom.com/docs/sdk-for-ink/api/digital-ink-web/Rendering.WebGL.BrushGL/)

### 3.4 PencilKit 与 Flutter：压力之外确实存在姿态通道

Apple PencilKit 的基础笔宽会受到 force、azimuth 和 angle 影响；Flutter 的 `PointerEvent` 也提供压力、倾斜和方向字段。

对 FlowMuse 的启示：姿态是未来提升铅笔侧锋和笔头方向的正确方向，但必须先在目标鸿蒙设备、Web 手写板和 Windows 手写笔上做可靠性探针。首版不以未验证数据为依赖。

来源：[Apple PKInkingTool](https://developer.apple.com/documentation/pencilkit/pkinkingtoolreference?language=objc)、[Flutter PointerEvent tilt](https://api.flutter.dev/flutter/gestures/PointerEvent/tilt.html)、[Flutter PointerEvent orientation](https://api.flutter.dev/flutter/gestures/PointerEvent/orientation.html)

### 3.5 Adobe Fresco：压力曲线需要可视化校准

Fresco 提供标准压力曲线、节点调整和实时试写区。它说明“设备原始压力 → 笔刷表现”不应由固定时间地板解决。

对 FlowMuse 的启示：本期先提供三个内部固定响应曲线并继续复用现有灵敏度滑块，不急于制作复杂曲线编辑器；必须用真实轻/中/重输入回放验证单调性。

来源：[Adobe Fresco - Adjust stylus pressure](https://helpx.adobe.com/fresco/using/pressure-curve.html)

### 3.6 石墨研究：纸纹、材料和压力共同决定外观

计算机石墨铅笔研究把纸张纹理、石墨材料、笔尖形状和压力视为共同输入。FlowMuse 不需要做物理仿真，但至少应保留这些关系中的三个可见结果：低压留白更多、重压覆盖更多、重复描画自然变深。

来源：[Observational Models of Graphite Pencil Materials](https://diglib.eg.org/items/0f0d430c-7ac9-4aba-b96a-77bb6836cbc4f)、[Computer-Generated Graphite Pencil Rendering](https://diglib.eg.org/items/929edc11-8bac-4479-98ed-c2912fcec395)

## 4. 目标体验定义

### 4.1 铅笔 v2：HB 日常书写铅笔

必须出现：

1. 低压细且浅，重压主要更黑，同时只适度变宽；
2. 边缘存在稳定、不规则的小缺口，不出现规则横纹；
3. 沿轨迹存在细小石墨颗粒，缩放和平移后不游动；
4. 同一路径重复覆盖会逐步变深；
5. 鼠标/触摸无压感时仍是可识别的中等 HB 效果；
6. Web、Windows、HarmonyOS 使用同一确定性几何，不因 shader 能力变成两种笔。

本期不做：

- 铅笔侧锋大面积铺色；
- 2H/HB/2B 多硬度 UI；
- 真实纸张材质选择；
- 物理级石墨反射。

### 4.2 毛笔 v2：软头毛笔笔

必须出现：

1. 提按对笔画宽度的影响明显，轻压细线仍可保留；
2. 起笔、行笔、转折、收笔由真实压力和方向决定，不再统一生成对称矛尖；
3. 急转时外侧自然铺展，内侧不产生尖刺或自交黑块；
4. 主体有少量方向一致的毫丝层次，但默认不是“枯笔”；
5. 横、竖、撇、捺、点、折、钩、提八类基本笔画可辨；
6. 鼠标/触摸以确定性模拟压力获得可用结果。

本期不做：

- 宣纸渗墨和水分扩散；
- 墨池、蘸墨、含墨量状态；
- 数十根独立毫毛的物理模拟；
- 书法字形自动美化。

## 5. 技术路线裁决

### 5.1 采用：一个共享采样模型，两个专用渲染器

新增共享的 `NaturalMediaStrokeSampler`，只负责：

- 校验点和压力；
- 按稳定点序建立切线、法线和曲率；
- 给每条原始边分配稳定采样点；
- 生成与分块无关的确定性种子；
- 提供局部宽度和可视边界数据。

在其上分别实现：

- `PencilStrokeRendererV2`：浅色基底 + 2～3 个密度桶的复合颗粒 Path；
- `BrushPenStrokeRendererV2`：方向性包络 + 一个毫丝细节复合 Path。

静态画布、本地湿墨、远端湿墨和 SVG 都消费同一采样结果或同一规则，不各写一套算法。

### 5.2 新笔走 v2，旧笔保持 v1

新增 `customData.flowMuse.brushRenderVersion=2`：

- 新建铅笔、毛笔元素写 2；
- 旧元素缺失时按 1 渲染；
- 不自动升级历史笔迹，避免打开旧笔记后视觉漂移；
- 其他三支笔继续走 ADR-020 的经典 renderer；
- `BrushRenderProfile` 继续作为样式、边界和分发真源，不再强迫它承担自然介质算法。

### 5.3 铅笔 v2 采用纯 Dart/Canvas 确定性颗粒，不新增 shader

本次选择跨端一致优先：

- 新铅笔不使用 FragmentShader；
- 粒子按“原始边索引 + 边内序号 + stroke seed”生成；
- 所有粒子合并进有限个复合 Path，禁止逐粒子 draw；
- 粒子数量有静态、湿墨两档硬上限；
- v1 铅笔仍保留旧 shader/fallback，保证历史元素不漂移。

这样只有一个 v2 实现需要调优，不再长期维护 shader、fallback、SVG 三套互不等价纹理。

### 5.4 毛笔 v2 采用方向性矢量包络，不做流体模拟

每个样本计算一个受压力控制的接触宽度和受切线平滑控制的笔头方向，生成左右边界；转角使用有限 miter/round join，禁止无限尖刺。毫丝只作为少量确定性内部纹理，不参与物理状态。

### 5.5 压力策略：取消长时硬下限，改为短时稳定 + 单调曲线

v2 铅笔和毛笔不再使用 1500ms/0.50 攻击地板。改为：

1. 保留现有滤波；
2. 对前 40～80ms 或前 2～3 个有效样本做平滑引导，不把低压抬到固定中压；
3. 使用笔形专属单调响应曲线；
4. 继续在创建时烘焙用户灵敏度，历史元素不随设置变化；
5. 真实压力始终保持有序：输入 `p1 < p2` 时编码后也必须 `<` 或 `≤`，不得反转。

具体常数由真实设备回放确定，计划禁止实现者凭肉眼一次性写死。

## 6. 被否决的方案

| 方案 | 否决原因 |
| --- | --- |
| 继续只调 `thinning/smoothing/taper` | 无法补出颗粒、方向性笔头和介质沉积，最多得到另一种平滑带状线 |
| 为 v2 再写一个更复杂 shader，同时保留颗粒 fallback | 三端会长期呈现两种效果，测试与维护成本翻倍；鸿蒙 shader 能力仍有不确定性 |
| 直接接入 Huawei Pen Suite 画布 | Pen Suite 是完整画布/工具栏/文件体系，会替换现有 Scene、Excalidraw、协作和导出链，不是渲染器插件 |
| 使用 HarmonyOS 平台分支实现毛笔 | 违反共享代码禁止平台判断的架构约束，且 Web/Windows 会退化 |
| 首版加入倾斜持久化 | 目标设备可靠性未证实，过早增加 schema、协作和文档体积 |
| 真实水墨/宣纸流体模拟 | 超出比赛项目收益边界，难以在交互帧预算和跨端一致性内完成 |
| 每个颗粒/毫丝一次 `drawPath` | 长笔画调用数线性爆炸，远端湿墨和 1000 元素场景不可接受 |

## 7. 成功判据

自然介质版本只有同时满足以下条件才算成功：

- 无标签视觉矩阵中，至少 4/5 测试者能分别识别铅笔和软头毛笔笔；
- 铅笔的主要压力变化体现为浓度，毛笔的主要压力变化体现为宽度；
- 新铅笔和新毛笔不再受 1.5 秒压力地板影响；
- 本地湿墨、远端湿墨、静态元素在分块边界上无可见接缝，提交后无纹理重排；
- `.markdraw`、Excalidraw JSON、SQLite、协作快照往返后渲染版本和压力语义不丢；
- v1 历史元素像素摘要保持基线；
- Web、Windows、HarmonyOS 的 v2 主算法相同，无平台专属视觉实现；
- 结构门禁和 Profile 性能门禁全部通过。

## 8. 参考资料

- [Goodnotes Pen tool](https://support.goodnotes.com/hc/en-us/articles/7353756785679-Using-the-Pen-tool)
- [Procreate Brush Studio](https://help.procreate.com/procreate/handbook/5.3/brushes/brush-studio)
- [Procreate Brush Studio Settings](https://help.procreate.com/procreate/handbook/5.3/brushes/brush-studio-settings)
- [Wacom Ink Geometry Pipeline & Rendering](https://developer-docs.wacom.com/docs/sdk-for-ink/guides/rendering/)
- [Wacom BrushGL](https://developer-docs.wacom.com/docs/sdk-for-ink/api/digital-ink-web/Rendering.WebGL.BrushGL/)
- [Apple PKInkingTool](https://developer.apple.com/documentation/pencilkit/pkinkingtoolreference?language=objc)
- [Flutter fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)
- [Flutter PointerEvent tilt](https://api.flutter.dev/flutter/gestures/PointerEvent/tilt.html)
- [Flutter PointerEvent orientation](https://api.flutter.dev/flutter/gestures/PointerEvent/orientation.html)
- [Adobe Fresco pressure curve](https://helpx.adobe.com/fresco/using/pressure-curve.html)
- [Wacom Universal Ink Model encoding](https://developer-docs.wacom.com/docs/sdk-for-ink/uim/encoding/)
- [Observational Models of Graphite Pencil Materials](https://diglib.eg.org/items/0f0d430c-7ac9-4aba-b96a-77bb6836cbc4f)
- [Computer-Generated Graphite Pencil Rendering](https://diglib.eg.org/items/929edc11-8bac-4479-98ed-c2912fcec395)
