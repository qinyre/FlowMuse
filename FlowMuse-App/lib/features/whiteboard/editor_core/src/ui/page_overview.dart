import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Element, TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

import '../rendering/page_thumbnail.dart';
import 'page_navigation_controls.dart';
import 'positioned_math_text.dart';

/// Mounted only while open. Preview updates stay inside this subtree.
class PageOverview extends StatefulWidget {
  const PageOverview({
    super.key,
    required this.controller,
    required this.onClose,
    this.onNavigate,
  });
  final MarkdrawController controller;
  final VoidCallback onClose;
  final VoidCallback? onNavigate;
  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  static const _rowExtent = 196.0;
  final _scroll = ScrollController();
  final _cache = <String, PageThumbnail>{};
  final _failed = <String>{};
  final _dirtyPages = <String>{};
  final _changedElements = <ElementId, Element>{};
  bool _invalidateAll = false;
  Timer? _timer;
  bool _rendering = false;
  int _generation = 0;
  int _cacheBytes = 0;
  int _columns = 2;
  int _current = 0;
  double _height = 0;
  late Scene _scene;
  late CanvasLayout _layout;
  late ViewportState _viewport;
  late String _background;
  int? _grid;
  MarkdrawController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scene = controller.currentScene;
    _layout = controller.layout;
    _viewport = controller.editorState.viewport;
    _background = controller.canvasBackgroundColor;
    _grid = controller.gridSize;
    _current = controller.pagedViewportMetrics?.currentPageIndex ?? 0;
    _scroll.addListener(_schedule);
    controller.addListener(_onControllerChanged);
    controller.sceneChangeListeners.add(_onSceneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealCurrent();
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    controller.removeListener(_onControllerChanged);
    controller.sceneChangeListeners.remove(_onSceneChanged);
    _scroll.dispose();
    for (final thumbnail in _cache.values) {
      thumbnail.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!identical(controller.currentScene, _scene) &&
        _changedElements.isEmpty &&
        !_invalidateAll) {
      // loadScene/applyScene can notify without a scene-change callback.
      _invalidateAll = true;
      _generation++;
      _schedule();
    }
    final viewport = controller.editorState.viewport;
    final layout = controller.layout;
    final appearanceChanged =
        _background != controller.canvasBackgroundColor ||
        _grid != controller.gridSize;
    if (viewport == _viewport &&
        identical(layout, _layout) &&
        !appearanceChanged) {
      return;
    }
    if (viewport != _viewport) _generation++;
    _viewport = viewport;
    _layout = layout;
    _background = controller.canvasBackgroundColor;
    _grid = controller.gridSize;
    final current = controller.pagedViewportMetrics?.currentPageIndex ?? 0;
    if (appearanceChanged) {
      _generation++;
      _invalidateAll = true;
    }
    if (current != _current || appearanceChanged) {
      setState(() => _current = current);
    }
    _schedule();
  }

  void _onSceneChanged(Scene scene, SceneChangeSource source) {
    final changes = controller.lastChangedElements;
    if (source != SceneChangeSource.userEdit || changes == null) {
      _invalidateAll = true;
    } else {
      for (final element in changes) {
        _changedElements[element.id] = element;
      }
    }
    _generation++;
    _schedule();
  }

