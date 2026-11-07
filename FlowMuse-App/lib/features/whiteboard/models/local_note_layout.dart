import '../../library/models/note_item.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart';

CanvasLayout layoutForLocalNote(NoteItem? note) {
  final template = switch (note?.pageTemplate) {
    PageTemplate.narrowLine => CanvasPageTemplate.narrowLine,
    PageTemplate.wideLine => CanvasPageTemplate.wideLine,
    PageTemplate.grid => CanvasPageTemplate.grid,
    PageTemplate.dotGrid => CanvasPageTemplate.dotGrid,
    PageTemplate.tianGrid => CanvasPageTemplate.tianGrid,
    PageTemplate.miGrid => CanvasPageTemplate.miGrid,
    PageTemplate.narrowVerticalLine => CanvasPageTemplate.narrowVerticalLine,
    PageTemplate.wideVerticalLine => CanvasPageTemplate.wideVerticalLine,
    PageTemplate.fourLineGrid => CanvasPageTemplate.fourLineGrid,
    PageTemplate.ancientBook => CanvasPageTemplate.ancientBook,
    PageTemplate.blank || null => CanvasPageTemplate.blank,
  };
  return CanvasLayout(
    type: note?.noteType == NoteType.unbounded
        ? CanvasLayoutType.unbounded
        : CanvasLayoutType.paged,
    template: template,
    pageFlow: note?.pageFlow == PageFlow.rightToLeft
        ? CanvasPageFlow.rightToLeft
        : CanvasPageFlow.topToBottom,
  );
}
