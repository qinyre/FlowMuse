# PDF 协作中新笔迹不可见：排查与复现

排查日期：2026-11-11。代码基线：main `ab117719`。本轮只排查，未修改业务代码、协作协议、数据库或原生工程，未发布应用。

后续已按用户要求在独立分支实施修复；本文件下文保留修复前的排查证据，当前修复与验收结果见[修复计划及实施记录](../plans/2026-11-11-pdf-collaboration-ink-visibility.md)。

## 现场信息与结论边界

- 200 多页 PDF，华为 MatePad 11.5S 与一加平板双端协作。
- 开始书写和翻页正常，随后新写的几个字消失；此后双方新写笔迹都消失，双方观察相同。
- 故障前更早的字仍可见，PDF 底图正常；不可见笔迹仍能被套索选中。
- 结束协作、退出并重新进入后可正常书写。没有确认原先不可见的旧字是否也恢复。
- 未提供现场应用源提交、故障页码、笔型、现场日志或场景快照。

**已在当前代码上确定性复现真实缺陷：协作补排序索引将新笔迹排到 PDF 底图下面。** 此缺陷能同时解释上述现象，是本次事件的高置信候选；缺少现场证据，不能宣称已经证明那一次事件的唯一原因。

## 发散假设与逐项结果

| 假设 | 证据与结果 |
| --- | --- |
| 协作覆盖/删除了笔迹 | 不能解释仍可选中。复现中笔迹 points、opacity、isDeleted 均正常，所有元素保留；真正变化的是 index。降低优先级。 |
| 湿墨清除后正式笔迹未接上，或工具清空了提交点列表 | 正式 points 使用独立 `.toList()`，pressures 使用不可变副本；提交创建新 Scene 并通知。未发现正式元素隐藏 ID 集合；湿墨与预览回归通过。降低优先级。 |
| 静态缓存不失效 | 画布 build 主动释放显示列表，shouldRepaint 检查 scene/viewport/layout/图片等；现有静态缓存像素回归通过。未找到持续双端不刷新路径。 |
| PDF 页数/大坐标导致 clip 或 Picture 裁剪 | 300 页布局、第 1/2/51/101/200/300 页、缩放 0.25/0.75/2，共 18 组，直绘、缓存 miss/hit 逐像素一致且可见，湿墨也可见。未覆盖真机 GPU。 |
| PDF 图片解码失败或内存压力 | 解码失败首先影响底图/占位，不直接隐藏自由笔画；现场底图正常。未找到 200 页阈值。不能据此排除真实设备显存问题，但已有更直接的可复现原因。 |
| 创建者聚焦/透明度 | 聚焦只降至 0.22，选中元素全亮，且聚焦不经网络同步；不符合双方只有后续新字全消失。 |
| PDF 标记丢失、变为普通前景图片 | 检查到的序列化和文件状态更新保留 customData。没有找到正常链路丢失标记的证据；无需丢失标记就能复现遮挡。 |
| PDF 和笔迹排序混乱，底图覆盖新字 | 真实 Repository 增量流程和双控制器像素测试均复现，与旧字保留、双端一致、可选中、重开新写恢复吻合。最高优先级。 |
| 坏元素使 paint 中途异常退出 | 绘制没有逐元素异常隔离，理论上成立，但未找到正常输入制造坏元素的触发链或现场异常。保持未证实，不作为结论。 |

## 已确认的触发链

