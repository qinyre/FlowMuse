import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/live_ink_chunk.dart';
import 'live_ink_receive_scheduler.dart';

enum RemoteWetInkDropReason {
  finalized('finalized'),
  senderLimit('sender_limit'),
  strokeLimit('stroke_limit'),
  strokePointLimit('stroke_point_limit'),
  roomPointLimit('room_point_limit'),
  renderCacheLimit('render_cache_limit'),
  invalidChunk('invalid_chunk');

  const RemoteWetInkDropReason(this.code);
  final String code;
}

class RemoteWetInkApplyResult {
  const RemoteWetInkApplyResult.accepted(this.addedPoints) : reason = null;
  const RemoteWetInkApplyResult.dropped(this.reason) : addedPoints = 0;

  final int addedPoints;
  final RemoteWetInkDropReason? reason;
  bool get accepted => reason == null;
}

@immutable
class RemoteWetInkSegment {
  const RemoteWetInkSegment(this.points);

  final List<LiveInkPoint> points;
}

@immutable
class RemoteWetInkStrokeSnapshot {
  const RemoteWetInkStrokeSnapshot({
    required this.senderSocketId,
    required this.strokeId,
    required this.style,
    required this.consolidatedSegments,
    required this.incrementalSegments,
    required this.tailSegments,
    required this.pointCount,
    required this.revision,
  });

  final String senderSocketId;
  final String strokeId;
  final LiveInkStyle style;
  final List<RemoteWetInkSegment> consolidatedSegments;
  final List<RemoteWetInkSegment> incrementalSegments;
  final List<RemoteWetInkSegment> tailSegments;
  final int pointCount;
  final int revision;

  int get layerCount =>
      (consolidatedSegments.isEmpty ? 0 : 1) +
      incrementalSegments.length +
      (tailSegments.isEmpty ? 0 : 1);
}

class RemoteWetInkStore extends ChangeNotifier {
  RemoteWetInkStore({
    int Function()? nowMs,
    this.inactivityTtl = const Duration(seconds: 5),
    this.completedCacheTtl = const Duration(seconds: 10),
    bool autoCleanup = true,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (autoCleanup) {
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => cleanup(),
      );
    }
  }

  static const int maxSenders = 8;
  static const int maxStrokes = 64;
  static const int maxPointsPerStroke = 16384;
  static const int maxPointsPerRoom = 65536;
  static const int maxIncrementalSegments = 8;
  static const int maxEstimatedRenderBytes = 16 * 1024 * 1024;
  static const int _estimatedBytesPerPoint = 48;
  static const int _estimatedBytesPerSegment = 128;

  final int Function() _nowMs;
  final Duration inactivityTtl;
  final Duration completedCacheTtl;
  final Map<String, int> _senderLastActiveMs = {};
  final Map<String, _RemoteWetInkStroke> _strokes = {};
  final Set<String> _finalizedStrokeIds = {};
  final Map<String, int> _completedUntilMs = {};
  final Map<RemoteWetInkDropReason, int> _dropCounts = {};
  Timer? _cleanupTimer;
  int _roomPointCount = 0;
  int _revision = 0;

  int get roomPointCount => _roomPointCount;
  int get senderCount => _senderLastActiveMs.length;
  int get strokeCount => _strokes.length;
  int get revision => _revision;
  int get finalizedStrokeCount => _finalizedStrokeIds.length;
  int get completedCacheCount => _completedUntilMs.length;
  int dropCount(RemoteWetInkDropReason reason) => _dropCounts[reason] ?? 0;

  List<RemoteWetInkStrokeSnapshot> get strokes =>
      List.unmodifiable(_strokes.values.map((stroke) => stroke.snapshot));

  bool isFinalized(String strokeId) => _finalizedStrokeIds.contains(strokeId);

  void seedFinalizedStrokeIds(Iterable<String> strokeIds) {
    _finalizedStrokeIds.addAll(strokeIds);
  }

