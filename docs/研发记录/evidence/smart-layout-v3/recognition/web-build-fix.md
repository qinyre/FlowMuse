# V3 识别 Web 构建修复

2026-09-16；失败运行：GitHub Actions `35084651369`，基线 `a370d83`。

- 三种宿主的 Web 构建均失败；其他可用目标构建成功。报告仅留错误尾部，本地 `flutter build web --no-pub` 复现了实际 dart2js 错误。
- 根因：`StructureRecovery._textFingerprintOf` 使用不能由 JavaScript 精确表示的 64 位整数常量与运算。
- 修复：复用现有跨 VM/Web 的 `fingerprint64`，输入为有序 `[unitId, text]` JSON；包含完整 ID 和单元边界。服务端只校验并回填该请求字段，未改协议字段或 V1。
- 回归：固定中英文/emoji 向量、重复输入、等长 ID 变化、正文变化。
- 验证：Web 正式构建成功；`flutter analyze --no-pub` 零问题；全量 Flutter 测试 1657 项通过。
- 额外 Chrome 测试停在加载阶段，未取得测试结果，已停止本次测试进程，不计为通过。Web 编译验证与 VM 测试结果独立记录。
- 未关闭任何 CI 门禁。既有 Wasm dry-run/第三方字体警告不属于本次 dart2js 致命错误，未顺带修改依赖。
