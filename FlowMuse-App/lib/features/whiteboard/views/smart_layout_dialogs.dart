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

/// 识别进度状态：整页识别阶段（尚无逐块进度）或裁剪重问逐块阶段。
/// [pageLabel] 为多页流程的页码提示（如"第 2/5 页"），单页为 null 不显示。
@immutable
class SmartLayoutRecognitionProgress {
  const SmartLayoutRecognitionProgress.page({this.pageLabel})
    : isBlockStage = false,
      completed = 0,
      total = 0;

  const SmartLayoutRecognitionProgress.blocks({
    required this.completed,
    required this.total,
    this.pageLabel,
  }) : isBlockStage = true;

  /// true = 裁剪重问逐块转写阶段；false = 整页识别阶段。
  final bool isBlockStage;
  final int completed;
  final int total;
  final String? pageLabel;

  String get label {
    final stage = !isBlockStage || total <= 0
        ? '正在识别页面…'
        : '正在识别文字 $completed/$total';
    return pageLabel == null ? stage : '$pageLabel · $stage';
  }
}

/// 识别进行中的轻量浮层：进度文案 + 取消按钮。
/// 用 ValueNotifier 驱动原位刷新（SnackBar 不能改文案，逐条 hide/show 会抖动）。
class SmartLayoutProgressOverlay extends StatelessWidget {
  const SmartLayoutProgressOverlay({
    super.key,
    required this.progress,
    this.onCancel,
  });

  final SmartLayoutRecognitionProgress progress;

  /// null = 不显示取消按钮。
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(progress.label, style: theme.textTheme.bodyMedium),
            if (onCancel != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onCancel, child: const Text('取消')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 非模态底部"预览确认"悬浮条（画布全程可见，红区/蓝框不被遮挡）。
/// 风格由 AI 自主决定（不提供人工切换）；按钮随页数/失败情况显隐，
/// 可用宽度不足时动作区自动换行（不溢出）。
class SmartLayoutConfirmBar extends StatelessWidget {
  const SmartLayoutConfirmBar({
    super.key,
    required this.plan,
    required this.isMultiPage,
    required this.onAction,
    this.onProofread,
    this.currentKind,
    this.availableKinds = const [],
    this.onTemplateSelected,
    this.keepHandwriting = false,
    this.onReviewAll,
  });

  final SmartLayoutPlan plan;
  final bool isMultiPage;
  final ValueChanged<SmartLayoutBarAction> onAction;

  /// 低置信文本校对入口；为 null 表示本页没有可校对项（隐藏按钮）。
  final Future<void> Function()? onProofread;

  /// 当前草稿模板；为 null 表示不显示模板切换 chips（向后兼容旧调用方）。
  final SmartLayoutTemplateKind? currentKind;

  /// 可切换的模板集合（当前模式下放得下的种类）；不在其中的 chip 置灰。
  final List<SmartLayoutTemplateKind> availableKinds;

  /// 点选其他模板 chip：由页面取消当前草稿并按新模板重建；当前模板点选无效。
  final ValueChanged<SmartLayoutTemplateKind>? onTemplateSelected;

  /// 保留手写模式：文本以墨迹移动占位，标题旁标注"保留手写"。
  final bool keepHandwriting;

  /// 全文核对入口（草稿全部智能排版文本项，不只低置信）；为 null 隐藏按钮。
  final Future<void> Function()? onReviewAll;

  bool get _hasFailures =>
      plan.failedStrokeIds.isNotEmpty || plan.failureRects.isNotEmpty;

  /// 模板切换 chips 行：三个模板横排，当前模板高亮、放不下的置灰。
  Widget? _buildTemplateChips(BuildContext context) {
    final onSelected = onTemplateSelected;
    if (currentKind == null || onSelected == null) return null;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final kind in SmartLayoutTemplateKind.values)
          ChoiceChip(
            label: Text(kind.displayName),
            selected: kind == currentKind,
            visualDensity: VisualDensity.compact,
            // 当前模板：保持高亮但点选无效；放不下的模板：置灰。
            onSelected: (kind == currentKind || availableKinds.contains(kind))
                ? (_) {
                    if (kind != currentKind) onSelected(kind);
                  }
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowConfidenceCount = plan.lowConfidenceTexts.length;
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${plan.style.displayName} · 置信度 '
              '${(plan.confidence * 100).round()}%',
              style: theme.textTheme.titleSmall,
            ),
            if (keepHandwriting) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text('保留手写', style: theme.textTheme.labelSmall),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          plan.description,
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // 置信度可解释（走查 #6）：解释橙框含义，低置信为 0 时给正向确认。
        // 红区存在时"全部内容识别把握良好"与红区提示自相矛盾（第七轮），
        // 只在无红区时显示正向确认。
        if (lowConfidenceCount > 0 || plan.failureRects.isEmpty)
          Text(
            lowConfidenceCount > 0
                ? '有 $lowConfidenceCount 处内容识别把握较低（画布橙框标出），'
                      '建议校对后再应用'
                : '全部内容识别把握良好',
            style: theme.textTheme.bodySmall?.copyWith(
              color: lowConfidenceCount > 0
                  ? const Color(0xFFF08C00)
                  : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (plan.failureRects.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '${plan.failureRects.length} 处手写未识别成功（红色区域）：'
            '应用将保留笔迹，可改用"删除未识别笔迹后应用"。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (onProofread != null)
          lowConfidenceCount > 0
              ? FilledButton.tonal(
                  onPressed: onProofread,
                  child: Text('校对 $lowConfidenceCount 处'),
                )
              : TextButton(
                  onPressed: onProofread,
                  child: Text('校对 $lowConfidenceCount 处'),
                ),
        if (onReviewAll != null)
          TextButton(onPressed: onReviewAll, child: const Text('核对全文')),
        if (_hasFailures)
          TextButton(
            onPressed: () => onAction(SmartLayoutBarAction.applyAndDrop),
            child: const Text('删除未识别笔迹后应用'),
          ),
        TextButton(
          onPressed: () => onAction(SmartLayoutBarAction.retry),
          child: const Text('重新识别'),
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
        FilledButton(
          onPressed: () => onAction(SmartLayoutBarAction.apply),
          child: const Text('应用'),
        ),
      ],
    );
    // 宽度充足：说明在左、动作在右（原布局）；不足：上下两段、动作区换行。
    Widget body = LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 720
          ? Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                actions,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 8),
                actions,
              ],
            ),
    );
    final chips = _buildTemplateChips(context);
    if (chips != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chips,
          const SizedBox(height: 8),
          body,
        ],
      );
    }
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: body,
      ),
    );
  }
}

