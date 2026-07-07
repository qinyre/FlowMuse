/// Autocomplete prompts and dropdown builder for .markdraw sketch syntax.
library;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Element keywords that trigger auto-ID insertion on autocomplete.
const Set<String> elementKeywords = {
  'rect',
  'ellipse',
  'diamond',
  'line',
  'arrow',
  'text',
  'freedraw',
  'frame',
  'image',
};

/// Returns the next available element ID for [keyword] given [currentText].
///
/// Scans [currentText] for existing `id=` values matching `<keyword><N>` and
/// returns the first unused `<keyword><N>` starting from 1.
String nextElementId(String keyword, String currentText) {
  final existing = <int>{};
  final pattern = RegExp(r'\bid=(' + RegExp.escape(keyword) + r')(\d+)\b');
  for (final match in pattern.allMatches(currentText)) {
    final n = int.tryParse(match.group(2)!);
    if (n != null) existing.add(n);
  }
  var i = 1;
  while (existing.contains(i)) {
    i++;
  }
  return '$keyword$i';
}

/// All keyword prompts for .markdraw autocomplete.
const List<CodeKeywordPrompt> markdrawPrompts = [
  // Element keywords
  CodeKeywordPrompt(word: 'rect'),
  CodeKeywordPrompt(word: 'ellipse'),
  CodeKeywordPrompt(word: 'diamond'),
  CodeKeywordPrompt(word: 'line'),
  CodeKeywordPrompt(word: 'arrow'),
  CodeKeywordPrompt(word: 'text'),
  CodeKeywordPrompt(word: 'freedraw'),
  CodeKeywordPrompt(word: 'frame'),
  CodeKeywordPrompt(word: 'image'),

  // Position keywords
  CodeKeywordPrompt(word: 'from'),
  CodeKeywordPrompt(word: 'to'),
  CodeKeywordPrompt(word: 'at'),

  // Property keys
  CodeKeywordPrompt(word: 'id'),
  CodeKeywordPrompt(word: 'fill'),
  CodeKeywordPrompt(word: 'color'),
  CodeKeywordPrompt(word: 'stroke'),
  CodeKeywordPrompt(word: 'fill-style'),
  CodeKeywordPrompt(word: 'stroke-width'),
  CodeKeywordPrompt(word: 'roughness'),
  CodeKeywordPrompt(word: 'opacity'),
  CodeKeywordPrompt(word: 'rounded'),
  CodeKeywordPrompt(word: 'angle'),
  CodeKeywordPrompt(word: 'frame'),
  CodeKeywordPrompt(word: 'group'),
  CodeKeywordPrompt(word: 'file'),
  CodeKeywordPrompt(word: 'crop'),
  CodeKeywordPrompt(word: 'scale'),
  CodeKeywordPrompt(word: 'arrow-type'),
  CodeKeywordPrompt(word: 'start-arrow'),
  CodeKeywordPrompt(word: 'end-arrow'),
  CodeKeywordPrompt(word: 'points'),
  CodeKeywordPrompt(word: 'pressure'),
  CodeKeywordPrompt(word: 'text-size'),
  CodeKeywordPrompt(word: 'text-font'),
  CodeKeywordPrompt(word: 'text-align'),
  CodeKeywordPrompt(word: 'text-valign'),
  CodeKeywordPrompt(word: 'text-color'),
  CodeKeywordPrompt(word: 'size'),
  CodeKeywordPrompt(word: 'font'),
  CodeKeywordPrompt(word: 'align'),
  CodeKeywordPrompt(word: 'valign'),

  // Property values — stroke/fill styles
  CodeKeywordPrompt(word: 'solid'),
  CodeKeywordPrompt(word: 'dashed'),
  CodeKeywordPrompt(word: 'dotted'),
  CodeKeywordPrompt(word: 'hachure'),
  CodeKeywordPrompt(word: 'cross-hatch'),
  CodeKeywordPrompt(word: 'zigzag'),

  // Property values — alignment
  CodeKeywordPrompt(word: 'left'),
  CodeKeywordPrompt(word: 'center'),
  CodeKeywordPrompt(word: 'right'),
  CodeKeywordPrompt(word: 'top'),
  CodeKeywordPrompt(word: 'middle'),
  CodeKeywordPrompt(word: 'bottom'),

  // Property values — roundness
  CodeKeywordPrompt(word: 'sharp'),
  CodeKeywordPrompt(word: 'round'),
  CodeKeywordPrompt(word: 'sharp-elbow'),
  CodeKeywordPrompt(word: 'round-elbow'),

  // Arrowhead values
  CodeKeywordPrompt(word: 'bar'),
  CodeKeywordPrompt(word: 'dot'),
  CodeKeywordPrompt(word: 'triangle'),

  // Flags
  CodeKeywordPrompt(word: 'locked'),
  CodeKeywordPrompt(word: 'closed'),
  CodeKeywordPrompt(word: 'no-simulate-pressure'),

  // Common CSS color names
  CodeKeywordPrompt(word: 'red'),
  CodeKeywordPrompt(word: 'blue'),
  CodeKeywordPrompt(word: 'green'),
  CodeKeywordPrompt(word: 'black'),
  CodeKeywordPrompt(word: 'white'),
  CodeKeywordPrompt(word: 'yellow'),
  CodeKeywordPrompt(word: 'orange'),
  CodeKeywordPrompt(word: 'purple'),
  CodeKeywordPrompt(word: 'pink'),
  CodeKeywordPrompt(word: 'gray'),
  CodeKeywordPrompt(word: 'grey'),
  CodeKeywordPrompt(word: 'brown'),
  CodeKeywordPrompt(word: 'cyan'),
  CodeKeywordPrompt(word: 'magenta'),
  CodeKeywordPrompt(word: 'transparent'),
];

