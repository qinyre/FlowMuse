import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../whiteboard/editor_core/markdraw.dart'
    show
        CanvasLayout,
        CanvasLayoutType,
        CanvasPageFlow,
        CanvasPageTemplate,
        RoughCanvasAdapter,
        Scene,
        StaticCanvasPainter,
        ViewportState;
import '../../whiteboard/editor_core/src/ui/file_picker_channel_ohos.dart';
import '../../whiteboard/pdf_note_import/pdf_note_import_payload.dart';
import '../../whiteboard/pdf_note_import/pdf_note_import_service.dart';
import '../../whiteboard/collaboration/models/excalidraw_scene.dart';
import '../../whiteboard/repositories/whiteboard_scene_repository.dart';
import '../models/note_item.dart';
import '../repositories/library_repository.dart';

class CreateNotePage extends ConsumerStatefulWidget {
  const CreateNotePage({super.key});

  @override
  ConsumerState<CreateNotePage> createState() => _CreateNotePageState();
}

class _CreateNotePageState extends ConsumerState<CreateNotePage> {
  String _title = '';
  NoteType _noteType = NoteType.paged;
  PageTemplate _pageTemplate = PageTemplate.blank;
  PageFlow _pageFlow = PageFlow.topToBottom;
  bool _creating = false;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();

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
    debugPrint(
      '[FlowMuseCreateNote] CreateNotePage.create pressed '
      'title="$_title" noteType=${_noteType.name} '
      'pageTemplate=${_pageTemplate.name} pageFlow=${_pageFlow.name}',
    );
    setState(() => _creating = true);
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final note = await ref
          .read(libraryRepositoryProvider)
          .createNote(
            noteType: _noteType,
            pageTemplate: _pageTemplate,
            pageFlow: _pageFlow,
            title: _title,
          );
      await defaultWhiteboardSceneRepository.saveScene(
        note.id,
        emptyExcalidrawSceneContent,
      );
      ref.invalidate(libraryIndexProvider);
      debugPrint(
        '[FlowMuseCreateNote] CreateNotePage.create success '
        'noteId=${note.id}',
      );
      if (!mounted) {
        return;
      }
      runWhenUiStable(() {
        if (mounted) {
          context.pushReplacement(AppRoutes.whiteboardPath(noteId: note.id));
        }
      });
    } catch (error, stackTrace) {
      debugPrint('[FlowMuseCreateNote] CreateNotePage.create failed: $error');
      debugPrintStack(
        label: '[FlowMuseCreateNote] CreateNotePage.create stack',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _importPdf() async {
    if (_creating) {
      return;
    }
    debugPrint(
      '[FlowMuseCreateNote] CreateNotePage.importPdf pressed '
      'noteType=${_noteType.name} pageTemplate=${_pageTemplate.name} '
      'pageFlow=${_pageFlow.name}',
    );
    setState(() => _creating = true);
    try {
      final note = await ref
          .read(pdfNoteImportServiceProvider)
          .pickAndStageImport(
            ref.read,
            noteType: _noteType,
            pageTemplate: _pageTemplate,
            pageFlow: _pageFlow,
            picker: () async {
              if (defaultTargetPlatform == TargetPlatform.ohos) {
                try {
                  final files = await pickFilesViaOhosChannel(
                    suffixFilters: const ['PDF文件(.pdf)|.pdf'],
                  );
                  final picked = files.first;
                  return PdfNoteImportPayload(
                    bytes: picked.bytes,
                    name: picked.name,
                  );
                } on PlatformException {
                  return null;
                }
              }
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['pdf'],
                withData: true,
              );
              final file = result?.files.single;
              final bytes = file?.bytes;
              if (file == null || bytes == null) {
                return null;
              }
              return PdfNoteImportPayload(bytes: bytes, name: file.name);
            },
          );
      if (!mounted || note == null) {
        debugPrint('[FlowMuseCreateNote] CreateNotePage.importPdf canceled');
        return;
      }
      debugPrint(
        '[FlowMuseCreateNote] CreateNotePage.importPdf success '
        'noteId=${note.id}',
      );
      context.push(AppRoutes.whiteboardPath(noteId: note.id));
    } catch (error, stackTrace) {
      debugPrint(
        '[FlowMuseCreateNote] CreateNotePage.importPdf failed: $error',
      );
      debugPrintStack(
        label: '[FlowMuseCreateNote] CreateNotePage.importPdf stack',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                              titleChanged: (value) => _title = value,
                              noteType: _noteType,
                              onNoteTypeChanged: (value) {
                                setState(() => _noteType = value);
                              },
                              pageFlow: _pageFlow,
                              onPageFlowChanged: (value) {
                                setState(() => _pageFlow = value);
                              },
                              onImport: () {
                                unawaited(_importPdf());
                              },
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
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              child: const Text('取消'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: creating
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      onCreate();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
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
            color: Theme.of(context).colorScheme.onSurface,
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
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
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
              template.displayName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
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
    required this.titleChanged,
    required this.noteType,
    required this.onNoteTypeChanged,
    required this.pageFlow,
    required this.onPageFlowChanged,
    required this.onImport,
    required this.onSubmitted,
  });

  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final ValueChanged<String> titleChanged;
  final NoteType noteType;
  final ValueChanged<NoteType> onNoteTypeChanged;
  final PageFlow pageFlow;
  final ValueChanged<PageFlow> onPageFlowChanged;
  final VoidCallback onImport;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430, minWidth: 360),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TitleInput(
                controller: titleController,
                focusNode: titleFocusNode,
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
                      value: NoteType.paged,
                      label: Text('分页'),
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
                label: '排列',
                child: SegmentedButton<PageFlow>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: PageFlow.topToBottom,
                      label: Text('上下'),
                      icon: Icon(LucideIcons.arrowDown),
                    ),
                    ButtonSegment(
                      value: PageFlow.rightToLeft,
                      label: Text('右左'),
                      icon: Icon(LucideIcons.arrowLeft),
                    ),
                  ],
                  selected: {pageFlow},
                  onSelectionChanged: noteType == NoteType.paged
                      ? (value) {
                          onPageFlowChanged(value.first);
                        }
                      : null,
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
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        maxLines: 1,
        cursorHeight: 18,
        onTapAlwaysCalled: true,
        onTap: () {
          if (!focusNode.hasFocus) {
            FocusScope.of(context).requestFocus(focusNode);
            return;
          }
          focusNode.unfocus();
          Future<void>.delayed(const Duration(milliseconds: 50), () {
            if (context.mounted) {
              FocusScope.of(context).requestFocus(focusNode);
            }
          });
        },
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        textAlign: TextAlign.start,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: '输入笔记标题',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainer,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
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
            color: Theme.of(context).colorScheme.onSurface,
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
        color: Theme.of(context).colorScheme.onSurface,
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
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: _PaperSurface(template: template),
            ),
            const SizedBox(height: 10),
            Text(
              template.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 20,
              child: selected
                  ? Icon(
                      LucideIcons.circleCheck,
                      color: Theme.of(context).colorScheme.primary,
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
  _TemplatePreviewPainter(this.template);

  final PageTemplate template;
  final RoughCanvasAdapter _adapter = RoughCanvasAdapter();

  @override
  void paint(Canvas canvas, Size size) {
    final pageTemplate = _canvasPageTemplateFor(template);
    final pageSize = CanvasLayout.pageSizeForTemplate(pageTemplate);
    final layout = CanvasLayout(
      type: CanvasLayoutType.paged,
      template: pageTemplate,
      pageFlow: CanvasPageFlow.topToBottom,
    ).ensurePage();
    final scale = math.min(
      size.width / pageSize.width,
      size.height / pageSize.height,
    );
    final renderedSize = Size(pageSize.width * scale, pageSize.height * scale);

    canvas.save();
    canvas.translate(
      (size.width - renderedSize.width) / 2,
      (size.height - renderedSize.height) / 2,
    );
    StaticCanvasPainter(
      scene: Scene(),
      adapter: _adapter,
      viewport: ViewportState(zoom: scale),
      layout: layout,
      renderPageShadows: false,
    ).paint(canvas, renderedSize);
    canvas.restore();
  }

  CanvasPageTemplate _canvasPageTemplateFor(PageTemplate template) {
    return switch (template) {
      PageTemplate.blank => CanvasPageTemplate.blank,
      PageTemplate.narrowLine => CanvasPageTemplate.narrowLine,
      PageTemplate.wideLine => CanvasPageTemplate.wideLine,
      PageTemplate.grid => CanvasPageTemplate.grid,
      PageTemplate.dotGrid => CanvasPageTemplate.dotGrid,
      PageTemplate.tianGrid => CanvasPageTemplate.tianGrid,
      PageTemplate.miGrid => CanvasPageTemplate.miGrid,
      PageTemplate.narrowVerticalLine => CanvasPageTemplate.narrowVerticalLine,
      PageTemplate.wideVerticalLine => CanvasPageTemplate.wideVerticalLine,
      PageTemplate.fourLineGrid => CanvasPageTemplate.fourLineGrid,
      PageTemplate.ancientBook => CanvasPageTemplate.ancientBook,
    };
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) {
    return oldDelegate.template != template;
  }
}
