import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/smart_layout_session_state.dart';
import '../session/smart_layout_session_view_model.dart';
import 'smart_layout_candidate_view.dart';

/// 智能排版会话视图（V3-505A 骨架）：按会话 sealed 相位渲染——
/// idle（范围/保护摘要 + 开始）、analyzing（进度 + 取消）、
/// reviewing（候选卡 + 应用）、applying（进度 + 取消）、applied（完成 +
/// 复位）、cancelled/failed（信息 + 重试/复位）。
///
/// 视图零业务状态：不持有 bool/Completer/在途 future，一切启用条件
/// 来自 [SmartLayoutSessionUiState] 的唯一判定（canStartAnalysis 等），
/// 一切动作只转发 ViewModel 方法。可访问性闭环（Semantics 全覆盖/
/// 键盘/焦点恢复）归 V3-505C。
class SmartLayoutSessionView extends ConsumerWidget {
  const SmartLayoutSessionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smartLayoutSessionViewModelProvider);
    final viewModel = ref.read(smartLayoutSessionViewModelProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScopeSummary(state: state),
        const SizedBox(height: 8),
        switch (state.phase) {
          SmartLayoutSessionPhase.idle => _IdlePane(
            state: state,
            onStart: viewModel.startAnalysis,
          ),
          SmartLayoutSessionPhase.analyzing => _BusyPane(
            message: '正在分析…',
            onCancel: state.canCancel ? viewModel.cancel : null,
          ),
          SmartLayoutSessionPhase.reviewing => _ReviewPane(
            state: state,
            onChoose: viewModel.chooseCandidate,
            onApply: viewModel.applySelectedCandidate,
            onCancel: viewModel.cancel,
          ),
          SmartLayoutSessionPhase.applying => _BusyPane(
            message: '正在应用排版…',
            onCancel: state.canCancel ? viewModel.cancel : null,
          ),
          SmartLayoutSessionPhase.applied => _TerminalPane(
            message: '排版已应用',
            onReset: viewModel.reset,
          ),
          SmartLayoutSessionPhase.cancelled => _TerminalPane(
            message: '已取消（${state.sessionState.operationId ?? '-'}）',
            onReset: viewModel.reset,
          ),
          SmartLayoutSessionPhase.failed => _FailurePane(
            state: state,
            onRetry: viewModel.retry,
            onReset: viewModel.reset,
          ),
        },
      ],
    );
  }
}

class _ScopeSummary extends StatelessWidget {
  const _ScopeSummary({required this.state});

  final SmartLayoutSessionUiState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '范围 ${state.scopeSourceIds.length} 项，'
          '其中保护 ${state.protectedSourceIds.length} 项',
      child: Text(
        '排版范围 ${state.scopeSourceIds.length} 项 · '
        '保护 ${state.protectedSourceIds.length} 项',
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
      onPressed: state.canStartAnalysis ? () => onStart() : null,
      child: const Text('开始智能排版'),
    );
  }
}

class _BusyPane extends StatelessWidget {
  const _BusyPane({required this.message, this.onCancel});

  final String message;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        if (onCancel != null)
          TextButton(onPressed: onCancel, child: const Text('取消')),
      ],
    );
  }
}

class _ReviewPane extends StatelessWidget {
  const _ReviewPane({
    required this.state,
    required this.onChoose,
    required this.onApply,
    required this.onCancel,
  });

  final SmartLayoutSessionUiState state;
  final ValueChanged<String> onChoose;
  final Future<void> Function() onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (state.candidates.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('本次分析没有可用的排版候选'),
          TextButton(onPressed: onCancel, child: const Text('关闭')),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final candidate in state.candidates)
          SmartLayoutCandidateView(
            candidateId: candidate.candidateId,
            structureLabel: candidate.structureLabel,
            selected: candidate.candidateId == state.selectedCandidateId,
            onChoose: state.canChooseCandidate
                ? () => onChoose(candidate.candidateId)
                : null,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: state.canApply ? () => onApply() : null,
              child: const Text('应用所选排版'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
      ],
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
        Text(message),
        if (onReset != null)
          TextButton(onPressed: onReset, child: const Text('完成')),
      ],
    );
  }
}

class _FailurePane extends StatelessWidget {
  const _FailurePane({
    required this.state,
    required this.onRetry,
    required this.onReset,
  });

  final SmartLayoutSessionUiState state;
  final Future<void> Function() onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          failure == null
              ? '会话失败'
              : '失败（${failure.stage}/${failure.reason}，'
                    '第 ${failure.attempt} 次尝试）',
        ),
        Row(
          children: [
            FilledButton(
              onPressed: state.canRetry ? () => onRetry() : null,
              child: const Text('重试'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onReset, child: const Text('关闭')),
          ],
        ),
      ],
    );
  }
}
