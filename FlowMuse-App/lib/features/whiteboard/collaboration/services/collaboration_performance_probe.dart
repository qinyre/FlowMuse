enum CollaborationPerformanceStage {
  jsonEncode,
  encrypt,
  transportSend,
  reliableQueueWait,
  decrypt,
  jsonDecode,
  reconcile,
}

class CollaborationPerformanceSample {
  const CollaborationPerformanceSample({
    required this.stage,
    required this.durationMicros,
    required this.itemCount,
    required this.byteCount,
  });

  final CollaborationPerformanceStage stage;
  final int durationMicros;
  final int itemCount;
  final int byteCount;
}

/// 仅由性能 runner 注入；默认 null 时不会分配样本或启动计时器。
class CollaborationPerformanceProbe {
  CollaborationPerformanceProbe({int Function()? nowMicros})
    : _providedClock = nowMicros,
      _stopwatch = nowMicros == null ? (Stopwatch()..start()) : null;

  final int Function()? _providedClock;
  final Stopwatch? _stopwatch;
  final List<CollaborationPerformanceSample> _samples = [];

  List<CollaborationPerformanceSample> get samples =>
      List.unmodifiable(_samples);

  int nowMicros() => _providedClock?.call() ?? _stopwatch!.elapsedMicroseconds;

  void recordSince(
    CollaborationPerformanceStage stage,
    int startedMicros, {
    int itemCount = 0,
    int byteCount = 0,
  }) {
    _samples.add(
      CollaborationPerformanceSample(
        stage: stage,
        durationMicros: nowMicros() - startedMicros,
        itemCount: itemCount,
        byteCount: byteCount,
      ),
    );
  }

  void clear() => _samples.clear();
}
