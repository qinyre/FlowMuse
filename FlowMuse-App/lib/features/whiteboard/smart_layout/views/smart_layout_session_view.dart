import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/smart_layout_session_state.dart';
import '../session/smart_layout_session_view_model.dart';
import '../recognition/source_ledger.dart';
import '../recognition/recognition_repository.dart';
import '../semantics/semantic_document.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'smart_layout_candidate_view.dart';
import 'smart_layout_preview.dart';

/// 智能排版会话视图（V3-505A 骨架，V3-505C 闭环）：按会话 sealed 相位
/// 渲染——idle（开始）、analyzing（进度 + 取消）、reviewing（候选卡 +
/// 应用/纠错/取消，无解时重新分析）、applying（进度 + 取消）、
/// applied（完成 + 复位）、cancelled/failed（信息 + 重试/复位）。
///
/// 视图只持有缩放/块选择等展示状态，不持有业务在途 future，一切启用条件
/// 来自 [SmartLayoutSessionUiState] 的唯一判定（canStartAnalysis 等），
/// 一切动作只转发 ViewModel 方法。
///
/// V3-505C 可访问性闭环：
/// - 无鼠标流程：Shortcuts/Actions 全键盘驱动——Enter/Space 开始或
///   应用、Escape 取消或复位、上下方向键在候选间移动选择；每个相位
///   首要控件 autofocus，相位切换即焦点迁移；
/// - 焦点恢复：会话结束（applied/cancelled 复位完成）把焦点交还
///   [restoreFocusNode]（离场控件不再持有焦点）；
/// - Semantics：相位播报 liveRegion（读屏跟随状态迁移），候选卡/按钮
///   均有语义标签；
/// - 零 modal：本视图为常驻面板，不使用 showDialog/Navigator 弹层，
///   不存在模态死锁或弹层残留路径。
class SmartLayoutSessionView extends ConsumerStatefulWidget {
  const SmartLayoutSessionView({
    super.key,
    this.restoreFocusNode,
    this.recognitionStatus,
  });

  /// 会话结束（applied/cancelled 复位后回到 idle）时归还焦点的节点
  ///（通常为宿主页面的画布/入口控件）。
  final FocusNode? restoreFocusNode;

  /// 识别状态播报（R7，spec §10 面板状态枚举：正在准备/正在识别/
  /// 正在重分组/正在复核/正在恢复结构/正在生成排版/部分完成）；
  /// null = 无独立识别链（HTTP 实验路径），analyzing 显示通用文案。
  final ValueListenable<String?>? recognitionStatus;

  @override
  ConsumerState<SmartLayoutSessionView> createState() =>
      _SmartLayoutSessionViewState();
}

