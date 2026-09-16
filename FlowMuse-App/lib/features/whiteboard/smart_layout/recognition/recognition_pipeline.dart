library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';

/// 识别管线状态机与编排（spec §6.1/§6.2/§6.3）。
///
/// 状态：idle → capturing → proposing → rendering → reading →
/// regrouping → verifying → structuring → assembling → done。
/// **顺序约束（计划书 §3.4）：先做至多一轮区域重分组得到最终复核区域，
/// 再发复核请求**——regrouping 在 verifying 之前。
///
/// 取消检查点：capture 后、分区后、每张资产生成后、每批请求派发前、
/// 每批返回后、结构请求前后、装配前；检查点间最长不可取消窗口=单次请求
/// （服务端 ctx 取消 + 仓库侧总预算计时器兜底）。

enum RecognitionPipelineState {
  idle,
  capturing,
  proposing,
  rendering,
  reading,
  regrouping,
  verifying,
  structuring,
  assembling,
  done,
}

/// 一次识别操作的捕获输入（§1：操作身份 + 版本三元组 + 内容指纹）。
class RecognitionCapture {
  const RecognitionCapture({
    required this.scene,
    required this.sceneRevision,
    required this.contentFingerprint,
    required this.operationId,
    required this.generation,
    required this.pageId,
  });

  /// 完整捕获快照（含原生元素；背景剥离由结构/装配阶段处理）。
  final Scene scene;
  final RecognitionSceneRevision sceneRevision;
  final String contentFingerprint;
  final String operationId;
  final int generation;
  final String pageId;
}

/// 单区域最终识别状态（初读 + 可能的复核覆盖后）。
class RegionReadOutcome {
  const RegionReadOutcome({
    required this.regionId,
    required this.status,
    required this.targetSourceIds,
    this.text,
    this.confidence,
    this.diagnostics = const [],
    this.verified = false,
  });

  final String regionId;
  final RecognitionRegionStatus status;

  /// 该区域待消费源集合（= 区域 target 全集）。
  final List<String> targetSourceIds;
  final String? text;
  final double? confidence;
  final List<String> diagnostics;

  /// 是否经复核确认。
  final bool verified;
}

/// 会话识别产物（R6 语义适配与 R7 会话接线的输入）。
class RecognitionSessionResult {
  const RecognitionSessionResult({
    required this.operationId,
    required this.generation,
    required this.pageId,
    required this.sceneRevision,
    required this.contentFingerprint,
    required this.regionRecords,
    required this.regionOutcomes,
    required this.ledger,
    required this.assetIndex,
    this.structureResult,
    this.partial = false,
    this.partialNotes = const [],
  });

  final String operationId;
  final int generation;
  final String pageId;
  final RecognitionSceneRevision sceneRevision;
  final String contentFingerprint;

  /// 最终生效的区域记录（含超限拆分后的子区域）。
  final List<RegionRecord> regionRecords;
  final Map<String, RegionReadOutcome> regionOutcomes;

  /// 识别期源账本：unreadable/nonText/missing/assetFailed/budgetExceeded
  /// 已 preserve；recognized/uncertain 保持 pending，待语义适配 consume。
  final SourceLedger ledger;
  final RegionAssetIndex assetIndex;

  /// R5 结构恢复结果（未接线时为 null）。
  final Object? structureResult;

  /// 部分完成（有区域被保留）及其原因。
  final bool partial;
  final List<String> partialNotes;
}

/// 取消异常（携带已安全结算的部分会话；§6.1 部分预览）。
class RecognitionCancelledException implements Exception {
  RecognitionCancelledException(this.partialSession);

  final RecognitionSessionResult? partialSession;

  @override
  String toString() =>
      'RecognitionCancelledException(partial: ${partialSession != null})';
}

/// 复核触发条件（spec §6.1；与 §7 结构触发表分离，不混用）。
enum RecognitionVerifyTrigger {
  lowConfidence,
  emptyTextForTextRegion,
  nonTextButTextLike,
  brokenNumbering,
  shapeMismatch,
}

