# C1/T3 任务审查

- 审查范围：`f1dc359..153ff87`（单 commit `153ff87`，3 文件 +699/-12）
- 审查依据：task-c1-t3-brief.md → hybrid.md（§2 T3 行四点规格、§3 不变量 2/3/5、§4 T3 行、§4.1-8）+ execution.md §2 T3（268-407 行）+ §3.3（794-809 行）
- 审查方式：diff 逐行对照规格；源码上下文核对（image_cache.dart 全文、markdraw_controller.dart 新增段与 loadScene/_prewarmImageCache/editor_canvas/_isDark/static_canvas_painter clipPath、pubspec 字体、barrel 导出）；抽查重跑 `flutter analyze`（37 issues，与报告一致，改动文件仅 1 条 pre-existing info 于 :359 未触碰行）与新测试文件 + 既有 image_cache_prewarm_test（13 例全绿，验证报告证据属实）。

## Spec 合规：✅

### 全局约束

| 条目 | 结论 | 证据 |
|---|---|---|
| editor_core 不 import ai_assistant | ✅ | 两 lib 改动文件 import 列表无 ai_assistant/ai_agent；测试仅 import barrel + flutter |
| 无新依赖 | ✅ | diff 仅 3 文件，pubspec 未动 |
| 无 Platform.is* | ✅ | grep 改动文件零命中 |
| 不改 ai_assistant 任何文件 | ✅ | diff 文件清单 |
| 单 commit 自含可绿 | ✅ | f1dc359..153ff87 恰 1 commit；worktree 与 commit 一致（git status 干净） |
| 中文提交信息 | ✅ | `feat:编辑器内核新增区域截图与图片预热能力` |

### image_cache 在途去重四点状态机（hybrid §2）

| 规格点 | 结论 | 证据（image_cache.dart） |
|---|---|---|
| ① 三态定义；"无"=无表条目且不在 _cache/_failed；markDecoding 沿用前置条件、不覆盖真在途、仅"无"时插占位 | ✅ | :73-79 `if (_cache.containsKey(id) \|\| _failed.contains(id)) continue; if (_decoding[id] != null) continue; _decoding[id] = null;`；`_decoding` 从 Set 改 `Map<String, Future<void>?>`（:21），null=占位/非 null=在途，类文档 :10-14 明示三态 |
| ② decodeAndWait 命中占位→取得所有权启动 _decode 升级在途；在途→await 共享 Future；cache/failed→早退 | ✅ | :55-65，首行早退原样保留；`_decode(...)` 与 `_decoding[fileId] = future` 之间无 await（同步无窗口） |
| ③ getImage 对占位与在途均返 null 且不重复启动 | ✅ | :42-44 `!_decoding.containsKey(fileId)`（containsKey 覆盖 null 与非 null 两态） |
| ④ _decode 失败先记 _failed 再正常 complete（不以异常 complete） | ✅ | :132-138 catch 吞异常、`_failed.add` 后 `onImageDecoded?.call()`，无 rethrow——共享 Future 正常完成，多等待者不收异常 |
| prewarmRegionImages finally 释放异常路径未取得所有权的残留占位 | ✅ | 新增 `releaseDecodingPlaceholders`（:86-92，仅释放 value==null 条目，在途 Future 不动）+ markdraw_controller.dart:5753 finally 调用 |
| _decode 完成段 disposed 早退并 dispose 产物；dispose() 置标志 | ✅ | :122-126 `if (_disposed) { image.dispose(); return; }`；:159 `_disposed = true` |

### 预热三件套（hybrid §3 不变量 2）

| 条目 | 结论 | 证据（markdraw_controller.dart） |
|---|---|---|
| markDecoding(相交子集) 同步占位 | ✅ | :5717-5728 只收集相交未删除 ImageElement；:5736 占位相交子集（注释亦说明为何不全量占位） |
| 暂停 onImageDecoded | ✅ | :5741-5742 保存并置 null |
| finally 恢复 + 尾部单次 notifyListeners | ✅ | :5750 恢复；:5755 `if (!_disposed) notifyListeners()`（对齐 _prewarmImageCache :2962 尾刷） |
| 返回失败计数用 peek 复核（_failed 粘性 + LRU 自逐出如实报数） | ✅ | :5747 |

### exportRegionPng（execution.md §2 T3 骨架）

