import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';
import '../models/note_item.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onActionsTap,
    this.selectionControl,
  });

  static const coverWidth = 132.0;
  static const coverHeight = 176.0;
  static const gridMaxCrossAxisExtent = 192.0;
  static const gridMainAxisExtent = 251.0;
  static const compactGridCrossGap = 16.0;
  static const gridCrossGap = 22.0;
  static const compactGridMainGap = 20.0;
  static const gridMainGap = 26.0;

  static double gridHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return coverHeight +
        20 +
        scaler.scale(14) * 2 * 1.45 +
        4 +
        scaler.scale(12) * 1.5;
  }

  final NoteItem item;
  final VoidCallback onTap;
  final void Function(BuildContext context)? onActionsTap;
  final Widget? selectionControl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionsKey = GlobalKey();

    void showActions() {
      final actionsContext = actionsKey.currentContext;
      if (actionsContext != null) {
        onActionsTap!(actionsContext);
      }
    }

    return Column(
      children: [
        SizedBox(
          width: coverWidth,
          height: coverHeight,
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.06),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                InkWell(
                  key: ValueKey('note-card-${item.id}'),
                  onTap: onTap,
                  onLongPress: onActionsTap != null ? showActions : null,
                  child: NoteCover(item: item),
                ),
                if (selectionControl != null)
                  Positioned(top: -8, right: -8, child: selectionControl!),
                if (onActionsTap != null && selectionControl == null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: SizedBox(
                      key: actionsKey,
                      width: AppSpacing.shellHeaderIconButtonSize,
                      height: AppSpacing.shellHeaderIconButtonSize,
                      child: IconButton(
                        key: ValueKey('note-card-actions-${item.id}'),
                        tooltip: '更多操作：${item.title}',
                        onPressed: showActions,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surface.withValues(
                            alpha: 0.94,
                          ),
                          foregroundColor: colorScheme.onSurface,
                          visualDensity: VisualDensity.standard,
                        ),
                        icon: const Icon(LucideIcons.chevronDown, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          item.title,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.date,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class NoteCover extends StatelessWidget {
  const NoteCover({super.key, required this.item});

  final NoteItem item;

  @override
  Widget build(BuildContext context) {
    final thumbnailBytes = item.coverThumbnailBytes;
    final placeholder = _NoteCoverPlaceholder(item: item);
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: item.coverColor),
        child: Image.memory(
          thumbnailBytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return placeholder;
          },
        ),
      );
    }
    return placeholder;
  }
}

class _NoteCoverPlaceholder extends StatelessWidget {
  const _NoteCoverPlaceholder({required this.item});

  final NoteItem item;

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      item.coverColor,
      Theme.of(context).colorScheme.surface,
    );
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF263C36);
    return ExcludeSemantics(
      child: DecoratedBox(
        key: ValueKey('note-cover-placeholder-${item.id}'),
        decoration: BoxDecoration(
          color: background,
          border: Border(
            left: BorderSide(
              width: 5,
              color: foreground.withValues(alpha: 0.14),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTitle =
                constraints.maxWidth >= 100 && constraints.maxHeight >= 140;
            return Padding(
              padding: EdgeInsets.all(showTitle ? 16 : 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.kind == LibraryFilter.pdf
                        ? LucideIcons.fileText
                        : LucideIcons.notebookPen,
                    size: showTitle ? 24 : 18,
                    color: foreground.withValues(alpha: 0.75),
                  ),
                  if (showTitle) ...[
                    const SizedBox(height: 16),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
