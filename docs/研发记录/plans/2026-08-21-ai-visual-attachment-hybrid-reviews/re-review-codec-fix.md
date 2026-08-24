# 范围化复审：image_cache codec 泄漏修复（34613e8）

- 复审对象：HEAD~1..HEAD（34613e8，单文件 FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/image_cache.dart，+12/-1）
- 处方来源：review-final.md 遗留 Minor triage #3（"frame 取得后 `codec.dispose()` 一行低风险修复"）+ 顺带闭合 triage #1（catch 段缺 disposed 守卫的对称性）
- 一致性核验：review-pkg-codec-fix.diff 与实际提交逐行一致（同 blob 对 c5964ca..0353576）；工作树 clean；被读源码经 `git hash-object` 实证即提交后 blob 03535760。

## 结论

**通过｜Critical 0 / Important 0 / Minor 0（新增）**。处方完整落实，两条遗留项（triage #3、#1）闭合，无新破损。

## 逐检查点裁决

### CP1 codec 生命周期 — ADDRESSED

终态源码 image_cache.dart:145-181：

- **正常路径**：`getNextFrame()` 返回后立即 `codec.dispose(); codec = null;`（:152-153）。置空使 finally 的 `codec?.dispose()`（:179）成为 no-op——置空惯用法保证全程恰好一次 dispose，无双释放。
- **getNextFrame 抛错路径**：此时 codec 非 null 且未释放，catch 不重抛，进入 finally 后 `codec?.dispose()` 补释放。triage #3 指认的泄漏路径已闭合。
- **instantiateImageCodec 本身抛错**：赋值未发生，`codec` 保持 null，`?.` 空安全跳过，无 NPE、无多余动作。
- **disposed 早退分支次序**：codec 释放在 `_disposed` 检查之前（:152 vs :156），故该分支只需 `image.dispose()`，无需再管 codec——次序正确。
- **frame.image 存活性与先例一致性**：`FrameInfo.image` 独立持有解码产物，释放 codec 不使其失效；与本仓库既有模式吻合（visual_attachment_capture.dart `_rescalePng` 的 finally frame+codec 双 dispose，见 review-final 不变量 #5 证据），非新引入的假设。

### CP2 catch 段新增 `if (_disposed) return;` — ADDRESSED

- **对称性**：成功路径 disposed 早退跳过"入缓存 + 通知"（:156-160）；catch 路径 disposed 早退跳过"`_failed` 回填 + 通知"（:167-170）。两分支形状对称。
- **失败粘性契约**：非 disposed 的失败路径原样保留 `_failed.add(fileId)` + `_notifyDecoded()`（:175-176），粘性语义不变；disposed 场景跳过回填与 `dispose()` 清空语义一致——dispose 已 `_failed.clear()` 且置永久粘性 `_disposed=true`，此后无人读取该表（controller 侧闭包自带 `!_disposed` 守卫，markdraw_controller.dart:104-108，即 triage #1 原判据），回填只是写后即弃的死状态。跳过正确而非破坏。
- **多等待者共享 Future 正常 complete**：早退发生在 catch 内部且不重抛，async 函数继续走 finally 后正常完成——`decodeAndWait` 及所有共享等待者仍拿到无异常完成，契约保持。
- **`_notifyDecoded` 跳过**：与成功路径对称；且因 `dispose()` 将 `_decodedCallbackPaused` 归零，若不跳过此处通知反而会真实触发回调——跳过避免了弃用缓存上的无效 repaint 调度，叠加 controller 层守卫构成双保险。

### CP3 finally 中 `_decoding.remove(fileId)` 时序 — ADDRESSED（不变）

- 该语句仍是 finally 最后一条，覆盖全部三条退出路径（正常 / catch-disposed / catch-常规失败）；唯一插入物 `codec?.dispose()` 位于其前，且 dispose 不触碰 `_decoding` 表，先后次序无影响。
- Future 完成相对时序不变：finally 执行完毕后 Future 才 resolve，等待者恢复时条目必已移除——与修复前完全一致。
- disposed 场景下 `dispose()` 已清空 `_decoding`，finally 的 remove 为 no-op，与修复前行为相同。

### CP4 diff 无夹带 — ADDRESSED

- 单 commit（34613e8）、单文件、+12/-1，改动全部落在 `_decode` 方法内：声明提升、dispose+置空、catch 守卫、finally 补释放四件事，均为处方范围。
- 注释风格与文件既有中文注释一致并注明出处（最终审查跟进项）；commit message 与内容相符；无格式化噪声、无无关重排。

### CP5 测试证据 — ADDRESSED

控制器声明（全量 flutter test 429 全绿、analyze 37 与基线持平）按复审口径采信；另做独立定向复核：

- `test/features/whiteboard/editor_core/image_cache_prewarm_test.dart`：**14 例全绿**（本机实跑，含"解码失败标记 failed 不无限重试"、串行预热去重、回调暂停计数器等本路径用例）。
- `test/features/whiteboard/editor_core/export_region_png_test.dart`：**12 例全绿**（本机实跑，含预热后真实渲染、损坏 bytes 失败计数=1、并发预热重叠不双解等解码/失败/并发用例）。

## 新发现

无 Critical / Important。两条信息级观察均为存量行为、非本 diff 引入，仅留档：

1. 若 `onImageDecoded` 回调同步抛错且发生在图片已入缓存之后，catch 会给已缓存的 fileId 回填 `_failed`——修复前即如此，本次未触碰该象限，不构成回归。
2. `getImage` 无 `_disposed` 前置守卫，理论上可在弃用缓存上启动解码；但成功/失败两路径现均能安全收尾（image.dispose / 早退），且 codec 释放使该理论路径也不泄漏——修复后鲁棒性略优于修复前。

## 总裁决

**通过**。triage #3（codec 泄漏，建议尽快跟进项）与 triage #1（catch 段 disposed 守卫对称性）双双闭合，实现与处方逐点吻合，契约面（失败粘性、共享 Future 正常完成、通知语义、`_decoding` 时序）零扰动，定向测试独立复跑全绿。

Critical 0 / Important 0 / Minor 0（新增）