/// R5 结构恢复 seam：pipeline 在 structuring 阶段调用；实现方按 §7
/// 触发条件决定是否发结构请求。
abstract class RecognitionStructureRecoverer {
  Future<Object?> recover(RecognitionStructureInput input);
}

/// 结构恢复输入（R5 消费）。
class RecognitionStructureInput {
  const RecognitionStructureInput({
    required this.capture,
    required this.regionRecords,
    required this.regionOutcomes,
    required this.remainingBudgetOf,
    required this.sendStructureRequest,
  });

  final RecognitionCapture capture;
  final List<RegionRecord> regionRecords;
  final Map<String, RegionReadOutcome> regionOutcomes;

  /// 剩余总预算（真实计时器）。
  final Duration Function() remainingBudgetOf;

  /// 发一次结构请求的 seam（预算计数/取消/重试由 pipeline 统一执行）。
  final Future<RecognitionStructureResponse?> Function(
    RecognitionStructureRequest request,
  )
  sendStructureRequest;
}

/// 识别管线。一个实例一个操作（一个 operationId 一个预算，§6.2）；
/// 显式用户纠错=新实例+新预算+generation+1，实例不可复用。
class RecognitionPipeline {
  RecognitionPipeline({
    required RecognitionRepository repository,
    RecognitionStructureRecoverer? structureRecoverer,
    this.verifyConfidenceThreshold = 0.6,
    this.verifyMergeGapLineHeights = 0.5,
    String Function()? requestIdFactory,
  }) : _repository = repository,
       _structureRecoverer = structureRecoverer,
       _requestIdFactory = requestIdFactory ?? _defaultRequestIdFactory;

  final RecognitionRepository _repository;
  final RecognitionStructureRecoverer? _structureRecoverer;
  final double verifyConfidenceThreshold;
  final double verifyMergeGapLineHeights;
  final String Function() _requestIdFactory;

  static int _requestCounter = 0;
  static String _defaultRequestIdFactory() {
    _requestCounter++;
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'req-$now-$_requestCounter';
  }

  RecognitionPipelineState _state = RecognitionPipelineState.idle;
  bool _cancelRequested = false;
  NativeHttpCancelToken? _cancelToken;
  RecognitionBudget _budget = const RecognitionBudget();
  final Map<String, RecognitionResponse> _responseCache = {};
  final Map<String, RegionAsset> _assetByRegion = {};
  final Map<String, RegionReadOutcome> _outcomes = {};
  int _cacheHits = 0;
  List<RegionPartition> _effectivePartitions = const [];

  RecognitionPipelineState get state => _state;

  final List<RecognitionPipelineState> _stateHistory = [];

  /// 状态迁移历史（测试与诊断）。
  List<RecognitionPipelineState> get stateHistory =>
      List.unmodifiable(_stateHistory);

  /// 会话内缓存命中数（§6.3：命中不计调用预算）。
  int get cacheHitCount => _cacheHits;

  /// 请求取消：置位标记并主动取消在途请求。
  void cancel() {
    _cancelRequested = true;
    _cancelToken?.cancel();
  }

  void _transition(RecognitionPipelineState next) {
    _state = next;
    _stateHistory.add(next);
  }

  void _checkCancelled() {
    if (_cancelRequested) {
      throw RecognitionCancelledException(null);
    }
  }