/// A prompts builder that wraps another builder and enhances element keyword
/// prompts with auto-generated `id=` suffixes.
///
/// When the delegate returns prompts for element keywords (e.g. `rect`),
/// they are replaced with [CodeFieldPrompt]s whose [customAutocomplete]
/// inserts `rect id=rect1` (with the index auto-incremented). This works
/// for both Enter key and mouse click selection.
class ElementIdPromptsBuilder implements CodeAutocompletePromptsBuilder {
  ElementIdPromptsBuilder({required this.delegate, required this.controller});

  final CodeAutocompletePromptsBuilder delegate;
  final CodeLineEditingController controller;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final value = delegate.build(context, codeLine, selection);
    if (value == null) return null;

    final currentText = controller.text;
    final enhancedPrompts = value.prompts.map((prompt) {
      if (prompt is CodeKeywordPrompt &&
          elementKeywords.contains(prompt.word)) {
        final id = nextElementId(prompt.word, currentText);
        final enhanced = '${prompt.word} id=$id';
        return CodeFieldPrompt(
          word: prompt.word,
          type: '',
          customAutocomplete: CodeAutocompleteResult(
            word: enhanced,
            input: '',
            selection: TextSelection.collapsed(offset: enhanced.length),
          ),
        );
      }
      return prompt;
    }).toList();

    return value.copyWith(prompts: enhancedPrompts);
  }
}

/// Builds the autocomplete suggestion dropdown.
///
/// Used as the `viewBuilder` for [CodeAutocomplete].
PreferredSizeWidget buildAutocompleteView(
  BuildContext context,
  ValueNotifier<CodeAutocompleteEditingValue> notifier,
  ValueChanged<CodeAutocompleteResult> onSelected,
) {
  return _AutocompleteDropdown(notifier: notifier, onSelected: onSelected);
}

class _AutocompleteDropdown extends StatelessWidget
    implements PreferredSizeWidget {
  const _AutocompleteDropdown({
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const _itemHeight = 28.0;
  static const _maxVisible = 6;

  @override
  Size get preferredSize => const Size(200, _itemHeight * _maxVisible + 8);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: notifier,
      builder: (context, value, _) {
        final prompts = value.prompts;
        if (prompts.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final visibleCount = prompts.length.clamp(1, _maxVisible);

        return Container(
          constraints: BoxConstraints(
            maxHeight: _itemHeight * visibleCount + 8,
            maxWidth: 220,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: prompts.length,
            itemExtent: _itemHeight,
            itemBuilder: (context, index) {
              final prompt = prompts[index];
              final isSelected = index == value.index;
              return InkWell(
                onTap: () =>
                    onSelected(value.copyWith(index: index).autocomplete),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: isSelected
                      ? theme.colorScheme.primary.withAlpha(30)
                      : null,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    prompt.word,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
