# 智能排版文案与触控笔模式下的手指选择

## Context

智能排版会话面板仍显示“v3 实时预览”。现有触摸分流只允许选择工具接收对象触摸；画笔、橡皮等工具下手指即使命中图片也只能平移。自由笔迹在选择工具中可通过单点命中，容易误选手写文字。

## 需求

- 应用内将智能排版面板称为“智能排版”，不展示 v3；协议、类型和内部版本标识保持兼容。
- 关闭手指绘制时，画笔、橡皮等非抓手工具下，手指命中图片等可选对象即可点选或在同一手势中拖动，当前工具不切换；空白处仍导航页面。
- 自由笔迹不通过单点新选中；选择工具下用触控笔拉框选择，手指从空白处拖动仍用于平移。已框选的笔迹仍可移动。键盘输入的文本框保留现有点选与编辑方式。
- 双指缩放、防误触、分页滚动和其他输入设备维持既有行为。

## 实现方案

复用 `SelectTool` 的命中、移动和 `ToolResult` 路径，非选择工具触摸命中对象时临时交给该工具。场景命中增加可选过滤条件，使选择路径跳过未选中的自由笔迹，同时允许命中笔迹下方的图片；橡皮和其他调用方保持原有命中规则。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/scene/scene.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/select_tool.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/smart_layout/views/smart_layout_session_panel.dart`
- `FlowMuse-App/test/features/whiteboard/editor_core/`、`FlowMuse-App/test/features/whiteboard/smart_layout/views/`
- `docs/项目说明/项目需求.md`

## 验证方案

定向覆盖非选择工具点选与单手势拖动图片、图片上层笔迹、选择工具下笔/手点按不选笔迹而框选可选、分页和无限画布、空白平移、双指取消及防误触。运行相关 Flutter 测试、全量 `flutter test` 和 `flutter analyze`；没有真机时如实记录设备验证范围。

## 实施步骤

1. 更新文案及对应 Widget 断言。
2. 调整选择命中和触摸路由，并更新相关交互测试。
3. 同步需求文档，执行验证清单。
