# 触控笔模式下手指对象交互

> 2026-09-25 交互规则已调整：仅选择工具支持手指先点选后拖动，其余工具只允许页面导航。当前方案见 [手指先点选后拖动](2026-09-25-touch-select-before-drag.md)。以下保留原始实现背景。

## Context

触控笔书写模式下，手指当前会被统一当作单指画布导航，无法点选、拖动或调整图片等对象。主流白板产品采用“笔负责书写/擦除，手指负责对象交互和画布导航”的设备分工。

## 需求

- 手指不创建自由笔画、形状、文字、橡皮或激光内容。
- 手指命中对象时支持选择、拖动、缩放、旋转及选中句柄操作。
- 手指命中空白区域时继续支持单指平移；双指缩放/平移保持不变。
- 触控笔行为、Excalidraw 场景格式和协作协议不变。

## 调研结论

- Apple iPad/Apple Pencil：Apple Pencil 是主要书写和标注入口。
- Microsoft Whiteboard：关闭 finger painting 后，手指可点选、拖动对象；双指用于缩放对象/画布。
- Gynzy、Webex Whiteboard：手指负责导航、选择和移动对象，触控笔负责写画和擦除。

## 实现方案

- 在 `SelectTool` 增加无副作用的触摸命中预判，复用既有对象/句柄命中规则。
- 在 `MarkdrawController` 增加触摸对象交互指针状态：命中对象时临时走选择工具，空白时走原有平移路径。
- 触摸在关闭手指绘制与单指平移时明确拒绝，不再意外进入创建工具。
- 分页画布仅在触摸命中空白时截获分页滚动。

## 关键文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/select_tool.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- `FlowMuse-App/test/features/whiteboard/editor_core/editor_preferences_controller_test.dart`

## 验证方案

- 运行触摸输入定向测试。
- 运行 `test/features/whiteboard/editor_core` 全套测试。
- 运行 `flutter analyze`。
- 真机复核 Android/iPad/鸿蒙：笔写画擦、手指点选/拖动/缩放、空白平移、双指缩放。
