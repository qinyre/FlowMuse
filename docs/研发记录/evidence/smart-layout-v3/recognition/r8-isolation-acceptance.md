# R8：V1 / V3 隔离与自动回归验收

日期：2026-09-16。基于 R7 提交 `94f21e7`，遵循同日独立识别计划与实现 spec v4。

## 结论与范围

R8 自动验收通过。本包仅补测试，不修改生产实现，不删除旧测试，不放宽架构门禁。
V1 指旧控制器识别/模板链（代码中部分命名为 v2），不是 `/analyze/v3` 实验协议。
测试使用真实控制器、V3 scope/pipeline 和可控传输响应；不代表真实模型识别质量或实机通过。

## 隔离证据

| 验收项 | 自动化入口与断言 |
| --- | --- |
| 新旧取消双向独立 | `recognition/wiring_v3_entry_test.dart`：同一真实控制器上两条识别同时在途；取消 V3 后旧准备成功、V3 token 已取消且旧 cancel 调用为零；取消 V1 后旧准备抛取消异常、V3 token 未取消且 V3 成功 |
| 不调用旧准备、不回退旧引擎 | 同文件：观测旧 prepare/cancel 调用，执行原实现而非替换为空操作；V3 请求仅命中 `/recognize/v3`；503 未配置时源保留、partial 为真、旧 prepare/vision/cancel 调用为零 |
| 配置双向独立 | `FlowMuse-Server/internal/config/config_test.go` 的 `TestRecognitionV1V3ConfigurationIsolation`：URL/key/model/timeout 独立读取；分别修改两侧配置不覆盖另一侧；V3 缺 URL/model 不借用旧配置，仅 key 按协议允许回落 ARK |
| 静态隔离 | `v2_client_isolation_matrix_test.dart`：保留旧 URL 禁止断言、要求新旧实验端点存在；拦截旧控制器调用、tear-off、旧视觉回调访问及旧 repository 直接导入 |
| 既有架构边界 | `gateways/smart_layout_architecture_test.dart` 未修改，随全量测试通过 |
| V1 冻结 | 相对 `d158d7c` 检查 editor_core 源码与既有测试、旧 ink_recognition_repository、服务端 internal/recognition，均无差异 |

除注明服务端路径外，测试相对目录为 `FlowMuse-App/test/features/whiteboard/smart_layout/`。

## 本轮验证

- `cd FlowMuse-App; flutter analyze --no-pub`：退出 0，No issues found。
- `cd FlowMuse-App; flutter test --no-pub --reporter expanded`：退出 0，1646 项全部通过。
- `cd FlowMuse-Server; go test ./...`：退出 0，全部包通过。
- `cd FlowMuse-Server; go vet ./...`：退出 0。
- `git diff --check`：通过。

覆盖包含既有分区、协议、源账本、列表与原生组、取消/过期结果、应用/撤销/重开回归；未另建执行框架或生成临时验证脚本。

## 下一阶段

R9 尚未完成：常驻 CER 评测工具、20 页固定真值与 V1/V3 真实预测对照、真实设备与 #14 字号验证仍需执行。R8 不以模拟响应替代这些结果。
