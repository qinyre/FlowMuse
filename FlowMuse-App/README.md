# FlowMuse 客户端

Flutter 应用，包含本地资料库、Markdraw 编辑器、加密协作、PDF 批注、识别和 AI 助手。产品说明、环境准备与本地服务启动见[仓库首页](../README.md)，开发前先读 [AGENTS.md](../AGENTS.md)。以下命令除图标脚本外均在本目录执行。

## 目录与配置

| 目录 | 职责 |
| --- | --- |
| `lib/app/` | 路由、主题和应用装配 |
| `lib/features/` | 资料库、账户、社交、设置与白板功能 |
| `lib/features/whiteboard/editor_core/` | 内置 Markdraw 编辑器及公开导出入口 |
| `lib/shared/` | 存储、网络、平台适配与共享组件 |
| `test/`、`integration_test/` | 单元/Widget 测试与设备性能回放 |
| `android/`、`ohos/` 等 | 各平台工程与原生通道 |
| `tool/` | Web 发布自检、性能和智能排版工具 |
| `tool/vendor/` | 仍在使用的依赖适配，原因见 `pubspec.yaml` |

应用设置保存在 SQLite `local_settings`，敏感凭据走安全存储。`assets/config/app.env` 只放可以随应用公开的配置；AI、识别、签名与服务端密钥不得打入资源。

| 构建参数 | 用途 | 默认 |
| --- | --- | --- |
| `FLOWMUSE_COLLAB_SERVER_URL` | 账户、协作、附件与识别 API | `https://api.flowmuse.cloud` |
| `FLOWMUSE_SHARE_ORIGIN` | 房间分享 Web 入口 | `https://app.flowmuse.cloud` |
| `FLOWMUSE_LAYERED_WET_INK` | 湿墨分层 | `true` |
| `FLOWMUSE_LIVE_INK_V2` | 实时墨迹协议 | `true`，还需分层开关及服务端支持 |

前两个地址优先读取 `--dart-define`，其次为随包 `app.env`。后两个是编译期开关，普通构建默认开启；可显式传入 `--dart-define=FLOWMUSE_LAYERED_WET_INK=false` 或 `--dart-define=FLOWMUSE_LIVE_INK_V2=false` 做关闭对照。参与测试的 Web、原生客户端仍需核对配置及协议能力。

## 源码与发行许可

原创部分适用仓库根的 [FlowMuse 源码使用许可](../LICENSE)，商业二次利用和将软件作为作品参赛需书面授权；第三方代码及用户内容的权利边界见[第三方声明](../THIRD_PARTY_NOTICES.md)。内置编辑器源自 MIT 许可的 markdraw，并由本项目持续修改维护。

发行时保留 `NOTICES`。Flutter 会收集本包 `NOTICES` 及各依赖的许可，写入 App/Web 的 `NOTICES` / `NOTICES.Z`；设置中的“软件与第三方许可”可查看。它包含完整的原创许可、markdraw、字体、内置 KaTeX 和 Web ZXing 通知，不将它们统一改为受限许可。实际语音权重、原生 SDK 与预编译库仍须按第三方声明核对来源和再分发权利，通知不能替代授权证明。

修改根 `LICENSE` 或更新依赖/内置材料时，同步本包通知中的相应文本并核对原许可；不要清空 Flutter 自动收集的依赖许可。该政策适用于随附它的新版本，不能据此追溯变更旧发行版。

