import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../analysis/analysis_retry_policy.dart';
import '../analysis/smart_layout_analysis_repository.dart';
import '../commit/validated_candidate_commit_gateway.dart';
import '../correction/correction_patch_applier.dart' show AffectedSourceSet;
import '../snapshot/source_coverage_ledger.dart';
import '../metrics/layout_profile.dart';
import '../protocol/smart_layout_v3_request.dart';
import '../validation/correction_rerun_coordinator.dart';
import '../validation/validated_candidate.dart';
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

/// 验证候选卡（V3-505B）：review 阶段每张卡绑定当前
/// [ValidatedCandidate]——真实渲染缩略图（snapshot.image）、可还原
/// 评分解释（ProfileScore.entries）、结构代表与差异标签。
/// 卡数据与候选同生命周期：候选被纠错重跑失效时卡片一并重建。
class ValidatedCandidateCard {
  const ValidatedCandidateCard({
    required this.candidate,
    required this.rank,
    required this.structureLabel,
    required this.structureDiffLabel,
  });

  final ValidatedCandidate candidate;
  final int rank;
  final String structureLabel;

  /// 与首名候选的结构差异摘要（首名为基准）。
  final String structureDiffLabel;

  String get candidateId => candidate.candidateId;
  double get score => candidate.score.score;
  List<MetricContribution> get scoreEntries => candidate.score.entries;

  /// 真实 renderer 缩略图（归候选所有；卡片不得 dispose）。
  ui.Image get thumbnail => candidate.snapshot.image;
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
    required this.validatedCards,
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
        validatedCards: const [],
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

  /// 验证候选卡（每张绑定当前 ValidatedCandidate；空 = 未进入验证
  /// 候选路径，review 面回落到普通摘要卡）。
  final List<ValidatedCandidateCard> validatedCards;
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

  /// 整页视觉模式：分析对象是当前页全量内容（视觉链按页截图识别），
  /// 不依赖 scope 手工圈选——idle 即可启动；scope 仅作展示/保护数据。
  bool get canStartAnalysis => phase == SmartLayoutSessionPhase.idle;

  bool get canCancel =>
      phase == SmartLayoutSessionPhase.analyzing ||
      phase == SmartLayoutSessionPhase.reviewing ||
      phase == SmartLayoutSessionPhase.applying;

  bool get canChooseCandidate =>
      phase == SmartLayoutSessionPhase.reviewing && candidates.isNotEmpty;

  /// 当前选中卡绑定的验证候选（无验证卡路径为 null）。
  ValidatedCandidate? get selectedValidatedCandidate {
    final id = selectedCandidateId;
    if (id == null) return null;
    for (final card in validatedCards) {
      if (card.candidateId == id) return card.candidate;
    }
    return null;
  }

  /// 账本核对投影：当前选中候选的唯一账本逐源状态（id 排序）。
  List<(String, SourceCoverageStatus)> get ledgerReview {
    final candidate = selectedValidatedCandidate;
    if (candidate == null) return const [];
    final entries = candidate.patch.sourceCoverage.statuses.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [for (final entry in entries) (entry.key, entry.value)];
  }

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
    List<ValidatedCandidateCard>? validatedCards,
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
      validatedCards: List.unmodifiable(validatedCards ?? this.validatedCards),
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

/// 本地分析执行函数：绕过 requestBuilder+HTTP 仓库，直接产出
/// [SmartLayoutAnalysisOutcome]（生产链：v2 视觉感知 → v3 response 适配，
/// 手写转写文本经本地 map 进入语义装配，不经网络协议）。
/// 候选生成、状态迁移与失败处理仍在 ViewModel——runner 只负责分析。
typedef SmartLayoutAnalysisRunner =
    Future<SmartLayoutAnalysisOutcome> Function(
      SmartLayoutOperationTicket ticket,
    );

/// ViewModel 依赖束（真实接线归 V3-505C；测试经 provider 覆盖注入）。
class SmartLayoutSessionDependencies {
  final SmartLayoutSession session;
  final V3AnalysisRepository repository;

