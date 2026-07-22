/// 默认实现:不支持任何平台时返回 false。
///
/// 在 Flutter Web 之外的纯 Dart VM(单元测试)或未知平台上,导出此 stub。
/// 实际平台通过条件导入覆盖。
class AppUrlLauncher {
  static Future<bool> launch(Uri uri, {bool external = true}) async => false;
}
