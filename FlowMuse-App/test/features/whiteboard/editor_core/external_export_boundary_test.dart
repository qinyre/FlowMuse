import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/element_id.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/rectangle_element.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/io/document_format.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/export/png_metadata.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/markdraw_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // PNG 栅格化需要

  const creator = CollaborationCreator(
    creatorKey: 'user:z',
    displayName: '赵六',
    isGuest: false,
  );

  MarkdrawController buildControllerWithOwnedElement() {
    final controller = MarkdrawController();
    controller.applyResult(
      AddElementResult(
        withCreator(
          RectangleElement(
            id: const ElementId('ext-1'),
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            customData: const {
              'flowMuse': {'pageId': 'p1', 'brushType': 'fountainPen'},
            },
          ),
          creator,
        ),
      ),
    );
    return controller;
  }

  test(
    'serializeSceneForExternalExport(excralidraw) 产物无 collaborationOwner，其他 flowMuse 键保留',
    () {
      final controller = buildControllerWithOwnedElement();
      final json = controller.serializeSceneForExternalExport(
        format: DocumentFormat.excalidraw,
      );
      expect(json.contains('collaborationOwner'), isFalse);
      expect(json.contains('pageId'), isTrue);
      expect(json.contains('brushType'), isTrue);
      controller.dispose();
    },
  );

  test('内部 serializeScene(excralidraw) 仍保留 owner', () {
    final controller = buildControllerWithOwnedElement();
    final json = controller.serializeScene(format: DocumentFormat.excalidraw);
    expect(json.contains('collaborationOwner'), isTrue);
    controller.dispose();
  });

  test(
    '最终产物断言：exportSvg / exportLibraryContent / exportPng 嵌入数据均无 owner',
    () async {
      final controller = buildControllerWithOwnedElement();

      // SVG 最终字符串
      final svg = controller.exportSvg(selectedOnly: false);
      expect(svg.contains('collaborationOwner'), isFalse);

      // Library 最终产物（先生成一个 item 再导出）
      controller.addToLibrary();
      final library = controller.exportLibraryContent();
      expect(library.contains('collaborationOwner'), isFalse);

      // PNG tEXt 嵌入数据（最终字节内 base64 解码后断言）
      final png = await controller.exportPng(
        selectedOnly: false,
        embedMarkdraw: true,
      );
      expect(png, isNotNull);
      final embedded = PngMetadata.extractTextChunk(png!, 'markdraw');
      expect(embedded, isNotNull);
      final decoded = utf8.decode(base64Decode(embedded!));
      expect(decoded.contains('collaborationOwner'), isFalse);
      controller.dispose();
    },
  );

  test('loadFromContent(isExternalImport: true) 剥离不可信 owner；默认 false 保留', () {
    final controller = buildControllerWithOwnedElement();
    final withOwner = controller.serializeScene(
      format: DocumentFormat.excalidraw,
    );
    controller.dispose();

    final external = MarkdrawController();
    external.loadFromContent(withOwner, 'a.excalidraw', isExternalImport: true);
    expect(readCreator(external.editorState.scene.elements.single), isNull);
    expect(
      (external.editorState.scene.elements.single.customData!['flowMuse']
          as Map)['pageId'],
      'p1',
    );
    external.dispose();

    final internal = MarkdrawController();
    internal.loadFromContent(withOwner, 'a.excalidraw');
    expect(
      readCreator(internal.editorState.scene.elements.single)?.creatorKey,
      'user:z',
    );
    internal.dispose();
  });

  test('外部出口调用点审计：file handler 与 share 只走外部 API', () {
    final handler = File(
      'lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart',
    ).readAsStringSync();
    expect(handler.contains('serializeSceneForExternalExport'), isTrue);
    // 迁移后内部 serializeScene( 调用应为 0 次（serializeSceneForExternalExport(
    // 中 serializeScene 后跟 F 不是 (，不会被该正则误匹配）
    expect(
      RegExp(r'serializeScene\(').allMatches(handler),
      isEmpty,
      reason: 'file handler 不得再直接调用内部 serializeScene',
    );

    final share = File(
      'lib/features/whiteboard/share/services/share_export_coordinator.dart',
    ).readAsStringSync();
    expect(share.contains('serializeSceneForExternalExport'), isTrue);
    expect(RegExp(r'serializeScene\(').allMatches(share), isEmpty);
  });

  test('内部链路仍保留 owner：本地笔记保存不走外部 API', () {
    final page = File(
      'lib/features/whiteboard/views/whiteboard_page.dart',
    ).readAsStringSync();
    // 四处本地持久化调用是多行写法，用宽松正则匹配
    expect(
      RegExp(
        r'serializeScene\(\s*format:\s*DocumentFormat\.excalidraw',
      ).hasMatch(page),
      isTrue,
      reason: '本地持久化必须继续使用内部 serializeScene',
    );
  });

  test('ShareExportCoordinator 产物门禁：prepareDocument 只走外部 API（源码断言）', () {
    final share = File(
      'lib/features/whiteboard/share/services/share_export_coordinator.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'serializeScene\(').allMatches(share),
      isEmpty,
      reason:
          'share 的 markdraw/excalidraw 产物经 serializeSceneForExternalExport，最终字节由上一用例的 controller 级断言覆盖',
    );
  });
}
