# 铅笔与毛笔自然介质渲染重构执行计划

> 版本：v2（二轮对抗审查修订）
> 日期：2026-08-30
> 计划基线：`main@3eb2b97`
> 计划分支：`plan/pencil-brush-natural-media-redesign`
> 实施分支建议：`feature/pencil-brush-natural-media-v2`
> 调研依据：[专项调研](../research/2026-08-30-pencil-brush-natural-media-research.md)
> 审查记录：[首轮计划审查](../specs/2026-08-30-pencil-brush-natural-media-review.md)、[二轮对抗审查](../specs/2026-08-30-pencil-brush-natural-media-review-round2.md)

## 0. 执行摘要

本计划不再通过调高压感、扩大 taper 或增强噪声来“模拟”铅笔和毛笔，而是引入两个版本化、确定性的专用渲染器：

- 铅笔 v2：HB 日常书写效果，压力主要控制石墨密度，宽度只适度变化；
- 毛笔 v2：软头毛笔笔效果，压力主要控制笔肚宽度，方向和转折控制包络；
- 其他三支笔与全部历史笔迹保持现有 v1 外观；
- 新效果由同一个共享采样器驱动 Canvas、本地湿墨、远端湿墨和 SVG；
- 新铅笔使用确定性复合 Path 颗粒，不依赖 shader，不新增第三方包；
- 不在未验证设备能力前引入 tilt/orientation schema；
- 用视觉语义、数据往返、分块连续性和 Profile 性能四类门禁替代“像素不同即可”。

计划共 14 个任务，建议 17～24 人日。T0 是产品目标门，T1～T3 是共同基础，T4/T5 分别完成铅笔和毛笔，T6～T10 补齐湿墨、导出、UI 和兼容，T11～T13 收口验收与文档。

### 0.1 v2 修订摘要

本版关闭二轮审查的 1 个 Critical 和 5 个 Important：

1. 将跨端种子算法改为 dart2js 安全的 16 位拆分乘法 + `.toUnsigned(32)`，补 Chrome 实跑门禁；
2. 不预建静态缓存，先增加 plan 构建计数与同机性能基线；只有实测越线才启用条件缓存任务；
3. 补齐默认 `buildPreviewElement`、`ActiveFreedrawView`、远端临时元素和 `_sameStyle` 四处 renderVersion 管道；
4. 明确默认预览路径与 layered/live ink feature flag 两套验收口径；
5. 将自然介质指标的算式、fixture、采样区域和阈值冻结列为 T0 产物，重写 N2/N5/N8/N11/N12/N13/N16/N18；
6. 毛笔方向滞后改为有限窗口，不允许递归历史状态；分块 context 深度覆盖窗口，并比较实际切线/包络顶点而非只比较 key。

同时吸收会影响实现正确性的 Minor：数值版本解析语义、primitive 记录、渲染层唯一分发、边界常数同源、v1 压力回归、T4/T5 合入顺序、Profile 基线程序、`.markdraw` 示例和盲测协议。

## 1. 范围与非目标

### 1.1 本期范围

1. 新铅笔和新毛笔的 v2 渲染算法；
2. 压力响应重构，移除两者的 1.5 秒硬地板；
3. 静态、本地湿墨、远端湿墨、协作提交的一致性；
4. `.markdraw`、Excalidraw JSON、SQLite 与 SVG 往返/导出；
5. v1/v2 兼容和混合版本协作降级；
6. 视觉、结构、性能和跨端验收工具；
7. 对 ADR-020 的增补或取代记录。

### 1.2 明确不做

- 不实现宣纸扩散、含墨量、水分和蘸墨状态；
- 不实现 2H/HB/2B 多硬度笔盒；
- 不实现枯笔/润笔多预设；
- 不实现 tilt/orientation 持久化；
- 不替换 FlowMuse 画布为 Huawei Pen Suite；
- 不改服务端，不增数据库表，不引入第三方渲染依赖；
- 不自动升级旧元素外观；
- 不修改圆珠笔、钢笔和荧光笔的既有视觉语义。

## 2. 必须先锁定的产品裁决

实现者不得跳过 T0 直接调参。需要用户在固定测试纸上确认以下默认目标：

| 笔形 | 本期默认目标 | 可接受特征 | 不接受特征 |
| --- | --- | --- | --- |
| 铅笔 | HB 日常书写 | 浅灰石墨、低压留白、重压更黑、重复覆盖加深 | 喷枪、规则横纹、纯半透明钢笔、低压消失 |
| 毛笔 | 软头毛笔笔 | 提按清楚、转折有笔肚、起收不对称、少量毫丝 | 对称矛尖、马克笔粗线、宣纸水墨、转角尖刺 |

若用户期待的是“真实传统毛笔 + 宣纸渗墨”，必须另立项目，不得通过不断扩张本计划实现。

## 3. 架构设计

### 3.1 版本字段

在 `customData.flowMuse` 新增：

```json
{
  "brushType": "pencil",
  "pressureEncoding": 1,
  "brushRenderVersion": 2
}
```

规则：

- 缺失或非法值统一解释为 v1；
- JSON 数值按 `value is num && value == 1/2` 判定，避免 VM 与 dart2js 对 `1.0 is int` 的差异；其他类型和值非法；
- 新建 pencil/brushPen 写 2；其他笔不写或写 1，首版建议不写；
- copy/duplicate 保留版本；
- 导入旧数据不补写；
- 修改已有元素不改变版本；
- v1 元素永远走现有 `FreedrawRenderer`；
- v2 仅对 pencil/brushPen 有效，非法组合安全回退 v1；
- 字段不是权限或安全数据，外部 Excalidraw JSON 可保留。

建议新增值对象：

```dart
enum BrushRenderVersion { classicV1, naturalMediaV2 }
```

并提供唯一 codec：

- `brushRenderVersionFromCustomData`；
- `customDataWithFreedrawRender(..., renderVersion:)`；
- 不允许其他模块手写嵌套 Map。

### 3.2 渲染分发

`BrushRenderProfile` 仍负责共有样式与边界，但增加明确的 renderer family：

```text
classicV1     -> FreedrawRenderer
pencilV2      -> PencilStrokeRendererV2
brushPenV2    -> BrushPenStrokeRendererV2
```

renderer family 是 core 层纯枚举/值，不持有 renderer 实例，也不 import rendering。唯一 dispatch switch 位于 rendering 层的元素渲染入口；StaticCanvasPainter、本地湿墨、远端湿墨和 SVG 通过该入口或纯数据 plan 消费结果。ADR-021 要明确：这是按版本化 family 的单点分发，不是允许调用方重新散落 brushType 特判。

禁止：

- 在 StaticCanvasPainter、本地湿墨和远端湿墨分别按 brushType 写 switch；
- 把 v2 特判继续堆进 `FreedrawRenderer.draw()`；
- 让 SVG 自己发明另一套采样常数；
- 通过平台判断选择视觉算法。

### 3.3 共享采样器

新增纯数据层 `NaturalMediaStrokeSampler`，输入：

- element/stroke id；
- 按顺序的 indexed points；
- encoded pressures；
- nominal strokeWidth；
- brushType；
- completeness/taper phase；
- 当前分段拥有的边索引范围。

输出不可变 `NaturalMediaStrokePlan`：

- 已校验的采样点；
- 每点 position/tangent/normal/pressure/curvature；
- 每条原始边的稳定 index；
- 边内确定性采样序号；
- Canvas、SVG 和测试共同消费的 primitive 记录（kind/channel/key/几何参数/paint bucket）；
- 可视 bounds；
- 结构计数（sample/particle/path）；
- 是否命中降级或上限。

确定性规则：

```text
strokeSeed = fnv1a32(utf8("flowmuse-natural-media-v2|" + strokeId))
sampleSeed = mix32(strokeSeed, edgeStartIndex, sampleOrdinal, channel)
```

禁止把 `h * constant & 0xffffffff` 当作跨端安全乘法：dart2js 会先用 53 位 double 计算，FNV 乘积可超过 2^53，低位在掩码前已经丢失。规范实现必须使用下面的 16 位拆分乘法，并在每个公开结果处 `.toUnsigned(32)`：

