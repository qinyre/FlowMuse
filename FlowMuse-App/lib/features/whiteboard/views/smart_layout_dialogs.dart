import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../editor_core/flow_muse_whiteboard_editor.dart';
import 'smart_layout_page_ranges.dart';

/// 页面入口三选一：全部页 / 选页 / 当前页。
enum SmartLayoutScopeMode { currentPage, allPages, selectedPages }

/// 页面入口选择结果。
class SmartLayoutScopeSelection {
  const SmartLayoutScopeSelection({
    required this.mode,
    this.pageIds = const [],
  });

  final SmartLayoutScopeMode mode;
  final List<String> pageIds;
}

/// 页面缩略图渲染回调（场景矩形 → PNG 字节；失败返回 null）。
typedef SmartLayoutThumbnailBuilder =
    Future<Uint8List?> Function(Rect sceneBounds);

/// 页面入口对话框：三选一 +（选页时）缩略图勾选列表 + 页码范围输入框。
/// 输入框输入（如 3-5,7）→ 自动勾选对应页；只勾选 → 输入框清空；格式错 → 右下提示并禁用确定。
class SmartLayoutScopeDialog extends StatefulWidget {
  const SmartLayoutScopeDialog({
    super.key,
    required this.pages,
    this.currentPageId,
    this.thumbnailBuilder,
  });

  final List<CanvasPage> pages;
  final String? currentPageId;
  final SmartLayoutThumbnailBuilder? thumbnailBuilder;

  @override
  State<SmartLayoutScopeDialog> createState() => _SmartLayoutScopeDialogState();
}

class _SmartLayoutScopeDialogState extends State<SmartLayoutScopeDialog> {
  SmartLayoutScopeMode _mode = SmartLayoutScopeMode.currentPage;
  final Set<String> _checked = {};
  final TextEditingController _input = TextEditingController();
  String _inputError = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _confirmEnabled {
    if (_mode != SmartLayoutScopeMode.selectedPages) return true;
    return _checked.isNotEmpty && _inputError.isEmpty;
  }

  void _onCheckToggled(String pageId, bool? checked) {
    setState(() {
      if (checked == true) {
        _checked.add(pageId);
      } else {
        _checked.remove(pageId);
      }
      // 只勾选 → 输入框清空（按需求）
      if (_input.text.isNotEmpty) {
        _input.clear();
        _inputError = '';
      }
    });
  }

  void _onInputChanged(String text) {
    setState(() {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        _inputError = '';
        return;
      }
      final result = SmartLayoutPageRangeParser.parse(
        trimmed,
        widget.pages.length,
      );
      if (result.isValid) {
        _inputError = '';
        _checked
          ..clear()
          ..addAll({
            for (final index in result.pageIndexes) widget.pages[index].id,
          });
      } else {
        _inputError = result.errorText;
      }
    });
  }

  void _submit() {
    switch (_mode) {
      case SmartLayoutScopeMode.allPages:
        Navigator.of(context).pop(
          SmartLayoutScopeSelection(
            mode: _mode,
            pageIds: [for (final page in widget.pages) page.id],
          ),
        );
      case SmartLayoutScopeMode.currentPage:
        Navigator.of(context).pop(
          SmartLayoutScopeSelection(
            mode: _mode,
            pageIds: [if (widget.currentPageId != null) widget.currentPageId!],
          ),
        );
      case SmartLayoutScopeMode.selectedPages:
        Navigator.of(context).pop(
          SmartLayoutScopeSelection(
            mode: _mode,
            pageIds: [
              for (final page in widget.pages)
                if (_checked.contains(page.id)) page.id,
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('智能排版范围'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<SmartLayoutScopeMode>(
                groupValue: _mode,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _mode = value);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final mode in SmartLayoutScopeMode.values)
                      RadioListTile<SmartLayoutScopeMode>(
                        dense: true,
                        value: mode,
                        title: Text(switch (mode) {
                          SmartLayoutScopeMode.currentPage => '当前页',
                          SmartLayoutScopeMode.allPages => '全部页',
                          SmartLayoutScopeMode.selectedPages => '选页',
                        }),
                      ),
                  ],
                ),
              ),
              if (_mode == SmartLayoutScopeMode.selectedPages)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 300,
                          child: ListView(
                            children: [
                              for (final page in widget.pages)
                                _PageCheckTile(
                                  page: page,
                                  checked: _checked.contains(page.id),
                                  thumbnailBuilder: widget.thumbnailBuilder,
                                  onChanged: (value) =>
                                      _onCheckToggled(page.id, value),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 220,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _input,
                              onChanged: _onInputChanged,
                              decoration: InputDecoration(
                                labelText: '页码',
                                hintText: '如 3-5,7',
                                border: const OutlineInputBorder(),
                                errorText: _inputError.isEmpty
                                    ? null
                                    : _inputError,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '连续页用 -（如 3-5 表示第 3 到第 5 页），'
                              '不连续用 ,（如 3,5），混合如 3-5,7。'
                              '输入后自动勾选；直接勾选则输入框置空。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirmEnabled ? _submit : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 单个页面的勾选行：缩略图 + 页码。
class _PageCheckTile extends StatelessWidget {
  const _PageCheckTile({
    required this.page,
    required this.checked,
    required this.onChanged,
    this.thumbnailBuilder,
  });

  final CanvasPage page;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final SmartLayoutThumbnailBuilder? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      value: checked,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: SizedBox(
        width: 96,
        height: 64,
        child: _PageThumbnail(page: page, builder: thumbnailBuilder),
      ),
      title: Text('第 ${page.index + 1} 页'),
    );
  }
}

/// 页面缩略图：异步渲染，失败回落灰块。
class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({required this.page, this.builder});

  final CanvasPage page;
  final SmartLayoutThumbnailBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final thumbBuilder = builder;
    if (thumbBuilder == null) {
      return _fallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: FutureBuilder<Uint8List?>(
        future: thumbBuilder(page.bounds),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              width: 96,
              height: 64,
            );
          }
          return _fallback();
        },
      ),
    );
  }

  Widget _fallback() => Container(
    width: 96,
    height: 64,
    color: Colors.grey.shade300,
    alignment: Alignment.center,
    child: const Icon(Icons.description_outlined, size: 20),
  );
}

