import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Lightweight WebDAV client using HTTP Basic Auth.
///
/// Designed for use with 坚果云 (dav.jianguoyun.com) and standard
/// WebDAV servers. All operations are authenticated with Basic Auth.
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : _inner = httpClient ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;

  final http.Client _inner;

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Map<String, String> get _baseHeaders => {'Authorization': _authHeader};

  /// Joins [baseUrl] and [path], normalizing slashes.
  String _resolve(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$base$p';
  }

  /// PROPFIND depth 0 — verifies connectivity and credentials.
  ///
  /// Throws [WebDavException] on auth failure or server error.
  Future<void> testConnection() async {
    const body =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:resourcetype/></d:prop></d:propfind>';
    final request = http.Request('PROPFIND', Uri.parse(_resolve('/')))
      ..headers.addAll({
        ..._baseHeaders,
        'Depth': '0',
        'Content-Type': 'application/xml',
        'Connection': 'close',
      })
      ..body = body;
    final streamed = await _inner
        .send(request)
        .timeout(const Duration(seconds: 15));
    final status = streamed.statusCode;
    await streamed.stream.drain<void>().timeout(const Duration(seconds: 15));
    if (status == 401) {
      throw const WebDavException('用户名或密码错误', statusCode: 401);
    }
    if (status != 207 && status != 200) {
      throw WebDavException('服务器返回 $status', statusCode: status);
    }
  }

  /// MKCOL — creates a directory at [path].
  ///
  /// 405 (Method Not Allowed) and 409 (Conflict) indicate the directory
  /// already exists and are silently ignored.
  Future<void> ensureDirectory(String path) async {
    final uri = Uri.parse(_resolve(path.endsWith('/') ? path : '$path/'));
    final request = http.Request('MKCOL', uri)
      ..headers.addAll({..._baseHeaders, 'Connection': 'close'});
    final streamed = await _inner
        .send(request)
        .timeout(const Duration(seconds: 15));
    await streamed.stream.drain<void>().timeout(const Duration(seconds: 15));
    final status = streamed.statusCode;
    // 201 = created, 405/409 = already exists — all acceptable
    if (status != 201 && status != 405 && status != 409 && status != 301) {
      throw WebDavException('无法创建目录 $path，服务器返回 $status', statusCode: status);
    }
  }

  /// PUT — uploads [data] bytes to [path], creating or replacing the file.
  Future<void> putFile(
    String path,
    Uint8List data, {
    String contentType = 'application/json; charset=utf-8',
  }) async {
    final uri = Uri.parse(_resolve(path));
    final request = http.Request('PUT', uri)
      ..headers.addAll({
        ..._baseHeaders,
        'Content-Type': contentType,
        'Content-Length': '${data.length}',
        'Connection': 'close',
      })
      ..bodyBytes = data;
    final streamed = await _inner
        .send(request)
        .timeout(const Duration(seconds: 90));
    await streamed.stream.drain<void>().timeout(const Duration(seconds: 90));
    final status = streamed.statusCode;
    if (status != 200 && status != 201 && status != 204) {
      throw WebDavException('上传失败，服务器返回 $status', statusCode: status);
    }
  }

  /// GET — downloads the file at [path] and returns its bytes.
  Future<Uint8List> getFile(String path) async {
    final uri = Uri.parse(_resolve(path));
    final response = await _inner
        .get(uri, headers: {..._baseHeaders, 'Connection': 'close'})
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      throw WebDavException(
        '下载失败，服务器返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  /// PROPFIND depth 1 — lists direct children of [path].
  ///
  /// Skips the directory entry for [path] itself and returns only files
  /// (non-directories).
  Future<List<WebDavEntry>> listDirectory(String path) async {
    const body =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getcontentlength/>'
        '<d:getlastmodified/><d:resourcetype/>'
        '</d:prop></d:propfind>';
    final uri = Uri.parse(_resolve(path.endsWith('/') ? path : '$path/'));
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll({
        ..._baseHeaders,
        'Depth': '1',
        'Content-Type': 'application/xml',
        'Accept-Encoding': 'identity',
        'Connection': 'close',
      })
      ..body = body;
    final streamed = await _inner
        .send(request)
        .timeout(const Duration(seconds: 20));
    final status = streamed.statusCode;
    if (status == 404) {
      return const [];
    }
    if (status != 207) {
      await streamed.stream.drain<void>().timeout(const Duration(seconds: 20));
      throw WebDavException('读取目录失败，服务器返回 $status', statusCode: status);
    }
    final xml = await streamed.stream.bytesToString().timeout(
      const Duration(seconds: 20),
    );
    return _parseMultiStatus(xml);
  }

  void dispose() => _inner.close();

  // ── XML parsing ────────────────────────────────────────────────────────────

  static List<WebDavEntry> _parseMultiStatus(String xml) {
    final entries = <WebDavEntry>[];
    // Match each <d:response> block (case-insensitive namespace prefixes)
    final blocks = RegExp(
      r'<(?:d|D):response[^>]*>(.*?)</(?:d|D):response>',
      dotAll: true,
    ).allMatches(xml);

    for (final m in blocks) {
      final block = m.group(1)!;
      final href = _xmlText(block, 'href') ?? '';
      final isDir =
          block.contains(':collection') || block.contains('collection/');
      if (isDir) continue; // skip the directory itself and any sub-dirs

      final rawName = _xmlText(block, 'displayname');
      final name = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : href.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
      final sizeStr = _xmlText(block, 'getcontentlength');
      final sizeBytes = sizeStr != null ? int.tryParse(sizeStr) : null;
      final lastModStr = _xmlText(block, 'getlastmodified');
      final lastModified = lastModStr != null
          ? _parseHttpDate(lastModStr)
          : null;

      entries.add(
        WebDavEntry(
          href: href,
          name: name,
          sizeBytes: sizeBytes,
          lastModified: lastModified,
        ),
      );
    }
    return entries;
  }

  static String? _xmlText(String block, String tag) {
    final pattern = RegExp(
      '<(?:d|D):$tag[^>]*>(.*?)</(?:d|D):$tag>',
      dotAll: true,
    );
    return pattern.firstMatch(block)?.group(1)?.trim();
  }

  /// Parses RFC 1123 / RFC 822 HTTP-date:
  ///   "Thu, 16 Jul 2026 05:00:00 GMT"
  static DateTime? _parseHttpDate(String value) {
    try {
      const months = [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ];
      final parts = value.trim().split(RegExp(r'[\s,]+'));
      // Format: [DayOfWeek, Day, Month, Year, HH:MM:SS, TZ]
      final day = int.parse(parts[1]);
      final month = months.indexOf(parts[2].toLowerCase()) + 1;
      final year = int.parse(parts[3]);
      final timeParts = parts[4].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);
      return DateTime.utc(year, month, day, hour, minute, second).toLocal();
    } catch (_) {
      return null;
    }
  }
}

/// An error returned by a WebDAV operation.
class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode != null ? '[$statusCode] $message' : message;
}

/// Metadata for a file on the WebDAV server.
class WebDavEntry {
  const WebDavEntry({
    required this.href,
    required this.name,
    this.sizeBytes,
    this.lastModified,
  });

  final String href;
  final String name;
  final int? sizeBytes;
  final DateTime? lastModified;
}
