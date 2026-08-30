# 铅笔与毛笔自然介质重构计划审查报告

> 日期：2026-08-30
> 审查对象：[2026-08-30-pencil-brush-natural-media-redesign.md](../plans/2026-08-30-pencil-brush-natural-media-redesign.md)
> 代码基线：`main@3eb2b97`
> 审查方式：产品目标、渲染几何、数据协作、性能跨端四维对抗审查 + 代码实证
> 本轮结论：**计划可执行；0 个未关闭 Critical，0 个未关闭 Important，9 个实施期强制观察项**

## 1. 总评

计划方向正确，且比原 Issue #5 的“参数差异化”更贴近用户反馈。它没有推翻已经稳定的五笔 profile、压力冻结和 WYSIWYG 基础，而是把自然介质能力放到版本化 renderer 中，旧笔迹仍走 v1。

最关键的三个设计判断成立：

1. **铅笔和毛笔不能继续只靠同一个实体圆截面轮廓调参。** 当前代码与视觉矩阵已经证明，参数差异能通过测试，但无法提供介质可信度。
2. **新铅笔选择一个跨端确定性 Path 实现是合理的。** 它避免 HarmonyOS shader 能力差异造成的双重视觉实现；v1 shader 仍保留给历史元素。
3. **必须把 live ink 分块连续性提前到架构层。** 当前远端湿墨按 64 点冻结，只解决了 taper 相位；颗粒和毫丝若没有 edge ownership，会立即出现周期接缝。

计划不是“写完算法就结束”的任务。T0 视觉原型通过、混合版本协作通过、Web/Windows 实测和用户盲测都是硬条件；HarmonyOS 真机暂时拿不到时必须明确登记，不得推断通过。

## 2. 审查证据

### 2.1 代码和运行证据

| 证据 | 审查结论 |
| --- | --- |
| `BrushRenderProfile` 的 pencil/brushPen 仍只配置 perfect_freehand 参数 | 根因不是常数没调好，而是表达能力不足 |
| `freedraw_renderer.dart` 对毛笔只生成 pressure+taper 实心 outline | 无笔头方向、毫丝和转折铺展 |
| `pencil.frag` 只有 FBM alpha | 无轨迹、压力场、纸纹和 seed 语义 |
| `StrokeInputSample` 不含 tilt/orientation | 本期不能承诺侧锋，不应先扩 schema |
| pencil/brushPen 使用 1500ms、0.50 攻击地板 | 轻写表达被压缩，v2 必须分流 |
| `.markdraw` 写 brush/pressures，解析只恢复 brushType | pressureEncoding 已存在往返缺口，v2 版本也会丢 |
| `RemoteWetInkStore` 64 点冻结 + 多级 Picture | v2 primitive 必须与分块无关 |
| 视觉矩阵测试实跑 2/2 通过 | 当前门禁无法识别“灰平滑线/黑宽带”不符合介质 |

视觉矩阵的代码内行序为 pencil、ballpoint、fountainPen、brushPen、highlighter。实际输出中铅笔近似均匀灰线，毛笔近似两端尖的宽黑线，但 pairwise ink union 差异仍超过 5%，证实旧验收目标已经过时。

### 2.2 市场与技术证据

- Goodnotes 把 Brush Pen 定义为高度压感的艺术/lettering 工具，说明毛笔产品语义应围绕提按，而不是纹理噪声；
- Procreate 的 Shape + Grain 模型和压力/倾斜属性映射，说明自然笔刷需要把轨迹形状、介质纹理和输入曲线拆开；
- Wacom WILL 明确区分 raster particle brush 与 vector brush，支持本计划“铅笔颗粒、毛笔方向性包络”的分工；
- Apple PencilKit 与 Flutter 都证明 tilt/orientation 是有效的未来输入，但不能替代本期目标设备探针；
- Adobe Fresco 的压力曲线和实时试写说明固定时间压力地板不是成熟的长期交互模型。

来源见[专项调研](../research/2026-08-30-pencil-brush-natural-media-research.md)。

## 3. Critical 发现及裁决

### C-1：产品名“毛笔”可能对应两个完全不同的工程量

**问题：** 用户可能期待软头 brush pen，也可能期待传统毛笔在宣纸上的渗墨、枯湿和含墨量。后者需要姿态、介质状态、流体/纹理合成和完全不同的数据模型，本计划 15～21 人日不可能可靠交付。

**修订：** 计划已把本期目标钉死为“软头毛笔笔”，并把真实水墨列为非目标；T0 要求用户先确认固定测试纸。

**状态：CLOSED。** 若用户不接受目标，停止计划并另立项目，不允许边实现边扩范围。

