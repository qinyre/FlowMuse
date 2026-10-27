# 第三方来源与许可边界

FlowMuse 的[受限源码许可](LICENSE)仅覆盖相关权利人有权据此授权的原创部分。第三方代码、字体、模型、SDK、预编译库和素材继续适用各自的许可；不能据根许可证限制他人独立、合法取得的上游材料，也不能把本仓库整体声明为完全从零原创。

## 直接内置、修改或随包分发的材料

| 材料与位置 | 已核对的来源/许可 | 适用范围与保留要求 |
| --- | --- | --- |
| `FlowMuse-App/lib/features/whiteboard/editor_core/` 中源自 markdraw 的实现 | [markdraw](https://pub.dev/packages/markdraw)，MIT；[原文](docs/研发记录/third_party/markdraw-MIT-LICENSE.txt)，Copyright 2026 Scott Horn | 本仓库于 `94125f11` 内置上游编辑器，后持续演进。原实现保持 MIT 权利及声明；根许可证至多覆盖可识别且有权另行许可的新增原创部分。内置记录不能替代缺失的上游精确版本标记。 |
| `FlowMuse-App/tool/vendor/code_assets/` | [BSD 声明](FlowMuse-App/tool/vendor/code_assets/LICENSE)；Dart project authors | 含 OHOS 适配的本地 fork；保留原许可，不能标成独占原创。 |
| `FlowMuse-App/tool/vendor/path_provider/`、`path_provider_ohos/` | 各目录 [BSD 声明](FlowMuse-App/tool/vendor/path_provider/LICENSE)、[BSD 声明](FlowMuse-App/tool/vendor/path_provider_ohos/LICENSE) | 保留 Flutter 与原贡献者的版权和免责声明；本地修改不撤销上游许可。 |
| `FlowMuse-App/tool/vendor/flutter_math_fork/` 与内置 KaTeX 字体 | [Apache-2.0](FlowMuse-App/tool/vendor/flutter_math_fork/LICENSE)、[KaTeX MIT](FlowMuse-App/tool/vendor/flutter_math_fork/lib/katex_fonts/LICENSE) | 代码许可与字体许可分别保留，不能仅携带外层 Apache 文本。 |
| `FlowMuse-Server/third_party/engine.io/` 及子目录 | [主实现 MIT](FlowMuse-Server/third_party/engine.io/LICENSE)、[events MIT](FlowMuse-Server/third_party/engine.io/events/LICENSE)、[webtransport BSD](FlowMuse-Server/third_party/engine.io/webtransport/LICENSE) | 含协作修复的本地替换；保留根目录及子组件许可。 |
| Web 扫码 `FlowMuse-App/web/scanner/zxing-0.23.0.min.js` | `@zxing/library 0.23.0`，[Apache-2.0](FlowMuse-App/web/scanner/LICENSE.zxing)；[来源/校验记录](docs/研发记录/third_party/2026-10-22-zxing-web-scanner.md) | 单独随 Web 分发，不属于团队独占代码；发行时保留许可证和适用通知。 |
| Excalifont | [原 OFL-1.1](FlowMuse-App/assets/fonts/markdraw/OFL.txt)，保留字体名 Excalifont | 字体保持 OFL，不改为根许可证；未修改本次字体二进制。 |
| Virgil | 字体自身 name 表第 0、13、14 项含版权、完整 OFL-1.1 和地址；[上游项目](https://github.com/excalidraw/virgil) | 本地字体沿用其随附元数据，不能拿 Excalifont 的版权行代替。随 App 的 NOTICES 另收录其原始声明和完整许可。 |
| FlowMuse Sans（Noto Sans SC 派生） | [来源与重命名记录](FlowMuse-App/assets/fonts/ui/README.md)、[OFL-1.1](FlowMuse-App/assets/fonts/ui/OFL.txt) | 保留上游版权、OFL 与派生重命名，不把字体改为非商业许可。 |
| Android 内置 Zipformer 双语模型 | [上游下载说明](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/pretrained_models/online-transducer/zipformer-transducer-models.rst)指向 `csukuangfj/k2fsa-zipformer-bilingual-zh-en-t`，其[模型卡声明 Apache-2.0](https://huggingface.co/csukuangfj/k2fsa-zipformer-bilingual-zh-en-t/blob/main/README.md) | **权重与 SDK 的许可须分开核对。** 当前文件夹未保存原下载包的校验和与随包授权，尚未完成逐文件上游哈希对应；不得仅凭 sherpa-onnx SDK 的 Apache 许可认定全部权重已核清。根许可证不覆盖这些权重；再发布前补齐来源/许可对应证据。 |
| 鸿蒙预编译 `FlowMuse-App/ohos/entry/libs/arm64-v8a/libsqlite3.so` | Git 引入记录 `b18764af`；文件中可见版本字符串 `3.53.2`，但未找到可复核的构建/供应来源记录 | **来源待核实。** 维护者仅记得可能来自 SDK，不能作为授权证明；不因 SQLite 项目的一般许可或此版本字符串就认定该特定二进制可再分发。本轮保留文件，不重写其归属；下次发布前补证或从可信来源重建。 |

绘图格式和部分交互参考 Excalidraw；兼容其格式不代表所有实现均直接复制自其源码。涉及实际引入的第三方代码时，仍须按真实来源保留相应许可。

## 依赖、SDK 与发布

- Flutter/Dart 的准确版本以 `FlowMuse-App/pubspec.lock` 为准，Go 以 `FlowMuse-Server/go.mod`、`go.sum` 和本地替换为准；本次不升级依赖。
- [依赖许可核对清单](docs/研发记录/third_party/2026-10-27-dependency-license-inventory.md)区分 Dart/SDK 包、Go 声明依赖、实际 Linux 服务依赖及未检查的开发工具依赖。文本关键词扫描不是完整的兼容性或权属法律结论。
- Flutter 引擎/SDK 的通知可能同时包含 BSD、Apache、MPL 等文本。MPL 中提到 GPL 的“Secondary License”定义，不等于整个 Flutter 或 FlowMuse 变为 GPL；相应组件仍按其真实授权履行义务，不得删除原通知。[Mozilla 官方说明](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
- `FlowMuse-App/NOTICES` 按 Flutter 的多组件格式携带项目许可及直接内置材料的完整通知；依赖自身的许可继续由 Flutter 正常收集。发行 App/Web 时保留生成的 `NOTICES` / `NOTICES.Z`，设置中的许可页面用于查看。
- `FlowMuse-Server/NOTICES` 保留项目许可、已核对的 Go 依赖、Go 标准库及直接内置子组件的完整通知；服务端二进制或容器分发须携带该文件。基础镜像、操作系统及外部服务另有自己的许可和义务。
- **通知文件不是授权证明。** 它不能弥补来源不明的二进制/模型，也不能替代原生平台 SDK、预编译依赖、模型和外部服务的额外条款。新打包前仍须核对实际交付内容与版本。

## 演示工程与素材

- `docs/参赛文档/复赛演示视频/` 的字体、实录、配音和其他素材，不因仓库根许可而转成团队独占资源；按各自来源和授权记录处理。
- DM Sans 保留[随附 OFL](docs/参赛文档/复赛演示视频/DM-Sans-LICENSE.txt)；MiSans 等本机系统字体不能仅因本机可用就随源码或发行包复制。
- [音频来源说明](docs/参赛文档/复赛演示视频/edit/public/audio/SOURCES-LICENSE.md)记录算法合成方式且不额外主张独占版权；本次不推翻其中已有授权，也不把未使用的第三方音效写成已获得授权。
- Remotion `4.0.528` 属于有条件的 [Remotion License](https://www.remotion.dev/docs/license)，不能标为 MIT。是否需要商业许可须按实际主体、人数和使用方式核对；根许可不替代其授权。
- 演示工具中的 `@ffmpeg-installer/win32-x64 4.1.0` 包声明 GPLv3。它是独立视频制作工具，不是 App/Go 服务的代码依赖；本轮不将其二进制再分发或改为受限许可。若未来分发该工具/二进制，须另行遵守其 GPL、来源和源码提供要求。

## 历史授权与贡献

新许可只适用于明确随附它发布的版本，不追溯撤回有效的历史许可、第三方授权或平台内浏览/fork 权利。Git 提交作者、维护者名称或仓库所有权本身不等于完整的版权归属、学校/单位归属或代表所有贡献者另行商业授权的证明。

贡献者应只提交有权按目标文件所适用许可发布的材料，说明第三方来源。贡献者保留版权；不同条款的商业/参赛授权必须由相应有权授权者作出。本次未假定存在尚未提供的版权转让或贡献者授权协议。
