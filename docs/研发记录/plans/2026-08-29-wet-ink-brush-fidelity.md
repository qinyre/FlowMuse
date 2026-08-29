# 计划书：湿墨预览与最终渲染笔形一致化（WYSIWYG 缺陷修复）

- 日期：2026-08-29
- 状态：**定稿 v3**（两轮三路对抗审查收敛：第 2 轮三路判定均可执行、无 P0/P1 残留）
- 计划分支：`fix/wet-ink-brush-fidelity`（自 `feature/issue-5-pen-effects` 切出——修复依赖 ADR-020 BrushRenderProfile / pressureEncoding，均在该分支）
- 前置关系：PR #20（Issue #5）待评审收口；本修复是其后续缺陷修复，不阻塞 #20 评审
- 验收边界：代码级门禁（analyze + 全量测试）+ 子代理代码审查；**真机/web 手感由用户验收，本任务不做**

## 1. 问题描述

用户实测观察：五支笔（钢笔/圆珠笔/铅笔/毛笔/荧光笔）中，只有钢笔的书写中轨迹与最终效果基本一致；其余笔形在未松手时轨迹一律呈"钢笔状态"，松开后整条笔画才渲染为目标笔形（铅笔颗粒纹理、荧光笔平头端帽+darken 混合、各笔 sizeScale/opacityScale 差异等）。

影响：书写过程所见非所得；荧光笔尤甚（darken 叠色只在松手后出现）。

## 2. 问题所在（根因链，全部代码核实，行号为 2026-08-29 工作区实测）

1. **生产默认湿墨路径是场景内预览**：`writing_feature_flags.dart:7` `layeredWetInk` 默认 `false` → `editor_canvas.dart:339-346` 走 `controller.buildPreviewElement(toolOverlay)`，预览元素混入场景画布渲染（唯一消费者，全仓核实）。
2. **根因 A（笔型回退）**：`markdraw_controller.dart:3096-3109` `buildPreviewElement` 的 freedraw 分支构造预览 `FreedrawElement` 时**未写 customData**；`applyDefaultStyleToElement`（:1001）只拷样式字段。渲染端 `element_renderer.dart:167` 以 `brushTypeFromCustomData` 解析笔型，`brush_type.dart:116` 缺省返回 `fountainPen` → 预览按钢笔 profile 渲染。
3. **根因 B（压力语义回退）**：同一处缺失使 `element_renderer.dart:170` 的 `pressureEncodingFromCustomData` 返回 false，`freedraw_renderer.dart:96-104` 把**已编码**压力经 `effectiveThinning(legacySensitivity)` 按旧灵敏度仿射映射（easing=identity，brush_render_profile.dart:29-33）重新解释，而提交端（pressureEncoding=1）走 `profile.maxThinning`——带真实压感的笔形（铅笔/钢笔/毛笔）即使笔型恰好一致，预览线宽也与终稿不同。两层回退同源于"预览元素缺 customData"。
4. **提交端正确**：`freedraw_tool.dart:242` `_buildElement` 以 `customDataWithFreedrawRender(null, context.brushType)` 写入 brushType + `pressureEncoding=1` → 松手后按真实 profile 渲染，形成"变身"。
5. **钢笔"一致"的巧合**：笔型回退默认值恰为 fountainPen（根因 B 仍使其有轻微宽度漂移，肉眼不显）。
6. **正确实现已存在但未启用**：分层湿墨 `local_wet_ink_painter.dart:66` 已正确写 customDataWithFreedrawRender，但被环境开关默认关闭（性能特性另行立项，本修复不翻转）。

### 2.1 已核实一致、无需改动的疑似项