/// 草稿态低置信文本校对编辑条：逐项展示并允许改字，保存即更新草稿场景。
/// [headerNote] 覆盖默认说明文案（"核对全文"入口传全量模式的说明）。
class SmartLayoutProofreadSheet extends StatefulWidget {
  const SmartLayoutProofreadSheet({
    super.key,
    required this.items,
    required this.onRevise,
    this.headerNote,
  });

  final List<({ElementId id, String text})> items;
  final bool Function(ElementId id, String newText) onRevise;

  /// 顶部说明文案；为 null 用低置信校对默认文案。
  final String? headerNote;

  @override
  State<SmartLayoutProofreadSheet> createState() =>
      _SmartLayoutProofreadSheetState();
}

class _SmartLayoutProofreadSheetState extends State<SmartLayoutProofreadSheet> {
  final Map<int, TextEditingController> _controllers = {};
  // 每项最近一次已保存的文本：既是"已保存"标记，也是再次改动的比较基准
  // （支持保存后继续修改再保存，而不是锁死）。
  final Map<int, String> _savedTexts = {};

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
    final text = _controllers[index]!.text;
    if (!widget.onRevise(id, text)) return;
    setState(() => _savedTexts[index] = text);
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
              widget.headerNote ??
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
                  final baseline = _savedTexts[index] ?? item.text;
                  final saved =
                      _savedTexts.containsKey(index) &&
                      controller.text.trim() == baseline.trim();
                  final changed =
                      controller.text.trim() != baseline.trim();
                  // 空文本禁用保存（会产生不可见的空文字元素）。
                  final canSave =
                      changed && controller.text.trim().isNotEmpty;
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
                          onPressed: canSave
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
