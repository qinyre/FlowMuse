import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';

void main() {
  test('分层湿墨开关默认关闭', () {
    expect(writingFeatureFlags.layeredWetInk, isFalse);
  });

  test('effective value 可作为只读依赖向下传递', () {
    const enabled = WritingFeatureFlags(layeredWetInk: true);
    expect(enabled.layeredWetInk, isTrue);
  });
}
