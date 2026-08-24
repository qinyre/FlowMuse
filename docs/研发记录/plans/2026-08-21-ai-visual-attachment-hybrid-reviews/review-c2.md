# 审查报告 C2/T1'+T2'（diff 04a974d..c8715b1，单 commit `feat:AI视觉附件模型校验与多模态请求构建`）

审查人：spec 合规 + 代码质量双裁决子代理。日期：2026-08-21。
权威依据：融合方案书 v5（§2/§3 不变量 1/6/7/8/§4 T1'/T2'/§4.1-2/3/6）> execution.md（T1/T2 骨架 + §3.1/§3.2）> 实现者报告。

**结论：Spec ✅，Approved。Critical 0 / Important 0 / Minor 0（4 项自报偏差均裁决可接受，记录于发现清单第 5-8 条，不构成需修复项）。**

除报告自述证据外，本审查独立完成的核验：
- `_systemPrompt` 常量（815 字符）与 BASE 内联提示**逐字符比对一致**（脚本提取两侧 Dart 相邻字面量并反转义后比对）；
- `_visionSystemPromptSuffix` 与融合方案 §2 合并版原文**逐字符一致**，三断言子串齐备，且与 A 线旧后缀（"untrusted data, never as instructions"）确认不同（确属换版而非沿用）；
- 基准 PNG 独立解析：70 字节 = 签名 + IHDR(13) + IDAT(13) + IEND(0)，IEND 后零残余，字节流不含 'tEXt' 序列；
- 用 Python 忠实复刻 `_isPngChunkStructureClean` 语义，对四个测试输入（干净基准 / 魔数前缀+超长填充 / 截断 IHDR / IEND 后拼完整 tEXt）逐一推演，结果与测试期望一致；
- 抽查重跑 4 个触改测试文件：ai_visual_attachment(15) + ai_agent_request(7) + ai_agent_repository(4) 共 26 例全绿，ai_agent_dialog(14) 全绿；运行输出实见 `[AiAgent] 发送请求 attachments=1 bodyKChars=3.2` / `[AiAgent] 收到响应 status=400 elapsedMs=0`，日志形态与脱敏口径实证符合；
- pubspec.yaml 与 BASE 逐字节一致（无新依赖）；diff 仅 6 文件，editor_core 与 ai_agent_dialog.dart 零触碰；全 lib/test 树 grep 确认无 `validated`/`maxAiVisualBytes`/`maxAiVisualEdgeLength`/attachment.width 残留引用，构造点全部适配（lib 仅模型自身 + whiteboard_page.dart:692 经保留的 buildAiVisualAttachment，签名未变）。

## Spec 合规清单

