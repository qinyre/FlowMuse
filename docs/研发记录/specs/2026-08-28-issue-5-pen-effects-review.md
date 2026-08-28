# Issue #5 笔刷差异化计划：三路对抗审查记录

> 日期：2026-08-28
> 审查对象：[2026-08-28-issue-5-pen-effects.md](../plans/2026-08-28-issue-5-pen-effects.md)
> 计划基线：main / e747a15
> 审查方式：三路独立对抗审查（渲染几何 / 跨端构建 / 计划完备性）+ 主审复核
> 原审查结论：**不建议按 v1 现状执行**。
>
> 主审复核状态：**部分成立，不得把本记录中的原始修法直接作为实现指令**。v2 计划以本节“主审复核裁决”为准。
>
> 2026-08-28 第二轮：对 v2 再次三路对抗审查，裁决见第 10 节，计划已迭代为 v3。

## 主审复核裁决（2026-08-28）

本文件保留三路审查的原始输出用于追溯，但复核后确认其中既有真实阻断，也有关键技术误判。最终裁决如下：

| 原审查项 | 主审裁决 | v2 处置 |
| --- | --- | --- |
| shader 放在 assets 导致未编译 | 成立 | 改 flutter.shaders，先做构建/加载闭环 |
| 改用 BlendMode.multiply | **否决** | 当前 Flutter 的 multiply 会相乘 alpha；保留 darken，补深色底和透明层像素测试 |
| thinning 架空 sensitivity | 部分成立 | profile 使用 base+span；同时解决 sensitivity 全局状态 |
| taper 小于 size、单点退化 | 成立 | 钢笔首版不加 taper；毛笔按原始折线长度处理，短笔关闭 taper |
| 选择/擦除/PNG 边界不含笔宽 | 成立 | 新增共享 visual bounds 任务 |
| Excalidraw 需要 strokeWidth↔sizeScale 双向映射 | **否决** | JSON 已往返基础 strokeWidth、pressures 和 brushType；只补 roundtrip 测试 |
| 测试不可自动化 | 夸大 | 扩展 SpyCanvas 或直接 PictureRecorder 像素回读即可 |
| perfect_freehand caret 会令 CI 漂移 | 不成立 | pubspec.lock 已追踪并锁定 2.5.2+1 |
| T0 fixture/metrics 分属两目录是路径错误 | 不成立 | 两者职责不同，保留分目录 |
| T1 不可独立回退违反 AGENTS.md | 不成立 | AGENTS.md 只要求一个提交做一件事 |
| T4 整体应早于 profile | 部分成立 | 只把 shader 激活闭环提前，正式铅笔效果仍在 profile 后 |
| FragmentShader 每绘制创建且不释放 | 成立但当前未触发 | shader 激活时同步改为应用生命周期复用，并提供测试释放 |

### 原审查漏报的阻断项：pressureSensitivity 是全局渲染状态

RoughCanvasAdapter 只有一个可变 pressureSensitivity，MarkdrawController 在切换笔刷时覆盖它，而 FreedrawElement 没有保存创建时 sensitivity。结果是切换笔刷可能改变历史笔迹，两个当前 sensitivity 不同的协作端也可能显示不同。

v2 采用最小兼容方案：

1. 创建笔迹时把 sensitivity 烘焙进已有 pressures；
2. 新元素写 customData.flowMuse.pressureEncoding=1；
3. live ink 沿用现有 pressure 数组，不增加协议字段；
4. 旧元素使用对应 BrushState.defaults 的确定性 sensitivity，不再读取当前控制器状态。

以下各节是对 v1 的原始审查记录，行号也均指向 v1；除非明确标为“主审保留”，否则只作为追溯证据，不覆盖本节裁决。

## 0. 原始审查结论摘要（以主审复核裁决为准）

