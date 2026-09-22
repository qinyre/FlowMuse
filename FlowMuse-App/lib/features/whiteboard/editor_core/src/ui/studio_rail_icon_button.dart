library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'hover_tooltip.dart';
import 'toolbar_input_diagnostics.dart';

class StudioRailIconButton extends StatefulWidget {
  const StudioRailIconButton({
    super.key,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.emphasized = false,
    this.size = 32,
    this.useFlatBackground = false,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final bool emphasized;
  final double size;
  final bool useFlatBackground;

  @override
  State<StudioRailIconButton> createState() => _StudioRailIconButtonState();
}

class _StudioRailIconButtonState extends State<StudioRailIconButton> {
  static const _diagnosticControlId = 'studio_rail_icon_button';

  /// 触控笔原始指针通道（issue #31 第三轮）。
  ///
  /// 前两轮修复（Tooltip.triggerMode=manual、自绘 HoverTooltip）都保留了
  /// "点击动作要等手势竞技场判决"的结构：InkWell 的 TapGestureRecognizer
  /// 只有在竞技场判它赢、或按压超过 kPressTimeout(100ms) 之后才会派发
  /// tapDown/tap。真机触控笔的事件流由平台引擎产生：引擎在按压期间发出的
  /// PointerCancel，或超过 kTouchSlop 的抖动位移，都会让这一次按压永久失效，
  /// 于是"点一次没用、第一次连高亮都没有、得点好几次"。
  ///
  /// 这条通道只处理触控笔（stylus / invertedStylus）：按下后位移始终不超过
  /// kTouchSlop（与框架 tap 识别器同源）即把抬起或取消结算成一次点选，
  /// 完全绕开竞技场。手指/鼠标仍走 InkWell 原路径（它们的竞技场行为已验证
  /// 可靠），两条路径靠抑制开关去重（见 `_StylusTapArbiter.suppressInkTap`）。
  _StylusTapArbiter? _stylusArbiter;

  @override
  void dispose() {
    _stylusArbiter?.dispose();
    super.dispose();
  }

  bool _isStylusKind(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _onPointerDown(PointerDownEvent event) {
    // 新的一次按压开始：清掉上一次留下的抑制与记录（指针 id 会被引擎复用）。
    _stylusArbiter?.reset();
    if (widget.onPressed == null || !_isStylusKind(event)) return;
    (_stylusArbiter ??= _StylusTapArbiter(
      onActivated: _onStylusTapActivated,
    )).arm(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isStylusKind(event)) return;
    _stylusArbiter?.track(event);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isStylusKind(event)) return;
    _stylusArbiter?.settle(event, stage: 'rawTap');
  }

  /// 取消也必须结算：框架把 cancel 事件从命中缓存里移除（GestureBinding
  /// `_handlePointerEventImmediately`），之后的 PointerUpEvent 因查不到缓存
  /// 而不再派发——真机上引擎若用 cancel 代替 up，这次点选只能在此刻救回。
  void _onPointerCancel(PointerCancelEvent event) {
    if (!_isStylusKind(event)) return;
    _stylusArbiter?.settle(event, stage: 'rawCancelTap');
  }

  void _onStylusTapActivated(String stage) {
    ToolbarInputDiagnostics.recordTap(
      controlId: _diagnosticControlId,
      stage: stage,
    );
    widget.onPressed?.call();
  }

  void _handleInkTap() {
    // InkWell 的 tap 与原始通道是同一个动作的两条路径，先派发者胜。
    if (_stylusArbiter?.suppressInkTap ?? false) {
      ToolbarInputDiagnostics.recordTap(
        controlId: _diagnosticControlId,
        stage: 'inkTapSuppressed',
      );
      return;
    }
    ToolbarInputDiagnostics.recordTap(
      controlId: _diagnosticControlId,
      stage: 'tap',
    );
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = widget.selected
        ? colors.primary
        : colors.onSurfaceVariant;
    final callback = widget.onPressed;
    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: callback != null,
      child: ToolbarInputDiagnosticsTarget(
        controlId: _diagnosticControlId,
        child: HoverTooltip(
          message: widget.tooltip,
          showOnLongPress: callback != null,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                decoration: BoxDecoration(
                  color: widget.emphasized
                      ? (widget.useFlatBackground
                            ? colors.primaryContainer
                            : null)
                      : widget.selected
                      ? colors.primaryContainer
                      : Colors.transparent,
                  gradient: widget.emphasized && !widget.useFlatBackground
                      ? LinearGradient(
                          colors: [
                            colors.primaryContainer,
                            colors.secondaryContainer,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: colors.surfaceContainerHighest,
                  focusColor: colors.surfaceContainerHighest,
                  highlightColor: colors.surfaceContainerHighest,
                  onTapDown: callback == null
                      ? null
                      : (_) => ToolbarInputDiagnostics.recordTap(
                          controlId: _diagnosticControlId,
                          stage: 'tapDown',
                        ),
                  onTapUp: callback == null
                      ? null
                      : (_) => ToolbarInputDiagnostics.recordTap(
                          controlId: _diagnosticControlId,
                          stage: 'tapUp',
                        ),
                  onTapCancel: callback == null
                      ? null
                      : () => ToolbarInputDiagnostics.recordTap(
                          controlId: _diagnosticControlId,
                          stage: 'tapCancel',
                        ),
                  onTap: callback == null ? null : _handleInkTap,
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IconTheme(
                          data: IconThemeData(color: foreground),
                          child: DefaultTextStyle(
                            style: TextStyle(color: foreground),
                            child: widget.child,
                          ),
                        ),
                        if (widget.emphasized)
                          Positioned(
                            bottom: 4,
                            child: Container(
                              width: 14,
                              height: 2,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(99),
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
      ),
    );
  }
}

/// 触控笔点选的原始指针结算：不参与手势竞技场。
///
/// 竞技场里的 tap 只有在判赢之后才派发 tapDown/tap，且按下期间的
/// PointerCancel 或超过 kTouchSlop 的位移都会永久杀死这一次按压。这条通道
/// 只看原始事件：按下之后位移没有越过 kTouchSlop 就把抬起（或取消）结算成
/// 一次点选，容差与框架 tap 识别器同源（kTouchSlop，18 逻辑像素）。
class _StylusTapArbiter {
  _StylusTapArbiter({required this.onActivated});

  final ValueChanged<String> onActivated;

  /// 原始通道派发过动作后，InkWell 的 tap 若也判赢就挡掉，避免同一按压派发两次。
  bool _suppressInkTap = false;
  Timer? _suppressTimer;

  int? _pointer;
  Offset? _downPosition;

  /// 按下后的位移上限：越过 kTouchSlop 即视为拖动而非点选。
  double _maxDrift = 0;

  bool get suppressInkTap => _suppressInkTap;

  void arm(PointerDownEvent event) {
    _pointer = event.pointer;
    _downPosition = event.position;
    _maxDrift = 0;
  }

  void track(PointerEvent event) {
    if (event.pointer != _pointer || _downPosition == null) return;
    final drift = (event.position - _downPosition!).distance;
    if (drift > _maxDrift) _maxDrift = drift;
  }

  void settle(PointerEvent event, {required String stage}) {
    if (event.pointer != _pointer || _downPosition == null) return;
    // 结算事件自己的位置也要计入位移，避免稀疏采样漏掉"按下即拖走"。
    track(event);
    final drift = _maxDrift;
    _clearPress();
    if (drift > kTouchSlop) return;
    _suppressInkTap = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(const Duration(milliseconds: 400), () {
      _suppressInkTap = false;
    });
    onActivated(stage);
  }

  /// 下一次按压开始前复位：上一次的抑制不能挡到新的点选。
  void reset() {
    _clearPress();
    _suppressInkTap = false;
    _suppressTimer?.cancel();
    _suppressTimer = null;
  }

  void _clearPress() {
    _pointer = null;
    _downPosition = null;
    _maxDrift = 0;
  }

  void dispose() {
    _suppressTimer?.cancel();
    _suppressTimer = null;
  }
}