  void _flushInvalidation() {
    if (!_invalidateAll && _changedElements.isEmpty) return;
    final dirty = <String>{};
    if (_invalidateAll ||
        _changedElements.values.any(
          (element) => element.isCanvasPage || element is FrameElement,
        )) {
      dirty.addAll(_cache.keys);
    } else {
      // Only cached pages need invalidation. A moved element dirties both ends.
      final old = {
        for (final element in _scene.elements)
          if (_changedElements.containsKey(element.id)) element.id: element,
      };
      final cachedPages = _layout.pages
          .where((page) => _cache.containsKey(page.id))
          .toList();
      for (final element in _changedElements.values) {
        final previous = old[element.id];
        for (final candidate in [element, ?previous]) {
          final bounds = AlignmentUtils.visualBounds(candidate);
          final rect = Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.size.width,
            bounds.size.height,
          ).inflate(math.max(8, candidate.strokeWidth * 2));
          for (final page in cachedPages) {
            if (rect.overlaps(page.bounds)) dirty.add(page.id);
          }
        }
      }
    }
    _scene = controller.currentScene;
    _layout = controller.layout;
    _dirtyPages.addAll(dirty);
    _changedElements.clear();
    _invalidateAll = false;
    _failed.clear();
    setState(() {});
  }

  void _invalidate(Iterable<String> ids) {
    final old = <PageThumbnail>[];
    for (final id in ids) {
      _dirtyPages.remove(id);
      final thumbnail = _cache.remove(id);
      if (thumbnail != null) {
        _cacheBytes -= thumbnail.bytes;
        old.add(thumbnail);
      }
    }
    // RawImage widgets finish this frame before their old handles are released.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final item in old) {
        item.dispose();
      }
    });
  }

  void _schedule() {
    if (!mounted) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _renderNext);
  }

  List<CanvasPage> _wantedPages() {
    if (!_scroll.hasClients) return const [];
    final first = (_scroll.offset / _rowExtent).floor() * _columns;
    final end = first + ((_height / _rowExtent).ceil() + 1) * _columns;
    return _layout.pages.sublist(
      first.clamp(0, _layout.pages.length),
      end.clamp(0, _layout.pages.length),
    );
  }

  Future<void> _renderNext() async {
    if (!mounted || _rendering) return;
    if (controller.pageNavigationBusy ||
        controller.imageCache.hasPendingVisibleImages ||
        (_scroll.hasClients && _scroll.position.isScrollingNotifier.value)) {
      _schedule();
      return;
    }
    _flushInvalidation();
    final wanted = _wantedPages();
    for (final page in wanted) {
      final cached = _cache.remove(page.id);
      if (cached != null) _cache[page.id] = cached;
    }
    final pending = wanted.where(
      (page) =>
          (!_cache.containsKey(page.id) || _dirtyPages.contains(page.id)) &&
          !_failed.contains(page.id),
    );
    if (pending.isEmpty) return;
    final page = pending.first;
    final generation = _generation;
    _rendering = true;
    bool current() =>
        mounted &&
        generation == _generation &&
        !controller.pageNavigationBusy &&
        !controller.imageCache.hasPendingVisibleImages &&
        !(_scroll.hasClients && _scroll.position.isScrollingNotifier.value) &&
        _wantedPages().any((item) => item.id == page.id);
    try {
      final thumbnail = await renderPageThumbnail(
        scene: controller.currentScene,
        layout: _layout,
        page: page,
        background: _background,
        gridSize: _grid,
        shouldContinue: current,
      );
      if (thumbnail == null) return;
      if (!current()) {
        thumbnail.dispose();
        return;
      }
      setState(() {
        _invalidate([page.id]);
        _cache[page.id] = thumbnail;
        _dirtyPages.remove(page.id);
        _cacheBytes += thumbnail.bytes;
        final protected = _wantedPages().map((page) => page.id).toSet();
        while (_cache.length > 32 || _cacheBytes > 16 * 1024 * 1024) {
          final candidates = _cache.keys.where((id) => !protected.contains(id));
          if (candidates.isEmpty) break;
          _invalidate([candidates.first]);
        }
      });
    } catch (_) {
      if (current()) setState(() => _failed.add(page.id));
    } finally {
      _rendering = false;
      if (mounted) _schedule();
    }
  }

  void _revealCurrent() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      ((_current ~/ _columns) * _rowExtent).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
    );
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '页面预览',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                HoverTooltip(
                  message: '定位当前页',
                  child: IconButton(
                    onPressed: _revealCurrent,
                    icon: const Icon(Icons.my_location, size: 20),
                  ),
                ),
                HoverTooltip(
                  message: '关闭预览',
                  child: IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final navigated = await showPageJumpDialog(context, controller);
              if (mounted && navigated) widget.onNavigate?.call();
            },
            child: Text(
              '第 ${_current + 1} / ${_layout.pages.length} 页 · 输入页码跳转',
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _columns = (constraints.maxWidth / 140).floor().clamp(2, 6);
                _height = constraints.maxHeight;
                return NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _schedule();
                    return false;
                  },
                  child: GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    cacheExtent: _rowExtent,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _columns,
                      mainAxisExtent: _rowExtent,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _layout.pages.length,
                    itemBuilder: (context, index) {
                      final page = _layout.pages[index];
                      final thumbnail = _cache[page.id];
                      final selected = index == _current;
                      return Semantics(
                        label: '第 ${index + 1} 页',
                        selected: selected,
                        button: true,
                        child: InkWell(
                          key: ValueKey('page-preview-${page.id}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (controller.navigateToPage(page.id)) {
                              widget.onNavigate?.call();
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? colors.primaryContainer
                                          : colors.surface,
                                      border: Border.all(
                                        color: selected
                                            ? colors.primary
                                            : colors.outlineVariant,
                                        width: selected ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio:
                                            page.bounds.width /
                                            page.bounds.height,
                                        child: thumbnail == null
                                            ? ColoredBox(
                                                color: colors
                                                    .surfaceContainerHighest,
                                                child: Center(
                                                  child: Icon(
                                                    _failed.contains(page.id)
                                                        ? Icons
                                                              .broken_image_outlined
                                                        : Icons
                                                              .description_outlined,
                                                    color: colors.outline,
                                                  ),
                                                ),
                                              )
                                            : LayoutBuilder(
                                                builder: (context, box) => ClipRect(
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      RawImage(
                                                        image: thumbnail.image,
                                                        fit: BoxFit.fill,
                                                      ),
                                                      for (final formula
                                                          in thumbnail
                                                              .mathElements)
                                                        PositionedMathText(
                                                          element: formula,
                                                          viewport: ViewportState(
                                                            offset: page
                                                                .bounds
                                                                .topLeft,
                                                            zoom: math.min(
                                                              box.maxWidth /
                                                                  page
                                                                      .bounds
                                                                      .width,
                                                              box.maxHeight /
                                                                  page
                                                                      .bounds
                                                                      .height,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
