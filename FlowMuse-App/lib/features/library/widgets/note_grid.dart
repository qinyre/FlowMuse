import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../shared/widgets/app_motion.dart';
import 'note_card.dart';

/// Keeps lazy note tiles moving continuously when the responsive column count changes.
class NoteGrid extends StatefulWidget {
  const NoteGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.compact,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool? compact;

  @override
  State<NoteGrid> createState() => _NoteGridState();
}

class _NoteGridState extends State<NoteGrid>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this, value: 1);
  late var _children = _buildChildren();
  SliverGridDelegate? _from;
  SliverGridDelegateWithFixedCrossAxisCount? _target;
  Size? _windowSize;
  bool _windowResized = false;

  SliverChildBuilderDelegate _buildChildren() => SliverChildBuilderDelegate(
    widget.itemBuilder,
    childCount: widget.itemCount,
  );

  SliverGridDelegate get _current => _animation.value == 1
      ? _target!
      : _ReflowDelegate(
          _from!,
          _target!,
          Curves.easeOutCubic.transform(_animation.value),
        );

  @override
  void didUpdateWidget(covariant NoteGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemBuilder != widget.itemBuilder ||
        oldWidget.itemCount != widget.itemCount) {
      _children = _buildChildren();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final height = NoteCard.gridHeight(context);
    final windowSize = MediaQuery.sizeOf(context);
    _windowResized |= _windowSize != null && _windowSize != windowSize;
    _windowSize = windowSize;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = widget.compact ?? constraints.maxWidth < 820;
        final gap = compact
            ? NoteCard.compactGridCrossGap
            : NoteCard.gridCrossGap;
        final target = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: math.max(
            1,
            (constraints.maxWidth / (NoteCard.gridMaxCrossAxisExtent + gap))
                .ceil(),
          ),
          mainAxisExtent: height,
          crossAxisSpacing: gap,
          mainAxisSpacing: compact
              ? NoteCard.compactGridMainGap
              : NoteCard.gridMainGap,
        );
        final changedHeight =
            _target != null && _target!.mainAxisExtent != height;
        if (_target == null) {
          _target = target;
        } else if (target.shouldRelayout(_target!)) {
          _from = _current;
          _target = target;
          if (duration != Duration.zero && !_windowResized && !changedHeight) {
            _animation.duration = duration;
            _animation.forward(from: 0);
          }
        }
        // Window/font changes must not squeeze content into the previous layout.
        if (duration == Duration.zero || _windowResized || changedHeight) {
          _animation.stop();
          _animation.value = 1;
        }
        _windowResized = false;
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, _) => GridView.custom(
            gridDelegate: _current,
            childrenDelegate: _children,
          ),
        );
      },
    );
  }
}

class _ReflowDelegate extends SliverGridDelegate {
  const _ReflowDelegate(this.from, this.to, this.progress);

  final SliverGridDelegate from;
  final SliverGridDelegate to;
  final double progress;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => progress == 0
      ? from.getLayout(constraints)
      : _ReflowLayout(
          from.getLayout(constraints),
          to.getLayout(constraints),
          progress,
        );

  @override
  bool shouldRelayout(covariant _ReflowDelegate oldDelegate) =>
      from != oldDelegate.from ||
      to != oldDelegate.to ||
      progress != oldDelegate.progress;
}

class _ReflowLayout extends SliverGridLayout {
  const _ReflowLayout(this.from, this.to, this.progress);

  final SliverGridLayout from;
  final SliverGridLayout to;
  final double progress;

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final a = from.getGeometryForChildIndex(index);
    final b = to.getGeometryForChildIndex(index);
    return SliverGridGeometry(
      scrollOffset: lerpDouble(a.scrollOffset, b.scrollOffset, progress)!,
      crossAxisOffset: lerpDouble(
        a.crossAxisOffset,
        b.crossAxisOffset,
        progress,
      )!,
      mainAxisExtent: lerpDouble(a.mainAxisExtent, b.mainAxisExtent, progress)!,
      crossAxisExtent: lerpDouble(
        a.crossAxisExtent,
        b.crossAxisExtent,
        progress,
      )!,
    );
  }

  // Interpolated rows stay ordered; binary search avoids building the union
  // of both layouts when a large notebook is scrolled far down.
  int _firstIndex(double offset, {required bool trailing}) {
    var low = 0;
    var high =
        math.max(
          from.getMaxChildIndexForScrollOffset(offset),
          to.getMaxChildIndexForScrollOffset(offset),
        ) +
        1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final geometry = getGeometryForChildIndex(mid);
      final before = trailing
          ? geometry.trailingScrollOffset <= offset
          : geometry.scrollOffset < offset;
      if (before) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      scrollOffset <= 0 ? 0 : _firstIndex(scrollOffset, trailing: true);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      math.max(0, _firstIndex(scrollOffset, trailing: false) - 1);

  @override
  double computeMaxScrollOffset(int childCount) => lerpDouble(
    from.computeMaxScrollOffset(childCount),
    to.computeMaxScrollOffset(childCount),
    progress,
  )!;
}
