import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show ViewportState;

import '../rendering/draft_scene_renderer.dart';
import '../session/smart_layout_session_view_model.dart';
import '../validation/validated_candidate.dart';

/// 仅持有对照/缩放状态与原稿位图。原稿来自同轮不可变捕获，绝不读当前画布。
class SmartLayoutPreview extends StatefulWidget {
  const SmartLayoutPreview({super.key, required this.candidate, this.context});

  final ValidatedCandidate candidate;
  final SmartLayoutReviewContext? context;

  @override
  State<SmartLayoutPreview> createState() => _SmartLayoutPreviewState();
}

class _SmartLayoutPreviewState extends State<SmartLayoutPreview> {
  final _renderer = DraftSceneRenderer();
  final _transform = TransformationController();
  DraftRenderSnapshot? _original;
  int _renderGeneration = 0;
  String _mode = 'result';
  String? _renderError;

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
      _transform.value = Matrix4.identity();
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
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      6.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final mode = _mode == 'compare' && !wide ? 'result' : _mode;
      final before = _original;
      Widget pane(DraftRenderSnapshot snapshot, String label) => Expanded(
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 6,
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
                  if (wide && widget.context != null)
                    ChoiceChip(
                      label: const Text('并排对照'),
                      selected: mode == 'compare',
                      onSelected: before == null
                          ? null
                          : (_) => setState(() => _mode = 'compare'),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
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
                  IconButton(
                    tooltip: '适合页面',
                    onPressed: () => _transform.value = Matrix4.identity(),
                    icon: const Icon(Icons.fit_screen),
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
                if (mode != 'original' || before == null)
                  pane(widget.candidate.snapshot, '所选排版预览'),
              ],
            ),
          ),
          const Text('拖动或双指缩放查看；应用前不会修改笔记。', textAlign: TextAlign.center),
        ],
      );
    },
  );
}
