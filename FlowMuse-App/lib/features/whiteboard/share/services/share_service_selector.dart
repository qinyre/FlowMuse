import 'package:flutter/foundation.dart';

import 'share_service.dart';
import 'share_service_native.dart';
import 'share_service_ohos.dart';

ShareService createShareService() {
  return defaultTargetPlatform == TargetPlatform.ohos
      ? const OhosShareService()
      : const NativeShareService();
}
