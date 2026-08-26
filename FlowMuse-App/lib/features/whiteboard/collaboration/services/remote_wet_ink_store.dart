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
  const RemoteWetInkSegment({
    required this.startIndex,
    required this.points,
    this.leadingPoint,
    this.trailingPoint,
  });

  final int startIndex;
  final List<LiveInkPoint> points;
  final LiveInkPoint? leadingPoint;
  final LiveInkPoint? trailingPoint;

  bool containsIndex(int index) =>
      index >= startIndex && index < startIndex + points.length;
}

/// 笔迹点的轴对齐包围盒（纯几何数据，渲染层聚焦 dim 层复用）。
/// 由 store 在点冻结/合并时增量维护，painter 不得每帧重扫冻结点。
@immutable
class RemoteWetInkBounds {
  const RemoteWetInkBounds(this.minX, this.minY, this.maxX, this.maxY);

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  static RemoteWetInkBounds? ofPoints(Iterable<LiveInkPoint> points) {
    RemoteWetInkBounds? bounds;
    for (final point in points) {
      bounds = bounds == null
          ? RemoteWetInkBounds(point.x, point.y, point.x, point.y)
          : bounds.expandTo(point.x, point.y);
    }
    return bounds;
  }

  RemoteWetInkBounds expandTo(double x, double y) => RemoteWetInkBounds(
    x < minX ? x : minX,
    y < minY ? y : minY,
    x > maxX ? x : maxX,
    y > maxY ? y : maxY,
  );

  RemoteWetInkBounds union(RemoteWetInkBounds other) => RemoteWetInkBounds(
    other.minX < minX ? other.minX : minX,
    other.minY < minY ? other.minY : minY,
    other.maxX > maxX ? other.maxX : maxX,
    other.maxY > maxY ? other.maxY : maxY,
  );
}

@immutable
class RemoteWetInkBlock {
  const RemoteWetInkBlock({
    required this.level,
    required this.segments,
    required this.pointCount,
    required this.revision,
    required this.bounds,
  });

  final int level;
  final List<RemoteWetInkSegment> segments;
  final int pointCount;
  final int revision;

  /// 该冻结块覆盖点的包围盒（创建/合并时一次计算，此后不变）。
  final RemoteWetInkBounds bounds;
}

@immutable
class RemoteWetInkStrokeSnapshot {
  const RemoteWetInkStrokeSnapshot({
    required this.senderSocketId,
    required this.strokeId,
    required this.style,
    required this.frozenBlocks,
    required this.tailSegments,
    required this.pointCount,
    required this.maxPointIndex,
    required this.revision,
    required this.pointIndexLog,
    required this.pointIndexLogEnd,
    this.frozenBounds,
  });

  final String senderSocketId;
  final String strokeId;
  final LiveInkStyle style;
  final List<RemoteWetInkBlock> frozenBlocks;
  final List<RemoteWetInkSegment> tailSegments;
  final int pointCount;
  final int maxPointIndex;
  final int revision;
  final List<int> pointIndexLog;
  final int pointIndexLogEnd;

  /// 全部已冻结点（含 pending 与已成块）的合并包围盒，随点到达增量扩展；
  /// null = 尚无冻结点。painter 聚焦 dim 层据此计算 bounds，只另行扫描
  /// 有限的 tail 段，不重遍历冻结几何（评审 P1 修复）。
  final RemoteWetInkBounds? frozenBounds;

  int get layerCount => frozenBlocks.length + (tailSegments.isEmpty ? 0 : 1);
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
  static const int frozenBlockPointCapacity = 64;
  static const int maxEstimatedRenderBytes = 16 * 1024 * 1024;
  static const int _estimatedBytesPerPoint = 240;
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
  int _nextCleanupAtMs = 0;
  int _cleanupPassCount = 0;
  int _lastApplyExaminedPointCount = 0;
  int _cachedStrokesRevision = -1;
  List<RemoteWetInkStrokeSnapshot> _cachedStrokes = const [];

  int get roomPointCount => _roomPointCount;
  int get senderCount => _senderLastActiveMs.length;
  int get strokeCount => _strokes.length;
  int get revision => _revision;
  int get finalizedStrokeCount => _finalizedStrokeIds.length;
  int get completedCacheCount => _completedUntilMs.length;
  int get cleanupPassCount => _cleanupPassCount;
  int get lastApplyExaminedPointCount => _lastApplyExaminedPointCount;
  int dropCount(RemoteWetInkDropReason reason) => _dropCounts[reason] ?? 0;