/// 底部条形按钮动作。
enum SmartLayoutBarAction { apply, applyAndDrop, retry, skipPage, cancelAll }

/// 非模态底部"预览确认"悬浮条（画布全程可见，红区/蓝框不被遮挡）。
/// 风格由 AI 自主决定（不提供人工切换）；按钮随页数/失败情况显隐。
class SmartLayoutConfirmBar extends StatelessWidget {
  const SmartLayoutConfirmBar({
    super.key,
    required this.plan,
    required this.isMultiPage,
    required this.onAction,
  });

  final SmartLayoutPlan plan;
  final bool isMultiPage;
  final ValueChanged<SmartLayoutBarAction> onAction;

  bool get _hasFailures =>
      plan.failedStrokeIds.isNotEmpty || plan.failureRects.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.style.displayName} · 置信度 '
                    '${(plan.confidence * 100).round()}%',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.description,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (_hasFailures)
              TextButton(
                onPressed: () => onAction(SmartLayoutBarAction.applyAndDrop),
                child: const Text('删除未识别笔迹后应用'),
              ),
            if (isMultiPage)
              TextButton(
                onPressed: () => onAction(SmartLayoutBarAction.skipPage),
                child: const Text('跳过本页'),
              ),
            TextButton(
              onPressed: () => onAction(SmartLayoutBarAction.cancelAll),
              child: Text(isMultiPage ? '取消整个流程' : '取消'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => onAction(SmartLayoutBarAction.apply),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 非模态底部"识别失败"悬浮条（红区可见；展示失败原因便于定位）。
class SmartLayoutFailureBar extends StatelessWidget {
  const SmartLayoutFailureBar({
    super.key,
    required this.failures,
    required this.isMultiPage,
    required this.onAction,
  });

  final List<SmartLayoutFailureInfo> failures;
  final bool isMultiPage;
  final ValueChanged<SmartLayoutBarAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstError = failures.isEmpty ? null : failures.first.error;
    return Card(
      elevation: 6,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${failures.length} 处手写未识别成功（红色区域），'
                    '可修改字迹后重试，或删除后继续。',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (firstError != null && firstError.isNotEmpty)
                    Text(
                      '原因：$firstError',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isMultiPage)
              TextButton(
                onPressed: () => onAction(SmartLayoutBarAction.skipPage),
                child: const Text('跳过本页'),
              ),
            TextButton(
              onPressed: () => onAction(SmartLayoutBarAction.cancelAll),
              child: Text(isMultiPage ? '取消整个流程' : '取消'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => onAction(SmartLayoutBarAction.retry),
              child: const Text('重新识别'),
            ),
          ],
        ),
      ),
    );
  }
}
