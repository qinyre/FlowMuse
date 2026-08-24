import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../shared/widgets/app_spacing.dart';
import '../../ink_recognition/native_http_client.dart';
import '../models/ai_agent_models.dart';
import '../models/ai_visual_attachment.dart';
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
  bool hasSelection,
});

typedef AiAgentContextProvider = Future<AiAgentContextSnapshot> Function();

/// 捕获场景：决定回调返回 null / 抛错时的分流（hybrid 方案 §1.2 三场景表）。
enum _AiCaptureScene {
  /// 开面板被动捕获：null 静默；失败走附件条内联提示。
  passive,

  /// 快捷指令刷新：null 或失败都移除活动选区槽（过期意图产物）。
  refresh,

  /// 手动 chip 添加：null 走内联引导提示；失败走全局错误。
  manual,
}

/// 生成期间的客户端可知阶段；真实分阶段需 Repository 进度回调，先以近似状态呈现。
enum _AiGenerateStage { preparing, generating }

Future<void> showAiAgentDialog({
  required BuildContext context,
  required AiAgentRepository repository,
  required String noteTitle,
  required List<AiNoteText> texts,
  bool contextTruncated = false,
  String contextLabel = '整篇笔记',
  bool hasSelection = false,
  Future<AiVisualAttachment?> Function()? onCaptureSelection,
  Future<AiVisualAttachment?> Function()? onCaptureCurrentPdfPage,
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
          hasSelection: hasSelection,
          onCaptureSelection: onCaptureSelection,
          onCaptureCurrentPdfPage: onCaptureCurrentPdfPage,
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
    this.hasSelection = false,
    this.onCaptureSelection,
    this.onCaptureCurrentPdfPage,
    this.onRegionCapture,
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
  final bool hasSelection;

  /// 捕获回调（hybrid §1.2 契约）：返回 null=当前选区无可捕获的视觉内容，
  /// 抛 StateError=真失败（消息即用户文案）。捕获时机由面板按场景驱动
  /// （开面板被动捕获 / 快捷指令刷新 / 手动 chip 添加）。
  final Future<AiVisualAttachment?> Function()? onCaptureSelection;
  final Future<AiVisualAttachment?> Function()? onCaptureCurrentPdfPage;

  /// 框选截图回调：面板仅作入口，await 页面级框选流程（T4）提交的附件；
  /// 返回 null=用户取消（静默）。为 null 时 chip 回退元素捕获路径，
  /// showAiAgentDialog 不传即零回归。
  final Future<AiVisualAttachment?> Function()? onRegionCapture;

  final AiAgentContextProvider? contextProvider;
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
  _AiGenerateStage _stage = _AiGenerateStage.generating;

  // 附件条状态（单一事实源，hybrid §1.1）：仅存于面板内存态。
  List<AiVisualAttachment> _attachments = const [];

  /// 活动选区槽：系统自动产生的那张选区附件的引用（开面板被动捕获或
  /// 快捷指令刷新产物）。手动添加的附件永不登记；用户移除该附件或清除
  /// 对话时同步清空。引用判同一（附件不可变对象）。
  AiVisualAttachment? _activeSelectionSlot;
  bool _capturing = false;
  Future<void>? _pendingCapture;

  /// 非失败的引导性提示（被动捕获失败 / 手动 chip null），内联呈现，
  /// 区别于 [_error] 错误容器。
  String? _attachmentNotice;

  bool get _hasAttachmentSources =>
      widget.onCaptureSelection != null ||
      widget.onCaptureCurrentPdfPage != null ||
      widget.onRegionCapture != null;

  @override
  void initState() {
    super.initState();
    _context = (
      noteTitle: widget.noteTitle,
      texts: widget.texts,
      truncated: widget.contextTruncated,
      label: widget.contextLabel,
      hasSelection: widget.hasSelection,
    );
    if (widget.onCaptureSelection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _captureAndApply(
              capture: widget.onCaptureSelection!,
              scene: _AiCaptureScene.passive,
            ),
          );
        }
      });
    }
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

  /// 统一捕获入口：串行化在途捕获并按场景分流结果。
  /// 门控静默返回（按钮侧已禁用，此处兜底）。
  Future<void> _captureAndApply({
    required Future<AiVisualAttachment?> Function() capture,
    required _AiCaptureScene scene,
  }) async {
    if (_loading || _applying || _capturing) return;
    if (scene == _AiCaptureScene.manual &&
        _attachments.length >= maxAiVisualAttachments) {
      // 引导性提示走内联样式而非错误容器（hybrid §1.2）；chips 满额即禁用，
      // 此守卫仅为纵深防御。
      setState(() => _attachmentNotice = '最多添加 $maxAiVisualAttachments 张图片');
      return;
    }
    final task = _runCaptureTask(capture, scene);
    _pendingCapture = task;
    try {
      await task;
    } finally {
      _pendingCapture = null;
    }
  }

  /// 快捷指令刷新入口：捕获当前选区并替换活动槽（hybrid §1.2.2）。
  Future<void> _refreshSelectionAttachment() async {
    final capture = widget.onCaptureSelection;
    if (capture == null) return;
    await _captureAndApply(capture: capture, scene: _AiCaptureScene.refresh);
  }

  /// 框选截图添加入口：await 页面级框选流程提交的附件并入附件条；
  /// 返回 null（用户取消框选）静默——无提示、不报错。
  Future<void> _addRegionAttachment() async {
    if (_loading || _applying || _capturing) return;
    if (_attachments.length >= maxAiVisualAttachments) {
      setState(() => _attachmentNotice = '最多添加 $maxAiVisualAttachments 张图片');
      return;
    }
    setState(() {
      _capturing = true;
      _attachmentNotice = null;
    });
    try {
      final attachment = await widget.onRegionCapture!();
      if (attachment != null && mounted) {
        setState(() => _attachments = [..._attachments, attachment]);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _runCaptureTask(
    Future<AiVisualAttachment?> Function() capture,
    _AiCaptureScene scene,
  ) async {
    setState(() {
      _capturing = true;
      _attachmentNotice = null;
    });
    try {
      final attachment = await capture();
      if (!mounted) return;
      switch (scene) {
        case _AiCaptureScene.passive:
          if (attachment == null) {
            // 无视觉选区：静默不动作（§1.2 表）；finally 的 _capturing
            // 复位已触发重建，无需空 setState。
            return;
          }
          setState(() {
            _attachments = [..._attachments, attachment];
            _activeSelectionSlot = attachment;
          });
        case _AiCaptureScene.refresh:
          if (attachment == null) {
            setState(_removeActiveSelectionSlot);
            return;
          }
          _replaceActiveSelectionSlot(attachment);
        case _AiCaptureScene.manual:
          if (attachment == null) {
            setState(() => _attachmentNotice = '当前选区没有可截图的视觉内容');
            return;
          }
          setState(() => _attachments = [..._attachments, attachment]);
      }
    } catch (error) {
      if (!mounted) return;
      final message = _errorMessage(error);
      switch (scene) {
        case _AiCaptureScene.passive:
          // 未做任何操作前不弹全局横幅（§1.6 分级），附件条内联提示，
          // 不置任何粘性状态——可经快捷指令重试。
          setState(() => _attachmentNotice = message);
        case _AiCaptureScene.refresh:
          // 过期意图产物随失败一并移除，"以文字上下文为主"口径才成立
          // （第四轮 R1/R3 共同裁决）；错误追加后果说明（§1.6）。
          setState(() {
            _removeActiveSelectionSlot();
            _error =
                '$message（本次发送将以文字上下文为主，'
                '可能无法针对选区内容回答；可重试或修改指令）';
          });
        case _AiCaptureScene.manual:
          setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// 替换活动槽为计数中性操作（移除旧槽+加入新槽），不受满额限制；
  /// 槽空且已满则提示不驱逐。手动添加的附件一律不动。
  void _replaceActiveSelectionSlot(AiVisualAttachment attachment) {
    final slot = _activeSelectionSlot;
    final index = slot == null ? -1 : _attachments.indexOf(slot);
    if (index >= 0) {
      setState(() {
        _attachments = [..._attachments]..[index] = attachment;
        _activeSelectionSlot = attachment;
      });
      return;
    }
    // 槽空（或不变量被破坏的脏引用——此处一并清弃）。
    if (_attachments.length >= maxAiVisualAttachments) {
      setState(() => _attachmentNotice = '附件已满，移除一张以附带当前选区');
      return;
    }
    setState(() {
      _attachments = [..._attachments, attachment];
      _activeSelectionSlot = attachment;
    });
  }

  /// 按引用同一移除活动槽附件；无槽时为幂等空操作。
  /// 仅做字段变更，不调用 setState——由调用方包裹。
  void _removeActiveSelectionSlot() {
    final slot = _activeSelectionSlot;
    if (slot == null) return;
    _activeSelectionSlot = null;
    final index = _attachments.indexOf(slot);
    if (index < 0) return;
    _attachments = [..._attachments]..removeAt(index);
  }

  Future<void> _generate() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty ||
        _loading ||
        _speechState != SpeechRecognitionState.idle) {
      return;
    }
    final isFollowUp = _response != null;
    final generation = ++_generation;
    final cancelToken = NativeHttpCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _stage = _AiGenerateStage.preparing;
      _loading = true;
      _error = null;
      if (!isFollowUp) _selectedActions = const {};
    });
    // 在途捕获先于组请求完成（§1.2.5）：异常一律吸收——错误已由捕获
    // 路径按场景展示，发送以当前 _attachments 继续。
    final pending = _pendingCapture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final context = widget.contextProvider != null
        ? await widget.contextProvider!()
        : _context;
    if (!mounted || generation != _generation || cancelToken.isCancelled) {
      return;
    }
    setState(() {
      _context = context;
      _stage = _AiGenerateStage.generating;
    });
    try {
      final response = await widget.repository.run(
        instruction: instruction,
        noteTitle: context.noteTitle,
        texts: context.texts,
        conversation: _conversation,
        attachments: _attachments,
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
      _attachments = const [];
      _activeSelectionSlot = null;
      _attachmentNotice = null;
    });
  }

  void _removeAttachment(int index) {
    if (_loading || _applying || _capturing) return;
    setState(() {
      if (identical(_attachments[index], _activeSelectionSlot)) {
        _activeSelectionSlot = null;
      }
      _attachments = [..._attachments]..removeAt(index);
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
    TimeoutException() => 'AI 服务响应超时，请检查网络后重试',
    _ => 'AI 操作失败，请稍后重试',
  };

  BoxDecoration _attachmentTileDecoration(ColorScheme colors) => BoxDecoration(
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(AppSpacing.radius),
  );

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
                    onPressed: _loading || _applying || _capturing
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
                      for (final shortcut
                          in (_context.hasSelection
                                  ? const {
                                      '解释这里': '解释这里的内容',
                                      '检查公式': '检查这里的公式是否正确，如有错误请指出',
                                      '整理文字': '整理这里的文字内容',
                                      '整理成导图': '把这里的内容整理成思维导图',
                                    }
                                  : const {
                                      '总结': '总结当前笔记',
                                      '待办': '提取待办事项',
                                      '大纲': '生成结构化大纲',
                                      '思维导图': '根据当前内容生成思维导图',
                                      '手写排版': '智能排版当前手写内容',
                                    })
                              .entries)
                        ActionChip(
                          label: Text(shortcut.key),
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading || _applying || _capturing
                              ? null
                              : () {
                                  // 选区快捷指令即视觉意图表达：填入文案的
                                  // 同时刷新活动选区槽（hybrid §1.2.2）。
                                  _fillInstruction(shortcut.value);
                                  if (_context.hasSelection) {
                                    unawaited(_refreshSelectionAttachment());
                                  }
                                },
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
                  if (_hasAttachmentSources) ...[
                    const SizedBox(height: AppSpacing.controlGap),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.onCaptureSelection != null ||
                            widget.onRegionCapture != null)
                          ActionChip(
                            avatar: const Icon(Icons.crop_free, size: 18),
                            label: const Text('选区截图'),
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                _loading ||
                                    _applying ||
                                    _capturing ||
                                    _attachments.length >=
                                        maxAiVisualAttachments
                                ? null
                                : () => unawaited(
                                    widget.onRegionCapture != null
                                        ? _addRegionAttachment()
                                        : _captureAndApply(
                                            capture:
                                                widget.onCaptureSelection!,
                                            scene: _AiCaptureScene.manual,
                                          ),
                                  ),
                          ),
                        if (widget.onCaptureCurrentPdfPage != null)
                          ActionChip(
                            avatar: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('PDF 页'),
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                _loading ||
                                    _applying ||
                                    _capturing ||
                                    _attachments.length >=
                                        maxAiVisualAttachments
                                ? null
                                : () => unawaited(
                                    _captureAndApply(
                                      capture: widget.onCaptureCurrentPdfPage!,
                                      scene: _AiCaptureScene.manual,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    if (_attachments.isNotEmpty || _capturing) ...[
                      const SizedBox(height: AppSpacing.controlGap),
                      SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachments.length + (_capturing ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            if (index >= _attachments.length) {
                              // 捕获在途占位项：知情窗口内发送前可见。
                              return Container(
                                padding: const EdgeInsets.all(4),
                                decoration: _attachmentTileDecoration(colors),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '截取中…',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              );
                            }
                            final attachment = _attachments[index];
                            return Container(
                              padding: const EdgeInsets.all(4),
                              decoration: _attachmentTileDecoration(colors),
                              child: Row(
                                children: [
                                  Image.memory(
                                    attachment.bytes,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    cacheWidth: 88, // 2x DPR 缩略解码，避免全分辨率位图常驻
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        attachment.sourceLabel,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      Text(
                                        attachment.sizeLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: '移除图片',
                                    key: const ValueKey('ai-attachment-remove'),
                                    onPressed:
                                        _loading || _applying || _capturing
                                        ? null
                                        : () => _removeAttachment(index),
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_attachmentNotice != null) ...[
                      const SizedBox(height: AppSpacing.controlGap),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.controlGap),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radius,
                          ),
                        ),
                        child: Text(
                          _attachmentNotice!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.controlGap),
                    Text(
                      _attachments.isEmpty
                          ? '本次提问仅发送文字上下文'
                          : '选区截图包含选区矩形内的全部可见内容（可能含未选中的相邻内容）；'
                                '框选截图包含框内全部可见内容；'
                                'PDF 页附件为导入时的整页原始位图（不含白板批注）。'
                                '仅发送附件条中显示的 ${_attachments.length} 张图片'
                                '（其中选区截图会随打开面板或点击视觉指令自动加入或更新），'
                                '不会自动上传附件之外的画布图像内容'
                                '（文字上下文仍按既有规则随请求发送）；'
                                '追问时附件将随每次请求重新发送，直到移除或清除对话。'
                                '发送前请确认。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                      _stage == _AiGenerateStage.preparing
                          ? '正在准备上下文…'
                          : response != null
                          ? '正在根据追问修改…'
                          : _attachments.isNotEmpty
                          ? '正在结合选区图像与笔记内容生成…'
                          : _context.texts.isEmpty
                          ? '正在生成回复…'
                          : '正在阅读笔记并生成操作…',
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
