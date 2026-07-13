import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide Element, SelectionOverlay, TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart'
    as editor_core;

import '../models/excalidraw_scene.dart';

class WhiteboardCollaborationAdapter {
  const WhiteboardCollaborationAdapter(this.controller);

  final MarkdrawController controller;

  ExcalidrawScene currentScene({bool includeDeleted = true}) {
    return ExcalidrawScene.fromJson(
      controller.serializeExcalidrawSceneJson(includeDeleted: includeDeleted),
    );
  }

  List<Map<String, Object?>> serializeElements(
    Iterable<editor_core.Element> elements,
  ) {
    return [
      for (final element in elements)
        Map<String, Object?>.from(ExcalidrawJsonCodec.elementToJson(element)),
    ];
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
