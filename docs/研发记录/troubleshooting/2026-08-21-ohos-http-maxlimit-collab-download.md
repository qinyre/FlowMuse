# 鸿蒙 HTTP 响应默认 5MiB 上限疑似影响协作文件下载（存量问题）

> 发现日期：2026-08-21
> 发现途径：AI 视觉附件计划（`docs/研发记录/plans/2026-08-21-ai-visual-attachment.md`）对照 `harmonyos-guides` 官方文档核验鸿蒙 HTTP 通道时发现
> 性质：**存量问题**，与 AI 视觉附件计划无关；该计划响应体为小 JSON，不受影响

## 现象与风险

`@ohos.net.http`（Network Kit）存在"响应消息最大字节限制"参数 `maxLimit`：**默认值 5\*1024\*1024（5MiB），最大值 100\*1024\*1024，API version 11+**。依据：`harmonyos-guides/系统/网络/Network Kit（网络服务）/访问网络/http-request.md` 功能表"设置响应消息的最大字节限制"一行。

FlowMuse 的鸿蒙 HTTP 通道 `FlowMuse-App/ohos/entry/src/main/ets/channels/HttpChannel.ets` 的 `doRequest`（二进制收发）与 `doPost`（字符串收发）均**未设置 `maxLimit`**，因此所有经鸿蒙通道的请求响应都受默认 5MiB 上限约束。

协作文件存储的业务上限是 10MiB：`collaboration_file_store.dart:61` `_maxFileBytes = 10 * 1024 * 1024`，上传/下载经 `HarmonyAwareHttpClient`（`native_http_client.dart`，走 `doRequest`，`expectDataType: ARRAY_BUFFER`）。**当协作文件实际体积在 5MiB～10MiB 区间时，鸿蒙真机上的下载可能被截断或报错**（响应超过默认 maxLimit 时 @ohos.net.http 的具体失败表现需真机确认）。

## 影响范围

- 平台：仅鸿蒙真机（其他平台走 package:http / dart:io，无此上限）。
- 功能：协作房间内 5MiB 以上的加密快照/图片文件下载。上传方向（请求体）官方文档无大小限制，不受影响。
- AI 视觉附件计划：不受影响（响应为小 JSON）。

## 建议修复方案（待立项）

1. 在 `HttpChannel.ets` 的 `doRequest`（必要时含 `doPost`）的 `http.HttpRequestOptions` 中显式设置 `maxLimit`，取值与业务上限对齐或直接取官方最大值 100MiB（如 `maxLimit: 100 * 1024 * 1024`）。
2. 真机回归：上传一个 6～9MiB 协作文件并下载，验证完整性与哈希；同时验证接近 10MiB 上限的拒绝路径仍正常。
3. 顺带确认：`usingCache` 默认 true 是否需要按请求语义显式关闭（POST/PUT 一般不受影响，低优先级）。

## 关联

- 计划文档：`docs/研发记录/plans/2026-08-21-ai-visual-attachment.md`（勘察表"鸿蒙 HTTP 官方依据"行）
- 涉及代码：`ohos/entry/src/main/ets/channels/HttpChannel.ets`（doRequest/doPost 均未设 maxLimit）、`lib/features/whiteboard/collaboration/services/collaboration_file_store.dart:61`（10MiB 业务上限）、`lib/features/whiteboard/ink_recognition/native_http_client.dart`（HarmonyAwareHttpClient）
