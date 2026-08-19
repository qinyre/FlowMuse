import 'package:flutter/foundation.dart';

enum ActivePreviewTerminalReason {
  pointerUp,
  cancel,
  toolSwitch,
  viewportGesture,
  dispose,
}

@immutable
class ActivePreviewPaintMarker {
  const ActivePreviewPaintMarker({
    required this.strokeEpoch,
    required this.maxInputSeq,
  });

  final int strokeEpoch;
  final int maxInputSeq;

  @override
  bool operator ==(Object other) =>
      other is ActivePreviewPaintMarker &&
      other.strokeEpoch == strokeEpoch &&
      other.maxInputSeq == maxInputSeq;

  @override
  int get hashCode => Object.hash(strokeEpoch, maxInputSeq);
}

@immutable
class ActivePreviewSample {
  const ActivePreviewSample({
    required this.strokeEpoch,
    required this.inputSeq,
    required this.acceptedMicros,
    this.paintedMicros,
    this.frameNumber,
    this.terminalReason,
  });

  final int strokeEpoch;
  final int inputSeq;
  final int acceptedMicros;
  final int? paintedMicros;
  final int? frameNumber;
  final ActivePreviewTerminalReason? terminalReason;

  bool get painted => paintedMicros != null;
  bool get terminalBeforePreview => !painted && terminalReason != null;
  int? get eventToPaintMicros =>
      paintedMicros == null ? null : paintedMicros! - acceptedMicros;

  ActivePreviewSample paintedAt({
    required int micros,
    required int frameNumber,
  }) {
    return ActivePreviewSample(
      strokeEpoch: strokeEpoch,
      inputSeq: inputSeq,
      acceptedMicros: acceptedMicros,
      paintedMicros: micros,
      frameNumber: frameNumber,
    );
  }

  ActivePreviewSample terminated(ActivePreviewTerminalReason reason) {
    return ActivePreviewSample(
      strokeEpoch: strokeEpoch,
      inputSeq: inputSeq,
      acceptedMicros: acceptedMicros,
      terminalReason: reason,
    );
  }
}

/// Test/profile-only side-channel for accepted-point-to-preview-paint timing.
///
/// Production controllers keep this null, so the input hot path only performs
/// a nullable check and no samples are allocated.
class ActivePreviewMetricsProbe {
  ActivePreviewMetricsProbe({int Function()? nowMicros})
    : _providedClock = nowMicros,
      _stopwatch = nowMicros == null ? (Stopwatch()..start()) : null;

  final int Function()? _providedClock;
  final Stopwatch? _stopwatch;
  final List<ActivePreviewSample> _samples = [];
  final Map<int, int> _lastPaintedSeqByEpoch = {};
  final Map<int, int> _nextUnpaintedIndexByEpoch = {};
  final Map<String, int> _rejectedRawSamples = {};
  int _nextStrokeEpoch = 0;
  int _nextInputSeq = 0;

  List<ActivePreviewSample> get samples => List.unmodifiable(_samples);
  Map<String, int> get rejectedRawSamples =>
      Map.unmodifiable(_rejectedRawSamples);

  int startStroke() {
    final strokeEpoch = ++_nextStrokeEpoch;
    _nextUnpaintedIndexByEpoch[strokeEpoch] = _samples.length;
    return strokeEpoch;
  }

  int recordAcceptedPoint(int strokeEpoch) {
    final inputSeq = ++_nextInputSeq;
    _samples.add(
      ActivePreviewSample(
        strokeEpoch: strokeEpoch,
        inputSeq: inputSeq,
        acceptedMicros: _nowMicros(),
      ),
    );
    return inputSeq;
  }

  void recordRejectedRawSample(String reason) {
    _rejectedRawSamples.update(reason, (value) => value + 1, ifAbsent: () => 1);
  }

  void recordPaintedThrough({
    required ActivePreviewPaintMarker marker,
    required int frameNumber,
  }) {
    final lastPainted = _lastPaintedSeqByEpoch[marker.strokeEpoch] ?? 0;
    if (marker.maxInputSeq <= lastPainted) return;
    final paintedMicros = _nowMicros();
    final firstUnpainted = _nextUnpaintedIndexByEpoch[marker.strokeEpoch];
    if (firstUnpainted == null) return;
    var index = firstUnpainted;
    for (; index < _samples.length; index++) {
      final sample = _samples[index];
      if (sample.strokeEpoch != marker.strokeEpoch ||
          sample.inputSeq > marker.maxInputSeq) {
        break;
      }
      if (sample.inputSeq <= lastPainted ||
          sample.painted ||
          sample.terminalReason != null) {
        continue;
      }
      _samples[index] = sample.paintedAt(
        micros: paintedMicros,
        frameNumber: frameNumber,
      );
    }
    _nextUnpaintedIndexByEpoch[marker.strokeEpoch] = index;
    _lastPaintedSeqByEpoch[marker.strokeEpoch] = marker.maxInputSeq;
  }

  void finishStroke(int strokeEpoch, ActivePreviewTerminalReason reason) {
    final firstUnpainted = _nextUnpaintedIndexByEpoch[strokeEpoch];
    if (firstUnpainted == null) return;
    for (var index = firstUnpainted; index < _samples.length; index++) {
      final sample = _samples[index];
      if (sample.strokeEpoch != strokeEpoch) break;
      if (!sample.painted && sample.terminalReason == null) {
        _samples[index] = sample.terminated(reason);
      }
    }
    _lastPaintedSeqByEpoch.remove(strokeEpoch);
    _nextUnpaintedIndexByEpoch.remove(strokeEpoch);
  }

  int _nowMicros() => _providedClock?.call() ?? _stopwatch!.elapsedMicroseconds;
}