| 结论 | 处置 |
| --- | --- |
| 计划整体骨架（单一 profile 真源、T 序列、回退边界）设计合理，值得保留 | 保留 |
| **T4 前提崩塌**：铅笔 shader 因资产注册方式错误，在全部六端均为死代码 | 必须先修前提再估工 |
| **原判断已被主审否决**：曾建议用 multiply 替换 darken | 不得采纳；v2 保留 darken，并以深色底、透明层和 dim 层像素测试约束 |
| **T2 压力参数设计冲突**：固定 thinning 会架空用户 pressureSensitivity 偏好 | 部分成立；v2 同时修复 sensitivity 未随元素冻结的问题 |
| 擦除命中、选择命中、PNG 导出边界三处**不含笔宽**，改笔刷后会放大既有缺陷 | 补入范围或单列 issue |
| 5～7 人日严重低估，T2/T3/T4 不可并行 | 重新估算 |

---

## 1. 前提崩塌：铅笔 shader 在所有平台都是死代码

### 事实

- `FlowMuse-App/pubspec.yaml:126-132`：`shaders/` 注册在 `flutter: assets:` 下，pubspec 中**没有 `flutter: shaders:` 段**。
- 构建产物实证：`build/flutter_assets/shaders/pencil.frag` 与 `build/web/assets/shaders/pencil.frag` 均为 3916 字节、首行是 `/// Returns a pencil stroke texture,`（即原始 GLSL 源码文本）。全仓构建产物中**不存在任何 pencil.spirv / pencil.sksl**。
- Flutter 仅对 `AssetKind.shader`（即 `flutter: shaders:` 段）执行构建期 impellerc 编译；注册在 `assets:` 下的文件只做原样拷贝。
- 因此 `PencilShader.init()`（`rendering/rough/pencil_shader.dart:20-28`）中的 `FragmentProgram.fromAsset('shaders/pencil.frag')` 拿到的是 GLSL 文本，在 Impeller/Skia 运行时必然抛异常，被 catch 静默吞掉。

### 影响

- `freedraw_renderer.dart:236` 的 `PencilShader.isAvailable` 恒为 false，**铅笔纹理分支从未被执行过**。
- 计划 4.2 节、T4 全流程、风险台账"pencil shader 在 Web/HarmonyOS 不可用（高）"、性能记录项"Web 和 Windows 是否触发铅笔 fallback"——**全部建立在错误前提上**。实际是六端必走 fallback，而不是"部分平台可用"。
- 计划 T4 只写"检查 `shaders/pencil.frag`"，完全没意识到要先修资产注册链路。

### 修法

1. pubspec 增加 `flutter: shaders: - shaders/pencil.frag`，并从 `assets:` 列表移除（两处同时出现会被拒绝）。
2. 构建依赖 `HostArtifact.impellerc`，属 host 工具链而非运行时依赖，**不构成"新增依赖"**。CI 只要能跑 `flutter build` 即可满足。
3. 先做最小闭环验证：改 pubspec → `flutter build windows` → 运行确认日志出现 `PencilShader: loaded successfully`，再动 GLSL。
4. 在此之前，T4 的"纹理尺度基于笔宽""元素 id 派生种子"等需求**无法实现**（现 shader 只有 `uniform vec3 uColor`，频率 `const float freq = 0.7` 硬编码）。

---

## 2. 技术判断错误

### 2.1 【主审否决】BlendMode.darken 的选型理由是错的（T3）

计划称 multiply 会"参与 alpha 计算，在透明离屏层内可能得到透明结果"。按 Flutter/Skia 可分离混合公式 `result = (1-αs)·Cb + αs·[(1-αb)·Cs + αb·B(Cb,Cs)]` 推演（取 αs=0.32、黄 (1,1,0)）：

| 场景 | darken 结果 | multiply 结果 |
| --- | --- | --- |
| 白底单层 | (1, 1, 0.70) | 同 |
| 同色双层 | (1, 1, 0.49) 变深 | 同 |
| 覆盖纯黑 | (0, 0, 0) 不变亮 | 同 |
| 透明 saveLayer（αb=0） | 退化为 sourceOver，α 仍 0.32，不消失 | 同 |