  /// 执行一次识别操作。成功返回 [RecognitionSessionResult]（可含部分
  /// 完成）；被取消抛 [RecognitionCancelledException]。
  Future<RecognitionSessionResult> run(
    RecognitionCapture capture, {
    RecognitionBudget budget = const RecognitionBudget(),
    String? bearerToken,
  }) async {
    if (_state != RecognitionPipelineState.idle) {
      throw StateError('pipeline 实例不可复用（一个操作一个实例）');
    }
    final stopwatch = Stopwatch()..start();
    _cancelToken = NativeHttpCancelToken();
    _budget = budget;
    final partialNotes = <String>[];
    final assetIndex = RegionAssetIndex();

    // ---- capturing：源集合注册（排除背景后的识别源 = 全部活动笔迹）----
    _transition(RecognitionPipelineState.capturing);
    final strokes = capture.scene.activeElements
        .whereType<FreedrawElement>()
        .toList(growable: false);
    var ledger = SourceLedger.register(
      strokes.map((stroke) => stroke.id.value),
    );
    _checkCancelled();

    // ---- proposing：分区 + 首轮上限 ----
    _transition(RecognitionPipelineState.proposing);
    final partitions = const RegionPartitioner().partition(capture.scene);
    var included = partitions;
    if (partitions.length > budget.firstRoundMaxRegions) {
      included = partitions.take(budget.firstRoundMaxRegions).toList();
      for (final dropped in partitions.skip(budget.firstRoundMaxRegions)) {
        for (final sourceId in dropped.record.targetSourceIds) {
          ledger = ledger.preserve(
            sourceId,
            SourcePreserveReason.budgetExceeded,
          );
        }
        partialNotes.add('区域超首轮上限保留: ${dropped.record.regionId}');
      }
    }
    _checkCancelled();

    // ---- rendering：区域高清资产（逐区域失败隔离；超限一次二分拆分）----
    _transition(RecognitionPipelineState.rendering);
    final regionBuilder = RegionAssetBuilder(capturedScene: capture.scene);
    try {
      for (final partition in included) {
        _checkCancelled();
        final subPartitions = await _buildWithSplit(
          regionBuilder,
          partition,
          budget,
          depth: 0,
        );
        if (subPartitions == null) {
          for (final sourceId in partition.record.targetSourceIds) {
            ledger = ledger.preserve(
              sourceId,
              SourcePreserveReason.assetFailed,
            );
          }
          partialNotes.add('资产失败保留: ${partition.record.regionId}');
          continue;
        }
        _effectivePartitions = [..._effectivePartitions, ...subPartitions];
      }
    } finally {
      regionBuilder.dispose();
    }
    for (final partition in _effectivePartitions) {
      final asset = _assetByRegion[partition.record.regionId];
      if (asset != null) {
        assetIndex.register(asset);
      }
    }
    _checkCancelled();

    // ---- reading：初读（批 ≤8 且编码后 ≤16MiB；missing→保留）----
    _transition(RecognitionPipelineState.reading);
    final batches = _batchRegions(_effectivePartitions, budget);
    for (final batch in batches) {
      _checkCancelled();
      if (!_budget.canSpendModelCall) {
        // 预算不足则不发，该批区域保留（§6.2 执行点）。无响应不是模型
        // 输出——不产生 outcome，不进入复核触发表。
        for (final partition in batch) {
          for (final sourceId in partition.record.targetSourceIds) {
            ledger = ledger.preserve(
              sourceId,
              SourcePreserveReason.budgetExceeded,
            );
          }
          partialNotes.add('模型预算耗尽保留: ${partition.record.regionId}');
        }
        continue;
      }
      final response = await _dispatch(
        capture,
        batch,
        stopwatch: stopwatch,
        bearerToken: bearerToken,
        verify: false,
      );
      if (response == null) {
        // 整批未获有效响应（重试后仍失败/解析失败类）：不可归属即整批
        // 无效，不凭空恢复（§3.2）。无响应不产生 outcome、不触发复核。
        for (final partition in batch) {
          for (final sourceId in partition.record.targetSourceIds) {
            ledger = ledger.preserve(
              sourceId,
              SourcePreserveReason.missingResponse,
            );
          }
          partialNotes.add('批次未获有效响应保留: ${partition.record.regionId}');
        }
        continue;
      }
      _applyBatchResponse(
        batch,
        response as RecognitionBatchResponse,
        ledger,
        partialNotes,
      );
      ledger = _ledgerAfterBatch;
      _checkCancelled();
    }

    // ---- 复核触发评估 → regrouping（至多一轮）→ verifying ----
    final candidates = <RegionPartition, RecognitionVerifyTrigger>{};
    for (final partition in _effectivePartitions) {
      final outcome = _outcomes[partition.record.regionId];
      if (outcome == null) continue;
      final trigger = _verifyTriggerOf(partition, outcome);
      if (trigger != null) {
        candidates[partition] = trigger;
      }
    }
    if (candidates.isNotEmpty) {
      var capped = candidates.entries.toList()
        ..sort((a, b) => a.value.index.compareTo(b.value.index));
      if (capped.length > budget.verifyMaxRegions) {
        capped = capped.sublist(0, budget.verifyMaxRegions);
      }
      // 重分组：相邻候选（间距 < 0.5×行高）合并为同一批复核组；
      // regionId 保持稳定（最终复核区域分组语义）。
      _transition(RecognitionPipelineState.regrouping);
      final groups = _mergeAdjacentCandidates(capped);
      _checkCancelled();
      _transition(RecognitionPipelineState.verifying);
      for (final group in groups) {
        _checkCancelled();
        final response = await _dispatch(
          capture,
          group,
          stopwatch: stopwatch,
          bearerToken: bearerToken,
          verify: true,
        );
        if (response == null) {
          // 复核失败不推翻初读：保持初读结果（§6.1 复核未消解冲突按保留
          // 或初读处理——此处初读已定，保守保持）。
          continue;
        }
        _applyBatchResponse(
          group,
          response as RecognitionBatchResponse,
          ledger,
          partialNotes,
          verified: true,
        );
        ledger = _ledgerAfterBatch;
      }
    }

    // ---- structuring（R5 seam；触发条件由实现方判定）----
    _transition(RecognitionPipelineState.structuring);
    Object? structureResult;
    if (_structureRecoverer != null) {
      _checkCancelled();
      structureResult = await _structureRecoverer.recover(
        RecognitionStructureInput(
          capture: capture,
          regionRecords: [
            for (final partition in _effectivePartitions) partition.record,
          ],
          regionOutcomes: Map.unmodifiable(_outcomes),
          remainingBudgetOf: () => _remaining(stopwatch),
          sendStructureRequest: (request) => _dispatchStructure(
            capture,
            request,
            stopwatch: stopwatch,
            bearerToken: bearerToken,
          ),
        ),
      );
      _checkCancelled();
    }

    // ---- assembling ----
    _transition(RecognitionPipelineState.assembling);
    _checkCancelled();
    _transition(RecognitionPipelineState.done);
    return RecognitionSessionResult(
      operationId: capture.operationId,
      generation: capture.generation,
      pageId: capture.pageId,
      sceneRevision: capture.sceneRevision,
      contentFingerprint: capture.contentFingerprint,
      regionRecords: [
        for (final partition in _effectivePartitions) partition.record,
      ],
      regionOutcomes: Map.unmodifiable(_outcomes),
      ledger: ledger,
      assetIndex: assetIndex,
      structureResult: structureResult,
      partial: ledger.preservedCount > 0 || partialNotes.isNotEmpty,
      partialNotes: List.unmodifiable(partialNotes),
    );
  }

