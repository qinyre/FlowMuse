import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../models/ai_agent_models.dart';
import '../models/ai_visual_attachment.dart';
import 'visual_attachment_capture.dart';

AiAgentSource readAiAgentSource(
  MarkdrawController controller,
  AiAgentScope scope,
) {
  final scene = controller.currentScene;
  final layout = controller.layout;
  final visible = controller.editorState.viewport.visibleRect(
    controller.canvasSize,
  );
  final page = scope == AiAgentScope.page
      ? controller.pageForVisibleRect(visible)
      : null;
  if (scope == AiAgentScope.page &&
      (page == null || !page.bounds.overlaps(visible))) {
    throw StateError('当前视图没有页面，请滚动到要询问的页面');
  }

  int pageIndex(Element element) {
    final index = layout.pages.indexWhere((page) => page.id == element.pageId);
    if (index >= 0) return index;
    final center = Offset(
      element.x + element.width / 2,
      element.y + element.height / 2,
    );
    return layout.pages.indexWhere((page) => page.bounds.contains(center));
  }

  final selected = <ElementId, Element>{};
  if (scope == AiAgentScope.selection) {
    for (final element in controller.selectedElements) {
      if (element.isDeleted) continue;
      selected[element.id] = element;
      final bound = scene.findBoundText(element.id);
      if (bound != null && !bound.isDeleted) selected[bound.id] = bound;
    }
  }
  final elements = switch (scope) {
    AiAgentScope.selection => selected.values,
    AiAgentScope.page => [
      for (final element in scene.elements)
        if (!element.isDeleted && pageIndex(element) == page!.index) element,
    ],
    AiAgentScope.note => scene.activeElements,
    AiAgentScope.none => <Element>[],
  };
  final textItems =
      [
        for (final element in elements.whereType<TextElement>())
          AiNoteText(
            id: element.id.value,
            text: element.text,
            pageIndex: pageIndex(element),
            x: element.x,
            y: element.y,
          ),
      ]..sort((a, b) {
        final pageOrder = a.pageIndex!.compareTo(b.pageIndex!);
        if (pageOrder != 0) return pageOrder;
        final yOrder = a.y!.compareTo(b.y!);
        return yOrder != 0 ? yOrder : a.x!.compareTo(b.x!);
      });
  final text = AiNoteContext.fromTexts(textItems);
  final hasVisual = elements.any(
    (element) => element is! TextElement && !element.isCanvasPage,
  );
  final wantsImage =
      hasVisual &&
      (scope == AiAgentScope.selection || scope == AiAgentScope.page);
  final isPdf =
      page != null && elements.any((element) => element.isPdfBackground);
  final label = switch (scope) {
    AiAgentScope.selection => wantsImage ? '当前选区（含画布图像）' : '当前文字选区',
    AiAgentScope.page =>
      isPdf ? 'PDF 第 ${page.index + 1} 页（含批注）' : '第 ${page!.index + 1} 页',
    AiAgentScope.note => '整篇笔记（仅文字）',
    AiAgentScope.none => '未添加笔记来源',
  };
  if (text.texts.isEmpty &&
      !wantsImage &&
      (scope == AiAgentScope.selection || scope == AiAgentScope.page)) {
    throw StateError('此范围没有可供提问的内容');
  }

  Future<AiVisualAttachment?> Function()? capture;
  if (wantsImage) {
    var snapshot = Scene().upsertRemoteElements(elements);
    final fileIds = {
      for (final image in elements.whereType<ImageElement>()) image.fileId,
    };
    for (final id in fileIds) {
      final file = scene.files[id];
      if (file != null) snapshot = snapshot.addFile(id, file);
    }
    final selection = page == null
        ? ExportBounds.compute(snapshot, padding: 8)
        : null;
    final bounds =
        page?.bounds ??
        (selection == null
            ? null
            : Rect.fromLTWH(
                selection.left,
                selection.top,
                selection.size.width,
                selection.size.height,
              ));
    capture = () {
      if (controller.isDisposed || !identical(controller.layout, layout)) {
        throw StateError('画布布局已变化，请重新选择来源');
      }
      if (bounds == null) throw StateError('无法获取截图范围，请尝试手动框选');
      return captureAiRegion(
        controller,
        bounds,
        scene: snapshot,
        sourceLabel: label,
        kind: isPdf
            ? AiVisualAttachmentKind.pdfPage
            : AiVisualAttachmentKind.selection,
      );
    };
  }
  return (
    context: (
      noteTitle: scope == AiAgentScope.none
          ? ''
          : controller.documentName ?? '未命名笔记',
      texts: text.texts,
      truncated: text.truncated,
      label: label,
      hasSelection: scope == AiAgentScope.selection,
    ),
    capture: capture,
  );
}