class _SmartLayoutSessionViewState
    extends ConsumerState<SmartLayoutSessionView> {
  String? _selectedBlockId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartLayoutSessionViewModelProvider);
    final viewModel = ref.read(smartLayoutSessionViewModelProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.escape,
        ): state.canCancel || state.canReset
            ? () => _onEscape(state, viewModel)
            : () {},
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
        ): state.canChooseCandidate
            ? () => _moveSelection(state, viewModel, 1)
            : () {},
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
        ): state.canChooseCandidate
            ? () => _moveSelection(state, viewModel, -1)
            : () {},
      },
      child: Semantics(
        container: true,
        label: '智能排版会话，${_phaseLabel(state.phase)}',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.phase == SmartLayoutSessionPhase.idle)
                  _ScopeSummary(state: state),
                const SizedBox(height: 8),
                // 相位播报（读屏 liveRegion）：仅语义通道，不重复可见文案。
                Semantics(
                  liveRegion: true,
                  label: _phaseLabel(state.phase),
                  child: const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
                switch (state.phase) {
                  SmartLayoutSessionPhase.idle => _IdlePane(
                    state: state,
                    onStart: viewModel.startAnalysis,
                  ),
                  SmartLayoutSessionPhase.analyzing => _analyzingPane(
                    state,
                    viewModel,
                  ),
                  SmartLayoutSessionPhase.reviewing => _ReviewPane(
                    state: state,
                    onChoose: viewModel.chooseCandidate,
                    selectedBlockId: _selectedBlockId,
                    onSelectBlock: (id) =>
                        setState(() => _selectedBlockId = id),
                    onCancel: viewModel.cancel,
                    onCorrect: viewModel.applyRegionCorrection,
                    onRestart: viewModel.restartAnalysis,
                  ),
                  SmartLayoutSessionPhase.applying => _BusyPane(
                    message: '正在应用排版…',
                    onCancel: state.canCancel ? viewModel.cancel : null,
                  ),
                  SmartLayoutSessionPhase.applied => _TerminalPane(
                    message: '排版已应用',
                    onReset: () => _resetAndRestoreFocus(viewModel),
                  ),
                  SmartLayoutSessionPhase.cancelled => _TerminalPane(
                    message: '已取消，原稿未修改',
                    onReset: () => _resetAndRestoreFocus(viewModel),
                  ),
                  SmartLayoutSessionPhase.failed => _FailurePane(
                    state: state,
                    onRetry: viewModel.retry,
                    onRestart: viewModel.restartAnalysis,
                    onReset: () => _resetAndRestoreFocus(viewModel),
                  ),
                },
              ],
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constraints.hasBoundedHeight)
                  Flexible(child: SingleChildScrollView(child: content))
                else
                  content,
                if (state.canChooseCandidate)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          autofocus: true,
                          onPressed: state.canApply
                              ? viewModel.applySelectedCandidate
                              : null,
                          child: const Text('应用所选排版'),
                        ),
                        TextButton(
                          onPressed: viewModel.cancel,
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// analyzing 相位面板：有识别状态播报时跟随（正在准备/正在识别/
  /// …/部分完成），否则通用文案。
  Widget _analyzingPane(
    SmartLayoutSessionUiState state,
    SmartLayoutSessionViewModel viewModel,
  ) {
    final status = widget.recognitionStatus;
    if (status == null) {
      return _BusyPane(
        key: ValueKey(state.activeTicket?.operationId),
        message: '正在分析…',
        onCancel: state.canCancel ? viewModel.cancel : null,
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: status,
      builder: (context, value, _) => _BusyPane(
        key: ValueKey(state.activeTicket?.operationId),
        message: value ?? '正在分析…',
        onCancel: state.canCancel ? viewModel.cancel : null,
      ),
    );
  }

  void _onEscape(
    SmartLayoutSessionUiState state,
    SmartLayoutSessionViewModel viewModel,
  ) {
    if (state.canCancel) {
      viewModel.cancel();
    } else if (state.canReset) {
      _resetAndRestoreFocus(viewModel);
    }
  }

  /// 复位并归还焦点（applied/cancelled/failed 的完成路径）。
  void _resetAndRestoreFocus(SmartLayoutSessionViewModel viewModel) {
    viewModel.reset();
    widget.restoreFocusNode?.requestFocus();
  }

  void _moveSelection(
    SmartLayoutSessionUiState state,
    SmartLayoutSessionViewModel viewModel,
    int delta,
  ) {
    final ids = [for (final c in state.candidates) c.candidateId];
    final index = ids.indexOf(state.selectedCandidateId ?? '');
    if (index < 0) return;
    final next = (index + delta).clamp(0, ids.length - 1);
    viewModel.chooseCandidate(ids[next]);
  }

  static String _phaseLabel(SmartLayoutSessionPhase phase) => switch (phase) {
    SmartLayoutSessionPhase.idle => '待开始',
    SmartLayoutSessionPhase.analyzing => '正在分析',
    SmartLayoutSessionPhase.reviewing => '候选复核',
    SmartLayoutSessionPhase.applying => '正在应用排版',
    SmartLayoutSessionPhase.applied => '排版已应用',
    SmartLayoutSessionPhase.cancelled => '已取消',
    SmartLayoutSessionPhase.failed => '会话失败',
  };
}

class _ScopeSummary extends StatelessWidget {
  const _ScopeSummary({required this.state});

  final SmartLayoutSessionUiState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '本次整理当前页，原稿在应用前保持不变',
      child: Text(
        state.scopeSourceIds.isEmpty
            ? '整理当前页 · 应用前可预览与取消'
            : '排版范围 ${state.scopeSourceIds.length} 个源元素 · '
                  '保护 ${state.protectedSourceIds.length} 个源元素',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _IdlePane extends StatelessWidget {
  const _IdlePane({required this.state, required this.onStart});

  final SmartLayoutSessionUiState state;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      autofocus: true,
      onPressed: state.canStartAnalysis ? () => onStart() : null,
      child: const Text('开始智能排版'),
    );
  }
}

class _BusyPane extends StatefulWidget {
  const _BusyPane({super.key, required this.message, this.onCancel});

  final String message;
  final VoidCallback? onCancel;

  @override
  State<_BusyPane> createState() => _BusyPaneState();
}

class _BusyPaneState extends State<_BusyPane> {
  final _clock = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.onCancel == null
          ? widget.message
          : '${widget.message}，按 Escape 取消',
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.message),
                Text(
                  '已等待 ${_clock.elapsed.inSeconds} 秒',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.onCancel != null) const Text('可以随时取消，原稿不会改变。'),
              ],
            ),
          ),
          if (widget.onCancel != null)
            TextButton(
              autofocus: true,
              onPressed: widget.onCancel,
              child: const Text('取消'),
            ),
        ],
      ),
    );
  }
}