```dart
int mul32(int a, int b) {
  final au = a.toUnsigned(32);
  final bu = b.toUnsigned(32);
  final a0 = au & 0xffff;
  final a1 = au >>> 16;
  final b0 = bu & 0xffff;
  final b1 = bu >>> 16;
  final low = a0 * b0;
  final cross = ((a1 * b0 + a0 * b1) & 0xffff) << 16;
  return (low + cross).toUnsigned(32);
}

int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash.toUnsigned(32);
}

int fmix32(int value) {
  var x = value.toUnsigned(32);
  x = (x ^ (x >>> 16)).toUnsigned(32);
  x = mul32(x, 0x85ebca6b);
  x = (x ^ (x >>> 13)).toUnsigned(32);
  x = mul32(x, 0xc2b2ae35);
  return (x ^ (x >>> 16)).toUnsigned(32);
}

int mix32(int seed, int edge, int ordinal, int channel) => fmix32(
  fmix32(fmix32(seed ^ edge) ^ ordinal) ^ channel,
);
```

以上代码是协议级参考语义；允许等价优化，但必须与它的固定向量一致。随机小数从结果低 24 位除以 `0x01000000` 得到。测试固化至少 8 组向量，包含空字符串、`abc`、bit31 置位、长 strokeId 和最大合法 edge/ordinal，并同时在 VM 与 Chrome 执行。禁止使用 Dart `String.hashCode`、`Object.hash`、裸大整数乘法或默认 `Random`。种子不使用当前时间、房间/用户 id，也不依赖分块级别。

### 3.4 分块所有权规则

远端冻结块必须与整笔静态渲染生成同一组 primitive。每条边只允许一个分段拥有：

- segment 可携带前后相邻点作为 tangent context；
- context 点只参与导数，不拥有绘制权；
- 以 `edgeStartIndex` 判定 primitive 归属；
- 冻结块、tail 和完整元素对同一 edge 生成相同 sampleSeed；
- 交界处的 join 由较后 edge 统一拥有；
- 不允许每块重置粒子相位、毫丝通道或起收状态。

毛笔方向滞后只允许固定窗口的有限 stencil，不允许递归 IIR 状态或依赖整笔历史。首版窗口固定为当前 edge + 前 2 条 edge（窗口宽度 3）；segment 因此至少携带 2 个 leading context point，若为 join/tangent 计算需要未来方向，可再携带 1 个 trailing context point。笔画起点缺少历史 edge 时，缺失槽位复用最早一个有效 edge 的单位切线；重复点或零长 edge 向前寻找最近的有效切线；完全没有有效 edge 的单点直接走 dot/teardrop 退化，不虚构方向。T0 可以校准窗口权重，但不得扩大窗口而不同时扩大 context 深度。

为此需要让 `RemoteWetInkSegment` 暴露 indexed context、owned edge range 和 primitive channel。固定 channel 编号必须写入测试（例如 base=0、pencilLow/Medium/Heavy=1/2/3、brushBody/Strand=4/5，最终枚举以 T2 代码为准），join key 归属于较后 edge。若实现者选择别的数据结构，必须同时证明：

1. 64 点边界前后 primitive key 集合完全相等；
2. 分块与整笔在边界处的滤波切线、包络顶点和 paint bucket 逐值相等（同运行时容差 `1e-9`）；
3. 低 opacity 像素结果没有重复合成接缝。

### 3.5 压力响应

v2 不使用 `_pressureAttackMs=1500/_pressureAttackLevel=.50`。

输入链规则：

1. 原始压力仍经过既有平台策略和 OneEuro 过滤；
2. 起笔稳定只处理前 2～3 个有效样本，或不超过 80ms；
3. 稳定器只能在相邻值间插值，禁止把真实低压抬到固定 0.5；
4. 编码保持单调、有限、范围 [0,1]；
5. 用户 pressure sensitivity 仍在创建时烘焙；
6. 铅笔曲线将压力更多映射到 density，宽度变化受限；
7. 毛笔曲线将压力主要映射到 width，最低有效宽度仍可见；
8. v1 创建路径保持当前攻击补偿，避免本期改写其他笔/旧语义；
9. 任何常数必须来自 fixture 和至少一台真实压力设备的回放，不准只凭鼠标调参。

建议第一组候选（不是验收常数）：

```text
pencilDensity = 0.18 + 0.72 * pow(p, 0.85)
pencilWidth   = base * (0.82 + 0.28 * p)
brushWidth    = base * (0.16 + 1.34 * pow(p, 0.72))
```

实现前用 T0 fixture 校准，最终参数写入 profile 并由测试冻结。

### 3.6 铅笔 v2 绘制模型

每笔最多四个主要 draw：

1. 一条低 alpha、轻微不规则的连续基底；
2. 低密度颗粒复合 Path；
3. 中密度颗粒复合 Path；
4. 重压核心颗粒复合 Path（仅有重压区时存在）。

粒子规则：

- 沿每条 edge 按局部宽度决定 spacing，边内等距采样；
- 法向散布由稳定 seed 决定；
- 形状为短小椭圆/不规则线粒，长轴大致沿切线；
- pressure 同时控制激活密度桶、alpha 和轻微尺寸变化；
- 边缘粒子允许少量超出基底，形成破碎边缘；`pencilScatterRadiusScale` 与 `pencilParticleOverhang` 必须在 profile 中与 bounds 共用，初始保守上限为局部宽度的 0.45，实际值由 T0 校准但不得在 renderer/bounds 分别维护；
- 相同元素在重绘、缩放、平移、协作端和 SVG 中 seed 不变；
- 同色重复笔画使用正常 sourceOver，自然变深；
- 单笔内部不同 density bucket 不得因重叠造成压力非单调。

硬上限初始值：

| 场景 | 粒子上限 | 主要 draw 上限 |
| --- | ---: | ---: |
| 本地活动湿墨 | 1,024 | 4 |
| 远端 tail | 1,024 | 4/可见 owned segment |
| 单个静态元素 | 4,096 | 4 |
| SVG 单元素 | 4,096 primitive，优先合并 path | 4 path |

超过上限后按稳定步长降采样，不能截断笔尾，也不能改变已有区域的粒子位置。

### 3.7 毛笔 v2 绘制模型

每笔最多两个主要 draw：

1. 主体方向性包络；
2. 可选毫丝细节复合 Path。

几何规则：

- 对 pressure 计算接触半宽；
- 对 tangent 使用 §3.4 的三 edge 有限 stencil，形成短距离方向滞后，不得按时间或递归历史状态引入最终结果差异；
- 左右边界按 normal 和 contact width 生成；
- 转折 join 使用受限 miter，`brushMiterLimit` 初始为 1.5，超过阈值自动 round/bevel；常数进入 profile 并由 `elementVisualBounds` 共用，禁止 renderer 与 bounds 各写一份；
- 起笔形状由首 2～4 个真实压力样本决定；
- 收笔形状由尾部压力下降与 `isComplete` 决定；
- 没有压力下降时不强制生成 6×size 矛尖；
- 短划和单点有专门 dot/teardrop 退化；
- 毫丝为 3 个稳定通道以内的局部细节，不做独立毛发物理模拟；
- 默认润笔，毫丝不得把主体切成梳子。

边界必须直接由 sampler/renderer 给出，`elementVisualBounds` 不能继续只依赖 classic thinning 公式。

### 3.8 SVG 和外部格式

- Excalidraw JSON：保留 `brushRenderVersion`，未知客户端忽略；
- `.markdraw`：freedraw 行新增 `pressure-encoded` 与 `render=v2`；旧文本缺失时分别按 legacy/v1；
- SVG：使用同一 primitive plan 写 1～4 个 path，不使用随机 pattern 近似 v2；
- PNG：复用 Canvas 主渲染，视为最高保真外部产物；
- 外部 sanitizer：保留 brushRenderVersion/pressureEncoding，继续只剥离隐私字段；
- SVG 查看器不支持高级 blend 时不影响 v2，因为 v2 不依赖自定义 shader/filter；
- `.markdraw` parser 对未知 render 值产生 warning 并回退 v1，不抛整文档异常。

