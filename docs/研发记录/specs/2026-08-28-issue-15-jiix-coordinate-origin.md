# Issue #15：服务端 JIIX 识别结果坐标修复（设计稿 v3）

- 日期：2026-08-28（v2 吸收一轮三路审查；v3 吸收二轮三路审查，官方样本核实后改用"纯缩放+原点"变换）
- 关联：[Issue #15 服务端 JIIX 多元素识别结果坐标为相对系，未加回笔迹原点导致元素堆到画布 (0,0)](https://github.com/qinyre/FlowMuse/issues/15)
- 状态：实施完成（设计经三轮审查冻结；代码经两路对抗审查 + 变异测试迭代修复，`go test ./... && go vet ./...` 全绿）

## 1. 问题（经两轮审查与官方样本核实的事实基础）

**Issue 字面问题**：MyScript 走 JIIX 多元素路径（`exports` 里 `text/plain` 缺失、响应含 `elements` 数组）时，识别元素堆到画布 (0,0)，而非书写位置。

**核实后的修正事实**（证据见 §2、§8）：

1. 服务端 endpoint 是官方 iink Batch API（`cloud.myscript.com/api/v4.0/iink/batch`）。
2. 官方 API 的 JIIX 以 **`exports["application/vnd.myscript.jiix"]` 的 JSON 字符串**交付（官方 iinkJS 示例：`JSON.parse(exports['application/vnd.myscript.jiix'])`）；响应顶层**不存在** `elements`/`result.elements` 数组 → 代码中 `raw["elements"]`（:174）与 `raw["result"]["elements"]`（:178）对官方 API 不可达（早期按假想响应形状编写）。
3. JIIX 坐标与 bounding-box 单位是**毫米**：官方示例自带 `mmToPixel(mm) = 96×mm/25.4` 工具函数并直接把 jiix bbox 叠加到与输入同帧的画布，**不做原点扣除、不做 Y 翻转**。
4. JIIX Text 文档：根节点 `type:"Text"`、有 `label` 与 `bounding-box`，`words` 数组**在根上**（无需递归）；**word 节点没有 `type` 字段**（只有 label/candidates/bounding-box/items），空白词仅为 `{"label":" "}`。JIIX Math：子数组键名 `expressions`，但表达式节点 type 是 `"number"/"symbol"/"="` 等 23 种细类（**不存在 "Expression" 类型**），逐节点平铺不适合 Math。
5. 真实 JIIX 行盒含 ascender/行高 padding（官方论坛样本：word 盒 y 高于笔迹最高点约 9.25mm）→ 识别内容 bbox **系统性大于**笔迹 bbox，"以根 bbox 为参考系的自校准"会引入整体平移误差（v2 方案因此废弃，见 §3）。
6. 真实链路现状缺陷：`text/plain` 缺失但 exports 含 jiix 字符串时，代码不解析 jiix，一路 fallthrough 报 `"MyScript returned no recognized elements"`。修复 b 属**罕见兜底路径的加固**（官方响应正常双键并存、text/plain 优先），不是主路径改造。

**结论**：修复 = (a) issue 字面的原点修复（防御假想路径，验收标准 1 的 canned 形状即此）+ (b) 接线真实 JIIX 字符串入口并做毫米→像素换算。

## 2. 根因与证据

全部位于 `FlowMuse-Server/internal/recognition/myscript.go`，无跨包影响（`parseRawElements`/`boundsFromRaw`/`pointsFromRaw` 仅本文件使用，两轮审查 grep 复核一致）：

| # | 事实 | 位置/来源 |
|---|------|-----------|
| 1 | 发送笔画前减去笔迹包围盒原点（`point.X - request.Bounds.X`），MyScript 收到原点 (0,0) 的 px 坐标，width/height=笔迹尺寸 | `toMyScriptRequest` :111-112、:149-150 |
| 2 | JIIX 坐标为毫米、与输入同帧（不做原点扣除） | [官方 iinkJS 示例 mmToPixel](https://github.com/MyScript/iinkJS/blob/master/examples/v4/websocket_text_iink_search.html) |
| 3 | 真实 JIIX 经 exports jiix 字符串交付；代码只读 `text/plain`/latex | [REST 架构文档](https://developer.myscript.com/docs/interactive-ink/4.2/web/rest/architecture/)；myscript.go :163-173 |
| 4 | JIIX 结构（根 Text/Math、根级 words、word 无 type、行盒 padding） | [iinkTS 类型定义](https://github.com/MyScript/iinkTS/blob/master/src/model/Export.ts)、[官方论坛真实样本](https://developer-support.myscript.com/support/discussions/topics/16000032011/page/last) |
| 5 | 假想 elements 路径直接透传相对坐标，未加原点 | :213-245、:291-325 |
| 6 | 客户端把 `x/y`/`points` 当画布绝对坐标（`point.x - x` 转局部系） | markdraw_controller.dart:1415-1500、:1646-1662 |
| 7 | exports 主路径（textElement/mathTextElement 用 `request.Bounds` 整体盒）不受影响 | :165-192 |

**fallback 双重偏移陷阱**：`boundsFromRaw` 逐字段兜底；若先取绝对 fallback 再无条件加原点，缺 bounds 元素被双重偏移。elements 路径的 fallback 必须以相对系表达。

## 3. 备选方案与弃选理由

- **发绝对坐标、解析端零改动**：弃。违反书写区语义（笔画越界行为未定义）；扩书写区改变 Text 分行行为回归主路径；JIIX 以 mm 返回，"零改动"不成立。
- **客户端加回原点**：弃。响应将同时存在两种坐标约定且无字段可区分，多消费方（手写识别/smart-layout）各自补偿，契约劣化。
- **margin 置 0 + 绝对原点换算**：弃。需改 Text 工作路径请求体；且依赖"margin 平移输出坐标系"这一未证实前提，若 margin 默认非零（v3.0 文档 text margin 默认 bottom=10/其余 15）反而引入 ≈57px 静默偏移。
- **自校准（v2：减根节点 bbox）**：弃。二轮审查以官方真实样本证伪前提——行盒含 ascender padding（样本量级 9.25mm≈35px），根 bbox（行盒并集）系统性大于笔迹 bbox，自校准必引入整体下移；且根 bb 缺失时兜 0 会静默退化。
- **纯缩放+原点（v3 采用）**：`px = mm × 96/25.4 + ink原点`。与官方示例行为逐字一致（mmToPixel 直接叠加、无原点扣除）；无根 bbox 依赖（少一个失效模式）；提交系本就是 ink 相对系（:111-112），scale+origin 即还原绝对坐标。残余假设（输出帧==输入帧、margin 不平移输出坐标）列入 §6。
- **relativeFallback + 集中换算**（一轮 B#6 认可）：保留于修复 a。

## 4. 方案（v3）

原则：**工作路径（text/plain/latex exports 优先级与行为）零改动；两处修复相互独立、全部可本地单测；无凭据假设集中 §6 并单点可改。**

### 4.1 修复 a：既有 elements 路径加回原点（issue 字面）

```go
func parseRawElements(rawElements []any, inkBounds InkBounds) []RecognizedElement {
	// 该响应形状来自 issue #15 验收夹具（官方 API 未见顶层 elements 数组，
	// 真实 JIIX 走 exports jiix 字符串，见 parseJiixExport）。
	// toMyScriptRequest 提交笔画前已减去 inkBounds.X/Y，此路径的坐标因此以
	// ink 左上角为原点（px 相对系）；解析后统一加回原点得画布绝对坐标。
	// fallback 须用相对系（x/y 兜底 0），避免缺省元素被双重偏移。
	relativeFallback := InkBounds{X: 0, Y: 0, Width: inkBounds.Width, Height: inkBounds.Height}
	// …循环内（switch 之前，全类型一致）：
	box := boundsFromRaw(raw, relativeFallback)
	box.X += inkBounds.X
	box.Y += inkBounds.Y
	// shape 分支（rectangle/ellipse/diamond/line/arrow 共用一个 case、一处 Points 赋值）：
	Points: shiftedPoints(pointsFromRaw(raw), inkBounds.X, inkBounds.Y)
```

- `shiftedPoints` nil 进 nil 出（保 omitempty）；rectangle/ellipse/diamond 的 points 客户端暂不消费，一并偏移无害且为 ADR-019 留契约。
- `boundsFromRaw`/`pointsFromRaw` 保持纯相对解析器，不改签名；fallback 语义由调用方注入（elements 路径=px 相对系）。
- `parseMyScriptResponse` 的 `bounds` 参数双语义（exports 路径=绝对整体盒；elements 路径=X/Y 原点+W/H 尺寸兜底）写进两函数注释。

### 4.2 修复 b：接线真实 JIIX 字符串入口（纯缩放+原点）

`parseMyScriptResponse` 的 exports 分支，在 `text/plain`/latex 之后、既有 `raw["elements"]` 之前插入（**罕见兜底：仅 text/plain 与 latex 均缺失时触发**）：

```go
if jiix := firstString(exports, "application/vnd.myscript.jiix"); jiix != "" {
	if elements := parseJiixExport(jiix, bounds); len(elements) > 0 {
		return RecognizeResponse{Elements: elements}
	}
}
```

新增 `parseJiixExport(jiix string, inkBounds InkBounds) []RecognizedElement`（**自带循环，不复用 parseRawElements**——后者经 §4.1 会再加一次原点；仅复用 normalizeType/firstString/stringValue 等叶子 helper）：

```go
// jiixMmToPx 把 JIIX 毫米坐标换算为像素（xDPI=96），与官方 iinkJS 示例
// 的 mmToPixel(mm)=96*mm/25.4 一致；换算后叠加 inkBounds 原点还原画布绝对坐标。
const jiixMmToPx = 96.0 / 25.4
```

1. `json.Unmarshal` 字符串为 `map[string]any`；失败返回 nil（fallthrough，行为同现状）。
2. **选节点集**：根对象的子数组按 `words` → `expressions` → `elements` 顺序取**第一个非空**的节点对象数组；
   - `words`：节点**无 type 字段**（官方形状），一律按 text 处理；
   - `expressions`/`elements`：Math 的 expressions 是 `operands` 递归细类树（"number"/"symbol" 等 23 种 type），逐节点平铺不适合——**不走子数组，改用根节点自身**做单 math 元素（见下条）。即：命中 `expressions` 时忽略其内容，回落到根节点分支；
   - 都没有 → 根节点自身。
3. **根节点自身单元素**：仅当 `normalizeType(root.type)` 命中 `text`/`math`（官方根为 `Text`/`Math`，均可命中，无需改 normalizeType）且 `firstString(root, "latex","label","text")` 非空且根有 bounding-box 时，产出单元素（math→`mathTextElement`、text→`textElement`，**同样套用步骤 5 变换**）；否则返回 nil（`type:"Document"` 之类未知根 → nil fallthrough，与现状一致）。
4. **逐节点解析（words）**：跳过 label trim 后为空的节点（官方空白词 `{"label":" "}`）；bounds 用**严格读取** `jiixBounds(node map[string]any) (InkBounds, bool)`——仅认 `bounding-box` 键（官方唯一键名），返回**原始 mm 值**，缺键或 x/y/width/height 任一非 float64 → ok=false → 跳过该节点（不兜 0：mm 系下兜 0 会把元素拉到 ink 原点左侧形成负偏移）；text 取 `label`。注意不对称：`words:[]`（空数组）走根分支，而 `words:[全非法节点]`（全被跳过）返回 nil 不回落根。
5. **坐标变换（纯缩放+原点）**：
   ```
   X = bounding-box.x × jiixMmToPx + inkBounds.X
   Y = bounding-box.y × jiixMmToPx + inkBounds.Y
   W = bounding-box.width  × jiixMmToPx
   H = bounding-box.height × jiixMmToPx
   ```
   行盒 ascender padding 保留在元素盒内（盒略大于笔迹，客户端紧包裹在盒内排版，可接受）。**不处理 points**（官方 Text/Math 的 word/expression 节点无 points 键，shape 类型不在官方 jiix 中；防御性支持零收益，§7 已排除 strokes）。
6. 解析结果为空返回 nil（fallthrough 到既有入口与最终报错，行为同现状）。

### 4.3 请求配置：jiix 导出钉死 + Accept 对齐

Text configuration 增加（Math 分支在既有 `export.jiix.strokes` 旁补 `bounding-box`）：

```go
// Text
configuration["export"] = map[string]any{
	"jiix": map[string]any{
		"bounding-box": true,                        // v3.0 默认 false、4.4 默认 true，显式钉死跨版本行为
		"text":         map[string]any{"words": true}, // 4.4 默认 true，同样显式钉死
	},
}
// Math：export.jiix 增加 "bounding-box": true（与既有 strokes:true 并列）
```

均为**导出增强**选项，不改变识别行为与 text/plain/latex 导出（官方配置参考：`export.jiix.text.words | boolean | true | If true, JIIX export will include the detailed words information`）。

Accept 头 Text 分支补 jiix MIME（与 Math 对齐，零风险防御）：

```go
httpRequest.Header.Set("Accept", "application/json,text/plain,application/vnd.myscript.jiix")
```

### 4.4 明确不改

- exports 主路径（text/plain/latex → 整体包围盒单元素）优先级与行为不变——§4.3 生效后真实响应双键并存常态下仍走主路径（测试 3c 钉死）。
- `toMyScriptRequest` 减原点、width/height、xDPI/yDPI、margin 不变。
- normalizeType 不改（`Text`/`Math`/`Word`/`word` 等既有映射已覆盖所需；不新增 `expression`/`document` 死映射）。
- 客户端零改动。

## 5. 测试计划（myscript_test.go 新增；表驱动 + 中文注释，jsonString helper 复用 smart_layout_test.go:25-31 先例）

测试夹具取值：测试 1/2（legacy px 路径）取 `inkBounds={X:120,Y:80,W:200,H:100}`；测试 3-6 取 `{X:100,Y:200,W:300,H:150}`，`s=jiixMmToPx`；mm 涉及小数乘法的断言用容差 helper（误差 <1e-6）并以字面量锚定 96/25.4 官方换算值（175.5905511811 等），px 整数路径用精确相等。

1. `TestParseRawElementsShiftsJiixCoordinatesToAbsolute`（修复 a，canned 用 `bounds` 键回归既有键名）：表驱动 text/word 别名、math、line（**同时断言 box X/Y/W/H 与 points 绝对值**）、rectangle、无 points 的 line 断言 `Points == nil`。
2. `TestParseRawElementsFallbackUsesInkOrigin`（修复 a 陷阱）：整块缺 bounds、bounds 缺 x/y、bounds 只有 width；断言无双重偏移。
3. `TestParseMyScriptResponseExportsPathUnchanged`（主路径回归）：a) text/plain 单键 → 整盒单元素；b) x-latex 单键 → math 整盒；**c) text/plain 与 jiix 字符串双键并存（含多词）→ 必须仍返回单 text 元素**（§4.3 生效后的真实常态，防优先级翻转的最大隐性回归面）。
4. `TestParseJiixExportConvertsMillimetresToAbsolutePixels`（修复 b，canned 复刻官方形状：**word 无 type 字段**、键名 `bounding-box`、数值为任意合成 mm 量级）：
   | # | 输入 | 期望 |
   |---|------|------|
   | 1 | 根 `{type:"Text",bounding-box,words:[{label:"hello",bb:{20,10,20,8}},{label:"world",bb:{40,10,20,8}}]}`（word 无 type） | 2 个 text：X=100+20s/100+40s，Y=200+10s，W=20s |
   | 2 | 根 `{type:"Math",label:"a+b",bounding-box:{87.9,55.09,10.2,7.3}}` 无子数组 | 1 个 math：X=100+87.9s，W=10.2s |
   | 3 | 根 `{type:"Text",label:"你好",bounding-box:{0,0,60,20}}` + `words:[]` 空数组 + 无其他子数组 → 根自身分支 | 1 个 text："你好"，X=100，Y=200，W=60s，H=20s |
   | 4 | 根 `{type:"Text",label:"你好",bounding-box:{0,0,60,20}}` + `expressions` 非空（Math 形状混入 Text 根） | expressions 被忽略 → 根自身单 text（同 #3） |
   | 5 | word 缺 bounding-box / label 空白词 | 该节点跳过，其余正常 |
   | 6 | 非法 JSON | nil |
   | 7 | `{type:"Document",…}` 无子数组 | nil（未知根 fallthrough） |
   | 8 | words 与 expressions 双非空 | words 胜出（取第一个非空的顺序语义） |
5. `TestParseMyScriptResponseJiixStringFallback`：exports 含 jiix 字符串且缺 text/plain → 修复 b 生效；另测 `result.elements` 嵌套路径偏移正确（修复 a 覆盖）。
6. `TestRecognizeEndToEndWithStubMyScript`：httptest 伪 MyScript 返回官方形状（exports 含 jiix 字符串、无 text/plain）；**handler 只捕获 body（经 channel 回传），断言全部在测试主体**（不复制 smart_layout_test.go:16 在 handler 内 t.Fatalf 的坏先例）；走公开 `Recognize`（假 AppKey/HMACKey + stub Endpoint，覆盖 hint 分派）；断言：发出的 strokeGroups 坐标已减原点、顶层 width/height=inkBounds.W/H、Text 配置含 `export.jiix.text.words=true` 与 `bounding-box=true`、Accept 含 jiix MIME、响应元素为绝对坐标（期望值同测试 4 闭式推导）。stub 不校验 HMAC/Accept（hmacSignature 已有专测）。
7. `TestToMyScriptRequestExportConfig`：直接断言 Text/Math 两分支的 `configuration.export.jiix`（Text：`bounding-box:true`+`text.words:true`；Math：`bounding-box:true`+`strokes:true`），补齐 §4.3 Math 配置的覆盖。

实现级钉死（三轮收敛审查）：容差 helper `almostEqual(a, b float64) bool`（|a−b|<1e-6）放 myscript_test.go；`shiftedPoints(points []InkPoint, dx, dy float64) []InkPoint`；mm 换算集中在单函数（Y 假设证伪时单点改）。

全量验证：`cd FlowMuse-Server && go test ./... && go vet ./...`（AGENTS.md 验证清单要求）。

## 6. 无法本地验证的假设与验收对照

| 假设 | 依据 | 若证伪的修正点 |
|------|------|----------------|
| JIIX 坐标单位 mm，`px = mm × 96/25.4` | 官方 iinkJS 示例 mmToPixel 工具函数 | 常量 `jiixMmToPx` 单点改 1.0 |
| 输出帧==输入帧：jiix 坐标相对书写区原点，margin 配置**不**平移输出坐标 | 官方示例对 jiix bbox 直接 mmToPixel 叠加到与输入同帧画布、无原点扣除 | 加常量 margin 补偿项（单点） |
| JIIX Y 轴与提交系同向（均向下） | 官方示例无 Y 翻转 | 变换处改为 `Y = inkBounds.Y + inkBounds.Height − bb.y×s`（以 ink 底边为翻转基线），单点落在 mm 换算函数 |
| `export.jiix.text.words`/`bounding-box` 不影响 text/plain 与识别质量 | 官方配置参考定位为导出选项（且 4.4 默认即 true） | 移除 §4.3 配置（独立提交可回退） |
| 官方响应顶层无 `elements`/`result.elements` | 官方文档/示例/类型定义；仓库无真实样本 | 修复 a 已防御该形状 |

**golden fixture 定位**：实现与合入**不阻塞**（修复 b 是罕见兜底、主路径零改动）；**关闭 issue #15 前必须**在联调环境抓一份真实 MyScript 响应存为仓库内 golden fixture，钉死上表假设（首个核对项：Y 轴方向与 margin 平移）。

**验收对照**（issue 原文三条）：
- 标准 1（canned→绝对坐标）：测试 1/2/4/5/6；"本地 curl"需凭据不可行，以 stub e2e 等效替代。
- 标准 2（端上落位）：需 MyScript 凭据，本机无法执行——依赖上述 golden fixture 联调，关单前完成。
- 标准 3（exports 主路径回归）：测试 3（含双键并存优先级）+ 全量 go test/vet。

## 7. 超出范围（维持不处理）

- JIIX chars/segments/strokes 逐笔导出解析（shape 类型不在官方 Text/Math jiix 中，points 支持零收益）。
- `parseMyScriptResponse` 签名重构（双语义以注释文档化）。
- #14 智能排版尺寸缺陷、客户端逐元素紧包裹（ADR-019 后续）：关联但独立合入。

## 8. 审查记录

- **一轮（A 数值/B 根因/C 测试）**：A 无 P0（2×P2 吸收：shape Points 统一偏移、混合缺失测试）；B 2×P0（mm 单位、真实入口=exports jiix 字符串）触发 v2 重构，1×P1（elements 不可达）入 §1；C 3×P1 吸收（line box 断言、伪代码-代码一致、go test ./...+vet）。
- **二轮（A 数值/B 事实复核/C 实现就绪）**：
  - B P0：真实 word 节点**无 type 字段** → §4.2 words 一律按 text；P1：Math 用根节点单元素（expressions 是 operands 细类树）、自校准前提被官方样本证伪（行盒 padding≈9.25mm）→ §3 弃自校准、改纯缩放+原点；P1：补 `export.jiix.bounding-box=true`（v3.0 默认 false 跨版本钉死）；P2：修复 b 定位为罕见兜底（§1.6 措辞）、Accept 无需依赖但补齐防御（§4.3）；P3：修复 a 保留+注释标注来源、golden fixture 关单前必须。
  - A P1：根 bb 缺失/子节点 bb 缺失/退化分支三处留白 → 纯缩放方案消除 doc 依赖、子节点严格跳过（§4.2.4）、根分支显式 nil 语义（§4.2.3）；P2：Y 轴方向入假设表、mm 断言容差、Text Accept 补 jiix。
  - C P1：双键并存优先级 case（§5 测试 3c）、parseJiixExport 不复用 parseRawElements（§4.2 显式）、根/子 bb 语义钉死（§4.2.3/4）；P2：容差、键名优先级（canned 分别用 bounds/bounding-box）、points 从 jiix 路径移除（§4.2.5）；P3：表驱动与 helper 复用、handler 不调 t.Fatalf。
- **三轮（收敛）**：无 P0；P1=§6 行 3 残留 v2 `doc.y` 措辞（已改为 ink 底边基线单点改法）；7×P2 已吸收（测试 4 case 3/4 补数值与坐标期望、新增 case 8 双非空、Math 配置单测 测试 7、bounds 参数三语义注释、jiixBounds 签名与返回单位钉死、根分支套用变换与字段落点、almostEqual/shiftedPoints 签名）。结论：**v3 冻结进入实现**。
- **代码审查（两路对抗 + 变异测试）**：实现正确性审查 16 变异 12 杀 4 存活，存活者均为测试加固缺口且无实现 bug——已补齐：空白词夹具带 bbox（杀 M-A）、mm 换算字面量锚点 175.5905511811（杀 M-N）、非法 jiix fallthrough 到 elements 的接线用例（杀 M-D）、bbox 字段残缺跳过用例（杀 M-F），并实测两变异改错即红；设计符合度审查确认"明确不改"清单零违规、主路径解析侧回归为零（请求侧新增 export 配置/Accept 的边界已在 §6 假设表处置）、客户端契约闭合、假设单点性成立；P3 修复：nodeArray 注释纠偏、word label 键表收敛为仅 `label`（对齐冻结稿）、e2e 增加 math hint 分派场景、§5 夹具取值说明。
