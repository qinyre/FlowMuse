# Android 书写 P0：性能回退恢复

## Context

`2a0def5` 为实时协作笔迹在每个 freedraw move 中构造完整
`FreedrawElement`。该构造发生在是否协作的判断之前，会让普通 Android
书写也重复扫描、复制整笔点和压感数组。

## 目标

恢复非协作书写的原有热路径；协作时仅以 80ms 节流构造临时完整元素。
不调整输入滤波、笔刷参数、渲染器、数据格式或鸿蒙适配。

## 实现

1. `FreedrawTool.onPointerMove` 只追加输入点；仅 `buildLiveElement` 显式
   构造协作临时元素。
2. `MarkdrawController` 在协作回调存在时以 80ms 定时器请求临时元素；
   抬笔/取消/销毁时取消等待任务，取消时仍立即发送已发临时笔迹的墓碑。
3. `WhiteboardPage` 只在 `collaborating` 时注入协作回调，收到元素后直接
   复用既有 `broadcastElements` 发送。
4. 为工具层补测试：move 不生成完整元素、显式快照才生成，并保持 ID/
   version/墓碑语义。

## 验证

- `flutter test test/features/whiteboard/editor_core/freedraw_pressure_test.dart`
- `flutter analyze`
- `flutter test`

## 跨端影响

共享代码仅在是否注入协作回调时改变行为；Android、鸿蒙和其他端的非协作
输入模型、One Euro 参数及最终 Excalidraw 元素均不变。
