# 智能排版修复计划：PPT 版式误报"空间不足" + 同组文本并排问题

> 基于复现测试 `test/features/whiteboard/editor_core/smart_layout_repro_test.dart`：
> 标准页 1588×2246 + 4 行手写（同会话 s1，行距 ~45）+ 2 形状障碍 + 620×620 图片。
> 结果：in_place ✅ / article ✅ / **ppt ❌ 抛 StateError('智能排版没有足够的空白区域')**（`markdraw_controller.dart:3843`）。

## 根因（由堆栈与占位分析锁定）

1. **参与排版的元素被当作障碍物**：`_pptPlan` 内
   `pageOccupied = _smartLayoutSceneOccupancy(excludedIds)[pageId]`，而 `excludedIds` 只含"将被删除的笔迹 + 旧智能文本"。
   猫图（`figure` 组、**要移动**）仍在障碍集合，且以其原始位置（480,620,620,620）参与碰撞；
   布局把图排到目标栏后与原位碰撞，整体下移 40 步也无法避开（图太大）→ `PptLayoutEngine.place` 返回 null → 抛"空间不足"。
2. **同组多个文本被并排成一行**：AI 返回 `body: [b1,b2,b3,b4]` 时，`_pptPlan` 把 4 句合成单个 `PptGroupItem`（memberKeys=[b1..b4]），
   `placeColumn` 按"一行"处理（宽度=各文本宽度之和+间距=~1048，且四句并排），既不美观也不符合"各自找位置"。

## 修复方案

### A. `_pptPlan`（`markdraw_controller.dart`）：参与元素排除出障碍
在 `PptLayoutEngine.place` 调用前，参与排版的既有元素（`rawToUnitKey` 中能在 `pageElements` 解出的 id）加入排除集：

```dart
final participantIds = <ElementId>{
  for (final entry in rawToUnitKey.entries)
    if (pageElements.containsKey(entry.key)) ElementId(entry.key),
};
final pageOccupied =
    _smartLayoutSceneOccupancy({...excludedIds, ...participantIds})[pageId] ??
    const <Bounds>[];
```

（block id 不在 `pageElements` 中不会误加；新增文本未入场景，天然不是障碍。）

### B. `_pptPlan`：同组多文本 → 拆成独立组（各自占一行）
在构建 `items` 的循环里，`isWholeGroup` 判断之前插入：

```dart
final allTextMembers = keys.every((key) => createdTexts.containsKey(key));
if (allTextMembers && keys.length > 1) {
  for (final key in keys) {
    items.add(PptGroupItem(key: key, role: group.role, memberKeys: [key]));
  }
  continue;
}
```

（`units[key]` 已存在（文本测量尺寸）；`placeColumn` 对每个单成员组各占一行、层叠排布。）

## 预期效果

- 图片作为 `figure` 移动后不再与自身原位"打架"；图 620 宽 > 默认 0.62 列宽（549）时走自适应列（图列 620，文本列 800），4 句文字在左列各自占行（4×(≈30)+3×24 ≈ 192 高）→ **构建成功**，预览蓝框覆盖 4 句文字与图片。
- 若某单元宽超整页可用宽才真正失败（保留）。

## 实施步骤

1. 保留 `smart_layout_repro_test.dart` 为**回归测试**（三风格场景）。
2. 修改 `_pptPlan`（A + B）。
3. 运行 `flutter test test/features/whiteboard/editor_core/smart_layout_repro_test.dart` → 三例全过。
4. 运行 editor_core/views/ai_assistant 回归 + 全量 `flutter analyze` / `flutter test`。
5. 提交（中文），不推送（等用户确认）。

## 边界

- mindmap/in_place/article 路径不动（不移动既有元素，障碍语义正确；复现已证明可构建）。
- 竖排模板仍不拆分会话（既有行为）。
