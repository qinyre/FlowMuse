import 'package:flow_muse/features/whiteboard/models/whiteboard_element.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WhiteboardElement rectangle() {
    return WhiteboardElement.rectangle(
      id: 'rect-1',
      x: 10,
      y: 20,
      width: 30,
      height: 40,
      fractionalIndex: 'a0',
      version: 3,
      versionNonce: 9,
      updatedAt: 1000,
    );
  }

  test('does not bump version when Excalidraw-style update is unchanged', () {
    final element = rectangle();

    final updated = element.newWith(x: 10, y: 20);

    expect(identical(updated, element), isTrue);
    expect(updated.version, 3);
    expect(updated.versionNonce, 9);
    expect(updated.updatedAt, 1000);
  });

  test('bumps version nonce and updated timestamp when a field changes', () {
    final element = rectangle();

    final updated = element.newWith(x: 12, versionNonce: 77, updatedAt: 2000);

    expect(updated.x, 12);
    expect(updated.version, 4);
    expect(updated.versionNonce, 77);
    expect(updated.updatedAt, 2000);
  });

  test('uses explicit version when an update provides one', () {
    final element = rectangle();

    final updated = element.newWith(
      width: 64,
      version: 20,
      versionNonce: 88,
      updatedAt: 3000,
    );

    expect(updated.width, 64);
    expect(updated.version, 20);
    expect(updated.versionNonce, 88);
    expect(updated.updatedAt, 3000);
  });
}
