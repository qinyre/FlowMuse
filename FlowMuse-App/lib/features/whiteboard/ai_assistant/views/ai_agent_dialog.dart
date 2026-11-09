import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../shared/utils/ui_lifecycle.dart';
import '../../../../shared/url_launcher/app_url_launcher.dart';
import '../../../../shared/widgets/app_spacing.dart';
import '../../../../shared/widgets/keyboard_focus_recovery.dart';
import '../../ink_recognition/native_http_client.dart';
import '../../editor_core/src/core/layout/note_draft.dart';
import '../../editor_core/src/core/elements/latex_source.dart';
import '../../editor_core/src/rendering/canvas_markdown.dart';
import '../models/ai_agent_models.dart';
import '../models/ai_source_location.dart';
import '../models/ai_visual_attachment.dart';
import '../repositories/ai_agent_repository.dart';
import '../repositories/ai_prompt_store.dart';
import '../../speech_recognition/models/speech_recognition_event.dart';
import '../../speech_recognition/services/speech_recognition_service.dart';
import '../../speech_recognition/services/speech_recognition_service_factory.dart';
import 'reply_latex.dart';

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
    this.sourceProvider,
    this.initialSourceCapture,
    this.initialSourceLocation,
    this.automaticTextSource,
    this.onViewSource,
    this.initialInstruction,
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
  final AiAgentSource Function(AiAgentScope scope)? sourceProvider;
  final Future<AiVisualAttachment?> Function()? initialSourceCapture;
  final AiSourceLocation? initialSourceLocation;
  final ValueNotifier<AiAgentSource?>? automaticTextSource;
  final String? Function(AiSourceLocation location)? onViewSource;
  final String? initialInstruction;
  final AiPromptStore promptStore;
  final SpeechRecognitionService? speechRecognitionService;
  final Future<void> Function(AiAgentResponse response) onApply;
  final VoidCallback onClose;

  @override
  State<AiAgentPanel> createState() => _AiAgentPanelState();
}

typedef _AiPanelTurn = ({
  String instruction,
  AiAgentResponse response,
  List<String> sourceTextIds,
  List<({String label, AiSourceLocation? location})> images,
  ({String label, AiSourceLocation location})? source,
});