- **压力数据同源**：`freedraw_tool.dart:44` `_previewPressures` 是 `_pressures` 不可变视图，overlay（:203）与提交元素（:259）共用，值为 controller `_encodeStrokePressure`（:445-455，冻结笔型+灵敏度）编码后值。
- **simulatePressure 同语义**：预览（controller:3104-3106）≡ 提交（tool:260 `!_hasRealPressure`），真值表一致。
- **样式同源**：预览（:3114）与提交（:1080 经 `applyResult → _applyDefaultStyleToResult`）过同一 `applyDefaultStyleToElement`（同一 `_defaultStyle`）；copyWith 的 customData 用 `?? this.customData` 保留（`freedraw_element.dart:159`）。
- **中途切笔**：67e65bd 落笔冻结 `_strokeBrushTypeOverride`，`toolContext`（:667）与主修表达式逐字同源。
- **远端湿墨不受影响**：笔型走 `stroke.style.brushType`（`remote_wet_ink_painter.dart:291/490`）。
- **协作实况广播不受影响**：`onLiveInkChanged` 播的是 `buildLiveElement`（tool:160-165 → `_buildElement:242`，已带 customData），不上述屏、与预览元素无交集。

### 2.2 预览/提交元素的良性差异（渲染中性，测试按"渲染入参等价"归一，不做逐字段断言）

`isComplete` false/true（收针固有差异，§3.2 测试归一化处理）；坐标系（预览场景系点 + x=0/y=0 vs 提交相对点 + x/y=min，渲染经 `_absolutePoints` 抵消，`element_renderer.dart:157-161`）；width/height 1.0 下限钳制（仅提交有，FreedrawRenderer 不消费）；seed 42 vs 默认（FreedrawRenderer 不引用）；recognition keys 仅提交有（消费方只扫场景元素，预览从不入 scene）。

## 3. 计划方案

### 3.1 主修（P0）

`buildPreviewElement` 的 freedraw 分支补：

```dart
customData: customDataWithFreedrawRender(
  null,
  _strokeBrushTypeOverride ?? _activeBrushType,
),
```

- **必须用 `customDataWithFreedrawRender`**（brush_type.dart:154-169，同时写 brushType + pressureEncoding=1，一次闭合根因 A+B）；**禁止换用 `customDataWithBrushType`**（:135-150，不写 pressureEncoding，压感笔预览宽度仍漂移）。
- 时序同源保证：冻结在 :2235（先于首次 `onPointerDown`:2238）→ 提交在 ≈:2440-2448（`onPointerUp`+`applyResult`）→ 冻结清除在 ≈:2451→:2739（提交之后；行号实施时以代码为准）——`toolContext.brushType` 与主修表达式全笔生命周期取同一快照。
- 修复点唯一且充分：`buildPreviewElement` 消费者仅 `editor_canvas.dart:341/344`（另一测试消费者 `controller_content_bounds_test.dart:43` 只断言 x/y/points，不受影响）；`pendingPreviewElements`（editor_canvas.dart:459-462）是流程图/思维导图预览，与 freedraw 无关；png 导出/文本编辑均走 StaticCanvasPainter 不传预览。
- 预览元素为临时对象（固定 id `__preview__`，从不入 scene、不序列化、不参与协作/撤销），无数据兼容性风险。只动 freedraw 分支，形状工具零波及。

### 3.2 回归测试（P0）

**A. 行为测试**（新建 `test/features/whiteboard/editor_core/wet_ink_preview_fidelity_test.dart`，controller 全链路驱动，参照 `freedraw_pressure_test.dart` 的 stylus 事件手法；直接构造 ToolOverlay 有先例 `controller_content_bounds_test.dart:42-49`）：

1. 逐笔形（遍历 `BrushType.values`）书写中 `buildPreviewElement` 产物：`brushTypeFromCustomData` == 冻结笔形 且 `pressureEncodingFromCustomData` == true
2. 中途切笔（pencil 落笔 → 切 highlighter）：预览仍 pencil；抬笔后新笔画恢复 highlighter（对齐既有 P2-2 用例结构）
3. 无压感路径（鼠标驱动 + 圆珠笔/荧光笔）：预览 pressures 空、simulatePressure=true、brushType 正确（修复后该路径的可见变化全部来自根因 A 的 profile 参数——荧光笔 sizeScale 4.2+darken 最明显；pressureEncoded 仅在 hasPressure 时被读取（freedraw_renderer.dart:96-104），无压感路径下该翻转渲染中性）
4. 单点 overlay → `buildPreviewElement` 返回 null，不崩溃
5. 预览 id 恒为 `__preview__`、抬笔后 scene 无该元素、连续两帧构建互不污染（R2 断言落地）
6. 协作实况广播元素仍自带 brushType + pressureEncoding=1（扩展 `freedraw_pressure_test.dart:107-137` 节流用例，R4 断言落地）
7. 形状工具冒烟：rect/ellipse/diamond/line/arrow 预览类与字段不变、无 brushType customData；eraser/laser 预览为 null（R3 断言落地）
8. 负断言：预览 customData 不含 recognition keys（预览不入 scene，理论上无影响，锁死）

