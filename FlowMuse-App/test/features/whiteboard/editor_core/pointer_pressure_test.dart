import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/ui/pointer_pressure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes pressure for stylus input', () {
    expect(
      reliableStylusPressure(
        kind: PointerDeviceKind.stylus,
        pressure: 0.6,
        pressureMin: 0.2,
        pressureMax: 1.0,
      ),
      closeTo(0.5, 0.0001),
    );
  });

  test('accepts inverted stylus pressure', () {
    expect(
      reliableStylusPressure(
        kind: PointerDeviceKind.invertedStylus,
        pressure: 0.75,
        pressureMin: 0,
        pressureMax: 1,
      ),
      0.75,
    );
  });

  test('ignores synthetic pressure from touch and mouse input', () {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      expect(
        reliableStylusPressure(
          kind: kind,
          pressure: 1,
          pressureMin: 0,
          pressureMax: 1,
        ),
        isNull,
      );
    }
  });

  test('允许各类指针进入工具，触摸平移由控制器开关决定', () {
    expect(shouldDispatchToCreationTool(PointerDeviceKind.stylus), isTrue);
    expect(
      shouldDispatchToCreationTool(PointerDeviceKind.invertedStylus),
      isTrue,
    );
    expect(shouldDispatchToCreationTool(PointerDeviceKind.mouse), isTrue);
    expect(shouldDispatchToCreationTool(PointerDeviceKind.touch), isTrue);
  });
}