两者逐位一致。真正会在透明层整条消失的是 `modulate`（`ao = αs·αb = 0`），计划把故障模式张冠李戴了。

**且 darken 有 multiply 没有的缺陷**：当背景暗于高亮色时 `min` 恒取背景，深色底/深色 PDF 上高亮完全不可见；multiply 仍会压暗。

原修法“改用 multiply”已撤销。当前项目 Flutter 3.41-ohos 的 BlendMode 文档明确说明 multiply 同时相乘 alpha，任一侧透明会得到透明输出；darken 的输出 alpha 按 srcOver。v2 保留 darken，增加白底、深色底、PDF、透明 saveLayer 和 dim 层像素测试，仅允许证据驱动地回退 sourceOver。

### 2.2 固定 thinning 会架空用户压力偏好（T2）

`freedraw_renderer.dart:74-81` 现状：钢笔走特殊分支 `thinning = 0.05 + sensitivity * 0.9`，默认 sensitivity 0.7 → **0.68**，恰好落在计划给的 0.55～0.70 区间内。

- 计划把 thinning 改成固定值 = 删除"压力灵敏度"偏好，与 T6"钢笔/铅笔/毛笔继续显示压力设置"正面冲突；
- 若改为保留相乘，sensitivity=0.3 时毛笔 0.30 < 钢笔 0.68，A3"毛笔强于钢笔"断言崩塌。

另：圆珠笔与荧光笔 `pressureEnabled=false` → `hasPressure` 恒 false → 实际生效的是 `simulatedThinning`（0.02），**计划表里的 `thinning=0.00` 是死参数**。A1 的 <3% 只有把 `simulatedThinning` 也置 0 才成立。

修法：profile 存 `thinningBase + thinningSpan × sensitivity`，并把 `simulatedThinning` 一并纳入真源。

### 2.3 taper 的两个隐藏陷阱（T2）

- **起笔下限**：`StrokeEndOptions`（stroke_options.dart:199-202）用 `customTaper` 反写 `taperEnabled`（0 → 静默关闭）；且 `get_stroke_points.dart:105-109` 丢弃 `runningLength < size` 的点，故 `taperStart < size` 时起笔退化为 radius 0.01 的针尖而非渐变。计划的钢笔 0.2×size 起收同样无效。起笔 taper 下限应 ≥ 2×size。
- **"按路径长度同比缩放"不可实现**：`runningLength` 是 streamline 插值后的长度，且 `isComplete` 会改变总长。同比缩放会导致湿墨与提交后 taper 不一致，**直接违反计划 §1 与 A14**。修法：改用导出的 `getStrokePoints` 取总长，按绝对上限钳制，且湿墨与静态共用同一值。
- **单点输入回归**：开 taper 的笔型在单点输入时返回 5 点退化环（radius 被 `max(0.01, …)` 钳住），outline 非空，`freedraw_renderer.dart:209` 的圆点兜底**永不触发**，点一下什么都不画（含湿墨）。这是现状缺陷，计划未识别。

---

## 3. 范围遗漏（计划完全未提及）

### 3.1 命中与擦除不含笔宽（高）

- `core/scene/scene.dart:157-158`：命中测试用 `Bounds.fromLTWH(e.x, e.y, e.width, e.height)`，无 strokeWidth 外扩。
- `editor/tools/freedraw_tool.dart:254`：`width: math.max(maxX - minX, 1.0)`，元素边界是**纯中心线 AABB**，不乘 sizeScale。
- 后果：荧光笔 4.2× 半宽（strokeWidth 25 时约 52 px）**完全在擦除/选择热区之外**。T3 改平头后会更明显。
- 计划零提及。这不是本次引入的新 bug，但本次让笔刷更宽更差异化会**显著放大**它。

### 3.2 PNG 导出会裁边（高）

