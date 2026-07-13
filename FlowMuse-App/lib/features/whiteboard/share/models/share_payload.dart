import 'package:flutter/foundation.dart';

enum ShareContentType { png, markdraw, excalidraw, hyperlink }

@immutable
sealed class SharePayload {
  const SharePayload({required this.title, required this.contentType})
    : assert(title != '');

  final String title;
  final ShareContentType contentType;
}

@immutable
class ShareTextPayload extends SharePayload {
  ShareTextPayload({
    required super.title,
    required this.text,
    ShareContentType contentType = ShareContentType.hyperlink,
  }) : super(contentType: contentType) {
    if (contentType != ShareContentType.hyperlink) {
      throw ArgumentError.value(contentType, 'contentType', '文本分享仅支持链接');
    }
    _validateText(text);
  }

  final String text;

  static void _validateText(String text) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', '分享文本不能为空');
    }
  }
}

@immutable
class ShareFilePayload extends SharePayload {
  ShareFilePayload({
    required super.title,
    required ShareContentType contentType,
    this.filePath,
    required this.fileName,
    required this.mimeType,
    this.bytes,
  }) : super(contentType: contentType) {
    if (contentType == ShareContentType.hyperlink) {
      throw ArgumentError.value(contentType, 'contentType', '链接不能作为文件分享');
    }
    _validateFile(filePath, fileName, mimeType, bytes);
  }

  final String? filePath;
  final String fileName;
  final String mimeType;
  final Uint8List? bytes;

  static void _validateFile(
    String? filePath,
    String fileName,
    String mimeType,
    Uint8List? bytes,
  ) {
    if (filePath == null && bytes == null) {
      throw ArgumentError('文件分享需要文件路径或字节内容');
    }
    if (filePath != null &&
        !RegExp(r'^(?:[A-Za-z]:[\\/]|/)').hasMatch(filePath)) {
      throw ArgumentError.value(filePath, 'filePath', '文件路径必须是绝对路径');
    }
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName', '文件名不能为空');
    }
    if (mimeType.trim().isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'MIME 类型不能为空');
    }
  }
}
