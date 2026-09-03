import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../analysis/analysis_retry_policy.dart';
import '../analysis/smart_layout_analysis_repository.dart';
import '../commit/validated_candidate_commit_gateway.dart';
import '../composition/layout_block.dart';
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
import '../protocol/smart_layout_v3_response.dart';
import '../semantics/semantic_document_assembler.dart';
import '../snapshot/layout_page_snapshot.dart';
import '../snapshot/scene_revision.dart';
import '../snapshot/snapshot_extractor.dart';
import '../snapshot/source_coverage_ledger.dart';
import '../validation/validated_candidate.dart';
import '../validation/validated_candidate_pipeline.dart';
import 'smart_layout_operation_guard.dart';
import 'smart_layout_session.dart';
import 'smart_layout_session_state.dart';
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
    Map<String, String> transcribedTextByRegion = const {},
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
    if (response.regions.isEmpty && layoutObjects.isEmpty) {
      // 视觉适配器口径：无 movable 对象且零 region = prepare 门控全空
      // （页内仅余噪点等非排版源，不构成内容）——无解空候选收敛，
      // 不进守恒校验。有内容对象时零认领仍是契约破坏（fail closed）。
      return const RealGenerationSucceeded(candidates: []);
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
    // 手写转写经本地 map 进入 extras（typed exactText 优先，悬空
    // regionId 拒绝）——文本不经网络协议往返。
    final SemanticAssembly semantic;
    try {
      semantic = const SemanticDocumentAssembler().assemble(
        snapshot: layoutSnapshot,
        response: response,
        transcribedTextByRegion: transcribedTextByRegion,
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
    // 内容量事实（结构适用性输入，真机 2026-09-03 门禁）：内容块数 +
    // 文本实测填充率；图/图注存在即非纯文字（多栏适用性另由约束判）。
    var contentBlockCount = 0;
    var textMeasuredHeight = 0.0;
    var hasFigureContent = false;
    for (final block in assembly.blocks) {
      if (block.isPreservedLike) continue;
      contentBlockCount++;
      if (block.kind == LayoutBlockKind.figure ||
          block.kind == LayoutBlockKind.caption) {
        hasFigureContent = true;
      }
      final intrinsic = block.measuredIntrinsic;
      if (intrinsic != null) textMeasuredHeight += intrinsic.height;
    }
    final enumeration = const LayoutCompositionPlanner().enumerate(
      constraint: CompositionConstraint(
        contentWidth: pageContent.width,
        contentBlockCount: contentBlockCount,
        contentFillRatio: contentHeight > 0
            ? (textMeasuredHeight / contentHeight).clamp(0.0, 1.0)
            : 0.0,
        hasFigureContent: hasFigureContent,
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

/// v2 视觉准备 → v3 响应适配的契约破坏（source 守恒失败等）：
/// 稳定语义失败（badSchema，不重试），由 runner 统一映射。
class _VisionAdapterContractError implements Exception {
  const _VisionAdapterContractError(this.message);

  final String message;

  @override
  String toString() => 'VisionAdapterContractError: $message';
}

/// 排序草稿：region 待定内容 + 阅读序排序键（原稿 top/left/稳定 key）。
/// 列表项编号模式（行首，容忍空白）：阿拉伯 `1.`/`1、`/`1．`/`1)`、
/// CJK `一、`/`一.`、圈号 `①-⑳`。孤立编号行不成组；范围即冻结口径。
final RegExp _listItemNumberPattern = RegExp(
  r'^\s*(?:\d{1,3}\s*[.、．）)]|[①-⑳]|[一二三四五六七八九十]{1,3}\s*[、.．])',
);

class _RegionDraft {
  const _RegionDraft({
    required this.role,
    required this.sourceIds,
    required this.confidence,
    required this.sortTop,
    required this.sortLeft,
    required this.sortKey,
    required this.bounds,
    this.transcribedText,
  });

  final SmartLayoutV3Role role;
  final List<String> sourceIds;
  final double confidence;
  final double sortTop;
  final double sortLeft;
  final String sortKey;

  /// 认领源在原稿中的包围盒（噪点最近邻认领用）。
  final Rect bounds;
  final String? transcribedText;
}

/// 真实会话装配（V3-505C）：把既有真实模块组装为 ViewModel 依赖束——
/// 真实 editor/HTTP/分析仓库、快照级请求装配、真实候选生成链与
/// compare-and-commit 提交网关。无 fake provider；[post] 仅供测试注入
/// 传输（生产为 null，走真实 NativeHttpClient）。
///
/// 生命周期：scope 可跨页复用（[setActivePage] 改指新页）；[dispose]
/// 在页面离开时释放 revision tracker 并作废捕获缓存。
class SmartLayoutRealSessionScope {
  SmartLayoutRealSessionScope._({
    required String pageId,
    required this.session,
    required this.repository,
    required this.commitGateway,
    required MarkdrawController controller,
    required SmartLayoutEditorGateway editor,
    required SceneRevisionTracker tracker,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
    required LayoutProfile profile,
  }) : _pageId = pageId,
       _controller = controller,
       _editor = editor,
       _tracker = tracker,
       _measure = measure,
       _tokens = tokens,
       _profile = profile;

  /// 当前作用页（截图/视觉识别/候选重跑共用）；[setActivePage] 切页时
  /// 随会话一并改指新页。
  String _pageId;
  final SmartLayoutSession session;
  final V3AnalysisRepository repository;
  final ValidatedCandidateCommitGateway commitGateway;
  final MarkdrawController _controller;
  final SmartLayoutEditorGateway _editor;
  final SceneRevisionTracker _tracker;
  final TextMeasureAdapter _measure;
  final SmartLayoutDesignTokens _tokens;
  final LayoutProfile _profile;

  /// build() 末尾装配（闭包引用本 scope，构造后一次性注入）。
  late final SmartLayoutSessionDependencies dependencies;

  _RequestCapture? _lastCapture;
  SmartLayoutV3Response? _lastResponse;
  Map<String, String>? _lastTranscribedTextByRegion;
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
    bool useVisionAnalysis = true,
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
      controller: controller,
      editor: editor,
      tracker: tracker,
      measure: TextMeasureAdapter(tokens: tokens),
      tokens: tokens,
      profile: profile,
    );
    scope.dependencies = SmartLayoutSessionDependencies(
      session: session,
      repository: repo,
      // 生产分析入口（v2 视觉感知 → v3 适配）：零 `/analyze/v3` 请求。
      // [useVisionAnalysis]=false 时回落 requestBuilder+repository 的
      // HTTP 实验路径（既有基础设施测试口径）。
      analysisRunner: useVisionAnalysis
          ? (ticket) => scope._analyzeWithVision(ticket)
          : null,
      // 取消回调（生产视觉链）：VM 取消 → 控制器中止在途整页识别，
      // 释放识别锁（幂等；未在准备中为空操作）。
      onCancelAnalysis: () => controller.cancelSmartLayoutPreparation(),
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
  /// 响应后的生成链同源消费。（实验/测试路径：生产分析走
  /// [_analyzeWithVision]，不发送本请求。）
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

  /// 本地分析链（生产入口）：v2 视觉感知（整页截图 + Set-of-Mark +
  /// `/vision` 一次 + 低置信 `/transcribe` 裁剪重问）→ 轻量适配层 →
  /// v3 response + 本地转写 map。零 `/analyze/v3` 第二模型请求；
  /// 一页最多一次整页 VLM 调用。
  ///
  /// 异常映射：
  /// - 用户取消（SmartLayoutCancelledException）→ cancelled；
  /// - 页面/Scene/票据变化、编辑器释放、并发准备 → guard rejected；
  /// - 无识别引擎 → capabilityOff（稳定不可重试）；
  /// - 截图/vision/transcribe 主链失败 → 可重试失败；
  /// - 适配器 source 守恒失败 → badSchema（稳定不可重试）；
  /// - 页面门控全空（preparation null）→ 空响应（生成链按无解收敛）。
  Future<SmartLayoutAnalysisOutcome> _analyzeWithVision(
    SmartLayoutOperationTicket ticket,
  ) async {
    if (_disposed) {
      return const SmartLayoutAnalysisGuardRejected('disposed', 0);
    }
    final revision = _tracker.isDisposed ? null : _tracker.current;
    if (revision == null) {
      return const SmartLayoutAnalysisGuardRejected('disposed', 0);
    }
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
    _lastResponse = null;
    _lastTranscribedTextByRegion = null;

    final SmartLayoutTemplatePreparation? preparation;
    try {
      preparation = await _controller.prepareSmartLayoutTemplates(
        pageId: _pageId,
      );
    } on SmartLayoutCancelledException {
      return const SmartLayoutAnalysisFailed(
        AnalysisFailureKind.cancelled,
        'cancelled',
        1,
      );
    } on StateError catch (error) {
      final message = error.message;
      if (message == '编辑器已释放') {
        return const SmartLayoutAnalysisGuardRejected('disposed', 0);
      }
      if (message.startsWith('智能排版进行中') || message.startsWith('页面不存在')) {
        return SmartLayoutAnalysisGuardRejected(message, 0);
      }
      if (message == '没有可用的识别引擎') {
        return const SmartLayoutAnalysisFailed(
          AnalysisFailureKind.capabilityOff,
          '没有可用的识别引擎',
          1,
        );
      }
      // 截图失败/整页识别无内容（v2 显式"请重试"语义）→ 可重试失败。
      return SmartLayoutAnalysisFailed(
        AnalysisFailureKind.network,
        message,
        1,
      );
    } catch (error) {
      // 截图/vision/transcribe 主链其余异常：可重试失败，不伪装成功。
      return SmartLayoutAnalysisFailed(
        AnalysisFailureKind.network,
        error.toString(),
        1,
      );
    }

    // 迟到防线：识别期间用户取消/离页/新操作接管/远端内容变化/
    // scope 释放——任何一项发生即丢弃结果（四检）。
    if (_disposed) {
      return const SmartLayoutAnalysisGuardRejected('disposed', 1);
    }
    final decision = session.checkContinuation(ticket);
    if (decision is SmartLayoutGuardRejected) {
      return SmartLayoutAnalysisGuardRejected(decision.reason, 1);
    }
    if (preparation == null) {
      // 页面门控全空（无手写簇、无页面元素）：稳定无解——空 regions
      // 响应由生成链按 empty-page 空候选收敛（无解不是错误）。
      return const SmartLayoutAnalysisSucceeded(
        SmartLayoutV3Response(regions: [], warnings: []),
        1,
      );
    }
    try {
      final (response, transcribed) = _adaptVisionPreparation(
        preparation,
        snapshot,
      );
      _lastTranscribedTextByRegion = Map.unmodifiable(transcribed);
      return SmartLayoutAnalysisSucceeded(response, 1);
    } on _VisionAdapterContractError catch (error) {
      return SmartLayoutAnalysisFailed(
        AnalysisFailureKind.badSchema,
        error.toString(),
        1,
      );
    }
  }

  /// v2 视觉准备 → v3 响应适配（轻量投影，零模型调用）。
  ///
  /// - title → role=title；pairs → figure + captions（figure 先于其
  ///   captions，最近前驱 figure 绑定生效；relation 系统不扩展——
  ///   语义装配器不消费 response relation）；looseTexts → body（公式块
  ///   smartLayoutType=math → formula）；looseFigures → figure；
  /// - sourceIds 全部锚定原始 Scene/source ledger：手写=memberIds 笔迹
  ///   id、打字=原 TextElement id、图/形/组=成员元素 id；VLM 临时 id
  ///   （e0/vision-*）绝不充当 sourceId；region 自身 id 用稳定
  ///   vision-rN；
  /// - 每个 source 至多认领一次（重复=契约破坏 fail closed）；锁定成员
  ///   跳过认领（保持 protected obstacle）；
  /// - 未认领的 movable 对象/笔迹 → 显式 unknown region（进 preserved，
  ///   不静默删除）；background 与 protectedObstacle 不生成 region；
  ///   噪点笔画（removeIds 交集）例外——认领进最近转写文本块随应用
  ///   删除（v2"随方案静默删除"同口径，消除残留墨点）；
  /// - readingOrder 重建为连续 0..N-1：title 优先，其余按原稿
  ///   top/left/稳定 key；图文组内 figure 后接其 captions；
  /// - 置信度：单块值（blockId 直查）优先，缺省用页面整体值，clamp
  ///   [0,1]；unknown 用 0；
  /// - 手写转写进本地 map（空文本不伪造）；typed 不入 map（快照
  ///   exactText 回填，禁止 OCR 覆盖打字）。
  (SmartLayoutV3Response, Map<String, String>) _adaptVisionPreparation(
    SmartLayoutTemplatePreparation preparation,
    LayoutPageSnapshot snapshot,
  ) {
    final content = preparation.content;
    final objectById = {
      for (final object in snapshot.objects) object.sourceId: object,
    };
    final strokeIds = {
      for (final stroke in snapshot.inkStrokes) stroke.sourceId,
    };
    final claimed = <String>{};
    final transcribed = <String, String>{};

    List<String> claimUnitSources(LayoutUnit unit) {
      final ids = <String>[];
      for (final id in unit.memberIds) {
        final object = objectById[id];
        if (object != null &&
            object.mobility == SnapshotMobility.protectedObstacle) {
          continue;
        }
        if (object == null && !strokeIds.contains(id)) {
          throw _VisionAdapterContractError(
            '单元 ${unit.key} 引用了快照不存在的 source: $id',
          );
        }
        if (!claimed.add(id)) {
          throw _VisionAdapterContractError(
            '单元 ${unit.key} 重复认领 source: $id',
          );
        }
        ids.add(id);
      }
      return ids;
    }

    SmartLayoutV3Role unitRole(LayoutUnit unit, SmartLayoutV3Role fallback) {
      final flowMuse = unit.textElement?.customData?['flowMuse'];
      if (flowMuse is Map && flowMuse['smartLayoutType'] == 'math') {
        return SmartLayoutV3Role.formula;
      }
      return fallback;
    }

    double unitConfidence(LayoutUnit unit) {
      final flowMuse = unit.textElement?.customData?['flowMuse'];
      final blockId = flowMuse is Map ? flowMuse['blockId'] as String? : null;
      final value =
          (blockId == null ? null : preparation.confidenceByBlockId[blockId]) ??
          preparation.confidence;
      return value.clamp(0.0, 1.0);
    }

    _RegionDraft? textDraft(LayoutUnit unit, SmartLayoutV3Role role) {
      final typed =
          unit.memberIds.length == 1 &&
          objectById.containsKey(unit.memberIds.single);
      final handwritten =
          unit.memberIds.isNotEmpty && unit.memberIds.every(strokeIds.contains);
      if (!typed && !handwritten) {
        throw _VisionAdapterContractError(
          '文本单元 ${unit.key} 的成员既非单一场景元素也非整组笔迹',
        );
      }
      final ids = claimUnitSources(unit);
      if (ids.isEmpty) return null;
      return _RegionDraft(
        role: unitRole(unit, role),
        sourceIds: ids,
        confidence: unitConfidence(unit),
        sortTop: unit.sourceBounds.top,
        sortLeft: unit.sourceBounds.left,
        sortKey: unit.key,
        bounds: unit.sourceBounds,
        transcribedText: handwritten
            ? (unit.textElement?.text.trim() ?? '')
            : null,
      );
    }

    _RegionDraft? figureDraft(LayoutUnit unit) {
      final ids = claimUnitSources(unit);
      if (ids.isEmpty) return null;
      return _RegionDraft(
        role: SmartLayoutV3Role.figure,
        sourceIds: ids,
        confidence: unitConfidence(unit),
        sortTop: unit.sourceBounds.top,
        sortLeft: unit.sourceBounds.left,
        sortKey: unit.key,
        bounds: unit.sourceBounds,
      );
    }

    // 有序组：图文组内 figure 先于其 captions（最近前驱 figure 绑定），
    // 组间与松散项/unknown 统一按原稿 top/left/稳定 key 排序。
    final titleDrafts = <_RegionDraft>[];
    final groups =
        <({double top, double left, String key, List<_RegionDraft> drafts})>[];

    void addGroup(
      double top,
      double left,
      String key,
      List<_RegionDraft?> nullable,
    ) {
      final drafts = [for (final draft in nullable) ?draft];
      if (drafts.isEmpty) return;
      groups.add((top: top, left: left, key: key, drafts: drafts));
    }

    final titleUnit = content.title;
    if (titleUnit != null) {
      final draft = textDraft(titleUnit, SmartLayoutV3Role.title);
      if (draft != null) titleDrafts.add(draft);
    }
    for (final pair in content.pairs) {
      addGroup(
        pair.figure.sourceBounds.top,
        pair.figure.sourceBounds.left,
        pair.figure.key,
        [
          figureDraft(pair.figure),
          for (final unit in pair.topTexts)
            textDraft(unit, SmartLayoutV3Role.caption),
          for (final unit in pair.bottomTexts)
            textDraft(unit, SmartLayoutV3Role.caption),
        ],
      );
    }
    for (final unit in content.looseTexts) {
      addGroup(
        unit.sourceBounds.top,
        unit.sourceBounds.left,
        unit.key,
        [textDraft(unit, SmartLayoutV3Role.body)],
      );
    }
    for (final unit in content.looseFigures) {
      addGroup(
        unit.sourceBounds.top,
        unit.sourceBounds.left,
        unit.key,
        [figureDraft(unit)],
      );
    }

    // 未认领的可移动内容 → 显式 unknown region（进 preserved，不静默
    // 删除）。background 不生成 region；protectedObstacle 不生成
    // unknown（v3 障碍装配逻辑处理）。
    void addUnknown(String sourceId, double top, double left) {
      groups.add((
        top: top,
        left: left,
        key: sourceId,
        drafts: [
          _RegionDraft(
            role: SmartLayoutV3Role.unknown,
            sourceIds: [sourceId],
            confidence: 0,
            sortTop: top,
            sortLeft: left,
            sortKey: sourceId,
            bounds: Rect.fromLTWH(left, top, 0, 0),
          ),
        ],
      ));
    }

    for (final object in snapshot.objects) {
      if (object.mobility != SnapshotMobility.movable) continue;
      if (claimed.contains(object.sourceId)) continue;
      addUnknown(
        object.sourceId,
        object.visualBounds.top,
        object.visualBounds.left,
      );
    }
    // 噪点笔画（<8×8pt，v2 口径"随方案静默删除，消除残留墨点"）：
    // 不进 preserved——认领进最近的转写文本块（transcribed 变换整组
    // 删除源笔迹，应用时一并清除）；页面无转写块时回落 preserved
    // （未发生 ink→text 转换，噪点保留不算残留）。
    final noiseSourceIds = {
      for (final id in preparation.removeIds) id.value,
    };
    final textDraftsForNoise = [
      for (final draft in titleDrafts)
        if (draft.transcribedText != null) draft,
      for (final group in groups)
        for (final draft in group.drafts)
          if (draft.transcribedText != null) draft,
    ];
    double distanceToDraft(Rect strokeBounds, _RegionDraft draft) {
      final strokeCenter = strokeBounds.center;
      final draftCenter = draft.bounds.center;
      final dx = strokeCenter.dx - draftCenter.dx;
      final dy = strokeCenter.dy - draftCenter.dy;
      return dx * dx + dy * dy;
    }

    for (final stroke in snapshot.inkStrokes) {
      if (claimed.contains(stroke.sourceId)) continue;
      if (noiseSourceIds.contains(stroke.sourceId) &&
          textDraftsForNoise.isNotEmpty) {
        final strokeRect = Rect.fromLTWH(
          stroke.visualBounds.left,
          stroke.visualBounds.top,
          stroke.visualBounds.width,
          stroke.visualBounds.height,
        );
        _RegionDraft nearest = textDraftsForNoise.first;
        var nearestDistance = distanceToDraft(strokeRect, nearest);
        for (final draft in textDraftsForNoise.skip(1)) {
          final distance = distanceToDraft(strokeRect, draft);
          if (distance < nearestDistance) {
            nearest = draft;
            nearestDistance = distance;
          }
        }
        nearest.sourceIds.add(stroke.sourceId);
        claimed.add(stroke.sourceId);
        continue;
      }
      addUnknown(
        stroke.sourceId,
        stroke.visualBounds.top,
        stroke.visualBounds.left,
      );
    }

    groups.sort((a, b) {
      final byTop = a.top.compareTo(b.top);
      if (byTop != 0) return byTop;
      final byLeft = a.left.compareTo(b.left);
      if (byLeft != 0) return byLeft;
      return a.key.compareTo(b.key);
    });

    // 连续编号行黏连（真机 2026-09-03 案例）：视觉服务逐行返回、不产
    // list 语义，"1./一、/①"连续行会被当独立正文块，双栏平衡器按
    // 栏深均衡把它们拆到两栏（阅读断裂）。阅读序连续、文本匹配编号
    // 模式的手写转写行黏连为单个列表块——单块物理不可拆，平衡器无法
    // 拆清单；角色升为 list 供下游语义使用。typed 文本不打乱（用户
    // 显式分立的元素不改组）。
    bool numberedBodyGroup(
      ({double top, double left, String key, List<_RegionDraft> drafts}) group,
    ) {
      if (group.drafts.length != 1) return false;
      final draft = group.drafts.single;
      final text = draft.transcribedText;
      return draft.role == SmartLayoutV3Role.body &&
          text != null &&
          _listItemNumberPattern.hasMatch(text);
    }

    final compactedGroups =
        <({double top, double left, String key, List<_RegionDraft> drafts})>[];
    var runStart = 0;
    while (runStart < groups.length) {
      if (!numberedBodyGroup(groups[runStart])) {
        compactedGroups.add(groups[runStart]);
        runStart++;
        continue;
      }
      var runEnd = runStart + 1;
      while (runEnd < groups.length && numberedBodyGroup(groups[runEnd])) {
        runEnd++;
      }
      if (runEnd - runStart == 1) {
        // 孤立编号行不成组（无拆分风险，保持原样不造语义）。
        compactedGroups.add(groups[runStart]);
        runStart = runEnd;
        continue;
      }
      final runDrafts = <_RegionDraft>[
        for (var i = runStart; i < runEnd; i++) groups[i].drafts.single,
      ];
      var left = runDrafts.first.bounds.left;
      var top = runDrafts.first.bounds.top;
      var right = runDrafts.first.bounds.right;
      var bottom = runDrafts.first.bounds.bottom;
      var confidence = runDrafts.first.confidence;
      for (final draft in runDrafts.skip(1)) {
        left = draft.bounds.left < left ? draft.bounds.left : left;
        top = draft.bounds.top < top ? draft.bounds.top : top;
        right = draft.bounds.right > right ? draft.bounds.right : right;
        bottom = draft.bounds.bottom > bottom ? draft.bounds.bottom : bottom;
        if (draft.confidence < confidence) confidence = draft.confidence;
      }
      final first = runDrafts.first;
      compactedGroups.add((
        top: groups[runStart].top,
        left: groups[runStart].left,
        key: groups[runStart].key,
        drafts: [
          _RegionDraft(
            role: SmartLayoutV3Role.list,
            sourceIds: [for (final draft in runDrafts) ...draft.sourceIds],
            confidence: confidence,
            sortTop: first.sortTop,
            sortLeft: first.sortLeft,
            sortKey: first.sortKey,
            bounds: Rect.fromLTWH(left, top, right - left, bottom - top),
            transcribedText: [
              for (final draft in runDrafts) draft.transcribedText!,
            ].join('\n'),
          ),
        ],
      ));
      runStart = runEnd;
    }
    groups
      ..clear()
      ..addAll(compactedGroups);

    // 终态化：region id 稳定编号 vision-r1..rN，readingOrder 连续
    // 0..N-1（不沿用可能有间断的旧序号）；手写转写以 region id 键入
    // 本地 map（空文本不伪造，typed 不入 map）。
    final regions = <SmartLayoutV3Region>[];
    var regionNumber = 0;
    void publish(_RegionDraft draft) {
      final id = 'vision-r${++regionNumber}';
      regions.add(
        SmartLayoutV3Region(
          id: id,
          role: draft.role,
          sourceIds: List.unmodifiable(draft.sourceIds),
          readingOrder: regions.length,
          confidence: draft.confidence,
          relations: const [],
        ),
      );
      final text = draft.transcribedText;
      if (text != null && text.isNotEmpty) {
        transcribed[id] = text;
      }
    }

    for (final draft in titleDrafts) {
      publish(draft);
    }
    for (final group in groups) {
      for (final draft in group.drafts) {
        publish(draft);
      }
    }
    return (
      SmartLayoutV3Response(
        regions: List.unmodifiable(regions),
        warnings: const [],
      ),
      Map.unmodifiable(transcribed),
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
      transcribedTextByRegion:
          _lastTranscribedTextByRegion ?? const <String, String>{},
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
        transcribedTextByRegion:
            _lastTranscribedTextByRegion ?? const <String, String>{},
      );
      return outcome is RealGenerationSucceeded ? outcome.candidates : const [];
    } on StateError {
      return const [];
    }
  }

  /// 用户切换页面（离页防线）：scope 改指新页（截图、视觉识别、候选
  /// 重跑都作用于新页号）并作废未完成的捕获与转写缓存（旧票据续作由
  /// 会话守卫拒绝）。
  ///
  /// 面板重开复用本 scope：终态会话（applied/cancelled/failed）在此
  /// 复位为 idle——新面板的 VM 初始相位与状态机若错位，点开始将在
  /// beginOperation 静默抛非法迁移（零反馈死按钮）。在途态不动。
  void setActivePage(String pageId) {
    _pageId = pageId;
    _lastCapture = null;
    _lastResponse = null;
    _lastTranscribedTextByRegion = null;
    switch (session.state.phase) {
      case SmartLayoutSessionPhase.applied:
      case SmartLayoutSessionPhase.cancelled:
      case SmartLayoutSessionPhase.failed:
        session.reset();
      case SmartLayoutSessionPhase.idle:
      case SmartLayoutSessionPhase.analyzing:
      case SmartLayoutSessionPhase.reviewing:
      case SmartLayoutSessionPhase.applying:
        break;
    }
    session.setActivePage(pageId);
  }

  /// 释放作用域：候选产物归 ViewModel 候选卡管理（其 provider dispose
  /// 释放）；此处作废捕获/响应/转写缓存并释放 revision tracker。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lastCapture = null;
    _lastResponse = null;
    _lastTranscribedTextByRegion = null;
    _tracker.dispose();
  }
}