`export/export_bounds.dart:24-25` 只读中心线 AABB + 固定 padding 20。strokeWidth=20 的荧光笔半宽 42 > 20，**必裁**。而 T1 要把 `kMaxBrushSizeScale`（freedraw_renderer.dart:345，现被 `remote_wet_ink_painter.dart:243` 以 ×0.5×1.3+2 消费）改为从 profile 派生——改完无人兜底。`export_region_png_test.dart` 未列入 T5 验证范围。

### 3.3 其他

- **鸿蒙双重平滑**：`harmony_stylus_stroke_smoother.dart:23` 的 `pressureAlpha=0.45` 是一级平滑，profile 的 smoothing/streamline 是二级 → 可能叠加出跟手延迟。T2 未纳入其测试。
- **AI 链路**：已核实不受影响（`ink_recognition_repository.dart:32` 只用 points.length；`smart_layout_ink_clusterer.dart:19-30` 只用中心线宽高比），但计划既不论证也不排除，建议写明。
- **【主审否决】Excalidraw 导入导出不对称**：该判断混淆了 Excalidraw JSON 与 SVG。JSON 已同时序列化基础 strokeWidth、pressures 和完整 customData，解析也会恢复这些字段；Canvas/SVG 在渲染时读取 profile 即可。v2 不新增 strokeWidth↔sizeScale 映射，只补 JSON roundtrip。

---

## 4. 测试可测性（A1～A16 三分法）

测试基础设施事实：

- `test/.../rendering/canvas_spy.dart:9-32` 只记录 drawCallCount / saveLayerCount / saveLayerBounds / pathOrder，**完全不捕获 Paint** → BlendMode、opacity、shader 均测不到。
- 全仓 `matchesGoldenFile` 0 命中、golden 文件 0 个；`static_canvas_painter_focus_test.dart:72` 用 PictureRecorder 但从不 `toImage()` → **零像素回读**。

| 分类 | 断言 |
| --- | --- |
| 可自动化（现状即可） | A1 A2 A3 A4 A11 A12 A13 A15 A16、A14 前半 |
| 需新增设施 | A5 A6 A7 A8(可见性) A9(像素摘要) A14(无跳变) |
| 需扩展测试设施，但可以自动化 | blendMode/opacity/shader、初始化次数、像素可见性；可增量扩展 SpyCanvas 或使用 PictureRecorder 回读 |

补充问题：

- **A1/A4 原口径信息量不足**：圆珠笔应直接断言不同压力输入生成等价轮廓；毛笔应在弧长 10%/50%/90% 处比较宽度，避免只测端点 taper 得到恒真结果。可用导出的 `getStrokePoints` 加测试侧半径计算完成自动化。
- **A9 必须拆分**：命令摘要可自动化，但探针不记 `paint.shader`，shader 分支的确定性根本测不到。
- **"强制失败"无入口**：`pencil_shader.dart` 无 reset API，需新增 `@visibleForTesting`。
- **【主审否决】依赖漂移**：pubspec.lock 已被 Git 跟踪并锁定 perfect_freehand 2.5.2+1，普通 CI 不会因 caret 自动漂移。仍应使用相对几何断言，避免主动升级依赖时出现脆弱测试，但无需为本 Issue 改依赖约束。

---

## 5. 文件路径与规范问题

### 5.1 计划中路径错误的条目

| 计划位置 | 计划写法 | 实际位置 |
| --- | --- | --- |
| T4:393 | `src/rendering/pencil_shader.dart` | `src/rendering/rough/pencil_shader.dart` |
| T5:441 | `src/rendering/svg_element_renderer.dart` | `src/rendering/export/svg_element_renderer.dart` |
| T5:446 | `editor_core/svg_export_structure_test.dart` | `editor_core/rendering/svg_export_structure_test.dart`（已存在） |
| T0:213/215 | 两个新文件分属 `fixtures/` 与 `rendering/` | 【主审否决】职责不同，分目录合理 |
| T7:532 | `docs/项目说明/技术设计.md` | **该文件不存在**；应为 `docs/技术设计/前端架构.md`（见 AGENTS.md:412） |

