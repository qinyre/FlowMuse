/// High-level file I/O handler that wires file_picker, platform I/O,
/// and [MarkdrawController] methods together.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// Encapsulates all file-picker + platform-I/O + controller interactions.
///
/// Create one per editor and pass its methods as callbacks to
/// [MarkdrawEditor].
class MarkdrawFileHandler {
  MarkdrawFileHandler({required this.controller});

  final MarkdrawController controller;

  /// The native file path of the currently-open file (null on web).
  String? currentFilePath;

  /// Saves to [currentFilePath], or falls through to [saveAs].
  Future<void> save() async {
    if (!kIsWeb && currentFilePath != null) {
      await writeStringToFile(currentFilePath!, controller.serializeScene());
    } else {
      await saveAs();
    }
  }

  /// Shows a save dialog (or blob download on web) and writes the scene.
  Future<void> saveAs() async {
    final content = controller.serializeScene();
    if (kIsWeb) {
      downloadFile('drawing.markdraw', content);
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存绘图',
        fileName: 'drawing.markdraw',
        type: FileType.custom,
        allowedExtensions: ['markdraw', 'excalidraw'],
      );
      if (path != null) {
        await writeStringToFile(path, content);
        currentFilePath = path;
      }
    }
  }

  /// Shows a file picker and loads the selected drawing.
  Future<void> open() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '打开绘图',
      type: FileType.any,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.single;
    final ext = file.name.split('.').last.toLowerCase();
    if (!{'markdraw', 'excalidraw', 'json'}.contains(ext)) return;

    final content = file.bytes != null
        ? utf8.decode(file.bytes!)
        : !kIsWeb
        ? await readStringFromFile(file.path!)
        : null;
    if (content == null) return;

    controller.loadFromContent(content, file.name);
    currentFilePath = kIsWeb ? null : file.path;
  }

  /// Exports the scene as PNG bytes via a save dialog (or blob download).
  Future<void> exportPng() async {
    final bytes = await controller.exportPng();
    if (bytes == null) return;

    if (kIsWeb) {
      downloadBytes('drawing.png', bytes, mimeType: 'image/png');
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 PNG',
        fileName: 'drawing.png',
        type: FileType.any,
      );
      if (path != null) await writeBytesToFile(path, bytes);
    }
  }

  /// Exports the scene as SVG via a save dialog (or blob download).
  Future<void> exportSvg() async {
    final svg = controller.exportSvg();
    if (svg.isEmpty) return;

    if (kIsWeb) {
      downloadFile('drawing.svg', svg);
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 SVG',
        fileName: 'drawing.svg',
        type: FileType.any,
      );
      if (path != null) await writeStringToFile(path, svg);
    }
  }

  /// Shows an image picker and imports the selected image.
  ///
  /// [context] is used to determine screen size for centering.
  Future<void> importImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入图片',
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.single;
    if (file.bytes == null) return;

    if (!context.mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final screenSize = renderBox?.size ?? const Size(800, 600);
    await controller.importImage(file.bytes!, file.name, screenSize);
  }

  Future<void> importPdfSource(
    PdfImportSource source,
    Size canvasSize, {
    bool asBackground = false,
  }) async {
    final importer = PdfImporter(renderer: createDefaultPdfPageRenderer());
    await importer.importPdf(
      source: source,
      controller: controller,
      canvasSize: canvasSize,
      asBackground: asBackground,
    );
  }

  /// Shows a file picker and imports a library file.
  Future<void> importLibrary() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入素材库',
      type: FileType.custom,
      allowedExtensions: ['excalidrawlib', 'markdrawlib'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final content = kIsWeb && picked.bytes != null
        ? utf8.decode(picked.bytes!)
        : picked.path != null
        ? await readStringFromFile(picked.path!)
        : null;
    if (content == null) return;

    controller.importLibraryFromContent(content, picked.name);
  }

  /// Exports the current library via a save dialog (or blob download).
  Future<void> exportLibrary() async {
    if (controller.libraryItems.isEmpty) return;
    final content = controller.exportLibraryContent();

    if (kIsWeb) {
      downloadFile('library.excalidrawlib', content);
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出素材库',
        fileName: 'library.excalidrawlib',
        allowedExtensions: ['excalidrawlib', 'markdrawlib'],
        type: FileType.custom,
      );
      if (path != null) {
        final format = DocumentService.detectFormat(path);
        final output = controller.exportLibraryContent(format: format);
        await writeStringToFile(path, output);
      }
    }
  }
}
