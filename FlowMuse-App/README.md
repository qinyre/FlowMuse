# flow_muse

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web 发布与首屏加载

在 `FlowMuse-App` 下构建后预压缩资源（Python 3.11+ 标准库，无额外依赖）：

```sh
flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
  --dart-define=FLOWMUSE_COLLAB_SERVER_URL=https://api.flowmuse.cloud \
  --dart-define=FLOWMUSE_SHARE_ORIGIN=https://app.flowmuse.cloud
python tool/precompress_web.py build/web
```

将整个 `build/web`（包括 `.gz`）一并发布。Nginx Web 站点采用
`tool/nginx_web_resources.conf` 中的静态资源配置，并在已有 HTTPS listen 上开启 HTTP/2；
保留证书、`/api/`、`/socket.io/` 配置。先 `nginx -t` 再 reload。
预压缩覆盖字体，入口和未版本化资源保留 `no-cache` 校验，防止发布后资源版本混用。

Web 加载提示直接来自 HTML，不依赖 Flutter 或网络字体；显示真实启动阶段，在第一帧出现后移除。
慢加载提供手动重试，不自动刷新或清理浏览器数据。验证入口：

```sh
node --test tool/web_startup_test.mjs
python tool/precompress_web_test.py
```

## Android / 鸿蒙 / Web 应用图标

唯一原图为 `assets/images/flowmuse-app-icon.png`，保留原有绿色笔触、星光和米黄色底色。
Android 使用五档密度的桌面图标，API 26+ 使用独立自适应前景层；Web 使用 favicon、
Apple 主屏幕图标及 192/512px PWA 图标。Maskable 图标单独留边，避免圆形裁切损伤主体。
鸿蒙沿用单层 PNG 图标，同时替换 AppScope 应用图标和 EntryAbility 桌面/启动图标，
保留已有资源名、bundleName 和入口配置；桌面卡片没有独立图片引用，无需改动布局。
浏览器主题色沿用应用日间主题的 `#4F8F84`。此次不更改 iOS/macOS/Windows 或官网仓库。

在仓库根目录使用 Windows 自带 PowerShell/.NET 重新生成或只读检查，无需安装图像工具：

```powershell
powershell -NoProfile -File scripts/Generate-AppIcons.ps1
powershell -NoProfile -File scripts/Generate-AppIcons.ps1 -Check
```

派生 PNG 需入库。更新原图后重新生成，同时递增 `web/index.html`、`web/manifest.json`
中的图标缓存版本。不修改 manifest 的 `start_url`，避免改变已有 PWA 的安装身份。
Android / 鸿蒙需重新打包安装，Web 需发布新构建；不需要修改或重启 Go 后端。

裁切规则参考 [Android 自适应图标](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
与 [Web maskable 图标](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Define_app_icons#support_masking)，
鸿蒙引用优先级见[配置应用图标和名称](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/layered-image)。

本次验证（2026-09-22）：13 张派生图检查通过，Flutter analyze 无问题，全量测试
1697 通过、5 跳过；Android/Web release 构建通过，安装包中的前景像素与 Web 图标文件
均已核对。鸿蒙 HAP 已尝试，但本机 Flutter SDK 的 `packages/flutter_tools/hvigor/`
有 8 个既有删除文件，导致找不到 `flutter-hvigor-plugin`；未擅自恢复 SDK，尚未完成
HAP 构建或鸿蒙实机验证。本次尚未重新安装平板客户端或发布线上 Web。
