import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

typedef ToolbarInputDiagnosticSink = void Function(String line);

class ToolbarInputDiagnostics {
  static const bool enabled = bool.fromEnvironment(
    'FLOWMUSE_TOOLBAR_INPUT_DIAGNOSTICS',
    defaultValue: false,
  );

  static ToolbarInputDiagnosticSink? _testSink;

  static bool get isActive => enabled || _testSink != null;

  @visibleForTesting
  static void setTestSink(ToolbarInputDiagnosticSink? sink) {
    _testSink = sink;
  }

  @visibleForTesting
  static void resetTestSink() {
    _testSink = null;
  }

  static void recordPointer({
    required String controlId,
    required String stage,
    required PointerEvent event,
    Offset delta = Offset.zero,
    Duration elapsed = Duration.zero,
  }) {
    if (!isActive) return;
    _emit(
      'control=$controlId source=pointer stage=$stage '
      'pointer=${event.pointer} device=${event.device} kind=${event.kind.name} '
      'buttons=${event.buttons} deltaX=${_format(delta.dx)} '
      'deltaY=${_format(delta.dy)} dtMs=${elapsed.inMilliseconds}',
    );
  }

  static void recordTap({required String controlId, required String stage}) {
    if (!isActive) return;
    _emit('control=$controlId source=gesture stage=$stage');
  }

  static void _emit(String fields) {
    final line = '[FlowMuseCreateNote] toolbar-input $fields';
    final sink = _testSink;
    if (sink != null) {
      sink(line);
    } else {
      debugPrint(line);
    }
  }

  static String _format(double value) => value.toStringAsFixed(1);
}

class ToolbarInputDiagnosticsTarget extends StatefulWidget {
  const ToolbarInputDiagnosticsTarget({
    super.key,
    required this.controlId,
    required this.child,
  });

  final String controlId;
  final Widget child;

  @override
  State<ToolbarInputDiagnosticsTarget> createState() =>
      _ToolbarInputDiagnosticsTargetState();
}

class _ToolbarInputDiagnosticsTargetState
    extends State<ToolbarInputDiagnosticsTarget> {
  final Map<int, _PointerStart> _pointers = {};
  bool _globalRouteRegistered = false;

  @override
  void initState() {
    super.initState();
    _syncGlobalRoute();
  }

  void _syncGlobalRoute() {
    if (ToolbarInputDiagnostics.isActive && !_globalRouteRegistered) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        _onGlobalPointerEvent,
      );
      _globalRouteRegistered = true;
    }
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (!ToolbarInputDiagnostics.isActive || event is! PointerDownEvent) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final localPosition = renderObject.globalToLocal(event.position);
    if (!renderObject.size.contains(localPosition)) return;
    ToolbarInputDiagnostics.recordPointer(
      controlId: widget.controlId,
      stage: 'globalDown',
      event: event,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!ToolbarInputDiagnostics.isActive) return;
    _pointers[event.pointer] = _PointerStart(
      position: event.position,
      timeStamp: event.timeStamp,
    );
    ToolbarInputDiagnostics.recordPointer(
      controlId: widget.controlId,
      stage: 'down',
      event: event,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    _finishPointer(event, 'up');
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishPointer(event, 'cancel');
  }

  void _finishPointer(PointerEvent event, String stage) {
    if (!ToolbarInputDiagnostics.isActive) return;
    final start = _pointers.remove(event.pointer);
    final delta = start == null ? Offset.zero : event.position - start.position;
    final elapsed = start == null
        ? Duration.zero
        : event.timeStamp - start.timeStamp;
    ToolbarInputDiagnostics.recordPointer(
      controlId: widget.controlId,
      stage: stage,
      event: event,
      delta: delta,
      elapsed: elapsed,
    );
  }

  @override
  void dispose() {
    if (_globalRouteRegistered) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _onGlobalPointerEvent,
      );
      _globalRouteRegistered = false;
    }
    _pointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}

class _PointerStart {
  const _PointerStart({required this.position, required this.timeStamp});

  final Offset position;
  final Duration timeStamp;
}
