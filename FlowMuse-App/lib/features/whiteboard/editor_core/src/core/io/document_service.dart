import '../library/library.dart';
import '../serialization/serialization.dart';
import 'document_format.dart';

/// Platform-agnostic service for loading and saving markdraw documents.
///
/// Takes file read/write functions as parameters (Dependency Inversion),
/// so it can work with any platform's file system without importing dart:io.
class DocumentService {
  final Future<String> Function(String path) readFile;
  final Future<void> Function(String path, String content) writeFile;

  const DocumentService({required this.readFile, required this.writeFile});

  /// Detects the document format from a file path's extension.
  ///
  /// Supported extensions:
  /// - `.markdraw` → [DocumentFormat.markdraw]
  /// - `.excalidraw`, `.json` → [DocumentFormat.excalidraw]
  /// - `.markdrawlib` → [DocumentFormat.markdrawLibrary]
  /// - `.excalidrawlib` → [DocumentFormat.excalidrawLibrary]
  ///
  /// Throws [ArgumentError] for unrecognized extensions.
  static DocumentFormat detectFormat(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) {
      throw ArgumentError('No file extension found in path: $path');
    }
    final ext = path.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'markdraw':
        return DocumentFormat.markdraw;
      case 'excalidraw':
      case 'json':
        return DocumentFormat.excalidraw;
      case 'markdrawlib':
        return DocumentFormat.markdrawLibrary;
      case 'excalidrawlib':
        return DocumentFormat.excalidrawLibrary;
      default:
        throw ArgumentError('Unsupported file extension: .$ext');
    }
  }

  /// Reads a file, detects its format, and parses it into a [MarkdrawDocument].
  ///
  /// Format is detected from the file extension. Throws if the file cannot
  /// be read or has an unsupported extension.
  Future<ParseResult<MarkdrawDocument>> load(String path) async {
    final format = detectFormat(path);
    final content = await readFile(path);
    switch (format) {
      case DocumentFormat.markdraw:
        return DocumentParser.parse(content);
      case DocumentFormat.excalidraw:
        return ExcalidrawJsonCodec.parse(content);
      case DocumentFormat.markdrawLibrary:
      case DocumentFormat.excalidrawLibrary:
        throw ArgumentError('Use loadLibrary() for library files (.$format)');
    }
  }

  /// Serializes a document and writes it to a file.
  ///
  /// Format is detected from the file extension unless [format] is provided.
  Future<void> save(
    MarkdrawDocument doc,
    String path, {
    DocumentFormat? format,
  }) async {
    final fmt = format ?? detectFormat(path);
    final String content;
    switch (fmt) {
      case DocumentFormat.markdraw:
        content = DocumentSerializer.serialize(doc);
      case DocumentFormat.excalidraw:
        content = ExcalidrawJsonCodec.serialize(doc);
      case DocumentFormat.markdrawLibrary:
      case DocumentFormat.excalidrawLibrary:
        throw ArgumentError('Use saveLibrary() for library files (.$fmt)');
    }
    await writeFile(path, content);
  }

  /// Converts a document from one format to another.
  ///
  /// Loads from [inputPath], saves to [outputPath]. Formats are detected
  /// from file extensions. Returns the [ParseResult] from loading, which
  /// may contain warnings from the import step.
  Future<ParseResult<MarkdrawDocument>> convert(
    String inputPath,
    String outputPath,
  ) async {
    final result = await load(inputPath);
    await save(result.value, outputPath);
    return result;
  }

  /// Loads a library file and parses it into a [LibraryDocument].
  ///
  /// Format is detected from the file extension.
  Future<ParseResult<LibraryDocument>> loadLibrary(String path) async {
    final format = detectFormat(path);
    final content = await readFile(path);
    switch (format) {
      case DocumentFormat.markdrawLibrary:
        return LibraryCodec.parse(content);
      case DocumentFormat.excalidrawLibrary:
        return ExcalidrawLibCodec.parse(content);
      case DocumentFormat.markdraw:
      case DocumentFormat.excalidraw:
        throw ArgumentError('Use load() for document files (.$format)');
    }
  }

  /// Serializes a library document and writes it to a file.
  ///
  /// Format is detected from the file extension unless [format] is provided.
  Future<void> saveLibrary(
    LibraryDocument doc,
    String path, {
    DocumentFormat? format,
  }) async {
    final fmt = format ?? detectFormat(path);
    final String content;
    switch (fmt) {
      case DocumentFormat.markdrawLibrary:
        content = LibraryCodec.serialize(doc);
      case DocumentFormat.excalidrawLibrary:
        content = ExcalidrawLibCodec.serialize(doc);
      case DocumentFormat.markdraw:
      case DocumentFormat.excalidraw:
        throw ArgumentError('Use save() for document files (.$fmt)');
    }
    await writeFile(path, content);
  }
}