### 5.2 AGENTS.md 合规问题

- **分支命名违规**：AGENTS.md:361 要求 `feature/<功能名>`，计划:6/:637 用 `feat/`。
- **违反 §10 文档同步**：新增 `brush_render_profile.dart` 属"新模块"，AGENTS.md:412 是强制项；计划 T7 的"按实际架构影响判断是否更新"把义务降为自由裁量，违反 :419。
- **提交粒度**：T7 前缀 test: 同时含文档可改成更中性的提交描述；“T1 不可独立回退违反 AGENTS.md”这一判断撤销，§8.4 只要求一个提交做一件事。

### 5.3 完成定义空洞（第 15 节）

| 现状表述 | 建议改为可量化判定 |
| --- | --- |
| :738"具有明确差异" | 先以轮廓宽度、端部形态、混合模式和纹理的自动化断言为硬门禁；双人盲测仅作非阻断的体验检查 |
| :739"适度/明显" | 直接引 A2/A3/A4 的 15%/25%/50% |
| :740"不消失"（无阈值） | dim 层内 drawPath ≥1 且 pathOrder 非空 |
| :741"稳定" | 连续 100 次重绘 pathOrder 全等、drawCallCount ≤2 |
| :742"无明显跳变" | 湿墨与提交后可视 bounds 各边差 ≤1 logical pixel，并补代表性像素回读 |
| :746"相关测试"（未枚举） | §16 增「测试文件清单 + 用例数」 |
| :747/:748"验收完成"（无产物） | 附构建日志 + 截图 + 房间号；鸿蒙须填设备/版本/P95 帧耗时与相对 main 退化百分比（§10.2:626 的"显著"须定义，如 ≤10%） |

另 §16 缺「saveLayer 新增数」行。

---

## 6. 工作量与执行顺序

**5～7 人日不可信。** v2 已按依赖重排并调整为 8～12 人日。原计划最被低估的是：

- **原 T4**：修资产注册、补 uniform、三端构建/加载验证、确定性降级和 FragmentShader 生命周期都未拆开。`#version 460 core` 是 Flutter runtime effect 支持的形式，本身不是阻断；工期应由 T1 探针结果校准，而非预先断言 GLSL 版本不兼容。
- **T5**：改填充 path 会推翻 `svg_export_structure_test.dart` 大片断言，且 `svg_exporter.dart` / `svg_path_converter.dart` 未列入主要文件。
- **T0**：现有 `freedraw_renderer_test.dart` 仅 48 行 3 用例，离"可重复测量工具"差距大。

**"T2/T3/T4 可并行"不成立（主审保留）**：

1. 三者主文件重叠 `brush_render_profile.dart` 与 `freedraw_renderer.dart:261-313` 同一 switch，无法并行编辑；
2. T4 应**最早**做——T2 的盲看验收依赖铅笔最终形态，而它由 T4 决定；
3. T3 → T5 有硬依赖（SVG 的 mix-blend-mode 由 T3 定义）。

**主审修正后的重排**：T0 基线 → shader 注册/资源闭环 → profile 与压力冻结 → 几何笔刷 → 荧光笔 → 铅笔正式效果 → 可视边界 → SVG → UI/收口。只提前 shader 可行性闭环，避免在 profile 建立前重复实现正式纹理。

---

## 7. 额外发现：FragmentShader 泄漏

`freedraw_renderer.dart:237` 每次绘制铅笔都 `PencilShader.create()!` 新建实例，全仓 `rendering/rough/` 下 dispose 命中数为 0。Flutter 的 `FragmentShader`（ui/painting.dart:1043-1052）需显式 dispose，否则 GPU 侧对象滞留。1000 铅笔元素画布 = 每帧 1000 个；30 秒连续书写约 1800 个。

这与计划 §10.1"不逐点创建 Paint/Path/Random/Image 或 Shader"直接自相矛盾——现状比逐点更粗放。修法：按笔刷缓存单实例、每帧 `setFloat` 覆盖，renderer 销毁时统一 dispose。