`.markdraw` 规范示例：

```text
freedraw id=path1 points=[...] pressure=[...] no-simulate-pressure brush=pencil pressure-encoded render=v2
```

- 仅当 `pressureEncoding==1` 时写 `pressure-encoded`；
- 仅当 renderVersion==2 时写 `render=v2`；v1 省略；
- parser 读取未知 `render=` 值时通过既有 `ParseWarning` 管道报告一次并回退 v1；
- 未知普通属性仍遵循现有容错策略，不为本任务重写整个 PropertyBag。

### 3.9 协作和 live ink 兼容

`LiveInkStyle` 新增可选 `renderVersion`：

- `toJson` 对 v2 写 2；
- `fromJson` 缺失时取 1；存在但不是 `num == 1/2` 时拒绝该 live chunk；禁止使用裸 `is int`；
- 不修改 `LiveInkChunk.protocolVersion=2`，因为只是 style 内可选字段；
- 服务端只转发加密正文，无服务端变更；
- v1 客户端忽略未知 style 字段并按 v1 预览；
- v2 客户端收到旧客户端缺字段时按 v1 预览，提交后不跳变；
- final scene 元素的 `brushRenderVersion` 与 live style 必须一致。

同一 stroke 后续 chunk 的 `_sameStyle` 必须把 `renderVersion` 纳入比较；中途版本变化按 `invalidChunk` 丢弃，不能在一个缓存 stroke 内混用两套 renderer。

### 3.10 默认预览路径与 feature flag 裁决

本功能不顺带改变现有 feature flag 默认值：

- `FLOWMUSE_LAYERED_WET_INK=false` 的默认生产路径必须支持 v2，`buildPreviewElement` 与 final element 使用相同 renderVersion/brush/pressure 语义；
- `FLOWMUSE_LAYERED_WET_INK=true` 时，本地 `LocalWetInkPainter` 走同一 dispatcher，并维持既有高频路径门禁；
- 远端 live ink 验收必须同时设置 `FLOWMUSE_LAYERED_WET_INK=true`、`FLOWMUSE_LIVE_INK_V2=true`，且服务端协议版本 ≥2；
- flag 未开启时仍要验证 final scene 协作一致性，但不能声称已验证远端 live ink；
- T6 同时覆盖默认 preview 与 layered 本地湿墨，T7/T12 显式覆盖开启 flag 的远端路径。

## 4. 任务依赖

```text
T0 视觉目标/基线
 └─ T1 版本与格式契约
     ├─ T2 共享采样器
     │   ├─ T4 铅笔 v2
     │   └─ T5 毛笔 v2
     └─ T3 压力响应 v2
          ├─ T4
          └─ T5
T4 + T5 ─ T6 本地湿墨 ─ T7 远端湿墨/协作
T4 + T5 ─ T8 静态分发/边界 ─ T9 SVG/格式
T3 + T4 + T5 ─ T10 UI/预览纸
T6..T10 ─ T11 自动化验收 ─ T12 跨端人工验收 ─ T13 文档收口
```

T4 和 T5 可在 T1～T3 合并后并行开发各自专用文件，但共用 dispatcher/profile/bounds 的合入按 T4→T5 串行；T6～T10 不得在两个 renderer API 未冻结前抢跑。

阶段复核门：

- T0：用户确认目标纸和纯 Path spike 后才能进入生产实现；
- T2：独立复核 `mul32/fnv1a32/fmix32` 代码与 VM/Chrome 实跑结果，不能只看测试名称；
- T4：若触发 T4-C，独立复核缓存键和元素编辑失效；未触发则不审不存在的缓存；
- T7：独立复核 63/64/65/127/128/129 分块、乱序补洞、低 opacity 接缝和 `_sameStyle`；
- T11：复核指标实现是否仍与 T0 冻结公式相同，禁止在实现不达标时放宽定义。

## 5. 任务卡

### T0：锁定视觉目标与失败基线

目标：把“符合预期”转成固定输入和可复查产物。

主要文件：

- 扩展 `test/features/whiteboard/editor_core/fixtures/brush_stroke_fixtures.dart`；
- 新增 `test/features/whiteboard/editor_core/rendering/natural_media_visual_sheet_test.dart`；
- 新增测试工具 `natural_media_image_metrics.dart`；
- 产物输出到 `build/natural_media_baseline/`，不提交生成图。

工作项：

1. 铅笔 fixture：轻/中/重恒压、压力坡道、慢/快等轨迹、交叉排线、重复覆盖、短点和 90° 转角；
2. 毛笔 fixture：横、竖、撇、捺、点、折、钩、提，另加压力坡道、S 曲线、短点；
3. 生成 v1 有标签和无标签两套测试纸；
4. 记录 ink coverage、平均亮度、宽度剖面、边缘不规则度、draw/path 数；
5. 同一几何轨迹生成稀疏/正常/密集三种采样率，防止效果依赖设备事件频率；
6. 用户确认 §2 的 HB/软头毛笔目标；
7. 在 `tool/natural_media_spike/` 做两个可删除原型：≤4 Path 的铅笔颗粒和 ≤2 Path 的方向性毛笔包络；只用固定 fixture，不接生产 Scene；
8. 原型同时跑 1k/16k 点结构与耗时探针，证明纯 Path 路线在进入数据契约前可行；
9. 把当前视觉问题截图编号写入测试纸说明，不把第三方截图复制进仓库；
10. T0 完成后删除 spike 代码，只保留确认过的 fixture、指标和产物说明，避免实验实现进入生产依赖。

T0 必须把下列指标实现、fixture 和阈值写进 `natural_media_image_metrics.dart` 并随基线冻结；T11 只能复用，不得重新挑更宽松的口径：

1. **渲染底图**：白色不透明背景、固定黑色笔、opacity=100%、zoom=1、devicePixelRatio=1；另设透明背景 fixture 专测 alpha/接缝；
2. **着墨像素**：亮度 `Y=0.2126R+0.7152G+0.0722B`，`darkness=1-Y/255`；`darkness>=16/255` 计为 ink；
3. **共同中心带浓度**：沿弧长 40%～60% 取样，以轻/重两笔有效宽度较小值的 45% 为共同半宽，比较该区域平均 darkness；N2 不使用总 coverage，避免靠增宽作弊；
4. **有效宽度**：在弧长 40%～60% 每 2% 处做法向扫描，以 `darkness>=16/255` 的最外像素距离为宽度，取中位数；N3/N6 共用；
5. **边缘不规则度**：按固定弧长步长记录左右有效边缘距离，减去 9 样本移动平均后计算 RMS/局部宽度；阈值由 T0 目标原型冻结；
6. **固定周期峰**：对上一步残差在 lag 2～32 做归一化自相关，排除 lag 0 后的最大正峰不得超过 T0 冻结阈值；禁止用肉眼替代；
7. **弧长前缀**：所谓“前 90%”统一指 owned edge 的累计原始弧长终点 `<=0.9*totalLength`，不是图片像素排序；
8. **像素差**：同尺寸图像中 `|darknessA-darknessB|>=8/255` 的像素数除以两图 ink union；仅在固定 mask/弧长前缀内计算；
9. **SVG 趋势**：Canvas 与 Chromium SVG 分别比较轻/重平均 darkness 排序及毛笔轻/重有效宽度排序，要求排序一致，不使用“看起来同向”；
10. **分块结构**：除 primitive key multiset 外，还比较 channel、paint bucket、滤波切线和包络顶点；key 相等不能代替几何相等。

验收：

- 当前铅笔的压力主要改变宽度、边缘不规则度不足被指标检出；
- 当前毛笔的固定对称 taper 和转角形态被 fixture 呈现；
- 纯 Path 原型在无 shader、无 saveLayer 条件下得到用户认可，且 16k 点没有 O(n²) 趋势；若不通过，停止后续任务并修订技术路线；
- 稀疏/正常/密集输入在同一轨迹上的共同中心带浓度与有效宽度偏差均不超过 T0 冻结阈值；
- 上述 10 项指标均已有代码、注释、固定 fixture 和失败示例，T11 不再自行定义；
- 基线测试只记录，不误把 v1 当成 v2 合格值；
- 用户在计划“目标确认记录”填写确认结论。