  SourceLedger _ledgerAfterBatch = SourceLedger.register(const []);

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = _budget.remainingOf(stopwatch);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 应用 read/verify 批响应：区域状态入账、终态 preserve。
  void _applyBatchResponse(
    List<RegionPartition> batch,
    RecognitionBatchResponse response,
    SourceLedger ledger,
    List<String> partialNotes, {
    bool verified = false,
  }) {
    var next = ledger;
    final byRegionId = {
      for (final partition in batch) partition.record.regionId: partition,
    };
    for (final region in response.regions) {
      final partition = byRegionId[region.regionId];
      if (partition == null) continue;
      _outcomes[region.regionId] = RegionReadOutcome(
        regionId: region.regionId,
        status: region.status,
        targetSourceIds: partition.record.targetSourceIds,
        text: region.text,
        confidence: region.confidence,
        diagnostics: region.diagnostics,
        verified: verified,
      );
      if (region.status == RecognitionRegionStatus.unreadable ||
          region.status == RecognitionRegionStatus.nonText) {
        for (final sourceId in partition.record.targetSourceIds) {
          next = next.preserve(
            sourceId,
            region.status == RecognitionRegionStatus.unreadable
                ? SourcePreserveReason.unreadable
                : SourcePreserveReason.nonText,
          );
        }
      }
    }
    for (final missingId in response.missingRegionIds) {
      final partition = byRegionId[missingId];
      if (partition == null) continue;
      _outcomes[missingId] =
          _outcomes[missingId] ??
          RegionReadOutcome(
            regionId: missingId,
            status: RecognitionRegionStatus.unreadable,
            targetSourceIds: partition.record.targetSourceIds,
          );
      for (final sourceId in partition.record.targetSourceIds) {
        next = next.preserve(sourceId, SourcePreserveReason.missingResponse);
      }
      partialNotes.add('漏答保留: $missingId');
    }
    _ledgerAfterBatch = next;
  }

