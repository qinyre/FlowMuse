import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../analysis/analysis_retry_policy.dart';
import '../analysis/smart_layout_analysis_repository.dart';
import '../protocol/smart_layout_v3_request.dart';
import 'smart_layout_operation_guard.dart';
import 'smart_layout_session.dart';
import 'smart_layout_session_state.dart';

/// 候选展示摘要（review 阶段的 UI 投影）。V3-505B 将其绑定到真实
/// ValidatedCandidate（评分解释/结构差异/缩略图在此扩展）。
class SmartLayoutCandidateSummary {
  const SmartLayoutCandidateSummary({
    required this.candidateId,
    required this.structureLabel,
  });

  final String candidateId;
  final String structureLabel;

  @override
  String toString() =>
      'SmartLayoutCandidateSummary($candidateId, $structureLabel)';
}

/// 会话失败的稳定描述：阶段 + 原因 + 是否可重试 + 第几次尝试。
class SmartLayoutSessionFailure {
  const SmartLayoutSessionFailure({
    required this.stage,
    required this.reason,
    required this.retryable,
    required this.attempt,
  });

  /// analysis | apply。
  final String stage;
  final String reason;
  final bool retryable;
  final int attempt;

  @override
  String toString() =>
      'SmartLayoutSessionFailure($stage, $reason, '
      'retryable: $retryable, attempt: $attempt)';
}

/// Riverpod ViewModel 的不可变 UI 状态：会话 sealed 状态 + 范围选择 +
/// 保护标记 + review 数据 + 失败信息。UI 只读此状态、只调
/// [SmartLayoutSessionViewModel] 方法——视图层不持有业务 bool 或
/// Completer，任何在途操作都以 operationId 票据判新旧。
class SmartLayoutSessionUiState {
  const SmartLayoutSessionUiState({
    required this.sessionState,
    required this.scopeSourceIds,
    required this.protectedSourceIds,
    required this.candidates,
    required this.selectedCandidateId,
    required this.failure,
    required this.attemptCount,
    required this.activeTicket,
    required this.lastAnalysisResponse,
  });

  const SmartLayoutSessionUiState.initial()
    : this(
        sessionState: const SessionIdle(),
        scopeSourceIds: const [],
        protectedSourceIds: const {},
        candidates: const [],
        selectedCandidateId: null,
        failure: null,
        attemptCount: 0,
        activeTicket: null,
        lastAnalysisResponse: null,
      );

  final SmartLayoutSessionState sessionState;
  final List<String> scopeSourceIds;
  final Set<String> protectedSourceIds;
  final List<SmartLayoutCandidateSummary> candidates;
  final String? selectedCandidateId;
  final SmartLayoutSessionFailure? failure;

  /// 本次会话累计分析尝试次数（retry 递增，reset 归零）。
  final int attemptCount;

  /// 当次操作票据；idle/终态复位后为 null。迟到 continuation 以此判旧。
  final SmartLayoutOperationTicket? activeTicket;

  /// 最近一次成功分析的响应（生成链输入；V3-504B/505B 消费）。
  final SmartLayoutV3Response? lastAnalysisResponse;

  SmartLayoutSessionPhase get phase => sessionState.phase;

  /// 在途（分析/生成中）：一切重复入口按钮禁用的唯一依据。
  bool get isBusy =>
      phase == SmartLayoutSessionPhase.analyzing ||
      phase == SmartLayoutSessionPhase.applying;

  bool get canStartAnalysis =>
      phase == SmartLayoutSessionPhase.idle && scopeSourceIds.isNotEmpty;

  bool get canCancel =>
      phase == SmartLayoutSessionPhase.analyzing ||
      phase == SmartLayoutSessionPhase.reviewing ||
      phase == SmartLayoutSessionPhase.applying;

  bool get canChooseCandidate =>
      phase == SmartLayoutSessionPhase.reviewing && candidates.isNotEmpty;

  bool get canApply =>
      phase == SmartLayoutSessionPhase.reviewing && selectedCandidateId != null;

  bool get canRetry => failure != null && failure!.retryable;

