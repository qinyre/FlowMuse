import 'package:flutter/material.dart';

import '../models/ai_agent_models.dart';
import '../repositories/ai_agent_repository.dart';

Future<void> showAiAgentDialog({
  required BuildContext context,
  required AiAgentRepository repository,
  required String noteTitle,
  required List<AiNoteText> texts,
  bool contextTruncated = false,
  required Future<void> Function(AiAgentResponse response) onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AiAgentDialog(
      repository: repository,
      noteTitle: noteTitle,
      texts: texts,
      contextTruncated: contextTruncated,
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
    required this.onApply,
  });

  final AiAgentRepository repository;
  final String noteTitle;
  final List<AiNoteText> texts;
  final bool contextTruncated;
  final Future<void> Function(AiAgentResponse response) onApply;

  @override
  State<_AiAgentDialog> createState() => _AiAgentDialogState();
}

class _AiAgentDialogState extends State<_AiAgentDialog> {
  final _instructionController = TextEditingController(
    text: '总结当前笔记，提取待办事项，并生成合适的标题',
  );
  AiAgentResponse? _response;
  Set<int> _selectedActions = const {};
  String? _error;
  bool _loading = false;
  bool _applying = false;

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _response = null;
      _selectedActions = const {};
    });
    try {
      final response = await widget.repository.run(
        instruction: instruction,
        noteTitle: widget.noteTitle,
        texts: widget.texts,
      );
      if (mounted) {
        setState(() {
          _response = response;
          _selectedActions = {
            for (var index = 0; index < response.actions.length; index++) index,
          };
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final response = _response;
    if (response == null || _applying || _selectedActions.isEmpty) return;
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
              if (_selectedActions.contains(index)) response.actions[index],
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
              Wrap(
                spacing: 8,
                children: [
                  for (final prompt in const ['总结当前笔记', '提取待办事项', '生成结构化大纲'])
                    ActionChip(
                      label: Text(prompt),
                      onPressed: _loading || _applying
                          ? null
                          : () {
                              _instructionController.text = prompt;
                              _instructionController.selection =
                                  TextSelection.collapsed(
                                    offset: prompt.length,
                                  );
                            },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructionController,
                enabled: !_loading && !_applying,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '希望 AI 完成什么？',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.contextTruncated) ...[
                const SizedBox(height: 8),
                Text(
                  '当前笔记较长，已使用前 $maxAiAgentContextLength 字作为上下文。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Text('正在阅读笔记并生成操作…'),
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
                const SizedBox(height: 6),
                for (var index = 0; index < response.actions.length; index++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selectedActions.contains(index),
                    onChanged: _applying
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
                    subtitle: Text(
                      response.actions[index].value,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading || _applying
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (response == null)
          FilledButton(
            onPressed: _loading ? null : _generate,
            child: const Text('生成操作'),
          )
        else ...[
          TextButton(
            onPressed: _loading || _applying ? null : _generate,
            child: const Text('重新生成'),
          ),
          FilledButton(
            onPressed: _applying || _selectedActions.isEmpty ? null : _apply,
            child: Text(_applying ? '正在应用…' : '确认应用'),
          ),
        ],
      ],
    );
  }
}
