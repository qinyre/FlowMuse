# 范围化复审报告：C1/T3 修复环 1（re-review-c1-fix1）

- 复审日期：2026-08-21
- 复审对象：commit `04a974d` `fix:并发区域预热的解码回调暂停改为计数器防互覆丢失`
- 复审输入：`review-pkg-c1-fix1.diff`、`task-c1-t3-report.md` §五、源码 `image_cache.dart` / `markdraw_controller.dart`（prewarmRegionImages 一带）、测试 `export_region_png_test.dart`
- 复审范围：仅裁决下述开放发现的处置情况 + 检查修复 diff 是否引入新破损，不展开全量重审。

## 一、开放发现裁决

### [Important] 并发 prewarmRegionImages 的回调保存/恢复互相覆盖，可致 onImageDecoded 会话内永久丢失

**裁决：ADDRESSED**

核对明细（对照检查点逐项）：

**1. 计数器语义正确性 — 通过**

- 实现与审查建议方案①一致：`ImageElementCache` 新增 `int _decodedCallbackPaused` 计数器，`pauseDecodedCallback()` 自增（image_cache.dart:127-129）、`resumeDecodedCallback()` 在 `>0` 时自减（:133-137，防护防未配对 resume 下溢）、统一私有 `_notifyDecoded()` 仅在计数为 0 时调用 `onImageDecoded`（:139-143）。
- **嵌套配对**：`prewarmRegionImages` 中 pause 在 try 之前紧邻（markdraw_controller.dart:5744-5745），resume 在 finally（:5752），循环体内 `decodeAndWait` 抛异常时 finally 保证归零；pause 与 try 之间无其他可抛异常语句，无计数泄漏路径。
- **归零后恢复等于原回调（不互覆）**：回调字段从不再被修复代码触碰——全库唯一生产赋值点是构造函数注册（markdraw_controller.dart:104），`_notifyDecoded` 每次读当前字段值。保存/恢复式互覆在结构上被消除。
- **与 `_decode` 完成段的交互**：暂停期间完成（成功/失败两处均经 `_notifyDecoded`）静默丢弃、不补发。与原"置 null 暂停 + 尾部单次 notifyListeners 刷新"语义一致：原实现暂停期间完成同样不触发回调，统一靠 prewarm 尾部单次 `notifyListeners()`（:5757，保留未动）刷新。暂停窗口内经 getImage 启动的非相交 fileId 解码完成也被丢弃，但尾部刷新时已入缓存者直接绘制、未完成者在其自身完成时（计数已归零）正常回调——与原实现行为等价，无语义回退。
- **边缘核验**：`dispose()` 清零计数（image_cache.dart:196）与遗留 prewarm 的 finally resume（`>0` 防护跳过）配合不会下溢；dispose 后 `_decode` 完成段有 `_disposed` 早退（:151-155，位于 `_notifyDecoded` 之前），不会误发回调。安全。

**2. 四点状态机其余语义未被改动 — 通过**

- diff 对 image_cache.dart 的改动仅限：新增字段 + 3 个方法、`_decode` 两处 `onImageDecoded?.call()` → `_notifyDecoded()`（计数为 0 时逐字等价）、dispose 清零。`getImage` 契约、`decodeAndWait` 三分支、`markDecoding` 前置条件、`releaseDecodingPlaceholders`、LRU/peek 均零改动（对照 diff 与当前源码逐一确认）。
- markdraw_controller.dart 仅替换暂停/恢复方式 + 注释更新；markDecoding 占位、串行 decodeAndWait、finally 释放残留占位、尾部单次 notifyListeners、peek 复核失败计数全部原样。
- 交互面检查：`_prewarmImageCache`（loadScene 路径，:2950-2963）**不暂停回调**（靠占位 + 逐张 notifyListeners），grep 确认全库唯一 pause/resume 调用方是 prewarmRegionImages——不存在旧保存/恢复模式与计数器并存互踩的混合状态。

**3. 新增第 12 例测试真实锁定原缺陷 — 通过**

- 测试（export_region_png_test.dart:427-497）构造真实重叠：firstPrewarm 同步段 markDecoding + pause（计数 1）后在 `await decodeAndWait('img-0')` 挂起（此时 `_decoding['img-0'] = future` 已同步建立）；secondPrewarm 同步段 markDecoding（img-0 在途跳过、img-1 占位保留）+ pause（计数 2）后挂起 await 共享 Future。重叠窗口成立。
- **无修复必红**：旧保存/恢复代码下，secondPrewarm 捕获的 `previousCallback` 是 firstPrewarm 暂停后的 `null`；FIFO 微任务序 firstPrewarm 先结束恢复真回调、secondPrewarm 的 finally 再覆盖为 `null` → 计数回调永久丢失。测试随后注入 img-late 经 `resolveImages()`（getImage 路径）触发解码，完成时 `onImageDecoded?.call()` 为 null → `decodedCallbacks` 恒 0 → `expect(decodedCallbacks, greaterThan(0))`（:495）稳定失败。实现者报告 §五的变异验证（回退旧代码实测失败）与本次独立时序推演一致。
- 新实现下计数归零后 `_notifyDecoded` 调用当前字段（countingCallback）→ 断言绿。测试走真实 controller + 真异步管线，无 mock 自证循环。
- 既有测试 9（:340-362）在新实现下：`decodedCallbacks == 0`（暂停期间不被调用）与重绘恰好 +1 断言原样成立；`identical(onImageDecoded, countingCallback)` 断言变为平凡真（字段不再被触碰），实现者已如实披露——区分度转移到第 12 例，非破损。

**4. 修复 diff 内无其他行为变更 — 通过**

- 3 文件改动中：image_cache.dart 与 markdraw_controller.dart 均为上述目标改动；测试文件仅追加第 12 例，其余用例未动。
- stat（+109/-5）与实际内容吻合，无夹带。

## 二、新破损清单

无。未发现修复引入的任何新 Critical/Important（或以下级别）问题。

非破损备注（不计入发现）：
- `resumeDecodedCallback` 的 `>0` 防护意味着若未来出现未配对 resume 的调用方 bug，计数将卡在偏高值导致回调静默更久——当前唯一调用点严格 try/finally 配对，防护本身是防下溢的合理设计，仅作前瞻提示。

## 三、结论

| 发现 | 严重度 | 裁决 |
|---|---|---|
| 并发 prewarmRegionImages 回调保存/恢复互覆致 onImageDecoded 会话内永久丢失 | Important | ADDRESSED |
| 新破损（本次修复引入） | — | 0 Critical / 0 Important |

新 Critical/Important 合计：0。