  bool get canReset =>
      phase == SmartLayoutSessionPhase.applied ||
      phase == SmartLayoutSessionPhase.cancelled ||
      phase == SmartLayoutSessionPhase.failed;

  SmartLayoutSessionUiState copyWith({
    SmartLayoutSessionState? sessionState,
    List<String>? scopeSourceIds,
    Set<String>? protectedSourceIds,
    List<SmartLayoutCandidateSummary>? candidates,
    Object? selectedCandidateId = _sentinel,
    Object? failure = _sentinel,
    int? attemptCount,
    Object? activeTicket = _sentinel,
    Object? lastAnalysisResponse = _sentinel,
  }) {
    return SmartLayoutSessionUiState(
      sessionState: sessionState ?? this.sessionState,
      scopeSourceIds: List.unmodifiable(scopeSourceIds ?? this.scopeSourceIds),
      protectedSourceIds: Set.unmodifiable(
        protectedSourceIds ?? this.protectedSourceIds,
      ),
      candidates: List.unmodifiable(candidates ?? this.candidates),
      selectedCandidateId: identical(selectedCandidateId, _sentinel)
          ? this.selectedCandidateId
          : selectedCandidateId as String?,
      failure: identical(failure, _sentinel)
          ? this.failure
          : failure as SmartLayoutSessionFailure?,
      attemptCount: attemptCount ?? this.attemptCount,
      activeTicket: identical(activeTicket, _sentinel)
          ? this.activeTicket
          : activeTicket as SmartLayoutOperationTicket?,
      lastAnalysisResponse: identical(lastAnalysisResponse, _sentinel)
          ? this.lastAnalysisResponse
          : lastAnalysisResponse as SmartLayoutV3Response?,
    );
  }

  static const _sentinel = Object();

  @override
  String toString() =>
      'SmartLayoutSessionUiState(${sessionState.phase.name}, '
      'scope: ${scopeSourceIds.length}, protected: '
      '${protectedSourceIds.length}, candidates: ${candidates.length}, '
      'failure: $failure, attempts: $attemptCount)';
}

/// ViewModel 依赖束（真实接线归 V3-505C；测试经 provider 覆盖注入）。
class SmartLayoutSessionDependencies {
  const SmartLayoutSessionDependencies({
    required this.session,
    required this.repository,
    required this.requestBuilder,
    required this.commitResultBuilder,
    this.bearerToken,
  });

  final SmartLayoutSession session;
  final V3AnalysisRepository repository;

  /// 以当次票据构建分析请求（真实链：快照提取 + 资产编码，V3-505C 接线）。
  final Future<SmartLayoutV3Request> Function(SmartLayoutOperationTicket ticket)
  requestBuilder;

  /// 以候选 id 构建提交负载（真实链：ValidatedCandidate→ToolResult，
  /// V3-502A/505C 接线）。
  final ToolResult Function(String candidateId) commitResultBuilder;

  final String? bearerToken;
}

final smartLayoutSessionDependenciesProvider =
    Provider<SmartLayoutSessionDependencies>((ref) {
      throw UnimplementedError(
        'smartLayoutSessionDependenciesProvider 必须由入口覆盖注入'
        '（真实接线：V3-505C）',
      );
    });

final smartLayoutSessionViewModelProvider =
    NotifierProvider<SmartLayoutSessionViewModel, SmartLayoutSessionUiState>(
      SmartLayoutSessionViewModel.new,
    );

/// 会话 ViewModel（Riverpod Notifier）：编排范围选择、保护、分析、
/// 生成、review、commit、取消与重试。
///
/// 确定性契约（V3-505A acceptance）：
/// - 重复入口：`startAnalysis`/`retry`/`apply` 都先检相位，非法相位
///   no-op——重复点击不签发新票据、不产生第二次副作用；
/// - 取消立即终止：`cancel` 同步推进会话 cancelled 并清理 draft
///   （候选/选择/分析响应），不等待任何在途 future；迟到结果按票据
///   判旧丢弃；
/// - 重试/恢复确定：`retry` = reset→以同一 scope 重新分析，尝试计数
///   递增；重建 provider 恢复为 initial 确定状态。
///
/// 不引入额外策略门禁或确认流程：除状态机与四检守卫外无新增审批位。
class SmartLayoutSessionViewModel extends Notifier<SmartLayoutSessionUiState> {
  @override
  SmartLayoutSessionUiState build() =>
      const SmartLayoutSessionUiState.initial();