  /// 批次组织：≤batchMaxRegions 且编码后请求 JSON 估算 ≤16MiB（按实际
  /// 大小提前拆批，不只计区域数，§3.2）。
  List<List<RegionPartition>> _batchRegions(
    List<RegionPartition> partitions,
    RecognitionBudget budget,
  ) {
    final batches = <List<RegionPartition>>[];
    var current = <RegionPartition>[];
    var currentBytes = 0;
    for (final partition in partitions) {
      final asset = _assetByRegion[partition.record.regionId];
      if (asset == null) continue;
      final imageBytes = (asset.pngBytes.length * 4 / 3).ceil() + 64;
      final overhead = 512 + partition.record.regionId.length;
      final requestBytes = currentBytes + overhead + imageBytes;
      if (current.isNotEmpty &&
          (current.length >= budget.batchMaxRegions ||
              requestBytes > budget.batchMaxRequestBytes)) {
        batches.add(current);
        current = <RegionPartition>[];
        currentBytes = 0;
      }
      current.add(partition);
      currentBytes += overhead + imageBytes;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// 派发一批（read 或 verify）。预算派发前递减；缓存命中不计预算、
  /// 不发请求；重试仅一次且排除解析失败类（invalidProviderResponse /
  /// invalidResponse / invalidRequest）。
  Future<RecognitionResponse?> _dispatch(
    RecognitionCapture capture,
    List<RegionPartition> batch, {
    required Stopwatch stopwatch,
    String? bearerToken,
    bool verify = false,
  }) async {
    if (batch.isEmpty) return null;
    _checkCancelled();
    if (!_budget.canSpendModelCall) {
      return null;
    }
    final isVerify = verify;
    final cacheKey = _cacheKeyOf(capture, batch, isVerify);
    final cached = _responseCache[cacheKey];
    if (cached != null) {
      _cacheHits++;
      return cached;
    }
    var attempts = 0;
    while (true) {
      _checkCancelled();
      _budget = _budget.spendModelCall();
      final request = isVerify
          ? _buildVerifyRequest(capture, batch)
          : _buildReadRequest(capture, batch);
      try {
        final response = await _repository.send(
          request,
          bearerToken: bearerToken,
          cancelToken: _cancelToken,
          remainingBudget: _remaining(stopwatch),
        );
        _responseCache[cacheKey] = response;
        return response;
      } on RecognitionException catch (error) {
        if (error.kind == RecognitionExceptionKind.cancelled) {
          throw RecognitionCancelledException(null);
        }
        final canRetry =
            error.retryable &&
            attempts < _budget.retryPerRequest &&
            error.code != 'invalidProviderResponse' &&
            error.kind != RecognitionExceptionKind.invalidResponse &&
            error.kind != RecognitionExceptionKind.invalidRequest;
        if (!canRetry) {
          return null;
        }
        attempts++;
        if (!_budget.canSpendModelCall) {
          return null;
        }
      }
    }
  }

  /// 结构请求派发（R5 seam 使用；同预算同取消语义）。
  Future<RecognitionStructureResponse?> _dispatchStructure(
    RecognitionCapture capture,
    RecognitionStructureRequest request, {
    required Stopwatch stopwatch,
    String? bearerToken,
  }) async {
    _checkCancelled();
    if (!_budget.canSpendModelCall) {
      return null;
    }
    final cacheKey =
        '${_cacheKeyOf(capture, const [], false)}|structure|${request.textFingerprint}';
    final cached = _responseCache[cacheKey];
    if (cached != null) {
      _cacheHits++;
      return cached as RecognitionStructureResponse;
    }
    var attempts = 0;
    while (true) {
      _checkCancelled();
      _budget = _budget.spendModelCall();
      try {
        final response = await _repository.send(
          request,
          bearerToken: bearerToken,
          cancelToken: _cancelToken,
          remainingBudget: _remaining(stopwatch),
        );
        _responseCache[cacheKey] = response;
        return response as RecognitionStructureResponse;
      } on RecognitionException catch (error) {
        if (error.kind == RecognitionExceptionKind.cancelled) {
          throw RecognitionCancelledException(null);
        }
        final canRetry =
            error.retryable &&
            attempts < _budget.retryPerRequest &&
            error.kind != RecognitionExceptionKind.invalidResponse &&
            error.kind != RecognitionExceptionKind.invalidRequest;
        if (!canRetry) {
          return null;
        }
        attempts++;
        if (!_budget.canSpendModelCall) {
          return null;
        }
      }
    }
  }

  RecognitionReadRequest _buildReadRequest(
    RecognitionCapture capture,
    List<RegionPartition> batch,
  ) {
    return RecognitionReadRequest(
      operationId: capture.operationId,
      requestId: _requestIdFactory(),
      pageId: capture.pageId,
      sceneRevision: capture.sceneRevision,
      contentFingerprint: capture.contentFingerprint,
      generation: capture.generation,
      regions: [
        for (final partition in batch)
          RecognitionRegionImage(
            regionId: partition.record.regionId,
            imagePngBase64: _base64Of(partition),
            imageScale: _assetByRegion[partition.record.regionId]!.scale,
            contextBefore: _finalizedContextBefore(partition),
          ),
      ],
    );
  }

  RecognitionVerifyRequest _buildVerifyRequest(
    RecognitionCapture capture,
    List<RegionPartition> batch,
  ) {
    return RecognitionVerifyRequest(
      operationId: capture.operationId,
      requestId: _requestIdFactory(),
      pageId: capture.pageId,
      sceneRevision: capture.sceneRevision,
      contentFingerprint: capture.contentFingerprint,
      generation: capture.generation,
      regions: [
        for (final partition in batch)
          RecognitionVerifyRegion(
            regionId: partition.record.regionId,
            imagePngBase64: _base64Of(partition),
            imageScale: _assetByRegion[partition.record.regionId]!.scale,
            reason:
                _verifyReasons[partition.record.regionId] ??
                RecognitionVerifyReason.lowConfidence,
            originalText: _outcomes[partition.record.regionId]?.text,
            originalConfidence:
                _outcomes[partition.record.regionId]?.confidence,
          ),
      ],
    );
  }

  final Map<String, RecognitionVerifyReason> _verifyReasons = {};

  String _base64Of(RegionPartition partition) {
    final asset = _assetByRegion[partition.record.regionId];
    if (asset == null) {
      throw StateError('区域 ${partition.record.regionId} 缺少资产（不应进入派发）');
    }
    return base64Encode(asset.pngBytes);
  }

  /// 邻区上下文（§3.2）：来自**已定稿**的相邻区域正文——上方最近区域
  /// 已有识别结果时携带其正文，否则缺省。
  String? _finalizedContextBefore(RegionPartition partition) {
    RegionPartition? closestAbove;
    for (final other in _effectivePartitions) {
      if (other.record.regionId == partition.record.regionId) continue;
      if (other.record.bounds.top + other.record.bounds.height <=
              partition.record.bounds.top &&
          _horizontalOverlap(other.record.bounds, partition.record.bounds) &&
          (closestAbove == null ||
              other.record.bounds.top + other.record.bounds.height >
                  closestAbove.record.bounds.top +
                      closestAbove.record.bounds.height)) {
        closestAbove = other;
      }
    }
    if (closestAbove == null) return null;
    return _outcomes[closestAbove.record.regionId]?.text;
  }

  bool _horizontalOverlap(RecognitionBounds a, RecognitionBounds b) {
    return a.left < b.left + b.width && b.left < a.left + a.width;
  }

  // ---- 复核触发（§6.1 表；与 §7 结构触发表分离）----

  RecognitionVerifyTrigger? _verifyTriggerOf(
    RegionPartition partition,
    RegionReadOutcome outcome,
  ) {
    // 1. 初读置信低于阈值。
    if (outcome.confidence != null &&
        outcome.confidence! < verifyConfidenceThreshold) {
      return RecognitionVerifyTrigger.lowConfidence;
    }
    final text = outcome.text ?? '';
    // 2. 文本形态区域返回空正文（细高外框=文本行形态）。
    if ((outcome.status == RecognitionRegionStatus.recognized ||
            outcome.status == RecognitionRegionStatus.uncertain) &&
        text.trim().isEmpty &&
        partition.record.bounds.height >
            partition.record.localLineHeight * 0.8) {
      return RecognitionVerifyTrigger.emptyTextForTextRegion;
    }
    // 3. 被判 nonText 但局部笔迹形态像文字。
    if (outcome.status == RecognitionRegionStatus.nonText &&
        partition.record.bounds.height < partition.record.localLineHeight * 2 &&
        partition.record.bounds.width > partition.record.localLineHeight * 2) {
      return RecognitionVerifyTrigger.nonTextButTextLike;
    }
    // 4. 编号断裂且空间上有候选续项。
    final leading = leadingNumberOf(text);
    if (leading != null && leading >= 2) {
      final predecessor = _regionAbove(partition);
      if (predecessor == null ||
          leadingNumberOf(_outcomes[predecessor.record.regionId]?.text ?? '') !=
              leading - 1) {
        return RecognitionVerifyTrigger.brokenNumbering;
      }
    }
    // 5. 初读结果与区域形态明显不匹配（超长行但正文极短）。
    if (text.trim().isNotEmpty &&
        partition.record.bounds.width > partition.record.localLineHeight * 40 &&
        text.trim().length < 5) {
      return RecognitionVerifyTrigger.shapeMismatch;
    }
    return null;
  }

  RegionPartition? _regionAbove(RegionPartition partition) {
    RegionPartition? closest;
    for (final other in _effectivePartitions) {
      if (other.record.regionId == partition.record.regionId) continue;
      if (other.record.bounds.top + other.record.bounds.height <=
              partition.record.bounds.top &&
          (closest == null ||
              other.record.bounds.top + other.record.bounds.height >
                  closest.record.bounds.top + closest.record.bounds.height)) {
        closest = other;
      }
    }
    return closest;
  }

  /// 重分组：相邻复核候选（间距 < verifyMergeGapLineHeights×行高）合并为
  /// 同批复核组（至多一轮；regrouping 产物=最终复核区域分组）。
  List<List<RegionPartition>> _mergeAdjacentCandidates(
    List<MapEntry<RegionPartition, RecognitionVerifyTrigger>> candidates,
  ) {
    final sorted = [...candidates]
      ..sort(
        (a, b) => a.key.record.bounds.top.compareTo(b.key.record.bounds.top),
      );
    for (final entry in sorted) {
      _verifyReasons[entry.key.record.regionId] = _reasonOfTrigger(entry.value);
    }
    final groups = <List<RegionPartition>>[];
    for (final entry in sorted) {
      var merged = false;
      for (final group in groups) {
        final last = group.last;
        final lineHeight = math.max(
          last.record.localLineHeight,
          entry.key.record.localLineHeight,
        );
        final gap = SmallStrokeAttribution.gapBetween(
          last.record.bounds,
          entry.key.record.bounds,
        );
        if (gap < verifyMergeGapLineHeights * lineHeight) {
          group.add(entry.key);
          merged = true;
          break;
        }
      }
      if (!merged) {
        groups.add([entry.key]);
      }
    }
    return groups;
  }

  RecognitionVerifyReason _reasonOfTrigger(RecognitionVerifyTrigger trigger) {
    switch (trigger) {
      case RecognitionVerifyTrigger.lowConfidence:
        return RecognitionVerifyReason.lowConfidence;
      case RecognitionVerifyTrigger.emptyTextForTextRegion:
        return RecognitionVerifyReason.suspectedMiss;
      case RecognitionVerifyTrigger.nonTextButTextLike:
        return RecognitionVerifyReason.maybeNonText;
      case RecognitionVerifyTrigger.brokenNumbering:
        return RecognitionVerifyReason.brokenNumbering;
      case RecognitionVerifyTrigger.shapeMismatch:
        return RecognitionVerifyReason.shapeMismatch;
    }
  }

  // ---- 渲染辅助（超限一次二分拆分；不可安全拆分则整块保留）----

  Future<List<RegionPartition>?> _buildWithSplit(
    RegionAssetBuilder builder,
    RegionPartition partition,
    RecognitionBudget budget, {
    required int depth,
  }) async {
    final outcome = await builder.build(partition.record, budget);
    if (outcome is RegionAssetBuilt) {
      _assetByRegion[partition.record.regionId] = outcome.asset;
      return [partition];
    }
    final failed = outcome as RegionAssetFailed;
    if (failed.reason != RegionAssetFailureReason.tooLarge || depth >= 1) {
      return null;
    }
    // 局部分区（§5.2）：按 bounds 中线二分（左/右），成员按中心就近归侧。
    final record = partition.record;
    if (record.targetSourceIds.length < 2) return null;
    final midX = record.bounds.left + record.bounds.width / 2;
    final leftIds = <String>[];
    final rightIds = <String>[];
    for (final sourceId in record.targetSourceIds) {
      final stroke = _strokeOf(partition, sourceId);
      if (stroke == null) return null;
      final centerX = stroke.x + stroke.width / 2;
      if (centerX < midX) {
        leftIds.add(sourceId);
      } else {
        rightIds.add(sourceId);
      }
    }
    if (leftIds.isEmpty || rightIds.isEmpty) return null;
    final subPartitions = <RegionPartition>[];
    for (final ids in [leftIds, rightIds]) {
      final sub = _subPartition(partition, ids);
      if (sub == null) return null;
      final subOutcome = await _buildWithSplit(
        builder,
        sub,
        budget,
        depth: depth + 1,
      );
      if (subOutcome == null) return null;
      subPartitions.addAll(subOutcome);
    }
    return subPartitions;
  }

  RegionPartition? _subPartition(RegionPartition partition, List<String> ids) {
    final strokes = [for (final id in ids) _strokeOf(partition, id)!];
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final stroke in strokes) {
      left = math.min(left, stroke.x);
      top = math.min(top, stroke.y);
      right = math.max(right, stroke.x + stroke.width);
      bottom = math.max(bottom, stroke.y + stroke.height);
    }
    final sortedIds = [...ids]..sort();
    return RegionPartition(
      record: RegionRecord(
        regionId: 'r:${sortedIds.first}',
        bounds: RecognitionBounds(
          left: left,
          top: top,
          width: right - left,
          height: bottom - top,
        ),
        targetSourceIds: List.unmodifiable(sortedIds),
        contextSourceIds: List.unmodifiable(
          partition.record.contextSourceIds
              .where((id) => !sortedIds.contains(id))
              .toList(),
        ),
        localLineHeight: partition.record.localLineHeight,
      ),
      strokes: List.unmodifiable(strokes),
    );
  }

  FreedrawElement? _strokeOf(RegionPartition partition, String sourceId) {
    for (final stroke in partition.strokes) {
      if (stroke.id.value == sourceId) return stroke;
    }
    return null;
  }

  String _cacheKeyOf(
    RecognitionCapture capture,
    List<RegionPartition> batch,
    bool verify,
  ) {
    return [
      capture.contentFingerprint,
      recognitionSchemaVersion,
      if (verify) 'verify' else 'read',
      for (final partition in batch)
        '${partition.record.regionId}:${_assetByRegion[partition.record.regionId]?.pngBytes.length ?? 0}',
    ].join('|');
  }
}

/// 编号前缀（§7 同款正则：编号分隔符后不得紧跟数字，排除 "1.2" 小数）。
int? leadingNumberOf(String text) {
  final match = RegExp(r'^\s*(\d{1,3})[.、)）](?!\d)').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