class _AiAgentPanelState extends State<AiAgentPanel> {
  final _instructionController = TextEditingController();
  final _searchController = TextEditingController();
  bool _searchEnabled = false;
  Timer? _streamRefresh;
  String _streamPreview = '';
  final _instructionFocusNode = FocusNode();
  final _messageScroll = ScrollController();
  final _latestMessageKey = GlobalKey();
  final _shortcutsKey = GlobalKey();
  final _actionControllers = <TextEditingController>[];
  final _actionFocusNodes = <FocusNode>[];
  final _messages = <_AiPanelTurn>[];
  AiAgentResponse? get _response => _messages.lastOrNull?.response;
  String? _pendingInstruction;
  bool? _showShortcuts;
  bool _applied = false;
  Set<int> _selectedActions = const {};
  List<String> _customPrompts = const [];
  NativeHttpCancelToken? _cancelToken;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _applying = false;
  bool _editingDraft = false;
  bool _actionSourceChanged = false;
  late final SpeechRecognitionService _speechService;
  late final bool _ownsSpeechService;
  StreamSubscription<SpeechRecognitionEvent>? _speechSubscription;
  SpeechRecognitionState _speechState = SpeechRecognitionState.idle;
  bool _speechAvailable = false;
  String _speechPreview = '';
  bool _speechFinalCommitted = false;
  bool _ownsSpeechSession = false;
  List<AiAgentConversationTurn> _conversation = const [];
  late AiAgentContextSnapshot _context;
  AiAgentSource? _pendingTextSource;
  AiSourceLocation? _sourceLocation;
  String? _citationNotice;
  _AiPanelTurn? _citationNoticeTurn;
  bool _needsSourceImage = false;
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
      widget.sourceProvider != null ||
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
    final initialCapture =
        widget.initialSourceCapture ?? widget.onCaptureSelection;
    _needsSourceImage = widget.initialSourceCapture != null;
    _sourceLocation = widget.initialSourceLocation;
    widget.automaticTextSource?.addListener(_onAutomaticTextSource);
    if (initialCapture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _captureAndApply(
              capture: initialCapture,
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
    if (widget.initialInstruction case final instruction?) {
      _instructionController.text = instruction;
    } else if (widget.texts.isNotEmpty) {
      _instructionController.text = '总结当前笔记，提取待办事项，并生成合适的标题';
    }
    _loadPrompts();
  }

  @override
  void didUpdateWidget(covariant AiAgentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.automaticTextSource != widget.automaticTextSource) {
      oldWidget.automaticTextSource?.removeListener(_onAutomaticTextSource);
      widget.automaticTextSource?.addListener(_onAutomaticTextSource);
    }
    if (identical(oldWidget, widget)) return;
    final incoming = widget;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget, incoming)) return;
      if (_loading || _applying || _capturing) {
        setState(() => _attachmentNotice = '请完成当前操作后再切换来源');
        return;
      }
      _replaceSource((
        context: (
          noteTitle: incoming.noteTitle,
          texts: incoming.texts,
          truncated: incoming.contextTruncated,
          label: incoming.contextLabel,
          hasSelection: incoming.hasSelection,
        ),
        capture: incoming.initialSourceCapture,
        location: incoming.initialSourceLocation,
      ));
      if (incoming.initialInstruction case final instruction?) {
        _fillInstruction(instruction);
      }
    });
  }

  @override
  void dispose() {
    widget.automaticTextSource?.removeListener(_onAutomaticTextSource);
    _cancelToken?.cancel();
    unawaited(_speechService.cancel());
    unawaited(_speechSubscription?.cancel());
    if (_ownsSpeechService) unawaited(_speechService.dispose());
    _instructionController.dispose();
    _searchController.dispose();
    _streamRefresh?.cancel();
    _instructionFocusNode.dispose();
    _messageScroll.dispose();
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    for (final node in _actionFocusNodes) {
      node.dispose();
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
      _ownsSpeechSession = true;
      _speechFinalCommitted = false;
      await _speechService.start();
    } else {
      await _speechService.stop();
    }
  }

  void _onSpeechEvent(SpeechRecognitionEvent event) {
    if (!mounted || !_ownsSpeechSession) return;
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
          if (state == SpeechRecognitionState.idle) {
            _speechPreview = '';
            _ownsSpeechSession = false;
          }
        });
      case SpeechRecognitionFailed(:final message):
        setState(() {
          _speechState = SpeechRecognitionState.idle;
          _ownsSpeechSession = false;
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

  void _selectSource(AiAgentScope scope) {
    if (_loading || _applying || _capturing) return;
    final AiAgentSource source;
    try {
      source = widget.sourceProvider!(scope);
    } on StateError catch (error) {
      setState(() => _attachmentNotice = _errorMessage(error));
      return;
    }
    _replaceSource(source);
  }

  void _onAutomaticTextSource() {
    // Applying a reply can select the elements it just inserted.
    if (_applying) return;
    _pendingTextSource = widget.automaticTextSource?.value;
    _lockPendingTextSource();
  }

  void _lockPendingTextSource() {
    final source = _pendingTextSource;
    if (source == null || _loading || _applying || _capturing) return;
    _replaceSource(source, keepManualAttachments: true);
  }

  void _replaceSource(
    AiAgentSource source, {
    bool keepManualAttachments = false,
  }) {
    _pendingTextSource = null;
    final capture = source.capture;
    setState(() {
      // Keep visible messages, but stop resending history from the old source.
      _conversation = const [];
      _selectedActions = const {};
      _actionSourceChanged = true;
      if (keepManualAttachments) {
        _removeActiveSelectionSlot();
      } else {
        _attachments = const [];
        _activeSelectionSlot = null;
      }
      _attachmentNotice = null;
      _context = source.context;
      _sourceLocation = source.location;
      _needsSourceImage = capture != null;
    });
    if (capture != null) {
      unawaited(
        _captureAndApply(capture: capture, scene: _AiCaptureScene.passive),
      );
    }
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
      if (mounted) {
        setState(() => _capturing = false);
        _lockPendingTextSource();
      }
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
      if (mounted) {
        setState(() => _capturing = false);
        _lockPendingTextSource();
      }
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
    final webQuery = _searchEnabled ? _searchController.text.trim() : null;
    if (instruction.isEmpty ||
        webQuery == '' ||
        _loading ||
        _applying ||
        _speechState != SpeechRecognitionState.idle) {
      return;
    }
    final isFollowUp = _response != null;
    final generation = ++_generation;
    final cancelToken = NativeHttpCancelToken();
    _cancelToken = cancelToken;
    final streamedText = StringBuffer();
    setState(() {
      _stage = _AiGenerateStage.preparing;
      _loading = true;
      _error = null;
      _pendingInstruction = instruction;
      _streamPreview = '';
      _showShortcuts = false;
      if (!isFollowUp) _selectedActions = const {};
    });
    _revealInConversation(_latestMessageKey);
    // 在途捕获先于组请求完成（§1.2.5）：异常一律吸收——错误已由捕获
    // 路径按场景展示，发送以当前 _attachments 继续。
    final pending = _pendingCapture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    try {
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
      if (_needsSourceImage && _attachments.isEmpty) {
        throw StateError('来源截图不可用，请重新选择来源或添加框选截图');
      }
      final attachments = _attachments;
      final response = await widget.repository.run(
        instruction: instruction,
        noteTitle: context.noteTitle,
        texts: context.texts,
        conversation: _conversation,
        attachments: attachments,
        cancelToken: cancelToken,
        webQuery: webQuery,
        onText: (fragment) {
          if (!mounted ||
              !_loading ||
              generation != _generation ||
              cancelToken.isCancelled) {
            return;
          }
          streamedText.write(fragment);
          _streamRefresh ??= Timer(const Duration(milliseconds: 45), () {
            _streamRefresh = null;
            if (!mounted || generation != _generation) return;
            final follow =
                _messageScroll.hasClients &&
                _messageScroll.position.extentAfter < 80;
            setState(() => _streamPreview = streamedText.toString());
            if (follow) {
              runAfterUiFrame(() {
                if (mounted &&
                    generation == _generation &&
                    _messageScroll.hasClients) {
                  _messageScroll.jumpTo(
                    _messageScroll.position.maxScrollExtent,
                  );
                }
              });
            }
          });
        },
      );
      if (!mounted || generation != _generation || cancelToken.isCancelled) {
        return;
      }
      _setResponse(
        response,
        instruction: instruction,
        attachments: attachments,
      );
      _instructionController.clear();
      _searchController.clear();
      _revealInConversation(_latestMessageKey);
    } on NativeHttpCancelledException {
      // 用户主动取消，不显示为失败。
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _pendingInstruction = null;
          _searchEnabled = webQuery != null && _error != null;
          _streamPreview = _error == null ? '' : streamedText.toString();
        });
        _streamRefresh?.cancel();
        _streamRefresh = null;
        _lockPendingTextSource();
      }
    }
  }

  void _revealInConversation(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = key.currentContext;
      if (!mounted || anchor == null || !_messageScroll.hasClients) return;
      unawaited(Scrollable.ensureVisible(anchor));
    });
  }

  void _setResponse(
    AiAgentResponse response, {
    required String instruction,
    required List<AiVisualAttachment> attachments,
  }) {
    // 防呆：丢弃"不成立"的写动作（空值、与回复同文的说明、无效重命名、
    // 空导图），净化后为空则按纯回复处理，面板不出现确认区块。
    final actions = sanitizeAiAgentActions(
      message: response.message,
      actions: response.actions,
      currentNoteTitle: _context.noteTitle,
    );
    final effective = actions.length == response.actions.length
        ? response
        : AiAgentResponse(
            message: response.message,
            actions: actions,
            webSources: response.webSources,
          );
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    _actionControllers
      ..clear()
      ..addAll(
        actions.map((action) => TextEditingController(text: action.value)),
      );
    _actionFocusNodes
      ..clear()
      ..addAll(actions.map((_) => FocusNode()));
    final source = _sourceLocation;
    final sentTextIds = _context.texts
        .map((text) => text.sourceElementId)
        .toSet();
    final sentSource =
        attachments.contains(_activeSelectionSlot) ||
        (source is AiPageSource && sentTextIds.isNotEmpty) ||
        (source is AiElementSource && sentTextIds.containsAll(source.ids));
    setState(() {
      _conversation = compactAiAgentConversation([
        ..._conversation,
        AiAgentConversationTurn(instruction: instruction, response: effective),
      ]);
      _messages.add((
        instruction: instruction,
        response: effective,
        sourceTextIds: [
          for (final text in _context.texts) text.sourceElementId,
        ],
        images: [
          for (final image in attachments)
            (label: image.sourceLabel, location: image.location),
        ],
        source: source != null && sentSource
            ? (label: _context.label, location: source)
            : null,
      ));
      _applied = false;
      _actionSourceChanged = false;
      _editingDraft = false;
      _citationNotice = null;
      _citationNoticeTurn = null;
      _selectedActions = {
        for (var index = 0; index < actions.length; index++) index,
      };
    });
  }

  void _viewSource(AiSourceLocation? location, _AiPanelTurn turn) {
    final notice = location == null
        ? '此引用未对应本次发送的笔记来源'
        : widget.onViewSource?.call(location);
    setState(() {
      _citationNotice = notice;
      _citationNoticeTurn = notice == null ? null : turn;
    });
  }

  Widget _sourceButton(
    String label,
    AiSourceLocation location,
    _AiPanelTurn turn,
  ) {
    return ActionChip(
      avatar: const Icon(Icons.location_searching, size: 16),
      label: Text(label),
      tooltip: '定位来源',
      onPressed: _loading || _applying
          ? null
          : () => _viewSource(location, turn),
    );
  }

  void _openCitation(String? href, _AiPanelTurn turn) {
    if (href != null && href.startsWith('flowmuse-web:')) {
      final index = int.tryParse(href.substring('flowmuse-web:'.length));
      if (index != null &&
          index > 0 &&
          index <= turn.response.webSources.length) {
        _openWebSource(turn.response.webSources[index - 1].url);
      }
      return;
    }
    if (href == null || !href.startsWith('flowmuse-source:')) return;
    final match = RegExp(
      r'^flowmuse-source:(text|image)-([1-9][0-9]{0,5})$',
    ).firstMatch(href);
    if (match == null) {
      _viewSource(null, turn);
      return;
    }
    final index = int.parse(match[2]!) - 1;
    final location = switch (match[1]) {
      'text' when index < turn.sourceTextIds.length => AiElementSource([
        turn.sourceTextIds[index],
      ]),
      'image' when index < turn.images.length => turn.images[index].location,
      _ => null,
    };
    _viewSource(location, turn);
  }

  Future<void> _openWebSource(Uri url) async {
    if (!await AppUrlLauncher.launch(url) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开网页')));
    }
  }

  Widget _draftPreview(int index) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final List<NoteDraftBlock> blocks;
    try {
      blocks = parseNoteDraft(_actionControllers[index].text);
    } on FormatException catch (error) {
      return Text(error.message, style: TextStyle(color: colors.error));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '整理稿预览',
            style: theme.textTheme.labelMedium?.copyWith(color: colors.primary),
          ),
          const Divider(),
          for (final block in blocks)
            Padding(
              padding: EdgeInsets.only(
                top: block.role == NoteDraftRole.section ? 14 : 6,
              ),
              child: _previewDraftBlock(block, theme),
            ),
          if (_response?.webSources.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.listGap),
              child: Text(
                '确认后附上 ${_response!.webSources.length} 条网页参考资料',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewDraftBlock(NoteDraftBlock block, ThemeData theme) {
    final style =
        switch (block.role) {
          NoteDraftRole.title => theme.textTheme.headlineSmall,
          NoteDraftRole.section => theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
          _ => theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        } ??
        const TextStyle();
    if (standaloneLatex(block.text) case final latex?) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Math.tex(
          latex,
          mathStyle: MathStyle.display,
          textStyle: style,
          onErrorFallback: (_) => Text(block.text, style: style),
        ),
      );
    }
    final text = block.role == NoteDraftRole.bullet
        ? '•  ${block.text}'
        : block.text;
    return Text.rich(CanvasMarkdown.span(text, style));
  }

  void _clearConversation() {
    for (final controller in _actionControllers) {
      controller.dispose();
    }
    for (final node in _actionFocusNodes) {
      node.dispose();
    }
    _actionControllers.clear();
    _actionFocusNodes.clear();
    _instructionController.clear();
    _searchController.clear();
    setState(() {
      _conversation = const [];
      _messages.clear();
      _pendingInstruction = null;
      _streamPreview = '';
      _searchEnabled = false;
      _showShortcuts = null;
      _applied = false;
      _actionSourceChanged = false;
      _citationNotice = null;
      _citationNoticeTurn = null;
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
        if (_context.texts.isNotEmpty) _needsSourceImage = false;
      }
      _attachments = [..._attachments]..removeAt(index);
      if (widget.sourceProvider != null) _conversation = const [];
    });
  }

  void _cancelGeneration() {
    _cancelToken?.cancel();
    _generation++;
    _streamRefresh?.cancel();
    _streamRefresh = null;
    setState(() {
      _loading = false;
      _pendingInstruction = null;
      _error = '已取消生成';
    });
    _lockPendingTextSource();
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
          webSources: response.webSources,
          actions: [
            for (var index = 0; index < response.actions.length; index++)
              if (_selectedActions.contains(index)) _editedAction(index),
          ],
        ),
      );
      if (mounted) {
        setState(() {
          _applying = false;
          _applied = true;
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

  Future<void> _previewAttachment(AiVisualAttachment attachment) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.compactPageInset),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 900,
            height: 700,
            child: Column(
              children: [
                ListTile(
                  title: Text(attachment.sourceLabel),
                  subtitle: Text(attachment.sizeLabel),
                  trailing: IconButton(
                    tooltip: '关闭截图预览',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: SizedBox.expand(
                        child: Image.memory(
                          attachment.bytes,
                          fit: BoxFit.contain,
                          semanticLabel: attachment.sourceLabel,
                          errorBuilder: (_, _, _) =>
                              const Center(child: Text('无法显示这张图片')),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _attachmentTileDecoration(ColorScheme colors) => BoxDecoration(
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(AppSpacing.radius),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildPanel(context, constraints.maxHeight),
  );

  Widget _buildPanel(BuildContext context, double height) {
    final shortcutsOpen = _showShortcuts ?? _messages.isEmpty;
    final response = _response;
    final instruction = _instructionController.text.trim();
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sidebarInset,
              4,
              AppSpacing.controlGap,
              4,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
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
                const SizedBox(width: AppSpacing.controlGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI笔记助手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.sourceProvider == null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _context.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_messages.isNotEmpty)
                  IconButton(
                    tooltip: '清除对话',
                    onPressed: _loading || _applying || _capturing
                        ? null
                        : () {
                            if (widget.sourceProvider != null) {
                              _selectSource(AiAgentScope.none);
                            }
                            _clearConversation();
                          },
                    icon: const Icon(Icons.edit_square),
                  ),
                IconButton(
                  tooltip: '收起AI笔记助手',
                  onPressed: _applying
                      ? null
                      : () {
                          _instructionFocusNode.unfocus();
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
              controller: _messageScroll,
              padding: const EdgeInsets.all(AppSpacing.sidebarInset),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_messages.isEmpty && !_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        '从当前页或选区开始，和笔记聊一聊',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final (index, turn) in _messages.indexed) ...[
                    _userMessage(
                      turn.instruction,
                      key:
                          index == _messages.length - 1 &&
                              _pendingInstruction == null
                          ? _latestMessageKey
                          : null,
                    ),
                    ..._replyWidgets(context, turn),
                    if (index == _messages.length - 1 && response != null)
                      ..._actionWidgets(context, response),
                    const SizedBox(height: 16),
                  ],
                  if (shortcutsOpen) ..._shortcutWidgets(context),
                  if (_pendingInstruction case final pending?)
                    _userMessage(pending, key: _latestMessageKey),
                  if (_streamPreview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.listGap),
                      child: SelectableText(_streamPreview),
                    )
                  else if (_loading) ...[
                    const SizedBox(height: AppSpacing.controlGap),
                    Text(
                      _stage == _AiGenerateStage.preparing
                          ? '正在准备上下文…'
                          : _searchEnabled
                          ? '正在查找资料并生成回复…'
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
                ],
              ),
            ),
          ),
          _composer(context, response, instruction, colors, height),
        ],
      ),
    );
  }

  Widget _userMessage(String text, {Key? key}) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      key: key,
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 28, top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(text),
      ),
    );
  }

  List<Widget> _replyWidgets(BuildContext context, _AiPanelTurn turn) {
    final colors = Theme.of(context).colorScheme;
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.listGap),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: SelectionArea(
          child: MarkdownBody(
            data: turn.response.message,
            blockSyntaxes: [ReplyBlockLatex()],
            inlineSyntaxes: [ReplyInlineLatex()],
            builders: {
              'reply-math-block': ReplyLatexBuilder(display: true),
              'reply-math-inline': ReplyLatexBuilder(),
            },
            imageBuilder: turn.response.webSources.isEmpty
                ? null
                : (_, _, _) => const SizedBox.shrink(),
            onTapLink:
                (widget.onViewSource == null &&
                        turn.response.webSources.isEmpty) ||
                    _applying ||
                    _loading
                ? null
                : (_, href, _) => _openCitation(href, turn),
            styleSheet: MarkdownStyleSheet.fromTheme(
              Theme.of(context),
            ).copyWith(p: TextStyle(color: colors.onSurface)),
          ),
        ),
      ),
      if (turn.response.webSources.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.controlGap),
          child: Text('网页来源', style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final (index, source) in turn.response.webSources.indexed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openWebSource(source.url),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                '${index + 1}. ${source.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      if (widget.onViewSource != null) ...[
        if (turn.source != null ||
            turn.sourceTextIds.isNotEmpty ||
            turn.images.any((image) => image.location != null))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.controlGap),
            child: Text('本次发送来源', style: Theme.of(context).textTheme.bodySmall),
          ),
        Wrap(
          spacing: AppSpacing.controlGap,
          children: [
            if (turn.source case (:final label, :final location))
              _sourceButton(label, location, turn)
            else if (turn.sourceTextIds.isNotEmpty)
              _sourceButton(
                '第一段原文',
                AiElementSource([turn.sourceTextIds.first]),
                turn,
              ),
            for (final image in turn.images)
              if (image.location case final location?)
                if (!identical(location, turn.source?.location))
                  _sourceButton(image.label, location, turn),
          ],
        ),
        if (_citationNoticeTurn == turn)
          if (_citationNotice case final notice?)
            Text(notice, style: Theme.of(context).textTheme.bodySmall),
      ],
    ];
  }

  List<Widget> _actionWidgets(BuildContext context, AiAgentResponse response) {
    if (response.actions.isEmpty) return const [];
    if (_applied) {
      return [
        Text(
          response.actions.singleOrNull?.tool == AiAgentTool.draftNote
              ? '已写入笔记'
              : '已确认操作',
        ),
      ];
    }
    if (_actionSourceChanged) return const [Text('来源已切换，请重新生成操作')];
    final colors = Theme.of(context).colorScheme;
    return [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(AppSpacing.controlGap),
        decoration: _attachmentTileDecoration(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (response.actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.listGap),
              const Text(
                '确认后写入当前笔记：',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
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
                    secondary: Icon(switch (response.actions[index].tool) {
                      AiAgentTool.renameNote => Icons.drive_file_rename_outline,
                      AiAgentTool.insertText => Icons.note_add_outlined,
                      AiAgentTool.draftNote => Icons.article_outlined,
                      AiAgentTool.generateMindmap => Icons.account_tree,
                      AiAgentTool.smartLayout => Icons.auto_fix_high,
                    }),
                    title: Text(response.actions[index].label),
                  ),
                  if (response.actions[index].tool ==
                      AiAgentTool.draftNote) ...[
                    if (!_editingDraft) _draftPreview(index),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _applying || _loading
                            ? null
                            : () => setState(
                                () => _editingDraft = !_editingDraft,
                              ),
                        icon: Icon(
                          _editingDraft
                              ? Icons.visibility_outlined
                              : Icons.edit_outlined,
                          size: 16,
                        ),
                        label: Text(_editingDraft ? '预览成稿' : '编辑草稿'),
                      ),
                    ),
                  ],
                  if (response.actions[index].tool != AiAgentTool.smartLayout &&
                      (response.actions[index].tool != AiAgentTool.draftNote ||
                          _editingDraft))
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 40,
                        bottom: AppSpacing.controlGap,
                      ),
                      child: KeyboardFocusRecoveryExclusion(
                        child: TextField(
                          controller: _actionControllers[index],
                          focusNode: _actionFocusNodes[index],
                          enabled: !_applying && !_loading,
                          onTapAlwaysCalled: true,
                          onTap: () {
                            final node = _actionFocusNodes[index];
                            if (!node.hasFocus) {
                              FocusScope.of(context).requestFocus(node);
                              return;
                            }
                            if (_applying || _loading) return;
                            node.unfocus();
                            Future<void>.delayed(
                              const Duration(milliseconds: 50),
                              () {
                                if (context.mounted) {
                                  FocusScope.of(context).requestFocus(node);
                                }
                              },
                            );
                          },
                          onChanged: (_) => setState(() {}),
                          minLines: 1,
                          maxLines: switch (response.actions[index].tool) {
                            AiAgentTool.renameNote => 2,
                            AiAgentTool.insertText => 8,
                            AiAgentTool.draftNote => 12,
                            AiAgentTool.generateMindmap => 12,
                            AiAgentTool.smartLayout => 1,
                          },
                          maxLength: switch (response.actions[index].tool) {
                            AiAgentTool.renameNote => maxAiAgentTitleLength,
                            AiAgentTool.insertText ||
                            AiAgentTool.draftNote => maxAiAgentTextLength,
                            AiAgentTool.generateMindmap =>
                              maxAiMindmapJsonLength,
                            AiAgentTool.smartLayout => 0,
                          },
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            helperText:
                                response.actions[index].tool ==
                                    AiAgentTool.draftNote
                                ? '# 标题，## 分节，- 列表'
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _loading || !_canApply ? null : _apply,
                child: Text(
                  _applying
                      ? '正在应用…'
                      : response.actions.singleOrNull?.tool ==
                            AiAgentTool.draftNote
                      ? '确认写入整理稿'
                      : '确认应用',
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _shortcutWidgets(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasNoSource =
        widget.sourceProvider != null &&
        _context.noteTitle.isEmpty &&
        _attachments.isEmpty;
    final shortcuts = hasNoSource
        ? const {
            '课堂笔记模板': '给我一份可复用的课堂笔记模板，包含核心概念、例题和待复习问题。',
            '复习计划模板': '给我一份可填写的复习计划模板，包含目标、复习安排和自测。',
            '任务清单模板': '给我一份可复用的任务清单模板，按优先级整理，并留出截止日期。',
          }
        : _context.hasSelection
        ? const {
            '解释这里': '解释这里的内容',
            '检查公式': '检查这里的公式是否正确，如有错误请指出',
            '整理文字': '整理这里的文字内容',
            '整理为笔记': '把这段内容整理为笔记，保留要点，看不清的地方标为待确认',
            '整理成导图': '把这里的内容整理成思维导图',
          }
        : const {
            '总结': '总结本次提供的内容',
            '待办': '提取待办事项',
            '大纲': '生成结构化大纲',
            '整理为笔记': '把本次提供的内容整理为笔记，保留要点，看不清的地方标为待确认',
            '思维导图': '根据当前内容生成思维导图',
            '手写排版': '智能排版当前手写内容',
          };
    return [
      Text(
        '快捷指令',
        key: _shortcutsKey,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: AppSpacing.controlGap),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final shortcut in shortcuts.entries)
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
    ];
  }

  Widget _composer(
    BuildContext context,
    AiAgentResponse? response,
    String instruction,
    ColorScheme colors,
    double height,
  ) {
    final shortcutsOpen = _showShortcuts ?? _messages.isEmpty;
    final hasSource =
        widget.sourceProvider != null && _context.noteTitle.isNotEmpty;
    final busy = _loading || _applying || _capturing;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (height * 0.27).clamp(0.0, 176.0),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasSource)
                    InputChip(
                      label: Text(
                        _context.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteButtonTooltipMessage: '移除笔记来源',
                      onDeleted: busy
                          ? null
                          : () => _selectSource(AiAgentScope.none),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_hasAttachmentSources) ...[
                    if (widget.sourceProvider == null)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (widget.onCaptureSelection != null ||
                              widget.onRegionCapture != null)
                            _selectionCaptureButton(),
                          if (widget.onCaptureCurrentPdfPage != null)
                            ActionChip(
                              avatar: const Icon(
                                Icons.picture_as_pdf,
                                size: 18,
                              ),
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
                                        capture:
                                            widget.onCaptureCurrentPdfPage!,
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
                                  Tooltip(
                                    message: '查看截图',
                                    child: InkWell(
                                      onTap: () =>
                                          _previewAttachment(attachment),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radius,
                                      ),
                                      child: Image.memory(
                                        attachment.bytes,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.contain,
                                        cacheWidth: 88,
                                      ),
                                    ),
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
                    if (widget.sourceProvider == null ||
                        hasSource ||
                        _attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                        child: Text(
                          widget.sourceProvider != null
                              ? _attachments.isEmpty
                                    ? '所选文字将随消息发送至模型服务。'
                                    : '截图包含框内可见内容，将随消息发送至模型服务，请先核对。'
                              : _attachments.isEmpty
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                  ],
                  if (widget.sourceProvider == null)
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
                ],
              ),
            ),
          ),
          if (_searchEnabled)
            KeyboardFocusRecoveryExclusion(
              child: TextField(
                controller: _searchController,
                enabled: !_loading && !_applying,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '搜索关键词',
                  helperText: '仅此关键词发送给网页搜索服务',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(height: 6),
          KeyboardFocusRecoveryExclusion(
            child: TextField(
              key: const ValueKey('note-agent-composer'),
              controller: _instructionController,
              focusNode: _instructionFocusNode,
              enabled: !_loading && !_applying,
              onTapAlwaysCalled: true,
              onTap: () {
                if (!_instructionFocusNode.hasFocus) {
                  FocusScope.of(context).requestFocus(_instructionFocusNode);
                  return;
                }
                if (_loading || _applying) return;
                _instructionFocusNode.unfocus();
                Future<void>.delayed(const Duration(milliseconds: 50), () {
                  if (context.mounted) {
                    FocusScope.of(context).requestFocus(_instructionFocusNode);
                  }
                });
              },
              onChanged: (_) => setState(() {}),
              maxLength: 1000,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: response == null ? '输入你的问题或任务' : '继续提问，或调整上一次结果',
                contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                isDense: true,
                counterText: '',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                helperText: _speechState == SpeechRecognitionState.idle
                    ? null
                    : (_speechPreview.isEmpty ? '正在聆听…' : _speechPreview),
              ),
            ),
          ),

          Row(
            children: [
              if (widget.sourceProvider != null)
                Builder(
                  builder: (anchor) => IconButton(
                    tooltip: '选择来源',
                    onPressed: busy
                        ? null
                        : () => _showComposerMenu(anchor, instruction),
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ),
              IconButton(
                tooltip: shortcutsOpen ? '收起快捷指令' : '展开快捷指令',
                isSelected: shortcutsOpen,
                onPressed: () {
                  setState(() => _showShortcuts = !shortcutsOpen);
                  if (!shortcutsOpen) _revealInConversation(_shortcutsKey);
                },
                icon: const Icon(Icons.bolt_outlined, size: 20),
                selectedIcon: const Icon(Icons.bolt, size: 20),
              ),
              if (widget.sourceProvider != null &&
                  (widget.onRegionCapture != null ||
                      widget.onCaptureSelection != null))
                IconButton(
                  tooltip: '选区截图',
                  onPressed:
                      busy || _attachments.length >= maxAiVisualAttachments
                      ? null
                      : _captureSelection,
                  icon: const Icon(Icons.crop_free, size: 20),
                ),
              if (widget.sourceProvider == null)
                IconButton(
                  tooltip: '保存为常用指令',
                  onPressed: _loading || _applying || instruction.isEmpty
                      ? null
                      : _savePrompt,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                ),
              const Spacer(),
              if (widget.sourceProvider != null)
                IconButton(
                  tooltip: _searchEnabled ? '关闭查资料' : '查资料',
                  isSelected: _searchEnabled,
                  onPressed: busy
                      ? null
                      : () => setState(() => _searchEnabled = !_searchEnabled),
                  icon: const Icon(Icons.travel_explore, size: 20),
                  selectedIcon: const Icon(Icons.public, size: 20),
                ),
              if (_speechAvailable)
                IconButton(
                  tooltip: _speechState == SpeechRecognitionState.idle
                      ? '语音输入'
                      : '结束语音输入',
                  onPressed: _loading || _applying ? null : _toggleSpeech,
                  icon: Icon(
                    _speechState == SpeechRecognitionState.idle
                        ? Icons.mic_none
                        : Icons.stop_circle_outlined,
                    size: 20,
                  ),
                ),
              IconButton.filled(
                tooltip: _loading
                    ? '取消生成'
                    : response == null
                    ? '发送'
                    : '追问修改',
                onPressed: _loading
                    ? _cancelGeneration
                    : _applying ||
                          instruction.isEmpty ||
                          (_searchEnabled &&
                              _searchController.text.trim().isEmpty) ||
                          _speechState != SpeechRecognitionState.idle
                    ? null
                    : _generate,
                icon: Icon(
                  _loading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  size: 19,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showComposerMenu(
    BuildContext anchor,
    String instruction,
  ) async {
    final action = await showAnchoredPopupMenu<VoidCallback>(
      context: anchor,
      placement: AnchoredPopupPlacement.above,
      items: [
        for (final (scope, icon, label) in const [
          (AiAgentScope.selection, Icons.crop_free, '当前选区'),
          (AiAgentScope.page, Icons.description_outlined, '当前页'),
          (AiAgentScope.note, Icons.notes_outlined, '整篇笔记（仅文字）'),
        ])
          _composerMenuItem(label, icon, () => _selectSource(scope)),
        if (widget.onCaptureCurrentPdfPage case final capture?)
          _composerMenuItem(
            'PDF 页',
            Icons.picture_as_pdf_outlined,
            _attachments.length >= maxAiVisualAttachments
                ? null
                : () => unawaited(
                    _captureAndApply(
                      capture: capture,
                      scene: _AiCaptureScene.manual,
                    ),
                  ),
          ),
        const PopupMenuDivider(),
        _composerMenuItem(
          '保存为常用指令',
          Icons.bookmark_add_outlined,
          instruction.isEmpty ? null : () => unawaited(_savePrompt()),
        ),
      ],
    );
    if (mounted && !_loading && !_applying && !_capturing) action?.call();
  }

  PopupMenuItem<VoidCallback> _composerMenuItem(
    String label,
    IconData icon,
    VoidCallback? action,
  ) => PopupMenuItem(
    value: action,
    enabled: action != null,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.controlGap),
        Flexible(child: Text(label)),
      ],
    ),
  );

  void _captureSelection() => unawaited(
    widget.onRegionCapture != null
        ? _addRegionAttachment()
        : _captureAndApply(
            capture: widget.onCaptureSelection!,
            scene: _AiCaptureScene.manual,
          ),
  );

  Widget _selectionCaptureButton() => ActionChip(
    avatar: const Icon(Icons.crop_free, size: 18),
    label: const Text('选区截图'),
    visualDensity: VisualDensity.compact,
    onPressed:
        _loading ||
            _applying ||
            _capturing ||
            _attachments.length >= maxAiVisualAttachments
        ? null
        : _captureSelection,
  );
}