  List<RemoteWetInkStrokeSnapshot> get strokes {
    if (_cachedStrokesRevision != _revision) {
      _cachedStrokes = List.unmodifiable(
        _strokes.values.map((stroke) => stroke.snapshot),
      );
      _cachedStrokesRevision = _revision;
    }
    return _cachedStrokes;
  }

  bool isFinalized(String strokeId) => _finalizedStrokeIds.contains(strokeId);

  void seedFinalizedStrokeIds(Iterable<String> strokeIds) {
    _finalizedStrokeIds.addAll(strokeIds);
  }

  RemoteWetInkApplyResult apply(DecodedLiveInkChunk decoded) {
    final now = _nowMs();
    _cleanupIfDue(now);
    final sender = decoded.senderSocketId;
    final chunk = decoded.chunk;
    _lastApplyExaminedPointCount = chunk.points.length;
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
    _lastApplyExaminedPointCount += stroke.addPoints(newPoints);
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
    _cleanupPassCount++;
    _nextCleanupAtMs = now + const Duration(seconds: 1).inMilliseconds;
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
    _nextCleanupAtMs = 0;
    if (hadStrokes) _notifyChanged();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  int get _estimatedSegmentCount {
    return _strokes.values.fold<int>(
      0,
      (total, stroke) =>
          total +
          stroke._frozenBlocks.whereType<RemoteWetInkBlock>().fold<int>(
            0,
            (blockTotal, block) => blockTotal + block.segments.length,
          ) +
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

  void _cleanupIfDue(int now) {
    if (now >= _nextCleanupAtMs) cleanup(nowMs: now);
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
  final SplayTreeMap<int, LiveInkPoint> _allPoints = SplayTreeMap();
  final Map<int, int> _arrivalOrder = {};
  final List<int> _pointIndexLog = [];
  final SplayTreeMap<int, LiveInkPoint> _tailPoints = SplayTreeMap();
  final List<RemoteWetInkBlock?> _frozenBlocks = List.filled(
    RemoteWetInkStore.maxIncrementalSegments,
    null,
  );
  final SplayTreeMap<int, LiveInkPoint> _pendingFrozen = SplayTreeMap();
  List<RemoteWetInkSegment> tailSegments = const [];
  RemoteWetInkBounds? _frozenBounds;
  int revision = 0;
  int _pointCount = 0;
  int _maxPointIndex = -1;
  int _blockRevision = 0;
  int _nextArrivalOrder = 0;
  RemoteWetInkStrokeSnapshot? _cachedSnapshot;

  int get pointCount => _pointCount;
  bool containsIndex(int index) => _allPoints.containsKey(index);

  RemoteWetInkStrokeSnapshot get snapshot {
    final cached = _cachedSnapshot;
    if (cached != null && cached.revision == revision) return cached;
    return _cachedSnapshot = RemoteWetInkStrokeSnapshot(
      senderSocketId: senderSocketId,
      strokeId: strokeId,
      style: style,
      frozenBlocks: List.unmodifiable(
        _frozenBlocks.whereType<RemoteWetInkBlock>(),
      ),
      tailSegments: tailSegments,
      pointCount: pointCount,
      maxPointIndex: _maxPointIndex,
      revision: revision,
      pointIndexLog: _pointIndexLog,
      pointIndexLogEnd: _pointIndexLog.length,
      frozenBounds: _frozenBounds,
    );
  }

  int addPoints(Map<int, LiveInkPoint> points) {
    if (points.isEmpty) return 0;
    for (final entry in points.entries) {
      final index = entry.key;
      if (index > _maxPointIndex) _maxPointIndex = index;
      _allPoints[index] = entry.value;
      _arrivalOrder[index] = ++_nextArrivalOrder;
      _pointIndexLog.add(index);
    }
    final tailFloor = _maxPointIndex - LiveInkChunk.maxPoints + 1;
    final newlyFrozen = SplayTreeMap<int, LiveInkPoint>();
    var examinedPointCount = points.length;

    final expiredTailIndices = <int>[];
    for (final entry in _tailPoints.entries) {
      examinedPointCount++;
      if (entry.key >= tailFloor) break;
      expiredTailIndices.add(entry.key);
      newlyFrozen[entry.key] = entry.value;
    }
    for (final index in expiredTailIndices) {
      _tailPoints.remove(index);
    }
    for (final entry in points.entries) {
      if (entry.key < tailFloor) {
        newlyFrozen[entry.key] = entry.value;
      } else {
        _tailPoints[entry.key] = entry.value;
      }
    }
    _appendFrozen(newlyFrozen.entries);
    final visibleTail = SplayTreeMap<int, LiveInkPoint>()
      ..addAll(_pendingFrozen)
      ..addAll(_tailPoints);
    tailSegments = List.unmodifiable(_segmentsFrom(visibleTail.entries));
    _pointCount += points.length;
    revision++;
    return examinedPointCount;
  }

  void _appendFrozen(Iterable<MapEntry<int, LiveInkPoint>> entries) {
    for (final entry in entries) {
      _pendingFrozen[entry.key] = entry.value;
      final point = entry.value;
      _frozenBounds = _frozenBounds == null
          ? RemoteWetInkBounds(point.x, point.y, point.x, point.y)
          : _frozenBounds!.expandTo(point.x, point.y);
    }
    while (_pendingFrozen.length >=
        RemoteWetInkStore.frozenBlockPointCapacity) {
      final entries = _pendingFrozen.entries
          .take(RemoteWetInkStore.frozenBlockPointCapacity)
          .toList(growable: false);
      for (final entry in entries) {
        _pendingFrozen.remove(entry.key);
      }
      _insertBlock(
        RemoteWetInkBlock(
          level: 0,
          segments: List.unmodifiable(_segmentsFrom(entries)),
          pointCount: entries.length,
          revision: ++_blockRevision,
          bounds: RemoteWetInkBounds.ofPoints(
            entries.map((entry) => entry.value),
          )!,
        ),
      );
    }
  }

  void _insertBlock(RemoteWetInkBlock incoming) {
    var block = incoming;
    for (var level = 0; level < _frozenBlocks.length; level++) {
      final existing = _frozenBlocks[level];
      if (existing == null) {
        _frozenBlocks[level] = RemoteWetInkBlock(
          level: level,
          segments: block.segments,
          pointCount: block.pointCount,
          revision: ++_blockRevision,
          bounds: block.bounds,
        );
        return;
      }
      _frozenBlocks[level] = null;
      block = RemoteWetInkBlock(
        level: level + 1,
        segments: List.unmodifiable(
          _mergeSegments(existing.segments, block.segments),
        ),
        pointCount: existing.pointCount + block.pointCount,
        revision: ++_blockRevision,
        bounds: existing.bounds.union(block.bounds),
      );
    }
    throw StateError('remote wet ink frozen block capacity exceeded');
  }

  List<RemoteWetInkSegment> _segmentsFrom(
    Iterable<MapEntry<int, LiveInkPoint>> entries,
  ) {
    final segments = <RemoteWetInkSegment>[];
    var points = <LiveInkPoint>[];
    int? previousIndex;
    for (final entry in entries) {
      if (previousIndex != null && entry.key != previousIndex + 1) {
        segments.add(_segment(previousIndex - points.length + 1, points));
        points = <LiveInkPoint>[];
      }
      points.add(entry.value);
      previousIndex = entry.key;
    }
    if (points.isNotEmpty) {
      segments.add(_segment(previousIndex! - points.length + 1, points));
    }
    return segments;
  }

  RemoteWetInkSegment _segment(int startIndex, List<LiveInkPoint> points) {
    final endIndex = startIndex + points.length - 1;
    final firstOrder = _arrivalOrder[startIndex]!;
    final lastOrder = _arrivalOrder[endIndex]!;
    final leadingIndex = startIndex - 1;
    final trailingIndex = endIndex + 1;
    return RemoteWetInkSegment(
      startIndex: startIndex,
      points: List.unmodifiable(points),
      leadingPoint: (_arrivalOrder[leadingIndex] ?? firstOrder) < firstOrder
          ? _allPoints[leadingIndex]
          : null,
      trailingPoint: (_arrivalOrder[trailingIndex] ?? lastOrder) < lastOrder
          ? _allPoints[trailingIndex]
          : null,
    );
  }

  static List<RemoteWetInkSegment> _mergeSegments(
    List<RemoteWetInkSegment> left,
    List<RemoteWetInkSegment> right,
  ) {
    final sorted = [...left, ...right]
      ..sort((a, b) => a.startIndex.compareTo(b.startIndex));
    final merged = <RemoteWetInkSegment>[];
    for (final segment in sorted) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        if (previous.startIndex + previous.points.length ==
            segment.startIndex) {
          merged[merged.length - 1] = RemoteWetInkSegment(
            startIndex: previous.startIndex,
            points: List.unmodifiable([...previous.points, ...segment.points]),
            leadingPoint: previous.leadingPoint,
            trailingPoint: segment.trailingPoint,
          );
          continue;
        }
      }
      merged.add(segment);
    }
    return merged;
  }
}
