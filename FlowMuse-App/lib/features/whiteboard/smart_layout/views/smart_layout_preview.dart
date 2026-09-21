import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show Bounds, FlowMuseElementData, Scene, ViewportState;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'package:flow_muse/shared/widgets/app_spacing.dart';

import '../rendering/draft_scene_renderer.dart';
import '../session/smart_layout_session_view_model.dart';
import '../validation/validated_candidate.dart';

/// 仅持有对照/缩放状态与原稿位图。原稿来自同轮不可变捕获，绝不读当前画布。
class SmartLayoutPreview extends StatefulWidget {
  const SmartLayoutPreview({super.key, required this.candidate, this.context});

  final ValidatedCandidate? candidate;
  final SmartLayoutReviewContext? context;

  @override
  State<SmartLayoutPreview> createState() => _SmartLayoutPreviewState();
}

class _SmartLayoutPreviewState extends State<SmartLayoutPreview> {
  final _renderer = DraftSceneRenderer();
  var _transform = TransformationController();
  DraftRenderSnapshot? _original;
  int _renderGeneration = 0;
  String _mode = 'result';
  String? _renderError;
  Size _viewSize = Size.zero;
  Object? _fitKey;
  ViewportState _contentView = const ViewportState();
  double _maxScale = 6;

  @override
  void initState() {
    super.initState();
    _renderOriginal();
  }