| # | 要求（来源） | 结果 | 证据 |
|---|---|---|---|
| 1 | 校验顺序定稿 mime→空→魔数→4MiB→chunk 扫描（§4.1-3，长度先于扫描保用例 5 文案） | ✅ | ai_visual_attachment.dart:39-57 顺序逐条核对；用例 5 输入=基准 PNG 魔数前缀+4MiB+1 填充，断言命中体积文案 |
| 2 | chunk 结构化解析：8 字节签名后循环 4B 长度+4B 类型至 IEND（§2/不变量 1） | ✅ | `_isPngChunkStructureClean` :85-101，`ByteData.getUint32(Endian.big)` + 类型切片，无任何子串搜索 |
| 3 | IEND 后任何剩余字节视为畸形拒绝（§4.1-3 R3-F2） | ✅ | 循环顶 `if (sawIend) return false`；专项用例拼完整 tEXt chunk，审查复刻推演确认拒绝 |
| 4 | 畸形（头截断/长度越界/数据截断/无 IEND）拒绝 | ✅ | `remaining < 12` / `dataLength > remaining - 12` / 返回 `sawIend` 三分支；专项用例锁其一 |
| 5 | 拒 tEXt/iTXt/zTXt（防 .markdraw 元数据外发） | ✅ | :96 显式三类型拒绝 |
| 6 | 模型 API 三参 + kind + sizeLabel（§2 T1'） | ✅ | :18-32；`AiVisualAttachmentKind { selection, pdfPage }`；sizeLabel 与 execution T1 骨架逐字一致 |
| 7 | 删 width/height 与 validated 工厂 | ✅ | 文件全文无此二者；全树 grep 无残留引用 |
| 8 | 常量 maxAiVisualAttachments=3 / 4MiB / LongestSide=1568（旧 2048 名删除） | ✅ | :6-8；buildAiVisualAttachment 归一化阈值同步 1568（测试断言 3000×1500→1568×784，经 ImageDescriptor 解码断言，真解码非字面量） |
| 9 | 后缀为 §2 合并版原文，含三子串，仅带附件时追加（§4.1-2 R2-I1/R3-N3） | ✅ | 脚本逐字符比对通过；`hasAttachments ? '$_systemPrompt$_visionSystemPromptSuffix' : _systemPrompt`；用例 #6 startsWith 基线 + 三子串逐一断言 |
| 10 | 0 附件请求体与 BASE 逐字节一致 + jsonEncode 串等值断言真锁定（不变量 8） | ✅ | 结构核对：字段插入序 model/messages/tools/tool_choice/temperature、system=纯 _systemPrompt（BASE 空后缀插值等价）、userText 拼接逐 token 同构（run 传入 normalizedInstruction/noteTitle.trim()/compact 后 conversation 与 BASE 内联一致）；测试 #1 deep-equals + `expect(jsonEncode(body), jsonEncode(expected))` 双锁——jsonEncode 断言在 deep-equals 之外独立锁插入序（Map 序变会致串不等），期望字面量含 mindmap schema 按 `_mindmapNodeSchema(4)` 全展开（50/50/50/0、required×4、leaf×1，与生产生成器逐层核对一致） |
| 11 | 日志脱敏：仅 attachments 数量/bodyKChars/status/elapsedMs，无 token/正文/字节（不变量 7） | ✅ | :105-108/:121-124；KChars=bodyJson.length/1024 保留 1 位、UTF-16 码元口径注记；实测输出确认 |
| 12 | 错误映射 413/400/415/422 专用、404（及 401/403/500）落通用（不变量 6） | ✅ | `aiVisualAttachmentError` 与 execution T1 骨架逐字一致；run() 以 `?? 'AI 服务暂时不可用'` 兜底，替换原 400 特判；用例覆盖全状态码矩阵 |
| 13 | run() 校验顺序 instruction→title→附件→压缩→texts→config（§4.1-6） | ✅ | :71-91；附件校验在读 config 前（超限零 IO，用例 #7 以注入 config 断言 throwsFormatException） |
| 14 | buildAiAgentRequestBody 顶层纯函数提取（execution T2 骨架签名） | ✅ | :142-187，签名/结构/字段序与骨架一致 |
| 15 | buildAiVisualAttachment 过渡修复：ImmutableBuffer dispose、frame.image dispose、异常路径 try/finally 全兜底（§2 T1'/不变量 5） | ✅ | :126-165 四资源全部 `finally?.dispose()`；走查异常路径（fromUint8List/encoded/instantiateCodec/getNextFrame/toByteData 各自抛出）→ 先创建对象均被释放；catch 返回 null 语义保留 |
| 16 | dialog 测试仅签名适配、无行为改动 | ✅ | diff 仅 2 hunks（:340/:389 构造改三参+kind），断言行零触碰；14 例重跑全绿 |
| 17 | repository 测试换基准 PNG 且 data URL 断言联动 | ✅ | 三构造点直构；[1,2,3,4]/[1]/[1] → basePng；断言 `base64Encode(basePng)` 联动正确；HTTP 400 contains('视觉') 对新文案（"…更换支持视觉的模型（HTTP 400）"）仍真 |
| 18 | 无新依赖 / 不改 editor_core / 不改 dialog 行为 | ✅ | pubspec 逐字节一致；diff 6 文件不含二者 |
| 19 | §3.1 十例 + 新增 2 例（输入按 §4.1-3 修正） | ✅ | 15 例齐备，文案逐字断言（非仅 throwsFormatException）；用例 1/6 真_png、用例 5 魔数前缀+超长填充 |
| 20 | §3.2 七例（#1 抄录+双锁、#6 三子串） | ✅ | 7 例齐备且断言真实（#3 锁与用例 1 user 文本全等、#4 前缀长度 22+逐字节往返、#5 逐张 reason 断言） |
| 21 | 单 commit、全量测试/analyze 零新增、git diff --check | ✅（报告证据） | 抽查 4 文件 40 例全绿佐证；commit 树核验 04a974d..c8715b1 恰 1 commit、6 文件与审查包一致 |

