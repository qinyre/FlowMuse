import 'package:flutter/services.dart';

import '../models/external_document_request.dart';

class ExternalDocumentChannelOhos {
  const ExternalDocumentChannelOhos();

  static const _channel = MethodChannel('flow_muse/external_document');

  Future<ExternalDocumentRequest?> takeNext() async {
    Map<String, Object?>? value;
    try {
      value = await _channel.invokeMapMethod<String, Object?>('takeNext');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (value == null) return null;
    final name = value['name'];
    final bytes = value['bytes'];
    if (name is! String || bytes is! Uint8List) return null;
    return ExternalDocumentRequest(fileName: name, bytes: bytes);
  }

  /// 监听 ArkTS 端入队通知。app 在后台收到 onNewWant 时，
  /// ArkTS 端入队后会通过此回调主动通知 Flutter 端消费。
  void setEnqueueListener(VoidCallback onEnqueued) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDocumentEnqueued') {
        onEnqueued();
      }
      return null;
    });
  }
}
