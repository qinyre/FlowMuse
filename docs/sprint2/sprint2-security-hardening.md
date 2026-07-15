# Sprint 2 安全加固挑战报告

更新时间：2026-07-14  
挑战类型：安全加固挑战  
审计基线：OWASP Top 10（2021）  
范围：`FlowMuse-Server` HTTP、鉴权与协作元数据入口

## 1. 挑战结论

本轮确认并修复 3 个安全问题，均有自动化回归测试：

| 编号 | OWASP 分类 | 问题 | 修复结果 |
| --- | --- | --- | --- |
| SEC-01 | A05 安全配置错误 | 通配 CORS 与 credentials 同时启用 | 通配来源不再允许 credentials；仅明确白名单来源允许 |
| SEC-02 | A02 加密机制失效 / A07 身份认证失效 | 房主密钥哈希使用普通字符串比较 | 改为标准库恒定时间比较，避免比较耗时泄露匹配程度 |
| SEC-03 | A04 不安全设计 | 账户与房间元数据 JSON 请求体无大小限制 | 统一限制为 64 KiB，超限返回 HTTP 413 |

## 2. 修复前后对比

### SEC-01：CORS 凭据边界

**修复前**

- `FLOWMUSE_ALLOWED_ORIGINS=*` 时，服务端反射任意 `Origin`。
- 同时返回 `Access-Control-Allow-Credentials: true`。
- Socket.IO 也无条件启用 credentials。

**修复后**

- 通配模式固定返回 `Access-Control-Allow-Origin: *`，不再返回 credentials。
- 只有配置中的明确来源会回显 Origin 并允许 credentials。
- HTTP 与 Socket.IO 使用相同判定规则。

**验证**

- `TestWithCORSHandlesBrowserPreflight`
- `TestWithCORSAllowsCredentialsOnlyForExplicitOrigin`

### SEC-02：房主密钥哈希比较

**修复前**

- 结束协作房间时，服务端使用普通字符串相等运算比较房主密钥哈希。
- 普通比较可能因首个不同字符的位置产生耗时差异，形成远程计时侧信道。

**修复后**

- 使用 Go 标准库 `crypto/subtle.ConstantTimeCompare` 比较固定长度 SHA-256 哈希。
- 空哈希仍直接拒绝，房主账号校验逻辑保持不变。
- 不修改配置、部署文件、接口协议或服务器启动流程。

**验证**

- `TestOwnerKeyHashesEqual`

### SEC-03：JSON 请求体资源上限

**修复前**

- 登录、注册、密码重置等账户 JSON 入口没有请求体上限。
- 创建房间和结束房间的元数据入口没有请求体上限。
- 攻击者可持续发送超大 JSON，占用服务端内存与解析时间。

**修复后**

- 账户 JSON 和房间元数据统一限制为 64 KiB。
- 场景接口继续保留 8 MiB 独立上限，文件接口继续保留 10 MiB 独立上限。
- 超限统一返回 `413 Request Entity Too Large`，非法 JSON 返回通用 400，不回显解析器内部错误。

**验证**

- `TestDecodeJSONRejectsOversizedBody`
- `TestRoomsRootRejectsOversizedMetadata`

## 3. OWASP Top 10 自查矩阵

| 分类 | 自查结果 | 证据或后续动作 |
| --- | --- | --- |
| A01 访问控制失效 | 已有防护 | 结束房间校验 owner 身份或 ownerKey；房间和文件 ID 使用安全字符白名单 |
| A02 加密机制失效 | 本轮修复 | 房主密钥哈希改用恒定时间比较；协作内容继续使用 AES-GCM 端到端加密 |
| A03 注入 | 未发现直接风险 | PostgreSQL 访问使用 pgx 参数绑定；对象存储键经过 room/file ID 白名单约束 |
| A04 不安全设计 | 本轮修复 | JSON 元数据增加 64 KiB 上限；场景和文件维持各自独立上限 |
| A05 安全配置错误 | 本轮修复 | 禁止 `*` 与 credentials 组合；生产仍应配置明确 Web 域名 |
| A06 易受攻击和过时组件 | 需持续治理 | 已固定依赖版本；建议在 CI 增加 `govulncheck ./...`，本轮未声称完成 CVE 扫描 |
| A07 身份认证失效 | 本轮修复 | 房主密钥校验避免计时侧信道；密码修改/重置后撤销既有 session |
| A08 软件和数据完整性失效 | 未发现直接风险 | 未从用户输入加载插件或执行代码；部署镜像仍建议固定 digest |
| A09 日志与监控失效 | 部分覆盖 | 现有日志不记录 token、ownerKey 和加密密钥；生产仍需接入限流与异常指标告警 |
| A10 SSRF | 未发现用户可控入口 | MyScript 与 AI Base URL 仅由服务端环境变量配置，客户端不能提交目标 URL |

## 4. 自动化验证证据

执行命令：

```powershell
cd FlowMuse-Server
go test ./...
go vet ./...
```

结果：

- `cmd/flowmuse-collab-server`：通过
- `internal/auth`：通过
- `internal/collab`：通过
- `internal/storage`：通过
- `go vet ./...`：退出码 0，无诊断输出
- `git diff --check`：通过

## 5. 部署前要求

1. 生产环境将 `FLOWMUSE_ALLOWED_ORIGINS` 配置为实际 Web 域名，不使用 `*`。
2. 当前线上协作地址仍为 HTTP；TLS 终止属于部署层工作，未在本次本地挑战中修改或伪报完成。
3. 本次没有改变服务器启动流程，也没有部署、重启或修改线上服务器。
