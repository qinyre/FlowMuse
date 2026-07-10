# PDF 视口边界修复设计

## 目标

恢复 probe 分支已经验证的 PDF 阅读行为：

- 打开或首次导入 PDF 笔记时，首屏适配第一张 PDF 背景页。
- 平移和缩放后的可视区域不能离开整份 PDF 背景覆盖范围。
- 普通分页笔记和无界笔记继续使用原有视口行为。

本次不处理元素渲染裁剪，也不改变 PDF 数据、协同协议和导出格式。

## 根因

main 当前从 `CanvasLayout.pages` 隐式推导 PDF 边界，并使用
`MarkdrawEditor` 外层约束作为画布尺寸。该实现与 probe 的
`contentBounds + canvasSize` 调用链不等价：

- PDF 边界依赖布局元数据，元数据缺失或尚未同步时约束失效。
- 外层尺寸包含工具栏等区域，不等于实际绘图画布尺寸。
- 导入与重新打开流程没有像 probe 一样显式执行
  “设置画布尺寸 → 设置内容边界 → 适配第一页”。

## 设计

### Controller

`MarkdrawController` 恢复独立的运行时 PDF 边界状态：

- `contentBounds`：PDF 背景元素整体边界；`null` 表示无限画布。
- `canvasSize`：`EditorCanvas` 实际绘图区域尺寸。

所有视口更新继续通过 `applyResult`，并在 `UpdateViewportResult` 上统一调用
`clampViewportToBounds`。覆盖手形工具平移、滚轮缩放、双指缩放、缩放按钮、
重置视口和程序化视口更新。

设置或更新 `contentBounds`、`canvasSize` 时立即重新 clamp 当前视口。
画布旋转或窗口缩放只重新 clamp，不自动跳回第一页。

### PDF 生命周期

首次导入和重新打开 PDF 笔记时：

1. 从 `isPdfBackground` 元素计算联合边界。
2. 获取 `EditorCanvas` 报告的真实画布尺寸。
3. 设置 controller 的 `canvasSize`。
4. 设置 controller 的 `contentBounds`。
5. 仅在本次打开流程中执行一次第一页适配。

若场景中不存在 PDF 背景，则清空 `contentBounds`，保持普通无限画布行为。

### UI 尺寸来源

`EditorCanvas` 的 `LayoutBuilder` 是画布尺寸唯一来源。删除或停止使用
`MarkdrawEditor` 外层尺寸参与 PDF clamp，避免工具栏、侧栏和安全区造成偏差。

## 兼容性

- PDF 约束不包含平台判断，多端行为一致。
- 普通笔记的 `contentBounds` 始终为 `null`，行为不变。
- 不修改元素模型、序列化字段或后端同步协议。
- 保留 `CanvasLayout` 负责分页和页面归属，但不再把它作为 PDF 视口边界的唯一来源。

## 测试

- PDF 导入后使用真实画布尺寸适配第一页。
- 重新打开 PDF 后适配第一页。
- PDF 平移到四个方向的远端时均被拉回边界。
- 滚轮、双指和按钮缩放不能产生边界外可视区域。
- 画布尺寸变化后重新 clamp，但不跳回第一页。
- 普通分页和无界笔记仍可移动到远离原点的位置。