**B. 渲染测试**（新建 `test/features/whiteboard/editor_core/rendering/wet_ink_preview_rendering_test.dart`；**必须经 `ElementRenderer.render(element, adapter)` 渲染**——brushType/pressureEncoded 解析发生在 element_renderer.dart:167/170，直调 `FreedrawRenderer.draw` 传参则 customData 不参与、测不出本缺陷；**两侧共用同一 adapter 实例与渲染口径**；复用 `canvas_spy.dart` SpyCanvas 与 `brush_stroke_fixtures.dart` 五组笔迹几何夹具（恒压 0.5、无笔型维度，笔型维度由测试遍历 `BrushType.values`）；像素回读用裸 `test()`（先例 highlighter_rendering_test.dart:16-18）；铅笔用例 `PencilShader.init()` + tearDown 重置）：

1. 五笔**命令摘要**逐笔一致（预览 vs 提交）：drawCallCount / pathBlendModes / pathAlphas / shaderPathCount 相等；提交侧 `copyWithFreedraw(isComplete: false)` 归一化（荧光笔 darken + alpha 断言在内；铅笔只断言两侧相等且绘制次数 ≤2 的互斥性——"shaderPathCount 恰为 1"是环境敏感绝对断言，留给 pencil_rendering_test.dart:92-93 专测，避免双卡点）
2. 五笔**像素摘要**逐笔一致（同归一化口径，rawRgba 逐字节）
3. **突变哨兵（防假绿）**：无 customData 的预览渲染与提交渲染在非钢笔四笔上必须不同——证明本测试组真能抓住原始缺陷。排除钢笔是必要而非保守：夹具恒压 0.5 恰为 encodePressure 仿射映射的不动点（brush_render_profile.dart:198-203），钢笔预览/提交在此输入下本就逐字节相同，后人勿"补全"钢笔哨兵后误判测试失效
4. 真压感笔形：预览与提交 pressures 逐点相等（§2.1 数据同源回归锁）

**C. 本地性能护栏（确定性计数，非墙钟；writing_perf 探针为 integration+profile+真机专用，本地不可用）**：

1. 轮廓上界：`measureStroke`（freedraw_renderer.dart:163-194）对固定合成样本断言 outlinePointCount 上界（铅笔/荧光笔；`StrokeRenderMetrics` 仅 outlinePointCount/getStrokeDuration/pathBuildDuration 三字段，不含颗粒数）
2. 颗粒上界：引用既有覆盖（pencil_grain_path_test.dart:13-81 已含 maxGrainCount 硬上限、双绘确定性、密度不变性），不新增；如需显式断言可直调 `buildPencilGrainPath`（freedraw_renderer.dart:351，@visibleForTesting）+ PathMetrics，≤ `maxGrainCount`（:348）；荧光笔无颗粒路径（grain 仅 pencil 分支）
3. 分支门禁：SpyCanvas 断言 shader 可用时铅笔渲染走 shader 路径、不触发颗粒 Path（互斥门禁，与 B1 呼应；PencilShader 真实加载在测试环境可行，先例 pencil_shader_test.dart:8/15）

**D. 既有套件回归**：freedraw_pressure / freedraw_renderer / local_wet_ink_painter / remote_wet_ink_painter / brush_visual_matrix / pencil·highlighter_rendering / scene_freedraw_hit_test 全绿；`flutter analyze` 41 零新增；**实施首步复跑 `flutter test` 以实际计数为准并回填 §5**。

### 3.3 性能评估（代码级论证，真机留验）

