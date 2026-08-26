import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/document_section.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/markdraw_document.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/serialization/external_export_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = CollaborationCreator(
    creatorKey: 'user:k',
    displayName: '李四',
    isGuest: true,
  );

  test(
    'sanitizeSceneForExternalExport 剥离 owner、保留其他 customData、无 owner 短路',
    () {
      final scene = Scene()
          .addElement(
            withCreator(
              RectangleElement(
                id: const ElementId('a'),
                x: 0,
                y: 0,
                width: 1,
                height: 1,
                customData: const {
                  'flowMuse': {'pageId': 'p1'},
                },
              ),
              creator,
            ),
          )
          .addElement(
            RectangleElement(
              id: const ElementId('b'),
              x: 0,
              y: 0,
              width: 1,
              height: 1,
            ),
          );
      final sanitized = sanitizeSceneForExternalExport(scene);
      expect(
        readCreator(sanitized.getElementById(const ElementId('a'))!),
        isNull,
      );
      expect(
        (sanitized.getElementById(const ElementId('a'))!.customData!['flowMuse']
            as Map)['pageId'],
        'p1',
      );
      expect(
        readCreator(sanitized.getElementById(const ElementId('b'))!),
        isNull,
      );
      // 全场无 owner 时返回同一实例
      final clean = Scene().addElement(
        RectangleElement(
          id: const ElementId('c'),
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      );
      expect(identical(sanitizeSceneForExternalExport(clean), clean), isTrue);
      // version/versionNonce 不被 bump（upsertRemoteElements 语义）
      final withOwner = withCreator(
        RectangleElement(
          id: const ElementId('d'),
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
        creator,
      );
      final scene2 = Scene().addElement(withOwner);
      expect(
        sanitizeSceneForExternalExport(scene2).elements.first.version,
        withOwner.version,
      );
    },
  );

  test('sanitizeDocumentForExternalExport 剥离 doc 内 owner 并保留其余', () {
    final doc = MarkdrawDocument(
      sections: [
        SketchSection([
          withCreator(
            RectangleElement(
              id: const ElementId('e'),
              x: 0,
              y: 0,
              width: 1,
              height: 1,
            ),
            creator,
          ),
          RectangleElement(
            id: const ElementId('f'),
            x: 0,
            y: 0,
            width: 1,
            height: 1,
          ),
        ]),
      ],
    );
    final sanitized = sanitizeDocumentForExternalExport(doc);
    final elements = sanitized.allElements;
    expect(readCreator(elements[0]), isNull);
    expect(readCreator(elements[1]), isNull);
    expect(sanitized.aliases, doc.aliases);
    // 无 owner 短路返回同一实例
    expect(
      identical(sanitizeDocumentForExternalExport(sanitized), sanitized),
      isTrue,
    );
  });
}
