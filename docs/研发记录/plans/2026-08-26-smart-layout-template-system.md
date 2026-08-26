# 智能排版版式模板系统实施计划（全风格深度重做）

> 分支：`feature/smart-layout-templates`（自 feature/ai-smart-layout 新开）。
> 需求方逐条确认：竖排自动识别并保持竖排；单列/配对流水平居中；title 置顶+居中+加大+不配图；
> 范围=全风格深度重做，采用**版式模板系统**架构。

## Context（含调研结论）

图二实测暴露的问题链：竖排文字（"惬意小猫"）被行簇拆分误拆成单字碎片（现防误拆只看页面模板）→
碎片毁掉图文配对与版式；单列流全靠左不居中；title（"反思总结"）无特殊处理被配到图旁；OCR 个别错字
（模型侧，不在代码保证范围）。

调研结论（两轮：同类 + 跨领域，出处见附录）：
- 工业界唯一被验证的路线 = **语义角色分类 + 模板槽位填充**（PowerPoint Designer/WPS 的实际做法），
  模板选择规则固定即天然确定；
- **配对在结构层完成，版式层永不拆散**（LaTeX float 与 HTML figure/figcaption 的共同经验）；
- 竖排惯例 = **几何判竖排 → 旋转 90° 送识别 → writing-mode 语义渲染**（Tesseract psm5/_vert、CSS writing-mode）；
- 配对度量用"垂直间距最小 + 水平重叠率"（pdfminer line_margin 思想），不用完整 XY-cut 递归；
- 不引入：Cassowary 约束求解、dagre/ELK、学习型生成模型（不可复现）、模板评分系统（固定 4-5 模板用 switch）。

## 需求（澄清结论）

| # | 结论 |
| --- | --- |
| R1 | 竖排自动识别：簇形态判断（bbox 高/宽 > 1.5 → 竖排列），整列不拆；识别图像旋转 90° 送 OCR；文本元素标记 `writingMode:vertical` 保持竖排渲染（渲染分支已存在） |
| R2 | 图文配对升级为结构层：垂直间距最小 + 水平重叠率 ≥0.3 的贪心唯一配对，title 不参与；配对在结构层绑定，版式层不拆散 |
| R3 | title（AI role==title）：置顶 + 水平居中 + 字号加大（max(原字号, 28)）+ 不参与配对 |
| R4 | 单列/配对流每个单元在页面内容区**水平居中**；双列两栏整体水平居中 |
| R5 | 架构：统一"版式内容模型 + 模板接口"，四风格收编为模板实现；基座能力（竖排/配对/居中/标题）在结构层统一生效 |
| R6 | OCR 错字不在代码保证范围（受字迹与模型影响） |

## 实现方案

### 1. 结构层内容模型（新文件 `smart_layout_content.dart`）

```dart
/// 一页排版的语义结构（结构层产物，版式模板只消费它）。
class SmartLayoutContent {
  final String pageId;
  final Rect contentArea;
  final TextUnit? title;                 // AI role==title；置顶居中加大、不配图
  final List<FigureTextPair> pairs;      // 图文配对（结构层已绑定）
  final List<LayoutUnit> looseTexts;     // 未配对文本
  final List<LayoutUnit> looseFigures;   // 未配对图/形状/组
}
class LayoutUnit { String key; Rect sourceBounds; Size size; LayoutUnitKind kind;
  TextElement? textElement; Element? element; bool vertical; }
class FigureTextPair { LayoutUnit figure; TextUnit caption; bool figureAbove; }
```

构建入口 `SmartLayoutContentBuilder.build(...)`（收编现 `_pairTextAndFigures` 并升级）：
- 文本块：AI role（groups role==title → title；body → 候选）；竖排块带 `vertical` 标记与竖排度量；
- 配对度量升级：**垂直间距最小 + 水平重叠率 ≥ 0.3**（替换中心距离贪心；title 不参与）；
- 图/形状/组 → LayoutUnit（组用并集 bounds）。

### 2. 模板接口（新文件 `smart_layout_template.dart`）

```dart
abstract class SmartLayoutTemplate {
  String get id;
  SmartLayoutPlan? layout(SmartLayoutContent content, SmartLayoutTemplateContext ctx);
}
```
`ctx` 携带 occupied/page/引擎常量。四实现（**收编现有函数，逻辑不重写**）：

