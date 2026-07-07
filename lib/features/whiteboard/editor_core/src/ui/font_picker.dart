library;

import 'package:flutter/material.dart';

import '../../markdraw.dart' hide TextAlign;

/// Desktop font picker overlay positioned below trigger button.
class FontPickerOverlay extends StatefulWidget {
  final Offset anchor;
  final String currentFont;
  final Set<String> sceneFonts;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const FontPickerOverlay({
    super.key,
    required this.anchor,
    required this.currentFont,
    required this.sceneFonts,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<FontPickerOverlay> createState() => _FontPickerOverlayState();
}

class _FontPickerOverlayState extends State<FontPickerOverlay> {
  @override
  Widget build(BuildContext context) {
    const popupWidth = 240.0;
    const maxPopupHeight = 360.0;

    final screen = MediaQuery.of(context).size;
    var left = widget.anchor.dx;
    var top = widget.anchor.dy + 34;
    if (left + popupWidth > screen.width - 8) {
      left = screen.width - popupWidth - 8;
    }
    if (left < 8) left = 8;
    if (top + maxPopupHeight > screen.height - 8) {
      top = widget.anchor.dy - maxPopupHeight - 4;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: TextFieldTapRegion(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: popupWidth,
                constraints: const BoxConstraints(maxHeight: maxPopupHeight),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: FontListContent(
                  currentFont: widget.currentFont,
                  sceneFonts: widget.sceneFonts,
                  onSelect: widget.onSelect,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared font list content used by both overlay and bottom sheet.
class FontListContent extends StatefulWidget {
  final String currentFont;
  final Set<String> sceneFonts;
  final ValueChanged<String> onSelect;
  final ScrollController? scrollController;

  const FontListContent({
    super.key,
    required this.currentFont,
    required this.sceneFonts,
    required this.onSelect,
    this.scrollController,
  });

  @override
  State<FontListContent> createState() => _FontListContentState();
}

class _FontListContentState extends State<FontListContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();
    const allUiFonts = FontResolver.uiFonts;

    final sceneFontList = allUiFonts
        .where((f) => widget.sceneFonts.contains(f))
        .where((f) => query.isEmpty || f.toLowerCase().contains(query))
        .toList();
    final availableFontList = allUiFonts
        .where((f) => !widget.sceneFonts.contains(f))
        .where((f) => query.isEmpty || f.toLowerCase().contains(query))
        .toList();

    final isDynamicSearch =
        query.isNotEmpty && !allUiFonts.any((f) => f.toLowerCase() == query);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Font name',
              hintText: 'Search fonts...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Flexible(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.only(bottom: 8),
            shrinkWrap: widget.scrollController == null,
            children: [
              if (sceneFontList.isNotEmpty) ...[
                _buildGroupHeader('Scene fonts'),
                for (final font in sceneFontList) _buildFontItem(font),
              ],
              if (availableFontList.isNotEmpty) ...[
                _buildGroupHeader(
                  sceneFontList.isNotEmpty ? 'Available fonts' : 'Fonts',
                ),
                for (final font in availableFontList) _buildFontItem(font),
              ],
              if (isDynamicSearch) _buildDynamicFontItem(_searchQuery),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFontItem(String font) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = font == widget.currentFont;
    final category = FontResolver.categoryOf(font);
    return InkWell(
      onTap: () => widget.onSelect(font),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: isSelected ? cs.primaryContainer : null,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                _categoryIcon(category),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                font,
                style: FontResolver.resolve(
                  font,
                  baseStyle: TextStyle(
                    fontSize: 13,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) Icon(Icons.check, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicFontItem(String searchText) {
    final displayName = searchText
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return InkWell(
      onTap: () => widget.onSelect(displayName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.cloud_download,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Google Font: $displayName',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryIcon(FontCategory category) {
    switch (category) {
      case FontCategory.handDrawn:
        return '~';
      case FontCategory.normal:
        return 'A';
      case FontCategory.code:
        return '</>';
    }
  }
}
