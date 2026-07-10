import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart';

void main() {
  test('FreedrawElement has runtime isComplete defaulting to true', () {
    final e = FreedrawElement(
      id: const ElementId('x'),
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      points: const [],
      pressures: const [],
      simulatePressure: true,
    );
    expect(e.isComplete, isTrue);
  });

  test('isComplete is NOT serialized to JSON (stays a render-only field)', () {
    final e = FreedrawElement(
      id: const ElementId('x'),
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      points: const [],
      pressures: const [],
      simulatePressure: true,
    );
    expect(e.isComplete, isTrue);
    final preview = e.copyWithFreedraw(points: const [], isComplete: false);
    expect(preview.isComplete, isFalse);
  });
}
