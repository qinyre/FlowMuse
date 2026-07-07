library;

import 'package:flutter/material.dart';

import '../core/library/library_item.dart';
import 'markdraw_controller.dart';

/// Desktop library panel (right side).
class LibraryPanel extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onImportLibrary;
  final VoidCallback? onExportLibrary;

  const LibraryPanel({
    super.key,
    required this.controller,
    this.onImportLibrary,
    this.onExportLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = controller.libraryItems;
    final hasSelection = controller.selectedElements.isNotEmpty;

    return Container(
      width: 200,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
        color: cs.surfaceContainerLowest,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Library',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (onImportLibrary != null)
                  IconButton(
                    icon: const Icon(Icons.file_upload, size: 18),
                    onPressed: onImportLibrary,
                    tooltip: 'Import Library',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                if (onExportLibrary != null)
                  IconButton(
                    icon: const Icon(Icons.file_download, size: 18),
                    onPressed: items.isEmpty ? null : onExportLibrary,
                    tooltip: 'Export Library',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => controller.showLibraryPanel = false,
                  tooltip: 'Close',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          ),
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add to Library'),
                  onPressed: controller.addToLibrary,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No library items.\nSelect elements and click "Add to Library".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final tile = ListTile(
                        dense: true,
                        title: Text(
                          item.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${item.elements.length} element${item.elements.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final size = box?.size ?? const Size(800, 600);
                          controller.placeLibraryItem(item, size);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 16),
                          onPressed: () =>
                              controller.removeLibraryItem(item.id),
                          tooltip: 'Remove',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      );
                      return Draggable<LibraryItem>(
                        data: item,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.name,
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.4, child: tile),
                        child: tile,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
