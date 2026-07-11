import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/utils/ui_lifecycle.dart';
import '../repositories/library_repository.dart';

// ---------------------------------------------------------------------------
// 笔记操作菜单
// ---------------------------------------------------------------------------

enum _NoteAction { rename, moveToNotebook, selectTags, delete }

class MoveToNotebookResult {
  final String? notebookId;
  const MoveToNotebookResult({this.notebookId});
}

class NoteActionsMenu extends StatelessWidget {
  const NoteActionsMenu({
    super.key,
    required this.onRename,
    required this.onMoveToNotebook,
    required this.onSelectTags,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onMoveToNotebook;
  final VoidCallback onSelectTags;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Tooltip(
        message: '更多操作',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final selected = await showAnchoredPopupMenu<_NoteAction>(
              context: context,
              items: const [
                PopupMenuItem<_NoteAction>(
                  value: _NoteAction.rename,
                  child: ListTile(
                    leading: Icon(LucideIcons.penLine),
                    title: Text('重命名'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_NoteAction>(
                  value: _NoteAction.moveToNotebook,
                  child: ListTile(
                    leading: Icon(LucideIcons.bookOpen),
                    title: Text('移动至'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_NoteAction>(
                  value: _NoteAction.selectTags,
                  child: ListTile(
                    leading: Icon(LucideIcons.tag),
                    title: Text('选择标签'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_NoteAction>(
                  value: _NoteAction.delete,
                  child: ListTile(
                    leading: Icon(LucideIcons.trash2),
                    title: Text('删除'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            );
            if (selected == null || !context.mounted) {
              return;
            }
            switch (selected) {
              case _NoteAction.rename:
                runAfterUiTeardown(onRename);
              case _NoteAction.moveToNotebook:
                runAfterUiTeardown(onMoveToNotebook);
              case _NoteAction.selectTags:
                runAfterUiTeardown(onSelectTags);
              case _NoteAction.delete:
                runAfterUiTeardown(onDelete);
            }
          },
          child: const SizedBox(
            width: 24,
            height: 24,
            child: Icon(LucideIcons.chevronDown, size: 18),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 移动至笔记本对话框
// ---------------------------------------------------------------------------

class MoveToNotebookDialog extends StatefulWidget {
  const MoveToNotebookDialog({
    super.key,
    required this.currentNotebookId,
  });

  final String? currentNotebookId;

  @override
  State<MoveToNotebookDialog> createState() => _MoveToNotebookDialogState();
}

class _MoveToNotebookDialogState extends State<MoveToNotebookDialog> {
  static const _unfiledNotebookId = '__flow_muse_unfiled_notebook__';

  late String? _selectedNotebookId;

  @override
  void initState() {
    super.initState();
    _selectedNotebookId = widget.currentNotebookId;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final libraryIndex = ref.watch(libraryIndexProvider).asData?.value;
        final notebooks = libraryIndex?.notebooks ?? const [];

        return AlertDialog(
          title: const Text('移动至笔记本'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 未归入选项
                RadioListTile<String>(
                  title: const Text('未归入笔记本'),
                  value: _unfiledNotebookId,
                  groupValue: _selectedNotebookId == null
                      ? _unfiledNotebookId
                      : _selectedNotebookId!,
                  onChanged: (value) {
                    setState(() => _selectedNotebookId = null);
                  },
                ),
                if (notebooks.isNotEmpty) const Divider(),
                // 笔记本列表
                Expanded(
                  child: ListView.builder(
                    itemCount: notebooks.length,
                    itemBuilder: (context, index) {
                      final notebook = notebooks[index];
                      return RadioListTile<String>(
                        title: Text(notebook.name),
                        value: notebook.id,
                        groupValue: _selectedNotebookId == null
                            ? _unfiledNotebookId
                            : _selectedNotebookId!,
                        onChanged: (value) {
                          setState(() => _selectedNotebookId = notebook.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                MoveToNotebookResult(notebookId: _selectedNotebookId),
              ),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 选择标签对话框
// ---------------------------------------------------------------------------

class SelectTagsDialog extends StatefulWidget {
  const SelectTagsDialog({
    super.key,
    required this.currentTagIds,
  });

  final List<String> currentTagIds;

  @override
  State<SelectTagsDialog> createState() => _SelectTagsDialogState();
}

class _SelectTagsDialogState extends State<SelectTagsDialog> {
  late Set<String> _selectedTagIds;
  bool _untaggedSelected = false;

  @override
  void initState() {
    super.initState();
    _selectedTagIds = Set.from(widget.currentTagIds);
    _untaggedSelected = _selectedTagIds.isEmpty;
  }

  void _toggleTag(String tagId) {
    setState(() {
      if (_untaggedSelected) {
        _untaggedSelected = false;
      }
      if (_selectedTagIds.contains(tagId)) {
        _selectedTagIds.remove(tagId);
      } else {
        _selectedTagIds.add(tagId);
      }
      if (_selectedTagIds.isEmpty) {
        _untaggedSelected = true;
      }
    });
  }

  void _toggleUntagged() {
    setState(() {
      _untaggedSelected = !_untaggedSelected;
      if (_untaggedSelected) {
        _selectedTagIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final libraryIndex = ref.watch(libraryIndexProvider).asData?.value;
        final tags = libraryIndex?.tags ?? const [];

        return AlertDialog(
          title: const Text('选择标签'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 未标签选项
                CheckboxListTile(
                  title: const Text('未标签'),
                  value: _untaggedSelected,
                  onChanged: (_) => _toggleUntagged(),
                ),
                if (tags.isNotEmpty) const Divider(),
                // 标签列表
                Expanded(
                  child: ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return CheckboxListTile(
                        title: Text(tag.name),
                        value: _selectedTagIds.contains(tag.id),
                        onChanged: (_) => _toggleTag(tag.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _untaggedSelected ? <String>[] : _selectedTagIds.toList(),
              ),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}
