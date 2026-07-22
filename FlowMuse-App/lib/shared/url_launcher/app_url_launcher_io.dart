import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 原生(非 Web)平台实现。
///
/// 鸿蒙:走项目自有的 [UrlLauncherChannel](通道名 `flow_muse/url_launcher`),
///      因为 url_launcher 上游未提供 OHOS 实现,直接调 launchUrl 会抛
///      MissingPluginException。原生侧用 startAbility + Want 拉起系统
///      浏览器/邮件应用。
/// 其他原生平台(Android/iOS/桌面):走 url_launcher 包。
class AppUrlLauncher {
  static const _ohosChannel = MethodChannel('flow_muse/url_launcher');

  /// 拉起外部应用打开 [uri]:
  /// - http/https:在系统浏览器中打开
  /// - mailto:在系统邮件应用中打开(可带 subject/body 等参数)
  ///
  /// [external] 仅对非 mailto 的 http(s) 链接生效:
  /// true=强制外部浏览器, false=允许应用内 WebView(默认行为)。
  static Future<bool> launch(Uri uri, {bool external = true}) async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux) {
      return _launchViaPackage(uri, external: external);
    }
    // 鸿蒙及其他:走原生 channel。OHOS 之外的平台会抛
    // MissingPluginException(channel 没注册),返回 false。
    return _launchViaOhosChannel(uri);
  }

  static Future<bool> _launchViaPackage(Uri uri, {bool external = true}) async {
    try {
      final isMailto = uri.scheme == 'mailto';
      final mode = external && !isMailto
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault;
      return await launchUrl(uri, mode: mode);
    } on PlatformException catch (e) {
      debugPrint('[AppUrlLauncher] url_launcher PlatformException: $e');
      return false;
    }
  }

  static Future<bool> _launchViaOhosChannel(Uri uri) async {
    try {
      final ok = await _ohosChannel.invokeMethod<bool>(
        'launchUrl',
        {'uri': uri.toString()},
      );
      return ok ?? false;
    } on MissingPluginException catch (e) {
      debugPrint('[AppUrlLauncher] OHOS channel not registered: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[AppUrlLauncher] OHOS channel PlatformException: $e');
      return false;
    }
  }
}
