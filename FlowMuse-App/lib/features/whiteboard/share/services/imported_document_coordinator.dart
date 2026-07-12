import 'dart:convert';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../models/external_document_request.dart';

class ImportedDocumentPreview {
  const ImportedDocumentPreview({
    required this.fileName,
    required this.content,
    required this.warnings,
  });

  final String fileName;
  final String content;
  final List<String> warnings;
}

class ImportedDocumentCoordinator {
  ImportedDocumentPreview preview(ExternalDocumentRequest request) {
    final name = request.fileName.toLowerCase();
    if (!name.endsWith('.markdraw') && !name.endsWith('.excalidraw')) {
      throw ArgumentError.value(request.fileName, 'fileName', '不支持的文件格式');
    }
    final content = utf8.decode(request.bytes);
    final result = name.endsWith('.markdraw')
        ? DocumentParser.parse(content)
        : ExcalidrawJsonCodec.parse(content);
    return ImportedDocumentPreview(
      fileName: request.fileName,
      content: ExcalidrawJsonCodec.serialize(result.value),
      warnings: result.warnings.map((warning) => warning.message).toList(),
    );
  }
}
