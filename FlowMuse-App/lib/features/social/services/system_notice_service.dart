import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/system_notice.dart';
import 'system_notice_stub.dart'
    if (dart.library.io) 'system_notice_native.dart'
    if (dart.library.js_interop) 'system_notice_web.dart'
    as platform;

abstract interface class SystemNoticeService {
  Future<SystemNoticePermission> permission({bool request = false});
  Future<void> initialize(void Function(SystemNoticeTarget) onTap);
  Future<void> show(SystemNoticeMessage notice);
  Future<void> cancel(String tag);
  Future<void> clear();
  void dispose();
}

final systemNoticeServiceProvider = Provider<SystemNoticeService>((ref) {
  final service = platform.createSystemNoticeService();
  ref.onDispose(service.dispose);
  return service;
});

final systemNoticePermissionProvider = FutureProvider(
  (ref) => ref.watch(systemNoticeServiceProvider).permission(),
);