建议提交：`test: 建立铅笔与毛笔自然介质视觉基线`

### T1：建立版本、序列化和混合客户端契约

目标：新外观不改写旧笔迹，所有往返链路不丢版本。

主要文件：

- `brush_render_profile.dart` 或独立 `brush_render_version.dart`；
- `brush_type.dart`；
- `sketch_line_serializer.dart`；
- `sketch_line_parser.dart`；
- `live_ink_chunk.dart`；
- `freedraw_tool.dart` 与 `markdraw_controller.dart` 的新笔创建/预览构造点；
- Excalidraw codec 相关测试；
- 数据模型文档。

工作项：

1. 新增 `BrushRenderVersion` 与 customData codec；
2. 新建 pencil/brushPen 元数据默认 v2，旧元素缺失为 v1；
3. `.markdraw` 新增 `pressure-encoded` 和 `render=v2`；
4. 修复当前 `.markdraw` 丢 pressureEncoding 的缺口；
5. `LiveInkStyle.renderVersion` 可选字段，缺失为 1；
6. 非法值、未知版本、非法 brush/version 组合均有安全回退；
7. 测试 nested flowMuse merge，不覆盖 collaborationOwner/pageId/brushType；
8. `.markdraw` 按 §3.8 示例输出；未知 render 走 ParseWarning 并回退 v1；
9. 测试旧文本、旧 JSON、旧 live chunk 可读；
10. 所有版本数值按 `num == 1/2` 解析，增加 `1`、`1.0`、字符串、null、NaN/Infinity（可构造路径）的兼容测试。

验收：

- v1 JSON 逐字段往返不被补写/改观；
- v2 `.markdraw → scene → .markdraw` 保留 brush、pressure、pressureEncoding、renderVersion；
- 新客户端收到缺 renderVersion 的 live chunk 按 v1；
- 服务端与协议版本号零改动；
- 外部 sanitizer 继续保留非隐私笔刷字段。

建议提交：`feat: 建立自然介质笔刷版本与格式契约`

### T2：实现确定性共享采样器

目标：为两支笔和四条渲染链提供唯一几何采样真源。

主要文件：

- 新增 `rendering/natural_media/natural_media_stroke_sampler.dart`；
- 新增 `natural_media_stroke_plan.dart`；
- 新增 `deterministic_stroke_seed.dart`；
- 新增对应单测。

工作项：

1. 非有限坐标/压力过滤；
2. 单点、重复点、零长 edge 退化；
3. 点序 tangent/normal/curvature 计算；
4. edge-local 等距采样；
5. FNV-1a 32 + mix32 的 seed/edge/ordinal/channel 稳定哈希与固定测试向量；
6. 参考实现使用 `mul32`，所有 mix 乘法禁止裸大整数乘法；
7. primitive 记录及稳定 channel/join key；
8. owned edge 与 context edge 分离；
9. sample/primitive 硬上限和稳定降采样；
10. O(n) 统计探针；
11. 可视 bounds 增量合并；
12. 输出不可变，输入列表不被修改。

验收：

- 同输入 100 次输出字节级/字段级一致；
- VM 与 Chrome 实际执行同一固定向量并逐值一致；源码门禁禁止 `hashCode`/`Object.hash`/默认 `Random` 及未经 `mul32` 的 32 位混合乘法；
- 完整笔与任意 64 点分块的 owned primitive key 并集完全一致且无重复；
- 固定窗口毛笔方向在整笔/分块边界的切线和包络输入逐值一致；
- 1k/16k 线性度比值 ≤20；
- 非有限、重复、乱序 context 不死循环、不越界；
- 上限降采样保留首尾与所有压力极值段。

建议提交：`feat: 新增确定性自然介质笔画采样器`

### T3：重构 v2 压力响应与起笔稳定

目标：恢复轻写表达，同时消除真机起笔闪变。

主要文件：

- `stroke_input_modeler.dart`；
- `markdraw_controller.dart`；
- `brush_render_profile.dart`；
- `stroke_input_modeler_test.dart`；
- `freedraw_pressure_test.dart`；
- `wet_ink_preview_fidelity_test.dart`；
- 新增压力回放 fixture。

工作项：

1. 将 v1 攻击补偿与 v2 稳定器显式分流；
2. v2 最长 80ms/3 样本稳定器；
3. pencil density/width 与 brush width 响应函数收进单一 profile；
4. 继续复用 pressure sensitivity 烘焙入口；
5. 用 OPD2404 已有慢爬压力序列补回放测试；
6. 增加“有意轻写”序列，防止重新引入压力地板；
7. 鼠标/触摸模拟压力保持确定性；
8. 日志不得记录原始压力序列，仅测试 fixture 可包含合成值。

既有“铅笔/毛笔起笔抬到 0.5”测试不得删除：改为显式构造 renderVersion=1，继续锁定 v1 回退；另增 renderVersion=2 的轻写与慢爬用例。

验收：

- 轻压 0.2 在 1.5 秒内不被抬成 0.5；
- 慢爬序列的相邻可视宽度/密度变化无单帧 >15% 跳变；
- 压力响应单调；
- v1 fixture 输出不变；
- 切换 sensitivity 不改历史笔迹。

建议提交：`fix: 以笔形压力曲线替代自然介质起笔硬地板`

### T4：实现铅笔 v2

目标：实现跨端一致的 HB 书写铅笔。

主要文件：

- 新增 `pencil_stroke_renderer_v2.dart`；
- `element_renderer.dart`；
- `rough_canvas_adapter.dart`/抽象 adapter；
- `element_visual_bounds.dart`；
- 新增铅笔 renderer/像素测试。

工作项：

1. 基底 Path；
2. 三个确定性密度桶；
3. edge/point primitive 所有权；
4. 压力控制 density 为主、width 为辅；
5. 稳定边缘破碎和法向散布；
6. 单点、短划、尖转角退化；
7. 粒子硬上限与稳定降采样；
8. v2 不申请 shader、不创建 saveLayer；
9. 可视 bounds 含 scatter/AA；
10. 重复覆盖、透明度和聚焦 dim 像素测试；
11. 增加 `planBuildCount`/primitiveCount 测量探针，证明普通静态重绘的实际构造成本；本任务默认不新增静态缓存。

验收：

- p=0.2→0.8：平均墨色明显变深，中心有效宽度增长不超过 35%；
- 按 T0“共同中心带浓度”口径，p=0.8 的平均 darkness 至少比 p=0.2 高 35%，不得用总 coverage 或宽度增长作弊；
- 三次重复覆盖亮度单调降低；
- 边缘不规则度高于 v1 基线且无周期性横纹；
- 100 次重绘 primitive 摘要一致；
- 单元素 draw ≤4、saveLayer=0、particle ≤4096；
- 同机同构建的 1000 元素静态压力场景满足 §T12 门禁，或触发下面的 T4-C 条件任务；
- v1 铅笔像素摘要不变。

**T4-C（仅性能实测触发，不预建）**：若 T0/T4 同机 Profile 证明 1000 元素浏览 P95 相对 main 退化超过 20%，才增加最小的有界 plan/Path 缓存。缓存键至少包含 element id、version、versionNonce、renderVersion 和会影响几何的 profile 版本；必须有命中/失效计数与“编辑元素后不得回放旧 plan”测试。若降低粒子密度即可达标，优先调低上限，不引入缓存。触发后工作量另加 2～4 人日并在实施记录说明；未触发则不写缓存代码。

建议提交：`feat: 实现确定性 HB 铅笔渲染器 v2`

### T5：实现毛笔 v2

目标：实现适合中文书写的软头毛笔笔。

主要文件：

