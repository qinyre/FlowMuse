import 'package:flow_muse/features/whiteboard/models/fractional_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates Excalidraw order keys between bounds', () {
    expect(generateKeyBetween(null, null), 'a0');
    expect(generateKeyBetween('a0', null), 'a1');

    final beforeFirst = generateKeyBetween(null, 'a0');
    expect(beforeFirst.compareTo('a0'), lessThan(0));

    final between = generateKeyBetween('a0', 'a1');
    expect(between.compareTo('a0'), greaterThan(0));
    expect(between.compareTo('a1'), lessThan(0));
  });

  test('rejects invalid Excalidraw order keys', () {
    expect(() => generateKeyBetween('a!', null), throwsArgumentError);
    expect(() => generateKeyBetween('zd0032', null), throwsArgumentError);
    expect(() => generateKeyBetween('a1', 'a0'), throwsArgumentError);
  });
}