## 本地开发与检查

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port=8080 --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
flutter analyze --no-pub
flutter test --no-pub
```

依赖变更后先更新锁文件，再按锁文件重新验证；不要顺带升级无关依赖。插件注册文件由 Flutter 生成，不手工编辑或强制入库。

开发中先跑相关测试，完整回归与 CI 分片规则见[测试说明](test/README.md)。普通文档无需跑整套；源码 PR 仍全量覆盖，避免多个工作流重复跑相同测试。

插件变更或测试后若发布构建出现陈旧注册，先执行正常的 `flutter pub get` 与目标构建，使注册文件按当前目标重新生成；不要手改注册文件，排障时不要坚持 `--no-pub`。仍有缓存问题时仅清理对应目标生成缓存，无需删除全部编译中间产物。

## 使用入口与平台边界

- 设置分类可通过 `/settings?section=theme`、`/settings?section=document` 等路由打开，分类 ID 以 `SettingsPage` 枚举为准。卡片、选择器、主题预览及动效遵循[界面约定](../docs/技术设计/界面与交互.md)。
- Web 白板支持 Ctrl+滚轮缩放；搜索当前只匹配笔记标题及副标题，不扫描白板正文或未识别手写。
- 支持设备上的笔身双击与起笔重压临时橡皮是两条独立交互。轻捏菜单、预测点及其他厂商手势不因已有双击通道而自动可用。
- 语音使用系统/浏览器识别及 Android 离线回退，具体隐私和可用性见[现行语音规格](../docs/技术设计/语音转文字规格.md)。

## Web 发布

```sh
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --base-href / --dart-define=FLOWMUSE_COLLAB_SERVER_URL=https://api.flowmuse.cloud --dart-define=FLOWMUSE_SHARE_ORIGIN=https://app.flowmuse.cloud --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
python tool/precompress_web.py build/web
node --test tool/web_startup_test.mjs
python tool/precompress_web_test.py
```

发布整个 `build/web`，包含 `.gz`；`tool/precompress_web.py` 仅使用 Python 3.11+ 标准库。使用 [Nginx 静态资源配置](tool/nginx_web_resources.conf) 并保留现有 HTTPS、API 与 WebSocket 代理；`nginx -t` 通过后再 reload。页面路径需回退到 `index.html`，确保 `/library`、`/whiteboard/collaboration` 和邮件路由可以直接访问及刷新，保留房间 fragment。

`--no-web-resources-cdn` 随包提供 CanvasKit，避免外部 CDN 导致白屏；当前不启用 Flutter 离线 Service Worker，未版本化资源返回 `Cache-Control: no-cache`。若发布到子路径，需同步调整 base href 与站点路由，不能复用根路径配方。

发布后核对实际入口、主脚本、CanvasKit、UI 字体、扫码解码脚本、缓存/压缩响应，并用干净浏览器验证启动、保存及必要协作流程。记录源提交、构建参数和资源哈希；临时上传包验证后清除，不累积整包归档。纯客户端更新无需重启 Go 服务。

Web 上 `compute` 仍在原事件循环执行；原生端的大 PDF 后台编码优化不能直接当成 Web 的线程优化。书写流畅度需使用真实 PDF 复测。

## 原生构建

Android：

```sh
flutter build apk --release --target=lib/main.dart --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
```

HarmonyOS（OHOS Flutter SDK、完整 DevEco SDK 和签名配置齐备时）：

```sh
flutter build hap --release --target=lib/main.dart --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
```

不要将 CI 为静态检查创建的空 SDK 目录当成可用的 HarmonyOS SDK。HAP/APK 编译通过也不等于笔压、双击、扫码、授权和性能已通过实机验证。[性能 runner 说明](integration_test/README.md)包含 Profile 回放、设备身份与历史数据隔离要求。

## 图标与字体维护

图标原图为 `assets/images/flowmuse-app-icon.png`。在**仓库根目录**生成 Android、OHOS 和 Web 派生图，或只读检查：

```powershell
powershell -NoProfile -File scripts/Generate-AppIcons.ps1
powershell -NoProfile -File scripts/Generate-AppIcons.ps1 -Check
```

派生图入库；更新图标后同步 Web 入口与 manifest 中的图标版本，保留现有 `start_url`。原生需重新打包，Web 需发布新构建。

界面字体及授权见 [FlowMuse Sans](assets/fonts/ui/README.md)。只有重新裁剪字体时需要 `fontTools`；正常构建不需要重新下载字体。白板内容字体与界面字体分开维护，保留许可证及格式兼容。