| 条目 | 结论 | 证据（markdraw_controller.dart:5646-5694） |
|---|---|---|
| 骨架逐行一致（零/负尺寸 null、zoom、viewport、背景先铺、ceilToDouble） | ✅ | 与 execution.md:281-329 逐行同构 |
| resolvedImages 传入（修缺图根因） | ✅ | :5672 `resolvedImages: _peekResolvedImages()` |
| peek-only（禁 resolveImages()） | ✅ | :5699-5708 仅 `_imageCache.peek`，零副作用（不变量 3） |
| skipMathText:true | ✅ | :5678 |
| contentBounds 同源 | ✅ | :5676 `_contentBounds`（与 live canvas editor_canvas.dart:419 同字段） |
| isDarkBackground 同源 | ✅ | :5674-5675 `parseColor(_canvasBackgroundColor).computeLuminance() < 0.5` 与 live `_isDark`（editor_canvas.dart:585-588）同公式同数据源 |
| 分页裁剪（页并集） | ✅ | 传 `layout: _layout`；painter paged 模式 clipPath（static_canvas_painter.dart:119-129）；测试 7 像素级锁定 |
| try/finally 释放 Picture/ui.Image | ✅ | :5683-5693（image?.dispose + picture.dispose，异常路径兜底） |
| 输出最长边 ≤1568 | ✅ | zoom = 1568/max(w,h)，ceil 后恰 1568；测试 1 锁定 |
| 与 exportCoverThumbnail 两处刻意差异不回溯修正 | ✅ | exportCoverThumbnail 未被触碰 |

### pageForVisibleRect 公开

| 条目 | 结论 | 证据 |
|---|---|---|
| 改名公开、实现零改动、唯一调用点 :4440 同步改 | ✅ | diff :4544-4595；grep 全库无 `_pageForVisibleRect` 残留；新增公开文档注释含 nearest 回退警示（为 T4' R3-F3 留提示，报告偏差 #5 如实申报） |

### 测试（execution.md §3.3 + hybrid §4 T3 增补）

| 条目 | 结论 | 证据（export_region_png_test.dart） |
|---|---|---|
| §3.3 全部 9 用例 | ✅ | 用例 1-9 与表格逐条对应（断言口径一致：签名/≤1568/比例 ±0.02/1568×1568/chunk 三禁/bytes 不同+中心红/返回 1/三采样点背景色+页内纸色/零负 null） |
| 构造范式：图片用例 applyResult 注入勿 loadScene | ✅ | #5/#6/#9（及 #10 注入段）均 `applyResult(AddFileResult/AddElementResult)`；AddFileResult 经 editor_state.dart:52-54 入 scene.files，成立 |
| 普通 test() + ensureInitialized | ✅ | 文件头 :398-399 + 注释说明 fake-async 理由 |
| ⑩ 交错不双解（行为断言：length 恰为预期 + peek 同一实例，不触 _lruOrder） | ✅ | 用例 10：prewarm 未 await 即 loadScene 同 fileId → `imageCache.length == 1` + `identical(imageAfterPrewarm, imageAfterSettle)`；微任务序推演成立（prewarm 同步取占位所有权启动解码，loadScene 的 markDecoding 不覆盖在途、decodeAndWait join 共享 Future） |
| ⑪ >maxSize 张触发 LRU 逐出后 getImage 重解码（锁定 R3-F1 前置条件） | ✅ | 用例 11：`ImageElementCache(maxSize: 2)` 注入 3 张（3 > maxSize，满足">maxSize 张"），`markDecoding(['a','b','c'])` 混合已缓存/未缓存 id → a 逐出 → `getImage('a')` 首返 null（异步启动）→ 轮询后 contains+peek 非空；若 markDecoding 对已缓存 id 插占位该用例必失败——非恒真断言 |
| image_cache_prewarm_test.dart 既有契约不破坏 | ✅ | 重跑验证 2 用例绿：loadScene 后 resolveImages 即时返 null（占位仍阻止 getImage 启动解码）+ _failed 粘性均保持 |
| 报告申报的两处测试适配是否削弱检验力 | ✅ 不削弱 | ① Excalifont：pubspec :135-137 确为 bundled asset（assets/fonts/markdraw/Excalifont-Regular.ttf），text_box_sizing_test 等既有离线范式；被测属性（尺寸/签名/chunk/像素色）与字体无关——必要适配非弱化。② G/B 分量：纸色 0xFFFFFCF4 的 R=255 与背景红相同，G/B 是唯一判别维度——断言仍完整区分"页内纸色 vs 页外红"，且采样点选取（左侧/页外元素/页间隙/页内）覆盖规格全部三类位置 |
| editor_core 目录全绿 / 全量 +387 | ⚠️ 抽查核实 | 关键两文件 13 例重跑全绿；全量未重跑（按审查约定采信实现者报告证据） |
| flutter analyze 零新增 | ✅ | 重跑 37 issues 与报告一致；改动文件内仅 markdraw_controller.dart:359 一条 info，位于 diff 未触碰的存量行（BASE 已有） |

