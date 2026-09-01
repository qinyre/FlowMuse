import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../analysis/smart_layout_analysis_repository.dart';
import '../commit/validated_candidate_commit_gateway.dart';
import '../composition/layout_block_assembler.dart';
import '../composition/layout_composition_planner.dart';
import '../correction/correction_patch_applier.dart' show AffectedSourceSet;
import '../design/smart_layout_design_tokens.dart';
import '../design/text_measure_adapter.dart';
import '../gateways/smart_layout_editor_gateway.dart';
import '../gateways/smart_layout_http_gateway.dart';
import '../geometry/layout_rect.dart';
import '../metrics/anti_gaming_veto.dart';
import '../metrics/layout_metric_contract.dart';
import '../metrics/layout_profile.dart';
import '../patch/candidate_patch_materializer.dart';
import '../placement/balanced_flow_placer.dart';
import '../placement/flow_placer.dart' show FlowPlacementSuccess;
import '../placement/preflight_layout.dart';
import '../protocol/smart_layout_v3_request.dart';
import '../semantics/semantic_document_assembler.dart';
import '../snapshot/layout_page_snapshot.dart';
import '../snapshot/scene_revision.dart';
import '../snapshot/snapshot_extractor.dart';
import '../snapshot/source_coverage_ledger.dart';
import '../validation/validated_candidate.dart';
import '../validation/validated_candidate_pipeline.dart';
import 'smart_layout_operation_guard.dart';
import 'smart_layout_session.dart';
import 'smart_layout_session_view_model.dart';

/// 真实候选生成链结果（V3-505C）：成功 = 验证候选（可能为空——
/// 无解/零修改保留如实呈现）；失败 = 稳定原因 + 是否可重试。
sealed class RealGenerationOutcome {
  const RealGenerationOutcome();

  /// 无解类原因：以空候选呈现（reviewing 无卡 + 重新分析入口），
  /// 不进 failed 态——无解不是错误。
  bool get isNoSolution =>
      this is RealGenerationFailed &&
      switch ((this as RealGenerationFailed).reason) {
        'no-feasible-layout' ||
        'no-placeable-candidate' ||
        'empty-page' => true,
        _ => false,
      };
}

class RealGenerationSucceeded extends RealGenerationOutcome {
  const RealGenerationSucceeded({required this.candidates});

  /// 经完整门禁流水线的验证候选（空 = 无解/零修改保留）。
  final List<ValidatedCandidate> candidates;
}

class RealGenerationFailed extends RealGenerationOutcome {
  const RealGenerationFailed({
    required this.reason,
    required this.retryable,
    this.detail = '',
  });

  final String reason;
  final bool retryable;
  final String detail;
}

