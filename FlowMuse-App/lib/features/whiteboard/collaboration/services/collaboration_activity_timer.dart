import 'dart:async';

/// Keeps one deadline timer instead of canceling/recreating timers per pen point.
class CollaborationActivityTimer {
  CollaborationActivityTimer(this.onStateChanged, {this.elapsed});

  final void Function(String state) onStateChanged;
  final Duration Function()? elapsed;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  Duration _lastActivity = Duration.zero;
  String? _state;

  Duration get _now => elapsed?.call() ?? _clock.elapsed;

  void markActive() {
    _lastActivity = _now;
    if (_state != 'active') {
      _state = 'active';
      onStateChanged('active');
      _timer?.cancel();
      _timer = null;
    }
    _timer ??= Timer(const Duration(minutes: 1), _check);
  }

  void _check() {
    _timer = null;
    final inactive = _now - _lastActivity;
    if (inactive >= const Duration(minutes: 5)) {
      _state = 'away';
      onStateChanged('away');
    } else if (inactive >= const Duration(minutes: 1)) {
      _state = 'idle';
      onStateChanged('idle');
      _timer = Timer(const Duration(minutes: 5) - inactive, _check);
    } else {
      _timer = Timer(const Duration(minutes: 1) - inactive, _check);
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _state = null;
  }
}
