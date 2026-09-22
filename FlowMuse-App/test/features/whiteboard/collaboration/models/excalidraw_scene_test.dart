import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('增量场景共享未变的长笔迹，并隔离新输入及嵌套扩展', () {
    final input = <String, Object?>{
      'id': 'history',
      'points': [
        for (var i = 0; i < 10000; i++) [i, i],
      ],
      'customData': {
        'flowMuse': {
          'unknown': <int>[7],
        },
      },
    };
    final first = ExcalidrawScene(elements: [input], appState: {}, files: {});
    final changed = <String, Object?>{
      'id': 'new',
      'points': <Object?>[
        <int>[1, 2],
      ],
    };
    final next = first.copyWith(elements: [...first.elements, changed]);

    expect(identical(next.elements.first, first.elements.first), isTrue);
    (input['points'] as List).clear();
    (changed['points'] as List).clear();
    expect((next.elements.first['points'] as List).length, 10000);
    expect((next.elements.last['points'] as List).length, 1);
    expect(first.elements.length, 1);
    expect(
      () => (next.elements.first['points'] as List).clear(),
      throwsUnsupportedError,
    );
    final custom = next.elements.first['customData'] as Map;
    final nested = (custom['flowMuse'] as Map)['unknown'] as List;
    expect(nested.single, 7);
    expect(() => nested.clear(), throwsUnsupportedError);
    expect(
      ExcalidrawScene.fromContent(next.toContent()).toJson(),
      next.toJson(),
    );
  });
}