class _ReviewPane extends StatelessWidget {
  const _ReviewPane({
    required this.state,
    required this.onChoose,
    required this.selectedBlockId,
    required this.onSelectBlock,
    required this.onCancel,
    required this.onCorrect,
    required this.onRestart,
  });

  final SmartLayoutSessionUiState state;
  final ValueChanged<String> onChoose;
  final String? selectedBlockId;
  final ValueChanged<String?> onSelectBlock;
  final VoidCallback onCancel;
  final Future<void> Function(RegionCorrectionIntent intent) onCorrect;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    if (state.isCorrecting) {
      return _BusyPane(message: '正在更新排版预览…', onCancel: onCancel);
    }
    if (state.candidates.isEmpty) {
      // 无解分支（V3-505C）：空候选如实呈现 + 重新分析（同 scope
      // 重走完整链），不伪装成功。
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.reviewContext?.recognitionFailure case final error?)
            _RecognitionFailure(error: error),
          if (state.correctionError != null)
            _CorrectionError(reason: state.correctionError!),
          Semantics(label: '本次分析没有可用的排版候选', child: const Text('本次分析没有可用的排版候选')),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                autofocus: true,
                onPressed: onRestart,
                child: const Text('重新分析'),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onCancel, child: const Text('关闭')),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.reviewContext?.excludedScopeReasons.isNotEmpty ?? false)
          Text(
            '部分整理：本页可见的 ${state.reviewContext!.excludedScopeReasons.length} 个元素归属不明确或属于其他页，保持原位。',
          ),
        if (state.reviewContext?.recognitionFailure case final error?) ...[
          _RecognitionFailure(error: error),
          TextButton(onPressed: onRestart, child: const Text('重新分析')),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final candidate in state.candidates)
              SmartLayoutCandidateView(
                key: ValueKey(candidate.candidateId),
                structureLabel: candidate.structureLabel,
                selected: candidate.candidateId == state.selectedCandidateId,
                recommended:
                    state.validatedCards.isNotEmpty &&
                    candidate.candidateId ==
                        state.validatedCards.first.candidateId,
                onChoose: state.canChooseCandidate
                    ? () => onChoose(candidate.candidateId)
                    : null,
              ),
          ],
        ),
        if (state.selectedValidatedCandidate case final candidate?) ...[
          SmartLayoutPreview(
            candidate: candidate,
            context: state.reviewContext,
          ),
          const SizedBox(height: 8),
          _LedgerSummary(state: state),
        ],
        if (state.correctionError != null)
          _CorrectionError(reason: state.correctionError!),
        if (state.selectedValidatedCandidate != null &&
            (state.reviewContext?.document.blocks.isNotEmpty ?? false))
          _BlockCorrection(
            state: state,
            onCorrect: onCorrect,
            selectedId: selectedBlockId,
            onSelect: onSelectBlock,
          ),
        if (state.validatedCards.isNotEmpty)
          ExpansionTile(
            title: const Text('排版详情'),
            children: [
              for (final card in state.validatedCards)
                ListTile(
                  title: Text(
                    '${card.structureLabel} · 评分 ${card.score.toStringAsFixed(3)}',
                  ),
                  subtitle: Text(
                    '${card.candidateId} · ${card.structureDiffLabel}\n'
                    '${card.scoreEntries.map((e) => '${e.id.name}: ${e.contribution.toStringAsFixed(2)}').join('，')}',
                  ),
                ),
              _LedgerReview(state: state),
            ],
          ),
      ],
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({required this.state});
  final SmartLayoutSessionUiState state;

  @override
  Widget build(BuildContext context) {
    final ledger = state.ledgerReview;
    final kept = ledger
        .where((e) => e.$2 == SourceCoverageStatus.preserved)
        .toList();
    final reasons = <String, int>{};
    for (final (id, _) in kept) {
      final reason = switch (state.reviewContext?.preserveReasons[id]) {
        SourcePreserveReason.locked => '已锁定',
        SourcePreserveReason.binding => '绑定内容',
        SourcePreserveReason.unreadable ||
        SourcePreserveReason.uncertain => '识别不可靠',
        SourcePreserveReason.nonText => '图形等非文字内容',
        SourcePreserveReason.userKept => '选择保留',
        SourcePreserveReason.budgetExceeded => '处理额度已用完',
        SourcePreserveReason.assetFailed => '图像准备失败',
        SourcePreserveReason.missingResponse => '未取得识别结果',
        SourcePreserveReason.contextOnly => '参考内容',
        null =>
          state.reviewContext?.document.preservedSourceIds.contains(id) == true
              ? '选择保留或不参与重排'
              : state.reviewContext?.document.consumedSourceIds.contains(id) ==
                    true
              ? '无法安全排版，关联内容整组保留'
              : '未安全转换',
      };
      reasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已整理 ${ledger.where((e) => e.$2 == SourceCoverageStatus.consumed).length} 个源元素 · '
          '原样保留 ${kept.length} 个源元素',
        ),
        if (reasons.isNotEmpty)
          Text(
            reasons.entries.map((e) => '${e.key} ${e.value}').join('；'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _BlockCorrection extends StatelessWidget {
  const _BlockCorrection({
    required this.state,
    required this.onCorrect,
    required this.selectedId,
    required this.onSelect,
  });
  final SmartLayoutSessionUiState state;
  final Future<void> Function(RegionCorrectionIntent) onCorrect;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final document = state.reviewContext!.document;
    final byId = {for (final block in document.blocks) block.id: block};
    final blocks = [
      for (final id in document.readingOrder.orderedBlockIds) byId[id]!,
    ];
    final selected = byId[selectedId] ?? blocks.first;
    final ledger =
        state.selectedValidatedCandidate!.patch.sourceCoverage.statuses;
    final canPreserve =
        selected.sourceIds.isNotEmpty &&
        selected.sourceIds.every(
          (id) => ledger[id] == SourceCoverageStatus.consumed,
        ) &&
        selected.sourceIds.every(document.consumedSourceIds.contains);
    final canChangeRole =
        canPreserve &&
        selected.text?.trim().isNotEmpty == true &&
        {
          SemanticRole.title,
          SemanticRole.body,
          SemanticRole.list,
          SemanticRole.caption,
        }.contains(selected.role);
    String roleLabel(SemanticRole role) => switch (role) {
      SemanticRole.title => '标题',
      SemanticRole.body => '正文',
      SemanticRole.list => '列表',
      SemanticRole.caption => '图注',
      SemanticRole.figure => '图片',
      SemanticRole.formula => '公式',
      SemanticRole.table => '表格',
      SemanticRole.unknown => '原样保留',
    };
    return ExpansionTile(
      title: Text('调整内容块（${blocks.length}）'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: selected.id,
          items: [
            for (final block in blocks)
              DropdownMenuItem(
                value: block.id,
                child: Text(
                  '${roleLabel(block.role)} · ${block.text ?? '${block.sourceIds.length} 个源元素'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onSelect,
        ),
        Text(
          selected.text ??
              '${roleLabel(selected.role)}（${selected.sourceIds.length} 个源元素）',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final role in [SemanticRole.title, SemanticRole.body])
              OutlinedButton(
                onPressed: canChangeRole && selected.role != role
                    ? () => onCorrect(
                        RegionCorrectionIntent(
                          kind: 'role',
                          subjectIds: [selected.id],
                          detail: role.wireName,
                        ),
                      )
                    : null,
                child: Text('作为${roleLabel(role)}'),
              ),
            OutlinedButton(
              onPressed: canPreserve
                  ? () => onCorrect(
                      RegionCorrectionIntent(
                        kind: 'preserve',
                        subjectIds: selected.sourceIds,
                      ),
                    )
                  : null,
              child: const Text('保留原件'),
            ),
          ],
        ),
        const Text('这里只调整结构，不逐字修改识别文字；可保留原件后继续编辑。'),
      ],
    );
  }
}

class _CorrectionError extends StatelessWidget {
  const _CorrectionError({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    final message =
        reason.contains('stale') ||
            reason.contains('revision') ||
            reason.contains('page')
        ? '画布或当前页已变化，请取消后重新分析。'
        : reason == 'rerun-failed'
        ? '本次调整未能生成预览，请重新分析；原稿未修改。'
        : '无法调整此内容块，请重新选择或保留原件；原稿未修改。';
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// 账本核对区：仅在详情展开时逐一呈现 consumed/preserved。
class _LedgerReview extends StatelessWidget {
  const _LedgerReview({required this.state});

  final SmartLayoutSessionUiState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '账本核对：${state.ledgerReview.length} 个源，'
          '${state.ledgerReview.where((e) => e.$2 == SourceCoverageStatus.consumed).length} 已消费，'
          '${state.ledgerReview.where((e) => e.$2 == SourceCoverageStatus.preserved).length} 保留',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (id, status) in state.ledgerReview)
              Text(
                '$id · ${status == SourceCoverageStatus.consumed ? '已消费' : '保留'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({required this.message, this.onReset});

  final String message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(label: message, child: Text(message)),
        if (onReset != null)
          TextButton(
            autofocus: true,
            onPressed: onReset,
            child: const Text('完成'),
          ),
      ],
    );
  }
}

/// 与保留账本分开解释服务故障；不能把 unreadable 猜成断网。
class _RecognitionFailure extends StatelessWidget {
  const _RecognitionFailure({required this.error});
  final RecognitionException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.code) {
      'providerTimeout' ||
      'requestTimeout' ||
      'operationTimeout' => '识别处理超时，原稿未修改。可以稍后重新分析。',
      'unconfigured' => '识别服务尚未配置，请检查服务器模型配置。',
      'auth' => '识别服务认证失败，请检查服务配置。',
      'busy' => '识别服务繁忙，可以稍后重新分析。',
      _ => switch (error.kind) {
        RecognitionExceptionKind.network => '无法连接识别服务，请检查网络后重新分析。',
        RecognitionExceptionKind.budgetExhausted => '本轮处理已达到限制，未完成的内容原样保留。',
        RecognitionExceptionKind.invalidRequest ||
        RecognitionExceptionKind.invalidResponse => '识别响应校验未通过，未安全转换的内容原样保留。',
        _ => '识别服务暂不可用，未完成的内容原样保留。',
      },
    };
    return Column(
      children: [
        Semantics(liveRegion: true, child: Text(message)),
        ExpansionTile(
          title: const Text('识别故障详情'),
          children: [
            SelectableText('${error.code ?? error.kind.name}\n${error.detail}'),
          ],
        ),
      ],
    );
  }
}

