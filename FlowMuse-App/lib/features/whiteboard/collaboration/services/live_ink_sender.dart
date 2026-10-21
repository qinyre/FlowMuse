import 'dart:async';
import 'dart:math' as math;

import '../models/live_ink_chunk.dart';

typedef LiveInkChunkEmitter = Future<bool> Function(LiveInkChunk chunk);

class LiveInkSender {
  LiveInkSender({required LiveInkChunkEmitter emit}) : _emit = emit;

  final LiveInkChunkEmitter _emit;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _retryTimer;
  static const _maxCandidateAge = Duration(milliseconds: 250);

  String? _strokeId;
  LiveInkStyle? _style;
  int _lastSentIndex = 0;
  final List<int> _recentCycleStarts = [];
  _LiveInkCandidate? _pending;
  bool _inFlight = false;
  bool _closing = false;
  int _generation = 0;
  int errorCount = 0;
  int emittedChunks = 0;
  int notWritableCount = 0;

  bool get active => _strokeId != null;
  String? get strokeId => _strokeId;
  bool get inFlight => _inFlight;
  bool get hasPending => _pending != null;

  void start({required String strokeId, required LiveInkStyle style}) {
    cancel();
    _strokeId = strokeId;
    _style = style;
  }

  void offer(List<LiveInkPoint> points) {
    _offerWhole(points, closing: false);
  }

  void finish(List<LiveInkPoint> points) {
    _offerWhole(points, closing: true);
  }

  void offerTail({
    required int totalCount,
    required int startIndex,
    required List<LiveInkPoint> points,
  }) {
    _offerTail(
      totalCount: totalCount,
      startIndex: startIndex,
      points: points,
      closing: false,
    );
  }

  void finishTail({
    required int totalCount,
    required int startIndex,
    required List<LiveInkPoint> points,
  }) {
    _offerTail(
      totalCount: totalCount,
      startIndex: startIndex,
      points: points,
      closing: true,
    );
  }

  void cancel() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _generation++;
    _strokeId = null;
    _style = null;
    _lastSentIndex = 0;
    _recentCycleStarts.clear();
    _pending = null;
    _inFlight = false;
    _closing = false;
  }

  void _offerWhole(List<LiveInkPoint> points, {required bool closing}) {
    final startIndex = math.max(0, points.length - LiveInkChunk.maxPoints);
    _offerTail(
      totalCount: points.length,
      startIndex: startIndex,
      points: points.skip(startIndex).toList(growable: false),
      closing: closing,
    );
  }

  void _offerTail({
    required int totalCount,
    required int startIndex,
    required List<LiveInkPoint> points,
    required bool closing,
  }) {
    if (!active) return;
    if (startIndex < 0 ||
        totalCount < startIndex ||
        startIndex + points.length != totalCount ||
        points.length > LiveInkChunk.maxPoints) {
      throw ArgumentError('Invalid live ink tail');
    }
    _closing = _closing || closing;
    if (totalCount > _lastSentIndex) {
      _pending = _LiveInkCandidate(
        totalCount: totalCount,
        tailStart: startIndex,
        tail: List<LiveInkPoint>.unmodifiable(points),
        createdAtMicros: _clock.elapsedMicroseconds,
      );
    }
    _drain();
  }

  void _drain() {
    if (_inFlight || _retryTimer != null) return;
    final candidate = _pending;
    final strokeId = _strokeId;
    final style = _style;
    if (candidate == null || strokeId == null || style == null) {
      if (_closing) cancel();
      return;
    }
    _pending = null;
    if (candidate.totalCount <= _lastSentIndex) {
      if (_closing) cancel();
      return;
    }
    if (_clock.elapsedMicroseconds - candidate.createdAtMicros >
        _maxCandidateAge.inMicroseconds) {
      if (_closing) cancel();
      return;
    }

    final cycleStart = _lastSentIndex;
    final requestedStart = _recentCycleStarts.fold(cycleStart, math.min);
    final startIndex = math.max(candidate.tailStart, requestedStart);
    final offset = startIndex - candidate.tailStart;
    final chunk = LiveInkChunk(
      strokeId: strokeId,
      startIndex: startIndex,
      points: List<LiveInkPoint>.unmodifiable(candidate.tail.skip(offset)),
      style: style,
    );

    _inFlight = true;
    final generation = _generation;
    Future<void>.microtask(() async {
      if (generation != _generation) return;
      var emitted = false;
      try {
        emitted = await _emit(chunk);
      } catch (_) {
        errorCount++;
      }
      if (generation != _generation) return;
      _inFlight = false;
      if (emitted) {
        emittedChunks++;
        _lastSentIndex = candidate.totalCount;
        _recentCycleStarts.add(cycleStart);
        if (_recentCycleStarts.length > 2) _recentCycleStarts.removeAt(0);
      } else {
        notWritableCount++;
        _pending ??= candidate;
        _retryTimer = Timer(const Duration(milliseconds: 50), () {
          _retryTimer = null;
          _drain();
        });
      }
      _drain();
    });
  }
}

class _LiveInkCandidate {
  const _LiveInkCandidate({
    required this.totalCount,
    required this.tailStart,
    required this.tail,
    required this.createdAtMicros,
  });

  final int totalCount;
  final int tailStart;
  final List<LiveInkPoint> tail;
  final int createdAtMicros;
}
