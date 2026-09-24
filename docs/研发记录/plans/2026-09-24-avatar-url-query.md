# 头像上传后无法显示修复

## Context 与需求

用户反馈头像上传不可用。线上日志显示头像 POST 返回 200，随后图片 GET 因版本参数中的 `?` 被编码为 `%3F` 返回 404。服务端返回 `/api/users/{id}/avatar?v=...`，客户端 `AccountRepository._uri` 将整段字符串作为 URI path，误把 query 当作路径。

## 实现方案与关键文件

- 在 `AccountRepository._uri` 复用 Dart URI 解析，保留现有服务地址前缀和头像版本 query；所有头像展示继续走既有共用入口。
- 在 `account_network_config_test.dart` 补充版本 query、服务地址前缀、空头像与绝对 CDN 地址回归。
- 不修改上传接口、图片文件、用户资料、数据库或原生平台代码；已上传头像无需重传。

## 验证与实施步骤

1. 新增回归，确认旧逻辑失败，再修复 URL 解析。
2. 运行账号相关测试、全量 Flutter 测试与 analyze。
3. 只读验证线上相同头像的正确地址返回图片，错误地址为 404；不输出用户标识或图片内容。
4. 构建 Web/Android，更新网页版；安卓设备连接时覆盖安装，鸿蒙由队员验证。
5. 保留回滚版本，推送 PR，CI 通过后合并主分支。

## 验证记录

- 回归在旧代码失败：`avatar?v=...` 被解析为包含 `%3F` 的路径；修复后包含前缀与末尾斜杠的四种服务地址均通过。
- 账号测试 11 项通过；全量 Flutter 测试 1765 项通过、6 项既有跳过。analyze 无 error，只有既有本地 `build/nav_compact_screenshot_test.dart:199` warning。
- 线上只读对照：同一张已上传头像，错误地址 404；正确地址 200、`image/jpeg`、300227 bytes，CORS 允许 Web 应用来源。
- 修改仅在共享 Dart URL 解析，无原生代码、接口或数据库变更；实际发布状态记录在对应 PR。