  RemoteWetInkApplyResult apply(DecodedLiveInkChunk decoded) {
    final now = _nowMs();
    cleanup(nowMs: now);
    final sender = decoded.senderSocketId;
    final chunk = decoded.chunk;
    if (_finalizedStrokeIds.contains(chunk.strokeId) ||
        (_completedUntilMs[chunk.strokeId] ?? 0) > now) {
      return _drop(RemoteWetInkDropReason.finalized);
    }
    if (!_validChunkBounds(chunk)) {
      return _drop(RemoteWetInkDropReason.strokePointLimit);
    }

    final existing = _strokes[chunk.strokeId];
    if (existing != null &&
        (existing.senderSocketId != sender ||
            !_sameStyle(existing.style, chunk.style))) {
      return _drop(RemoteWetInkDropReason.invalidChunk);
    }
    if (!_senderLastActiveMs.containsKey(sender) &&
        _senderLastActiveMs.length >= maxSenders) {
      return _drop(RemoteWetInkDropReason.senderLimit);
    }
    if (existing == null && _strokes.length >= maxStrokes) {
      return _drop(RemoteWetInkDropReason.strokeLimit);
    }

    final newPoints = <int, LiveInkPoint>{};
    for (final indexed in chunk.indexedPoints) {
      if (!(existing?.containsIndex(indexed.index) ?? false)) {
        newPoints[indexed.index] = indexed.point;
      }
    }
    if ((existing?.pointCount ?? 0) + newPoints.length > maxPointsPerStroke) {
      return _drop(RemoteWetInkDropReason.strokePointLimit);
    }
    if (_roomPointCount + newPoints.length > maxPointsPerRoom) {
      return _drop(RemoteWetInkDropReason.roomPointLimit);
    }
    final estimatedSegments =
        _estimatedSegmentCount + newPoints.length + _strokes.length + 1;
    final estimatedBytes =
        (_roomPointCount + newPoints.length) * _estimatedBytesPerPoint +
        estimatedSegments * _estimatedBytesPerSegment;
    if (estimatedBytes > maxEstimatedRenderBytes) {
      return _drop(RemoteWetInkDropReason.renderCacheLimit);
    }

    _senderLastActiveMs[sender] = now;
    final stroke =
        existing ??
        (_strokes[chunk.strokeId] = _RemoteWetInkStroke(
          senderSocketId: sender,
          strokeId: chunk.strokeId,
          style: chunk.style,
          lastActiveMs: now,
        ));
    stroke.lastActiveMs = now;
    if (newPoints.isEmpty) {
      return const RemoteWetInkApplyResult.accepted(0);
    }
    stroke.addPoints(newPoints);
    _roomPointCount += newPoints.length;
    _revision++;
    notifyListeners();
    return RemoteWetInkApplyResult.accepted(newPoints.length);
  }

  void finalizeStroke(String strokeId) {
    final now = _nowMs();
    _finalizedStrokeIds.add(strokeId);
    _completedUntilMs[strokeId] = now + completedCacheTtl.inMilliseconds;
    final removed = _removeStroke(strokeId);
    if (removed) _notifyChanged();
  }

  void finalizeStrokes(Iterable<String> strokeIds) {
    var removed = false;
    final now = _nowMs();
    final until = now + completedCacheTtl.inMilliseconds;
    for (final strokeId in strokeIds) {
      _finalizedStrokeIds.add(strokeId);
      _completedUntilMs[strokeId] = until;
      removed = _removeStroke(strokeId) || removed;
    }
    if (removed) _notifyChanged();
  }

  void removeSender(String senderSocketId) {
    _senderLastActiveMs.remove(senderSocketId);
    final strokeIds = [
      for (final stroke in _strokes.values)
        if (stroke.senderSocketId == senderSocketId) stroke.strokeId,
    ];
    var removed = false;
    for (final strokeId in strokeIds) {
      removed = _removeStroke(strokeId) || removed;
    }
    if (removed) _notifyChanged();
  }

  void cleanup({int? nowMs}) {
    final now = nowMs ?? _nowMs();
    final cutoff = now - inactivityTtl.inMilliseconds;
    final expiredSenders = [
      for (final entry in _senderLastActiveMs.entries)
        if (entry.value <= cutoff) entry.key,
    ];
    final expiredStrokes = [
      for (final stroke in _strokes.values)
        if (stroke.lastActiveMs <= cutoff) stroke.strokeId,
    ];
    var removed = false;
    for (final sender in expiredSenders) {
      _senderLastActiveMs.remove(sender);
    }
    for (final strokeId in expiredStrokes) {
      removed = _removeStroke(strokeId) || removed;
    }
    _completedUntilMs.removeWhere((_, until) => until <= now);
    if (removed) _notifyChanged();
  }

