import 'package:flutter/services.dart';

import '../models/share_payload.dart';
import '../models/share_result.dart';
import 'share_service.dart';

class OhosShareService implements ShareService {
  const OhosShareService();

  static const _channel = MethodChannel('flow_muse/system_share');

  @override
  Future<ShareResult> share(SharePayload payload) async {
    if (payload is ShareFilePayload && payload.filePath == null) {
      return ShareResult.unavailable;
    }
    try {
      final result = await _channel.invokeMethod<String>('share', {
        'kind': payload.contentType.name,
        'title': payload.title,
        if (payload case ShareTextPayload()) 'text': payload.text,
        if (payload case ShareFilePayload()) ...{
          'filePath': payload.filePath,
          'fileName': payload.fileName,
          'mimeType': payload.mimeType,
        },
      });
      return result == 'completed'
          ? ShareResult.completed
          : result == 'dismissed'
          ? ShareResult.dismissed
          : ShareResult.failed;
    } on MissingPluginException {
      return ShareResult.unavailable;
    } on PlatformException {
      return ShareResult.failed;
    }
  }
}
