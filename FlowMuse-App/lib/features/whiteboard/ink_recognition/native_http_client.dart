import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class NativeHttpResponse {
  const NativeHttpResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

/// Cross-platform HTTP POST client.
///
/// On HarmonyOS: Platform Channel → @ohos.net.http (avoids dart:io socket bug).
/// On other platforms: package:http Client (exact same as original behavior).
class NativeHttpClient {
  static const String _channelName = 'flow_muse/http';
  static const MethodChannel _channel = MethodChannel(_channelName);

  static Future<NativeHttpResponse> post({
    required String url,
    Map<String, String> headers = const {},
    required String body,
    int connectTimeoutMs = 8000,
    int readTimeoutMs = 15000,
  }) async {
    try {
      return await _postViaChannel(
        url: url, headers: headers, body: body,
        connectTimeoutMs: connectTimeoutMs, readTimeoutMs: readTimeoutMs,
      );
    } on MissingPluginException {
      debugPrint('[NativeHttp] 🔄 非鸿蒙平台，回退 package:http');
      return await _postViaHttpPackage(url: url, headers: headers, body: body);
    }
  }

  /// OHOS: Platform Channel → @ohos.net.http
  static Future<NativeHttpResponse> _postViaChannel({
    required String url, required Map<String, String> headers,
    required String body, required int connectTimeoutMs, required int readTimeoutMs,
  }) async {
    debugPrint('[NativeHttp] 📡 鸿蒙原生通道 | url: $url');
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('post', {
      'url': url, 'headersJson': jsonEncode(headers), 'body': body,
      'connectTimeoutMs': connectTimeoutMs, 'readTimeoutMs': readTimeoutMs,
    });
    if (result == null) throw Exception('Native HTTP channel returned null');
    return NativeHttpResponse(
      statusCode: result['statusCode'] as int,
      body: result['body'] as String? ?? '',
    );
  }

  /// Android / iOS / desktop: package:http Client (original behavior).
  static Future<NativeHttpResponse> _postViaHttpPackage({
    required String url, required Map<String, String> headers,
    required String body,
  }) async {
    final response = await http.post(Uri.parse(url), headers: headers, body: body);
    return NativeHttpResponse(statusCode: response.statusCode, body: response.body);
  }
}