### C-2：混合版本远端湿墨会预览错误

**问题：** 只在 final element 写 `brushRenderVersion` 不够。v2 客户端收到旧客户端的 pencil/brushPen live chunk 时，如果按当前默认 v2 预览，提交后又会回到 v1；反方向旧客户端也需要忽略新字段。

**修订：** `LiveInkStyle` 增加可选 `renderVersion`，缺失视为 1；不 bump `LiveInkChunk.protocolVersion`，旧 parser 自然忽略未知 style 字段。

**代码可行性：** 当前 `LiveInkStyle.fromJson` 只读取已知键，不拒绝未知键；字段位于既有加密 live ink payload，服务端无需修改。

**状态：CLOSED。** T1/T7/N15 已形成完整门禁。

### C-3：纯 Path 路线的视觉收益尚未被真实原型证明

**问题：** 纯 Path 在跨端一致性上更优，但如果复合颗粒和方向包络达不到目标，先改数据契约会产生无收益架构。

**修订：** T0 增加两个一次性原型和停止门：铅笔 ≤4 Path、毛笔 ≤2 Path，无 shader/saveLayer；用户与 16k 探针同时通过后才进入 T1。原型随后删除。

**状态：CLOSED BY GATE。** 这是执行前置条件，不是允许绕过的待办。

## 4. Important 发现及裁决

### I-1：原“稳定 hash64”定义不足，跨端可能漂移

**问题：** 若实现者使用 `String.hashCode`、`Object.hash` 或默认 `Random`，Dart VM、Web JS 和不同运行可能产生不同粒子，导致协作端和 SVG 不一致。

**修订：** 计划已钉死 UTF-8 FNV-1a 32 + 显式 mix32，每步 `& 0xffffffff`，低 24 位归一化，并要求至少 8 组测试向量和源码禁止项。

**状态：CLOSED。** 实现审查必须看算法和测试向量，不能只看函数名。

### I-2：`.markdraw` 当前已丢失 pressureEncoding

**问题：** serializer 写了已编码 pressures，却不写 marker；parser 重建 customData 时只放 brushType。文本分屏往返后渲染会再次应用 legacy sensitivity。新增 renderVersion 若照搬 customData 方案也会消失。

**修订：** T1/T9 增加 `pressure-encoded` 与 `render=v2` 语法，旧文本默认 legacy/v1；N14 双往返锁定。

**状态：CLOSED。** 该修复应在 renderer 前落地。

### I-3：当前 RemoteWetInkSegment 不足以表达 primitive 所有权

**问题：** 它只有 `startIndex`、points 和无 index 的 leading/trailing context。几何 renderer 若把 context 也画出，会重复；若每块独立播种，会接缝。

**修订：** T2/T7 要求 indexed context + owned edge range；context 只算导数，edge 和 join 有唯一所有者。63/64/65 等边界做 primitive key multiset 测试。

**状态：CLOSED IN PLAN。** 实施时这是 T7 的首要审查点。

### I-4：新 renderer 不能直接替换 v1，否则历史笔记全部变脸

**问题：** 现有 customData 没有版本；若按 brushType 直接切新算法，全部历史、本地备份和导入文件会改变外观。

**修订：** 缺失版本=v1，新建 pencil/brushPen 才写 v2，不自动迁移。v1 的 shader/fallback 不能因 v2 采用纯 Path 被删除。

**状态：CLOSED。** N1 必须用真实历史 fixture，不得只构造新元素后删版本。

### I-5：压力地板不能直接删除

**问题：** 当前 1.5 秒补偿源于 OPD2404 真机慢爬压力；直接删除会恢复起笔闪变。保留又会让轻压失真。

**修订：** T3 为 v2 单独引入最多 80ms/3 样本的相邻值稳定器与单调响应曲线；v1 保持不动；同时加入慢爬和有意轻写两组回放。

**状态：CLOSED。** 最终常数必须真机校准，计划中的公式只是候选。

### I-6：自然介质分发与 ADR-020 的“单一 profile”表述冲突

**问题：** ADR-020 要求 renderer/导出/边界不按 brushType 特判。新增两个 renderer 后，若各调用方自行 switch，会重新产生三套真源。

**修订：** profile 增加 renderer family，唯一 dispatcher 选择 v1/pencilV2/brushV2；Canvas、湿墨和 SVG 只消费 dispatcher/plan。T13 新增 ADR-021 说明 ADR-020 在 classic 范围继续有效。

**状态：CLOSED。** 审查时 grep 调用方 switch，新增散落特判即退回。

