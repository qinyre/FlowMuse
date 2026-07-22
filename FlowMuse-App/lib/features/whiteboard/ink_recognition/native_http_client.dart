import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class NativeHttpResponse {
  const NativeHttpResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

class NativeHttpCancelledException implements Exception {
  const NativeHttpCancelledException();
}

class NativeHttpCancelToken {
  bool _cancelled = false;
  void Function()? _cancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel?.call();
  }

  void _attach(void Function() cancel) {
    if (_cancelled) {
      cancel();
    } else {
      _cancel = cancel;
    }
  }

  void _detach() => _cancel = null;

  void _throwIfCancelled() {
    if (_cancelled) throw const NativeHttpCancelledException();
  }
}

/// Cross-platform HTTP POST client.
///
/// On HarmonyOS: Platform Channel → @ohos.net.http (avoids dart:io socket bug).
/// On other platforms: package:http Client (exact same as original behavior).
class NativeHttpClient {
  static const String _channelName = 'flow_muse/http';
  static const MethodChannel _channel = MethodChannel(_channelName);
  static int _nextRequestId = 0;

  static Future<NativeHttpResponse> post({
    required String url,
    Map<String, String> headers = const {},
    required String body,
    int connectTimeoutMs = 8000,
    int readTimeoutMs = 15000,
    NativeHttpCancelToken? cancelToken,
  }) async {
    cancelToken?._throwIfCancelled();
    try {
      return await _postViaChannel(
        url: url,
        headers: headers,
        body: body,
        connectTimeoutMs: connectTimeoutMs,
        readTimeoutMs: readTimeoutMs,
        cancelToken: cancelToken,
      );
    } on MissingPluginException {
      debugPrint('[NativeHttp] 🔄 非鸿蒙平台，回退 package:http');
      cancelToken?._throwIfCancelled();
      return await _postViaHttpPackage(
        url: url,
        headers: headers,
        body: body,
        cancelToken: cancelToken,
      );
    } on PlatformException {
      cancelToken?._throwIfCancelled();
      rethrow;
    }
  }

  /// OHOS: Platform Channel → @ohos.net.http
  static Future<NativeHttpResponse> _postViaChannel({
    required String url,
    required Map<String, String> headers,
    required String body,
    required int connectTimeoutMs,
    required int readTimeoutMs,
    NativeHttpCancelToken? cancelToken,
  }) async {
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextRequestId++}';
    cancelToken?._attach(() {
      unawaited(_channel.invokeMethod<void>('cancel', requestId));
    });
    debugPrint('[NativeHttp] 📡 鸿蒙原生通道 | url: $url');
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('post', {
            'requestId': requestId,
            'url': url,
            'headersJson': jsonEncode(headers),
            'body': body,
            'connectTimeoutMs': connectTimeoutMs,
            'readTimeoutMs': readTimeoutMs,
          });
      cancelToken?._throwIfCancelled();
      if (result == null) throw Exception('Native HTTP channel returned null');
      return NativeHttpResponse(
        statusCode: result['statusCode'] as int,
        body: result['body'] as String? ?? '',
      );
    } finally {
      cancelToken?._detach();
    }
  }

  /// Android / iOS / desktop: package:http Client (original behavior).
  static Future<NativeHttpResponse> _postViaHttpPackage({
    required String url,
    required Map<String, String> headers,
    required String body,
    NativeHttpCancelToken? cancelToken,
  }) async {
    final client = http.Client();
    cancelToken?._attach(client.close);
    try {
      final response = await client
          .post(Uri.parse(url), headers: headers, body: body)
          .catchError((Object error) {
            cancelToken?._throwIfCancelled();
            throw error;
          });
      cancelToken?._throwIfCancelled();
      return NativeHttpResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } finally {
      cancelToken?._detach();
      client.close();
    }
  }
}

/// HTTP client that uses HarmonyOS Network Kit when the platform channel is
/// available and preserves package:http behavior everywhere else.
class HarmonyAwareHttpClient extends http.BaseClient {
  HarmonyAwareHttpClient({
    http.Client? fallbackClient,
    this.connectTimeoutMs = 8000,
    this.readTimeoutMs = 15000,
  }) : _fallbackClient = fallbackClient ?? http.Client();

  final http.Client _fallbackClient;
  final int connectTimeoutMs;
  final int readTimeoutMs;
  final Set<String> _activeRequestIds = {};
  bool _channelUnavailable = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    if (_channelUnavailable) {
      return _sendFallback(request, bodyBytes);
    }

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${NativeHttpClient._nextRequestId++}';
    _activeRequestIds.add(requestId);
    try {
      final result = await NativeHttpClient._channel
          .invokeMethod<Map<Object?, Object?>>('request', {
            'requestId': requestId,
            'method': request.method,
            'url': request.url.toString(),
            'headersJson': jsonEncode(request.headers),
            'bodyBytes': bodyBytes,
            'connectTimeoutMs': connectTimeoutMs,
            'readTimeoutMs': readTimeoutMs,
          });
      if (result == null) {
        throw StateError('Native HTTP channel returned null');
      }
      final responseBytes = switch (result['bodyBytes']) {
        final Uint8List bytes => bytes,
        final List<Object?> bytes => Uint8List.fromList(bytes.cast<int>()),
        _ => Uint8List(0),
      };
      return http.StreamedResponse(
        Stream.value(responseBytes),
        result['statusCode'] as int,
        contentLength: responseBytes.length,
        headers: _decodeHeaders(result['headersJson']),
        request: request,
      );
    } on MissingPluginException {
      _channelUnavailable = true;
      return _sendFallback(request, bodyBytes);
    } finally {
      _activeRequestIds.remove(requestId);
    }
  }

  Future<http.StreamedResponse> _sendFallback(
    http.BaseRequest original,
    Uint8List bodyBytes,
  ) {
    final request = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..bodyBytes = bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    return _fallbackClient.send(request);
  }

  static Map<String, String> _decodeHeaders(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return const {};
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return const {};
    return decoded.map(
      (key, value) => MapEntry(
        key.toString().toLowerCase(),
        value is List ? value.join(',') : value.toString(),
      ),
    );
  }

  @override
  void close() {
    for (final requestId in _activeRequestIds) {
      unawaited(
        NativeHttpClient._channel.invokeMethod<void>('cancel', requestId),
      );
    }
    _activeRequestIds.clear();
    _fallbackClient.close();
  }
}
