# 智能排版 v3 分析协议（V3-200A 冻结）

- 端点：`POST /api/ink/smart-layout/analyze/v3`（handler 归 V3-201B；本文件冻结 schema/字段/错误映射）
- 内容类型：`application/json; charset=utf-8`
- 双端强类型：Dart（`FlowMuse-App/lib/features/whiteboard/smart_layout/protocol/`）与 Go（`FlowMuse-Server/internal/recognition/smart_layout_v3_types.go`）消费同一组 fixtures（`fixtures/`），正例无损 round-trip、负例双端同类拒绝。
- typed text 永远只来自请求 `exactTexts`；服务端不得从图片重建打字文本。响应 schema 无任何 text 字段。
- 解析为严格模式：未知字段（任意层级）拒绝；必需键（含嵌套数组元素级）缺失或显式 null 拒绝；枚举闭集；数值范围显式；无动态 map 透传；JSON 值之后的尾随内容拒绝。
- 字符长度按 Unicode 字符数（rune）计量（pageId/requestId ≤128、text ≤10000、warning ≤500），不按字节或 UTF-16 码元。
- 校验顺序：必需键与结构先于枚举/引用校验（缺失一律 invalid_request；unknown_enum/dangling_reference 仅用于"存在但取值非法/悬空"）。sourceRefs 集合先于 marks/exactTexts 收集（引用依赖，双端一致）。
- region.sourceIds 对请求 sourceRefs 的跨消息校验属链路层（V3-201B handler 落实），本文件的双端解析器各自独立存在时只做消息内校验。

## 请求 schema

```json
{
  "protocolVersion": 3,
  "pageId": "page-1",
  "sceneRevision": {"epoch": 0, "revision": 5, "fingerprint": "0123456789abcdef"},
  "assets": [
    {"key": "crop|r1", "kind": "crop", "fingerprint": "0123456789abcdef"}
  ],
  "marks": [
    {"markId": "m1", "label": "m1", "assetKey": "annotated|page", "sourceId": "r1"}
  ],
  "exactTexts": [{"sourceId": "text-1", "text": "已打字内容"}],
  "sourceRefs": ["r1", "text-1"]
}
```

约束（校验顺序按字段声明序；fixtures 每个负例只违反一条）：

| 字段 | 规则 | 违例错误码 |
| --- | --- | --- |
| protocolVersion | 必须 == 3 | invalid_request |
| pageId | 非空，≤128 字符 | invalid_request |
| sceneRevision.epoch / revision | 整数 ≥ 0 | invalid_request |
| sceneRevision.fingerprint | 16 位小写 hex | invalid_request |
| assets | ≤ 64 条；key 非空且唯一；kind ∈ {clean, annotated, crop}；fingerprint 16 位小写 hex | 超限 limit_exceeded；枚举 unknown_enum；其余 invalid_request；key 重复 duplicate_reference |
| marks | ≤ 512 条；markId 非空且唯一；label 非空；assetKey 必须引用已声明 asset；sourceId 必须 ∈ sourceRefs | 超限 limit_exceeded；assetKey 悬空 dangling_reference；markId 重复 duplicate_reference；其余 invalid_request |
| exactTexts | sourceId 唯一且 ∈ sourceRefs；text ≤ 10000 字符 | sourceId 重复 duplicate_reference；悬空 dangling_reference；超长 limit_exceeded；其余 invalid_request |
| sourceRefs | 每项非空且唯一，总数 ≤ 2048 | 重复 duplicate_reference；超限 limit_exceeded；其余 invalid_request |
| 任意层级未知字段 | 拒绝 | unknown_field |
| 非对象/类型错误 | 拒绝 | invalid_request |

## 响应 schema

```json
{
  "protocolVersion": 3,
  "requestId": "req-1",
  "regions": [
    {
      "id": "g1",
      "role": "title",
      "sourceIds": ["r1"],
      "readingOrder": 0,
      "confidence": 0.9,
      "relations": [{"type": "captionOf", "targetRegionId": "g2"}]
    }
  ],
  "warnings": ["低速网络重试一次"]
}
```

| 字段 | 规则 | 违例错误码 |
| --- | --- | --- |
| protocolVersion | == 3 | invalid_request |
| requestId | 可选；非空时 ≤128 | invalid_request |
| regions | ≤ 128；id 非空唯一；role ∈ {title, body, caption, figure, formula, list, table, unknown}；sourceIds 非空且区域内唯一；readingOrder ≥ 0；confidence ∈ [0,1] | 超限 limit_exceeded；role 枚举 unknown_enum；id 重复 duplicate_reference；范围 invalid_request |
| relations.type | ∈ {captionOf, boundTo, sameColumn} | unknown_enum |
| relations.targetRegionId | 必须引用已声明 region id | dangling_reference |
| relations 有向链 | 不得成环 | reference_cycle |
| warnings | 每条 ≤ 500 字符，≤ 16 条 | limit_exceeded |
| 未知字段 | 拒绝 | unknown_field |

## 错误 envelope

```json
{"error": {"code": "invalid_request", "message": "pageId 不能为空", "field": "pageId"}}
```

- code ∈ {invalid_request, unknown_field, unknown_enum, dangling_reference, duplicate_reference, reference_cycle, limit_exceeded}
- field 可选，指向首个违例字段（可含索引，如 `assets[2].kind`）。
- HTTP 状态映射（V3-201B handler）：invalid_request/unknown_field/unknown_enum/dangling_reference/duplicate_reference/limit_exceeded → 400；reference_cycle → 400；服务端内部故障 → 500（code=internal，不在本冻结范围）。

## 字段可追溯性

- 每个 region 只引用请求 sourceRefs 中的 id（悬空即拒）；
- marks 经 sourceId 关联资产与来源对象；
- asset/marks/region 无自由文本语义负载（text 仅存在于请求 exactTexts，由客户端 Scene 投影，不从模型往返）。