  @override
  void didUpdateWidget(SmartLayoutPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.context?.originalScene,
          widget.context?.originalScene,
        ) ||
        oldWidget.context?.pageBounds != widget.context?.pageBounds) {
      _original?.dispose();
      _original = null;
      _renderOriginal();
    }
  }

  Future<void> _renderOriginal() async {
    final generation = ++_renderGeneration;
    final context = widget.context;
    if (context == null) return;
    final bounds = context.pageBounds;
    // 原稿最长边 2048px；候选已是整页真实渲染图，不重新识别、不渲染缩略图。
    final scale = math.min(
      1.0,
      2048 / math.max(bounds.size.width, bounds.size.height),
    );
    try {
      final snapshot = await _renderer.render(
        scene: context.originalScene,
        viewport: ViewportState(
          offset: Offset(bounds.left, bounds.top),
          zoom: scale,
        ),
        pixelSize: Size(bounds.size.width * scale, bounds.size.height * scale),
      );
      if (!mounted || generation != _renderGeneration) {
        snapshot.dispose();
        return;
      }
      setState(() {
        _original = snapshot;
        _renderError = null;
      });
    } on DraftRenderCancelled {
      // 关闭或新捕获已接管；不发布旧图。
    } catch (_) {
      if (mounted && generation == _renderGeneration) {
        setState(() => _renderError = '原稿预览暂不可用，排版结果仍可查看');
      }
    }
  }

  @override
  void dispose() {
    _renderGeneration++;
    _renderer.dispose();
    _original?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    if (_viewSize.isEmpty) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final view = ViewportState(
      offset: Offset(-matrix.storage[12] / scale, -matrix.storage[13] / scale),
      zoom: scale,
    );
    _showView(
      view.zoomAt(
        factor,
        _viewSize.center(Offset.zero),
        minZoom: 1,
        maxZoom: _maxScale,
      ),
    );
  }

  void _showView(ViewportState view) {
    final matrix = Matrix4.diagonal3Values(view.zoom, view.zoom, 1)
      ..setTranslationRaw(
        -view.offset.dx * view.zoom,
        -view.offset.dy * view.zoom,
        0,
      );
    final previous = _transform;
    // 重建查看器以结束旧惯性动画，否则它会用旧平移量覆盖新的缩放/定位。
    setState(() => _transform = TransformationController(matrix));
    runAfterUiFrame(previous.dispose);
  }

  /// 对齐 RawImage 的 contain 留白，再把真实墨迹边界映射到预览坐标。
  Rect? _contentRect(DraftRenderSnapshot snapshot, Scene scene, Size size) {
    final backgrounds = {
      for (final element in scene.activeElements)
        if (element.isCanvasPage || element.isPdfBackground) element.id.value,
    };
    final imageSize = Size(
      snapshot.image.width.toDouble(),
      snapshot.image.height.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final imageScale = destination.width / imageSize.width;
    Rect? result;
    for (final layer in snapshot.layers) {
      if (backgrounds.contains(layer.elementId)) continue;
      final bounds = layer.bounds;
      final pixels = Rect.fromPoints(
        snapshot.viewport.sceneToScreen(Offset(bounds.left, bounds.top)),
        snapshot.viewport.sceneToScreen(Offset(bounds.right, bounds.bottom)),
      ).intersect(Offset.zero & imageSize);
      if (!pixels.isFinite || pixels.isEmpty) continue;
      final rect = Rect.fromLTWH(
        destination.left + pixels.left * imageScale,
        destination.top + pixels.top * imageScale,
        pixels.width * imageScale,
        pixels.height * imageScale,
      );
      result = result?.expandToInclude(rect) ?? rect;
    }
    return result;
  }

  void _configureView(Size size, String mode) {
    final before = mode == 'result' ? null : _original;
    final key = (widget.candidate?.snapshot, before, size, mode);
    if (key == _fitKey || size.isEmpty) return;
    _fitKey = key;
    _viewSize = size;
    Rect? content;
    if (before != null) {
      content = _contentRect(before, widget.context!.originalScene, size);
    }
    if ((mode != 'original' || before == null) && widget.candidate != null) {
      final after = _contentRect(
        widget.candidate!.snapshot,
        widget.candidate!.reduced.scene,
        size,
      );
      if (after != null) content = content?.expandToInclude(after) ?? after;
    }
    _contentView = const ViewportState();
    if (content != null) {
      final fitted = const ViewportState().fitToBounds(
        Bounds.fromLTWH(
          content.left,
          content.top,
          content.width,
          content.height,
        ),
        size,
        padding: AppSpacing.sectionGap,
      );
      // 默认最多放到场景的 2 倍，短句可读但不撑成满屏巨字；手动仍可继续放大。
      final snapshot = before ?? widget.candidate!.snapshot;
      final imageScale = math.min(
        size.width / snapshot.image.width,
        size.height / snapshot.image.height,
      );
      final zoom = fitted.zoom
          .clamp(1.0, math.max(1.0, 2 / (imageScale * snapshot.viewport.zoom)))
          .toDouble();
      _contentView = ViewportState(
        offset: content.center - size.center(Offset.zero) / zoom,
        zoom: zoom,
      );
    }
    _maxScale = math.max(6, _contentView.zoom * 3);
    // LayoutBuilder 中不能通知已构建的 InteractiveViewer；过期布局不得抢回视角。
    runAfterUiFrame(() {
      if (mounted && key == _fitKey) _showView(_contentView);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final mode = widget.candidate == null
          ? 'original'
          : _mode == 'compare' && !wide
          ? 'result'
          : _mode;
      final before = _original;
      Widget pane(DraftRenderSnapshot snapshot, String label) => Expanded(
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, paneConstraints) {
                  _configureView(paneConstraints.biggest, mode);
                  return ClipRect(
                    child: InteractiveViewer(
                      key: ObjectKey(_transform),
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: _maxScale,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: SizedBox.expand(
                        child: ColoredBox(
                          color: Colors.white,
                          child: Semantics(
                            label: label,
                            image: true,
                            child: RawImage(
                              image: snapshot.image,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  if (widget.candidate != null)
                    ChoiceChip(
                      label: const Text('排版结果'),
                      selected: mode == 'result',
                      onSelected: (_) => setState(() => _mode = 'result'),
                    ),
                  if (widget.context != null)
                    ChoiceChip(
                      label: const Text('原稿'),
                      selected: mode == 'original',
                      onSelected: before == null
                          ? null
                          : (_) => setState(() => _mode = 'original'),
                    ),
                  if (wide &&
                      widget.context != null &&
                      widget.candidate != null)
                    ChoiceChip(
                      label: const Text('并排对照'),
                      selected: mode == 'compare',
                      onSelected: before == null
                          ? null
                          : (_) => setState(() => _mode = 'compare'),
                    ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: '缩小预览',
                    onPressed: () => _zoom(1 / 1.5),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: '放大预览',
                    onPressed: () => _zoom(1.5),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  TextButton.icon(
                    onPressed: () => _showView(_contentView),
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('回到内容'),
                  ),
                  Tooltip(
                    message: '适合页面',
                    child: TextButton.icon(
                      onPressed: () => _showView(const ViewportState()),
                      icon: const Icon(Icons.fit_screen),
                      label: const Text('查看整页'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_renderError != null) Text(_renderError!),
          if (widget.context != null && before == null && _renderError == null)
            const Text('正在准备原稿对照…'),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * .42).clamp(
              180.0,
              440.0,
            ),
            child: Row(
              children: [
                if ((mode == 'original' || mode == 'compare') && before != null)
                  pane(before, '分析时的原稿'),
                if (mode == 'compare') const SizedBox(width: 12),
                if ((mode != 'original' || before == null) &&
                    widget.candidate != null)
                  pane(widget.candidate!.snapshot, '所选排版预览'),
              ],
            ),
          ),
          const Text('拖动或双指缩放查看；应用前不会修改笔记。', textAlign: TextAlign.center),
        ],
      );
    },
  );
}
