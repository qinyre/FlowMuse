// 条件导入:
// - Web 平台走 url_launcher 包(浏览器原生能力)
// - 非 Web 平台(含 OHOS/Android/iOS/桌面)走 IO 版本,
//   IO 版本内部会先尝试鸿蒙原生 channel,失败再降级到 url_launcher 包。
//
// 每个条件分支文件都导出一个同名的 AppUrlLauncher 类,平台行为不同。
export 'app_url_launcher_stub.dart'
    if (dart.library.html) 'app_url_launcher_web.dart'
    if (dart.library.io) 'app_url_launcher_io.dart';
