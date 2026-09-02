import 'dart:async';

import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';

/// 可注入的 POST 传输函数，签名与 [NativeHttpClient.post] 一致。
/// 测试与合成服务器联调用 fake 替换，不引入第二套 HTTP client。
typedef SmartLayoutHttpPost =
    Future<NativeHttpResponse> Function({
      required String url,
      Map<String, String> headers,
      required String body,
      int connectTimeoutMs,
      int readTimeoutMs,
      NativeHttpCancelToken? cancelToken,
    });

/// 传输层错误分类。语义级错误翻译归 analysis repository（V3-203A）。
enum SmartLayoutHttpErrorKind {
  /// 连接失败、超时、平台通道异常等网络故障。
  network,

  /// 服务端返回非 2xx 状态码。
  badStatus,
}

/// 智能排版 v3 HTTP 传输错误的唯一异常类型。
class SmartLayoutHttpException implements Exception {
  const SmartLayoutHttpException._(this.kind, this.statusCode, this.detail);

  const SmartLayoutHttpException.network(String detail)
    : this._(SmartLayoutHttpErrorKind.network, null, detail);

  const SmartLayoutHttpException.badStatus(int statusCode, String detail)
    : this._(SmartLayoutHttpErrorKind.badStatus, statusCode, detail);

  final SmartLayoutHttpErrorKind kind;

  /// 非 null 时 [kind] 为 [SmartLayoutHttpErrorKind.badStatus]。
  final int? statusCode;
  final String detail;

  @override
  String toString() =>
      'SmartLayoutHttpException($kind, statusCode: $statusCode, $detail)';
}

/// 请求在完成前被 [NativeHttpCancelToken] 取消。
class SmartLayoutHttpCancelledException implements Exception {
  const SmartLayoutHttpCancelledException();

  @override
  String toString() => 'SmartLayoutHttpCancelledException';
}

/// 智能排版 v3 的唯一 HTTP 边界：薄封装既有 [NativeHttpClient]，
/// 负责 URL 拼接、鉴权头、超时、取消与传输错误分类；
/// 不做协议解析、重试或业务错误翻译。
class SmartLayoutHttpGateway {
  SmartLayoutHttpGateway({
    required Uri serverUri,
    SmartLayoutHttpPost? post,
    int connectTimeoutMs = 8000,
    int readTimeoutMs = 130000,
  }) : _serverUri = serverUri,
       _post = post ?? NativeHttpClient.post,
       _connectTimeoutMs = connectTimeoutMs,
       _readTimeoutMs = readTimeoutMs;

  final Uri _serverUri;
  final SmartLayoutHttpPost _post;
  final int _connectTimeoutMs;

  /// v2 智能排版识别同样使用 130s 读超时；分析端点按请求可覆盖。
  final int _readTimeoutMs;

  Uri get serverUri => _serverUri;

  /// 将 API 路径解析为完整请求地址；[path] 必须以 `/` 开头。
  Uri resolveUri(String path) {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'API 路径必须以 / 开头');
    }
    return _serverUri.resolve(path);
  }

  /// 发送 JSON POST 并返回 2xx 响应体。
  ///
  /// 取消抛 [SmartLayoutHttpCancelledException]；网络故障与非 2xx
  /// 抛 [SmartLayoutHttpException]。[bearerToken] 为 null 时不带鉴权头。
  Future<String> postJson({
    required String path,
    required String body,
    String? bearerToken,
    NativeHttpCancelToken? cancelToken,
    int? readTimeoutMs,
  }) async {
    final uri = resolveUri(path);
    final headers = <String, String>{
      'content-type': 'application/json',
      if (bearerToken != null && bearerToken.isNotEmpty)
        'authorization': 'Bearer $bearerToken',
    };
    final NativeHttpResponse response;
    try {
      response = await _post(
        url: uri.toString(),
        headers: headers,
        body: body,
        connectTimeoutMs: _connectTimeoutMs,
        readTimeoutMs: readTimeoutMs ?? _readTimeoutMs,
        cancelToken: cancelToken,
      );
    } on NativeHttpCancelledException {
      throw const SmartLayoutHttpCancelledException();
    } on SmartLayoutHttpException {
      rethrow;
    } catch (error) {
      throw SmartLayoutHttpException.network('$uri: $error');
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw SmartLayoutHttpException.badStatus(status, response.body);
    }
    return response.body;
  }
}