- 新增 `brush_pen_stroke_renderer_v2.dart`；
- 新增 `directional_brush_envelope.dart`；
- `element_renderer.dart`；
- `element_visual_bounds.dart`；
- 新增毛笔几何与像素测试。

工作项：

1. 压力接触宽度；
2. §3.4 三 edge 固定 stencil 的方向滞后，不引入递归状态；
3. 左右边界和受限 join；
4. 真实压力驱动的起收；
5. 单点/短线 teardrop 退化；
6. 最多三通道毫丝细节；
7. 急转自交/尖刺防护；
8. 可视 bounds；
9. 不透明与元素低 opacity 两种接缝测试；
10. 横竖撇捺点折钩提 fixture。

验收：

- p=0.2→0.8 的中段宽度比 ≥2.2；
- 轻压线持续可见，不受 0.5 地板影响；
- 没有尾部降压的短横不生成统一长矛尖；
- 有尾部降压的捺/提能形成自然收束；
- 90°/135° 转角无超过局部目标宽度 1.6 倍的尖刺；
- 自交检测/非有限坐标为 0；
- 分块 context 深度覆盖完整 stencil，边界切线/包络顶点与整笔相等；
- 静态整笔 drawPath ≤2、saveLayer=0；远端每个发生变化的 owned segment 录制时 ≤2 drawPath，稳定帧只回放既有 Picture + 有限 tail；
- v1 毛笔像素摘要不变。

建议提交：`feat: 实现方向性软头毛笔渲染器 v2`

### T6：统一静态画布和本地湿墨

目标：本地书写中看到的就是提交后的 v2。

主要文件：

- `element_renderer.dart`；
- `local_wet_ink_painter.dart`；
- `local_wet_ink_state.dart`；
- `editor/tools/freedraw_tool.dart`；
- `markdraw_controller.dart`；
- 本地湿墨测试。

工作项：

1. `ActiveFreedrawView` 冻结 renderVersion；
2. 默认 `buildPreviewElement` 显式携带 renderVersion，活动笔画与提交元素使用同一 renderer dispatch；
3. layered `LocalWetInkPainter` 同样从 view 获取 renderVersion；
4. predicted points 只参与湿墨，提交仍只含 actual；
5. 粒子 seed 使用 strokeId，预测点回撤不移动已确认 primitive；
6. live strokeId 与最终 ElementId 必须相同并以测试断言，否则提交会重播种；
7. isComplete 只影响真正的尾端收束，不重排前段；
8. 切换笔形中途不改当前 stroke；
9. 清理/取消/undo 生命周期完整；
10. 分别运行默认 preview（flag=false）与 layered painter（flag=true）测试，不用其中一条替代另一条。

验收：

- terminal 湿墨与静态提交：已确认区域 primitive key 完全一致；
- 提交只允许最新尾部补全；按 T0 “弧长前 90%”mask 计算的像素差 ≤1%；
- 快速切笔不改当前笔；
- predicted 回滚不造成已确认铅笔颗粒跳动；
- layered 路径无新增页面 setState/scene 重建；默认 preview 路径只要求不比 main 新增重建次数，因为其全量重绘是既有行为。

建议提交：`feat: 对齐自然介质本地湿墨与静态渲染`

### T7：统一远端湿墨、缓存和混合版本协作

目标：远端长笔无 64 点周期接缝，旧客户端可安全共存。

主要文件：

- `live_ink_chunk.dart`；
- `remote_wet_ink_store.dart`；
- `remote_wet_ink_painter.dart`；
- `whiteboard_page.dart` live style 构造；
- collaboration/store/painter 测试。

工作项：

1. style 传 renderVersion；
2. `_drawSegment` 临时元素/dispatcher 显式接收 live style renderVersion，不再只靠 brushType 参数；
3. `_sameStyle` 纳入 renderVersion，阻断同 stroke 中途换版本；
4. segment 暴露至少 2 个 leading context point、可选 trailing context、indexed context 与 owned edge range；
5. cache Picture 使用稳定 plan；
6. frozen block/tail 边界不重复 primitive；
7. block 合并不改变 seed、path 顺序、滤波切线、包络顶点或 bounds；
8. focus dim 继续包 stroke bounds，不污染 Picture；
9. v1 incoming 按 v1；v2 incoming 按 v2；
10. 缺字段/旧客户端 fixture；
11. stroke finalize 后静态元素版本一致；
12. 乱序缺口导致 context 不足时暂不固化错误 primitive；缺口补齐后只重录受影响 block；
13. 保留既有 16k/64-stroke 内存与 bounds 门禁。

验收：

- 63/64/65/127/128/129 点边界前后无重复或缺失 primitive；
- block 合并前后 primitive key/channel/bucket multiset 一致，边界滤波切线与包络顶点逐值相等；
- 远端湿墨与最终静态按 T0 “弧长前 90%”mask 计算的像素差 ≤2%；
- 低 opacity 毛笔在块边界不加深；
- 16k 长笔每帧仍只处理有限 tail，冻结 Picture 不重录未变 block；
- focus 切换不重建几何缓存；
- v1/v2 双端缺字段路径不崩溃、不错误升级。

建议提交：`feat: 保证自然介质远端湿墨分块连续`

### T8：收敛边界、命中、选择和擦除

目标：新颗粒散布和方向性包络不被裁、不出现看得见点不中。

主要文件：

- `element_visual_bounds.dart`；
- Scene hit test/selection/eraser 消费点；
- `export_bounds.dart`；
- bounds 与命中测试。

工作项：

1. v1 继续使用 profile 公式；
2. v2 使用 renderer 提供的保守解析上界，不为命中生成完整粒子 Path；
3. profile 中的 pencil scatter/overhang、brush miterLimit、最大 width response 和 AA 余量进入上界，renderer/bounds 共用同一常数；
4. remote wet ink bounds 使用同一上界；
5. sceneBounds、选区、橡皮、PNG/AI capture 全链路核对；
6. 1000 元素 bounds 不遍历历史粒子。

验收：

- 最大宽度/最大 scatter 外缘可命中、可框选、可擦除；
- PNG/选区导出不裁边；
- bounds 计算 O(1)/元素或 O(points)，不得 O(particles)；
- v1 A20/A21 全绿。

建议提交：`fix: 对齐自然介质笔刷可视边界与命中`

### T9：实现 SVG 和文本格式保真

目标：导出结果可识别为同一种笔，不要求逐像素相同。

主要文件：

- `svg_element_renderer.dart`；
- `sketch_line_serializer.dart`；
- `sketch_line_parser.dart`；
- SVG/serialization 测试。

工作项：

1. SVG 消费共享 primitive plan，不复制 sampler/seed/方向滤波；
2. pencil density buckets 合并成 path；
3. brush envelope/micro-strands 写 path；
4. seed、opacity、fill-rule 与 Canvas 对齐；
5. 限制 SVG 字节量和 path 数；
6. `.markdraw` 新旧语法与 warning；
7. Chromium 实际打开 SVG 做像素回读；
8. Excalidraw JSON 往返不改变旧顶层 schema。

验收：

- 按真实 XML `<path>` 节点计数，铅笔 ≤4、毛笔 ≤2；
- 16k 点单个 v2 铅笔 SVG 片段 ≤512 KiB、单个毛笔片段 ≤256 KiB，且生成时间维持线性；若 T0 实测证明预算不合理，必须以同一 fixture 的文件与耗时证据修订阈值，不得取消上限；
- Chromium 渲染后轻/重铅笔、毛笔提按趋势与 Canvas 同向；
- `.markdraw` 两次往返输出稳定；
- `.markdraw` 既有坐标取整不纳入像素级版本验收；N14 比较版本/压力语义与第二次文本输出稳定性，不把历史取整误报为本任务回归；
- 旧查看器不因 filter/shader 缺失而消失。

建议提交：`feat: 对齐自然介质笔刷 SVG 与 markdraw 往返`

### T10：提供目标明确的笔盒交互

目标：不堆叠复杂设置，让用户理解现有滑块的含义。

主要文件：

- `toolbar_palette_buttons.dart`；
- 笔刷设置 widget/状态；
- UI 测试。

