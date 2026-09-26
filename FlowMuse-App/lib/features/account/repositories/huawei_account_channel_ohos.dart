import 'package:flutter/services.dart';

/// Capability probing keeps platform checks out of the account UI.
class HuaweiAccountChannel {
  static const _channel = MethodChannel('flow_muse/huawei_account');

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// null means the user cancelled; no business session is changed.
  Future<String?> authorize() async {
    try {
      final code = await _channel.invokeMethod<String>('login');
      if (code != null && code.isEmpty) {
        throw StateError('未取得华为登录凭证，请重试');
      }
      return code;
    } on MissingPluginException {
      throw StateError('此设备暂不支持华为登录，请使用邮箱登录');
    } on PlatformException catch (error) {
      throw StateError(switch (error.code) {
        'network' => '无法连接华为账号服务，请检查网络后重试',
        'busy' => '华为登录正在进行，请稍候',
        'authorization_failed' when error.details == 1001500001 =>
          '华为登录配置或应用签名验证失败，请联系开发者检查 Client ID 和证书指纹',
        'authorization_failed' when error.details == 1001502001 =>
          '请先在设备上登录华为账号，然后重试',
        'authorization_failed' when error.details == 12300001 =>
          '华为账号服务暂不可用，请稍后重试',
        'authorization_failed' when error.details is int =>
          '华为登录失败（错误码 ${error.details}），请重试或联系开发者',
        _ => '华为登录未完成，请重试或使用邮箱登录',
      });
    }
  }
}