- **前提修正（一审路 2/路 3 指正）**：静态画布**无** picture 缓存，本就整帧全量重绘（static_canvas_painter.dart:164-246；revision 缓存仅存在于远端湿墨与默认关闭的分层湿墨）。故本修复的边际成本 = **预览笔画自身按真实 profile 渲染的成本**（与提交端同函数 `FreedrawRenderer.draw` 同量级），不存在"缓存被打破"问题。
- **铅笔（shader 可用，主流平台默认；main.dart 启动预加载）**：与修复前同为一次轮廓构建 + 一次 drawPath，差异仅 5 次 setFloat（pencil_shader.dart:151-155；shader 单实例复用 :66-75），CPU 增量≈0；GPU 仅对预览笔画像素跑程序化噪声。**颗粒 Path 与 shader 路径互斥**（freedraw_renderer.dart:305），不存在叠加。
- **铅笔（shader 降级平台）**：每帧颗粒 Path（O(n) 点、≤4096 段硬上限、每粒 2 次 sin）+ 每帧新建 Path + 一次 drawPath；成本随当前笔画长度 O(n) 增长、整笔累计 O(n²)，常规笔画仅数百颗粒，低端 A55 估 1-3ms/帧（未实测，真机留验）。
- **荧光笔**：sizeScale 4.2 属参数级放大（轮廓顶点/填充面积随宽度增长），无新绘制命令类型；darken 为 paint.blendMode 直绘（:267-271 显式不隐式 saveLayer），live 与终稿同机制，**无新增 saveLayer 成立**。
- **钢笔/圆珠/毛笔**：仅 profile 参数差，可忽略；另增每帧 customData 2 个 map 分配（brush_type.dart:154-171），可忽略。
- **协作实况叠加说明**：strokeLiveMode 开启时低配机同时承担场景预览渲染与节流广播（:2365/:2688-2701），既有成本，本修复仅加重预览侧（同上分平台结论）。
- **顺带优化（P2，同 PR，二审后改为保守方案）**：降级路径 `_polylineLength` 每帧重复计算 3 次（buildOutline :83、draw :306、buildPencilGrainPath :359）。**只合并 :83/:306 两处（3→2）**：draw 内算一次分段长度，同值传 buildOutline（语义等价）；buildPencilGrainPath :359 **保持自算不动**——因为 draw 降级分支的 `wholeLength`（供 skipStart/skipEnd taper 距离）与 grain 内部 `totalLength`（供步长/循环界/remaining 门）在远端分段渲染下是**两种长度**（整笔折线长 vs 分段局部弧长，remote_wet_ink_painter.dart:124-125/:378-381 传整笔长），若把整笔长注入 grain 将改变分段颗粒步长并错置 skipEnd 门。曾考虑 `totalLengthOverride` 可选参数方案，因语义陷阱弃用。
- **R1 后备（真机卡顿时触发）**：live 侧颗粒降档（live 渲染 maxGrainCount 用 1024，终稿不变）——触发条件=用户真机反馈铅笔书写掉帧；届时二选一（降档 or 铅笔 live 回退普通描边）另行确认。

### 3.4 明确不做

- 不翻转 `layeredWetInk` 默认值（性能特性另行立项）。
- 不改远端湿墨、序列化/SVG 导出、撤销/重做、`isComplete`/收针语义。
- 不做真机/web 自动化测试（用户验收）。

## 4. 可执行度

