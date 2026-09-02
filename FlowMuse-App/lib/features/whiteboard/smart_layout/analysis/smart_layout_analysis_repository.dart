import 'dart:async';
import 'dart:convert';

import '../gateways/smart_layout_http_gateway.dart';
import '../protocol/smart_layout_v3_error.dart';
import '../protocol/smart_layout_v3_request.dart';
import '../protocol/smart_layout_v3_response.dart';
import '../session/smart_layout_operation_guard.dart';
import '../session/smart_layout_session.dart';
import 'analysis_operation_guard.dart';
import 'analysis_retry_policy.dart';

export '../protocol/smart_layout_v3_response.dart' show SmartLayoutV3Response;

/// 一次分析的结果：成功 / 稳定失败 / 守卫拒绝（四检）。
sealed class SmartLayoutAnalysisOutcome {
  const SmartLayoutAnalysisOutcome();
}

class SmartLayoutAnalysisSucceeded extends SmartLayoutAnalysisOutcome {
  const SmartLayoutAnalysisSucceeded(this.response, this.attempts);

  final SmartLayoutV3Response response;
  final int attempts;
}

class SmartLayoutAnalysisFailed extends SmartLayoutAnalysisOutcome {
  const SmartLayoutAnalysisFailed(this.kind, this.detail, this.attempts);

  final AnalysisFailureKind kind;
  final String detail;
  final int attempts;
}

class SmartLayoutAnalysisGuardRejected extends SmartLayoutAnalysisOutcome {
  const SmartLayoutAnalysisGuardRejected(this.reason, this.attempts);

  final String reason;
  final int attempts;
}

/// v3 分析仓库（V3-203A）：复用 [SmartLayoutHttpGateway]（即
/// NativeHttpClient 的唯一封装），统一取消、有限重试与四检；
/// 与真实 synthetic server 的联调走同一 [SmartLayoutHttpPost] 传输面。
///
/// capability off：不发任何请求（请求数为 0）。
/// 状态零污染：仓库无跨调用可变状态，一切结果都在 outcome 里。
class V3AnalysisRepository {
  V3AnalysisRepository({
    required SmartLayoutHttpGateway http,
    required SmartLayoutSession session,
    this.capabilityEnabled = true,
    this.retryPolicy = const AnalysisRetryPolicy(),
    this.guard = const AnalysisOperationGuard(),
    this.readTimeoutMs = 65000,
  }) : _http = http,
       _session = session;

  final SmartLayoutHttpGateway _http;
  final SmartLayoutSession _session;
  final AnalysisRetryPolicy retryPolicy;
  final AnalysisOperationGuard guard;
  final int readTimeoutMs;

  /// 能力开关（远端配置/feature flag 注入）。
  final bool capabilityEnabled;

  int _requestCount = 0;

  /// 已发出的 HTTP 请求总数（capability/守卫短路不计入）。
  int get requestCount => _requestCount;

  /// 取消是协作式（与 v2 语义一致）：session.cancelOperation() 后，
  /// 下一个守卫检查点（发送前/响应落地前/重试前）即拒绝；
  /// HTTP 传输不强行中断，迟到响应由 late-guard 丢弃。
  Future<SmartLayoutAnalysisOutcome> analyze({
    required SmartLayoutV3Request request,
    required SmartLayoutOperationTicket ticket,
    String? bearerToken,
  }) async {
    if (!capabilityEnabled) {
      return const SmartLayoutAnalysisFailed(
        AnalysisFailureKind.capabilityOff,
        'capability-off',
        0,
      );
    }
    var attempt = 0;
    while (true) {
      final guardReason = guard.check(_session, ticket);
      if (guardReason != null) {
        return SmartLayoutAnalysisGuardRejected(guardReason, attempt);
      }
      attempt++;
      _requestCount++;
      SmartLayoutHttpException? failure;
      String? body;
      try {
        body = await _http.postJson(
          path: '/api/ink/smart-layout/analyze/v3',
          body: _encodeRequest(request),
          bearerToken: bearerToken,
          readTimeoutMs: readTimeoutMs,
        );
        failure = null;
      } on SmartLayoutHttpCancelledException {
        return SmartLayoutAnalysisFailed(
          AnalysisFailureKind.cancelled,
          'cancelled',
          attempt,
        );
      } on SmartLayoutHttpException catch (error) {
        failure = error;
      }
      if (failure != null) {
        final kind = switch (failure.kind) {
          SmartLayoutHttpErrorKind.network =>
            failure.detail.contains('TimeoutException')
                ? AnalysisFailureKind.timeout
                : AnalysisFailureKind.network,
          SmartLayoutHttpErrorKind.badStatus => AnalysisFailureKind.badStatus,
        };
        if (!retryPolicy.shouldRetry(kind, failure.statusCode, attempt - 1)) {
          return SmartLayoutAnalysisFailed(kind, failure.toString(), attempt);
        }
        continue;
      }
      // 迟到响应防线：解码/落地前再过一次四检。
      final lateGuardReason = guard.check(_session, ticket);
      if (lateGuardReason != null) {
        return SmartLayoutAnalysisGuardRejected(lateGuardReason, attempt);
      }
      try {
        final response = SmartLayoutV3Response.fromJson(_decodeBody(body!));
        return SmartLayoutAnalysisSucceeded(response, attempt);
      } on SmartLayoutV3ProtocolException catch (error) {
        // 模型/服务端响应不合约：稳定失败，不重试。
        return SmartLayoutAnalysisFailed(
          AnalysisFailureKind.badSchema,
          error.toString(),
          attempt,
        );
      } on FormatException {
        return SmartLayoutAnalysisFailed(
          AnalysisFailureKind.badSchema,
          '响应不是合法 JSON',
          attempt,
        );
      }
    }
  }

  String _encodeRequest(SmartLayoutV3Request request) {
    final map = request.toJson();
    return jsonEncode(map);
  }

  Object? _decodeBody(String body) => jsonDecode(body);
}