---

## 8. 附：审查中已实测确认的事实

| 事实 | 证据 |
| --- | --- |
| shader 未被编译进产物 | `build/flutter_assets/shaders/pencil.frag` 3916 字节、首行为注释；全仓无 pencil.spirv/sksl |
| 命中测试不含笔宽 | `core/scene/scene.dart:157-158` |
| 元素边界为纯中心线 | `editor/tools/freedraw_tool.dart:254` |
| 导出边界只读中心线 + padding 20 | `export/export_bounds.dart:24-25` |
| 聚焦确用透明 saveLayer | `static_canvas_painter.dart:194-195`，dim 0.22 来自 `collaboration_focus_alpha.dart` |
| SVG 内置重复 width/opacity switch | `export/svg_element_renderer.dart:349-370` |
| 探针不捕获 Paint | `test/.../rendering/canvas_spy.dart:9-32` |
| 全仓无 golden 测试 | `matchesGoldenFile` 0 命中 |

---

## 9. 建议的下一步

1. 由计划作者确认第 1、2.1、2.2 三条判断，修订计划对应章节；
2. 先做 T4 的最小可行性验证（改 pubspec → build windows → 看 loaded successfully），据此决定铅笔纹理走 shader 还是纯 Dart 降级；
3. 第 3 节的命中/擦除/导出裁边三项，明确"本期修"还是"另立 issue"，不要留在本期范围外又不记录；
4. 修正第 5 节的 5 处路径错误与 AGENTS.md 合规问题；
5. 按第 4 节三分法重写 A1～A16，删除恒真断言；
6. 按第 6 节重排执行顺序并重新估算工作量。

---

## 10. 第二轮三路对抗审查与主审 v3 裁决（2026-08-28）

审查对象：计划 v2。三路审查员独立核查（渲染几何与算法 / 跨端构建与运行时 / 计划完备性与工程可执行性），对照包源码（perfect_freehand 2.5.2+1 pub cache）、本机 Flutter 3.41.10-ohos-0.0.1-canary1 SDK 源码与 impellerc 实测编译、历史构建产物与全链路 grep。以下为主审裁决，计划已按此迭代为 v3（变更明细见计划 §0）。

### 10.1 渲染几何与算法

| 审查发现 | 主审裁决 | v3 处置 |
| --- | --- | --- |
| 压力编码公式在 identity easing（包默认、现状未传）下严格成立；包半径公式 `size × easing(0.5 + thinning×(pressure−0.5))`，无额外压力平滑/钳制 | 成立 | 公式保留；profile 注释与单测钉死 easing=identity 前提；编码点保持在 controller→tool 交界（全部平滑之后） |
| **A4 弧长 10%/90% 判据与绝对 taper 数学不相容**：taper 开启时起点侧判据恒不可满足（需 L≤0.046×size）；终点侧仅 L≤13.2×size 成立 | 成立（新阻断） | A4 改绝对距离判据：距起/终点 1×size ≤中段 65%、2×size ≤85% |
| 起笔 taper 2×size 因包内 `runningLength<size` 丢点（get_stroke_points.dart:105-109，不回填），可见起始宽度 ≥75%，渐变无效 | 成立 | 毛笔起笔种子上调至 4×size、收笔 6×size；铅笔 3×/4× |
| **远端湿墨 64 点冻结块+尾段逐段独立 getStroke**（remote_wet_ink_store.dart:158-159/500-517、remote_wet_ink_painter.dart:314-317/361-399），毛笔 taper 会在每段边界周期性收针（段末半径钳 0.01），违反 §1 与 A15 | 成立（新阻断，首轮与 v2 均未识别） | 新增 TaperPhase（full/headOnly/tailOnly/none）分段语义；A15 补分段合并 bounds ≤2px/边与段边界无收针断言 |
| 荧光笔平头：`StrokeEndOptions(cap:false)` 原生生成平截面（get_stroke_outline_points.dart:304-315/340-347）；首轮“perfect_freehand 无 cap 概念”系误判 | 成立 | 直接用包原生 cap:false，禁止自研截面；拐角圆弧（size/128 阈值）记为标准行为 |
| 单点输入返回 5 点退化环、outline.isEmpty 兜底永不触发；<3×size 关 taper 门控可保证单点可见 | 成立（复核首轮 2.3） | 门控须覆盖全部渲染入口（含远端分段与 SVG），A19 按此验收 |
| darken 输出 alpha 按 srcOver（SDK painting.dart:806-812 实证）；multiply 确会乘 alpha（:901-917），主审首轮否决正确 | 成立 | 维持 darken；深色底弱可见为 min 混合数学预期，像素判据定为“不提亮、不消失”并记已知局限 |
| simulatedThinning=0 时包内整段速度模拟不执行、半径恒 size/2（get_stroke_outline_points.dart:117/133-134），streamline/smoothing 不影响宽度 | 成立 | 圆珠笔/荧光笔恒宽可达；A1 补 profile 结构断言兜底 |
| measureStroke 缺 brushType 参数（freedraw_renderer.dart:151-157 恒按钢笔测） | 成立 | T0 补参数 |
| “不读取 isComplete 插值后 runningLength”只能对 customTaper 取值成立；包内 te 与 isComplete 末端删点（≤~size/2）仍存在，威胁大宽度 A14 | 成立（措辞修正） | §6.1 改述为“不由插值总长推导 taper 长度”；A14 分层口径（strokeWidth=4 ≤1px 严格；大宽度 ≤size/8，末端删点列为已知差异源） |