- **改动面**：主修 1 处（约 5 行含注释）+ `freedraw_renderer` 长度传递顺带优化 + 新增测试 2 文件（A 组 8 例、B 组 4 例）+ C 组护栏 2 例 + D 组既有扩展 1 处；`buildPreviewElement` 与冻结字段同属 `MarkdrawController`，无跨模块改动。
- **事实基础**：根因链 6 点 + 排除项 6 点 + 修复点唯一性全部带行号核实，且经三路独立审查复核。
- **门禁本地闭环**：analyze 41 基线（已实测）+ flutter test 计数实施时钉死（上次实测 826 全绿）。
- **风险与对策**：
  - R1 铅笔热路径 → §3.3 分平台论证 + C 组本地护栏 + 后备降档方案明确；真机留验。
  - R2 预览 id 与缓存交互 → 预览由 static_canvas_painter.dart:252-267 直绘、不进任何缓存结构（adapter 层 drawFreedraw 为 rough_canvas_adapter.dart:718，直连 FreedrawRenderer.draw）；A5 断言落地。
  - R3 形状工具波及 → 仅动 freedraw 分支 + A7 冒烟锁。
  - R4 协作实况误伤 → 来源不同（buildLiveElement vs buildPreviewElement）+ A6 断言锁。
  - R5 像素摘要跨环境不稳定 → 以命令摘要为主判据、像素摘要为辅（先例 highlighter/pencil_rendering_test 已跨环境稳定）；裸 test() 避开 testWidgets 踩坑。
- **可执行度评级：高**——单点修复、事实链完整、门禁全本地、后备方案明确。

## 5. 审查迭代记录

### 第 1 轮（2026-08-29，三路子代理）

| 路 | 判定 | 关键 findings | 处置 |
|---|---|---|---|
| 1 正确性/架构 | 可执行 | P2×1：根因链漏 pressureEncoding 第二层回退（element_renderer.dart:170 → legacy thinning 解释已编码压力），所选 API 恰好同时闭合；P3×5：修复点唯一性/时序链/良性差异/缓存键/strokeLiveMode | 全采纳：§2 补根因 B、§3.1 补禁换 API+时序链+唯一性、§2.2 补良性差异、§3.3 补实况叠加 |
| 2 性能/热路径 | 需补护栏 | P1×3：**"静态块 revision 缓存"论据错误**（静态画布本就整帧重绘）；**颗粒与 shader 互斥非叠加**；writing_perf 本地不可用须换确定性护栏；P2×2：live O(n)/整笔 O(n²) 措辞、_polylineLength 每帧 3 次；P3×2：荧光笔措辞、saveLayer 论证成立 | 全采纳：§3.3 重写（前提修正/分平台/互斥/O(n²) 明示/顺带优化纳入）、§3.2 增 C 组护栏、R1 后备具体化 |
| 3 测试完备性 | 需补 | P1×2：像素摘要须归一化 isComplete 否则必失败；**渲染测试必须经 ElementRenderer.render**（直调 FreedrawRenderer 测不出本缺陷）；P2×4：无压感路径/R4/R3/R2 断言落地；P3×7：marker 笔形名错误、单点/负断言/基建先例/计数口径 | 全采纳：§3.2 重构为 A/B/C/D 清单（A8 例 B4 例 C2 例 D 回归），B3 突变哨兵防假绿，§2.2 归一化口径声明 |

### 第 2 轮（2026-08-29，三路收敛复核）

| 路 | 判定 | 残留项 | 处置 |
|---|---|---|---|
| 1 正确性/架构 | **方案无误，可执行**（无 P0/P1） | P2×1：C1 措辞按字面不可实现（metrics 无颗粒数字段）；P3×4："高斯"措辞（实为仿射 easing=identity）、R2 文件名勘误（rough_canvas_adapter.dart:718）、A3 括注失准（pressureEncoded 无压感路径渲染中性）、夹具定名（五组笔迹几何而非五笔夹具）+ B3 钢笔排除原因注记、"5 次 setFloat"补行号 | 全部采纳并落入正文（C1 与路 3 意见合并处理） |
| 2 性能/热路径 | **性能论证成立，可执行** | P2×1（N1）：顺带优化的整笔长/分段长语义陷阱 → **采纳保守方案（3→2，grain 保持自算），弃用 totalLengthOverride 方案**；P3×2（N2）：C1 拆分（metrics 三字段+颗粒计数引用既有覆盖）、行号勘误 | 采纳，§3.3 顺带优化改写、C 组重构、R2 勘误 |
| 3 测试完备性 | **测试计划充分可执行**（13/13 处置正确） | 实施提示×2：B1 铅笔"shaderPathCount=1"为环境敏感绝对断言（改为两侧相等+≤2 互斥，=1 留专测）；B 头注补"两侧同 adapter"；C1 与既有覆盖重叠（颗粒上界引用既有）；P3×3：R2 引用改 static_canvas_painter.dart:252-267 并删 hashCode 句、:2451 行号模糊化、§3.3 行号近似声明 | 采纳，B1/B 头注/C1/R2/时序行号已修订 |

