import '../models/system_notice.dart';
import 'system_notice_service.dart';

SystemNoticeService createSystemNoticeService() =>
    UnsupportedSystemNoticeService();

class UnsupportedSystemNoticeService implements SystemNoticeService {
  @override
  Future<SystemNoticePermission> permission({bool request = false}) async =>
      SystemNoticePermission.unsupported;
  @override
  Future<void> initialize(void Function(SystemNoticeTarget) onTap) async {}
  @override
  Future<void> show(SystemNoticeMessage notice) async {}
  @override
  Future<void> cancel(String tag) async {}
  @override
  Future<void> clear() async {}
  @override
  void dispose() {}
}