  /// 本地分析入口（生产链 v2 视觉感知 → v3 适配）：非 null 时
  /// [_runAnalysis] 调用它而非 requestBuilder+repository——不向
  /// `/analyze/v3` 发第二次模型请求。null = 保持既有 HTTP 仓库路径
  /// （实验/测试基础设施）。
  final SmartLayoutAnalysisRunner? analysisRunner;

  /// 取消在途分析的底层回调（生产视觉链：控制器
  /// cancelSmartLayoutPreparation——在途整页识别在下一检查点中止并
  /// 释放识别锁）；null = 无底层可取消（票据判旧兜底）。幂等。
  final void Function()? onCancelAnalysis;

  /// 以当次票据构建分析请求（真实链：快照提取 + 资产编码，V3-505C 接线）。
  final Future<SmartLayoutV3Request> Function(SmartLayoutOperationTicket ticket)
  requestBuilder;

  /// 以候选 id 构建提交负载（真实链：ValidatedCandidate→ToolResult，
  /// V3-502A/505C 接线）。
  final ToolResult Function(String candidateId) commitResultBuilder;

  /// 纠错修正处理：应用 region/role/order/relation 修正并返回受影响源
  /// 集（真实链：V3-205A CorrectionPatchApplier.affectedSources，
  /// V3-505C 接线；缺省返回空影响集——无修正语义时重跑为全量链的
  /// 一次调用）。
  final AffectedSourceSet Function(RegionCorrectionIntent intent)
  correctionHandler;

  /// 最小重跑链：以受影响源为 scope 重跑 planner→patch→render→gate→
  /// score 并返回新验证候选（真实链 V3-504B/505C 接线）。
  final Future<List<ValidatedCandidate>> Function(Set<String> affectedSourceIds)
  rerunChain;

  /// 候选生成链（V3-505C 真实接线）：分析成功后以响应+当次票据运行
  /// 客户端候选链（semantic→assembly→planner→preflight→放置→物化→
  /// 完整门禁）。null = 编排方手动 complete 路径（V3-505A/B 测试）。
  final Future<List<ValidatedCandidate>> Function(
    SmartLayoutV3Response response,
    SmartLayoutOperationTicket ticket,
  )?
  candidateChain;

  /// 验证候选提交网关（V3-505C 真实提交路径）：review 卡绑定候选时
  /// 走 compare-and-commit 事务（V3-502A）。null = 回落
  /// [commitResultBuilder]（V3-505A 测试路径）。
  final ValidatedCandidateCommitGateway? commitGateway;

  final String? bearerToken;

  const SmartLayoutSessionDependencies({
    required this.session,
    required this.repository,
    required this.requestBuilder,
    required this.commitResultBuilder,
    this.analysisRunner,
    this.onCancelAnalysis,
    this.correctionHandler = _emptyCorrection,
    this.rerunChain = _emptyRerun,
    this.candidateChain,
    this.commitGateway,
    this.bearerToken,
  });

  static AffectedSourceSet _emptyCorrection(RegionCorrectionIntent intent) =>
      AffectedSourceSet(
        regionIds: const {},
        strokeSourceIds: const {},
        renderAssetKeys: const {},
        cropKeys: const {},
      );

  static Future<List<ValidatedCandidate>> _emptyRerun(
    Set<String> affectedSourceIds,
  ) async => const [];
}

/// 用户修正意图（region/role/order/relation 修正的统一表达；语义
/// 解析归真实链 V3-205A/505C）。
class RegionCorrectionIntent {
  const RegionCorrectionIntent({
    required this.kind,
    required this.subjectIds,
    this.detail = '',
  });

  /// merge | split | role | order | relation。
  final String kind;
  final List<String> subjectIds;
  final String detail;
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
  /// 当前由本会话持有渲染资源的候选（发布卡同源；离页/取消/复位
  /// 释放）。onDispose 阶段不可读 state（Riverpod 生命周期断言），
  /// 故以字段持有。
  List<ValidatedCandidate> _ownedCandidates = const [];

