/// Split-pane widget for live bidirectional sync between canvas and .markdraw text.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../markdraw.dart' hide TextAlign;
import '../core/elements/collaboration_element_owner.dart';

/// A split pane that shows the editor canvas on the left and a live
/// sketch text editor on the right, with bidirectional sync.
///
/// Canvas changes are reflected in the text pane immediately.
/// Text edits are parsed and applied to the canvas after a 150ms debounce.
///
/// The text pane shows only sketch element lines (no frontmatter, no fences,
/// no files block). A "copy as markdown" button wraps the content in a
/// `` ```markdraw `` fence for pasting into markdown documents.
class MarkdrawSplitPane extends StatefulWidget {
  const MarkdrawSplitPane({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The editor controller to sync with.
  final MarkdrawController controller;

  /// The editor content (typically the Stack from MarkdrawEditor._buildBody).
  final Widget child;

  @override
  State<MarkdrawSplitPane> createState() => _MarkdrawSplitPaneState();
}

/// v4 §9.1 text→canvas 的归属决策（纯函数，供测试）。
/// 返回新元素列表：alias 命中 sidecar → 恢复；未命中 → localCreator 盖章
/// （null 则无 owner）；绑定文字继承父元素（两遍处理）；系统元素清除。
List<Element> applySidecarOwners({
  required List<Element> parsedElements,
  required Map<String, String> aliasToElementId,
  required Map<String, CollaborationCreator> sidecar,
  CollaborationCreator? Function()? localCreatorResolver,
}) {
  final idToAlias = <String, String>{
    for (final entry in aliasToElementId.entries) entry.value: entry.key,
  };
  final resolved = <ElementId, CollaborationCreator?>{};

  // 第一遍：非绑定文字按 alias 决策
  final firstPass = <Element>[
    for (final element in parsedElements)
      _resolveStandalone(
        element,
        idToAlias,
        sidecar,
        localCreatorResolver,
        resolved,
      ),
  ];

  // 第二遍：绑定文字跟随父（父在前在后均可）
  final byId = <ElementId, Element>{
    for (final element in firstPass) element.id: element,
  };
  return [
    for (final element in firstPass) _resolveBoundText(element, byId, resolved),
  ];
}

Element _resolveStandalone(
  Element element,
  Map<String, String> idToAlias,
  Map<String, CollaborationCreator> sidecar,
  CollaborationCreator? Function()? localCreatorResolver,
  Map<ElementId, CollaborationCreator?> resolved,
) {
  if (element.isCanvasPage || element.isPdfBackground) {
    return withoutCreator(element);
  }
  if (element is TextElement && element.containerId != null) {
    return element; // 第二遍处理
  }
  final alias = idToAlias[element.id.value];
  CollaborationCreator? owner;
  if (alias != null && sidecar.containsKey(alias)) {
    owner = sidecar[alias];
  } else {
    owner = localCreatorResolver?.call();
  }
  resolved[element.id] = owner;
  return owner == null ? withoutCreator(element) : withCreator(element, owner);
}

Element _resolveBoundText(
  Element element,
  Map<ElementId, Element> byId,
  Map<ElementId, CollaborationCreator?> resolved,
) {
  final containerId = element is TextElement ? element.containerId : null;
  if (containerId == null) return element;
  final parent = byId[ElementId(containerId)];
  final owner = parent == null
      ? null
      : (resolved[parent.id] ?? readCreator(parent));
  return owner == null ? withoutCreator(element) : withCreator(element, owner);
}

/// 检测文本中重复出现的 `id=<alias>` 标识。词边界断言防止 `rect1` 误匹配
/// `rect11`（alias 形如 keyword+数字）。返回重复的 alias 列表。
List<String> findDuplicateAliasIds(String text, Map<String, String> aliases) {
  return [
    for (final alias in aliases.keys)
      if (RegExp(
            'id=${RegExp.escape(alias)}(?![0-9A-Za-z_])',
          ).allMatches(text).length >
          1)
        alias,
  ];
}

class _MarkdrawSplitPaneState extends State<MarkdrawSplitPane>
    with TickerProviderStateMixin {
  final _codeController = CodeLineEditingController();
  final _textFocusNode = FocusNode();

  bool _isSyncing = false;
  Timer? _debounceTimer;
  double _splitRatio = 0.8;
  bool _isDraggingDivider = false;
  bool _dockBottom = false;
  String _lastSyncedText = '';
  bool _hasPushedForSession = false;
  final Map<String, CollaborationCreator> _aliasCreators = {};

  // Parse status
  List<ParseWarning> _parseWarnings = [];
  bool _hasParseError = false;
  String _parseErrorMessage = '';

  // Flash animations
  late final AnimationController _canvasFlash;
  late final AnimationController _textFlash;

  static const _minPaneWidth = 280.0;
  static const _dividerWidth = 8.0;
  static const _debounceMs = 500;

  @override
  void initState() {
    super.initState();

    _canvasFlash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _textFlash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _codeController.addListener(_onTextChanged);

    // Wire up scene change listener.
    _previousOnSceneChanged = widget.controller.onSceneChanged;
    widget.controller.onSceneChanged = _onSceneChanged;

    // Listen for controller changes (e.g. rename).
    widget.controller.addListener(_onControllerChanged);

    // Seed the text pane with the current scene.
    _lastSyncedName = widget.controller.documentName;
    _syncCanvasToText();
  }

  // Store the previous callback so we can chain it.
  void Function(Scene scene, SceneChangeSource source)? _previousOnSceneChanged;

  // Track last-synced name so we can detect renames.
  String? _lastSyncedName;

  @override
  void didUpdateWidget(MarkdrawSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      // Restore old controller's callback.
      oldWidget.controller.onSceneChanged = _previousOnSceneChanged;
      // Re-wire to new controller.
      _previousOnSceneChanged = widget.controller.onSceneChanged;
      widget.controller.onSceneChanged = _onSceneChanged;
      widget.controller.addListener(_onControllerChanged);
      _syncCanvasToText();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _codeController.dispose();
    _textFocusNode.dispose();
    _canvasFlash.dispose();
    _textFlash.dispose();
    widget.controller.removeListener(_onControllerChanged);
    // Restore the previous callback.
    widget.controller.onSceneChanged = _previousOnSceneChanged;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sync: canvas → text (immediate, sketch lines only)
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    if (!mounted || _isSyncing) return;
    final currentName = widget.controller.documentName;
    if (currentName != _lastSyncedName) {
      _lastSyncedName = currentName;
      _syncCanvasToText();
      _textFlash.forward(from: 0);
    }
  }

  void _onSceneChanged(Scene scene, SceneChangeSource source) {
    _previousOnSceneChanged?.call(scene, source);
    if (!mounted || _isSyncing) return;
    _hasPushedForSession = false;
    _syncCanvasToText();
    _textFlash.forward(from: 0);
  }

  void _syncCanvasToText() {
    if (!mounted) return;
    _isSyncing = true;
    final result = widget.controller.serializeSceneWithAliases();
    final fullText = result.text;
    final sketchLines = _extractSketchLines(fullText);
    // 重建 alias → creator sidecar：只记录当前 Scene 中带 owner 的 alias，
    // 不写入文本、不落盘、不进剪贴板（v4 §9.1）。
    final scene = widget.controller.editorState.scene;
    _aliasCreators
      ..clear()
      ..addAll({
        for (final entry in result.aliases.entries)
          if (scene.getElementById(ElementId(entry.value)) case final element?)
            entry.key: ?readCreator(element),
      });
    _codeController.text = sketchLines;
    _lastSyncedText = sketchLines;
    _lastSyncedName = widget.controller.documentName;
    _isSyncing = false;
  }

  /// Extracts the lines between `` ```markdraw `` and `` ``` `` fences.
  static String _extractSketchLines(String fullText) {
    final lines = fullText.split('\n');
    final buffer = StringBuffer();
    var inSketch = false;
    for (final line in lines) {
      if (line.trim() == '```markdraw') {
        inSketch = true;
        continue;
      }
      if (line.trim() == '```' && inSketch) {
        inSketch = false;
        continue;
      }
      if (inSketch) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line);
      }
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Sync: text → canvas (debounced 500ms)
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    if (_isSyncing) return;
    final currentText = _codeController.text;
    if (currentText == _lastSyncedText) return;
    _lastSyncedText = currentText;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
      if (mounted) {
        _syncTextToCanvas();
      }
    });
  }

  void _syncTextToCanvas() {
    if (!mounted) return;
    final text = _codeController.text;
    _isSyncing = true;
    try {
      if (text.trim().isEmpty) {
        if (_hasPushedForSession) {
          widget.controller.replaceScene(Scene());
        } else {
          widget.controller.applyScene(Scene());
          _hasPushedForSession = true;
        }
        setState(() {
          _parseWarnings = [];
          _hasParseError = false;
          _parseErrorMessage = '';
        });
      } else {
        final bg = widget.controller.canvasBackgroundColor;
        final wrapped =
            '---\nmarkdraw: 1\nbackground: "$bg"\n---\n\n'
            '```markdraw\n$text\n```';
        final parseResult = DocumentParser.parse(wrapped);
        final doc = parseResult.value;
        final duplicateAliases = findDuplicateAliasIds(wrapped, doc.aliases);
        if (duplicateAliases.isNotEmpty) {
          // 受控失败：保留上次成功画布，显示可读错误（v4 §9.1 规则 1）。
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '文本中存在重复的元素标识：${duplicateAliases.join('、')}，画布保持上次成功状态',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          _isSyncing = false;
          return;
        }
        final scene = SceneDocumentConverter.documentToScene(doc);
        final ownedScene = scene.upsertRemoteElements(
          applySidecarOwners(
            parsedElements: scene.elements,
            aliasToElementId: doc.aliases,
            sidecar: _aliasCreators,
            localCreatorResolver: widget.controller.localCreatorResolver,
          ),
        );
        if (_hasPushedForSession) {
          widget.controller.replaceScene(ownedScene, background: bg);
        } else {
          widget.controller.applyScene(ownedScene, background: bg);
          _hasPushedForSession = true;
        }
        // Sync @name directive back to the controller
        widget.controller.renameDocument(doc.settings.name ?? '');
        setState(() {
          _parseWarnings = parseResult.warnings;
          _hasParseError = false;
          _parseErrorMessage = '';
        });
      }
      _canvasFlash.forward(from: 0);
    } catch (e) {
      // Parse error — canvas keeps last successful state.
      setState(() {
        _hasParseError = true;
        _parseErrorMessage = e.toString();
      });
    }
    _isSyncing = false;
  }

  // ---------------------------------------------------------------------------
  // Copy as markdown
  // ---------------------------------------------------------------------------

  void _onCopyMarkdown() {
    final text = _codeController.text;
    final markdown = '```markdraw\n$text\n```';
    Clipboard.setData(ClipboardData(text: markdown));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制为 Markdown'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  Widget _buildTextPane() {
    return Stack(
      children: [
        _TextPane(
          controller: _codeController,
          focusNode: _textFocusNode,
          onCopyMarkdown: _onCopyMarkdown,
          parseWarnings: _parseWarnings,
          hasParseError: _hasParseError,
          parseErrorMessage: _parseErrorMessage,
          dockBottom: _dockBottom,
          onDockChanged: (bottom) => setState(() => _dockBottom = bottom),
        ),
        _FlashOverlay(animation: _textFlash),
      ],
    );
  }

  Widget _buildCanvasPane() {
    return Stack(
      children: [
        widget.child,
        _FlashOverlay(animation: _canvasFlash),
      ],
    );
  }

  Widget _buildDivider(
    BuildContext context,
    double primarySize,
    double usableSize,
  ) {
    final dividerColor = _isDraggingDivider
        ? Theme.of(context).colorScheme.primary.withAlpha(80)
        : Theme.of(context).dividerColor;

    if (_dockBottom) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          onVerticalDragStart: (_) {
            setState(() => _isDraggingDivider = true);
          },
          onVerticalDragUpdate: (details) {
            setState(() {
              final newTop = (primarySize + details.delta.dy).clamp(
                _minPaneWidth,
                usableSize - _minPaneWidth,
              );
              _splitRatio = newTop / usableSize;
            });
          },
          onVerticalDragEnd: (_) {
            setState(() => _isDraggingDivider = false);
          },
          child: Container(height: _dividerWidth, color: dividerColor),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) {
          setState(() => _isDraggingDivider = true);
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            final newLeft = (primarySize + details.delta.dx).clamp(
              _minPaneWidth,
              usableSize - _minPaneWidth,
            );
            _splitRatio = newLeft / usableSize;
          });
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDraggingDivider = false);
        },
        child: Container(width: _dividerWidth, color: dividerColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_dockBottom) {
          final totalHeight = constraints.maxHeight;
          final usableHeight = totalHeight - _dividerWidth;
          final minRatio = _minPaneWidth / usableHeight;
          final maxRatio = 1.0 - minRatio;
          final clampedRatio = _splitRatio.clamp(minRatio, maxRatio);
          final topHeight = usableHeight * clampedRatio;

          return Column(
            children: [
              ClipRect(
                child: SizedBox(height: topHeight, child: _buildCanvasPane()),
              ),
              _buildDivider(context, topHeight, usableHeight),
              Expanded(child: _buildTextPane()),
            ],
          );
        }

        final totalWidth = constraints.maxWidth;
        final usableWidth = totalWidth - _dividerWidth;
        final minRatio = _minPaneWidth / usableWidth;
        final maxRatio = 1.0 - minRatio;
        final clampedRatio = _splitRatio.clamp(minRatio, maxRatio);
        final leftWidth = usableWidth * clampedRatio;

        return Row(
          children: [
            ClipRect(
              child: SizedBox(width: leftWidth, child: _buildCanvasPane()),
            ),
            _buildDivider(context, leftWidth, usableWidth),
            Expanded(child: _buildTextPane()),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Text pane with header
// -----------------------------------------------------------------------------

class _TextPane extends StatelessWidget {
  const _TextPane({
    required this.controller,
    required this.focusNode,
    required this.onCopyMarkdown,
    required this.parseWarnings,
    required this.hasParseError,
    required this.parseErrorMessage,
    required this.dockBottom,
    required this.onDockChanged,
  });

  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCopyMarkdown;
  final List<ParseWarning> parseWarnings;
  final bool hasParseError;
  final String parseErrorMessage;
  final bool dockBottom;
  final ValueChanged<bool> onDockChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Header bar
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.code,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'markdraw',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Tooltip(
                message: '停靠在右侧',
                child: IconButton(
                  icon: Icon(
                    Icons.vertical_split,
                    size: 18,
                    color: dockBottom
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                  onPressed: () => onDockChanged(false),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
              Tooltip(
                message: '停靠在底部',
                child: IconButton(
                  icon: Icon(
                    Icons.horizontal_split,
                    size: 18,
                    color: dockBottom
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => onDockChanged(true),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
              Tooltip(
                message: '复制为 Markdown',
                child: IconButton(
                  icon: Icon(
                    Icons.text_snippet,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onCopyMarkdown,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Code editor
        Expanded(
          child: CodeAutocomplete(
            viewBuilder: buildAutocompleteView,
            promptsBuilder: ElementIdPromptsBuilder(
              delegate: DefaultCodeAutocompletePromptsBuilder(
                language: langMarkdraw,
                keywordPrompts: markdrawPrompts,
              ),
              controller: controller,
            ),
            child: CodeEditor(
              controller: controller,
              focusNode: focusNode,
              style: CodeEditorStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontHeight: 1.5,
                codeTheme: CodeHighlightTheme(
                  languages: {
                    'markdraw': CodeHighlightThemeMode(mode: langMarkdraw),
                  },
                  theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                ),
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return DefaultCodeLineNumber(
                      controller: editingController,
                      notifier: notifier,
                      textStyle: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(
                          120,
                        ),
                      ),
                    );
                  },
              sperator: const SizedBox.shrink(),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
        // Parse status bar
        _ParseStatusBar(
          parseWarnings: parseWarnings,
          hasParseError: hasParseError,
          parseErrorMessage: parseErrorMessage,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Parse status bar — shows OK / warnings / error
// -----------------------------------------------------------------------------

class _ParseStatusBar extends StatelessWidget {
  const _ParseStatusBar({
    required this.parseWarnings,
    required this.hasParseError,
    required this.parseErrorMessage,
  });

  final List<ParseWarning> parseWarnings;
  final bool hasParseError;
  final String parseErrorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color dotColor;
    final String label;
    final String? detail;

    if (hasParseError) {
      dotColor = Colors.red;
      label = '解析错误';
      detail = parseErrorMessage;
    } else if (parseWarnings.isNotEmpty) {
      dotColor = Colors.amber;
      final count = parseWarnings.length;
      label = '$count 个警告';
      detail = parseWarnings.first.message;
    } else {
      dotColor = Colors.green;
      label = '正常';
      detail = null;
    }

    return Tooltip(
      message: _tooltipMessage(),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _tooltipMessage() {
    if (hasParseError) return parseErrorMessage;
    if (parseWarnings.isEmpty) return '没有问题';
    return parseWarnings.map((w) => '第 ${w.line} 行：${w.message}').join('\n');
  }
}

// -----------------------------------------------------------------------------
// Flash overlay — fades primary color over 300ms
// -----------------------------------------------------------------------------

class _FlashOverlay extends StatelessWidget {
  const _FlashOverlay({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final alpha = (1.0 - animation.value) * 0.12;
        if (alpha <= 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: color.withValues(alpha: alpha)),
          ),
        );
      },
    );
  }
}
