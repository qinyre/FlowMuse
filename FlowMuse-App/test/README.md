# 测试与 CI

从 `FlowMuse-App` 执行 Flutter 命令。依赖已解析时使用 `--no-pub`，避免每次测试重新做 Pub 检查。

## 日常检查范围

| 改动 | 本地验证 |
| --- | --- |
| 普通 Markdown/导航 | 事实、引用、链接/路径及 `git diff --check` |
| 普通 UI/动画 | 静态分析、受影响页面的关键交互与直接调用方测试 |
| 保存、迁移、撤销、协作、加密、共享内核或依赖 | 静态分析、相关回归及完整 App 测试；跨端协议需前后端联验 |
| CI、测试选路、工作流 | Node 策略自测、工作流语法验证及完整回归，验证失败/取消不能被汇总门禁放行 |
| 机读 docs、fixture、脚本 | 按实际消费者验证；不能按后缀当普通文档跳过 |
| 原生插件/平台工程 | 对应平台构建及实机验证；需要时手动运行平台矩阵 |

```sh
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test --no-pub test/features/settings
flutter test --no-pub                   # 完整回归
```

系统通知的 Web 桥接与 worker 检查使用 Node 内置测试器：`node --test test/web/system_notices_test.cjs`。此检查覆盖子路径、来源校验、点击目标和权限拒绝，不代表真实设备已收到通知；系统通知显示与点击仍需实机验收。

不因测试数量多就删除保存、回滚、合并冲突、加密或格式兼容场景。优先清理无生产调用的组件自测、只复述常量的断言、重复工作流及不准确的测试机性能阈值。组件布局只验证影响交互与无障碍的行为，不逐项冻结样式实现。

## GitHub CI 选路

Quality 在 PR、main push、手动运行时触发，功能分支 push 不再额外跑同一轮。新提交会取消同一 PR 的旧检查。

- 普通文档与 docs 截图不安装 Flutter、不执行 Go；保留原有 Flutter/Go 状态名称。
- App 改动跑全部 `test/`，以 `--total-shards=2 --shard-index=0/1` 在两台独立 runner 上并行。分析全项目一次；相关改动保留 V3 的严格告警门禁、双跑确定性和 CI 工具自测。
- Server 改动执行 `go test ./...` 与 `go vet ./...`，缓存依赖键使用服务端 `go.sum`。
- CI/未知路径扩大为全量；无效 base 或 diff 失败会失败。删除及跨目录重命名包含旧路径，不因改成 Markdown 而漏跑。
- `docs/研发记录/specs/smart-layout-v3/`、`evidence/`、`plans/smart-layout-v3-agent/` 为机器输入，检查前后端共享契约。App assets/fixture/vendor 即使是 Markdown 也需回归。
- 手动运行 Quality 强制所有检查。Flutter 缓存仅包含固定版本 SDK 和 Pub 依赖；始终按锁文件解析，不缓存 App 测试通过状态或项目 `.dart_tool`；Go 使用标准编译/测试缓存。

本地可依次执行两个分片，**两条都通过才等价于完整回归**：

```sh
flutter test --no-pub --total-shards=2 --shard-index=0
flutter test --no-pub --total-shards=2 --shard-index=1
```

在仓库根运行轻量选路自测：`node --test .github/scripts/ci-scope.test.mjs`。路径策略由 `.github/scripts/ci-scope.mjs` 维护；新增被机器读取的 docs 目录时同步策略及边界用例。

## 独立诊断与性能

- `Smart Layout V3 CI`：手动运行完整五阶段矩阵，保留报告/失败诊断，不再与 Quality 重复执行普通测试。
- `Smart Layout V3 Platform`：相关 main 更新或手动运行六端配方；无 SDK 的目标明确标记 `release_deferred`。
- 需在合并前检查平台变更时，手动选择对应分支运行平台矩阵；构建通过不代表实机性能通过。
- 真实设备性能按[Profile 回放说明](../integration_test/README.md)执行。首页冒烟只检查启动可用性，不把 Widget 测试的宿主墙钟宣称为实机首帧。

`.gitlab-ci.yml` 仍保留既有私有 runner 配方；这里的 GitHub 缓存/分片设置不自动作用于 GitLab。
