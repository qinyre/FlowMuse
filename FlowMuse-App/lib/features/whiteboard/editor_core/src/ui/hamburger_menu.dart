library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;

/// Shows a dialog to rename the document.
void showRenameDocumentDialog(
  BuildContext context,
  MarkdrawController controller,
  VoidCallback? onRenamed,
) {
  showDialog<String>(
    context: context,
    builder: (context) =>
        _RenameDocumentDialog(initialName: controller.documentName ?? ''),
  ).then((value) {
    if (value != null) {
      runAfterUiTeardown(() {
        controller.renameDocument(value);
        onRenamed?.call();
      });
    }
  });
}

class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    Navigator.of(context).pop(value ?? _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '文档名称', hintText: '文档名称'),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
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
  final VoidCallback? onExportSmartMarkdown;
  final VoidCallback? onExportSmartLatex;
  final VoidCallback? onShare;
  final VoidCallback? onImportImage;
  final VoidCallback? onDocumentRenamed;

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
    this.onExportSmartMarkdown,
    this.onExportSmartLatex,
    this.onShare,
    this.onImportImage,
    this.onDocumentRenamed,
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
          BoxShadow(color: cs.shadow.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 3),
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.menu, size: 20),
        tooltip: '菜单',
        offset: const Offset(0, 40),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onSelected: (value) {
          runAfterUiTeardown(() {
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
              case 'export_smart_md':
                onExportSmartMarkdown?.call();
              case 'export_smart_tex':
                onExportSmartLatex?.call();
              case 'share':
                onShare?.call();
              case 'library':
                controller.showLibraryPanel = !controller.showLibraryPanel;
              case 'markdown':
                controller.toggleMarkdownPanel();
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
          });
        },
        itemBuilder: (context) => [
          if (onOpen != null)
            _menuItem(context, 'open', Icons.folder_open, '打开', '$mod+O'),
          if (onSave != null)
            _menuItem(context, 'save', Icons.save, '保存', '$mod+S'),
          if (onSaveAs != null)
            _menuItem(context, 'save_as', Icons.save_as, '另存为', '$mod+Shift+S'),
          _menuItem(
            context,
            'rename',
            Icons.drive_file_rename_outline,
            '重命名...',
            null,
          ),
          if (onOpen != null || onSave != null || onSaveAs != null)
            const PopupMenuDivider(),
          if (onExportPng != null)
            _menuItem(
              context,
              'export_png',
              Icons.image,
              '导出 PNG',
              '$mod+Shift+E',
            ),
          if (onExportSvg != null)
            _menuItem(context, 'export_svg', Icons.code, '导出 SVG', null),
          if (onExportSmartMarkdown != null)
            _menuItem(
              context,
              'export_smart_md',
              Symbols.markdown,
              '导出智能排版 Markdown',
              null,
              enabled: controller.canExportSmartLayout,
            ),
          if (onExportSmartLatex != null)
            _menuItem(
              context,
              'export_smart_tex',
              Icons.functions,
              '导出智能排版 LaTeX',
              null,
              enabled: controller.canExportSmartLayout,
            ),
          if (onShare != null)
            _menuItem(context, 'share', Icons.share, '分享', null),
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
                const Expanded(child: Text('素材库')),
                if (controller.showLibraryPanel)
                  Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'markdown',
            child: Row(
              children: [
                Icon(
                  Symbols.markdown,
                  size: 18,
                  color: controller.showMarkdownPanel
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Markdown 面板')),
                if (controller.showMarkdownPanel)
                  Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ),
          ),
          if (onImportImage != null)
            _menuItem(
              context,
              'import_image',
              Icons.add_photo_alternate,
              '导入图片',
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
                const Expanded(child: Text('网格')),
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
                const Expanded(child: Text('吸附到对象')),
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
          _menuItem(context, 'frame_tool', Icons.crop_free, '画框工具', 'F'),
          _menuItem(
            context,
            'reset_canvas',
            Icons.delete_sweep,
            '重置画布',
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
                const Expanded(child: Text('专注模式')),
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
                const Expanded(child: Text('查看模式')),
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
    showRenameDocumentDialog(context, controller, onDocumentRenamed);
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label,
    String? shortcut, {
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled
                ? cs.onSurfaceVariant
                : cs.onSurfaceVariant.withValues(alpha: 0.45),
          ),
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
