import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/text_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/collaboration_focus_alpha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = CollaborationCreator(
    creatorKey: 'user:a',
    displayName: 'A',
    isGuest: false,
  );

  test('分类函数：选中/编辑集合命中全亮，绑定文字父在集合中不隐式全亮（只按元素自身 ID 判断）', () {
    final element = withCreator(
      TextElement(
        id: const ElementId('t1'),
        x: 0,
        y: 0,
        width: 5,
        height: 5,
        text: 'x',
      ),
      owner,
    );
    expect(
      collaborationFocusAlpha(
        element,
        focusedCreatorKey: 'user:b',
        focusHistoricalContent: false,
        highlightedElementIds: {const ElementId('t1')},
      ),
      1.0,
    );
    expect(
      collaborationFocusAlpha(
        element,
        focusedCreatorKey: 'user:b',
        focusHistoricalContent: false,
      ),
      0.22,
    );
  });

  test('无 focus 恒 1.0', () {
    final e = withCreator(
      RectangleElement(
        id: const ElementId('r'),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
      owner,
    );
    expect(
      collaborationFocusAlpha(
        e,
        focusedCreatorKey: null,
        focusHistoricalContent: false,
      ),
      1.0,
    );
  });
}