/// 真实候选生成链（V3-505C）：快照 + 分析响应 → 语义装配 → 块装配 →
/// planner 枚举 → 硬 preflight → 栏平衡放置 → candidate 物化 → 完整
/// 门禁流水线——全部真实模块，无 fake。输入为请求时捕获的
/// [LayoutPageSnapshot]（响应 source 与快照同源）。
abstract final class SmartLayoutRealCandidateChain {
  static Future<RealGenerationOutcome> run({
    required Scene baseScene,
    required LayoutPageSnapshot snapshot,
    required SmartLayoutV3Response response,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
    LayoutProfile profile = LayoutProfile.readability,
  }) async {
    // ---- 0. 布局快照视图：剥离页框/PDF 底图（page furniture）----
    // background 对象只贡献 pageBounds（已提取），不是排版内容：留在
    // 排版 ledger 会破坏块守恒（它们 preserved 但永不成为块——
    // V3-204A/400A fixture 口径的空隙）。请求侧保留全源清单不变。
    final layoutObjects = [
      for (final object in snapshot.objects)
        if (object.mobility != SnapshotMobility.background) object,
    ];
    if (layoutObjects.isEmpty && snapshot.inkStrokes.isEmpty) {
      return const RealGenerationFailed(
        reason: 'empty-page',
        retryable: false,
      );
    }
    final layoutSnapshot = LayoutPageSnapshot(
      pageId: snapshot.pageId,
      pageBounds: snapshot.pageBounds,
      contentBounds: snapshot.contentBounds,
      sceneRevision: snapshot.sceneRevision,
      objects: List.unmodifiable(layoutObjects),
      inkStrokes: snapshot.inkStrokes,
      renderAssets: List.unmodifiable([
        for (final asset in snapshot.renderAssets)
          if (layoutObjects.any((o) => o.sourceId == asset.ownerSourceId))
            asset,
      ]),
      sourceCoverage: SourceCoverageLedger.pending([
        for (final object in layoutObjects) object.sourceId,
        for (final stroke in snapshot.inkStrokes) stroke.sourceId,
      ]),
    );

    // ---- 1. 语义装配（悬空 source/ledger 破坏 → fail closed）----
    final SemanticAssembly semantic;
    try {
      semantic = const SemanticDocumentAssembler().assemble(
        snapshot: layoutSnapshot,
        response: response,
      );
    } on StateError catch (error) {
      return RealGenerationFailed(
        reason: 'semantic-contract-broken',
        retryable: false,
        detail: error.message,
      );
    }

    // ---- 2. 块装配（真实测量；账目不守恒 = 响应未全额认领源 →
    // 协议契约破坏，fail closed）----
    final LayoutBlockAssembly assembly;
    try {
      assembly = const LayoutBlockAssembler().assemble(
        document: semantic.document,
        snapshot: layoutSnapshot,
        measure: measure,
        tokens: tokens,
      );
    } on StateError catch (error) {
      return RealGenerationFailed(
        reason: 'semantic-contract-broken',
        retryable: false,
        detail: error.message,
      );
    }

    // ---- 3. 页内容区：页框优先，缺省按内容包围盒；统一 inset 边距 ----
    final pageFrame = snapshot.pageBounds ?? snapshot.contentBounds;
    if (pageFrame == null) {
      return const RealGenerationFailed(
        reason: 'empty-page',
        retryable: false,
      );
    }
    final margin = tokens.pageMargin;
    final pageContent = LayoutRect(
      left: pageFrame.left + margin,
      top: pageFrame.top + margin,
      width: (pageFrame.width - margin * 2).clamp(1, double.infinity),
      height: (pageFrame.height - margin * 2).clamp(1, double.infinity),
    );
    final contentHeight = pageContent.height;

    // ---- 4. planner 枚举（确定性）+ 硬 preflight（批量，四型分派）----
    final enumeration = const LayoutCompositionPlanner().enumerate(
      constraint: CompositionConstraint(
        contentWidth: pageContent.width,
        tokens: tokens,
      ),
    );
    final screening = const LayoutPreflight().screen(
      assembly: assembly,
      candidates: enumeration.candidates,
      contentHeight: contentHeight,
      measure: measure,
      tokens: tokens,
    );
    switch (screening) {
      case NoFeasibleLayout():
        return const RealGenerationFailed(
          reason: 'no-feasible-layout',
          retryable: false,
        );
      case PreserveFallback():
        // 无可排内容：零修改保留，非无解——空候选如实呈现。
        return const RealGenerationSucceeded(candidates: []);
      case RetryableGenerationFailure(:final dependency):
        return RealGenerationFailed(
          reason: 'measurement-dependency',
          retryable: true,
          detail: dependency,
        );
      case InternalGenerationError(:final detail):
        return RealGenerationFailed(
          reason: 'internal-generation-error',
          retryable: false,
          detail: detail,
        );
      case LayoutGenerationScreened():
        break;
    }
    final accepted = screening.accepted;
    if (accepted.isEmpty) {
      return const RealGenerationFailed(
        reason: 'no-feasible-layout',
        retryable: false,
      );
    }

    // ---- 5. 逐候选：栏几何 → 平衡放置 → 物化 → 门禁输入 ----
    final inputs = <CandidateGateInput>[];
    for (final candidate in accepted) {
      final columnRects = _columnRectsOf(candidate, pageContent);
      final placed = const BalancedFlowPlacer().placeBalanced(
        assembly: assembly,
        candidate: candidate,
        pageContent: pageContent,
        columnRects: columnRects,
        contentHeight: contentHeight,
        measure: measure,
        tokens: tokens,
      );
      if (placed is! BalancedPlacement) {
        continue;
      }
      final materialized = SmartLayoutCandidateMaterializer.materialize(
        baseScene: baseScene,
        baseRevision: layoutSnapshot.sceneRevision,
        sourceCoverage: layoutSnapshot.sourceCoverage,
        assembly: assembly,
        placement: FlowPlacementSuccess(
          placed: placed.placed,
          usedHeights: placed.usedHeights,
        ),
        timestampMs: layoutSnapshot.sceneRevision.revision,
        pageId: layoutSnapshot.pageId,
      );
      if (materialized is! PatchMaterializationSuccess) {
        continue;
      }
      final metricInput = LayoutMetricInput(
        assembly: assembly,
        placed: placed.placed,
        columnRects: columnRects,
        preservedRects: placed.preservedRects,
        originalBounds: {
          for (final block in assembly.blocks)
            if (block.extras['bounds'] is Map<String, Object?>)
              block.id: _rectOf(block.extras['bounds'] as Map<String, Object?>),
        },
        contentHeight: contentHeight,
        hardValidated: true,
      );
      inputs.add(
        CandidateGateInput(
          candidateId: candidate.id,
          diversityKey: candidate.skeleton.name,
          patch: materialized.patch,
          metricInput: metricInput,
          veto: const AntiGamingVetoDetector().evaluate(metricInput),
        ),
      );
    }
    if (inputs.isEmpty) {
      return const RealGenerationFailed(
        reason: 'no-placeable-candidate',
        retryable: false,
      );
    }

    // ---- 6. 完整门禁流水线（reducer→render→metrics→hard→soft→Top3）----
    // pageContentBounds = 整页框（渲染/校验域含未触碰的页框元素；
    // 放置域才是边距 inset 后的内容区，两者口径不同）。
    final round = await ValidatedCandidatePipeline.run(
      baseScene: baseScene,
      pageContentBounds: Bounds.fromLTWH(
        pageFrame.left,
        pageFrame.top,
        pageFrame.width,
        pageFrame.height,
      ),
      candidates: inputs,
      profile: profile,
    );
    return RealGenerationSucceeded(candidates: round.top);
  }

