library;

import 'package:flutter/material.dart';

import 'markdraw_controller.dart';

/// Shows a compact library bottom sheet for mobile layout.
void showCompactLibrary(
  BuildContext context,
  MarkdrawController controller, {
  VoidCallback? onImportLibrary,
  VoidCallback? onExportLibrary,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Library',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (onImportLibrary != null)
                    IconButton(
                      icon: const Icon(Icons.file_upload, size: 20),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onImportLibrary();
                      },
                      tooltip: 'Import Library',
                    ),
                  if (onExportLibrary != null)
                    IconButton(
                      icon: const Icon(Icons.file_download, size: 20),
                      onPressed: controller.libraryItems.isEmpty
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              onExportLibrary();
                            },
                      tooltip: 'Export Library',
                    ),
                ],
              ),
            ),
            if (controller.selectedElements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add to Library'),
                    onPressed: () {
                      controller.addToLibrary();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
            Expanded(
              child: controller.libraryItems.isEmpty
                  ? Center(
                      child: Text(
                        'No library items.',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: controller.libraryItems.length,
                      itemBuilder: (context, index) {
                        final item = controller.libraryItems[index];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.elements.length} element${item.elements.length == 1 ? '' : 's'}',
                          ),
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final size = box?.size ?? const Size(800, 600);
                            controller.placeLibraryItem(item, size);
                            Navigator.pop(ctx);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: () {
                              controller.removeLibraryItem(item.id);
                              Navigator.pop(ctx);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