  SmartLayoutSessionDependencies get _deps =>
      ref.read(smartLayoutSessionDependenciesProvider);

  SmartLayoutSession get _session => _deps.session;

  /// 范围选择：加入一个排版源（去重、排序保持确定性）。
  void addScopeSource(String sourceId) {
    final next = {...state.scopeSourceIds, sourceId}.toList()..sort();
    state = state.copyWith(scopeSourceIds: next);
  }

  /// 范围选择：移除一个源；受保护源不允许从范围外移除（见保护语义）。
  void removeScopeSource(String sourceId) {
    final next = [...state.scopeSourceIds]..remove(sourceId);
    state = state.copyWith(scopeSourceIds: next);
  }

  void clearScope() {
    state = state.copyWith(scopeSourceIds: const []);
  }

  /// 保护标记切换：被保护的源参与排版分析（仍在 scope 中）但语义层
  /// 按保护处理；此操作只是编排状态，语义消费在分析/生成链。
  void toggleProtection(String sourceId) {
    final next = {...state.protectedSourceIds};
    if (!next.add(sourceId)) {
      next.remove(sourceId);
    }
    state = state.copyWith(protectedSourceIds: next);
  }

  /// 启动分析（服务端阶段）。合法相位 idle；其余（含在途与终态）no-op。
  Future<void> startAnalysis() async {
    if (!state.canStartAnalysis) return;
    final ticket = _session.beginOperation();
    final attempt = state.attemptCount + 1;
    state = state.copyWith(
      sessionState: _session.state,
      activeTicket: ticket,
      candidates: const [],
      selectedCandidateId: null,
      failure: null,
      lastAnalysisResponse: null,
      attemptCount: attempt,
    );
    await _runAnalysis(ticket, attempt);
  }

  Future<void> _runAnalysis(
    SmartLayoutOperationTicket ticket,
    int attempt,
  ) async {
    SmartLayoutAnalysisOutcome outcome;
    try {
      final request = await _deps.requestBuilder(ticket);
      outcome = await _deps.repository.analyze(
        request: request,
        ticket: ticket,
        bearerToken: _deps.bearerToken,
      );
    } on StateError {
      // 编辑器/追踪器已释放等同守卫路径：按失败收敛。
      _recordAnalysisFailure('analysis', 'disposed', false, attempt, ticket);
      return;
    }
    // 迟到判旧：票据不再是当次操作（取消/复位/新操作已接管）。
    if (!identical(state.activeTicket, ticket)) return;
    switch (outcome) {
      case SmartLayoutAnalysisSucceeded():
        // 保持 analyzing 相位，等待生成链完成（completeGeneration）。
        state = state.copyWith(lastAnalysisResponse: outcome.response);
      case SmartLayoutAnalysisFailed(:final kind, :final detail):
        if (kind == AnalysisFailureKind.cancelled) {
          // 取消已同步推进会话；这里只保证视图状态一致。
          _clearDraft();
          return;
        }
        if (kind == AnalysisFailureKind.guardRejected) {
          _recordAnalysisFailure('analysis', detail, false, attempt, ticket);
          return;
        }
        final retryable = switch (kind) {
          AnalysisFailureKind.network ||
          AnalysisFailureKind.timeout ||
          AnalysisFailureKind.badStatus => true,
          AnalysisFailureKind.capabilityOff ||
          AnalysisFailureKind.badSchema => false,
          AnalysisFailureKind.cancelled ||
          AnalysisFailureKind.guardRejected => false,
        };
        _recordAnalysisFailure(
          'analysis',
          kind.name,
          retryable,
          attempt,
          ticket,
          detail: detail,
        );
      case SmartLayoutAnalysisGuardRejected(:final reason):
        _recordAnalysisFailure('analysis', reason, false, attempt, ticket);
    }
  }