| 模板 | 收编自 | 行为变化（相对现状） |
| --- | --- | --- |
| `PairFlowTemplate`（ppt·配对图文流） | `_pptPlan` 单列分支 | 每单元水平居中；title 置顶居中加大 |
| `TwoColumnTemplate`（ppt·双列分栏） | `_pptPlan` 双列分支 | 两栏整体水平居中；title 同上 |
| `MindmapTemplate` | `_mindmapPlan` | title 作为根节点优先（若 AI 给出）；其余不变 |
| `ArticleTemplate` / `InPlaceTemplate` | `_legacyPlacementPlan`/article 分支 | 竖排 writingMode 生效；其余不变 |

模板选择：`_planForStyle` switch（ppt 内部：content.pairs 非空 → PairFlow，否则 TwoColumn）。
`smart_layout_ppt_engine.dart` 保留为两模板共用的列布局工具（不删除，避免双份）。

### 3. 竖排（识别层 + 结构层）

- `SmartLayoutInkClusterer`：入口新增会话级形态判定——bbox 高/宽 > 1.5 → 整会话单簇不拆
  （`# ponytail: 混合横竖会话 v1 不分离，出现再按主导形态拆`）；
- `_renderInkBlockPng`：竖排簇 PNG 解码后旋转 90°（顺时针）再编码送识别（`ui.instantiateImageCodec`）；
- 识别结果回填：竖排块文本元素 `customData.flowMuse.writingMode = 'vertical'`，尺寸用
  `_measureSmartLayoutText(vertical: true)`（已有），排版按竖排尺寸参与。

### 4. 控制器接线

`_pptPlan`/`_mindmapPlan`/`_legacyPlacementPlan` 改为：构建 `SmartLayoutContent` → 选模板 → `layout()`
→ 现有 `SmartLayoutPlan` 产物（草稿态/底部条/撤销链路全部不变）。

## 复用点（ponytail 阶梯结论）

复用：`SmartLayoutPlacement`、`SmartLayoutInkClusterer`、`MindmapLayout`、`TemplateAnchorResolver`、
`SmartLayoutMoveBuilder`、`_measureSmartLayoutText(vertical:)`、`_fontSizeForRecognizedBlock`、
草稿态/底部条/历史链路。
不新建：约束求解器、图布局库、模板注册表/评分器、混合横竖分离、新交互。
新增文件仅 2 个（content + template 接口），模板实现为现有函数的收编包装。

## 验证方案

1. 新增测试：
   - 聚类器：竖排 4 字（x 窄 y 长）→ 1 簇；横排多行 → 多簇（回归）；
   - 结构层：配对（垂直间距+水平重叠）、title 不配图、竖排块 vertical 标记；
   - 模板：PairFlow 单元居中（centerX==contentArea.centerX）、title 置顶居中加大、
     TwoColumn 两栏整体居中、竖排单元 writingMode；
   - 图文配对既有回归（错序修复）继续通过。
2. 回归：全量 `flutter test`（现 540 例）+ `flutter analyze` 0 error。
3. 手动验收：用户同页（反思总结/惬意小猫/懒羊羊）重测，期望=原稿语义结构的美化版式。

## 实施步骤（每步可验证、可回退）

1. `smart_layout_content.dart`：模型 + builder（配对升级 + title 提取 + 竖排标记）+ 单测。
2. 聚类器竖排形态判定 + 单测。
3. 竖排图像旋转送识别 + writingMode 回填 + 单测（解码宽高互换断言）。
4. `smart_layout_template.dart` 接口 + PairFlow/TwoColumn 收编（含居中/title）+ 单测。
5. Mindmap/Article/InPlace 收编（行为不变重构）+ 回归。
6. 控制器接线切换 + 全量门禁 + 文档同步（项目需求.md + 本计划执行结果）。
7. 提交（中文，不推送）。

## 边界与风险

- 混合横竖同会话 v1 不分离（整会话按主导形态判定）——`ponytail:` 标注，出现场景再按主导形态拆；
- OCR 错字不保证（R6）；
- 重构面覆盖四风格：以"先收编后切换、每步全量测试"控制回归风险。
