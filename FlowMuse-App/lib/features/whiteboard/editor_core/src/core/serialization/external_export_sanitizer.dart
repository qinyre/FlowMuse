import '../elements/collaboration_element_owner.dart';
import '../scene/scene_exports.dart';
import 'document_section.dart';
import 'markdraw_document.dart';

/// 返回剥离 `customData.flowMuse.collaborationOwner` 的 Scene 不可变拷贝。
/// 其他 customData / flowMuse 键全部保留。用于所有外部导出出口；
/// 内部持久化与协作链路禁止调用。
Scene sanitizeSceneForExternalExport(Scene scene) {
  var hasOwner = false;
  for (final element in scene.elements) {
    if (readCreator(element) != null) {
      hasOwner = true;
      break;
    }
  }
  if (!hasOwner) return scene;
  return scene.upsertRemoteElements([
    for (final element in scene.elements) withoutCreator(element),
  ]);
}

/// MarkdrawDocument 级别的同一净化（避免 Scene 往返重建 alias/索引）。
MarkdrawDocument sanitizeDocumentForExternalExport(MarkdrawDocument doc) {
  var hasOwner = false;
  for (final element in doc.allElements) {
    if (readCreator(element) != null) {
      hasOwner = true;
      break;
    }
  }
  if (!hasOwner) return doc;
  final sections = <DocumentSection>[
    for (final section in doc.sections)
      if (section is SketchSection)
        SketchSection([
          for (final element in section.elements) withoutCreator(element),
        ])
      else
        section,
  ];
  return doc.copyWith(sections: sections);
}