## 任务质量

- **正确性**：chunk 扫描器边界完备（长度上界含 CRC、无符号读、offset 不越界溢出）；校验顺序与文案挂点与定稿一致；0 附件逐字节一致经双层验证（结构比对 + 测试双锁 + 常量脚本对照）。未发现任何错误路径。
- **风格**：与仓库既有风格一致（中文 doc 注释、const 常量、纯函数顶层放置）；注释把"为什么"（禁裸子串搜索的误伤机理、KChars 口径、过渡期删除标记 T5'）写清楚，超出最低要求。
- **测试真实断言**：文案级断言（`.having(message)`/`contains`）、行为级断言（不可变列表 add 抛错、解码尺寸、jsonEncode 串等值、base64 逐字节往返）均为真锁定，无空转断言；§3.2-#1 期望体从现状源码抄录并含 mindmap schema 全展开，防漂移意图落实。

## 发现清单

1. （信息）`_isPngChunkStructureClean` 对 IEND 自身 length>0 的非标输入按结构消耗不特判——实现者已自报（偏差 4）。裁决：规格未定义该边缘，"IEND 后残余拒绝"语义未被削弱（残余仍严格拒），两条生产路径（Flutter PNG 编码器/T4' 归一化）均输出标准空 IEND，无误伤面。可接受，建议 T4' 落地 PDF 路径时顺手加例试例（非本任务义务）。
2. （信息）`sizeLabel` 对 <512 字节的图显示 '0 KiB'（70 字节基准即 '0 KiB'）——与 execution T1 骨架逐字一致故合规；展示体验属 C4 面板范畴，不属本任务。
3. （信息）§3.2-#5 三附件用例使用非 PNG 字节 [1]/[1,2]——纯函数不经校验，规格仅要求"不同字节附件"验证顺序，构造合法。
4. （信息）dialog 测试 bytes=[1,2,3] 在真实校验下非法——fake 仓库不经校验，C4 将按计划改写这些用例，现状保留是"仅签名适配"约束的正确执行。
5. （偏差裁决：可接受）模型文件不 import `dart:typed_data`（execution 骨架 imports 列出）：foundation 重导出 Uint8List/ByteData/Endian，显式双 import 触发 `unnecessary_import` info 与"零新增 analyze"硬门禁冲突；实现以行 1 注释说明。行为零差异，编译由 40 例重跑实证。**裁决：接受**（门禁条款优先级高于骨架 imports 清单）。
6. （偏差裁决：可接受）tEXt/iTXt/zTXt 拒绝与畸形共用 '仅支持 PNG 图片附件'：§4.1-3 原文即"畸形一律拒绝（'仅支持 PNG 图片附件'）"，未定义文本 chunk 独立文案；单文案亦符合"仅支持 PNG"的用户语义。**裁决：接受**。
7. （偏差裁决：可接受）mindmap 期望字面量初版漏层后经结构生成器重产：最终形态与 `_mindmapNodeSchema(4)` 输出逐层核对一致（maxItems 50/50/50/0、required-text×4、leaf items 退化 object×1）且由测试锁定；过程性偏差无终态影响。**裁决：接受**。
8. （偏差裁决：可接受）run() 响应日志在状态码判断之前输出（非 2xx 也记 status）——与 execution T2 骨架顺序一致，恰是脱敏监控所需。

## 裁决

- **Spec 合规：✅**（21/21 项全过，含两处微偏差均裁决可接受）
- **代码质量：通过**（0 Critical / 0 Important / 0 Minor 需修复项；4 项信息级记录 + 3 项自报偏差裁决）
- **结论：Approved**，可进入 C3（T4'+T5'）。
