# 智能排版第五轮：图旁标签绑定与对齐协调

日期：2026-08-29　分支：`feature/smart-layout-som-echo-fix`
来源：用户真机复测走查（标题 + 两图各带上方标签/侧方"图N"/下方"图N介绍" + 底部两句正文）。

## Context

第四轮修复后复测发现三类新问题：

1. **图旁标签不绑图**："图1""图2"侧标与"小懒羊睡觉""小猫"上方标签被转写成散落正文。根因有二：
   - `FigureTextPair` 一图只容一注（controller 3876/3918，"各取第一项"/"一图至多一注"），下方"图1介绍"先占位后，侧标"图1"落空；
   - 几何兜底候选只有"caption 角色"和"图N 模式（≤6 字）"，上方短标签（body 角色、非图N）不在候选内。
2. **图片不对齐**：handout 网格中两只窄图的孤行（奇数对）落**左列**（engine `_tryHandout` pending 行），与整行居中的宽图/散图混排后"一张居中一张偏左"。
3. **文字排布死板**：looseTexts 一律单块一行左对齐；图注与图的相对对齐关系弱，观感"文字与图片不协调"。

**方案参考（跨领域调研）**：图注-图归属的成熟做法即"最近距离分配"——PDFFigures（Clark & Divvala, AI2）用 caption-to-figure 就近分配并处理"一注邻多图"的区域划分；天文文献数字化管线（arXiv 2209.04460）"按 caption 中心与图底边距离最小化配对"。借鉴其就近分配 + 距离最小化思想，扩展为"一图多标签、一文只归一图"（我们场景标签天然多于注，反向分配更稳）。文字行装包借鉴排版引擎的 greedy line packing（按序贪心装行、行内共享基线）。未找到可直接复用的库，均自行实现（纯 Dart 几何计算，无许可证问题）。

## 需求

1. 图旁短标签（上方/下方/侧方，含"图N"字样）全部绑定到图，不再以散落正文出现；一图可挂多个标签，一文只归一图。
2. 图片尽量对齐：孤行图整行居中（与宽图/散图一致），两两成行的图保持列对齐；图注与图对齐（居中于图）。
3. 文字不死板单块一行：looseTexts 按阅读序贪心装行，一排可放多块文字（行内 top 对齐、行距一致），放不下换行；长段独占行为不变。

## 实现方案（复用点：现有聚类/配对骨架、引擎 _moveUnit/压缩档位、inkSlotRects、withTextAsInk）

关键文件：`smart_layout_content.dart`、`smart_layout_template_engine.dart`、`markdraw_controller.dart`（3844-3935 配对区、4361-4441 兜底区）、对应测试（repro/vision/engine/template_sheet）。

1. **FigureTextPair 多标签重构**（content.dart）：`caption + figureAbove` 改为 `topTexts + bottomTexts`（List<LayoutUnit>，原稿 top < 图 top 归上、否则归下；确定性按原稿阅读序）；`textUnits`/`withTextAsInk` 覆盖全部标签；`figureAbove` 字段删除（由列表语义取代，grep 确认无其他消费方）。
2. **标签分配（controller 配对区）**：
   - VLM pairId 主注先落位（按原稿几何归上/下列表）；
   - 兜底候选扩展：caption 角色 / 图N 模式（≤6 字，间隙 64/96pt）**或** 去空白 ≤10 字且与图包围盒间隙 ≤64pt 的文本块；
   - 分配：一图可收多标签、一文只归最近图（间隙升序贪心，同分图 top 小者优先、文本 index 兜底），已被认领文本跳过。
3. **handout 布局（engine）**：
   - 孤行（单只窄图对）改整行居中（不再落左列）；
   - 单元格渲染：上图上标签栈（bottom 对齐图顶-gap）、下图下标签栈（top 对齐图底+gap），栈内与图水平居中；
   - 行高计算计入标签栈；压缩档位逻辑不变；
   - looseTexts 贪心装行（间隙 24pt，行内 top 对齐，行左对齐），looseFigures 整行居中不变。
4. **outline**：挂靠小图/独占行图的标签栈同样居中堆叠（沿用上/下列表）；正文条目仍一条一行。
5. **inplace 不变**（标签原位保留天然邻图）；keepAsInk 路径覆盖标签栈（各标签墨迹逐一移动占位）。
6. **测试**：repro 新增用户实测场景（两图各带上标签/侧图N/下图注 + 底部两句），断言：标签全部入对（looseTexts 仅剩底部两句）、孤行图中心 ≈ 内容区中心、图注栈居中于图、两句共行、不重叠 ⊆ 内容区；keepInk 变体同过；既有 engine/vision/template_sheet 测试随结构重构更新。

## 验证方案

- `flutter analyze` 无新增 error；`flutter test test/features/whiteboard/` 全绿后全量 `flutter test`。
- 心智回归：识别→选卡→草稿→应用/撤销；typed 与保留手写两模式；三模板。
- 跨端：纯共享 Dart 层，无 Platform.is*；鸿蒙未真机复验如实记录。
- 文档同步：`docs/项目说明/项目需求.md` 智能排版条目追加本轮要点。

## 实施步骤

1. 单代理执行（文件所有权集中，避免并行冲突）→ analyze + whiteboard 测试 → 提交推送。
2. ponytail-review 审 diff → 采纳修复 → 全量验证 → 提交推送。

## 备案

≤10 字且距图 ≤64pt 的文本会收作图标签（计划明示取舍）：紧贴图的一句话笔记会被重排进标签栈，真机复验时关注此类误收，必要时收紧为 caption 角色/图N 模式双条件。
