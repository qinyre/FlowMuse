library;

import 'package:flutter/material.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'markdraw_controller.dart';

/// Shows a compact library bottom sheet for mobile layout.
void showCompactLibrary(
  BuildContext context,
  MarkdrawController controller, {
  VoidCallback? onImportLibrary,
  VoidCallback? onExportLibrary,
}) {
  void closeThen(BuildContext ctx, VoidCallback action) {
    Navigator.pop(ctx);
    runAfterUiTeardown(action);
  }

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
                    '素材库',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (onImportLibrary != null)
                    IconButton(
                      icon: const Icon(Icons.file_upload, size: 20),
                      onPressed: () {
                        closeThen(ctx, onImportLibrary);
                      },
                      tooltip: '导入素材库',
                    ),
                  if (onExportLibrary != null)
                    IconButton(
                      icon: const Icon(Icons.file_download, size: 20),
                      onPressed: controller.libraryItems.isEmpty
                          ? null
                          : () {
                              closeThen(ctx, onExportLibrary);
                            },
                      tooltip: '导出素材库',
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
                    label: const Text('添加到素材库'),
                    onPressed: () {
                      closeThen(ctx, controller.addToLibrary);
                    },
                  ),
                ),
              ),
            Expanded(
              child: controller.libraryItems.isEmpty
                  ? Center(
                      child: Text(
                        '暂无素材。',
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
                          subtitle: Text('${item.elements.length} 个元素'),
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final size = box?.size ?? const Size(800, 600);
                            closeThen(
                              ctx,
                              () => controller.placeLibraryItem(item, size),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: () {
                              closeThen(
                                ctx,
                                () => controller.removeLibraryItem(item.id),
                              );
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
