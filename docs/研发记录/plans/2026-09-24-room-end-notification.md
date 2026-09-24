# 房主结束后成员仍能协作

## 原因与范围

HTTP 结束接口只写入 `ended_at`，清除在线成员和广播 `room-ended` 依赖房主随后再发送 Socket.IO `end-room`。后一条消息丢失时，实时转发仍认可旧成员。修复复用现有房主鉴权、结束事件和客户端退出流程，不修改加密、数据库结构或同步协议。

## 实施与验证

1. HTTP 成功结束后，由服务端直接清除 Hub 成员并广播；Socket.IO 结束入口复用同一收尾逻辑。加入与结束交错时再次检查房间状态。
2. 客户端收到结束通知后停止周期同步；本机主动结束不再重复显示被结束提示，忽略其他房间或重复通知。
3. 使用实际 HTTP + Socket.IO + 隔离 PostgreSQL schema 回归：不发送客户端 `end-room`，验证成员收到通知、旧连接不能继续同步、不能重新加入、非房主不能结束，且其他房间不受影响。
4. 跑 Go test/vet 和 Flutter 检查，分开提交服务端和客户端修复；CI 通过后部署并保留回退版本。

## 验证结果

- Go `test ./...`、`vet ./...` 通过。本地没有测试数据库，数据库用例另行在已有 `flowmuse-invite-test-20260923` 容器内运行；未启用 SSH 转发或新建服务环境。
- `TestHTTPEndRoomRevokesLiveMembersWithoutClientEndEvent` 使用独立 schema 连续通过三次，覆盖 HTTP 结束通知、移出 Socket.IO 房间、撤销实时笔迹与可靠消息权限、重复结束、重入拒绝、非房主拒绝及其他房间保留。
- Flutter 全量 1772 项通过、6 项既有跳过；新增主动/被动结束回归覆盖事件早于 HTTP 响应、重复及旧房间通知、断开和停止快照。分析仅有忽略的 `build/nav_compact_screenshot_test.dart` 既有告警。
- CI 保留既有配置：当前推送令牌没有修改 workflow 的权限，数据库用例的实际执行证据来自上述隔离库联调，未将 CI 跳过误报为通过。
