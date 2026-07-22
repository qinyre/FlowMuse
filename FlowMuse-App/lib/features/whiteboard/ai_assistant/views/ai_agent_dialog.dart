import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../shared/widgets/app_spacing.dart';
import '../../ink_recognition/native_http_client.dart';
import '../models/ai_agent_models.dart';
import '../repositories/ai_agent_repository.dart';
import '../repositories/ai_prompt_store.dart';
import '../../speech_recognition/models/speech_recognition_event.dart';
import '../../speech_recognition/services/speech_recognition_service.dart';
import '../../speech_recognition/services/speech_recognition_service_factory.dart';

typedef AiAgentContextSnapshot = ({
  String noteTitle,
  List<AiNoteText> texts,
  bool truncated,
  String label,
});

Future<void> showAiAgentDialog({
  required BuildContext context,
  required AiAgentRepository repository,
  required String noteTitle,
  required List<AiNoteText> texts,
  bool contextTruncated = false,
  String contextLabel = '整篇笔记',
  AiPromptStore? promptStore,
  required Future<void> Function(AiAgentResponse response) onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(dialogContext).height * 0.82,
        child: AiAgentPanel(
          repository: repository,
          noteTitle: noteTitle,
          texts: texts,
          contextTruncated: contextTruncated,
          contextLabel: contextLabel,
          promptStore: promptStore ?? defaultAiPromptStore,
          onApply: onApply,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

class AiAgentPanel extends StatefulWidget {
  const AiAgentPanel({
    super.key,
    required this.repository,
    required this.noteTitle,
    required this.texts,
    required this.contextTruncated,
    required this.contextLabel,
    this.contextProvider,
    required this.promptStore,
    this.speechRecognitionService,
    required this.onApply,
    required this.onClose,
  });

  final AiAgentRepository repository;
  final String noteTitle;
  final List<AiNoteText> texts;
  final bool contextTruncated;
  final String contextLabel;
  final AiAgentContextSnapshot Function()? contextProvider;
  final AiPromptStore promptStore;
  final SpeechRecognitionService? speechRecognitionService;
  final Future<void> Function(AiAgentResponse response) onApply;
  final VoidCallback onClose;

  @override
  State<AiAgentPanel> createState() => _AiAgentPanelState();
}

class _AiAgentPanelState extends State<AiAgentPanel> {
  final _instructionController = TextEditingController();
  final _actionControllers = <TextEditingController>[];
  AiAgentResponse? _response;
  Set<int> _selectedActions = const {};
  List<String> _customPrompts = const [];
  NativeHttpCancelToken? _cancelToken;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _applying = false;
  late final SpeechRecognitionService _speechService;
  late final bool _ownsSpeechService;
  StreamSubscription<SpeechRecognitionEvent>? _speechSubscription;
  SpeechRecognitionState _speechState = SpeechRecognitionState.idle;
  bool _speechAvailable = false;
  String _speechPreview = '';
  bool _speechFinalCommitted = false;
  List<AiAgentConversationTurn> _conversation = const [];
  late AiAgentContextSnapshot _context;

  @override
  void initState() {
    super.initState();
    _context = (
      noteTitle: widget.noteTitle,
      texts: widget.texts,
      truncated: widget.contextTruncated,
      label: widget.contextLabel,
    );
    _ownsSpeechService = widget.speechRecognitionService == null;
    _speechService =
        widget.speechRecognitionService ?? createSpeechRecognitionService();
    _speechSubscription = _speechService.events.listen(_onSpeechEvent);
    unawaited(_checkSpeechAvailability());
    if (widget.texts.isNotEmpty) {
      _instructionController.text = '总结当前笔记，提取待办事项，并生成合适的标题';
    }
    _loadPrompts();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    unawaited(_speechService.cancel());
    unawaited(_speechSubscription?.cancel());
    if (_ownsSpeechService) unawaited(_speechService.dispose());
    _instructionController.dispose();
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrompts() async {
    try {
      final prompts = await widget.promptStore.load();
      if (mounted) setState(() => _customPrompts = prompts);
    } catch (_) {
      // 常用指令是非关键功能，存储不可用时保留内置指令。
    }
  }

  Future<void> _checkSpeechAvailability() async {
    final available = await _speechService.isAvailable();
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleSpeech() async {
    if (_speechState == SpeechRecognitionState.idle) {
      _speechFinalCommitted = false;
      await _speechService.start();
    } else {
      await _speechService.stop();
    }
  }

  void _onSpeechEvent(SpeechRecognitionEvent event) {
    if (!mounted) return;
    switch (event) {
      case SpeechRecognitionResult(:final text, :final isFinal):
        if (isFinal) {
          if (_speechFinalCommitted) return;
          _speechFinalCommitted = true;
          final current = _instructionController.text.trimRight();
          _instructionController.text = current.isEmpty
              ? text
              : '$current$text';
          _instructionController.selection = TextSelection.collapsed(
            offset: _instructionController.text.length,
          );
          setState(() {
            _speechPreview = '';
            _speechState = SpeechRecognitionState.idle;
          });
        } else {
          setState(() => _speechPreview = text);
        }
      case SpeechRecognitionStateChanged(:final state):
        setState(() {
          _speechState = state;
          if (state == SpeechRecognitionState.starting) {
            _speechFinalCommitted = false;
          }
          if (state == SpeechRecognitionState.idle) _speechPreview = '';
        });
      case SpeechRecognitionFailed(:final message):
        setState(() {
          _speechState = SpeechRecognitionState.idle;
          _speechPreview = '';
          _error = message.trim().isEmpty ? '语音识别失败' : message;
        });
    }
  }

  Future<void> _savePrompt() async {
    try {
      final prompts = await widget.promptStore.save(
        _instructionController.text,
      );
      if (mounted) setState(() => _customPrompts = prompts);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    }
  }

  Future<void> _removePrompt(String prompt) async {
    try {
      final prompts = await widget.promptStore.remove(prompt);
      if (mounted) setState(() => _customPrompts = prompts);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    }
  }

  void _fillInstruction(String prompt) {
    _instructionController.text = prompt;
    _instructionController.selection = TextSelection.collapsed(
      offset: prompt.length,
    );
    setState(() {});
  }

  Future<void> _generate() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty ||
        _loading ||
        _speechState != SpeechRecognitionState.idle) {
      return;
    }
    final context = widget.contextProvider?.call() ?? _context;
    final isFollowUp = _response != null;
    final generation = ++_generation;
    final cancelToken = NativeHttpCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _context = context;
      _loading = true;
      _error = null;
      if (!isFollowUp) _selectedActions = const {};
    });
    try {
      final response = await widget.repository.run(
        instruction: instruction,
        noteTitle: context.noteTitle,
        texts: context.texts,
        conversation: _conversation,
        cancelToken: cancelToken,
      );
      if (!mounted || generation != _generation || cancelToken.isCancelled) {
        return;
      }
      _setResponse(response, instruction: instruction);
      if (isFollowUp) _instructionController.clear();
    } on NativeHttpCancelledException {
      // 用户主动取消，不显示为失败。
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _setResponse(AiAgentResponse response, {required String instruction}) {
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    _actionControllers
      ..clear()
      ..addAll(
        response.actions.map(
          (action) => TextEditingController(text: action.value),
        ),
      );
    setState(() {
      _conversation = compactAiAgentConversation([
        ..._conversation,
        AiAgentConversationTurn(instruction: instruction, response: response),
      ]);
      _response = response;
      _selectedActions = {
        for (var index = 0; index < response.actions.length; index++) index,
      };
    });
  }

  void _clearConversation() {
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    _actionControllers.clear();
    _instructionController.clear();
    setState(() {
      _conversation = const [];
      _response = null;
      _selectedActions = const {};
      _error = null;
    });
  }

  void _cancelGeneration() {
    _cancelToken?.cancel();
    _generation++;
    setState(() {
      _loading = false;
      _error = '已取消生成';
    });
  }

  AiAgentAction _editedAction(int index) {
    if (_response!.actions[index].tool == AiAgentTool.smartLayout) {
      return _response!.actions[index];
    }
    return AiAgentAction.edited(
      tool: _response!.actions[index].tool,
      value: _actionControllers[index].text,
    );
  }

  bool get _canApply {
    if (_applying || _selectedActions.isEmpty) return false;
    try {
      for (final index in _selectedActions) {
        _editedAction(index);
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<void> _apply() async {
    final response = _response;
    if (response == null || !_canApply) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.onApply(
        AiAgentResponse(
          message: response.message,
          actions: [
            for (var index = 0; index < response.actions.length; index++)
              if (_selectedActions.contains(index)) _editedAction(index),
          ],
        ),
      );
      if (mounted) {
        setState(() {
          _applying = false;
          _selectedActions = const {};
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = _errorMessage(error);
        });
      }
    }
  }

  String _errorMessage(Object error) => switch (error) {
    StateError(:final message) => message.toString(),
    FormatException(:final message) => message,
    _ => 'AI 操作失败，请稍后重试',
  };

  @override
  Widget build(BuildContext context) {
    final response = _response;
    final instruction = _instructionController.text.trim();
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sidebarInset,
              AppSpacing.listGap,
              AppSpacing.controlGap,
              AppSpacing.listGap,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 19,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.listGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 笔记助手',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _context.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_conversation.isNotEmpty)
                  IconButton(
                    tooltip: '清除对话',
                    onPressed: _loading || _applying
                        ? null
                        : _clearConversation,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                IconButton(
                  tooltip: '关闭 AI 助手',
                  onPressed: _applying
                      ? null
                      : () {
                          _cancelToken?.cancel();
                          widget.onClose();
                        },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.sidebarInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '快捷指令',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.controlGap),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final shortcut in const {
                        '总结': '总结当前笔记',
                        '待办': '提取待办事项',
                        '大纲': '生成结构化大纲',
                        '思维导图': '根据当前内容生成思维导图',
                        '手写排版': '智能排版当前手写内容',
                      }.entries)
                        ActionChip(
                          label: Text(shortcut.key),
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading || _applying
                              ? null
                              : () => _fillInstruction(shortcut.value),
                        ),
                      for (final prompt in _customPrompts)
                        InputChip(
                          label: Text(prompt),
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading || _applying
                              ? null
                              : () => _fillInstruction(prompt),
                          onDeleted: _loading || _applying
                              ? null
                              : () => _removePrompt(prompt),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.listGap),
                  TextField(
                    controller: _instructionController,
                    enabled: !_loading && !_applying,
                    onChanged: (_) => setState(() {}),
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: response == null
                          ? '希望 AI 完成什么？'
                          : '继续修改，例如：再精简一点',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: colors.surfaceContainerLowest,
                      helperText: _speechState == SpeechRecognitionState.idle
                          ? null
                          : (_speechPreview.isEmpty ? '正在聆听…' : _speechPreview),
                      suffixIcon: _speechAvailable
                          ? IconButton(
                              tooltip:
                                  _speechState == SpeechRecognitionState.idle
                                  ? '语音输入'
                                  : '结束语音输入',
                              onPressed: _loading || _applying
                                  ? null
                                  : _toggleSpeech,
                              icon: Icon(
                                _speechState == SpeechRecognitionState.idle
                                    ? Icons.mic_none
                                    : Icons.stop_circle_outlined,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _loading || _applying || instruction.isEmpty
                          ? null
                          : _savePrompt,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('保存为常用指令'),
                    ),
                  ),
                  Text(
                    '发送时读取画布当前选中的文本框；未选择时使用整篇笔记。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (_context.truncated)
                    Text(
                      '当前笔记较长，已使用前 $maxAiAgentContextLength 字作为上下文。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_loading) ...[
                    const SizedBox(height: AppSpacing.controlGap),
                    Text(
                      response == null
                          ? _context.texts.isEmpty
                                ? '正在生成回复…'
                                : '正在阅读笔记并生成操作…'
                          : '正在根据追问修改…',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.controlGap),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.listGap),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                  if (response != null) ...[
                    const SizedBox(height: AppSpacing.listGap),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.listGap),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                      child: MarkdownBody(
                        data: response.message,
                        selectable: true,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(
                              Theme.of(context),
                            ).copyWith(
                              p: TextStyle(color: colors.onSecondaryContainer),
                            ),
                      ),
                    ),
                    if (response.actions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.listGap),
                      const Text(
                        '确认后将执行：',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    for (
                      var index = 0;
                      index < response.actions.length;
                      index++
                    )
                      Column(
                        children: [
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _selectedActions.contains(index),
                            onChanged: _applying || _loading
                                ? null
                                : (selected) {
                                    setState(() {
                                      _selectedActions = {..._selectedActions};
                                      if (selected ?? false) {
                                        _selectedActions.add(index);
                                      } else {
                                        _selectedActions.remove(index);
                                      }
                                    });
                                  },
                            secondary: Icon(switch (response
                                .actions[index]
                                .tool) {
                              AiAgentTool.renameNote =>
                                Icons.drive_file_rename_outline,
                              AiAgentTool.insertText => Icons.note_add_outlined,
                              AiAgentTool.generateMindmap => Icons.account_tree,
                              AiAgentTool.smartLayout => Icons.auto_fix_high,
                            }),
                            title: Text(response.actions[index].label),
                          ),
                          if (response.actions[index].tool !=
                              AiAgentTool.smartLayout)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 40,
                                bottom: AppSpacing.controlGap,
                              ),
                              child: TextField(
                                controller: _actionControllers[index],
                                enabled: !_applying && !_loading,
                                onChanged: (_) => setState(() {}),
                                minLines: 1,
                                maxLines:
                                    switch (response.actions[index].tool) {
                                      AiAgentTool.renameNote => 2,
                                      AiAgentTool.insertText => 8,
                                      AiAgentTool.generateMindmap => 12,
                                      AiAgentTool.smartLayout => 1,
                                    },
                                maxLength:
                                    switch (response.actions[index].tool) {
                                      AiAgentTool.renameNote =>
                                        maxAiAgentTitleLength,
                                      AiAgentTool.insertText =>
                                        maxAiAgentTextLength,
                                      AiAgentTool.generateMindmap =>
                                        maxAiMindmapJsonLength,
                                      AiAgentTool.smartLayout => 0,
                                    },
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.listGap),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.controlGap,
              runSpacing: AppSpacing.controlGap,
              children: [
                if (_loading)
                  FilledButton.tonal(
                    onPressed: _cancelGeneration,
                    child: const Text('取消生成'),
                  )
                else if (response == null)
                  FilledButton.icon(
                    onPressed:
                        instruction.isEmpty ||
                            _speechState != SpeechRecognitionState.idle
                        ? null
                        : _generate,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('发送'),
                  )
                else ...[
                  TextButton(
                    onPressed:
                        instruction.isEmpty ||
                            _speechState != SpeechRecognitionState.idle
                        ? null
                        : _generate,
                    child: const Text('追问修改'),
                  ),
                  if (response.actions.isNotEmpty)
                    FilledButton(
                      onPressed: _canApply ? _apply : null,
                      child: Text(_applying ? '正在应用…' : '确认应用'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