  @override
  SmartLayoutSessionUiState build() {
    // 离页防线（V3-505C）：provider 作用域销毁（页面离开/重建）时
    // 释放已绑定候选的渲染资源——候选图片归候选所有，不得悬挂泄漏。
    ref.onDispose(() {
      for (final candidate in _ownedCandidates) {
        candidate.dispose();
      }
      _ownedCandidates = const [];
    });
    return const SmartLayoutSessionUiState.initial();
  }

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
      final runner = _deps.analysisRunner;
      if (runner != null) {
        // 本地分析链（v2 视觉感知 → v3 适配）：零 `/analyze/v3` 请求；
        // 取消/离页/守卫/失败语义由 runner 以 outcome 表达。
        outcome = await runner(ticket);
      } else {
        final request = await _deps.requestBuilder(ticket);
        outcome = await _deps.repository.analyze(
          request: request,
          ticket: ticket,
          bearerToken: _deps.bearerToken,
        );
      }
    } on StateError {
      // 编辑器/追踪器已释放等同守卫路径：按失败收敛。
      _recordAnalysisFailure('analysis', 'disposed', false, attempt, ticket);
      return;
    }
    // 迟到判旧：票据不再是当次操作（取消/复位/新操作已接管）。
    if (!identical(state.activeTicket, ticket)) return;
    switch (outcome) {
      case SmartLayoutAnalysisSucceeded():
        state = state.copyWith(lastAnalysisResponse: outcome.response);
        // 真实链（V3-505C）：分析成功即在同票据下运行候选生成链；
        // 缺省（测试编排路径）保持 analyzing 等待手动 complete。
        final chain = _deps.candidateChain;
        if (chain == null) return;
        List<ValidatedCandidate> candidates;
        try {
          candidates = await chain(outcome.response, ticket);
        } on StateError catch (error) {
          // 生成链 fail closed（契约破坏/内部错误/测量依赖失败）：
          // reason 透传；测量依赖失败按可重试收敛。
          _recordAnalysisFailure(
            'generation',
            error.message,
            error.message == 'measurement-dependency',
            attempt,
            ticket,
          );
          return;
        }
        if (!identical(state.activeTicket, ticket)) {
          // 迟到判旧：候选从未发布，立即释放其渲染资源（零泄漏）。
          for (final candidate in candidates) {
            candidate.dispose();
          }
          return;
        }
        completeGenerationFromValidated(candidates);
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

  /// 以验证候选完成生成（V3-505B 真实候选路径）：进入 reviewing，
  /// 每张卡绑定当前 ValidatedCandidate（真实缩略图/评分解释/结构差异）。
  /// 与 [completeGeneration] 共用同一相位契约。
  void completeGenerationFromValidated(List<ValidatedCandidate> candidates) {
    if (state.phase == SmartLayoutSessionPhase.analyzing) {
      _session.advance(
        SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: candidates.length,
        ),
      );
    } else if (state.phase != SmartLayoutSessionPhase.reviewing) {
      return;
    }
    final cards = <ValidatedCandidateCard>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      cards.add(
        ValidatedCandidateCard(
          candidate: candidate,
          rank: i + 1,
          structureLabel: candidate.diversityKey,
          structureDiffLabel: i == 0
              ? '基准结构'
              : (candidate.diversityKey == candidates.first.diversityKey
                    ? '同结构'
                    : '结构不同'),
        ),
      );
    }
    _ownedCandidates = List.unmodifiable(candidates);
    state = state.copyWith(
      sessionState: _session.state,
      candidates: [
        for (final card in cards)
          SmartLayoutCandidateSummary(
            candidateId: card.candidateId,
            structureLabel: card.structureLabel,
          ),
      ],
      validatedCards: cards,
      selectedCandidateId: cards.isEmpty ? null : cards.first.candidateId,
    );
  }

  /// 纠错修正（V3-505B）：应用修正 → 受影响源集 → 旧候选全失效
  ///（CorrectionRerunCoordinator 释放其渲染资源）→ 以受影响源为
  /// scope 最小重跑 → 新验证候选发布。仅 reviewing 相位合法。
  ///
  /// 修正期间锁定 reviewing 交互（isCorrecting 派生态）；
  /// 重跑无候选产出时保持 reviewing 并清空卡（无解如实呈现）。
  Future<void> applyRegionCorrection(RegionCorrectionIntent intent) async {
    if (state.phase != SmartLayoutSessionPhase.reviewing) return;
    final affected = _deps.correctionHandler(intent);
    final previous = [for (final card in state.validatedCards) card.candidate];
    final coordinator = CorrectionRerunCoordinator(chain: _deps.rerunChain);
    // 旧候选由 coordinator 释放（渲染资源归零）；随后立即发布新候选，
    // 重跑无产出时进入空卡 reviewing（无解如实呈现，不复活已释放候选）。
    final rerun = await coordinator.rerun(
      previousCandidates: previous,
      affected: affected,
    );
    completeGenerationFromValidated(rerun.newCandidates);
  }

  /// 选择候选（review 阶段）。非法相位或未知 id 为 no-op。
  void chooseCandidate(String candidateId) {
    if (!state.canChooseCandidate) return;
    if (!state.candidates.any((c) => c.candidateId == candidateId)) return;
    state = state.copyWith(selectedCandidateId: candidateId);
  }

  /// 提交所选候选：经会话唯一入口四检后 commit。合法相位 reviewing
  /// （或 applying 的重复调用 no-op）。
  ///
  /// V3-505C 真实路径：选中卡绑定 [ValidatedCandidate] 且依赖注入
  /// [SmartLayoutSessionDependencies.commitGateway] 时走
  /// compare-and-commit 事务（复核→CAS→applyResult，Scene 提交在
  /// 事务内一次完成）；否则回落 [SmartLayoutSessionDependencies.
  /// commitResultBuilder] 构建负载的 505A 路径。
  Future<void> applySelectedCandidate() async {
    if (!state.canApply) return;
    final ticket = state.activeTicket;
    if (ticket == null) return;
    final candidateId = state.selectedCandidateId!;
    final validated = state.selectedValidatedCandidate;
    final gateway = _deps.commitGateway;
    if (validated != null && gateway != null) {
      final decision = _session.completeApplyDelegated(
        ticket,
        candidateId: candidateId,
        commit: () {
          final result = gateway.commit(validated);
          return result is HistoryCommitted
              ? result.reduced.commitResult
              : null;
        },
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
      return;
    }
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
  ///
  /// V3-505C：取消即释放已绑定候选的渲染资源（卡不再展示，旧候选
  /// 不得再被提交/预览引用——与纠错失效同口径）。
  void cancel({String reason = 'user-cancel'}) {
    if (!state.canCancel) return;
    // 先请底层中止在途整页识别（幂等）：请求返回后在检查点退出并释放
    // 识别锁——取消后立即重试不撞“智能排版进行中”。
    _deps.onCancelAnalysis?.call();
    _releaseValidatedCards();
    _session.cancelOperation(reason: reason);
    _clearDraft();
  }

  void _releaseValidatedCards() {
    for (final candidate in _ownedCandidates) {
      candidate.dispose();
    }
    _ownedCandidates = const [];
    state = state.copyWith(validatedCards: const []);
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
  ///
  /// V3-505C：复位释放已绑定候选的渲染资源（终态卡不再展示）。
  void reset() {
    if (!state.canReset) return;
    _releaseValidatedCards();
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

  /// 无解重分析（V3-505C）：reviewing 无候选时以同 scope 重新走完整
  /// 分析（cancel→reset→startAnalysis 既有迁移的组合，不新增迁移）。
  void restartAnalysis() {
    if (state.phase != SmartLayoutSessionPhase.reviewing) return;
    if (state.candidates.isNotEmpty) return;
    cancel(reason: 'restart-analysis');
    reset();
    startAnalysis();
  }
}
