# 复审 C3/T4'+T5' 修复环 1：PDF 路径 oversize 专用文案

- 复审范围：仅裁决开放发现 [Important]「PDF 路径透传 '图片过大，请缩小选区后重试'」，检查修复 commit `a10425b` 是否落实要求且无新增破损。不展开全量重审。
- 裁决：**ADDRESSED**
- 新增 Critical / Important：**0 / 0**

## 一、修复要求逐项核验

### 1. 仅映射该 oversize 文案，其余错误原样透传 —— 通过

`visual_attachment_capture.dart:176-184`：try 块**只包裹** `normalizeAttachmentPng(file.bytes)` 一处调用；`on StateError` 内对消息做全等匹配，等于 `'图片过大，请缩小选区后重试'` 才改抛 `'该 PDF 页面图片过大，无法作为附件发送'`，其余一律 `rethrow`。

- `'图片处理失败，请重试'`（`_pngDimensions` 解析失败兜底，源码 :59）走 `rethrow` 原样透传 ✓
- mime 把关的 `'当前页面不是 PDF 页'`（:174）在 try 块之外，不可能被误捕 ✓
- 全库 grep 确认：PDF 专用文案在 lib 仅此一处（:183）、测试断言一处；原文案仅在 `normalizeAttachmentPng` 的两个 throw 点（:22 维度护栏、:46 字节档位穷尽）✓

### 2. 选区路径不变 —— 通过

`captureSelectionAttachment` :124 对 `normalizeAttachmentPng(png)` 的调用保持裸调用、无 try/catch，oversize 文案照旧透传。全库确认 `normalizeAttachmentPng` 仅这两个捕获函数调用（模型层旧 `buildAiVisualAttachment` 已删，余注释指向），映射单点成立，选区路径零波及。

### 3. 映射实现方式（消息字符串匹配）—— 可接受，误伤面已排除

try 块内唯一被调方是 `normalizeAttachmentPng`，其 StateError 出口全集为：

| 抛出点 | 消息 | 处置 | 评估 |
|---|---|---|---|
| :21 维度护栏 | 图片过大，请缩小选区后重试 | 映射 | 正确 |
| :46 档位穷尽 | 图片过大，请缩小选区后重试 | 映射 | 正确（同为"过大不可发"，PDF 场景下"缩小选区"同样不可执行，映射语义恰当） |
| :59 解析失败兜底 | 图片处理失败，请重试 | rethrow | 正确 |

两条 oversize 共用同一消息串且语义同族，按串匹配恰好覆盖两者，无误伤面。附注（非缺陷、不阻塞）：若未来有人改动 `normalizeAttachmentPng` 的该消息文本而未同步此处，映射会静默退化为透传——哨兵类型/子类更稳，但当前两处文案同源同文件、漂移风险低，按本次修复标准可接受。

### 4. 补锁定用例真实走到 maxPixelCount/oversize 分支 —— 通过（实测 + 推演）

新增用例第 15 例「PDF 页图片过大映射为 PDF 专用文案」+ `_patchPngDimensions`/`_crc32` 两个测试助手：

- **IHDR 篡改布局正确**：W@偏移16、H@20、CRC@29，CRC 覆盖 type+data 共 17 字节（偏移 12 起）——与 PNG 结构一致。
- **CRC 实现正确**：`_crc32` 为规范 IEEE CRC-32（反射多项式 0xEDB88320、初值/终值 0xFFFFFFFF）。本次复审用 Dart 实跑该实现对规范校验串 `"123456789"` 得 `0xCBF43926`，与规范值一致。CRC 有效保证 `ImageDescriptor.encoded` 头部解析成功（libpng 校验 IHDR CRC）；若 CRC 错，会落入 `'图片处理失败，请重试'` → rethrow → 用例失败。
- **数值与阈值关系**：默认护栏 `maxPixelCount = 4096×4096 = 16,777,216`；篡改声明维度 5000×4000 = **20,000,000 > 16,777,216** ⇒ 源码 :21 守卫在任何解码/缩放之前触发。
- **过路分支唯一性推演**：`_pngDimensions` 经 `ImageDescriptor.encoded` 只读头部不解码像素（无需真造大图）；若维度被误读为小图，则 1×1 PNG 本身合规、正常返回不抛错，`throwsA` 必失败。故用例通过 ⇔ 头部解析成功 ∧ 读得 5000×4000 ∧ :21 护栏分支触发 ∧ 映射生效——锁定路径唯一，不存在经 ：46 或其他拒绝分支侥幸通过的可能。
- **实跑证据**：本次复审独立执行 `flutter test test/features/whiteboard/ai_assistant/visual_attachment_capture_test.dart`，**15/15 全绿**（含新用例），工作树与 `a10425b` 完全一致（`git status` 干净、`git diff a10425b` 为空）。
- 场景构造细节合理：经 `applyResult(AddFileResult/AddElementResult)` 注入而非 `loadScene`，规避 loadScene 自动全量预热对该伪大图的无效解码；单页 paged 布局使视口判定正常落页，确保异常确实来自归一化环节。

### 5. 无夹带行为变更 —— 通过

commit `a10425b` 仅 2 files、+85/−1：lib 改动 = `final Uint8List normalized;` 声明前移 + try/catch 包裹（diff 上下文显示周边代码原样未动）；test 改动 = 1 个新用例 + 2 个测试助手。stat 与 diff 内容吻合，无其他文件、无顺手改动。

## 二、新破损清单

无。（上述"消息匹配漂移风险"为维护性附注，非本次修复引入的行为破损，不计入发现。）

## 三、结论

开放发现 [Important] 已按要求精准修复：映射单点、透传保序、选区路径不动、锁定用例以可推演的唯一分支路径 + 规范 CRC 实证真实覆盖 oversize 护栏，实测全绿，无夹带变更。

**裁决：ADDRESSED｜新 Critical/Important：0/0**