1. 本地恢复笔记时，`MarkdrawController.loadFromContent`（`markdraw_controller.dart:6114`）调用 `SceneDocumentConverter.documentToScene`（`core/io/scene_document_converter.dart:76`），默认给所有现有元素重新生成 `V`、`VV` 等字母索引。这是正常恢复流程，不需要手动调整图层。
2. `FreedrawTool._buildElement`（`editor/tools/freedraw_tool.dart:280`）新建笔迹不赋 index，因此为 null。`Scene.orderedElements`（`core/scene/scene.dart:34`）将 null 排最后，新笔迹暂时画在 PDF 上方，表现正常。
3. 本机终笔广播走 `CollaborationRepository.broadcastElements`（`collaboration_repository.dart:815`），把原始 null-index 笔迹并入 `_latestScene`。它不会在此时归一化本机索引。
4. 对方任意元素增量到达，`WhiteboardPage._applyRemoteElements`（`whiteboard_page.dart:2713`）调用 `reconcileRemoteElements`（`collaboration_repository.dart:1124`），对整个 `_latestScene` 合并，其中包含自己之前刚写的多笔。
5. `SceneReconciler` 先排序，再用八位数字补缺失索引（`scene_reconciler.dart:50、81`），例如 `00000221`。数字字典序小于已有 `V...`，使这些新笔迹排到底图之前。
6. `reconcileRemoteElements`（`collaboration_repository.dart:1137`）返回全部索引修复项，即使它们不是此次远端消息里的元素。本机刚写的多笔因此可能一次性一起改变排序。
7. `Scene._canvasLayers`（`scene.dart:56`）只将普通插图单独置顶，**PDF 底图和笔迹仍在同一 content 序列内按 index 混排**；`StaticCanvasPainter`（`static_canvas_painter.dart:195`）按此顺序绘制。白色不透明 PDF 盖住先画的新字。
8. 书写中湿墨在独立的上层绘制，正式笔迹移入静态场景后才受底图顺序影响，因而出现写时可见、终笔或随后同步时消失。元素本身未删除，选择仍能命中。双方继续交替书写，就持续给彼此触发此路径。
9. 退出房间本身不直接修复排序。本地重新加载会重新生成字母索引，此后新笔迹仍为 null、暂排最后，因而新写恢复。**这并不保证被遮住的原有笔迹自动恢复**；重新序列化可能已经保留错误的相对顺序。

光标/presence 不触发上述元素合并，首个对端元素消息才会触发。这解释先写数笔正常、随后一批消失。220 页并非必要条件，单页也能重现。

## 本轮验证证据

诊断代码与合成图片放在 Git 忽略目录 `FlowMuse-App/build/diagnostics/`，没有读取用户真实 PDF 或账号数据。以下“通过”表示成功断言当前缺陷及其反证，**不表示已修复**。

从 `FlowMuse-App` 执行：

```powershell
flutter test --no-pub build/diagnostics/pdf-ink-visibility/repro_delta_test.dart --reporter expanded
flutter test --no-pub build/diagnostics/pdf-ink-visibility/repro_reconciler_only_test.dart --reporter expanded
flutter test --no-pub build/diagnostics/pdf-ink-visibility/visibility_probe_test.dart test/features/whiteboard/editor_core/rendering/static_canvas_render_cache_test.dart test/features/whiteboard/editor_core/rendering/wet_ink_preview_rendering_test.dart --reporter expanded
flutter test --no-pub build/diagnostics/high_page_ink_probe_test.dart
```

- Repository 增量复现：1 项通过。内存房间中先广播本机四笔，仅一次远端 delta 返回五项索引修复（本机四笔 + 对端一笔），全部位于底图之前；旧字索引不动，第二轮新笔同样沉底。
- 纯合并器复现：1 项通过。八个元素全部存在、无删除，旧字保持原对象和索引。
- 像素复现及既有静态缓存/湿墨预览检查：10 项通过，其中像素复现分别覆盖 1 页与 220 页。使用真实 Repository 合并、Controller 协作应用、StaticCanvasPainter 绘制；两端均旧字可见、新字完全被盖，实际框选交互仍选中不可见笔迹；本地重开后再写恢复。
- 两种页数的样本新笔迹合并前均有 650 个黑色像素，合并后为 0；重开后新写样本为 650。未更改笔型、颜色或透明度。
- 300 页大坐标探针：1 项通过，内部 18 组；现有 `local_wet_ink_painter_test.dart` 另 3 项通过。
- 新主分支新增的 PDF 依赖最初未进入本地 package_config，曾导致编译失败。随后使用与锁文件一致的 pub.dev 源执行 `dart pub get --enforce-lockfile` 成功，未升级或修改锁文件；上述最终测试在依赖补齐后执行。

## 建议后续修复与验收边界

应同时考虑两层问题：

- 缺失/重复 index 的修复必须复用现有 FractionalIndex 机制并保留正确相对顺序，不能直接生成小于当前底图索引的数字号。检查混合索引、并发新笔、重复索引、完整快照与增量的行为。
- PDF 底图应固定处于笔记内容下方、先于笔迹绘制，避免历史错误索引继续遮挡笔迹。普通插图保持现有前景语义，各层内部保留 fractional index，不改变 Excalidraw 字段和协作协议。不能只修某一处画布而遗漏导出和缩略图消费者。

这轮没有实施修复、运行完整 App 回归或安装真机。修复阶段需把上述诊断改成“新字保持可见”的正式回归，覆盖保存重开/撤销/导出/缩略图/并发排序，执行静态检查与完整 App 测试，再在 MatePad 和一加平板同 PDF 双端持笔验收。应保留“代码确定性复现”与“原现场实机验证”的区别。