## 任务质量：Approved

代码与 execution.md 骨架逐行同构、并发状态机无 torn window（单线程事件循环内 check-then-set 均在同步块）、资源释放完备、测试为真实行为断言（含像素级与实例同一性判别）、注释质量高于仓库平均（每处防御均有"为什么"）。1 项 Important 为规格骨架自带的并发隐患（非实现偏差、C1 时点无调用方），已给出触发条件与修复建议，不阻断本任务验收。

## 发现清单

1. **[Important] 并发 prewarmRegionImages 的回调保存/恢复会互相覆盖，可致 onImageDecoded 会话内永久丢失**
   - 证据：markdraw_controller.dart:5741-5742 + :5750（`final previousCallback = _imageCache.onImageDecoded; _imageCache.onImageDecoded = null; ... finally { _imageCache.onImageDecoded = previousCallback; }`）。
   - 问题：两次 prewarmRegionImages 执行窗口重叠时，后启动者捕获的 `previousCallback` 是前者暂停后的 null；若先启动者先结束（同区域时因 FIFO 微任务序这是**常见**次序——两者 join 同一解码 Future，先注册的 continuation 先恢复），后启动者的 finally 把回调恢复为 null，controller 构造函数注册的"解码完成→重绘"闭包（:104-108）会话内丢失：后续解码完成的图片不再自动上屏，需等下一次交互重绘。无崩溃/泄漏/导出错误像素，属静默体验降级。
   - 缓解现状：C1 时点该方法零调用方（API 供 T4' 消费）；hybrid §1.2.5 的 `_pendingCapture` await 设计若面板侧对所有捕获串行则不触发；且该模式为 execution.md 骨架原文（379-389 行）逐字继承，非实现者引入。
   - 建议（二选一，均为小改）：① 本文件内守卫——finally 改为仅当回调仍处于自己设置的暂停态才恢复（如以哨兵 token 判 identical，或把暂停/恢复下沉为 ImageElementCache 的暂停计数器 `pauseDecodedCallback()/resumeDecodedCallback()`）；② 至迟在 T4'/T6' 接线时保证捕获路径串行（面板侧单一在途捕获，新捕获 await 旧捕获）。推荐 ①，2-4 行即可闭合，且不依赖未来消费方纪律。

2. **[Minor] `_decode` 失败路径缺 disposed 守卫，与成功路径不对称**
   - 证据：image_cache.dart:122-126（成功段有 `_disposed` 早退并 dispose 产物）vs :132-138（catch 段无守卫，dispose 后迟到的失败解码仍 `_failed.add(fileId)` 回填已清空集合并调用回调）。
   - 影响：无功能后果——controller 注册的回调闭包自带 `if (!_disposed)` 守卫（markdraw_controller.dart:104-108），cache 已弃用无人再读 `_failed`；纯对称性洁癖。
   - 建议：catch 段开头补 `if (_disposed) return;`（finally 仍会执行清理），或维持现状并在注释声明该不对称是有意的。

3. **[Minor] 测试 10 identical 断言存在完成序漏检窗口（实现者已如实申报）**
   - 证据：export_region_png_test.dart 用例 10；实现者报告 §四残留风险段。
   - 问题：若实现回退为双解且第二次解码在首次 peek 前完成，两次 peek 可读到同一（第二次）实例而漏检。
   - 建议：无需行动——此为 hybrid §4 T3 行 R2-N3/R3-N4 裁决定下的行为断言口径，属已接受边界；如欲收紧可在 loadScene 交错前先抓一次 peek 快照比较，收益有限。

4. **[Minor] `_decode` 未 dispose codec（存量，非本 diff 引入）**
   - 证据：image_cache.dart:118-119（`instantiateImageCodec` 后仅取 frame，codec 未释放）；同文件测试 helper `_decodePng`（export_region_png_test.dart:855-860）反而正确 `codec.dispose()`。
   - 影响：每次解码泄漏一个 Codec 句柄直至 GC；为 BASE 已有行为，本任务资源纪律条目（Picture/ui.Image try/finally）已满足。
   - 建议：可顺手在 `_decode` 成功/失败路径补 `codec.dispose()`（frame 取得后即可释放），非本任务验收项。

### 结论

- Spec 合规：✅（四点状态机、预热三件套、peek-only、资源纪律、1568、9+2 用例、既有契约、依赖方向全部落实；唯全量测试采信报告证据为 ⚠️ 抽查项）
- 任务质量：Approved（Critical 0 / Important 1 / Minor 3；Important 项为规格骨架继承的并发隐患，C1 无调用方不阻断，建议按发现 1 的方案 ① 小改闭合或在 T4'/T6' 接线时强制串行）
