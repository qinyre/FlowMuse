# 智能排版第六轮：机器文本（打字文本元素）走同一管线

日期：2026-08-30　分支：`feature/smart-layout-som-echo-fix`
来源：用户需求——"就算全是机器字体，也要可以智能排版，和手写字体走一样的路子，不要只能给手写字体排版"。

## Context

v2 视觉管线目前只把手写簇当"文本候选"：

1. **入口门控**（controller `prepareSmartLayoutTemplates`）：`groups.isEmpty → return null`——纯打字文本页、纯图形页直接被判"没有可排版内容"（UI 提示"本页没有可智能排版的手写内容"）。
2. **打字文本被当图形**：`_smartLayoutFigureUnits` 经 `_smartLayoutPageElements` 收集了全部非手写元素，自由 TextElement 被当作"图"整体搬运——不参与 VLM 文本认领、无标题/正文/图注语义、缩略图显示为灰"图"块。
3. **旧产出被无条件删除**：`_pageScopedOldSmartText`（`flowMuse.smartLayout == true` 的文本）不问认领与否一律进删除清单——一旦打字文本进管线，重跑会把上次产出直接抹掉（数据丢失隐患）。

**方案参考（调研结论）**：MyScript Notes（Nebo）的 responsive layout 让"手写、打字文本、图片"一视同仁参与重排，是同类佐证；无可复用的库。本项目 v2 管线机件齐全，本轮为"重新分类 + 复用既有路径"，无需外部引入。

## 关键事实（勘察结论，改动依据）

- 引擎对非 keepAsInk 文本单元的处理就是"克隆 `unit.textElement` → 模板样式（标题放大/正文缩放/项目符号）→ 进 addElements"——机器文本单元零引擎改动即可获得完整模板待遇。
- keepAsInk 路径按 memberIds 整体移动；`_textInkStrokeIds` 收集**全部**文本单元的 memberIds（不过滤 keepAsInk 标志）——机器文本单元 memberIds 填元素自身 id 后，保留手写模式自动"移动原元素"。
- 匹配器按 markId 直查：typed key 进 `textMarks` 即可被 VLM 认领为文本项。
- 未认领簇会进失败红区（`account()` 对 `clusterRects[key]!` 强解包）——typed key **绝不能**混进 `clusterRects`/`allClusterKeys`，未认领的打字文本应原地保留。
- 转写循环 `_recognizeVisionTextBlocks` 对认领键强解包 `clusterRects`——typed key 必须在调用前过滤掉。
- 进度浮层已兼容 total=0（"正在识别页面…"），纯打字页无转写块不会除零。

## 需求

1. 纯打字文本页可智能排版：入口不再以"有无手写簇"为门槛，页内有可移动内容（手写簇/打字文本/图形）即可发起。
2. 打字文本与手写走同一条路：作为文本标记（SoM 编号）参与 VLM 认字/配对/角色判定，按所选模板重排，享受完整模板样式（标题放大、正文缩放、项目符号）；默认模式"克隆重排"（原文删除、克隆落位），保留手写模式"原元素整体移动"。
3. 打字文本与图配对（VLM pairId + 几何兜底）、参与全文核对；未认领的打字文本原地保留、不进红区。
4. 重跑安全：上次智能排版产出的文本按普通打字文本参与重排，删除无条件清场逻辑。

## 实现方案（全部收敛在 controller 装配区 + UI 文案 + 测试；引擎/内容模型零改动）

关键文件：`markdraw_controller.dart`（准备区 3274-3330、标记区 3666-3695、装配区 3768-3960、账本区 3981-4050、收集区 4535-4570/4700-4720）、`whiteboard_page.dart`（两处文案）、`smart_layout_vision_test.dart`。

1. **门控放宽**：`groups.isEmpty && _smartLayoutPageElements(pageId).isEmpty → return null`（页内既无手写簇也无可移动元素才拒绝）。
2. **图形单元排除自由文本**：`_smartLayoutFigureUnits` 跳过 `containerId == null` 的 TextElement（改当文本标记）；容器绑定文本维持现状（随容器单元整体搬运）。
3. **打字文本标记**：新增 `_smartLayoutTypedTexts(pageId)`（页内自由 TextElement，阅读序），键 `<pageId>:t<N>`，矩形用 `_placementBoundsForElement`；进 `markCandidates`（isText: true）+ `textMarks`，另备 `typedTextByKey`（key → 元素+矩形）供装配直查。
4. **认领分流**：match 后把 textClaims 拆成 `inkClaimsByIndex`（键 ∈ clusterRects，供转写/账本/memberIds）与 typed 键（供单元装配）；转写调用与成功账本、`textClusterRects` 均改用 ink 侧。
5. **打字单元装配**：认领的 typed key → `LayoutUnit(kind: text, textElement: 现有元素, sourceBounds: 矩形, memberIds: [元素 id])`；标题取首个 role=title 且认领 typed 键的项（无墨迹标题时）；pairId 配对与几何兜底、looseTexts 的取单元/取矩形逻辑统一为"index → 墨迹单元或打字单元"。
6. **账本**：认领 typed 元素 id 并入 removeStrokeIds（默认模式克隆替换原件）、矩形并入 removalRects 与 textClusterRects（保留手写模式排除灰区、原元素随 memberIds 移动）。未认领 typed 不入任何清单（原地保留）。
7. **重跑安全**：删除 removeStrokeIds 里 `_pageScopedOldSmartText` 无条件项及死函数（`_pageScopedOldSmartText`、`_smartLayoutGeneratedTextElements` 若无其他消费方）；旧产出作为普通打字文本重新参与排版。
8. **UI 文案**："本页没有可智能排版的手写内容" → "本页没有可智能排版的内容"（whiteboard_page 两处）。
9. **测试**（控制器级，沿用 `_buildController`/`applyResult` 假管线）：
   - 纯打字页：prepare 成功，content 含标题/散文本（来自打字元素），计划 addElements 为带模板样式的克隆、removeIds 含原元素 id；
   - 混合页（手写 + 打字 + 图）：打字文本与图 pairId 配对成 FigureTextPair；
   - 保留手写变体：打字原元素进 moveDeltas、不进 removeIds；
   - 未认领打字文本：不进红区、原地保留；
   - 旧智能排版文本重跑：作为打字文本重排，不丢内容。

## 验证方案

- `flutter analyze` 无新增 error；先跑 `flutter test test/features/whiteboard/`，再全量 `flutter test`。
- 心智回归：纯手写页/混合页/纯图形页/空页四类入口行为；三模板 × 默认/保留手写；草稿→核对→应用/撤销。
- 跨端：纯共享 Dart 层，无 Platform.is*；鸿蒙待真机复验如实记录。
- 后端零改动（协议不变，VLM 只是多看到文本标记）。
- 文档同步：`docs/项目说明/项目需求.md` 智能排版条目追加本轮要点。

## 实施步骤

1. 单代理/主对话执行（文件所有权集中）→ analyze + whiteboard 测试 → 提交推送。
2. ponytail-review 审 diff → 采纳修复 → 全量验证 → 提交推送。
