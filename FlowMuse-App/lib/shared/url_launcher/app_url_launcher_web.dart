import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web 平台实现:直接走 url_launcher 包(底层是浏览器原生能力)。
class AppUrlLauncher {
  static Future<bool> launch(Uri uri, {bool external = true}) async {
    try {
      final isMailto = uri.scheme == 'mailto';
      // Web 上 mailto 走默认模式让浏览器打开邮件客户端;
      // http(s) 在 external=true 时强制新标签页打开。
      final mode = external && !isMailto
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault;
      return await launchUrl(uri, mode: mode);
    } on PlatformException catch (e) {
      debugPrint('[AppUrlLauncher] web PlatformException: $e');
      return false;
    }
  }
}
