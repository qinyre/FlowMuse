import 'package:flow_muse/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('文字编辑对象随 presence 同步，结束编辑清除瞬时标识', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final adapter = WhiteboardCollaborationAdapter(controller);
    final text = TextElement(
      id: const ElementId('editing-text'),
      x: 100,
      y: 100,
      width: 120,
      height: 40,
      text: '共同编辑',
      // Presence assertions must not depend on downloading a font.
      fontFamily: 'Excalifont',
    );
    controller.applyResult(AddElementResult(text), applyDefaultStyle: false);
    controller.startTextEditingExisting(text);
    expect(adapter.selectedElementIds(), contains('editing-text'));
    expect(
      adapter.pointerPayload(Offset.zero)['editingElementId'],
      'editing-text',
    );
    controller.commitTextEditing();
    expect(
      adapter.pointerPayload(Offset.zero).containsKey('editingElementId'),
      isFalse,
    );
    expect(
      controller.serializeExcalidrawSceneJson().toString().contains(
        'editingElementId',
      ),
      isFalse,
    );
  });
}
