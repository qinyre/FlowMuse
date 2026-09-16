/// recognize/v3 客户端仓库（spec §2/§3.5）：HTTP 边界 + 错误映射 +
/// 剩余预算接线。内部仅调 [SmartLayoutHttpGateway.postJson]。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_json_reader.dart';

import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';

/// 客户端侧识别异常（§3.5：SmartLayoutHttpException 与错误体映射为
/// {kind, retryable}）。
enum RecognitionExceptionKind {
  /// 发送前自检失败（请求 schema 违规）——客户端 bug，不可重试。
  invalidRequest,

  /// 网络传输失败（连接失败等）——可重试。
  network,

  /// 服务端错误 envelope 携带的语义码（busy/providerError/
  /// providerTimeout/invalidProviderResponse/unconfigured/auth/
  /// limitExceeded/...），retryable 以 envelope 为准（缺失按 §3.5 表）。
  serverCode,

  /// 响应体不是合法 JSON 或未通过客户端严格校验（含回填比对）。
  invalidResponse,

  /// 请求被取消（总时限到期主动取消或用户取消）。
  cancelled,

  /// 剩余预算已耗尽，请求未发出。
  budgetExhausted,
}

class RecognitionException implements Exception {
  const RecognitionException(
    this.kind, {
    required this.retryable,
    this.code,
    this.detail = '',
  });

  final RecognitionExceptionKind kind;
  final bool retryable;

  /// kind=serverCode 时为服务端语义码 wire 名。
  final String? code;
  final String detail;

  @override
  String toString() =>
      'RecognitionException($kind, retryable: $retryable'
      '${code == null ? '' : ', code: $code'}, $detail)';
}

/// recognize/v3 唯一 HTTP 边界。
class RecognitionRepository {
  RecognitionRepository({required SmartLayoutHttpGateway gateway})
    : _gateway = gateway;

  static const String endpointPath = '/api/ink/smart-layout/recognize/v3';

  final SmartLayoutHttpGateway _gateway;

  /// 发送一次识别请求并严格解析响应。
  ///
  /// - 发送前自检：请求 JSON 经 fromJson 重新解析（客户端侧 400 双保险，
  ///   §3.6）；失败抛 [RecognitionException]（invalidRequest，不可重试）。
  /// - [remainingBudget]：本请求允许占用的剩余时间。readTimeout =
  ///   min(45s, remaining)；到期由内部计时器**主动** [cancelToken.cancel]
  ///   在途请求（不只靠轮询）。
  /// - 响应携带 [RecognitionResponse.fromJson] 的 expectedFor 上下文校验
  ///   （回填四元组 + 覆盖声明，R-12/R-04 双保险）。
  Future<RecognitionResponse> send(
    RecognitionRequest request, {
    String? bearerToken,
    NativeHttpCancelToken? cancelToken,
    required Duration remainingBudget,
  }) async {
    // 1. 发送前自检（双保险的客户端一半）。
    final body = jsonEncode(request.toJson());
    try {
      RecognitionRequest.fromJson(jsonDecode(body));
    } on RecognitionProtocolException catch (error) {
      throw RecognitionException(
        RecognitionExceptionKind.invalidRequest,
        retryable: false,
        code: error.error.code.wireName,
        detail: '发送前自检失败: ${error.error.message}',
      );
    }

    if (remainingBudget <= Duration.zero) {
      throw const RecognitionException(
        RecognitionExceptionKind.budgetExhausted,
        retryable: false,
        detail: '剩余预算已耗尽',
      );
    }
    final readTimeoutMs = remainingBudget.inMilliseconds < 45000
        ? remainingBudget.inMilliseconds
        : 45000;

    // 2. 总预算计时器：到期主动取消在途请求（服务端 ctx 取消兜底之外的
    //    客户端主动取消，spec §6.1）。
    final activeCancelToken = cancelToken ?? NativeHttpCancelToken();
    final watchdog = Timer(remainingBudget, activeCancelToken.cancel);
    try {
      final responseBody = await _gateway.postJson(
        path: endpointPath,
        body: body,
        bearerToken: bearerToken,
        cancelToken: activeCancelToken,
        readTimeoutMs: readTimeoutMs,
      );
      return _parseResponse(responseBody, request);
    } on SmartLayoutHttpCancelledException {
      throw const RecognitionException(
        RecognitionExceptionKind.cancelled,
        retryable: false,
        detail: '请求被取消',
      );
    } on SmartLayoutHttpException catch (error) {
      throw _mapHttpException(error);
    } finally {
      watchdog.cancel();
    }
  }

  RecognitionResponse _parseResponse(
    String responseBody,
    RecognitionRequest request,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException catch (error) {
      throw RecognitionException(
        RecognitionExceptionKind.invalidResponse,
        retryable: false,
        detail: '响应不是合法 JSON: ${error.message}',
      );
    }
    try {
      return RecognitionResponse.fromJson(decoded, expectedFor: request);
    } on RecognitionProtocolException catch (error) {
      throw RecognitionException(
        RecognitionExceptionKind.invalidResponse,
        retryable: false,
        code: error.error.code.wireName,
        detail: error.error.message,
      );
    }
  }

  /// §3.5 错误映射：badStatus 解析服务端 envelope
  /// {"error":{"code","message","retryable"}}；网络故障 → network
  /// （retryable）；无法解析的错误体按状态码兜底。
  RecognitionException _mapHttpException(SmartLayoutHttpException error) {
    if (error.kind == SmartLayoutHttpErrorKind.network) {
      return RecognitionException(
        RecognitionExceptionKind.network,
        retryable: true,
        detail: error.detail,
      );
    }
    final status = error.statusCode ?? 0;
    try {
      final decoded = jsonDecode(error.detail);
      if (decoded is Map<String, Object?>) {
        final envelope = decoded['error'];
        if (envelope is Map<String, Object?>) {
          final wire = RecognitionWireError.fromJson(envelope);
          return RecognitionException(
            RecognitionExceptionKind.serverCode,
            retryable: wire.retryable,
            code: wire.code.wireName,
            detail: wire.message,
          );
        }
      }
    } on FormatException {
      // 落入下方状态码兜底。
    } on ArgumentError {
      // 未知错误码：落入兜底。
    }
    final retryable = status == 429 || status == 502 || status == 504;
    return RecognitionException(
      RecognitionExceptionKind.serverCode,
      retryable: retryable,
      code: status >= 500
          ? RecognitionExceptionCode.providerError.wireName
          : null,
      detail:
          'HTTP $status: ${error.detail.length > 120 ? error.detail.substring(0, 120) : error.detail}',
    );
  }
}