  void _recordAnalysisFailure(
    String stage,
    String reason,
    bool retryable,
    int attempt,
    SmartLayoutOperationTicket ticket, {
    String detail = '',
  }) {
    if (!identical(state.activeTicket, ticket)) return;
    // 用户已取消：会话处于 cancelled，迟到失败不升级为 failure 态。
    if (_session.state.phase == SmartLayoutSessionPhase.cancelled) {
      _clearDraft();
      return;
    }
    if (_session.state.phase == SmartLayoutSessionPhase.analyzing) {
      _session.advance(
        SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisFailed,
          reason: reason,
        ),
      );
    }
    state = state.copyWith(
      sessionState: _session.state,
      failure: SmartLayoutSessionFailure(
        stage: stage,
        reason: reason,
        retryable: retryable,
        attempt: attempt,
      ),
    );
  }

  /// 生成完成（客户端候选链回调；V3-504B 起接真实生成）。
  /// 合法相位 analyzing；空候选列表如实进入 reviewing（候选数 0，
  /// UI 显示无候选；505B 扩展无解分支展示）。
  void completeGeneration(List<SmartLayoutCandidateSummary> candidates) {
    if (state.phase != SmartLayoutSessionPhase.analyzing) return;
    _session.advance(
      SmartLayoutSessionEvent(
        SmartLayoutSessionEventKind.analysisSucceeded,
        candidateCount: candidates.length,
      ),
    );
    state = state.copyWith(
      sessionState: _session.state,
      candidates: candidates,
      selectedCandidateId: candidates.isEmpty
          ? null
          : candidates.first.candidateId,
    );
  }

  /// 选择候选（review 阶段）。非法相位或未知 id 为 no-op。
  void chooseCandidate(String candidateId) {
    if (!state.canChooseCandidate) return;
    if (!state.candidates.any((c) => c.candidateId == candidateId)) return;
    state = state.copyWith(selectedCandidateId: candidateId);
  }

  /// 提交所选候选：经会话唯一入口四检后 commit。合法相位 reviewing
  /// （或 applying 的重复调用 no-op）。
  Future<void> applySelectedCandidate() async {
    if (!state.canApply) return;
    final ticket = state.activeTicket;
    if (ticket == null) return;
    final candidateId = state.selectedCandidateId!;
    final result = _deps.commitResultBuilder(candidateId);
    final decision = _session.completeApply(
      ticket,
      candidateId: candidateId,
      result: result,
    );
    if (decision is SmartLayoutGuardRejected) {
      state = state.copyWith(
        sessionState: _session.state,
        failure: SmartLayoutSessionFailure(
          stage: 'apply',
          reason: decision.reason,
          retryable: false,
          attempt: state.attemptCount,
        ),
      );
      return;
    }
    state = state.copyWith(sessionState: _session.state, failure: null);
  }

  /// 立即取消：同步推进会话 cancelled 并清理 draft（候选/选择/响应），
  /// 不等待在途分析；迟到结果由票据判旧丢弃。幂等。
  void cancel({String reason = 'user-cancel'}) {
    if (!state.canCancel) return;
    _session.cancelOperation(reason: reason);
    _clearDraft();
  }

  void _clearDraft() {
    state = state.copyWith(
      sessionState: _session.state,
      candidates: const [],
      selectedCandidateId: null,
      lastAnalysisResponse: null,
    );
  }

  /// 重试：仅失败态且失败可重试。reset→同 scope 重新分析，
  /// 尝试计数在 startAnalysis 内递增——同一入口、同一确定性路径。
  Future<void> retry() async {
    if (!state.canRetry) return;
    if (!state.canReset) return;
    _session.reset();
    state = state.copyWith(sessionState: _session.state, failure: null);
    await startAnalysis();
  }

  /// 复位到 idle：清 draft 与失败信息，保留范围/保护（用户准备数据）。
  void reset() {
    if (!state.canReset) return;
    _session.reset();
    state = state.copyWith(
      sessionState: _session.state,
      candidates: const [],
      selectedCandidateId: null,
      failure: null,
      activeTicket: null,
      lastAnalysisResponse: null,
      attemptCount: 0,
    );
  }
}
