# Issue #5：笔盒五种笔刷差异化效果执行计划

> 日期：2026-08-28
>
> 状态：v3，已完成两轮三路对抗审查并裁决，待执行
>
> 对应 Issue：[对笔盒效果进行实现](https://github.com/qinyre/FlowMuse/issues/5)
>
> 建议分支：feature/issue-5-pen-effects
>
> 计划基线：main / e747a15
> 预计工作量：8～12 人日（团队口径）；本版按"单 AI 代理执行"裁剪，其中真机/双人项转为移交清单（见 §0、§15）
> 首轮审查：[Issue #5 笔刷差异化计划审查记录](../specs/2026-08-28-issue-5-pen-effects-review.md)（含第二轮三路对抗审查与主审 v3 裁决）

## 0. v3 变更记录（2026-08-28 第二轮三路对抗审查主审裁决）

第二轮三路审查（渲染几何 / 跨端构建 / 完备性）完整记录见审查文档第 10 节。以下裁决已并入正文对应小节：

1. **A4 判据改绝对距离**（原弧长 10%/90% 百分比判据与绝对 taper 数学不相容：taper 开启时起点侧判据恒不可满足）。新判据见 §9 A4 与 T3。
2. **taper 种子值上调**：毛笔起 4×size、收 6×size；铅笔起 3×size、收 4×size（2×size 起笔因包内 `runningLength < size` 丢点，可见起始宽度显著抬高（按 start easing 形式约 50%～75%），渐变无效）。
3. **新增强制规则：远端湿墨分段 taper 语义**（TaperPhase：full / headOnly / tailOnly / none）。远端湿墨按 64 点冻结块+尾段逐段独立 getStroke，若不分段控制 taper，毛笔会在每个段边界周期性收针，违反 §1 一致性目标。见 T3。
4. **荧光笔平头改用包原生能力**：`StrokeEndOptions.start/end(cap: false)` 生成确定性平截面（首轮"perfect_freehand 无 cap 概念"系误判），禁止自研截面。拐角处圆弧连接是包标准行为，验收口径写明。
5. **压力编码公式钉死前提**：等价性仅在 `StrokeOptions.easing = identity`（包默认，现状未传）下成立；profile 注释与测试断言同时锁定。编码发生在输入建模平滑之后（controller→tool 交界），现状链路已满足。
6. **T2/T6 文件清单补齐 4 个必改文件**：`local_wet_ink_painter.dart`（本地湿墨 pressureEncoding 标记）、`rough_canvas_adapter.dart`（删除全局 pressureSensitivity 渲染依赖的本体）、`freedraw_renderer_test.dart`（:32-47 "sensitivity 改变轮廓"用例按冻结语义改写，移入 T2）、`remote_wet_ink_painter_focus_test.dart`（:154/:219 硬编码 kMaxBrushSizeScale 公式，移入 T6）。
7. **T0 增加 SpyCanvas 扩展**：drawPath 捕获 `paint.blendMode / color.alpha / shader!=null`，否则 T4 结构门禁与 A9 无断言载体。`measureStroke` 补 `brushType` 参数（现状缺失，恒按钢笔测）。
8. **T1 构建闭环降级**：shader 编译产物最便宜闭环是 `flutter test`（unit_test_assets 由 impellerc 编译，历史产物已实证 ink_sparkle 为 IPLR 而 pencil 为源文本）；`flutter build hap` 必须 `--no-codesign`（signingConfigs 为空时默认模式直接 throwToolExit）；本机无 Visual Studio，`flutter build windows` 不可执行，Windows 桌面构建/运行列入移交清单。pencil.frag 现有 GLSL 经 impellerc 实测编译通过（ohos 与 web 双目标），不改写。
9. **FragmentShader 生命周期语义修正**：engine 逐 draw memcpy uniform 快照，"单实例缓存 + 每元素 setFloat 后立即 drawPath"安全；FragmentProgram 无公开 dispose（registry 持有至 shutdown），resetForTesting 仅释放 FragmentShader 实例。
10. **T4 像素测试须用 `test()` 而非 `testWidgets`**（fake-async 下 toImage 永不完成，仓库已有踩坑注释）；flutter test 为软件光栅，像素断言是语义证据，真实后端证据 = Web 构建运行 + hap 产物；深色底高亮判据定为"不提亮、不消失"（darken 在深底弱可见是数学预期，记为已知局限，不以"可见"为门禁）。
11. **T1 增加 PencilShader loader 注入点**：A23"并发 init 只加载一次"才有确定性断言入口。
12. **T7 现状修正**：`svg_export_structure_test.dart` 现零 freedraw 断言，T7 对它是"新增"而非"推翻大片断言"。
13. **§3.2 补记不做项**：属性面板固定 4 档粗细（issue #5 描述提及但不在验收标准内）。
14. **T9 文档同步扩充**：`docs/技术设计/数据模型.md`（customData 新增键）+ `.agent/decisions.md`（ADR）+ `.agent/architecture.md` + `.agent/ai_usage.md`（仓库 issue #9 收尾先例）；文档独立为 `docs:` 提交。
15. **验收按执行者能力二分**：双人盲测 → 五笔同轨迹 fixture PNG 并排 + 视觉代理无标签盲判（等效替代，结果移交用户复核）；真双端协作 → `MemoryRealtimeTransport` 双端自动化 + 可选双 Web 页面（部署服务）；HarmonyOS 真机 Profile/手写体验、Windows 桌面构建运行、双人盲测复核 → 移交用户清单（§15）。
16. **A14 口径分层**：典型宽度（strokeWidth=4）严格 ≤1 逻辑像素/边；大宽度回归用 ≤ size/8 上界；包内 isComplete 末端删点（≤~size/2）列为已知差异来源，单独断言上界。
17. **风险台账补记**：鸿蒙 `harmony_stylus_stroke_smoother` 一级压感平滑（pressureAlpha=0.45）与 profile 二级平滑的叠加手感风险，无真机无法验证，移交清单。

## 1. 计划目的

FlowMuse 已经提供铅笔、圆珠笔、钢笔、毛笔、荧光笔五种入口，但当前五者主要共用 perfect_freehand 的轮廓生成和 Canvas 路径绘制，只在宽度、透明度、thinning 等标量上有所区别。用户切换笔刷后，视觉和书写反馈仍然过于接近，尚未形成成熟笔记产品中“一眼可辨、手感稳定、导出一致”的笔盒体验。

本计划不重做手写引擎，而是在现有数据格式和渲染链路上完成以下结果：

- 五种笔刷在相同输入下可稳定区分；
- 本地湿墨、远端湿墨、落笔后的静态元素保持一致，不出现提交瞬间换笔触；
- PNG/画布与 SVG 导出保持语义一致；
- 荧光笔支持重复覆盖加深，同时不破坏 Issue #8 已实现的聚焦变淡 saveLayer；
- 铅笔具有可辨识但稳定的颗粒感；
- 圆珠笔保持恒定细线，钢笔体现适度压感，毛笔体现强压感和明显收锋；
- 压力灵敏度在创建笔迹时固化，切换笔刷或换一个协作端后不得改变历史笔迹；
- 选择、擦除、场景边界和 PNG/SVG 导出均覆盖真实可见笔宽；
- 不新增依赖，不修改协作协议、服务端、数据库和 Excalidraw 顶层 schema；只在现有 flowMuse customData 中增加压力编码版本。

## 2. 成功标准

### 2.1 用户可见结果

使用同一组输入轨迹分别绘制五种笔刷时，应达到：

| 笔刷 | 目标效果 | 必须避免 |
| --- | --- | --- |
| 铅笔 | 低饱和、轻颗粒、边缘略有纹理，短笔画也自然 | 每帧随机闪烁、颗粒密度随设备失控 |
| 圆珠笔 | 细、稳定、圆头、基本不受压力影响 | 线宽随压力明显跳动、尖锐断头 |
| 钢笔 | 干净、连续、适度压感，宽度变化可控 | 与圆珠笔几乎相同、过度夸张成毛笔 |
| 毛笔 | 强压感、起收锋明显、转折具有粗细变化 | taper 只有 1 像素而肉眼不可见 |
| 荧光笔 | 宽、平头、半透明，重复覆盖区域明显加深 | 遮盖黑色文字、在透明 saveLayer 内消失 |

### 2.2 工程结果

- 五种笔刷参数只有一个生产代码真源；
- Raster、SVG、湿墨边界计算均读取同一笔刷描述；
- 新笔迹的压力灵敏度被烘焙进已有 pressures 数据，历史笔迹使用确定性的兼容规则；
- 普通绘制热路径不新增 saveLayer；
- 铅笔之外的笔刷不增加无界随机采样或额外逐点绘制；
- 现有文档、协作存量数据可以直接打开；
- 同版本客户端之间的协作显示一致；
- 点击单点、短笔迹、选择、擦除、PNG/SVG 导出边界均有回归测试；
- 相关单元测试、结构测试、像素测试、导出测试、压力测试通过；
- Windows、Web、HarmonyOS 至少完成构建验证，Windows/Web 完成可操作验收，HarmonyOS 完成真机 Profile 后才关闭 Issue。

## 3. 范围边界

### 3.1 本期包含

1. 收敛五种笔刷的渲染配置；
2. 改善圆珠笔、钢笔和毛笔的几何差异；
3. 实现荧光笔可叠加加深的合成方式；
4. 完善铅笔 shader 路径并提供确定性降级；
5. 固化压力灵敏度，消除切换笔刷和协作端之间的历史笔迹漂移；
6. 修复自由笔画选择、擦除、场景边界和 PNG 导出裁边；
7. 让 SVG 使用真实自由笔画轮廓；
8. 调整笔盒内压力选项的交互语义；
9. 补齐自动化测试、性能门禁和跨端验收记录。

### 3.2 本期明确不做

- 不开发自定义笔刷编辑器、笔刷商店或笔刷包；
- 不给输入建模层新增 BrushType 分支；
- 不修改笔迹点结构，不记录倾斜角、方位角和新的时间序列；
- 不引入纹理库、噪声库或新的 Flutter 依赖；
- 不修改协作消息、服务端、数据库 schema；
- 不为不同笔刷强制改写用户颜色；
- 不保证新旧客户端对同一笔迹的视觉完全一致；
- 不追求 Raster 与 SVG 像素级一致，只要求笔刷语义和主要轮廓一致；
- 不改属性面板"固定 4 档粗细"为按笔型分档（issue #5 描述提及，但不在其验收标准内；如需另立项）。

这些能力如果未来有明确需求，应分别立项。尤其是倾斜感知：HarmonyOS 原生输入能够提供 tiltX/tiltY，但当前 Flutter 笔迹数据链没有保存这些字段，本期强行加入会扩大数据迁移和协作兼容范围。

## 4. 已核验的代码事实

### 4.1 当前渲染链路

- 自由笔画主渲染位于：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 轮廓由 perfect_freehand 生成，再通过 drawPath 绘制；
- 本地湿墨会构造临时 FreedrawElement 并复用 ElementRenderer；
- 远端湿墨也通过相同适配与渲染入口；
- SVG 当前仍按等宽中心线导出，未复用自由笔画真实轮廓；
- BrushState 已持久化每种笔刷的颜色、宽度和压力选项；
- 当前输入建模层只过滤位置和压力，最终元素没有 tilt、azimuth 或时间字段。

### 4.2 当前参数中的关键问题

现有毛笔和铅笔的 customTaper 以 0.5、1.0 直接传给 perfect_freehand。该参数表示路径距离而非比例，所以当前收锋大约只有 0.5～1 个逻辑像素，视觉上几乎不可见。

现有 SVG 渲染器另外维护一套宽度和透明度 switch，导致 Canvas 调参后 SVG 容易漂移。Excalidraw JSON 已同时往返 strokeWidth 和 customData.flowMuse.brushType，本期不增加 strokeWidth 与 sizeScale 的第二套双向映射。

当前铅笔 shader 注册方式错误：pubspec.yaml 把 shaders/ 放在 assets 段，当前项目使用的 Flutter 3.41-ohos 只会原样复制该文件。已存在的 Flutter、Web、HarmonyOS 构建产物内 pencil.frag 均仍是 GLSL 源文本，PencilShader.init 会捕获加载失败后静默降级。实施时必须先修为 flutter.shaders 并完成最小加载闭环。

当前压力灵敏度保存在 MarkdrawController/RoughCanvasAdapter 的全局可变状态中，FreedrawElement 只保存 pressures 和 brushType。这会让切换笔刷后历史元素重新按新的 sensitivity 渲染，也可能让两个协作端显示不一致。本期采用“创建时烘焙压力、渲染时使用固定 profile”的方式修复，不增加实时协作字段。

当前自由笔画元素的 width/height 是中心线 AABB；Scene 命中、sceneBounds 和 ExportBounds 都没有纳入笔刷可见半径。默认 strokeWidth=20、sizeScale=4.2 的荧光笔半宽为 42，而 PNG 默认 padding 只有 20，现状即可裁边。

荧光笔不能直接改用 BlendMode.multiply。当前 Flutter SDK 明确定义 multiply 会同时相乘 alpha，透明目标像素会得到透明输出；Issue #8 的聚焦功能会使用透明 saveLayer。首版继续使用 BlendMode.darken，并补白底、深色底、PDF、透明离屏层和 dim 层像素测试。若特定后端实测异常，只允许回退 sourceOver，不得改成 multiply 或 modulate。

## 5. 产品与技术裁决

成熟产品的共同做法不是为每支笔建立独立文档模型，而是保留统一笔迹数据，通过工具专属渲染特征形成区别：

- Goodnotes 将圆珠笔定义为无压感、圆头，将钢笔和毛笔定义为不同程度的压感笔；
- OneNote 使用压力和速度塑造钢笔，并让毛笔体现明显方向与粗细；
- Concepts 使用有限笔槽和每笔独立配置，强调快速切换；
- Procreate 将 taper、shape、grain、rendering 和 dynamics 分层，但这属于专业笔刷编辑器范畴；
- Office 的铅笔强调颗粒和倾斜，但 FlowMuse 当前数据模型尚不具备完整倾斜输入。

因此本期采用“一个统一轮廓引擎 + 一份笔刷渲染描述 + 少量笔刷专属绘制策略”，而不是五套渲染器。

## 6. 目标架构

### 6.1 单一配置真源

将 freedraw_renderer.dart 内部的私有 _BrushConfig 提升为 editor_core 可复用的 BrushRenderProfile。由于 Scene 命中、导出边界和渲染都要读取其纯几何字段，profile 放在 core/elements，而不是让 core/scene 反向依赖 rendering：

    FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_render_profile.dart

建议接口：

    enum BrushCapStyle {
      round,
      flat,
    }

    enum BrushCompositeMode {
      sourceOver,
      darken,
    }

    final class BrushRenderProfile {
      const BrushRenderProfile({
        required this.sizeScale,
        required this.opacityScale,
        required this.thinningBase,
        required this.thinningSpan,
        required this.simulatedThinning,
        required this.smoothing,
        required this.streamline,
        required this.pressureEnabled,
        required this.forceSimulatePressure,
        required this.startTaperSizeFactor,
        required this.endTaperSizeFactor,
        required this.capStyle,
        required this.compositeMode,
        required this.usesPencilTexture,
      });

      static BrushRenderProfile forType(BrushType type);

      double effectiveThinning(double sensitivity);
      double encodePressure(double rawPressure, double sensitivity);
      double visualHalfWidth(double strokeWidth);
    }

字段语义必须写在代码注释中：

- startTaperSizeFactor/endTaperSizeFactor 是相对渲染后笔宽的比例；换算绝对距离时 size 取 `max(strokeWidth × sizeScale, 1.0)`（sizeScale 之后、1.0 下限之后），"<3×size 禁用 taper" 的 size 同源；
- thinningBase + thinningSpan × sensitivity 是真实压感的有效 thinning；
- encodePressure 将创建时灵敏度烘焙到已有 pressure 值，结果钳制到 0～1；**等价性前提：StrokeOptions.easing 必须保持包默认 identity**（半径公式 `size × easing(0.5 + thinning×(pressure−0.5))` 仅在 identity 下对压力线性），profile 注释与单测双重锁定；
- 编码必须发生在全部输入压感平滑之后（controller→FreedrawTool 交界），现状链路（HarmonyOS 一级平滑 → modeler → controller）已满足；
- simulatedThinning 是无真实压力时的唯一 thinning；圆珠笔和荧光笔必须同时把 thinningBase、thinningSpan、simulatedThinning 设为 0；
- taper 距离以绝对距离传给包的 customTaper（其单位即绝对距离）；启用与否由应用侧按原始输入点折线长度判断，不由插值后总长推导；包内部 te 与 isComplete 末端删点仍依赖插值长度，属已知残差（见 A14 口径）；
- pressureEnabled 表示真实压力是否生效；
- forceSimulatePressure 表示无可信压力时是否使用速度模拟；
- compositeMode 仅描述最终合成，不允许内部隐式创建 saveLayer；
- usesPencilTexture 只表示可使用纹理，不保证 shader 一定可用。

渲染入口需能区分笔迹段的 taper 角色（远端湿墨 64 点分段独立 getStroke，见 T3）：

    enum FreedrawTaperPhase { full, headOnly, tailOnly, none }

- full：整笔渲染（本地湿墨、静态元素、SVG）；
- headOnly：包含笔迹起点的远端冻结首块/首段；
- tailOnly：远端最新尾段（taper 跟随对端笔尖）；
- none：其余中间段。

### 6.2 数据流

    Pointer pressure + current brush sensitivity
        -> profile.encodePressure
        -> FreedrawTool / local wet ink / live-ink chunk / element.pressures
        -> customData.flowMuse.pressureEncoding = 1
        -> old element without marker uses BrushState.defaults[type].pressureSensitivity
        -> new element uses baked pressure with max profile thinning

    BrushType
        -> BrushRenderProfile.forType
        -> perfect_freehand outline options
        -> raster path / pencil texture / highlighter composite
        -> local wet ink and remote wet ink reuse
        -> SVG outline export
        -> visualHalfWidth for Scene hit/export bounds and wet-ink bounds

配置层只能保存无状态常量。shader 是否可用、Path 缓存、Paint 等运行时对象不得放入 BrushRenderProfile。

### 6.3 压力冻结与旧数据兼容

新笔迹采用以下确定性规则：

1. 只有铅笔、钢笔、毛笔接收真实 pressure；
2. 控制器在把 pressure 交给 FreedrawTool 前调用 profile.encodePressure（controller 侧唯一编码点 `_encodeStrokePressure`；此后 pressures、ActiveFreedrawView、live-ink chunk、元素数据全程携带已编码值）；
3. FreedrawElement.pressures、ActiveFreedrawView 和现有 live-ink chunk 都携带已经编码的值（协议零改动论证：`LiveInkPoint.pressure` 字段已存在，`whiteboard_page._broadcastLiveInk` 直接透传 view.pressures，编码在 controller 侧完成后，收发两端与 `remote_wet_ink_store` 均无需修改）；
4. 创建的元素写入 customData.flowMuse.pressureEncoding=1（嵌套合并，不覆盖已有键）；
5. 渲染 pressureEncoding=1 的元素时使用 profile 最大 thinning（base+span），不再读取任何控制器 sensitivity；渲染入口删除 pressureSensitivity 参数，改传 `pressureEncoded` 标记；
6. 圆珠笔和荧光笔向 FreedrawTool 传 null pressure（simulatePressure 路径 + thinning 全 0 → 恒宽），并使用 simulatedThinning=0；
7. 旧元素没有 marker 时，使用 BrushState.defaults 对应笔刷的 sensitivity（常量、确定性），禁止读取当前选中的笔刷状态或适配器全局状态；
8. 本地湿墨与远端湿墨临时元素一律按"已编码"渲染（新笔迹必编码；湿墨不可能是旧元素），本地湿墨临时元素同时写入 pressureEncoding=1 标记以共用同一判定函数；
9. 同版本远端湿墨默认其 pressure 已编码；本期不增加实时消息字段。

编码公式必须保持当前半径语义。设 maxThinning=base+span、effective=base+span×sensitivity：

    encoded = 0.5 + (effective / maxThinning) * (raw - 0.5)

maxThinning 为 0 时直接返回 0.5。结果钳制到 0～1。该方案会损失原始 pressure，但满足用户真正需要的“创建后的笔迹稳定”，并复用已有数据与协作链路。

### 6.4 可视边界

BrushRenderProfile.visualHalfWidth 必须给出当前笔刷的保守最大可见半径，并包含固定抗锯齿/纹理余量。新增纯函数 elementVisualBounds(Element)：

- FreedrawElement：中心线 AABB 按 visualHalfWidth 外扩；
- 其他元素：保持现有边界行为，本 Issue 不顺带重做全部图形命中；
- Scene.sceneBounds、Scene.getElementAtPoint、ExportBounds 和远端湿墨边界统一复用；
- 不能继续用固定 kMaxBrushSizeScale 和固定 PNG padding 掩盖问题。

### 6.5 首轮调参种子

以下数值是实现起点，不是机械验收合同。允许在自动化约束和人工盲测范围内微调：

| 笔刷 | sizeScale | opacityScale | base+span | simulatedThinning | 压力 | 起始 taper | 结束 taper | 端帽 | 合成 |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |
| 铅笔 | 0.82 | 0.68 | 0.00+0.45 | 0.32 | 模拟/真实均可 | 3×size | 4×size | round | sourceOver |
| 圆珠笔 | 0.72 | 1.00 | 0.00+0.00 | 0.00 | 忽略 | 0 | 0 | round | sourceOver |
| 钢笔 | 1.00 | 1.00 | 0.05+0.90 | 现有默认值 | 启用 | 0 | 0 | round | sourceOver |
| 毛笔 | 1.15 | 1.00 | 0.00+1.00 | 0.82 | 强 | 6×size | 6×size | round | sourceOver |
| 荧光笔 | 4.20 | 0.28～0.32 | 0.00+0.00 | 0.00 | 忽略 | 0 | 0 | flat（cap:false） | darken |

任何调参不得突破以下语义：

- 圆珠笔和荧光笔的真实、模拟 thinning 必须都为 0；
- 荧光笔必须恒宽、平头（包原生 cap:false 平截面）、darken；拐角处圆弧连接是包标准行为，不作缺陷处理；
- 毛笔必须比钢笔拥有更强粗细差异和更长收锋；
- 原始折线长度小于 3×size 时禁用 taper，按短线/圆点规则绘制，避免整条笔迹被收锋吞掉（该门控必须在所有渲染入口生效：本地湿墨、远端分段、静态、SVG）；
- 铅笔纹理必须可确定复现；
- 可视半径必须从 profile 派生，不再维护手写 kMaxBrushSizeScale。

## 7. 执行顺序与依赖

    T0 基线、缺陷复现与测试夹具
        -> T1 shader 注册与资源闭环
            -> T2 profile 单一真源与压力冻结
                -> T3 圆珠笔/钢笔/毛笔几何
                    -> T4 荧光笔合成
                        -> T5 铅笔纹理
                            -> T6 可视边界与命中/导出
                                -> T7 SVG 对齐
                                    -> T8 笔盒交互语义
                                        -> T9 集成、性能与文档收口

T1 先验证 shader 前提，T2 之后的正式效果按顺序执行。T3、T4、T5 会修改同一 profile 和 renderer，不安排并行编辑；可以并行准备测试数据，但不得产生三份配置或三套轮廓入口。发现计划外数据库迁移或服务端改动时立即停止并回到方案审查。

## 8. 详细任务

### T0：冻结基线、复现阻断缺陷并建立测量工具

目标：先证明现状，再让后续差异可以被稳定测试，避免依赖人工截图。

主要文件：

- 修改：
  FlowMuse-App/test/features/whiteboard/editor_core/freedraw_renderer_test.dart
- 新增：
  FlowMuse-App/test/features/whiteboard/editor_core/fixtures/brush_stroke_fixtures.dart
- 可新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/brush_path_metrics.dart
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/export_region_png_test.dart
  FlowMuse-App/test/features/whiteboard/editor_core/scene_freedraw_hit_test.dart

执行步骤：

1. 固定五组输入：
   - 短水平线；
   - 慢速弧线；
   - 快速弧线；
   - 压力从低到高再降低的曲线；
   - 包含明显拐角的折线路径。
2. fixture 明确保存位置与压力，不依赖当前时间、随机数或设备 DPR。
3. 建立只供测试使用的轮廓指标：
   - bounds；
   - 起始、中段、结束局部宽度；
   - 轮廓面积；
   - path/paint 调用计数；
   - 结果是否包含有限数值。
4. 扩展 `rendering/canvas_spy.dart`：drawPath 捕获 `paint.blendMode`、`paint.color.alpha`、`paint.shader != null`（否则 T4 结构门禁与 A9 shader 确定性无断言载体）；`measureStroke` 补 `brushType` 参数（现状缺失，恒按钢笔测量）。
5. 先写会失败的缺陷测试或探针：
   - 构建产物 pencil.frag 首行仍是 GLSL 源码，证明当前注册未编译；
   - 切换 controller.pressureSensitivity 会改变同一历史笔迹轮廓；
   - 两个不同 sensitivity 的 adapter 会把同一元素渲染成不同 bounds；
   - 单点毛笔/铅笔开启 taper 后只生成退化轮廓；
   - 荧光笔可见区域外缘无法选择/擦除；
   - 默认荧光笔全场景 PNG 导出被裁边。
6. 增加现有五种配置可生成有限轮廓的基线测试。
7. 记录当前渲染截图，只作为人工对比材料，不把易漂移的逐像素金图纳入门禁。

验收：

- fixture 连续执行结果一致；
- 指标不会因为不同 Flutter 小版本的 Path 字符串格式而漂移；
- 本任务不改变生产绘制结果；
- 六类阻断均有稳定复现证据，不能只写源码字符串断言；
- 现有 freedraw_renderer_test 全绿。

建议提交：

    test: 冻结五种笔刷差异化渲染基线

### T1：修复 shader 注册并关闭 FragmentShader 资源漏洞

目标：先证明当前 shader 在 Windows、Web、HarmonyOS 构建链可被正确编译和加载，再进行纹理调参。

主要文件：

- 修改：
  FlowMuse-App/pubspec.yaml
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/pencil_shader_test.dart

执行步骤：

1. 从 flutter.assets 中移除 shaders/；
2. 在 flutter.shaders 中登记 shaders/pencil.frag，禁止两处重复声明（同时声明会使整个资产构建直接失败）；
3. 最低成本产物闭环：跑一次 `flutter test`，断言 `build/unit_test_assets/shaders/pencil.frag` 已非 GLSL 源文本（IPLR 二进制或 JSON；impellerc 由 flutter test 的资产构建调用，本机历史产物已实证该链路对 shaders 段生效）；
4. 以 `flutter build web`（产物为 SkSL JSON）与 `flutter build hap --no-codesign`（产物为 IPLR；不加 --no-codesign 会因 signingConfigs 为空直接失败）佐证两端产物；本机无 Visual Studio，flutter build windows 不可执行，Windows 桌面构建列入移交清单；
5. 运行应用，确认 PencilShader.init 成功；日志只记状态，不输出路径或绘制内容；
6. PencilShader 使用“未初始化 / 可用 / 不可用”三态，失败结果也要缓存，禁止每帧重试；
7. 缓存一个应用生命周期内复用的 FragmentShader，不再每元素每帧调用 fragmentShader()（engine 逐 draw memcpy uniform 快照，单实例 + 每元素 setFloat 后立即 drawPath 安全；FragmentProgram 无公开 dispose，由 registry 持有至 shutdown）；
8. 提供 visibleForTesting 的 reset（仅 dispose FragmentShader 实例）与 loader 注入点（否则“并发 init 只加载一次”无可确定性断言的入口）；
9. 给 shader 补齐 opacity 和 texture scale uniform，颜色输出保持预乘 alpha；
10. shader 编译或加载失败时继续走现有无 shader 路径，不允许应用启动失败。

测试与构建：

- init 并发调用只加载一次（经注入 loader 计数断言）；
- 失败后第二次 init 不重复加载；
- resetForTesting 会 dispose 已创建 shader 实例；
- 相同 shader 实例可在连续绘制间更新 uniform；
- flutter test 产物断言（见步骤 3）；
- flutter build web；
- flutter build hap --no-codesign。

说明：

- 当前 pencil.frag 使用的 #version 460 core 属 Flutter 官方支持范围，不在没有编译错误证据时改写 GLSL 版本；
- 本任务只建立可用和无泄漏的闭环，不在这里完成最终铅笔视觉调参；
- 若当前 HarmonyOS fork 的 impellerc 无法编译，保留明确失败日志和 fallback，并停止后续 shader 调参，不能伪造“已启用”。

建议提交：

    fix: 修复铅笔 shader 注册与资源生命周期

### T2：建立 BrushRenderProfile 单一真源并冻结压力语义

目标：收敛配置，并让新旧笔迹都不再依赖当前控制器的全局 pressureSensitivity。

主要文件：

- 新增：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_render_profile.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart
  （全局 pressureSensitivity 字段与 drawFreedraw 透传的本体，T2 步骤 9 的落点）
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart
  （湿墨临时元素补 pressureEncoding=1 标记，本地侧文件首轮清单遗漏，v3 补入）
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_type.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/element_renderer.dart
- 修改：
  FlowMuse-App/test/features/whiteboard/editor_core/freedraw_renderer_test.dart
  （:32-47 "sensitivity 改变轮廓"用例按冻结语义改写：当前灵敏度只影响新笔迹编码，不再改变既有 pressures 的渲染；该文件从 T3 清单移入 T2）
- 修改或新增对应测试。

执行步骤：

1. 定义 BrushCapStyle、BrushCompositeMode、BrushRenderProfile（含 taperPhase 语义，见 §6.1）；
2. 将原 _BrushConfig 五种 switch 迁移为 thinningBase/thinningSpan/simulatedThinning；
3. FreedrawRenderer 只读取 profile，不保留第二份参数；buildOutline/draw 删除 pressureSensitivity 参数，改传 pressureEncoded 标记（encoded → thinning=base+span；否则 thinning=base+span×BrushState.defaults[type].pressureSensitivity，常量确定性）；
4. 实现 encodePressure 纯函数（easing=identity 前提写进注释并由单测锁定）；
5. 控制器只在创建自由笔画时编码 pressure（唯一编码点 `_encodeStrokePressure`），圆珠笔和荧光笔传 null；
6. 新元素写 pressureEncoding=1，嵌套合并 flowMuse，不能覆盖 brushType、pageId、归属等已有键；
7. 新元素渲染使用已编码 pressure；旧元素固定使用对应 BrushState.defaults 的 sensitivity；
8. 本地湿墨和远端 live-ink 临时元素都按“已编码”渲染并标记 pressureEncoding=1；
9. 删除 RoughCanvasAdapter 的全局 pressureSensitivity 渲染依赖（字段+透传+controller 同步点）；UI 中的 sensitivity 仅影响后续新笔迹；
10. 将 taper 长度和 visualHalfWidth 定义成 profile 纯函数；
11. 删除旧配置结构和重复常量。

测试：

- 旧元素在默认 sensitivity 下迁移前后 outline bounds 和 opacity 保持等价；
- 切换当前笔刷或 sensitivity 后，已有元素的 outline 完全不变；
- 两个 controller/adapter 使用不同当前 sensitivity 时，同一元素轮廓一致；
- 新建 0.3 与 0.9 sensitivity 的笔迹效果不同，但创建后均稳定；
- 编码后的 pressure 保持 0～1，0.5 中性压力保持 0.5；
- 新 customData 写入不覆盖 flowMuse 其他键；
- 本地湿墨、live-ink 和静态元素使用相同编码压力；
- 每个 BrushType 都有且只有一个 profile；
- 无默认兜底将未知类型静默映射成另一支笔。

验收：

- 旧数据使用确定性默认兼容，新数据保持创建时语义；
- 无新增依赖；
- profile 不持有 Canvas、Paint、Shader 或可变集合；
- 后续 Raster、SVG 可以直接消费该接口。

建议提交：

    refactor: 收敛笔刷配置并固化压力语义

### T3：实现圆珠笔、钢笔、毛笔的几何差异

目标：只通过轮廓选项和可解释的 taper 形成三种明确手感。

主要文件：

- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_render_profile.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 修改（TaperPhase 落地链路，v3.1 补入）：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/rough_adapter.dart
  （drawFreedraw 抽象签名增加分段 phase 参数）
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart
  （实现签名透传）
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart
  （_drawSegment 调用点推导分段 phase：frozen 首块/首段 headOnly、最新尾段 tailOnly、其余 none）
- 修改：
  FlowMuse-App/test/features/whiteboard/editor_core/freedraw_renderer_test.dart

执行步骤：

1. 圆珠笔：
   - thinning 设为 0；
   - 忽略真实 pressure；
   - 使用较窄 sizeScale 和圆头；
   - 不额外生成墨团或随机圆点。
2. 钢笔：
   - 使用 0.05+0.90×sensitivity 的既有压感区间；
   - 使用创建时已编码的压力；
   - 无真实压力时使用温和速度模拟；
   - 首版不加 taper，避免小于 size 的无效针尖；依靠适度压感与圆头区别圆珠笔。
3. 毛笔：
   - 使用强 thinning；
   - start/end taper 由 size factor 转为绝对距离（customTaper 单位即绝对距离）；
   - 初始采用 4×size（起）和 6×size（收）；起笔低于 4×size 时因包内 runningLength<size 丢点，可见起始宽度 ≥75%，渐变基本无效；
   - taper 启用与否由应用侧按原始输入折线长度判断：原始长度小于 3×size 时关闭 taper，单点画可见圆点、短线保留圆头；
   - 分段渲染语义（TaperPhase，见 §6.1）：本地湿墨与静态元素 = full；远端冻结首块/首段 = headOnly；远端最新尾段 = tailOnly（taper 跟随对端笔尖，段冻结后去掉 end taper 是正确行为）；其余段 = none；**整笔尚在尾段（无任何冻结块、可见 tail 含 index 0）时该尾段 = full**（否则常见 ≤64 点短划在远端湿墨期间起笔恒宽、提交瞬间突然长出起锋）。若不做此区分，毛笔会在每个 64 点段边界周期性收针；
   - headOnly 判定：块内最小 startIndex == 0，每次 sync 重判（块合并/重排不丢失 index 0，判定稳定）；
   - “<3×size 禁用 taper”门控在远端分段侧必须按**整条可见笔迹**的原始折线长度（含 leadingPoint）判断，不得用段自身长度（密集慢写时单段可 <3×size 而整笔很长）；
   - terminal 湿墨和静态元素必须输入同一个 taper 纯函数。
4. 对本地湿墨临时元素和静态元素执行同一轮廓函数，不增加第二套“预览参数”。

自动化断言：

- 对同一路径使用两套明显不同压力：
  - 圆珠笔轮廓应完全一致；
  - 钢笔最大局部宽度差异至少 15%；
  - 毛笔最大局部宽度差异至少 25%，且大于钢笔差异。
- 毛笔收锋（绝对距离判据，替换原弧长百分比判据——后者与绝对 taper 数学不相容）：对折线长 ≥ 20×size、**采样间距 ≤ 0.5×size**（更稀疏时首个存活顶点可使起 1×size 探针落到 2×size 处而误判失败）的恒压 fixture，距起点 1×size 与距终点 1×size（沿原始折线弧长）处局部宽度 ≤ 中段（50% 弧长处）宽度的 65%，距起/终点 2×size 处 ≤ 85%；
- 远端分段一致性：同一笔迹按 64 点分段 + headOnly/tailOnly/none 渲染的合并 bounds 与整笔 full 渲染 bounds 每边误差 ≤ 2 逻辑像素，且除真实笔尾外无段边界收针（局部宽度不低于中段 80%）；
- 短毛笔、单点、两点和零压力输入均产生可见结果（单点时包会返回 5 点退化环绕过 outline.isEmpty 兜底，必须靠 <3×size 关 taper 的门控保证可见），不得只有退化 0.01 半径轮廓；
- 圆珠笔端点为圆头，毛笔收尾为轮廓渐缩，而非附加装饰圆点。

人工验收：

- 将五组固定输入用三支笔绘制并盲看，三种结果可无工具栏提示识别；
- 快速划线和慢速划线都无明显宽度跳变；
- 本地笔迹提交后不突然改变形状。

建议提交：

    feat: 强化圆珠笔钢笔与毛笔笔触差异

### T4：实现荧光笔安全叠加与平头效果

目标：在普通画布和聚焦变淡 saveLayer 内都能实现覆盖加深。

主要文件：

- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_render_profile.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/highlighter_rendering_test.dart
- 必要时扩展 Issue #8 静态 painter 像素测试，但不得改变聚焦架构。

执行步骤：

1. 荧光笔使用恒定宽度，忽略 pressure；
2. 端帽改为 flat：直接使用 `StrokeEndOptions.start/end(cap: false)`（包原生平截面，thinning=0 时半径恒定即真平头；禁止自研两端截面或逐点矩形）；拐角处圆弧连接是包标准行为（sharp corner 阈值 size/128），不作缺陷处理；
3. Paint 使用 BlendMode.darken 和约 0.28～0.32 的最终透明度；
4. 禁止为单支荧光笔新增 saveLayer；
5. 在普通画布、深色背景、PDF、透明离屏层、Issue #8 dim 段中验证；
6. 验证两条同色荧光笔重叠区域比单层更深，但黑色文字不会被提亮或洗白。
7. 仅当真机/像素测试证明 darken 在某个后端不可用时，允许该后端回退 sourceOver；回退是内部能力，不增加产品设置。

实现注意：所有像素回读测试必须用普通 `test()` 而非 `testWidgets`（fake-async 区内 PictureRecorder.toImage 永不完成，仓库 export_region_png_test 已有踩坑注释）；flutter test 为软件光栅，像素断言是语义证据，真实后端证据 = Web 构建运行 + hap 产物移交真机。

像素测试必须覆盖：

- 白底单层高亮；
- 白底同色双层高亮（重叠更深）；
- 深灰底和深色 PDF 上的高亮——判据为“不提亮、不消失”（darken 在深色底弱可见是 min 混合的数学预期，记为已知局限，不以“肉眼明显可见”为门禁）；
- 高亮覆盖纯黑路径（黑色不变亮、路径仍可辨）；
- 高亮绘制在透明 saveLayer 后再合成（不消失）；
- 非目标 owner 被 0.22 dim 后仍可见；
- 聚焦目标高亮保持原亮度；
- 全透明背景下不得整条消失。

结构门禁：

- 本任务不得在 freedraw 热路径新增 saveLayer；
- 一条荧光笔最多一次主要 drawPath；
- 不使用 BlendMode.multiply；
- 不使用 BlendMode.modulate；
- 无按元素大小创建额外全屏缓存。

建议提交：

    feat: 实现荧光笔可叠加高亮效果

### T5：完善铅笔纹理与确定性降级

目标：shader 可用时提供自然纹理，不可用时仍有稳定且低成本的铅笔特征。

主要文件：

- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
- 检查并按需修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart
- 检查：
  FlowMuse-App/shaders/pencil.frag
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/pencil_rendering_test.dart

执行步骤：

1. 复用 T1 已建立的 shader 三态和缓存实例，不得另建管理器；
2. shader 可用时：
   - 保持一次主要轮廓绘制；
   - 纹理尺度基于画布坐标和笔宽，避免随视口缩放漂移；
   - uColor 必须包含并正确应用元素 opacity 与 profile opacity；
   - 不在每帧重新编译、加载或创建 FragmentShader。
3. shader 不可用时：
   - 使用首点坐标、笔宽和点序号派生的确定性扰动，不为获取 seed 扩展渲染接口；
   - 生成一条复合纹理 Path 或最多一次额外 drawPath；
   - 禁止每帧随机生成不同结果；
   - 禁止为每个点分别 draw；
   - 禁止改变原始元素数据。
4. 铅笔仍由 perfect_freehand 生成主体轮廓，只在填充或轻量覆盖层体现颗粒；
5. 对 Web、Windows、HarmonyOS 的 shader 可用性分别记录，降级路径必须可测试强制触发。

自动化断言：

- 同一元素连续重绘两次，绘制命令和像素摘要一致；
- 几何位置或输入点不同的笔迹纹理分布不同，但总体透明度和覆盖率处于相同区间；
- shader 强制失败时仍能绘制；
- 长笔迹的额外绘制调用有固定上限；
- 纹理差异可测，但主体轮廓 bounds 不因纹理越界失控；
- 缩放前后纹理不会出现每帧闪烁。

人工验收：

- 铅笔与灰色钢笔可直接区分；
- 慢速涂写不出现规则条纹；
- Web 降级效果不应退回成完全光滑的钢笔线。

建议提交：

    feat: 强化铅笔纹理与跨端降级

### T6：修复自由笔画可视边界、命中与 PNG 裁边

目标：让用户看到的笔迹范围与选择、擦除、场景范围和导出范围一致。

主要文件：

- 新增或放入现有元素工具文件：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/element_visual_bounds.dart
- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/core/scene/scene.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/export_bounds.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/scene_freedraw_hit_test.dart
  FlowMuse-App/test/features/whiteboard/editor_core/export_region_png_test.dart
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_focus_test.dart
  （:154/:219 硬编码 kMaxBrushSizeScale margin 公式，删常量后必红，v3 补入清单）

执行步骤：

1. 实现 elementVisualBounds(Element) 纯函数；
2. FreedrawElement 使用 profile.visualHalfWidth 外扩中心线 AABB，包含最大 thinning、抗锯齿和铅笔纹理余量；
3. Scene.sceneBounds 改用可视边界；
4. Scene.getElementAtPoint 对 FreedrawElement 使用外扩边界；本期保留现有 AABB 命中语义，不扩成逐段精确 hit-test；
5. EraserTool 和 SelectTool 继续复用 Scene 入口，不复制笔刷判断；
6. ExportBounds 对自由笔画使用可视边界后再加普通导出 padding；
7. remote wet-ink bounds 复用相同半径，删除 kMaxBrushSizeScale；
8. 不顺手重写矩形、箭头、旋转元素的既有边界算法。

自动化断言：

- 默认和最大宽度荧光笔的可见外缘可以点击选择、擦除；
- 距离可见外缘之外的点不命中；
- sceneBounds 覆盖五种笔刷真实轮廓；
- 全场景 PNG、选区 PNG 和 AI 视觉附件捕获不裁切五种笔刷；
- 远端湿墨 dim saveLayer bounds 覆盖最大笔宽且不是全屏；
- 1,000 元素场景的边界计算仍为 O(n)，不生成实际 outline。

建议提交：

    fix: 修复自由笔画命中与导出裁边

### T7：让 SVG 导出复用真实轮廓和笔刷语义

目标：导出后仍能识别五种笔刷，不再全部变成等宽中心线。

主要文件：

- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/svg_element_renderer.dart
- 按需修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/svg_exporter.dart
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/svg_path_converter.dart
- 复用：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart
  或抽出的纯轮廓构建函数
- 修改或新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/svg_export_structure_test.dart
  （现状该文件零 freedraw 断言，本任务对它是“新增”，不是推翻既有断言）
- 按需新增：
  FlowMuse-App/test/features/whiteboard/editor_core/rendering/freedraw_svg_renderer_test.dart

执行步骤：

1. 将 buildOutline 保持为无 Canvas 依赖的纯几何入口；
2. SVG 对 FreedrawElement 调用同一 outline；
3. 将闭合轮廓转为 SVG path d，并使用 fill，不再导出 uniform stroke centerline；
4. 颜色、opacity、sizeScale、pressure、taper 均读取 profile；
5. 荧光笔输出 mix-blend-mode: darken；
6. 铅笔使用轻量 SVG pattern 或 mask 近似颗粒：
   - pattern id 必须稳定且在单文档内唯一；
   - 不嵌入大尺寸位图；
   - 若目标查看器不支持 pattern，主体轮廓仍可见。
7. 删除 SVG 内重复的 BrushType 宽度/透明度 switch；
8. 对空点、单点、极短路径做显式输出规则。
9. Excalidraw JSON 继续往返基础 strokeWidth、pressures、brushType 和 pressureEncoding，不增加 strokeWidth↔sizeScale 转换。

自动化断言：

- 圆珠笔、钢笔、毛笔输出的是填充轮廓 path；
- 同一压力 fixture 下，Raster 与 SVG 的轮廓 bounds 误差处于约定容差；
- 毛笔 SVG 起收宽度明显小于中段；
- 圆珠笔不同 pressure 输入的 SVG bounds 基本不变；
- 荧光笔包含 darken 混合声明和正确 opacity；
- 铅笔包含稳定 pattern 引用且重复导出文本稳定；
- SVG 不含第二套硬编码 brush width/opacity switch；
- Excalidraw JSON roundtrip 前后五种笔刷基础 strokeWidth、brushType、pressureEncoding 和轮廓一致；
- 导出的 XML 可被解析，不产生重复 id。

人工验收：

- 使用 Chrome/Edge 和至少一个桌面 SVG 查看器打开；
- 五种笔刷均可见；
- 荧光笔覆盖文字时语义与画布一致；
- 铅笔在不支持混合模式的查看器中至少保留主体线条。

建议提交：

    fix: 对齐五种笔刷 SVG 导出

### T8：调整笔盒的压力交互语义

目标：让现有五槽笔盒表达真实能力，不新造管理界面。

主要文件：

- 修改：
  FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/toolbar_palette_buttons.dart
- 按需修改：
  FlowMuse-App/lib/features/whiteboard/models/editor_preferences.dart
- 修改或新增相应 widget/preferences 测试。

执行步骤：

1. 保留现有五种一键切换和“再次点击当前笔刷打开设置”的交互；
2. 圆珠笔和荧光笔不支持 pressure：
   - 隐藏或禁用压力滑块；
   - 显示简短说明“恒定线宽”；
   - 不删除已持久化的历史 pressure 配置，避免切回其他笔刷时丢失用户偏好。
3. 铅笔、钢笔和毛笔继续显示压力设置；
4. 颜色和宽度的每笔刷独立持久化保持不变；
5. 无鼠标 hover 的触屏端必须能看到当前笔刷和设置入口；
6. 文案保持简短，不增加教程弹窗。

测试：

- 五种 BrushType 的压力控件可见性正确；
- 切换笔刷不会串改另一支笔的颜色、宽度和压力偏好；
- 旧 preference 数据可以正常加载；
- 重新启动后仍恢复上次笔刷和各自参数；
- 布局无溢出以 widget test 验证（平台无关；三端真机布局随移交清单复核）。

建议提交：

    feat: 对齐笔盒压力设置与笔刷能力

### T9：集成测试、性能验证和文档收口

目标：证明完整链路可用，并给 Issue 留下可复查证据。

主要文件：

- 补充 editor_core 渲染、SVG、UI 和协作测试；
- 更新：
  docs/项目说明/项目需求.md
- 必须更新：
  docs/技术设计/前端架构.md
  docs/技术设计/数据模型.md（customData.flowMuse 新增 pressureEncoding 键）
  .agent/decisions.md（ADR：创建时烘焙压力 + pressureEncoding marker + 单一 BrushRenderProfile）
  .agent/architecture.md（编辑器内核渲染链新增 profile 层）
  .agent/ai_usage.md（AI 使用日志，仓库 issue #9 收尾先例）
- 文档与代码分开提交（先功能提交，后独立 `docs:` 提交）；
- 在本计划末尾追加实际提交号、参数、测试计数和人工验收结果。

集成测试：

1. 本地湿墨 -> 静态元素：
   - 五种笔刷的 profile 和轮廓一致；
   - terminal 湿墨与静态元素：同 isComplete 轮廓逐点一致（无参数漂移）；提交时仅末端补全 ≤4px（perfect_freehand 湿墨拖尾设计，main 既有行为，差值为与笔宽无关的常数），其余三边零漂移；
   - 切换笔刷/sensitivity 后历史元素不变化。
2. 远端湿墨 -> 远端静态元素：
   - BrushType 正确传递；
   - 已编码 pressure 正确传递；
   - 边界没有被裁切。
3. 协作：
   - 两个当前 sensitivity 不同的同版本客户端看到相同历史笔刷；
   - Issue #8 聚焦目标和 dim 非目标时，五种笔刷均可见；
   - 切换 focus 不改变文档，不产生网络消息。
4. 导出：
   - PNG 与当前画布一致；
   - SVG 保留主要笔刷差异；
   - Excalidraw/本地存储只新增 customData.flowMuse.pressureEncoding，不修改顶层 schema；
   - 外部导出 sanitizer 对 pressureEncoding 无隐私要求，但 collaborationOwner 规则不得回退。

性能压力：

- 1,000 点和 16,000 点单笔（线性度比值断言：time(16k)/time(1k) ≤ 20，线性=16、O(n²)=256，跨机器稳定）；
- 1,000 个混合笔刷元素；
- 连续快速书写；
- 两人同时远端书写（移交用户，数据层一致性由 MemoryRealtimeTransport 自动化覆盖）；
- Issue #8 聚焦状态下混合五种笔刷；
- 快速缩放和平移。

必须记录（自动化的部分；真机平均/P95/最差帧耗时随 §12.3 移交）：

- 设备与构建模式；
- 平均、P95、最差帧耗时；
- shader 编译或首次使用卡顿；
- 每笔主要 drawPath 数；
- 是否新增 saveLayer；
- 长笔迹内存峰值或明显增长；
- Web 和 Windows 是否触发铅笔 fallback。

建议提交：

    test: 补齐笔盒跨端性能与验收门禁

## 9. 自动化验收矩阵

| 编号 | 场景 | 自动化判定 |
| --- | --- | --- |
| A1 | 圆珠笔压力变化 | 不同 pressure 输入轮廓一致 |
| A2 | 钢笔压力变化 | 最大局部宽度差异至少 15% |
| A3 | 毛笔压力变化 | 差异至少 25%，且强于钢笔 |
| A4 | 毛笔收锋 | 距起/终点 1×size（沿原始折线）宽度 ≤50% 处 65%，2×size 处 ≤85% |
| A5 | 荧光笔重叠 | 重叠区域亮度低于单层区域 |
| A6 | 荧光笔覆盖黑色 | 黑色不得变亮，路径仍可辨 |
| A7 | 荧光笔透明层 | 透明 saveLayer 内不消失 |
| A8 | 聚焦变淡 | dim 后五种笔刷均可见，目标保持正常 |
| A9 | 铅笔确定性 | 同输入连续 100 次命令摘要一致 |
| A10 | 铅笔降级 | shader 失败仍有有界纹理并可绘制 |
| A11 | SVG 轮廓 | 不再使用统一中心线表达五种笔刷 |
| A12 | SVG 毛笔 | 起收和压力差异保留 |
| A13 | SVG 荧光笔 | 包含 darken 和正确 opacity |
| A14 | 湿墨提交 | 同 isComplete 湿/干轮廓逐点一致（无参数漂移）；提交仅末端补全 ≤4px（pf 拖尾常数，与笔宽无关，实测 0.58~3.89），其余三边零漂移 |
| A15 | 远端湿墨 | 无裁边，提交前后笔刷类型一致；64 点分段 + TaperPhase 合并 bounds 与整笔渲染 ≤2px/边，段边界无收针 |
| A16 | 偏好持久化 | 五支笔参数互不串扰且可恢复 |
| A17 | 压力冻结 | 切换当前笔刷/sensitivity 后历史轮廓不变 |
| A18 | 双端一致 | 当前 sensitivity 不同的两端对同一元素轮廓一致 |
| A19 | 单点/短线 | 五种笔刷点击和短划均产生可见结果 |
| A20 | 选择与擦除 | 最大荧光笔可见外缘可以命中 |
| A21 | PNG 边界 | 全场景/选区/AI 捕获不裁切最大笔宽 |
| A22 | shader 注册 | flutter test 后 unit_test_assets 产物非 GLSL 源文本（构建脚本步骤，非 flutter test 内断言）；web/hap 产物佐证 |
| A23 | shader 生命周期 | 经注入 loader 断言并发 init 一次、绘制复用实例、测试 reset 释放实例 |

百分比断言应基于同一 fixture 的相对比较，不使用绝对像素金图。若某项因 perfect_freehand 版本产生合理小幅变化，应调整测量方法，不得直接扩大到失去约束意义的容差。

## 10. 性能与资源门禁

### 10.1 结构门禁

- 普通、圆珠笔、钢笔、毛笔、荧光笔：每元素一次主要 drawPath；
- 铅笔 fallback：最多额外一次复合 drawPath；
- 不在自由笔画元素内部新增 saveLayer；
- 不逐点创建 Paint、Path、Random、Image 或 Shader；
- 轮廓生成维持 O(n)；
- 16,000 点笔迹不得出现 O(n²) 后处理；
- shader 只初始化一次，失败状态也要缓存；
- FragmentShader 不得按元素或按帧创建；
- SVG pattern 不随点数线性膨胀；
- hit/export/wet-ink bounds 使用 profile.visualHalfWidth，不生成 outline、不重复遍历历史点。

### 10.2 运行门禁

Windows、Web、HarmonyOS Profile 应分别执行：

1. 空白画布连续书写 30 秒；
2. 1,000 元素画布连续书写和缩放；
3. 16,000 点长笔；
4. 两端协作同时写；
5. Issue #8 聚焦开启后书写；
6. 快速切换五种笔刷。

目标：

- 不出现持续性掉帧、内存线性增长或 shader 每帧重建；
- 与 main 同场景相比，非铅笔绘制 P95 帧耗时退化不超过 10%；
- 铅笔 P95 退化不超过 20%，且不得阻塞输入反馈；
- 发现 Web shader 不稳定时必须自动使用降级路径，不允许白屏或缺笔迹。

真机数据未采集前，不得用“Windows/Web 已通过”替代 HarmonyOS 验收。

**单代理执行降级口径**（本机无真机、无 Visual Studio）：

- 结构门禁（§10.1）与 drawCall/saveLayer/blendMode 计数全部自动化；
- CPU 微基准复用 `measureStroke`/`StrokeRenderMetrics`（16,000 点长笔、1,000 元素轮廓生成耗时上限断言，证无 O(n²) 后处理）；
- Web 端可选用 `FrameTimingMetricsCollector`（仓库已有，stroke_render_metrics.dart）采集 P95；
- §10.2 六场景真机 Profile、Windows 桌面 Profile、两人同写 → 移交用户清单（§15）。

## 11. 建议执行命令

在仓库根目录：

    git status --short
    git switch -c feature/issue-5-pen-effects
    cd FlowMuse-App

每个任务至少执行：

    dart format <本任务修改的 Dart 文件>
    flutter test test/features/whiteboard/editor_core/freedraw_renderer_test.dart
    flutter test test/features/whiteboard/editor_core/rendering

涉及 SVG 时执行：

    flutter test test/features/whiteboard/editor_core/rendering/svg_export_structure_test.dart
    flutter test test/features/whiteboard/editor_core/rendering/freedraw_svg_renderer_test.dart

涉及 UI/偏好时执行对应测试目录。收口阶段执行：

    flutter test test/features/whiteboard/editor_core
    flutter analyze
    flutter test
    flutter test  # 之后另跑产物探针：build/unit_test_assets/shaders/pencil.frag 非源文本
    flutter build web
    flutter build hap --no-codesign

（flutter build windows 本机无 Visual Studio 不可执行，列入移交清单；hap 不加 --no-codesign 会因空 signingConfigs 直接失败。）

如果仓库基线的 analyze 本身非零，按项目既有规则保存基线并比较 severity + code + file + message 的 multiset，要求本分支零新增；不得为通过门禁顺手格式化或修复无关文件。

最终回到仓库根目录执行：

    git diff --check
    git status --short
    git diff --stat main...HEAD

## 12. 人工验收脚本

### 12.1 单端视觉验收

在 100% 缩放下依次用五支笔绘制相同的：

1. 短横线；
2. 慢速 S 曲线；
3. 快速 S 曲线；
4. 从轻压到重压再到轻压的长线；
5. 有两个急转角的折线；
6. 在同一区域重复覆盖三次。

关闭工具栏提示后，请至少两名测试者判断笔刷类型。圆珠笔、钢笔、毛笔不得出现多数人无法区分的情况。

**单代理等效口径**：五笔同轨迹 fixture 渲染导出 PNG 并排图 + 视觉代理在无标签条件下多次盲判笔型，结果与参数语义对照；产出物移交用户，双人盲测由用户复核（移交清单）。

### 12.2 协作验收

- Web 创建房间，Windows 加入；
- 两端分别切换五种笔刷书写；
- 检查远端湿墨、提交后元素和重新进入房间后的快照；
- 点击协作者头像开启 Issue #8 聚焦；
- 检查荧光笔在正常、目标、dim 三种状态；
- 导出 PNG 和 SVG 后并排查看。

**单代理等效口径**：`MemoryRealtimeTransport` 双端自动化覆盖数据层一致性（A18/A15，仓库已有先例）；可选双 Web 页面（部署服务 124.221.236.179:48931）做可视化双人等效；Web 端单人 Playwright 验收（web-server + 浏览器控制）覆盖交互与导出。真双端（Web+桌面）由用户复核（移交清单）。

### 12.3 HarmonyOS 真机验收（移交用户）

- 使用手写笔和手指分别测试；
- 检查真实 pressure 是否只影响铅笔、钢笔、毛笔；
- 检查长笔、快速转折和连续落笔；
- 记录设备型号、HarmonyOS 版本、构建模式和帧率；
- 若设备可提供倾斜输入，只记录现状，不在本 Issue 临时扩展模型；
- 额外：验证鸿蒙一级压感平滑（pressureAlpha=0.45）与新 profile 二级平滑叠加后的跟手性。

## 13. 提交和回退策略

建议一任务一提交：

1. test: 冻结五种笔刷差异化渲染基线
2. fix: 修复铅笔 shader 注册与资源生命周期
3. refactor: 收敛笔刷配置并固化压力语义
4. feat: 强化圆珠笔钢笔与毛笔笔触差异
5. feat: 实现荧光笔可叠加高亮效果
6. feat: 强化铅笔纹理与跨端降级
7. fix: 修复自由笔画命中与导出裁边
8. fix: 对齐五种笔刷 SVG 导出
9. feat: 对齐笔盒压力设置与笔刷能力
10. test: 补齐笔盒跨端性能与验收门禁

回退边界：

- T1 可回退到始终 fallback，但回退前必须同时避免恢复每帧创建 shader；
- T2 是后续共同依赖，不与具体视觉调参混在一个提交；
- T3、T4、T5 可分别回退到旧 profile 参数；
- T6 可回退可视边界函数，但回退后不得关闭 Issue；
- T7 可独立回退到旧 SVG 中心线，但回退后不得关闭 Issue；
- 铅笔 shader 异常时优先运行时 fallback，不通过全局关闭所有新笔刷；
- 荧光笔 darken 若在特定平台出现引擎问题，应建立平台证据后单独回退合成策略，不得先改为 multiply。

## 14. 风险台账

| 风险 | 等级 | 预防与处置 |
| --- | --- | --- |
| darken 在不同 Flutter 后端结果有偏差 | 高 | 像素测试 + Web/Windows/HarmonyOS 实机；保留 sourceOver 回退开关但不暴露产品设置 |
| shader 在部分构建后端不可用 | 高 | 修 flutter.shaders 注册；显式状态和确定性 fallback，强制失败测试 |
| 全局 sensitivity 改写历史笔迹 | 高 | 创建时编码 pressure；新元素 marker；旧元素使用笔刷默认值 |
| taper 在短路径上吞掉整条笔迹 | 高 | 原始长度 <3×size 禁用 taper，覆盖单点/两点/短线 |
| 荧光笔选择/导出裁边 | 高 | profile.visualHalfWidth 单一真源，Scene/ExportBounds/wet ink 共用 |
| SVG 查看器不支持 blend/pattern | 中 | 主体轮廓始终存在，语义降级而非元素消失 |
| 调参只在鼠标输入上好看 | 中 | 固定 pressure fixture + HarmonyOS 真笔验收 |
| 纹理实现增加每帧分配 | 中 | 结构门禁、draw 调用上限、长笔压力测试 |
| 新旧客户端视觉不一致 | 中 | 本期明确以同版本协作为验收范围，不修改协议 |
| UI 隐藏 pressure 导致偏好丢失 | 低 | 只隐藏/禁用控件，不删除持久化字段 |

## 15. 完成定义

分两栏：A 栏为执行者机器可判定项（本分支内必须全绿）；B 栏为移交用户项（不阻断分支合并，但关闭 Issue 前须完成）。

### A. 执行者机器可判定（必须全绿）

- [ ] 五种笔刷在固定输入下的轮廓宽度、端部形态、混合模式和纹理均有自动化断言差异（A1–A4、A9–A13）；
- [ ] 圆珠笔恒宽、钢笔适度压感（≥15%）、毛笔强压感（≥25%）和绝对距离收锋判据（65%/85%）；
- [ ] 荧光笔重复覆盖加深、覆盖黑色不提亮、聚焦 saveLayer 内不消失（像素断言）；
- [ ] 铅笔 shader 与 fallback 都稳定、确定且有绘制上限（连续 100 次命令摘要一致）；
- [ ] 构建产物中的 pencil.frag 已编译（flutter test 产物断言 + web/hap 佐证），或目标平台有明确且经过测试的 fallback；
- [ ] 切换当前笔刷和 sensitivity 不改变历史笔迹，两端 sensitivity 不同也能一致渲染（自动化）；
- [ ] 本地 terminal 湿墨、远端湿墨和静态元素 bounds 误差满足 A14/A15 分层口径；
- [ ] 五种笔刷单点/短线可见，最大荧光笔可选中、可擦除且 PNG 不裁边；
- [ ] SVG 使用真实轮廓并保留压力、taper、荧光笔合成和铅笔近似纹理；
- [ ] 五支笔的颜色、宽度和适用的 pressure 设置可独立持久化（A16）；
- [ ] 无新增依赖、服务端改动、数据库迁移或协作协议字段；仅新增内部 customData pressureEncoding 标记；
- [ ] 相关自动化测试全绿，analyze 相对基线零新增；
- [ ] Web 构建完成且 Web 端 Playwright + 视觉代理验收通过（五笔截图并排 + 盲判 + SVG 打开）；
- [ ] flutter build hap --no-codesign 通过（构建验证，不等同真机）；
- [ ] 项目需求、技术设计（前端架构 + 数据模型）和本计划的落地记录已更新，.agent 四处同步完成；
- [ ] git diff --check 通过，工作区仅包含预期修改。

### B. 移交用户（关闭 Issue 前完成，不阻断合并）

- [ ] HarmonyOS 真机 Profile 与手写体验验收（§12.3，含一级/二级平滑叠加手感）；
- [ ] Windows 桌面构建与运行验收（本机无 Visual Studio）；
- [ ] 双人盲测复核（单代理已用视觉代理盲判等效，见 §12.1）；
- [ ] 真双端协作房间验收（Web+桌面，§12.2；数据层一致性已由自动化覆盖）。

## 16. 实施记录

本节由实现者在执行过程中持续补充，不得用口头结论代替：

| 项目 | 实际结果 |
| --- | --- |
| 开发分支 | `feature/issue-5-pen-effects`（自 e747a15 切出） |
| 起始提交 | e747a15 |
| 最终提交 | c4eca09（65877e5 docs v3 → 2a5ad89 T0 → be731f3 T1 → bffb268 docs 三轮 → 3aed93a T2 → 8636cf5 T3 → cead827 T4 → b899b1f T5 → 145143b T6 → d3a97ca T7 → d745e19 T8 → b6dd7ae T9 测试 → 40253ec 审查修复 → d44fec8 测试强化 → c4eca09 视觉矩阵；docs 收口提交随后） |
| 最终 profile 参数 | pencil sizeScale 0.82 / opacity 0.68 / thinning 0+0.45 / simulated 0.32 / taper 3×·4×；ballpoint 0.72 / 1 / 0（恒宽圆头）；fountainPen 1 / 1 / 0.05+0.9（默认灵敏度 0.5）；brushPen 1.15 / 1 / 0+1.0 / 0.82 / 6×·6×；highlighter 4.2 / 0.30 / flat + darken / forceSimulate |
| 自动化测试计数 | 全仓 790 全绿 0 失败（本次新增约 60 例：T0 基线夹具、几何 A1–A4/A15/A19、荧光 8、铅笔 8、SVG 10、命中 A20、导出 A21+真实栅格、工具栏语义 6、集成 A14/A17/A18/roundtrip/性能、湿墨长度守护、视觉矩阵 2）；`flutter analyze` 48 条 = 基线零新增 |
| shader 产物/加载结果 | `shaders/pencil.frag` 经 pubspec `shaders:` 段构建期 impellerc 编译（`flutter build web` 产物 unit_test_assets 内 6472B 编译产物实证）；PencilShader 三态缓存，不支持的端（含鸿蒙移植版）静默降级确定性颗粒 Path（收锋区跳过） |
| 新增 saveLayer 数 | 0（荧光笔单笔渲染结构断言 drawCallCount==1、无 saveLayer；darken 可分离混合直接合成） |
| 历史压力兼容 | 旧元素（无 pressureEncoding 标记）按出厂默认灵敏度确定性渲染；A17/A18 以真实状态切换（灵敏度 0.9→0.05、笔形切换）作回归防线，双客户端一致 |
| 最大笔宽命中/导出 | elementVisualBounds 单一真源（size×(0.5+maxThinning×0.5)+2）贯通 Scene 命中/sceneBounds/ExportBounds/远端湿墨 margin；A20 命中双向断言；A21 真实 exportRegionPng 栅格化验证荧光笔几何 AABB 外 3px 已着墨、可视带外为背景 |
| Windows 验收 | 未执行（本机无 Visual Studio，`build windows` 不可行）→ 移交 |
| Web 验收 | `flutter build web` 成功；视觉矩阵盲判 5/5 五判全中（见审查记录 §13）；SVG 经 Chromium 实际渲染通过（darken/pattern/平头端帽与画布一致） |
| HarmonyOS 真机验收 | 未执行（按用户指示跳过 hap 构建；构建链尚余 ohos/node_modules flutter-hvigor-plugin 坏链待 `npm install` 修复后 `PATH=…/ohpm/bin flutter build hap --no-codesign`）→ 移交 |
| 已知降级 | shader 不可用端 → 颗粒 Path；深底荧光笔弱可见（darken 数学预期，不作特判）；SVG pattern 不被查看器支持时主体轮廓仍可见；远端冻结块纹理频率固化于录制时缩放，zoom 变化后与尾段可能短暂失配（提交后恢复，见审查记录 §12.3）；SVG 铅笔 pattern 为装饰性近似（size<6 有 1.5px 下限） |
| Issue/PR | Issue #5；分支待推送、PR 待建（用户流程） |

## 17. 参考资料

- [Goodnotes Pen tool](https://support.goodnotes.com/hc/en-us/articles/7353756785679-Using-the-Pen-tool)
- [Microsoft OneNote Fountain Pen and Brush Pen](https://support.microsoft.com/en-us/onenote/get-started-with-fountain-pen-and-brush-pen)
- [Concepts Workspace and Tool Presets](https://concepts.app/en/manual/workspace)
- [Procreate Brush Studio Settings](https://help.procreate.com/procreate/handbook/5.3/brushes/brush-studio-settings)
- [Microsoft Office Pencil Ink](https://support.microsoft.com/en-us/office/draw-and-write-with-ink-in-office)
- [perfect-freehand](https://github.com/steveruizok/perfect-freehand)
- [Flutter BlendMode](https://api.flutter.dev/flutter/dart-ui/BlendMode.html)
- [Flutter Canvas.saveLayer](https://api.flutter.dev/flutter/dart-ui/Canvas/saveLayer.html)
- [W3C Compositing and Blending](https://www.w3.org/TR/compositing-1/)
- [HarmonyOS Custom Gesture Judgement](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V14/ts-gesture-customize-judge-V14)
