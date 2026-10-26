import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';

void main() {
  test('构建默认开启分层湿墨和 Live Ink V2，旧服务端仍兼容', () {
    expect(liveInkFlags.layeredWetInk, isTrue);
    expect(liveInkFlags.liveInkV2, isTrue);
    expect(liveInkFlags.effectiveFor(1), isFalse);
    expect(liveInkFlags.effectiveFor(2), isTrue);
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
