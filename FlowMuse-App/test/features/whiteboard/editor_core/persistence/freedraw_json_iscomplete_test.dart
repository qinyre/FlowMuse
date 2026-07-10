import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/freedraw_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/serialization.dart';

void main() {
  test('isComplete is NOT serialized', () {
    final e = FreedrawElement(
      id: const ElementId('a'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      points: const [Point(0, 0), Point(1, 1)],
      pressures: const [0.5, 0.6],
      simulatePressure: false,
    );
    final json = ExcalidrawJsonCodec.elementToJson(e);
    expect(json.containsKey('isComplete'), isFalse);
  });

  test('JSON round-trip preserves points/pressures, isComplete stays default true', () {
    final e = FreedrawElement(
      id: const ElementId('a'),
      x: 1,
      y: 2,
      width: 10,
      height: 10,
      points: const [Point(0, 0), Point(3, 4)],
      pressures: const [0.4, 0.5],
      simulatePressure: false,
    );
    final json = ExcalidrawJsonCodec.elementToJson(e);
    // parseElement returns Element?; type asserted to FreedrawElement
    final back = ExcalidrawJsonCodec.parseElement(
      json,
      json['type'] as String,
      0,
      <ParseWarning>[],
    ) as FreedrawElement;
    expect(back.points, e.points);
    expect(back.pressures, e.pressures);
    expect(back.isComplete, isTrue);
  });

  test('copyWith preserves fields not overridden (latent bug fix)', () {
    final e = FreedrawElement(
      id: const ElementId('a'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      points: const [Point(0, 0)],
      pressures: const [0.5],
      simulatePressure: false,
    );
    final moved = e.copyWith(x: 10); // only change x
    expect(moved.points, e.points);
    expect(moved.pressures, e.pressures);
    expect(moved.simulatePressure, e.simulatePressure);
  });
}