  /// 候选栏几何（绝对页面坐标；与 preflight `_columnRectsOf` 同源推导：
  /// single/conservative 全宽、twoColumn 等分、mainSide 主+侧按
  /// sideOnRight 排列，沟取 token）。
  static List<LayoutRect> _columnRectsOf(
    CompositionCandidate candidate,
    LayoutRect content,
  ) {
    final p = candidate.params;
    final widths = switch (candidate.skeleton) {
      LayoutSkeleton.single => [p.mainColumnWidth],
      LayoutSkeleton.twoColumn => [p.mainColumnWidth, p.mainColumnWidth],
      LayoutSkeleton.mainSide => p.sideOnRight
          ? [p.mainColumnWidth, p.sideColumnWidth!]
          : [p.sideColumnWidth!, p.mainColumnWidth],
      LayoutSkeleton.conservativeLayout => [p.mainColumnWidth],
    };
    final rects = <LayoutRect>[];
    var left = content.left;
    for (final width in widths) {
      rects.add(
        LayoutRect(
          left: left,
          top: content.top,
          width: width,
          height: content.height,
        ),
      );
      left += width + p.columnGutter;
    }
    return rects;
  }

  static LayoutRect _rectOf(Map<String, Object?> json) => LayoutRect(
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
  );
}

/// 请求时捕获（请求、响应与生成链同源）。
final class _RequestCapture {
  const _RequestCapture({
    required this.scene,
    required this.snapshot,
    required this.ticket,
  });