工作项：

1. 铅笔压力滑块标签显示“浓淡响应”；
2. 毛笔显示“提按响应”；
3. 其他笔保持现有语义；
4. 不增加硬度、纸张、枯湿等未实现控件；
5. 可选加入一个小型固定预览 stroke，不建完整压力曲线编辑器；
6. 无压感设备仍显示可解释的模拟效果文案。

压力滑块继续经过既有 sensitivity 烘焙和 [0,1] 钳制，再进入 v2 单调曲线；UI 文案不得暗示曲线能恢复已被钳制的极值，也不得绕过 `LiveInkPoint` 的合法范围。

验收：

- 控件切笔不串改各笔偏好；
- 设置重启可恢复；
- UI 无溢出；
- 无能力承诺和实现不一致的选项。

建议提交：`feat: 对齐铅笔浓淡与毛笔提按设置语义`

### T11：建立自然介质自动化验收矩阵

目标：把主观观感转成足以防回归的组合证据。

新增/扩展测试：

- `natural_media_sampler_test.dart`；
- `pencil_stroke_renderer_v2_test.dart`；
- `brush_pen_stroke_renderer_v2_test.dart`；
- `natural_media_visual_sheet_test.dart`；
- `natural_media_serialization_test.dart`；
- `natural_media_wet_ink_fidelity_test.dart`；
- `natural_media_performance_test.dart`；
- 既有 brush integration/SVG/hit/export 测试。

验收矩阵：

| 编号 | 场景 | 自动化判定 |
| --- | --- | --- |
| N1 | v1 兼容 | 旧 pencil/brushPen 像素摘要与基线一致 |
| N2 | 铅笔浓淡 | 按 T0 共同中心带计算，p=.8 平均 darkness 至少比 p=.2 高 35%，不使用总面积 coverage |
| N3 | 铅笔宽度 | 按 T0 弧长 40%～60% 法向剖面中位数，p=.8 有效宽度不超过 p=.2 的 1.35 倍 |
| N4 | 铅笔叠加（辅助） | 同轨迹 1/2/3 次平均 darkness 严格递增；只防不透明基底等错误，不单独证明铅笔质感 |
| N5 | 铅笔纹理 | 按 T0 残差 RMS 公式达到冻结阈值，lag 2～32 最大自相关峰低于冻结阈值 |
| N6 | 毛笔提按 | 按 T0 弧长 40%～60% 法向剖面中位数，p=.8/p=.2 宽度比 ≥2.2 |
| N7 | 毛笔转折 | 包络顶点距中心线不超过同点 profile 目标半宽的 1.6 倍、无自交/非有限几何 |
| N8 | 毛笔起收 | 无尾部降压 fixture 在距尾 2×size 处宽度 ≥中段 70%；有降压 fixture 同位置 ≤中段 45% |
| N9 | 单点短划 | 两笔均可见且 bounds 有限 |
| N10 | 确定性 | 100 次 primitive 摘要一致 |
| N11 | 分块连续 | 63/64/65/127/128/129 点 key/channel/bucket multiset 相等，边界滤波切线与包络顶点逐值相等 |
| N12 | 本地湿墨 | T0 定义的弧长前 90% primitive 相等，固定 mask 像素差 ≤1% |
| N13 | 远端湿墨 | frozen/tail/final primitive 无重复，弧长前 90% 像素差 ≤2%，opacity=35% 边界无加深带 |
| N14 | 格式往返 | JSON/.markdraw/SQLite 保留版本和压力语义 |
| N15 | 混合客户端 | live style 缺字段按 v1，不错误升级 |
| N16 | SVG | 真实 XML path 数/字节量达标；Canvas 与 Chromium SVG 的铅笔轻重 darkness、毛笔轻重宽度排序一致 |
| N17 | 边界命中 | scatter/brush 外缘可点、可擦、不裁 |
| N18 | 结构性能 | 静态整笔：pencil drawPath≤4、brush≤2、saveLayer=0；owned segment 录制分别≤4/2；稳定远端帧只断言未变 Picture 不重录且 tail 有限，不限制 drawPicture 总数为 2 |
| N19 | 长笔线性 | time(16k)/time(1k) ≤20 |
| N20 | 资源上限 | 粒子/Path/Picture/retained bytes 不越界 |
| N21 | focus | dim 只改 alpha，不重建 primitive/cache |
| N22 | 压力轻写 | 低压 1.5 秒不被抬到 .5 |

额外压力坡道断言并入 N2/N3：沿弧长滑窗计算的平均 darkness 与有效宽度不得出现逆压力方向的大幅回落；上限触发的 16k 铅笔仍必须满足 N2，不能让粒子降采样抹掉浓淡差异。

建议提交：`test: 固化铅笔与毛笔自然介质验收门禁`

### T12：Web、Windows、HarmonyOS Profile 与盲测

目标：验证真实书写手感与跨端性能。

自动执行者至少完成 Web；有环境时完成 Windows。HarmonyOS 真机若仍不可用，列为合并前用户验收，不得写成已通过。

固定场景：

1. 空白页连续铅笔 30 秒；
2. 空白页连续毛笔 30 秒；
3. 1000 混合元素缩放/平移；
4. 16k 点长铅笔和长毛笔；
5. Web+Windows 双端协作同时书写；
6. Issue #8 聚焦态书写；
7. PDF 页面上书写；
8. 快速切换两支笔；
9. 轻压持续 2 秒、慢加压、快速提笔；
10. 64 点边界附近的远端长笔。

记录：设备、系统、构建模式、平均/P95/最差帧耗时、draw/path/particle 数、Picture 重录数、内存、视觉异常。

运行口径：

- 默认本地预览场景不加 dart-define；
- layered 本地场景增加 `--dart-define=FLOWMUSE_LAYERED_WET_INK=true`；
- 远端 live ink 场景同时增加 `--dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true`，并记录服务端 protocolVersion；
- 性能基线复用 `integration_test/whiteboard_writing_perf_test.dart` 与现有 `test_driver/` 场景注入；在同一设备、同一天、相同 Profile 构建和相同 fixture 上分别运行 `main@3eb2b97` 与当前分支；
- 每个场景预热 1 次、正式运行 5 次，比较五次 P95 的中位数；不得拿历史 debug 日志充当 main 基线；
- 如果只完成默认路径，不得把 layered/远端 live ink 标成通过。

五人无标签盲测协议：

1. 每人独立查看同一尺寸、同一颜色的 v1/v2/对照测试纸；
2. 每人的呈现顺序用固定种子随机化并记录，不向测试者透露版本；
3. 分别回答“哪一张更像 HB 铅笔”“哪一张更像软头毛笔笔”及 1～5 分可读性；
4. 逐人保留匿名编号、顺序和答案摘要，不记录姓名或原始手写；
5. 至少 4/5 正确识别并偏好 v2，且 v2 可读性中位数不低于 v1。

门禁：

- 活动书写 P95 相对 main 退化 ≤15%；
- 1000 元素浏览 P95 相对 main 退化 ≤20%；
- 无持续内存增长；
- 没有每帧重算全部 frozen points；
- 没有按粒子 draw；
- 5 人无标签盲测至少 4 人识别正确并认为 v2 更接近目标；
- Web/Windows/HarmonyOS 同一 fixture 不出现算法级形态分叉。

建议提交：不提交设备日志原始隐私数据；只在计划实施记录中写摘要。

T12 不单独产生代码提交；Profile 与盲测摘要由 T13 写入实施记录。

### T13：文档、ADR 和提交收口

必须更新：

- `.agent/architecture.md`；
- `.agent/decisions.md`：新增 ADR-021，说明 ADR-020 仍管 classic，family 是 core 纯枚举，唯一 dispatch 在 rendering 层，pencil/brush v2 改走自然介质 renderer；
- `docs/技术设计/前端架构.md`；
- `docs/技术设计/数据模型.md`；
- `docs/项目说明/项目需求.md`；
- 本计划实施记录；
- 如工具栏体验改变，更新 README 功能描述，但不把内部实现细节塞进 README。

验收：

