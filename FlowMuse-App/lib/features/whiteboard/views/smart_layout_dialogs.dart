import 'package:flutter/material.dart';

import '../editor_core/flow_muse_whiteboard_editor.dart';

/// 逐页确认对话框返回的动作。
enum SmartLayoutConfirmAction { apply, applyAndDrop, skip, cancel }

/// 页面多选：返回选中页面 id 列表（取消返回 null）。
class SmartLayoutPagePickerDialog extends StatefulWidget {
  const SmartLayoutPagePickerDialog({
    super.key,
    required this.pages,
    this.initial = const {},
  });

  final List<CanvasPage> pages;
  final Set<String> initial;

  @override
  State<SmartLayoutPagePickerDialog> createState() =>
      _SmartLayoutPagePickerDialogState();
}

class _SmartLayoutPagePickerDialogState
    extends State<SmartLayoutPagePickerDialog> {
  late final Set<String> _checked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要智能排版的页面'),
      content: SizedBox(
        width: 340,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final page in widget.pages)
              CheckboxListTile(
                dense: true,
                value: _checked.contains(page.id),
                title: Text('第 ${page.index + 1} 页'),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _checked.add(page.id);
                    } else {
                      _checked.remove(page.id);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_checked.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 逐页确认：描述 + 风格切换 + 应用/跳过/取消。
/// 幽灵预览由调用方通过 controller.setSmartLayoutGhost 维护；切换风格回调返回新计划。
class SmartLayoutConfirmDialog extends StatefulWidget {
  const SmartLayoutConfirmDialog({
    super.key,
    required this.plan,
    required this.onSelectStyle,
    required this.onApply,
    required this.onApplyAndDrop,
    required this.onSkip,
    required this.onCancel,
  });

  final SmartLayoutPlan plan;
  final Future<SmartLayoutPlan?> Function(SmartLayoutStyle style)
  onSelectStyle;
  final void Function(SmartLayoutPlan plan) onApply;
  final void Function(SmartLayoutPlan plan) onApplyAndDrop;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  @override
  State<SmartLayoutConfirmDialog> createState() =>
      _SmartLayoutConfirmDialogState();
}

class _SmartLayoutConfirmDialogState extends State<SmartLayoutConfirmDialog> {
  late SmartLayoutPlan _plan = widget.plan;
  bool _switching = false;

  bool get _hasFailedBlocks =>
      _plan.failedStrokeIds.isNotEmpty || _plan.failureRects.isNotEmpty;

  Future<void> _switchStyle(SmartLayoutStyle style) async {
    if (style == _plan.style || _switching) return;
    setState(() => _switching = true);
    try {
      final next = await widget.onSelectStyle(style);
      if (next != null && mounted) {
        setState(() => _plan = next);
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('智能排版预览（${_plan.style.displayName}）'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_plan.description),
            const SizedBox(height: 8),
            Text(
              '置信度：${(_plan.confidence * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final style in SmartLayoutStyle.values)
                  ChoiceChip(
                    label: Text(style.displayName),
                    selected: style == _plan.style,
                    onSelected: _switching ? null : (_) => _switchStyle(style),
                  ),
              ],
            ),
            if (_hasFailedBlocks)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '页内有未识别成功的笔迹（红色区域）。'
                  '可先应用排版，或选择"删除未识别笔迹后应用"。',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消整个流程'),
        ),
        TextButton(
          onPressed: widget.onSkip,
          child: const Text('跳过本页'),
        ),
        if (_hasFailedBlocks)
          TextButton(
            onPressed: () => widget.onApplyAndDrop(_plan),
            child: const Text('删除未识别笔迹后应用'),
          ),
        FilledButton(
          onPressed: () => widget.onApply(_plan),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

/// 识别失败对话框（计划为空、整页失败时）：再试 / 取消。
class SmartLayoutFailureDialog extends StatelessWidget {
  const SmartLayoutFailureDialog({
    super.key,
    required this.failures,
    required this.onRetry,
    required this.onCancel,
  });

  final List<SmartLayoutFailureInfo> failures;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('部分内容未识别成功'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('整页将不应用排版。以下手写疑似未能识别：'),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < failures.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '第 ${i + 1} 处：'
                        '${failures[i].snippet ?? '手写笔迹'}'
                        '${failures[i].error?.isNotEmpty == true ? '（${failures[i].error}）' : ''}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('页面上的红色区域即为未识别部分，可修改字迹后重试。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: onRetry,
          child: const Text('重新识别'),
        ),
      ],
    );
  }
}