  final Scene scene;
  final LayoutPageSnapshot snapshot;
  final SmartLayoutOperationTicket ticket;
}

/// 真实会话装配（V3-505C）：把既有真实模块组装为 ViewModel 依赖束——
/// 真实 editor/HTTP/分析仓库、快照级请求装配、真实候选生成链与
/// compare-and-commit 提交网关。无 fake provider；[post] 仅供测试注入
/// 传输（生产为 null，走真实 NativeHttpClient）。
///
/// 生命周期：一个页面一个 scope；[dispose] 在页面离开时释放
/// revision tracker 并作废捕获缓存。
class SmartLayoutRealSessionScope {
  SmartLayoutRealSessionScope._({
    required String pageId,
    required this.session,
    required this.repository,
    required this.commitGateway,
    required SmartLayoutEditorGateway editor,
    required SceneRevisionTracker tracker,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
    required LayoutProfile profile,
  }) : _pageId = pageId,
       _editor = editor,
       _tracker = tracker,
       _measure = measure,
       _tokens = tokens,
       _profile = profile;

  final String _pageId;
  final SmartLayoutSession session;
  final V3AnalysisRepository repository;
  final ValidatedCandidateCommitGateway commitGateway;
  final SmartLayoutEditorGateway _editor;
  final SceneRevisionTracker _tracker;
  final TextMeasureAdapter _measure;
  final SmartLayoutDesignTokens _tokens;
  final LayoutProfile _profile;

  /// build() 末尾装配（闭包引用本 scope，构造后一次性注入）。
  late final SmartLayoutSessionDependencies dependencies;

  _RequestCapture? _lastCapture;
  SmartLayoutV3Response? _lastResponse;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  static SmartLayoutRealSessionScope build({
    required MarkdrawController controller,
    required Uri serverUri,
    required String pageId,
    String? bearerToken,
    SmartLayoutHttpPost? post,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
    LayoutProfile profile = LayoutProfile.readability,
  }) {
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    final session = SmartLayoutSession(
      editor: editor,
      revisions: tracker,
      pageId: pageId,
    );
    final repo = V3AnalysisRepository(
      http: SmartLayoutHttpGateway(serverUri: serverUri, post: post),
      session: session,
    );
    final commitGateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final scope = SmartLayoutRealSessionScope._(
      pageId: pageId,
      session: session,
      repository: repo,
      commitGateway: commitGateway,
      editor: editor,
      tracker: tracker,
      measure: TextMeasureAdapter(tokens: tokens),
      tokens: tokens,
      profile: profile,
    );
    scope.dependencies = SmartLayoutSessionDependencies(
      session: session,
      repository: repo,
      requestBuilder: (ticket) async => scope._buildRequest(ticket),
      commitResultBuilder: (candidateId) =>
          throw StateError('真实路径走 commitGateway（compare-and-commit）'),
      correctionHandler: (intent) => AffectedSourceSet(
        regionIds: const {},
        strokeSourceIds: Set.unmodifiable(intent.subjectIds.toSet()),
        renderAssetKeys: const {},
        cropKeys: const {},
      ),
      rerunChain: (affectedSourceIds) =>
          scope._rerunCandidateChain(affectedSourceIds),
      candidateChain: (response, ticket) =>
          scope._runCandidateChain(response, ticket),
      commitGateway: commitGateway,
      bearerToken: bearerToken,
    );
    return scope;
  }

