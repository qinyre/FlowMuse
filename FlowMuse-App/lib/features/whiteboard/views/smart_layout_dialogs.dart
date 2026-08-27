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
                          // 用 SingleChildScrollView 而非 ListView：
                          // ListView（viewport）不支持 intrinsic 尺寸，真实 showDialog 路由
                          // 会因 AlertDialog 的 IntrinsicWidth 布局查询抛异常（白框）。
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
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
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 180,
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
    // 自绘行而非 CheckboxListTile：窄窗口下 ListTile 的 trailing 缩略图会占满瓦片宽度抛断言。
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: onChanged),
            SizedBox(
              width: 72,
              height: 48,
              child: _PageThumbnail(page: page, builder: thumbnailBuilder),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '第 ${page.index + 1} 页',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
              width: 72,
              height: 48,
            );
          }
          return _fallback();
        },
      ),
    );
  }

  Widget _fallback() => Container(
    width: 72,
    height: 48,
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
    this.onProofread,
  });

  final SmartLayoutPlan plan;
  final bool isMultiPage;
  final ValueChanged<SmartLayoutBarAction> onAction;

  /// 低置信文本校对入口；为 null 表示本页没有可校对项（隐藏按钮）。
  final Future<void> Function()? onProofread;

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
            if (onProofread != null)
              TextButton(
                onPressed: onProofread,
                child: Text('校对 ${plan.lowConfidenceTexts.length} 处'),
              ),
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

/// 草稿态低置信文本校对编辑条：逐项展示并允许改字，保存即更新草稿场景。
class SmartLayoutProofreadSheet extends StatefulWidget {
  const SmartLayoutProofreadSheet({
    super.key,
    required this.items,
    required this.onRevise,
  });

  final List<({ElementId id, String text})> items;
  final bool Function(ElementId id, String newText) onRevise;

  @override
  State<SmartLayoutProofreadSheet> createState() =>
      _SmartLayoutProofreadSheetState();
}

class _SmartLayoutProofreadSheetState extends State<SmartLayoutProofreadSheet> {
  final Map<int, TextEditingController> _controllers = {};
  final Set<int> _savedIndexes = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int index, String initial) =>
      _controllers.putIfAbsent(index, () => TextEditingController(text: initial));

  void _save(int index, ElementId id) {
    final ok = widget.onRevise(id, _controllers[index]!.text);
    if (!ok) return;
    setState(() => _savedIndexes.add(index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('校对识别文字', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '橙色虚线标注的文本识别把握不足，请核对或修正后应用。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final controller = _controllerFor(index, item.text);
                  final saved = _savedIndexes.contains(index);
                  final changed =
                      controller.text.trim() != item.text.trim() && !saved;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          saved ? Icons.check_circle : Icons.edit_note,
                          size: 20,
                          color: saved
                              ? Colors.green.shade600
                              : const Color(0xFFF08C00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              helperText: saved ? '已更新' : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: changed
                              ? () => _save(index, item.id)
                              : null,
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