### 10.2 跨端构建与运行时

| 审查发现 | 主审裁决 | v3 处置 |
| --- | --- | --- |
| ohos fork flutter_tools 支持 flutter.shaders 段（flutter_manifest.dart:442、assets.dart:156-161、shader_compiler.dart:117-120 显式适配 ohos 目标）；历史 ohos 产物中 shaders 段的 ink_sparkle/stretch_effect 为 IPLR 编译产物而 assets 段 pencil.frag 为源文本——诊断与修法双实证；两处同时声明会使整个资产构建失败（asset.dart:1088-1107） | 成立 | T1 维持迁移方案，强调必须从 assets 移除 |
| pencil.frag `#version 460 core` 经 impellerc 实测编译通过（ohos 目标出 IPLR+spirv；web 目标出 SkSL JSON） | 成立 | 不改写 GLSL |
| engine 逐 draw memcpy uniform 快照（fragment_shader.cc），单实例+每元素 setFloat 后立即 drawPath 安全；FragmentProgram 无公开 dispose、registry 持有至 shutdown；热重载 _reinitializeShader 兼容 | 成立 | T1 生命周期按此实现；reset 仅释放 FragmentShader 实例 |
| **本机无 Visual Studio**（flutter doctor [X]，vswhere 不存在）：flutter build windows 及 Windows Profile/协作验收不可执行 | 成立（新阻断） | Windows 桌面构建/运行列入移交清单；本分支以 web/hap/test 产物链验收 |
| **flutter build hap 默认签名模式必失败**（hvigor.dart:326-335 空 signingConfigs 直接 throwToolExit）；--no-codesign 可行且历史未签名 hap 已佐证 | 成立（新阻断） | 全部 hap 命令改 --no-codesign；真机验收注明签名前提并移交 |
| shader 产物最便宜闭环：flutter test 的 unit_test_assets 由 impellerc 编译（commands/test.dart:785；历史 unit_test_assets 已实证） | 成立（优于计划原 Windows 构建闭环） | T1/§9 A22 采纳该口径 |
| Web canvasKit 加载 SkSL JSON 可行；降级入口即 init 的 catch（现状失败后不缓存，会重复加载） | 成立 | T1 三态+失败缓存 |
| flutter test 像素回读跑在 tester 软件光栅，非真实后端证据；真实后端=Windows(Skia)/Web(canvasKit)/OHOS(Impeller) | 成立 | T4 注明证据等级；darken 真机证据随 hap 移交 |
| 仓库已有 StrokeRenderMetrics/measureStroke、FrameTimingMetricsCollector、StrokeReplayRunner、SpyCanvas 测量设施，计划未点名 | 成立 | §10.2 降级口径点名复用；SpyCanvas 补 blendMode/shader 捕获 |