  /// 快照级真实请求装配：pageId + 当前 revision + clean 资产引用 +
  /// typed exactText + 全源 refs；捕获（scene+snapshot+ticket）供
  /// 响应后的生成链同源消费。
  SmartLayoutV3Request _buildRequest(SmartLayoutOperationTicket ticket) {
    if (_disposed) throw StateError('scope disposed');
    final revision = _tracker.isDisposed ? null : _tracker.current;
    if (revision == null) throw StateError('revision tracker disposed');
    final scene = _editor.currentScene;
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: _pageId,
      sceneRevision: revision,
    );
    _lastCapture = _RequestCapture(
      scene: scene,
      snapshot: snapshot,
      ticket: ticket,
    );
    return SmartLayoutV3Request(
      pageId: snapshot.pageId,
      sceneRevision: SmartLayoutV3SceneRevision(
        epoch: revision.epoch,
        revision: revision.revision,
        fingerprint: revision.fingerprint.value,
      ),
      assets: [
        SmartLayoutV3AssetRef(
          key: 'clean|${snapshot.pageId}',
          kind: SmartLayoutV3AssetKind.clean,
          fingerprint: revision.fingerprint.value,
        ),
      ],
      marks: const [],
      exactTexts: [
        for (final object in snapshot.objects)
          if (object.exactText != null)
            SmartLayoutV3ExactText(
              sourceId: object.sourceId,
              text: object.exactText!,
            ),
      ],
      sourceRefs: [for (final id in snapshot.sourceCoverage.statuses.keys) id],
    );
  }

  /// 真实候选生成链入口：捕获同源校验（票据不一致 = 离页/取消/重试
  /// 后的迟到响应 → StateError fail closed）。
  Future<List<ValidatedCandidate>> _runCandidateChain(
    SmartLayoutV3Response response,
    SmartLayoutOperationTicket ticket,
  ) async {
    final capture = _lastCapture;
    if (capture == null || !identical(capture.ticket, ticket)) {
      throw StateError('candidate-chain-ticket-mismatch');
    }
    _lastResponse = response;
    final outcome = await SmartLayoutRealCandidateChain.run(
      baseScene: capture.scene,
      snapshot: capture.snapshot,
      response: response,
      measure: _measure,
      tokens: _tokens,
      profile: _profile,
    );
    switch (outcome) {
      case RealGenerationSucceeded():
        return outcome.candidates;
      case RealGenerationFailed() when outcome.isNoSolution:
        // 无解：空候选如实呈现（reviewing 无卡 + 重新分析入口）。
        return const [];
      case RealGenerationFailed(:final reason):
        // 契约破坏/内部错误/可重试依赖失败 → failed 态
        //（reason 经 StateError 透传，VM 按 reason 判可重试）。
        throw StateError(reason);
    }
  }

  /// 纠错最小重跑（V3-505C 接线）：以当前 Scene 重新提取快照并对最后
  /// 响应重跑全链（V3-205A 已证"局部重算与全量等价"；affectedSourceIds
  /// 为 scope 键由链内缓存消费）。快照/响应失配（悬空 source）按
  /// 无产出处理——空列表如实呈现为无解卡，不伪装成功。
  Future<List<ValidatedCandidate>> _rerunCandidateChain(
    Set<String> affectedSourceIds,
  ) async {
    final response = _lastResponse;
    if (response == null || _disposed) return const [];
    try {
      final revision = _tracker.isDisposed ? null : _tracker.current;
      if (revision == null) return const [];
      final scene = _editor.currentScene;
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: _pageId,
        sceneRevision: revision,
      );
      final outcome = await SmartLayoutRealCandidateChain.run(
        baseScene: scene,
        snapshot: snapshot,
        response: response,
        measure: _measure,
        tokens: _tokens,
        profile: _profile,
      );
      return outcome is RealGenerationSucceeded ? outcome.candidates : const [];
    } on StateError {
      return const [];
    }
  }

  /// 用户切换页面（离页防线）：更新会话活页并作废未完成的捕获
  /// （旧票据续作由会话守卫拒绝）。
  void setActivePage(String pageId) {
    _lastCapture = null;
    session.setActivePage(pageId);
  }

  /// 释放作用域：候选产物归 ViewModel 候选卡管理（其 provider dispose
  /// 释放）；此处作废捕获/响应缓存并释放 revision tracker。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lastCapture = null;
    _lastResponse = null;
    _tracker.dispose();
  }
}
