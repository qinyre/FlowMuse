import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';

void main() {
  test('构建默认值关闭 Live Ink V2', () {
    expect(liveInkFlags.liveInkV2, isFalse);
  });

  test('effective flag 严格要求 layered、live 和 server v2', () {
    for (final testCase in [
      (layered: false, live: false, version: 0, effective: false),
      (layered: true, live: false, version: 2, effective: false),
      (layered: false, live: true, version: 2, effective: false),
      (layered: true, live: true, version: 1, effective: false),
      (layered: true, live: true, version: 2, effective: true),
    ]) {
      final flags = LiveInkFlags(
        layeredWetInk: testCase.layered,
        liveInkV2: testCase.live,
      );
      expect(flags.effectiveFor(testCase.version), testCase.effective);
    }
  });
}