### 10.3 计划完备性与工程可执行性

| 审查发现 | 主审裁决 | v3 处置 |
| --- | --- | --- |
| **T2/T6 文件清单缺 4 个必改文件**：local_wet_ink_painter.dart（:54-65 本地湿墨临时元素无 marker）、rough_canvas_adapter.dart（:714-739 全局 sensitivity 本体）、freedraw_renderer_test.dart（:32-47 用例必红）、remote_wet_ink_painter_focus_test.dart（:154/:219 硬编码 margin 公式必红） | 成立（新阻断） | 清单补齐；两个测试分别移入 T2/T6 |
| SpyCanvas 不捕获 Paint（canvas_spy.dart:26-30），blendMode/opacity/shader 结构门禁无载体；首轮已指出、v2 未落实 | 成立（新阻断） | T0 增加扩展步骤 |
| 像素测试须用 test() 而非 testWidgets（fake-async 下 toImage 永不完成；export_region_png_test.dart:12-16 已踩坑留注释） | 成立 | T4 写明 |
| PencilShader 无 reset/loader 注入（pencil_shader.dart:20-34），A23 并发断言无入口；FragmentProgram.fromAsset 在 flutter test 未验证（全仓零先例） | 成立 | T1 补注入点与探针 |
| live-ink 协议零改动论证未落盘：LiveInkPoint.pressure 已存在（live_ink_chunk.dart:4-27）、whiteboard_page._broadcastLiveInk 直接透传 view.pressures（:1922-1953）、_drawSegment 构造无 customData 临时元素 | 成立 | §6.3 论证写入计划；湿墨恒按已编码渲染作为规则载体 |
| svg_export_structure_test.dart 现零 freedraw 断言（:79-176），首轮“推翻大片断言”不成立，T7 实为新增 | 成立 | T7 注明 |
| T9 文档同步缺 4 处：数据模型.md（customData 新键）、.agent/decisions.md、.agent/architecture.md、.agent/ai_usage.md（issue #9 收尾 commit 36451d2 先例）；文档应独立 docs: 提交 | 成立 | T9 清单扩充 + 拆分提交 |
| 不可行验收项未裁剪：双人盲测、真机 Profile（integration_test/README.md:2/26 自身规则禁止无真机结论、measurementEligible 需 kProfileMode+physicalDevice）、docker/go 不在 PATH 致本地服务端不可起 | 成立 | §12/§15 按执行者能力二分：视觉代理盲判等效、MemoryRealtimeTransport 双端自动化、真机/双端/双人/Windows 桌面移交用户 |
| A1 现状即通过（ballpoint pressureEnabled=false 已丢弃真压感），区分度弱 | 成立 | 保留为守护断言 + 补 profile 结构断言 |
| 属性面板固定 4 档粗细不在 issue 验收标准内但计划未留痕 | 成立 | §3.2 补“不做”记录 |
| 顺序与依赖、提交序列、分支名、回退策略 | 无新问题 | 维持 |
| 鸿蒙一级平滑叠加手感风险（首轮 §3.3 提出、v2 未处置） | 成立 | 风险台账 + §12.3 移交项补记 |

### 10.4 第二轮结论

三路一致：**v2 需修订**。共 2 个渲染几何新阻断（A4 判据不相容、远端分段收针）、2 个构建新阻断（无 VS、hap 签名）、4 个文件清单缺口、1 个测试载体缺口。主审已全部裁决并迭代为 v3；v3 增设“执行者机器可判定 / 移交用户”二分完成定义。第三轮复审（针对 v3 修订本身）结论见第 11 节。