  void reset() {
    final hadStrokes = _strokes.isNotEmpty;
    _senderLastActiveMs.clear();
    _strokes.clear();
    _finalizedStrokeIds.clear();
    _completedUntilMs.clear();
    _dropCounts.clear();
    _roomPointCount = 0;
    if (hadStrokes) _notifyChanged();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  int get _estimatedSegmentCount {
    return _strokes.values.fold(
      0,
      (total, stroke) =>
          total +
          stroke.consolidatedSegments.length +
          stroke.incrementalSegments.length +
          stroke.tailSegments.length,
    );
  }

  bool _validChunkBounds(LiveInkChunk chunk) {
    if (chunk.startIndex < 0 || chunk.points.isEmpty) return false;
    final end = chunk.startIndex + chunk.points.length;
    return end <= maxPointsPerStroke;
  }

  bool _sameStyle(LiveInkStyle left, LiveInkStyle right) {
    return left.brushType == right.brushType &&
        left.strokeColor == right.strokeColor &&
        left.strokeWidth == right.strokeWidth &&
        left.opacity == right.opacity;
  }

  RemoteWetInkApplyResult _drop(RemoteWetInkDropReason reason) {
    _dropCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
    return RemoteWetInkApplyResult.dropped(reason);
  }

  bool _removeStroke(String strokeId) {
    final stroke = _strokes.remove(strokeId);
    if (stroke == null) return false;
    _roomPointCount -= stroke.pointCount;
    return true;
  }

  void _notifyChanged() {
    _revision++;
    notifyListeners();
  }
}

class _RemoteWetInkStroke {
  _RemoteWetInkStroke({
    required this.senderSocketId,
    required this.strokeId,
    required this.style,
    required this.lastActiveMs,
  });

  final String senderSocketId;
  final String strokeId;
  final LiveInkStyle style;
  int lastActiveMs;
  final SplayTreeMap<int, LiveInkPoint> _points = SplayTreeMap();
  final Set<int> _frozenIndices = {};
  final List<RemoteWetInkSegment> consolidatedSegments = [];
  final List<RemoteWetInkSegment> incrementalSegments = [];
  List<RemoteWetInkSegment> tailSegments = const [];
  int revision = 0;

  int get pointCount => _points.length;
  bool containsIndex(int index) => _points.containsKey(index);

  RemoteWetInkStrokeSnapshot get snapshot => RemoteWetInkStrokeSnapshot(
    senderSocketId: senderSocketId,
    strokeId: strokeId,
    style: style,
    consolidatedSegments: List.unmodifiable(consolidatedSegments),
    incrementalSegments: List.unmodifiable(incrementalSegments),
    tailSegments: tailSegments,
    pointCount: pointCount,
    revision: revision,
  );

  void addPoints(Map<int, LiveInkPoint> points) {
    _points.addAll(points);
    final entries = _points.entries.toList(growable: false);
    final tailStart = entries.length > LiveInkChunk.maxPoints
        ? entries.length - LiveInkChunk.maxPoints
        : 0;
    final newlyFrozen = <MapEntry<int, LiveInkPoint>>[];
    for (var index = 0; index < tailStart; index++) {
      final entry = entries[index];
      if (_frozenIndices.add(entry.key)) newlyFrozen.add(entry);
    }
    incrementalSegments.addAll(_segmentsFrom(newlyFrozen));
    while (incrementalSegments.length >
        RemoteWetInkStore.maxIncrementalSegments) {
      final mergeCount = incrementalSegments.length >= 4 ? 4 : 1;
      consolidatedSegments.addAll(incrementalSegments.take(mergeCount));
      incrementalSegments.removeRange(0, mergeCount);
    }
    tailSegments = List.unmodifiable(_segmentsFrom(entries.skip(tailStart)));
    revision++;
  }

  static List<RemoteWetInkSegment> _segmentsFrom(
    Iterable<MapEntry<int, LiveInkPoint>> entries,
  ) {
    final segments = <RemoteWetInkSegment>[];
    var points = <LiveInkPoint>[];
    int? previousIndex;
    for (final entry in entries) {
      if (previousIndex != null && entry.key != previousIndex + 1) {
        segments.add(RemoteWetInkSegment(List.unmodifiable(points)));
        points = <LiveInkPoint>[];
      }
      points.add(entry.value);
      previousIndex = entry.key;
    }
    if (points.isNotEmpty) {
      segments.add(RemoteWetInkSegment(List.unmodifiable(points)));
    }
    return segments;
  }
}