- 代码、计划、ADR、数据模型字段一致；
- 不宣称未完成的 tilt、宣纸或真机能力；
- 所有提交号、测试计数和未执行人工项可追溯；
- `git diff --check` 通过，工作区无意外文件。

建议提交：`docs: 记录自然介质笔刷架构与验收结果`

## 6. 性能与资源硬门禁

### 6.1 结构门禁

- v2 pencil 每元素主要 drawPath ≤4；
- v2 brushPen 每元素主要 drawPath ≤2；
- 两者自由笔画内部新增 saveLayer = 0；
- 禁止逐粒子、逐毫丝 draw；
- sampler/renderer O(n + cappedParticles)；
- 16k 点不得 O(n²)；
- seed 不创建全局 Random，32 位乘法只走 §3.3 `mul32` 语义；
- 静态重绘记录 plan 构建次数；默认不预建缓存，只有 T4-C 性能触发后才要求未变化元素命中缓存；
- remote frozen Picture 未变时不得重录；
- focus 只合成 alpha，不污染几何缓存；
- bounds 不通过生成全部粒子计算；
- SVG path 数不随粒子数线性增长；
- 不新增 Image、Shader、第三方纹理资产和依赖。

### 6.2 降级策略

- 粒子超限：稳定均匀降采样，保留首尾和压力极值，不截断尾部；
- 非有限点：跳过坏点，若有效点不足则退化为 dot 或不画；
- v2 元数据非法：回退 v1，不崩溃；
- SVG 输出超预算：降低粒子密度，不转成 base64 raster；
- 远端上下文缺失：只画当前拥有 edge，待缺口补齐后重录受影响 block；
- Profile 不达标：先降低颗粒密度/毫丝细节，不改回双实现 shader 路线。

## 7. 测试与门禁命令

在 `FlowMuse-App`：

```powershell
dart format --set-exit-if-changed <本任务触碰的 Dart 文件>
flutter test test/features/whiteboard/editor_core/rendering
flutter test --platform chrome test/features/whiteboard/editor_core/rendering/natural_media/deterministic_stroke_seed_test.dart
flutter test test/features/whiteboard/editor_core/input
flutter test test/features/whiteboard/editor_core/brush_integration_test.dart
flutter test test/features/whiteboard/collaboration/services/remote_wet_ink_store_test.dart
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard/collaboration
flutter analyze
flutter build web
```

门禁口径：

- format 只约束本分支触碰/新增文件，包含 untracked 且过滤 null；
- analyze 若基线非零，使用 `dart analyze --format=machine`，按 `severity+code+file+message` multiset 比较，要求零新增；
- 不为通过本任务门禁顺手修全仓无关 lint/format；
- Windows/HarmonyOS 构建与 Profile 按环境执行并明确记录，不能用 Web 替代；
- 所有性能数字用 Profile 模式，debug 数字只用于相对定位。
- T2 未实际执行 Chrome 哈希向量测试不得合并；`flutter build web` 只能证明可编译，不能替代 Web 断言。

## 8. 提交顺序和回退

建议一任务一提交。T4/T5 的专用 renderer 文件可以并行开发，但两者共用的 renderer dispatch、profile/bounds 常数由同一人按 T4→T5 顺序串行合入，避免同时修改同一 switch：

1. T0 `test: 建立铅笔与毛笔自然介质视觉基线`
2. T1 `feat: 建立自然介质笔刷版本与格式契约`
3. T2 `feat: 新增确定性自然介质笔画采样器`
4. T3 `fix: 以笔形压力曲线替代自然介质起笔硬地板`
5. T4 `feat: 实现确定性 HB 铅笔渲染器 v2`
6. T5 `feat: 实现方向性软头毛笔渲染器 v2`
7. T6 `feat: 对齐自然介质本地湿墨与静态渲染`
8. T7 `feat: 保证自然介质远端湿墨分块连续`
9. T8 `fix: 对齐自然介质笔刷可视边界与命中`
10. T9 `feat: 对齐自然介质笔刷 SVG 与 markdraw 往返`
11. T10 `feat: 对齐铅笔浓淡与毛笔提按设置语义`
12. T11 `test: 固化铅笔与毛笔自然介质验收门禁`
13. T12 不单独提交，验收摘要并入下一项
14. T13 `docs: 记录自然介质笔刷架构与验收结果`

回退规则：

- `brushRenderVersion` 允许把新元素默认值临时切回 1，但不得删除 v2 数据解析；
- T4、T5 可分别关闭，不影响其他笔；
- 压力 v2 稳定器只对 renderVersion=2 生效，可独立回退；
- live style 字段必须保持向后兼容，不能因回退删除 reader；
- 已写入 v2 的元素即使功能开关关闭，也必须安全显示为 v1 fallback；
- 不通过自动升级/降级批量改写用户 Scene。

## 9. 风险台账

| 风险 | 等级 | 预防/处置 |
| --- | --- | --- |
| 用户期待真实水墨而计划交付软头毛笔 | Critical | T0 明确目标并确认；若不接受则另立水墨项目 |
| v1/v2 远端湿墨预览混淆 | Critical | live style 可选版本；缺失=v1；双端测试 |
| 64 点冻结块导致纹理接缝 | High | edge ownership + 稳定 seed + 边界 fixture |
| `.markdraw` 丢版本/压力编码 | High | 新语法 + 旧文本兼容 + 双往返测试 |
| 取消压力地板后真机闪变回归 | High | 短时稳定器 + OPD2404 回放 + 真机轻写/慢爬场景 |
| 粒子过多拖慢 Web/HarmonyOS | High | compound Path、硬上限、稳定降采样、Profile 门禁 |
| 毛笔转角自交/尖刺 | High | 有限 join、几何断言、八笔画 fixture |
| 新外观改写旧笔记 | High | renderVersion 缺失=v1，不自动迁移 |
| SVG 文件膨胀 | Medium | ≤4/2 path，粒子合并与字节预算 |
| 低 opacity 分块叠加变深 | Medium | primitive 单一所有权和像素边界测试 |
| tilt 字段在部分端无效 | Medium | 本期不依赖；先做独立设备探针 |
| 新模块破坏 ADR-020 单一真源 | Medium | profile 负责分发/样式/边界，算法进入专用 renderer；新增 ADR |
| 调参过多导致无法收敛 | Medium | 固定目标、固定 fixture、首版不暴露多预设 |
| dart2js 32 位哈希漂移 | Critical | 16 位拆分 `mul32` + `.toUnsigned(32)` + VM/Chrome 固定向量双跑 |
| 静态自然介质重绘超预算 | High | 先测量并降低粒子上限；只有 T4-C 门禁触发才增加有界缓存 |

## 10. 完成定义

### A. 合并前自动化必过

- [ ] T0 目标已确认；
- [ ] N1～N22 全绿；
- [ ] v1 铅笔/毛笔输出不变；
- [ ] `.markdraw` 当前 pressureEncoding 丢失缺口已修复；
- [ ] mixed client live style 缺字段路径通过；
- [ ] 本地/远端/静态分块连续；
- [ ] draw/path/particle/saveLayer 上限通过；
- [ ] 1k/16k 线性度通过；
- [ ] VM 与 Chrome 哈希固定向量逐值一致；
- [ ] hit/export/SVG 不裁、不消失；
- [ ] 三个相关测试目录全绿；
- [ ] analyze 相对基线零新增；
- [ ] Web build 通过；
- [ ] 数据模型、架构和 ADR 已同步；
- [ ] `git diff --check` 干净。

### B. 合并前人工必过

- [ ] 用户对 HB 铅笔与软头毛笔目标纸确认；
- [ ] Web 实际书写/缩放/导出检查；
- [ ] Windows 实际书写与 Web 协作检查；
- [ ] 5 人无标签盲测至少 4 人识别正确并偏好 v2；
- [ ] 若当前能获得鸿蒙真机，完成 Profile；若确实不可获得，必须登记为比赛演示前阻断项，不能写“通过”。

### C. 明确不允许用以下结果代替完成

