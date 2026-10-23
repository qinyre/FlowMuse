import 'package:flutter/material.dart';

import '../utils/ui_lifecycle.dart';

/// 统一外观的下拉选择框：输入框样式触发器 + [showAnchoredValuePicker] 面板。
///
/// 替代 Material 2 观感的 [DropdownButton]，弹出部分走全应用统一的锚点面板。
/// 触发器使用主题的输入框样式，视觉与表单其他字段一致。
class AnchoredDropdownField<T extends Object> extends StatelessWidget {
  const AnchoredDropdownField({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    this.decoration,
    this.enabled = true,
    this.onChanged,
  });

  final T? value;
  final Iterable<T> options;
  final String Function(T option) labelOf;
  final InputDecoration? decoration;
  final bool enabled;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final canOpen = enabled && onChanged != null && options.isNotEmpty;
    return InputDecorator(
      decoration: (decoration ?? const InputDecoration()).copyWith(
        enabled: canOpen,
      ),
      isEmpty: value == null,
      child: Builder(
        builder: (fieldContext) => InkWell(
          onTap: !canOpen
              ? null
              : () async {
                  final selected = await showAnchoredValuePicker<T>(
                    context: fieldContext,
                    value: value,
                    options: options,
                    label: labelOf,
                  );
                  if (selected == null || !fieldContext.mounted) {
                    return;
                  }
                  onChanged?.call(selected);
                },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value == null ? '' : labelOf(value!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}