**收敛结论**：三路第 2 轮判定均为可执行，无 P0/P1 残留；全部文字级修订已回填。计划书冻结为定稿，进入实施。

## 6. 实施记录（2026-08-29）

- **提交**：`68a6a93`（计划书）→ `002bf72`（fix）。分支 `fix/wet-ink-brush-fidelity`。
- **实施细化（B 组，符合 §2.2 口径）**：预览快照是书写中间态（点位天然少于终稿），直接与终稿逐字段比较必然不等——按"渲染入参等价"把提交元素的点位/压力/模拟标志对齐到预览快照（customData/样式保持提交端）后断言同入参同输出。
- **实施发现（生产语义正确，测试适配）**：预览元素持有工具 `_points`/`_pressures` 的**活视图**（`UnmodifiableListView`），抬笔 `_clearStrokeState` 清空底层列表。生产上预览只在书写中被逐帧渲染、抬笔即弃，无影响；测试需在抬笔前拍不可变快照（`copyWithFreedraw` + `List.of`）。
- **B4 口径落地**：改为"预览拿到编码压力（∈[0,1] 且 ≠ 原始值）且为提交端前缀"——逐点相等受模型器批处理时序影响，前缀+编码域断言既锁数据同源又不脆弱。
- **门禁**：`flutter analyze` 41=基线零新增；`flutter test` **840 全绿**（基线 826 + 新增 14：A 组 8 + B 组 4 + C 组 2）。
- **待真机验收（用户）**：五笔书写中即时呈现目标笔形（铅笔颗粒/荧光笔 darken/各笔宽度透明度）、书写中切笔预览不跳变、低端安卓平板铅笔书写流畅度（触发 §3.3 R1 后备降档则反馈）。

## 7. 真机回归：起笔压力爬升闪变（2026-08-29）

**现象（用户真机验收反馈）**：毛笔/铅笔落笔后 ~0.5-1s 内仍呈"钢笔态"，随后闪变目标形状；钢笔/圆珠笔/荧光笔正常。

**诊断（双通道实测，OPD2404）**：
- 应用侧探针（提交元素烘焙压力序列）：每笔起笔 p≈0.25-0.33，第 2 点起 0.39-0.46；首点与第 2 点间隔 100-200ms（慢起笔被模型器 minDistance 丢点）。
- 内核 `getevent touchpanel_pen`（ABS_PRESSURE 0-16383）原始压力流：**每笔起笔压力真实爬升**——seg2 0.22→0.67/1.2s、seg3 0.33→0.72/0.5s、seg8 0.26→0.50/0.9s、seg9 0.19→0.52/0.8s。
- 结论：代码管线全程同步无延迟；爬升是自然书写发力（轻触→压实），应用如实渲染 → 压感笔形（毛笔/铅笔 thinning 强）前段过细、压力到位瞬间整笔增宽被感知为闪变。圆珠笔/荧光笔 `pressureEnabled=false` 全程模拟压感不受影响；钢笔宽度变化细微无感。

**修复（起笔攻击补偿）**：`InputPolicy` 新增 `pressureAttackMs/pressureAttackLevel`（手写笔 250ms/0.50，触摸/鼠标 0=关闭）；`StrokeInputModeler._pressureOut` 窗口内输出不低于"攻击水位→pressureFloor 线性衰减"包络，只抬输出不改滤波状态，真实压力高于包络时透传，窗口后纯实测；提交元素烘焙同一补偿，WYSIWYG 不破。顺带修正 gap 旁路（>200ms）中 `_lastTime` 滞后于压力计算致使滤波时间戳/包络窗口用过期时刻的既有小瑕疵。

**门禁**：模型器测试 23 例（新增攻击包络 4 例；"明显曲线"测试显式关窗保持指数语义本意）、analyze 41=基线、全量 **844 全绿**。探针已还原。
