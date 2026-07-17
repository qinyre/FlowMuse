import 'package:flutter/material.dart';

import '../../ink_recognition/native_http_client.dart';
import '../models/ai_agent_models.dart';
import '../repositories/ai_agent_repository.dart';
import '../repositories/ai_prompt_store.dart';

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
    builder: (_) => _AiAgentDialog(
      repository: repository,
      noteTitle: noteTitle,
      texts: texts,
      contextTruncated: contextTruncated,
      contextLabel: contextLabel,
      promptStore: promptStore ?? defaultAiPromptStore,
      onApply: onApply,
    ),
  );
}

class _AiAgentDialog extends StatefulWidget {
  const _AiAgentDialog({
    required this.repository,
    required this.noteTitle,
    required this.texts,
    required this.contextTruncated,
    required this.contextLabel,
    required this.promptStore,
    required this.onApply,
  });

  final AiAgentRepository repository;
  final String noteTitle;
  final List<AiNoteText> texts;
  final bool contextTruncated;
  final String contextLabel;
  final AiPromptStore promptStore;
  final Future<void> Function(AiAgentResponse response) onApply;

  @override
  State<_AiAgentDialog> createState() => _AiAgentDialogState();
}

class _AiAgentDialogState extends State<_AiAgentDialog> {
  final _instructionController = TextEditingController(
    text: '总结当前笔记，提取待办事项，并生成合适的标题',
  );
  final _actionControllers = <TextEditingController>[];
  AiAgentResponse? _response;
  Set<int> _selectedActions = const {};
  List<String> _customPrompts = const [];
  NativeHttpCancelToken? _cancelToken;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
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
    if (instruction.isEmpty || _loading) return;
    final previousResponse = _response;
    final generation = ++_generation;
    final cancelToken = NativeHttpCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _loading = true;
      _error = null;
      if (previousResponse == null) _selectedActions = const {};
    });
    try {
      final response = await widget.repository.run(
        instruction: instruction,
        noteTitle: widget.noteTitle,
        texts: widget.texts,
        previousResponse: previousResponse,
        cancelToken: cancelToken,
      );
      if (!mounted || generation != _generation || cancelToken.isCancelled) {
        return;
      }
      _setResponse(response);
      if (previousResponse != null) _instructionController.clear();
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

  void _setResponse(AiAgentResponse response) {
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
      _response = response;
      _selectedActions = {
        for (var index = 0; index < response.actions.length; index++) index,
      };
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
      if (mounted) Navigator.of(context).pop();
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
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome),
          SizedBox(width: 8),
          Text('AI 笔记助手'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('分析范围：${widget.contextLabel}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final prompt in const ['总结当前笔记', '提取待办事项', '生成结构化大纲'])
                    ActionChip(
                      label: Text(prompt),
                      onPressed: _loading || _applying
                          ? null
                          : () => _fillInstruction(prompt),
                    ),
                  for (final prompt in _customPrompts)
                    InputChip(
                      label: Text(prompt),
                      onPressed: _loading || _applying
                          ? null
                          : () => _fillInstruction(prompt),
                      onDeleted: _loading || _applying
                          ? null
                          : () => _removePrompt(prompt),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructionController,
                enabled: !_loading && !_applying,
                onChanged: (_) => setState(() {}),
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: response == null ? '希望 AI 完成什么？' : '继续修改，例如：再精简一点',
                  border: const OutlineInputBorder(),
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
              if (widget.contextTruncated)
                Text(
                  '当前笔记较长，已使用前 $maxAiAgentContextLength 字作为上下文。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(response == null ? '正在阅读笔记并生成操作…' : '正在根据追问修改…'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (response != null) ...[
                const SizedBox(height: 12),
                Text(response.message),
                const SizedBox(height: 12),
                const Text(
                  '确认后将执行：',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (var index = 0; index < response.actions.length; index++)
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
                        secondary: Icon(
                          response.actions[index].tool == AiAgentTool.renameNote
                              ? Icons.drive_file_rename_outline
                              : Icons.note_add_outlined,
                        ),
                        title: Text(response.actions[index].label),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 40, bottom: 8),
                        child: TextField(
                          controller: _actionControllers[index],
                          enabled: !_applying && !_loading,
                          onChanged: (_) => setState(() {}),
                          minLines: 1,
                          maxLines:
                              response.actions[index].tool ==
                                  AiAgentTool.renameNote
                              ? 2
                              : 8,
                          maxLength:
                              response.actions[index].tool ==
                                  AiAgentTool.renameNote
                              ? maxAiAgentTitleLength
                              : maxAiAgentTextLength,
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
      actions: [
        TextButton(
          onPressed: _applying
              ? null
              : () {
                  _cancelToken?.cancel();
                  Navigator.of(context).pop();
                },
          child: const Text('关闭'),
        ),
        if (_loading)
          FilledButton.tonal(
            onPressed: _cancelGeneration,
            child: const Text('取消生成'),
          )
        else if (response == null)
          FilledButton(
            onPressed: instruction.isEmpty ? null : _generate,
            child: const Text('生成操作'),
          )
        else ...[
          TextButton(
            onPressed: instruction.isEmpty ? null : _generate,
            child: const Text('追问修改'),
          ),
          FilledButton(
            onPressed: _canApply ? _apply : null,
            child: Text(_applying ? '正在应用…' : '确认应用'),
          ),
        ],
      ],
    );
  }
}