- “五种笔像素不同”；
- 单张静态截图好看；
- 鼠标输入通过；
- Web 通过所以鸿蒙也通过；
- 本地静态元素好看但远端湿墨有接缝；
- PNG 好看但 `.markdraw` 往返后变化；
- 关闭旧元素兼容测试以更新 golden。

## 11. 工作量估算

| 阶段 | 任务 | 估算 |
| --- | --- | ---: |
| 目标与契约 | T0–T1 | 2～3 人日 |
| 共同基础 | T2–T3 | 3～4 人日 |
| 两个 renderer | T4–T5 | 5～7 人日 |
| 湿墨/协作/边界/导出 | T6–T9 | 5～6 人日 |
| UI/验收/文档 | T10–T13 | 2～4 人日 |
| 合计（未触发 T4-C） |  | **17～24 人日** |
| T4-C 条件缓存 | 仅性能超门禁时 | 另加 2～4 人日 |

如果由一个代理连续实施，建议拆成两个可审查里程碑：

- M1（T0～T4）：版本、压力和铅笔 v2 完整闭环；
- M2（T5～T13）：毛笔、湿墨协作、导出与验收。

不建议让低能力模型一次跨越 T2、T4、T5、T7；这些任务包含几何、确定性、缓存和协议边界，必须逐任务测试和复核。

## 12. 实施记录（执行者填写）

| 项目 | 实际结果 |
| --- | --- |
| 实施分支 | `feature/pencil-brush-natural-media-plan-v2` |
| 起始提交 | `3eb2b97` |
| 目标确认 | 2026-08-30 用户确认目标纸通过（"挺好的"），特别认可 spike v2 铅笔中压行（pencil_pencilMediumStroke 右列）的铅笔质感；HB 铅笔/软头毛笔目标按 §2 锁定 |
| 进度 | T0～T3：732fa68/4719264/c2aca40/9902924/69320bf；T4：5fbc93a（+26505be 补 bounds/opacity/dim 验收、4dd3d90 lint）；T5：625d142；T6：d2a7f46。T4 为满足 §3.2 B1/B2 同入参预览=提交门禁，提前落地 T6 工作项 6 的通路与断言：`ToolOverlay.creationStrokeId` 携带 live element id → `buildPreviewElement` freedraw 预览元素用该 id（与 `_buildElement` 提交元素同 id 同种子），fidelity A5 断言"live strokeId 与最终 ElementId 必须相同"；另修 `customDataWithFreedrawRender` classicV1 显式移除 v2 标记（此前 spread 保残留导致显式降级无效）。T5 期间发现并修复：①分块交界 join(k−1→k) 两块都不发（并集缺 key）——按 §3.4"较后 edge 拥有"补块首入口 join 并以测试锁定；②轻压可见下限 0.7px（视觉审查抓到 S 曲线负压段 0.96px 全宽在斜向 AA 下断线成 6 列白点，违反 §3.5"最低有效宽度仍可见"；冻结曲线测试同步更新，只影响 p≲0.012）；③brushSCurve fixture 压力 0.30+0.40·sin 谷值 −0.10 越界，改 0.35+0.35·sin（峰值不变）。T5 有意偏差：圆帽用对称 4 点近似替代 spike 的单侧近似；转角尖刺验收以 plan 级 join 突出度断言（像素法向扫描在 90° 转角沿另一条腿读到假宽度 76px）。T6：ActiveFreedrawView 冻结 renderVersion、layered painter 同 dispatch、90% mask ≤1%、前缀 key 稳定、提交沿 live id（5 测试）；本地无预测点机制，工作项 4/5 以前缀 key 稳定性等价覆盖并记录。T10（笔盒）：压力滑块标签按笔形映射（铅笔=浓淡响应、毛笔=提按响应、其余=压感既有语义）+ v2 笔形模拟压感可解释文案（映射抽为公共 pressureLabelFor/simulatedPressureCaptionFor 并测试；无未实现控件、无能力承诺文案）；各笔偏好持久化/切笔不串改为既有行为（回归覆盖）。T9（SVG/格式）：SVG v2 分支消费共享 plan（bodyPolygon/basePolygon 从渲染器抽出共用真源，不复制 sampler/seed/滤波）；铅笔=基底多边形+≤3 密度桶复合 path（颗粒为旋转四边形）、毛笔=包络+毫丝描边线；SVG 侧确定性抽稀（多边形≤8000 顶点、颗粒≤4000、毫丝≤2000，等步长、末点保留）满足 16k 点预算（产物落盘 build/natural_media_baseline/svg_v2/）；v1 导出结构不变（outline+pattern 2 path）。修正隐藏缺陷：毫丝在画布上 fill 语义零面积不可见→改描边 0.8px round cap（画布与 SVG 同口径）。Chromium 实测（Playwright+页面 canvas 栅格）：铅笔轻重宽度同 6px、暗度 1.72→3.04（与 Canvas N2 同向）；毛笔宽度 4→8px（与 Canvas N6 同向）。markdraw/Excalidraw 往返契约由 T1/T2 契约测试锁定（全绿）。678 测试全绿。T8（bounds/命中）：铅笔颗粒几何常数（散布/半长/半厚）上收 profile 共用真源（sampler 默认值引用之）、铅笔 v2 解析上界 pencilV2VisualHalfWidth（wobble 基底/颗粒外缘/笔端沿切向外伸三者取大 + AA）进 elementVisualBounds 分支，远端湿墨 _strokeBounds 对 v2 style 用同一上界（与 v1 公式取大，保守覆盖缺压感回退）；消费点（scene 命中/选区、export_bounds、viewport_culling、聚焦 dim）经 elementVisualBounds 单一真源自动生效；674 测试全绿（含 T4/T5 的墨迹包络⊆bounds 经验锁与 v1 A20/A21）。T7（远端）：LiveInkStyle renderVersion 全链（发送端 whiteboard_page 显式带 2）、_sameStyle 纳入版本阻断中途翻转、段渲染 v2 分支（双 leading→实测扩到 4 个：桥接边滤波窗口 3 边 + 入界 join 的 from 切线窗口；计划"至少 2 个"允许）、桥接边（连前段末点→本段首点）归较后段（否则两段都不拥有、冻结边界缺 4 个 key）、入界 join 半宽取 from 边（与内部 join 同口径）、冻结整笔末块 ownsStrokeTail（笔尖帽随最后冻结点）、v1 路径输入列表保持单 leading 不变；验收 5 测试：63/64/65/127/128/129 边界段 key 并集=整笔且无重复、远端 vs 静态 90% mask ≤2%（铅笔/毛笔）、block 合并已冻结区域有序一致+边界边集合一致、版本翻转拒段、v1 仍走 adapter。已知口径：分块边界主体 Path 点序与整笔在边界边邻域不同（入界 join 在段首 vs from 边循环尾），点集相同、由 90% mask 像素门净检验；铅笔基底/毛笔包络补"每边终点顶点"保证跨 Picture 边界无白缝（整笔与分块同含该顶点，逐值一致） |
| 最终提交 | 待填写 |
| renderer 参数 | 待填写 |
| 测试计数 | 待填写 |
| analyze 基线/分支 | 待填写 |
| Web build/Profile | 待填写 |
| Windows Profile/协作 | 待填写 |
| HarmonyOS Profile | 待填写，不得默认通过 |
| 盲测结果 | 待填写 |
| 已知降级 | ①flutter test --platform chrome 在本机 dwds 浏览器通道挂起（后台与交互式两跑各 20+ 分钟停在 +0）：§7 种子跨端门禁改由 tool/natural_media_hash_web_check/run.ps1 执行——同一冻结向量清单（hash_vectors.dart 单点维护）经 dart2js 编译后用 node（V8）实跑生产 deterministic_stroke_seed.dart 本体，VM（flutter test）与 V8（node）双侧逐值一致；T12 Web Profile 仍按计划在真实 Chrome 跑整应用；②P-03 见 NOTES-v1（"边缘不规则度不足"未获实测支持，冻结下限 0.05 转为 v2 防退化门） |
| Issue/PR | 待填写 |