class _FailurePane extends StatelessWidget {
  const _FailurePane({
    required this.state,
    required this.onRetry,
    required this.onRestart,
    required this.onReset,
  });

  final SmartLayoutSessionUiState state;
  final Future<void> Function() onRetry;
  final VoidCallback onRestart;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure;
    final reason = failure?.reason ?? '';
    final stale = reason.contains('changed') || reason.contains('mismatch');
    final label = stale
        ? '画布或当前页已变化，请重新分析；旧结果未应用。'
        : switch (reason) {
            'network' => '无法连接识别服务，请检查网络后重试。',
            'timeout' => '识别处理超时，原稿未修改，可以稍后重试。',
            'badStatus' => '识别服务暂不可用，原稿未修改。',
            'disposed' => '当前页面已关闭，请重新打开排版。',
            'badSchema' => '识别或结构校验未通过，原稿未修改。',
            _ => '本次排版未能完成，原稿未修改。',
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(label: label, child: Text(label)),
        if (failure != null)
          ExpansionTile(
            title: const Text('失败详情'),
            children: [
              SelectableText(
                '${failure.stage}/${failure.reason} · 第 ${failure.attempt} 次\n${failure.detail}',
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              autofocus: true,
              onPressed: state.canRetry ? () => onRetry() : onRestart,
              child: Text(state.canRetry ? '重试' : '重新分析'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onReset, child: const Text('关闭')),
          ],
        ),
      ],
    );
  }
}
