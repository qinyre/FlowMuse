import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../models/note_item.dart';
import '../repositories/library_repository.dart';

class CreateNotePage extends ConsumerStatefulWidget {
  const CreateNotePage({super.key});

  @override
  ConsumerState<CreateNotePage> createState() => _CreateNotePageState();
}

class _CreateNotePageState extends ConsumerState<CreateNotePage> {
  static const _primary = Color(0xFF4F8F84);

  String _title = '';
  NoteType _noteType = NoteType.unbounded;
  PageTemplate _pageTemplate = PageTemplate.blank;
  bool _creating = false;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final GlobalKey<EditableTextState> _titleEditableKey =
      GlobalKey<EditableTextState>();

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  Future<void> _createNote() async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      final note = await ref
          .read(libraryIndexProvider.notifier)
          .createNote(
            noteType: _noteType,
            pageTemplate: _pageTemplate,
            title: _title,
          );
      if (!mounted) {
        return;
      }
      context.push(AppRoutes.whiteboardPath(noteId: note.id));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _showImportHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先创建笔记后，在白板页使用打开文件导入。')),
    );
  }

  void _focusTitle() {
    FocusScope.of(context).requestFocus(_titleFocusNode);
    _titleEditableKey.currentState?.requestKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleEditableKey.currentState?.requestKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageInset),
          child: Column(
            children: [
              _TopBar(creating: _creating, onCreate: _createNote),
              const SizedBox(height: 34),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 28,
                          runSpacing: 18,
                          children: [
                            _LargePaperPreview(template: _pageTemplate),
                            _NoteSetupPanel(
                              titleController: _titleController,
                              titleFocusNode: _titleFocusNode,
                              titleEditableKey: _titleEditableKey,
                              onTitleTap: _focusTitle,
                              titleChanged: (value) => _title = value,
                              noteType: _noteType,
                              onNoteTypeChanged: (value) {
                                setState(() => _noteType = value);
                              },
                              onImport: _showImportHint,
                              onSubmitted: _createNote,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
                      _SectionTitle(text: '选择页面模板'),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final template in PageTemplate.values) ...[
                              _TemplateCard(
                                template: template,
                                selected: _pageTemplate == template,
                                onTap: () {
                                  setState(() => _pageTemplate = template);
                                },
                              ),
                              if (template != PageTemplate.values.last)
                                const SizedBox(width: 22),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.creating, required this.onCreate});

  final bool creating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4F8F84),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: const Text('取消'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: creating ? null : onCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8F84),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: Text(creating ? '创建中' : '创建'),
            ),
          ],
        ),
        Text(
          '新建笔记',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF1F2624),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LargePaperPreview extends StatelessWidget {
  const _LargePaperPreview({required this.template});

  final PageTemplate template;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x144F8F84),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4F8F84)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 94,
              height: 133,
              child: _PaperSurface(template: template),
            ),
            const SizedBox(height: 12),
            Text(
              _templateLabel(template),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF4F8F84),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteSetupPanel extends StatelessWidget {
  const _NoteSetupPanel({
    required this.titleController,
    required this.titleFocusNode,
    required this.titleEditableKey,
    required this.onTitleTap,
    required this.titleChanged,
    required this.noteType,
    required this.onNoteTypeChanged,
    required this.onImport,
    required this.onSubmitted,
  });

  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final GlobalKey<EditableTextState> titleEditableKey;
  final VoidCallback onTitleTap;
  final ValueChanged<String> titleChanged;
  final NoteType noteType;
  final ValueChanged<NoteType> onNoteTypeChanged;
  final VoidCallback onImport;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 390, minWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE9EEEB)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TitleInput(
                controller: titleController,
                focusNode: titleFocusNode,
                editableKey: titleEditableKey,
                onTap: onTitleTap,
                onChanged: titleChanged,
                onSubmitted: onSubmitted,
              ),
              const SizedBox(height: 14),
              _PanelRow(
                label: '类型',
                child: SegmentedButton<NoteType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: NoteType.bounded,
                      label: Text('有界'),
                      icon: Icon(LucideIcons.fileText),
                    ),
                    ButtonSegment(
                      value: NoteType.unbounded,
                      label: Text('无界'),
                      icon: Icon(LucideIcons.infinity),
                    ),
                  ],
                  selected: {noteType},
                  onSelectionChanged: (value) {
                    onNoteTypeChanged(value.first);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _PanelRow(
                label: '导入',
                child: IconButton.outlined(
                  tooltip: '导入文件',
                  onPressed: onImport,
                  icon: const Icon(LucideIcons.upload),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleInput extends StatelessWidget {
  const _TitleInput({
    required this.controller,
    required this.focusNode,
    required this.editableKey,
    required this.onTap,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<EditableTextState> editableKey;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF1F2624),
        ) ??
        const TextStyle(color: Color(0xFF1F2624), fontSize: 16);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onTap(),
      child: Container(
        height: 48,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F1),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.centerLeft,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isNotEmpty) {
                  return const SizedBox.shrink();
                }
                return IgnorePointer(
                  child: Text(
                    '输入笔记标题',
                    style: textStyle.copyWith(color: const Color(0xFF8C9691)),
                  ),
                );
              },
            ),
            EditableText(
              key: editableKey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: const Color(0xFF4F8F84),
              backgroundCursorColor: const Color(0xFFC9D4CF),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.start,
              maxLines: 1,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: const Color(0xFF1F2624),
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        child,
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: const Color(0xFF1F2624),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PageTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 126,
      height: 222,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 106,
              height: 150,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected ? const Color(0x144F8F84) : Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF4F8F84)
                      : const Color(0xFFE3E8E5),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: _PaperSurface(template: template),
            ),
            const SizedBox(height: 10),
            Text(
              _templateLabel(template),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected
                    ? const Color(0xFF4F8F84)
                    : const Color(0xFF555C59),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 20,
              child: selected
                  ? const Icon(
                      LucideIcons.circleCheck,
                      color: Color(0xFF4F8F84),
                      size: 20,
                    )
                  : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _PaperSurface extends StatelessWidget {
  const _PaperSurface({required this.template});

  final PageTemplate template;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: _TemplatePreviewPainter(template),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  const _TemplatePreviewPainter(this.template);

  final PageTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9D4CF)
      ..strokeWidth = 1;

    switch (template) {
      case PageTemplate.blank:
        return;
      case PageTemplate.narrowLine:
        for (var y = 10.0; y < size.height; y += 9) {
          canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), paint);
        }
      case PageTemplate.wideLine:
        for (var y = 14.0; y < size.height; y += 15) {
          canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), paint);
        }
      case PageTemplate.grid:
        for (var x = 10.0; x < size.width; x += 10) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 10.0; y < size.height; y += 10) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case PageTemplate.dotGrid:
        for (var x = 10.0; x < size.width; x += 10) {
          for (var y = 10.0; y < size.height; y += 10) {
            canvas.drawCircle(Offset(x, y), 1, paint);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) {
    return oldDelegate.template != template;
  }
}

String _templateLabel(PageTemplate template) {
  return switch (template) {
    PageTemplate.blank => '空白',
    PageTemplate.narrowLine => '窄横线',
    PageTemplate.wideLine => '宽横线',
    PageTemplate.grid => '格纹',
    PageTemplate.dotGrid => '点阵',
  };
}
