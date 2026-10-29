import 'package:flutter/services.dart';

import '../models/system_notice.dart';
import 'system_notice_service.dart';

SystemNoticeService createSystemNoticeService() => NativeSystemNoticeService();

class NativeSystemNoticeService implements SystemNoticeService {
  static const channel = MethodChannel('flow_muse/system_notice');

  @override
  Future<SystemNoticePermission> permission({bool request = false}) async {
    try {
      final status = await channel.invokeMethod<String>(
        request ? 'requestPermission' : 'permission',
      );
      return SystemNoticePermission.values.firstWhere(
        (p) => p.name == status,
        orElse: () => SystemNoticePermission.unsupported,
      );
    } on MissingPluginException {
      return SystemNoticePermission.unsupported;
    } on PlatformException {
      return SystemNoticePermission.denied;
    }
  }

  @override
  Future<void> initialize(void Function(SystemNoticeTarget) onTap) async {
    void receive(Object? value) {
      final target = SystemNoticeTarget.parse(value);
      if (target != null) onTap(target);
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap') receive(call.arguments);
    });
    try {
      receive(await channel.invokeMethod<String>('takePending'));
    } on MissingPluginException {
      // Older packages and desktop platforms have no native notification channel.
    } on PlatformException {
      // Notification initialization must never block app startup.
    }
  }

  @override
  Future<void> show(SystemNoticeMessage notice) =>
      channel.invokeMethod<void>('show', notice.toJson());
  @override
  Future<void> cancel(String tag) => channel.invokeMethod<void>('cancel', tag);
  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Best effort on packages without this optional channel.
    } on PlatformException {
      // OS notification settings can change while the application is running.
    }
  }

  @override
  void dispose() => channel.setMethodCallHandler(null);
}
