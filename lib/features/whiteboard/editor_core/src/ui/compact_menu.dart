library;

import 'package:flutter/material.dart';

import 'color_picker.dart' as cp;
import 'hamburger_menu.dart';
import 'markdraw_controller.dart';
import 'color_utils.dart' show canvasBackgroundPresets;

/// Compact menu button (top-left on mobile).
class CompactMenuButton extends StatelessWidget {
  final MarkdrawController controller;
  final ThemeMode? currentThemeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;
  final VoidCallback? onImportImage;
  final VoidCallback? onShowLibrary;
  final VoidCallback? onDocumentRenamed;

  const CompactMenuButton({
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
    this.onShowLibrary,
    this.onDocumentRenamed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.menu, size: 24),
        tooltip: '菜单',
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: () => _showCompactMenu(context),
      ),
    );
  }

  void _showCompactMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (onOpen != null)
              _compactMenuItem(Icons.folder_open, '打开', () {
                Navigator.pop(ctx);
                onOpen!();
              }),
            if (onSave != null)
              _compactMenuItem(Icons.save, '保存', () {
                Navigator.pop(ctx);
                onSave!();
              }),
            if (onSaveAs != null)
              _compactMenuItem(Icons.save_as, '另存为', () {
                Navigator.pop(ctx);
                onSaveAs!();
              }),
            if (onOpen != null || onSave != null || onSaveAs != null)
              const Divider(),
            _compactMenuItem(Icons.drive_file_rename_outline, '重命名', () {
              Navigator.pop(ctx);
              showRenameDocumentDialog(
                context,
                controller,
                onDocumentRenamed,
              );
            }),
            if (onExportPng != null)
              _compactMenuItem(Icons.image, '导出 PNG', () {
                Navigator.pop(ctx);
                onExportPng!();
              }),
            if (onExportSvg != null)
              _compactMenuItem(Icons.code, '导出 SVG', () {
                Navigator.pop(ctx);
                onExportSvg!();
              }),
            if (onExportPng != null || onExportSvg != null) const Divider(),
            if (onImportImage != null)
              _compactMenuItem(Icons.add_photo_alternate, '导入图片', () {
                Navigator.pop(ctx);
                onImportImage!();
              }),
            if (onShowLibrary != null)
              _compactMenuItem(Icons.library_books, '素材库', () {
                Navigator.pop(ctx);
                onShowLibrary!();
              }),
            _compactMenuItem(
              controller.gridSize != null ? Icons.grid_on : Icons.grid_off,
              '网格${controller.gridSize != null ? "开启" : "关闭"}',
              () {
                Navigator.pop(ctx);
                controller.toggleGrid();
              },
            ),
            const Divider(),
            if (onThemeModeChanged != null) _buildCompactThemeRow(ctx),
            _buildCompactCanvasBackgroundRow(ctx),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactThemeRow(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final current = currentThemeMode ?? ThemeMode.system;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('主题', style: TextStyle(fontSize: 16, color: cs.onSurface)),
          const Spacer(),
          _themeButton(
            ctx,
            Icons.light_mode,
            '浅色',
            current == ThemeMode.light,
            ThemeMode.light,
            cs,
          ),
          const SizedBox(width: 4),
          _themeButton(
            ctx,
            Icons.dark_mode,
            '深色',
            current == ThemeMode.dark,
            ThemeMode.dark,
            cs,
          ),
          const SizedBox(width: 4),
          _themeButton(
            ctx,
            Icons.brightness_auto,
            '跟随系统',
            current == ThemeMode.system,
            ThemeMode.system,
            cs,
          ),
        ],
      ),
    );
  }

  Widget _themeButton(
    BuildContext ctx,
    IconData icon,
    String tooltip,
    bool isActive,
    ThemeMode mode,
    ColorScheme cs,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            onThemeModeChanged?.call(mode);
            Navigator.pop(ctx);
          },
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCanvasBackgroundRow(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('背景', style: TextStyle(fontSize: 16, color: cs.onSurface)),
          const Spacer(),
          for (final c in canvasBackgroundPresets)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: cp.ColorSwatch(
                color: c,
                isSelected: controller.canvasBackgroundColor == c,
                onTap: () {
                  controller.canvasBackgroundColor = c;
                  Navigator.pop(ctx);
                },
              ),
            ),
        ],
      ),
    );
  }

  ListTile _compactMenuItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      onTap: onTap,
    );
  }
}
