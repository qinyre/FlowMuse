library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../markdraw.dart' hide TextAlign;

/// Shows a dialog to rename the document.
void showRenameDocumentDialog(
  BuildContext context,
  MarkdrawController controller,
) {
  final textController = TextEditingController(
    text: controller.documentName ?? '',
  );
  showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Document name',
          hintText: 'Document name',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(textController.text),
          child: const Text('OK'),
        ),
      ],
    ),
  ).then((value) {
    if (value != null) {
      controller.renameDocument(value);
    }
  });
}

/// Desktop hamburger menu (top-left).
class HamburgerMenu extends StatelessWidget {
  final MarkdrawController controller;
  final ThemeMode? currentThemeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;
  final VoidCallback? onImportImage;

  const HamburgerMenu({
    super.key,
    required this.controller,
    this.currentThemeMode,
    this.onThemeModeChanged,
    this.onOpen,
    this.onSave,
    this.onSaveAs,
    this.onExportPng,
    this.onExportSvg,
    this.onImportImage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMac = Theme.of(context).platform == TargetPlatform.macOS || kIsWeb;
    final mod = isMac ? 'Cmd' : 'Ctrl';
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.menu, size: 20),
        tooltip: 'Menu',
        offset: const Offset(0, 40),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onSelected: (value) {
          switch (value) {
            case 'open':
              onOpen?.call();
            case 'save':
              onSave?.call();
            case 'save_as':
              onSaveAs?.call();
            case 'rename':
              _showRenameDialog(context);
            case 'export_png':
              onExportPng?.call();
            case 'export_svg':
              onExportSvg?.call();
            case 'library':
              controller.showLibraryPanel = !controller.showLibraryPanel;
            case 'import_image':
              onImportImage?.call();
            case 'toggle_grid':
              controller.toggleGrid();
            case 'snap_to_objects':
              controller.toggleObjectsSnapMode();
            case 'frame_tool':
              controller.switchTool(ToolType.frame);
            case 'reset_canvas':
              controller.resetCanvas();
            case 'zen_mode':
              controller.toggleZenMode();
            case 'view_mode':
              controller.toggleViewMode();
          }
        },
        itemBuilder: (context) => [
          if (onOpen != null)
            _menuItem(context, 'open', Icons.folder_open, 'Open', '$mod+O'),
          if (onSave != null)
            _menuItem(context, 'save', Icons.save, 'Save', '$mod+S'),
          if (onSaveAs != null)
            _menuItem(
              context,
              'save_as',
              Icons.save_as,
              'Save As',
              '$mod+Shift+S',
            ),
          _menuItem(
            context,
            'rename',
            Icons.drive_file_rename_outline,
            'Rename...',
            null,
          ),
          if (onOpen != null || onSave != null || onSaveAs != null)
            const PopupMenuDivider(),
          if (onExportPng != null)
            _menuItem(
              context,
              'export_png',
              Icons.image,
              'Export PNG',
              '$mod+Shift+E',
            ),
          if (onExportSvg != null)
            _menuItem(context, 'export_svg', Icons.code, 'Export SVG', null),
          if (onExportPng != null || onExportSvg != null)
            const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'library',
            child: Row(
              children: [
                Icon(
                  Icons.library_books,
                  size: 18,
                  color: controller.showLibraryPanel
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Library')),
                if (controller.showLibraryPanel)
                  Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ),
          ),
          if (onImportImage != null)
            _menuItem(
              context,
              'import_image',
              Icons.add_photo_alternate,
              'Import Image',
              '9',
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'toggle_grid',
            child: Row(
              children: [
                Icon(
                  Icons.grid_on,
                  size: 18,
                  color: controller.gridSize != null
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Grid')),
                Text(
                  "$mod+'",
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (controller.gridSize != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: cs.primary),
                  ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'snap_to_objects',
            child: Row(
              children: [
                Icon(
                  Icons.straighten,
                  size: 18,
                  color: controller.objectsSnapMode
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Snap to Objects')),
                Text(
                  'Alt+S',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (controller.objectsSnapMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: cs.primary),
                  ),
              ],
            ),
          ),
          _menuItem(context, 'frame_tool', Icons.crop_free, 'Frame Tool', 'F'),
          _menuItem(
            context,
            'reset_canvas',
            Icons.delete_sweep,
            'Reset Canvas',
            '$mod+Del',
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'zen_mode',
            child: Row(
              children: [
                Icon(
                  Icons.self_improvement,
                  size: 18,
                  color: controller.zenMode ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Zen Mode')),
                Text(
                  'Alt+Z',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (controller.zenMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: cs.primary),
                  ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'view_mode',
            child: Row(
              children: [
                Icon(
                  Icons.visibility,
                  size: 18,
                  color: controller.viewMode ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('View Mode')),
                Text(
                  'Alt+R',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (controller.viewMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: cs.primary),
                  ),
              ],
            ),
          ),
          if (onThemeModeChanged != null) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              enabled: false,
              padding: EdgeInsets.zero,
              child: ThemeButtons(
                currentThemeMode: currentThemeMode,
                onThemeModeChanged: onThemeModeChanged,
              ),
            ),
          ],
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: CanvasBackgroundPicker(controller: controller),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    showRenameDocumentDialog(context, controller);
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label,
    String? shortcut,
  ) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (shortcut != null)
            Text(
              shortcut,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
