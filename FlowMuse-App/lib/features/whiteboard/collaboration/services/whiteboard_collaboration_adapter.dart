import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;

import '../models/excalidraw_scene.dart';

class WhiteboardCollaborationAdapter {
  const WhiteboardCollaborationAdapter(this.controller);

  final MarkdrawController controller;

  ExcalidrawScene currentScene() {
    return ExcalidrawScene.fromJson(controller.serializeExcalidrawSceneJson());
  }

  void applyRemoteScene(ExcalidrawScene scene, {bool closeTransientUi = true}) {
    controller.applyRemoteExcalidrawSceneJson(
      scene.toJson(),
      closeTransientUi: closeTransientUi,
    );
  }

  Set<String> selectedElementIds() {
    return controller.editorState.selectedIds.map((id) => id.value).toSet();
  }

  Set<String> protectedElementIds() {
    final ids = selectedElementIds();
    final editingTextId = controller.editingTextElementId;
    if (editingTextId != null) {
      ids.add(editingTextId.value);
    }
    final editingFrameId = controller.editingFrameLabelId;
    if (editingFrameId != null) {
      ids.add(editingFrameId.value);
    }
    return ids;
  }

  Map<String, Object?> pointerPayload(Offset localPosition) {
    final point = controller.toScene(localPosition);
    return {
      'x': point.x,
      'y': point.y,
      'tool': controller.editorState.activeToolType.name,
    };
  }

  Map<String, Object?> visibleSceneBounds(Size canvasSize) {
    final rect = controller.editorState.viewport.visibleRect(canvasSize);
    return {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }
}
