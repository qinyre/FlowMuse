import 'dart:convert';
import 'dart:js_interop';

import '../models/system_notice.dart';
import 'system_notice_service.dart';

@JS('flowMuseSystemNotice')
external _NoticeBridge? get _bridge;

extension type _NoticeBridge(JSObject _) implements JSObject {
  external JSPromise<JSString> permission(JSBoolean request);
  external JSPromise<JSAny?> initialize(JSFunction callback);
  external JSPromise<JSAny?> show(JSString payload);
  external JSPromise<JSAny?> cancel(JSString tag);
  external JSPromise<JSAny?> clear();
  external void dispose();
}

SystemNoticeService createSystemNoticeService() => WebSystemNoticeService();

class WebSystemNoticeService implements SystemNoticeService {
  @override
  Future<SystemNoticePermission> permission({bool request = false}) async {
    final bridge = _bridge;
    if (bridge == null) return SystemNoticePermission.unsupported;
    final result = (await bridge.permission(request.toJS).toDart).toDart;
    return SystemNoticePermission.values.firstWhere(
      (p) => p.name == result,
      orElse: () => SystemNoticePermission.unsupported,
    );
  }

  @override
  Future<void> initialize(void Function(SystemNoticeTarget) onTap) async {
    final bridge = _bridge;
    if (bridge == null) return;
    await bridge
        .initialize(
          ((JSString raw) {
            final target = SystemNoticeTarget.parse(raw.toDart);
            if (target != null) onTap(target);
          }).toJS,
        )
        .toDart;
  }

  @override
  Future<void> show(SystemNoticeMessage notice) async =>
      await _bridge?.show(jsonEncode(notice.toJson()).toJS).toDart;
  @override
  Future<void> cancel(String tag) async =>
      await _bridge?.cancel(tag.toJS).toDart;
  @override
  Future<void> clear() async => await _bridge?.clear().toDart;
  @override
  void dispose() => _bridge?.dispose();
}