### I-7：draw 次数少不代表 path 构造便宜

**问题：** 把 20,000 个粒子塞进一个 Path 仍可能卡顿和膨胀 SVG，单纯 `drawPath <= 4` 不足。

**修订：** 静态粒子 ≤4096、湿墨 ≤1024，稳定降采样；同时测 particle/subpath 数、16k 线性度、SVG 字节量和真实 Profile。

**状态：CLOSED。** 建议实施时把 16k v2 pencil SVG 单元素预算固定为 ≤512 KiB；若实际基线证明不合理，可在同一测试证据下调整，不得取消上限。

### I-8：毛笔“每笔 ≤2 draw”不能机械套到远端分块

**问题：** 远端缓存由多个 frozen Picture + tail 组成，长笔稳定帧不可能只发生两次 canvas 调用；错误断言会迫使实现者合并缓存、反而退化性能。

**修订：** 计划已区分：静态完整毛笔 drawPath ≤2；每个变化的 owned segment 录制 ≤2；稳定帧回放既有 Picture + 有限 tail。缓存层数继续受现有 store 上限约束。

**状态：CLOSED。** N18 要按渲染阶段分别计数。

### I-9：边界不能通过生成全部颗粒获得

**问题：** Scene 命中、导出 bounds 和 focus saveLayer 是高频/批量路径。如果为此跑 sampler 或构建 4096 粒子，1000 元素画布会严重退化。

**修订：** T8 要求基于中心线 AABB + profile 最大 width/scatter/join 的解析保守上界；允许 O(points) 读取已有中心线，不允许 O(particles)。远端 frozen bounds 继续增量维护。

**状态：CLOSED。** 代码审查禁止 `elementVisualBounds` 调用完整 renderer。

## 5. Minor 发现与实施注记

1. `brush_render_profile.dart` 当前有重复铅笔注释，可在触碰文件时顺手清理，不单独提交；
2. SVG `<path>` 数量门禁应统计真实 XML 节点，不能只统计 renderer 的 logical bucket；
3. 低 opacity 毛笔的 block 交界比纯黑更容易暴露重叠，N13 必须使用 opacity 35% fixture；
4. `strokeId` 必须与最终 `ElementId` 一致，否则 live/final seed 不同；T6/T7 增断言；
5. edge-local 粒子会受原始采样间距影响，T0 必须比较同轨迹不同采样率，必要时在单 edge 内按长度均匀细分；
6. pressure density 指标应在相同颜色、opacity、背景和宽度 fixture 下比较，避免把颜色差当颗粒差；
7. 视觉 golden 可能受 Skia/Impeller 抗锯齿微差影响，硬门禁以结构+统计为主，golden 使用容差并由人工测试补足；
8. `brushRenderVersion=2` 是显示元数据，不得进入权限、协作仲裁或 LWW tie-break；
9. tilt 探针若后续实施，禁止记录或提交用户真实笔迹原始坐标，只保留字段可用率和范围摘要。

## 6. 可实现性评分

| 维度 | 评分 | 说明 |
| --- | ---: | --- |
| 产品收益 | 9/10 | 直接处理当前最明显的“像不像”问题 |
| 技术可行性 | 8/10 | 纯 Path、无依赖、现有输入足够完成首版目标 |
| 跨端一致性 | 9/10 | v2 不依赖 shader；仍需真机 Profile |
| 协作兼容 | 8/10 | 可选 style 版本成立，分块所有权是主要难点 |
| 性能风险 | 7/10 | 颗粒和复杂包络有成本，但有上限、复合 Path 和缓存门禁 |
| 数据兼容 | 9/10 | customData 版本化、旧数据 v1、不做迁移 |
| 计划可执行性 | 9/10 | 任务依赖、文件、测试、提交和停止门已明确 |

## 7. 审查结论

方案可以交付实现，但应按以下纪律执行：

1. 先做 T0 原型与用户目标确认，失败就修路线，不进入 T1；
2. T1～T3 必须先合并，不能让铅笔/毛笔各自复制版本、采样和压力逻辑；
3. T4/T5 完成后先做静态视觉复核，再进入湿墨和协作；
4. T7 是最高风险任务，必须单独代码审查并跑所有 63/64/65 边界；
5. T11 不能只更新旧视觉矩阵阈值，必须建立 N1～N22；
6. 未获得 HarmonyOS 真机时可以完成代码与 Web/Windows 验收，但比赛演示前仍有明确的真机阻断项。

目前没有需要继续修改计划文字的 Critical/Important。真正的外部阻断只有 T0 用户目标确认和实施后的目标端 Profile；它们不能由文档审查替代。
