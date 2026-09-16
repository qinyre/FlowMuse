import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';

/// R4 测试共用的假传输层：按脚本响应、记录请求、可阻塞与可被取消。
class FakeRecognitionTransport {
  FakeRecognitionTransport({this.responder, this.errorFactory});

  /// 按请求生成响应（status + body）；null 走 errorFactory。
  Future<(int, String)> Function(String requestBody)? responder;

  /// 传输层异常（网络故障/取消）；返回 null 则走 responder。
  Future<Object?> Function(String requestBody)? errorFactory;

  final List<RecordedRequest> requests = [];
  final Completer<void> firstRequestSeen = Completer<void>();
  Completer<void>? _blockUntil;

  /// 阻塞所有后续请求直到 [release]。
  void blockRequests() => _blockUntil = Completer<void>();

  void release() {
    _blockUntil?.complete();
    _blockUntil = null;
  }

  SmartLayoutHttpPost get post =>
      ({
        required String url,
        Map<String, String> headers = const {},
        required String body,
        int connectTimeoutMs = 8000,
        int readTimeoutMs = 15000,
        NativeHttpCancelToken? cancelToken,
      }) async {
        requests.add(
          RecordedRequest(
            url: url,
            body: body,
            headers: Map<String, String>.from(headers),
            connectTimeoutMs: connectTimeoutMs,
            readTimeoutMs: readTimeoutMs,
          ),
        );
        if (!firstRequestSeen.isCompleted) {
          firstRequestSeen.complete();
        }
        final blocker = _blockUntil;
        if (blocker != null) {
          await blocker.future.then((_) => null, onError: (_) => null);
        }
        if (errorFactory != null) {
          final error = await errorFactory!(body);
          if (error != null) {
            throw error;
          }
        }
        if (responder != null) {
          final (status, responseBody) = await responder!(body);
          return NativeHttpResponse(statusCode: status, body: responseBody);
        }
        return const NativeHttpResponse(statusCode: 200, body: '{}');
      };

  RecordedRequest? requestOf(String pathContains) {
    for (final request in requests) {
      if (request.url.contains(pathContains)) return request;
    }
    return null;
  }

  Iterable<Map<String, Object?>> decodedBodies(String stage) sync* {
    for (final request in requests) {
      final decoded = jsonDecode(request.body) as Map<String, Object?>;
      if (decoded['stage'] == stage) {
        yield decoded;
      }
    }
  }
}

class RecordedRequest {
  RecordedRequest({
    required this.url,
    required this.body,
    required this.headers,
    required this.connectTimeoutMs,
    required this.readTimeoutMs,
  });

  final String url;
  final String body;
  final Map<String, String> headers;
  final int connectTimeoutMs;
  final int readTimeoutMs;
}

/// 构建合法 read/verify 响应：回填请求外壳并把区域标为 recognized
///（可选置信度与 missingRegionIds 子集）。
(int, String) buildBatchResponseBody(
  Map<String, Object?> requestBody, {
  double confidence = 0.9,
  String Function(String)? textOf,
  Set<String>? missingRegionIds,
}) {
  textOf ??= defaultTextOf;
  final missing = missingRegionIds ?? const <String>{};
  final regions = (requestBody['regions'] as List).cast<Map<String, Object?>>();
  final answered = <Map<String, Object?>>[];
  for (final region in regions) {
    final id = region['regionId'] as String;
    if (missing.contains(id)) continue;
    answered.add({
      'regionId': id,
      'status': 'recognized',
      'text': textOf(id),
      'confidence': confidence,
      'diagnostics': <String>[],
    });
  }
  final response = <String, Object?>{
    'schemaVersion': 'recognition-v3/1',
    'stage': requestBody['stage'],
    'operationId': requestBody['operationId'],
    'requestId': requestBody['requestId'],
    'pageId': requestBody['pageId'],
    'sceneRevision': requestBody['sceneRevision'],
    'contentFingerprint': requestBody['contentFingerprint'],
    'generation': requestBody['generation'],
    'regions': answered,
    'missingRegionIds': missing.toList(),
  };
  return (200, jsonEncode(response));
}

String defaultTextOf(String regionId) => '识别正文-$regionId';

String errorEnvelopeJson(String code, String message, bool retryable) =>
    jsonEncode({
      'error': {'code': code, 'message': message, 'retryable': retryable},
    });
