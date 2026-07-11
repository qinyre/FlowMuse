import 'package:flow_muse/features/whiteboard/share/models/share_result.dart';
import 'package:flow_muse/features/whiteboard/share/services/share_service_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

void main() {
  test('映射系统分享的结果状态', () {
    expect(
      mapNativeShareResult(
        const share_plus.ShareResult(
          'ok',
          share_plus.ShareResultStatus.success,
        ),
      ),
      ShareResult.completed,
    );
    expect(
      mapNativeShareResult(
        const share_plus.ShareResult(
          '',
          share_plus.ShareResultStatus.dismissed,
        ),
      ),
      ShareResult.dismissed,
    );
    expect(
      mapNativeShareResult(
        const share_plus.ShareResult(
          '',
          share_plus.ShareResultStatus.unavailable,
        ),
      ),
      ShareResult.unavailable,
    );
  });
}
