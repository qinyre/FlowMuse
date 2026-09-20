import 'dart:convert' show jsonDecode;
import 'dart:ui' show TextDirection;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../analysis/analysis_retry_policy.dart';
import '../analysis/smart_layout_analysis_repository.dart';
import '../commit/validated_candidate_commit_gateway.dart';
import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../composition/layout_composition_planner.dart';
import '../correction/correction_patch_applier.dart';
import '../correction/region_correction_patch.dart';
import '../segmentation/ink_region_segmenter.dart';
import '../segmentation/region_segment.dart';
import '../segmentation/spatial_grid_index.dart';
import '../correction/semantic_correction.dart';
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
import '../recognition/recognition_models.dart';
import '../recognition/recognition_pipeline.dart';
import '../recognition/recognition_repository.dart';
import '../recognition/region_assets.dart';
import '../recognition/semantic_adapter.dart';
import '../recognition/source_ledger.dart';
import '../recognition/structure_recovery.dart';
import '../semantics/semantic_document.dart';
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
      return const RealGenerationFailed(reason: 'empty-page', retryable: false);
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
    return _generateFromAssembly(
      baseScene: baseScene,
      layoutSnapshot: layoutSnapshot,
      fullSnapshot: snapshot,
      semantic: semantic,
      measure: measure,
      tokens: tokens,
      profile: profile,
    );
  }

  /// V3 独立识别入口（R7，spec §10）：识别产物（语义装配 + 只读识别
  /// 账本）直接进入生成链，跳过 response→语义装配段。第 0 步与旧入口
  /// 相同的 page-furniture 剥离 + 空页门控后，按 §6.4-1 做三方一致
  /// 断言（输入即 [recognition] 携带的独立只读账本，不得用 assembly
  /// 自身账目自证），再复用 [run] 第 2 步之后的全部管线。
  ///
  /// [snapshot] 必须是完整捕获快照（含背景对象）——本方法内部执行
  /// 剥离，接收已剥离的 layoutSnapshot 会造成范围不一致（§6.4-4）。
  static Future<RealGenerationOutcome> runFromSemanticAssembly({
    required Scene baseScene,
    required LayoutPageSnapshot snapshot,
    required SemanticAssembly semantic,
    required RecognitionSessionResult recognition,
    required TextMeasureAdapter measure,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
    LayoutProfile profile = LayoutProfile.readability,
  }) async {
    // ---- 0. 布局快照视图：剥离页框/PDF 底图（与旧入口同口径）----
    final layoutObjects = [
      for (final object in snapshot.objects)
        if (object.mobility != SnapshotMobility.background) object,
    ];
    if (layoutObjects.isEmpty && snapshot.inkStrokes.isEmpty) {
      return const RealGenerationFailed(reason: 'empty-page', retryable: false);
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

    // ---- 0.5 §6.4-1 三方一致断言（fail closed，不静默取某一方）----
    try {
      RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: {
          for (final object in layoutObjects) object.sourceId,
          for (final stroke in snapshot.inkStrokes) stroke.sourceId,
        },
        recognition: recognition.ledger,
        assembly: semantic,
      );
    } on StateError catch (error) {
      return RealGenerationFailed(
        reason: 'semantic-contract-broken',
        retryable: false,
        detail: error.message,
      );
    }
    return _generateFromAssembly(
      baseScene: baseScene,
      layoutSnapshot: layoutSnapshot,
      fullSnapshot: snapshot,
      semantic: semantic,
      measure: measure,
      tokens: tokens,
      profile: profile,
      recognition: recognition,
    );
  }

  /// 语义装配之后的共享生成管线（块装配 → planner 枚举 → preflight →
  /// 栏平衡放置 → 物化 → 完整门禁流水线）。
  static Future<RealGenerationOutcome> _generateFromAssembly({
    required Scene baseScene,
    required LayoutPageSnapshot layoutSnapshot,
    required LayoutPageSnapshot fullSnapshot,
    required SemanticAssembly semantic,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
    required LayoutProfile profile,
    RecognitionSessionResult? recognition,
  }) async {
    // ---- 2. 块装配（真实测量；账目不守恒 = 响应未全额认领源 →
    // 协议契约破坏，fail closed）----
    late LayoutBlockAssembly assembly;
    try {
      assembly = const LayoutBlockAssembler().assemble(
        document: semantic.document,
        snapshot: layoutSnapshot,
        measure: measure,
        tokens: tokens,
      );
      if (recognition != null) {
        assembly = SmartLayoutCandidateMaterializer.composeNativeGroups(
          baseScene,
          assembly,
        );
      }
    } on StateError catch (error) {
      return RealGenerationFailed(
        reason: 'semantic-contract-broken',
        retryable: false,
        detail: error.message,
      );
    }

    // ---- 3. 页内容区：页框优先，缺省按内容包围盒；统一 inset 边距 ----
    final pageFrame = fullSnapshot.pageBounds ?? fullSnapshot.contentBounds;
    if (pageFrame == null) {
      return const RealGenerationFailed(reason: 'empty-page', retryable: false);
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
    // 文字按可读栏宽实测，图片按源显示尺寸计量；小图不豁免稀疏门禁。
    var contentBlockCount = 0;
    var textMeasuredHeight = 0.0;
    var figureMeasuredHeight = 0.0;
    var hasFigureContent = false;
    for (final block in assembly.blocks) {
      if (block.isPreservedLike) continue;
      contentBlockCount++;
      final figure = block.figure;
      if (figure != null && !figure.missingAsset) {
        hasFigureContent = true;
        if (figure.displayWidth != null && figure.displayAspectRatio > 0) {
          figureMeasuredHeight +=
              figure.widthInColumn(pageContent.width) /
              figure.displayAspectRatio;
        }
      }
      final text = block.text;
      if (text != null) {
        textMeasuredHeight += measure
            .measure(
              text: text.text,
              fontFamily: text.fontFamily,
              fontSize: text.fontSize,
              lineHeight: text.lineHeight,
              maxWidth: pageContent.width.clamp(1, tokens.maxLineLength),
              direction: text.direction == TextDirectionSpec.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            )
            .height;
      }
    }
    final enumeration = const LayoutCompositionPlanner().enumerate(
      constraint: CompositionConstraint(
        contentWidth: pageContent.width,
        contentBlockCount: contentBlockCount,
        contentFillRatio: contentHeight > 0
            ? (textMeasuredHeight / contentHeight).clamp(0.0, 1.0)
            : 0.0,
        hasFigureContent: hasFigureContent,
        figureFillRatio: (figureMeasuredHeight / contentHeight).clamp(0.0, 1.0),
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
      if (recognition != null &&
          ReplacementGuard.check(
            recognition: recognition.ledger,
            unitFactsByUnitId: ReplacementGuard.factsOf(recognition),
            deletedSourceIds: materialized.patch.removes.map(
              (op) => op.elementId,
            ),
            modifiedSourceIds: materialized.patch.updates.map(
              (op) => op.elementId,
            ),
          ).isNotEmpty) {
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
      LayoutSkeleton.mainSide =>
        p.sideOnRight
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

/// 真实会话装配（V3-505C + R7 独立识别入口）：把既有真实模块组装为
/// ViewModel 依赖束——真实 editor/HTTP/识别管线、快照级捕获、真实候选
/// 生成链与 compare-and-commit 提交网关。无 fake provider；[post] 仅供
/// 测试注入传输（生产为 null，走真实 NativeHttpClient）。
///
/// 生命周期：scope 可跨页复用（[setActivePage] 改指新页）；[dispose]
/// 在页面离开时释放 revision tracker 并作废捕获缓存。
class SmartLayoutRealSessionScope {
  SmartLayoutRealSessionScope._({
    required String pageId,
    required this.session,
    required this.repository,
    required this.commitGateway,
    required RecognitionRepository recognitionRepository,
    required SmartLayoutEditorGateway editor,
    required SceneRevisionTracker tracker,
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
    required LayoutProfile profile,
    String? bearerToken,
  }) : _pageId = pageId,
       _recognitionRepository = recognitionRepository,
       _editor = editor,
       _tracker = tracker,
       _measure = measure,
       _tokens = tokens,
       _profile = profile,
       _bearerToken = bearerToken;

  /// 当前作用页（识别/候选重跑共用）；[setActivePage] 切页时随会话
  /// 一并改指新页。
  String _pageId;
  final SmartLayoutSession session;
  final V3AnalysisRepository repository;
  final ValidatedCandidateCommitGateway commitGateway;
  final RecognitionRepository _recognitionRepository;
  final SmartLayoutEditorGateway _editor;
  final SceneRevisionTracker _tracker;
  final TextMeasureAdapter _measure;
  final SmartLayoutDesignTokens _tokens;
  final LayoutProfile _profile;
  final String? _bearerToken;

  /// build() 末尾装配（闭包引用本 scope，构造后一次性注入）。
  late final SmartLayoutSessionDependencies dependencies;

  _RequestCapture? _lastCapture;

  /// 最近一次识别会话（含结算账本；纠错/重跑的事实来源）。
  RecognitionSessionResult? _lastRecognition;

  /// 最近一次语义装配（语义纠错在其文档上重建）。
  SemanticAssembly? _lastSemantic;

  /// 分区纠错的更正区域记录（rerunChain 重识别输入；一次性消费）。
  List<RegionRecord>? _correctedRegionRecords;
  RegionCorrectionPatch? _inverseRegionPatch;

  /// 会话代次（§6.2/§9.8）：识别操作与显式纠错各 +1，单调递增。
  int _generation = 0;
  int _operationCounter = 0;

  /// 纠错捕获上下文（§9.4：correctionHandler 捕获、rerunChain 消费）。
  RecognitionCorrectionContext? _pendingCorrectionContext;

  /// 在途识别管线（取消信号宿主；一个操作一个实例）。
  RecognitionPipeline? _activePipeline;
  bool _disposed = false;

  /// 识别状态播报（spec §10 面板状态枚举；null=无在途播报）。
  final ValueNotifier<String?> _recognitionStatus = ValueNotifier<String?>(
    null,
  );

  /// 当前会话代次（VM §9.8 发布守卫读取）。
  int get currentGeneration => _generation;

  /// 识别状态播报（analyzing 相位的阶段文案/部分完成摘要）。
  ValueListenable<String?> get recognitionStatus => _recognitionStatus;

  bool get isDisposed => _disposed;

  static SmartLayoutRealSessionScope build({
    required MarkdrawController controller,
    required Uri serverUri,
    required String pageId,
    String? bearerToken,
    SmartLayoutHttpPost? post,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
    LayoutProfile profile = LayoutProfile.readability,
    bool useRecognitionPipeline = true,
  }) {
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    final session = SmartLayoutSession(
      editor: editor,
      revisions: tracker,
      pageId: pageId,
    );
    final httpGateway = SmartLayoutHttpGateway(
      serverUri: serverUri,
      post: post,
    );
    final repo = V3AnalysisRepository(http: httpGateway, session: session);
    final commitGateway = ValidatedCandidateCommitGateway(
      editor: editor,
      revisions: tracker,
    );
    final scope = SmartLayoutRealSessionScope._(
      pageId: pageId,
      session: session,
      repository: repo,
      commitGateway: commitGateway,
      recognitionRepository: RecognitionRepository(gateway: httpGateway),
      editor: editor,
      tracker: tracker,
      measure: TextMeasureAdapter(tokens: tokens),
      tokens: tokens,
      profile: profile,
      bearerToken: bearerToken,
    );
    scope.dependencies = SmartLayoutSessionDependencies(
      session: session,
      repository: repo,
      // 生产分析入口（R7 独立识别链）：recognize/v3 管线直出语义装配，
      // 零 v2 视觉链与 /analyze/v3 请求。[useRecognitionPipeline]=false
      // 时回落 requestBuilder+repository 的 HTTP 实验路径（既有基础
      // 设施测试口径）。
      analysisRunner: useRecognitionPipeline
          ? (ticket) => scope._analyzeWithRecognition(ticket)
          : null,
      // 取消回调（§6.1 独立取消信号）：VM 取消 → 在途管线主动取消
      // 在途请求（幂等；未在识别中为空操作）。
      onCancelAnalysis: () {
        scope._generation++;
        scope._activePipeline?.cancel();
      },
      currentRecognitionGeneration: () => scope.currentGeneration,
      requestBuilder: (ticket) async => scope._buildRequest(ticket),
      commitResultBuilder: (candidateId) =>
          throw StateError('真实路径走 commitGateway（compare-and-commit）'),
      // 纠错修正处理（§9.3）：应用修正 → 受影响源集 + 不可变捕获
      // 上下文（rerunChain 消费）。
      correctionHandler: (intent) => scope._applyRecognitionCorrection(intent),
      rerunChain: (affectedSourceIds) =>
          scope._rerunRecognitionChain(affectedSourceIds),
      candidateChain: (response, ticket) =>
          scope._runCandidateChain(response, ticket),
      candidateChainFromDocument: (outcome, ticket) =>
          scope._runCandidateChainFromDocument(outcome, ticket),
      commitGateway: commitGateway,
      bearerToken: bearerToken,
    );
    return scope;
  }

  /// 快照级真实请求装配：pageId + 当前 revision + clean 资产引用 +
  /// typed exactText + 全源 refs；捕获（scene+snapshot+ticket）供
  /// 响应后的生成链同源消费。（实验/测试路径：生产分析走
  /// [_analyzeWithRecognition]，不发送本请求。）
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

  /// 生产分析链（R7 独立识别入口，spec §10）：recognize/v3 管线
  /// （分区 → 区域高清资产 → 批量初读 → 复核 → 结构恢复）→ 语义适配
  /// （结算账本 + §8 装配）→ [SmartLayoutRecognitionSucceeded]。
  /// 零 v2 视觉链、零 `/analyze/v3` 请求。
  ///
  /// 异常映射：
  /// - 用户取消（RecognitionCancelledException）→ cancelled；
  /// - 页面/Scene/票据变化、编辑器释放（四检）→ guard rejected；
  /// - 管线/语义适配契约破坏（StateError）→ badSchema（稳定不可重试，
  ///   V3 失败保留原内容，不回退 V1）；
  /// - 部分完成（区域保留）不是失败：partial 语义随产物下行。
  Future<SmartLayoutAnalysisOutcome> _analyzeWithRecognition(
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
    _lastRecognition = null;
    _lastSemantic = null;
    _correctedRegionRecords = null;
    _pendingCorrectionContext = null;
    _generation++;
    final capture = RecognitionCapture(
      // 页级捕获（spec §6.4：完整捕获源集合=目标页非背景源；多页
      // Scene 不过滤会把他页笔迹计入识别账本，与页级快照三方断言
      // 失配）。文件表保留（图源渲染依赖）。
      scene: _pageScopedScene(scene, _pageId),
      sceneRevision: RecognitionSceneRevision(
        epoch: revision.epoch,
        revision: revision.revision,
        fingerprint: revision.fingerprint.value,
      ),
      contentFingerprint: revision.fingerprint.value,
      operationId: 'rec-op-${++_operationCounter}',
      generation: _generation,
      pageId: _pageId,
    );
    _activePipeline?.cancel();
    final pipeline = RecognitionPipeline(
      repository: _recognitionRepository,
      structureRecoverer: const StructureRecovery(),
    );
    pipeline.onStateChanged = (state) {
      if (capture.generation == _generation &&
          identical(_activePipeline, pipeline)) {
        _reportPipelineState(state);
      }
    };
    _activePipeline = pipeline;
    try {
      final result = await pipeline.run(capture, bearerToken: _bearerToken);
      // 迟到防线：识别期间用户取消/离页/新操作接管/scope 释放。
      if (_disposed || capture.generation != _generation) {
        return const SmartLayoutAnalysisGuardRejected('disposed', 1);
      }
      final decision = session.checkContinuation(ticket);
      if (decision is SmartLayoutGuardRejected) {
        return SmartLayoutAnalysisGuardRejected(decision.reason, 1);
      }
      final adapter = const RecognitionSemanticAdapter();
      final settled = adapter.settle(result);
      final semantic = adapter.assemble(
        settled,
        measure: _measure,
        tokens: _tokens,
      );
      _lastRecognition = settled;
      _lastSemantic = semantic;
      if (settled.partial) {
        _recognitionStatus.value =
            '部分完成（保留 ${settled.ledger.preservedCount} 源'
            '${settled.partialNotes.isEmpty ? '' : '：${settled.partialNotes.first}'}）';
      } else {
        _recognitionStatus.value = null;
      }
      return SmartLayoutRecognitionSucceeded(
        semantic: semantic,
        recognition: settled,
      );
    } on RecognitionCancelledException {
      return const SmartLayoutAnalysisFailed(
        AnalysisFailureKind.cancelled,
        'cancelled',
        1,
      );
    } on StateError catch (error) {
      return SmartLayoutAnalysisFailed(
        AnalysisFailureKind.badSchema,
        error.message,
        1,
      );
    } finally {
      if (identical(_activePipeline, pipeline)) {
        _activePipeline = null;
      }
    }
  }

  /// pipeline 状态 → 面板状态播报（spec §10 状态枚举；assembling 起
  /// 由生成链接管为“正在生成排版”）。
  void _reportPipelineState(RecognitionPipelineState state) {
    if (_disposed) return;
    _recognitionStatus.value = switch (state) {
      RecognitionPipelineState.idle => null,
      RecognitionPipelineState.capturing ||
      RecognitionPipelineState.proposing ||
      RecognitionPipelineState.rendering => '正在准备',
      RecognitionPipelineState.reading => '正在识别',
      RecognitionPipelineState.regrouping => '正在重分组',
      RecognitionPipelineState.verifying => '正在复核',
      RecognitionPipelineState.structuring ||
      RecognitionPipelineState.assembling => '正在恢复结构',
      RecognitionPipelineState.done => '正在生成排版',
    };
  }

  /// 目标页子 Scene（元素按 flowMuse pageId 归属过滤，文件表原样
  /// 保留——图源区域渲染依赖 files）。
  static Scene _pageScopedScene(Scene scene, String pageId) {
    var scoped = Scene();
    for (final element in scene.activeElements) {
      if (element.pageId == pageId) {
        scoped = scoped.addElement(element);
      }
    }
    for (final entry in scene.files.entries) {
      scoped = scoped.addFile(entry.key, entry.value);
    }
    return scoped;
  }

  /// V3 识别产物 → 候选生成链（R7）：票据同源校验后走
  /// [SmartLayoutRealCandidateChain.runFromSemanticAssembly]（第 0 步
  /// page-furniture 剥离 + §6.4 三方一致断言 + 既有生成管线）。
  Future<List<ValidatedCandidate>> _runCandidateChainFromDocument(
    SmartLayoutRecognitionSucceeded outcome,
    SmartLayoutOperationTicket ticket,
  ) async {
    final capture = _lastCapture;
    if (capture == null || !identical(capture.ticket, ticket)) {
      throw StateError('candidate-chain-ticket-mismatch');
    }
    if (!_disposed) {
      _recognitionStatus.value = '正在生成排版';
    }
    final generation =
        await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
          baseScene: capture.scene,
          snapshot: capture.snapshot,
          semantic: outcome.semantic,
          recognition: outcome.recognition,
          measure: _measure,
          tokens: _tokens,
          profile: _profile,
        );
    return _candidatesOf(generation);
  }

  /// 生成链结果 → 候选约定（无解=空候选；其余失败 reason 透传）。
  List<ValidatedCandidate> _candidatesOf(RealGenerationOutcome outcome) {
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

  /// 纠错修正处理（§9.3 真实实现）：
  /// - role/order/relation/preserve：语义纠错（§9.2 闭环）——构造
  ///   [SemanticCorrectionPatch] 应用到最近语义文档，重建 assembly 与
  ///   识别账本投影（consume→preserve 仅单向降级，§6.4-3）；
  /// - merge/split：分区纠错——更正区域记录（成员并集/子集重切），
  ///   受影响区域重识别由 rerunChain 执行（§9.6）。
  ///
  /// 每次接受的纠错：新 operationId + `generation+1`（§6.2/§9.6）+
  /// 不可变捕获上下文（§9.4；副作用=会话资产索引失效）。被拒的意图抛
  /// [SmartLayoutCorrectionRejected]（不发布新上下文、不重跑）。
  AffectedSourceSet _applyRecognitionCorrection(RegionCorrectionIntent intent) {
    const empty = AffectedSourceSet(
      regionIds: {},
      strokeSourceIds: {},
      renderAssetKeys: {},
      cropKeys: {},
    );
    if (_disposed) return empty;
    final result = _lastRecognition;
    final semantic = _lastSemantic;
    if (result == null || semantic == null) {
      // 无识别会话（未分析/已复位）：无修正语义，返回空影响集。
      return empty;
    }
    if (result.generation != _generation) {
      throw const SmartLayoutCorrectionRejected('stale-recognition-generation');
    }
    return switch (intent.kind) {
      'merge' ||
      'split' ||
      'undo-region' => _applyRegionCorrection(result, intent),
      'role' ||
      'order' ||
      'relation' ||
      'preserve' => _applySemanticCorrection(result, semantic, intent),
      _ => throw SmartLayoutCorrectionRejected('unknown-kind(${intent.kind})'),
    };
  }

  /// 分区纠错（merge/split）：更正区域记录 + §9.3 影响集（before 受触
  /// ∪ after 新建；笔画=成员并集）+ §9.4 捕获。
  AffectedSourceSet _applyRegionCorrection(
    RecognitionSessionResult result,
    RegionCorrectionIntent intent,
  ) {
    final recordsByRegionId = {
      for (final record in result.regionRecords) record.regionId: record,
    };
    if (_correctedRegionRecords != null) {
      throw const SmartLayoutCorrectionRejected('correction-in-progress');
    }
    final strokes = result.scene.activeElements
        .whereType<FreedrawElement>()
        .toList();
    final bySource = {for (final stroke in strokes) stroke.id.value: stroke};
    final columnOf = <String, int>{
      for (final segment in InkRegionSegmenter().segment(strokes))
        for (final id in segment.strokeIds) id: segment.columnIndex,
    };
    final state = SegmentationState(
      revision: _generation,
      regions: [
        for (final r in result.regionRecords)
          RegionSegment(
            id: r.regionId,
            strokeIds: r.targetSourceIds,
            left: r.bounds.left,
            top: r.bounds.top,
            width: r.bounds.width,
            height: r.bounds.height,
            lineDirection: SegmentLineDirection.horizontal,
            columnIndex: columnOf[r.targetSourceIds.first] ?? 0,
            skewRadians: 0,
            localScale: r.localLineHeight,
            preservedReason:
                r.targetSourceIds.any((id) => bySource[id]?.locked ?? true)
                ? RegionPreservedReason.lowConfidence
                : null,
          ),
      ],
      strokeBoxes: {
        for (final s in strokes)
          s.id.value: StrokeBox(
            id: s.id.value,
            left: conservativeVisualBounds(s).left,
            top: conservativeVisualBounds(s).top,
            width: conservativeVisualBounds(s).width,
            height: conservativeVisualBounds(s).height,
          ),
      },
    );
    final RegionCorrectionPatch patch;
    if (intent.kind == 'merge') {
      if (intent.subjectIds.toSet().length < 2 ||
          intent.subjectIds.toSet().length != intent.subjectIds.length) {
        throw const SmartLayoutCorrectionRejected('merge-needs-two-regions');
      }
      final members = <RegionRecord>[];
      for (final regionId in intent.subjectIds) {
        final record = recordsByRegionId[regionId];
        if (record == null) {
          throw SmartLayoutCorrectionRejected('unknown-region($regionId)');
        }
        members.add(record);
      }
      patch = MergeRegionsPatch(
        baseRevision: state.revision,
        membersByRegionId: {
          for (final r in members) r.regionId: r.targetSourceIds,
        },
      );
    } else if (intent.kind == 'undo-region') {
      final inverse = _inverseRegionPatch;
      if (inverse == null) {
        throw const SmartLayoutCorrectionRejected('no-region-inverse');
      }
      patch = inverse;
    } else {
      if (intent.subjectIds.length != 1) {
        throw const SmartLayoutCorrectionRejected('split-needs-one-region');
      }
      final regionId = intent.subjectIds.single;
      final record = recordsByRegionId[regionId];
      if (record == null) {
        throw SmartLayoutCorrectionRejected('unknown-region($regionId)');
      }
      final subsets = _parseSplitSubsets(intent.detail, record);
      patch = SplitRegionPatch(
        baseRevision: state.revision,
        regionId: regionId,
        regionStrokeIdsSnapshot: record.targetSourceIds,
        subsets: [for (final subset in subsets) subset.toList()],
      );
    }
    const applier = CorrectionPatchApplier();
    final applied = applier.apply(state, patch);
    if (!applied.accepted) {
      throw SmartLayoutCorrectionRejected(applied.rejectionReason!);
    }
    final affected = applier.affectedSources(state, patch);
    final beforeRegionIds = affected.regionIds;
    final corrected = [
      for (final r in applied.state!.regions)
        if (!r.strokeIds.any(affected.strokeSourceIds.contains))
          recordsByRegionId[r.id]!
        else
          _rebuildRecord([
            for (final old in result.regionRecords)
              if (old.targetSourceIds.any(r.strokeIds.contains)) old,
          ], r.strokeIds.toSet()),
    ];
    final afterRegionIds = correctionDiffOf(corrected, result.regionRecords);
    final strokeIds = <String>{
      for (final record in recordsByRegionId.values)
        if (beforeRegionIds.contains(record.regionId))
          ...record.targetSourceIds,
    };
    _generation++;
    _inverseRegionPatch = applied.inverse;
    _pendingCorrectionContext = RecognitionCorrectionContext.capture(
      generation: _generation,
      operationId: 'rec-cor-${++_operationCounter}',
      session: result,
      beforeRegionIds: beforeRegionIds,
      afterRegionIds: afterRegionIds,
      strokeSourceIds: strokeIds,
    );
    _correctedRegionRecords = List.unmodifiable(corrected);
    return AffectedSourceSet(
      regionIds: Set.unmodifiable(beforeRegionIds.union(afterRegionIds)),
      strokeSourceIds: Set.unmodifiable(strokeIds),
      renderAssetKeys: _pendingCorrectionContext!.affected.invalidatedAssetIds,
      cropKeys: const {},
    );
  }

  /// 新建区域 id = 更正后出现、更正前不存在的区域 id。
  static Set<String> correctionDiffOf(
    List<RegionRecord> corrected,
    List<RegionRecord> previous,
  ) {
    final previousIds = {for (final record in previous) record.regionId};
    return {
      for (final record in corrected)
        if (!previousIds.contains(record.regionId)) record.regionId,
    };
  }

  /// split 子集解析：detail 为 JSON 数组的数组（笔画 source id 分组）；
  /// 必须恰覆盖原区域成员、组组不相交、无空组。
  List<Set<String>> _parseSplitSubsets(String detail, RegionRecord record) {
    Object? decoded;
    try {
      decoded = jsonDecode(detail);
    } on FormatException {
      throw const SmartLayoutCorrectionRejected('split-detail-not-json');
    }
    if (decoded is! List || decoded.length < 2) {
      throw const SmartLayoutCorrectionRejected('split-detail-empty');
    }
    final subsets = <Set<String>>[];
    final seen = <String>{};
    for (final entry in decoded) {
      if (entry is! List || entry.isEmpty) {
        throw const SmartLayoutCorrectionRejected('split-detail-invalid');
      }
      final subset = <String>{};
      for (final id in entry) {
        if (id is! String) {
          throw const SmartLayoutCorrectionRejected('split-detail-invalid');
        }
        subset.add(id);
      }
      if (subset.length != entry.length) {
        throw const SmartLayoutCorrectionRejected('split-detail-duplicate');
      }
      if (subset.any(seen.contains)) {
        throw const SmartLayoutCorrectionRejected('split-detail-overlap');
      }
      seen.addAll(subset);
      subsets.add(subset);
    }
    final members = record.targetSourceIds.toSet();
    if (seen.length != members.length || !members.containsAll(seen)) {
      throw SmartLayoutCorrectionRejected(
        'split-detail-membership(${seen.length}/${members.length})',
      );
    }
    return subsets;
  }

  /// 更正区域记录重建：成员排序后 `r:<最小 sourceId>` 稳定 id（§1 约定）、
  /// 外框并集、行高取成员最小正值（保守）。
  RegionRecord _rebuildRecord(
    List<RegionRecord> sources,
    Set<String> targetIds,
  ) {
    final ids = targetIds.toList()..sort();
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    var lineHeight = double.infinity;
    final elements = {
      for (final e in _lastRecognition!.scene.activeElements) e.id.value: e,
    };
    for (final id in ids) {
      final element = elements[id];
      if (element == null) {
        throw const SmartLayoutCorrectionRejected('correction-source-missing');
      }
      final bounds = conservativeVisualBounds(element);
      left = bounds.left < left ? bounds.left : left;
      top = bounds.top < top ? bounds.top : top;
      right = bounds.left + bounds.width > right
          ? bounds.left + bounds.width
          : right;
      bottom = bounds.top + bounds.height > bottom
          ? bounds.top + bounds.height
          : bottom;
    }
    for (final record in sources) {
      if (record.localLineHeight > 0 && record.localLineHeight < lineHeight) {
        lineHeight = record.localLineHeight;
      }
    }
    return RegionRecord(
      regionId: 'r:${ids.first}',
      bounds: RecognitionBounds(
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
      ),
      targetSourceIds: List.unmodifiable(ids),
      localLineHeight: lineHeight == double.infinity ? 1.0 : lineHeight,
    );
  }

  /// 语义纠错（§9.2 闭环）：构造 patch → 应用 → 文档 consumed/preserved
  /// 重投影为一致 assembly + 识别账本同步（preserve 单向降级/撤销保留
  /// 重建账本，用户显式代次按 §6.4 重新验证）。
  AffectedSourceSet _applySemanticCorrection(
    RecognitionSessionResult result,
    SemanticAssembly semantic,
    RegionCorrectionIntent intent,
  ) {
    final document = semantic.document;
    final patch = _semanticPatchOf(document, intent);
    final outcome = const SemanticPatchApplier().apply(document, patch);
    if (!outcome.accepted) {
      throw SmartLayoutCorrectionRejected(
        outcome.rejection ?? 'correction-rejected',
      );
    }
    final nextDocument = outcome.document!;
    final nextLedger = _ledgerForDocument(result, nextDocument);
    var coverage = SourceCoverageLedger.pending([
      ...nextDocument.consumedSourceIds,
      ...nextDocument.preservedSourceIds,
    ]);
    coverage = coverage
        .markConsumed(nextDocument.consumedSourceIds)
        .markPreserved(nextDocument.preservedSourceIds);
    _generation++;
    _pendingCorrectionContext = RecognitionCorrectionContext.capture(
      generation: _generation,
      operationId: 'rec-cor-${++_operationCounter}',
      session: result,
      beforeRegionIds: const {},
      afterRegionIds: const {},
      strokeSourceIds: patch is PreserveSemanticSourcesPatch
          ? patch.sourceIds.toSet()
          : const {},
    );
    _lastRecognition = result.copyWith(
      ledger: nextLedger,
      generation: _generation,
      operationId: _pendingCorrectionContext!.operationId,
    );
    _lastSemantic = SemanticAssembly(document: nextDocument, ledger: coverage);
    _correctedRegionRecords = null;
    return AffectedSourceSet(
      regionIds: const {},
      strokeSourceIds: Set.unmodifiable(
        _pendingCorrectionContext!.affected.strokeSourceIds,
      ),
      renderAssetKeys: const {},
      cropKeys: const {},
    );
  }

  /// 纠错后文档 → 识别账本同步（§6.4-3：自动处理禁止 preserve→consume
  /// 反向升级；用户显式纠错=新代次，按文档终态重建并断言闭合）。
  SourceLedger _ledgerForDocument(
    RecognitionSessionResult result,
    SemanticDocument document,
  ) {
    var ledger = SourceLedger.register([
      ...document.consumedSourceIds,
      ...document.preservedSourceIds,
    ]);
    ledger = ledger.registerUnits([
      for (final block in document.blocks) block.id,
    ]);
    final consumed = document.consumedSourceIds.toSet();
    final facts = ReplacementGuard.factsOf(result);
    for (final block in document.blocks) {
      for (final sourceId in block.sourceIds) {
        if (consumed.contains(sourceId)) {
          if (result.ledger.entryOf(sourceId).status ==
              SourceLedgerStatus.preserved) {
            final unit = facts[block.id];
            final source = result.scene.activeElements
                .where((e) => e.id.value == sourceId)
                .firstOrNull;
            final allowed = unit != null
                ? ConversionAdmission.check(
                        statusConfirmedRecognized: unit.conflictsResolved,
                        text: unit.text,
                        unitSourceIds: block.sourceIds.toSet(),
                        regionTargetSourceIds: unit.regionTargetSourceIds,
                        sourceGuards: unit.sourceGuards,
                        conflictsResolved: unit.conflictsResolved,
                        versionValid: unit.versionValid,
                      ) ==
                      null
                : source != null &&
                      !source.locked &&
                      (source is TextElement || source is ImageElement);
            if (!allowed) {
              throw const SmartLayoutCorrectionRejected(
                'unpreserve-admission-failed',
              );
            }
          }
          ledger = ledger.consume(sourceId, block.id);
        }
      }
    }
    for (final sourceId in document.preservedSourceIds) {
      ledger = ledger.preserve(
        sourceId,
        result.ledger.entryOf(sourceId).reason ?? SourcePreserveReason.userKept,
      );
    }
    return ledger..assertAllSettled();
  }

  /// 修正意图 → 语义 patch（baseRevision=当前文档；fromRole/oldOrder/
  /// oldRelations 取当前值，过期即拒）。
  SemanticCorrectionPatch _semanticPatchOf(
    SemanticDocument document,
    RegionCorrectionIntent intent,
  ) {
    final base = SemanticRevisionRef.of(document);
    switch (intent.kind) {
      case 'role':
        if (intent.subjectIds.length != 1) {
          throw const SmartLayoutCorrectionRejected('role-needs-one-block');
        }
        final block = document.blocks
            .where((b) => b.id == intent.subjectIds.single)
            .firstOrNull;
        if (block == null) {
          throw SmartLayoutCorrectionRejected(
            'unknown-block(${intent.subjectIds.single})',
          );
        }
        final toRole = _roleFromWire(intent.detail);
        if (toRole == null) {
          throw SmartLayoutCorrectionRejected('unknown-role(${intent.detail})');
        }
        return SetSemanticRolePatch(
          baseRevision: base,
          blockId: block.id,
          fromRole: block.role,
          toRole: toRole,
        );
      case 'order':
        return ReorderSemanticPatch(
          baseRevision: base,
          oldOrder: document.readingOrder.orderedBlockIds,
          newOrder: intent.subjectIds,
        );
      case 'relation':
        if (intent.subjectIds.length != 1) {
          throw const SmartLayoutCorrectionRejected('relation-needs-one-block');
        }
        final block = document.blocks
            .where((b) => b.id == intent.subjectIds.single)
            .firstOrNull;
        if (block == null) {
          throw SmartLayoutCorrectionRejected(
            'unknown-block(${intent.subjectIds.single})',
          );
        }
        final oldRelations = <({String type, String targetBlockId})>[];
        for (final raw in block.extras['relations'] as List? ?? const []) {
          final relation = raw as Map<String, Object?>;
          oldRelations.add((
            type: relation['type'] as String,
            targetBlockId: relation['targetBlockId'] as String,
          ));
        }
        return SetSemanticRelationsPatch(
          baseRevision: base,
          blockId: block.id,
          oldRelations: oldRelations,
          newRelations: _parseRelations(intent.detail),
        );
      case 'preserve':
        if (intent.subjectIds.isEmpty) {
          throw const SmartLayoutCorrectionRejected('preserve-needs-sources');
        }
        return PreserveSemanticSourcesPatch(
          baseRevision: base,
          sourceIds: intent.subjectIds,
          toPreserved: intent.detail != 'false',
        );
      default:
        throw StateError('unreachable');
    }
  }

  /// role 意图 detail（wire 名）→ [SemanticRole]；unknown 语义角色不
  /// 经纠错入口设置（保留语义走 preserve 意图）。
  SemanticRole? _roleFromWire(String wire) {
    for (final role in SemanticRole.values) {
      if (role.wireName == wire) {
        return role == SemanticRole.unknown ? null : role;
      }
    }
    return null;
  }

  /// relation 意图 detail：JSON `[{type, targetBlockId}]`。
  List<({String type, String targetBlockId})> _parseRelations(String detail) {
    Object? decoded;
    try {
      decoded = jsonDecode(detail);
    } on FormatException {
      throw const SmartLayoutCorrectionRejected('relation-detail-not-json');
    }
    if (decoded is! List) {
      throw const SmartLayoutCorrectionRejected('relation-detail-invalid');
    }
    if (decoded.any(
      (entry) =>
          entry is! Map<String, Object?> ||
          entry['type'] is! String ||
          entry['targetBlockId'] is! String,
    )) {
      throw const SmartLayoutCorrectionRejected('relation-detail-invalid');
    }
    return [
      for (final entry in decoded.cast<Map<String, Object?>>())
        (
          type: entry['type'] as String,
          targetBlockId: entry['targetBlockId'] as String,
        ),
    ];
  }

  /// 纠错最小重跑（§9.5/§9.6）：一次性消费捕获上下文；
  /// - 语义纠错：以重建后的语义装配走 [runFromSemanticAssembly]（当前
  ///   Scene 重提取快照，三方一致断言把守）；
  /// - 分区纠错：更正区域重识别（RegionAssetBuilder + 一次 read 请求，
  ///   未触区域沿用既有结果）→ 结构恢复 → settle/assemble → 生成。
  ///
  /// 代次过期（捕获后又有新纠错/新分析接管）→ 无产出（空列表；VM 侧
  /// §9.8 守卫保证不清空较新代候选）。Scene 与捕获失配（悬空 source）
  /// 按无产出处理——空列表如实呈现，不伪装成功。
  Future<List<ValidatedCandidate>> _rerunRecognitionChain(
    Set<String> affectedSourceIds,
  ) async {
    final context = _pendingCorrectionContext;
    if (context == null || _disposed) return const [];
    if (!context.isCurrent(_generation)) return const [];
    _pendingCorrectionContext = null;
    try {
      final revision = _tracker.isDisposed ? null : _tracker.current;
      if (revision == null) return const [];
      final previousRevision = _lastRecognition?.sceneRevision;
      if (previousRevision == null ||
          previousRevision.epoch != revision.epoch ||
          previousRevision.revision != revision.revision ||
          previousRevision.fingerprint != revision.fingerprint.value) {
        return const [];
      }
      final scene = _editor.currentScene;
      final snapshot = const SnapshotExtractor().extract(
        scene: scene,
        pageId: _pageId,
        sceneRevision: revision,
      );
      final correctedRecords = _correctedRegionRecords;
      RecognitionSessionResult recognition;
      SemanticAssembly semantic;
      if (correctedRecords != null) {
        final reread = await _rerecognizeCorrectedRegions(
          context,
          correctedRecords,
        );
        if (reread == null ||
            _disposed ||
            !context.isCurrent(_generation) ||
            _tracker.isDisposed ||
            _tracker.current != revision) {
          return const [];
        }
        final adapter = const RecognitionSemanticAdapter();
        recognition = adapter.settle(reread);
        semantic = adapter.assemble(
          recognition,
          measure: _measure,
          tokens: _tokens,
        );
        _lastRecognition = recognition;
        _lastSemantic = semantic;
        _correctedRegionRecords = null;
      } else {
        recognition = _lastRecognition!;
        semantic = _lastSemantic!;
      }
      final outcome =
          await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
            baseScene: scene,
            snapshot: snapshot,
            semantic: semantic,
            recognition: recognition,
            measure: _measure,
            tokens: _tokens,
            profile: _profile,
          );
      final candidates = _candidatesOf(outcome);
      if (_disposed ||
          !context.isCurrent(_generation) ||
          _tracker.isDisposed ||
          _tracker.current != revision) {
        for (final candidate in candidates) {
          candidate.dispose();
        }
        return const [];
      }
      return candidates;
    } on StateError {
      return const [];
    }
  }

  /// 分区纠错复用正式管线：新代次预算、分批、复核与取消全部同路；
  /// 未触区域沿用结果及有效资产，只有受影响成员重新渲染和识别。
  Future<RecognitionSessionResult?> _rerecognizeCorrectedRegions(
    RecognitionCorrectionContext context,
    List<RegionRecord> correctedRecords,
  ) async {
    final previous = _lastRecognition;
    if (previous == null) return null;
    final strokes = {
      for (final element in previous.scene.activeElements)
        if (element is FreedrawElement) element.id.value: element,
    };
    final partitions = <RegionPartition>[];
    for (final record in correctedRecords) {
      if (record.targetSourceIds.any((id) => !strokes.containsKey(id))) {
        throw StateError('correction-source-missing');
      }
      partitions.add(
        RegionPartition(
          record: record,
          strokes: [for (final id in record.targetSourceIds) strokes[id]!],
        ),
      );
    }
    final capture = RecognitionCapture(
      scene: previous.scene,
      sceneRevision: previous.sceneRevision,
      contentFingerprint: previous.contentFingerprint,
      operationId: context.operationId,
      generation: context.generation,
      pageId: previous.pageId,
    );
    _activePipeline?.cancel();
    final pipeline = RecognitionPipeline(
      repository: _recognitionRepository,
      structureRecoverer: const StructureRecovery(),
    );
    _activePipeline = pipeline;
    try {
      return await pipeline.run(
        capture,
        bearerToken: _bearerToken,
        correctedPartitions: partitions,
        previous: previous,
        affectedSourceIds: context.affected.strokeSourceIds,
      );
    } on RecognitionCancelledException {
      return null;
    } finally {
      if (identical(_activePipeline, pipeline)) _activePipeline = null;
    }
  }

  /// 旧入口候选生成链（response 路径，实验/测试）：捕获同源校验
  /// （票据不一致 = 离页/取消/重试后的迟到响应 → StateError fail
  /// closed）后走 [SmartLayoutRealCandidateChain.run]。
  Future<List<ValidatedCandidate>> _runCandidateChain(
    SmartLayoutV3Response response,
    SmartLayoutOperationTicket ticket,
  ) async {
    final capture = _lastCapture;
    if (capture == null || !identical(capture.ticket, ticket)) {
      throw StateError('candidate-chain-ticket-mismatch');
    }
    final outcome = await SmartLayoutRealCandidateChain.run(
      baseScene: capture.scene,
      snapshot: capture.snapshot,
      response: response,
      measure: _measure,
      tokens: _tokens,
      profile: _profile,
    );
    return _candidatesOf(outcome);
  }

  /// 用户切换页面（离页防线）：scope 改指新页（识别、候选重跑都作用于
  /// 新页号）并作废未完成的捕获与识别缓存（旧票据续作由会话守卫拒绝）。
  ///
  /// 面板重开复用本 scope：终态会话（applied/cancelled/failed）在此
  /// 复位为 idle——新面板的 VM 初始相位与状态机若错位，点开始将在
  /// beginOperation 静默抛非法迁移（零反馈死按钮）。在途态不动。
  void setActivePage(String pageId) {
    _activePipeline?.cancel();
    _generation++;
    _pageId = pageId;
    _lastCapture = null;
    _lastRecognition = null;
    _lastSemantic = null;
    _correctedRegionRecords = null;
    _pendingCorrectionContext = null;
    _recognitionStatus.value = null;
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
  /// 释放）；此处作废捕获/识别缓存并释放 revision tracker。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lastCapture = null;
    _lastRecognition = null;
    _lastSemantic = null;
    _correctedRegionRecords = null;
    _pendingCorrectionContext = null;
    _activePipeline?.cancel();
    _activePipeline = null;
    _recognitionStatus.dispose();
    _tracker.dispose();
  }
}
