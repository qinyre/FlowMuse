import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';

import 'collaboration_debug_log.dart';

class SceneReconciler {
  SceneReconciler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const Duration deletedElementTimeout = Duration(days: 1);

  final DateTime Function() _now;

  List<Map<String, Object?>> reconcile({
    required List<Map<String, Object?>> localElements,
    required List<Map<String, Object?>> remoteElements,
    Set<String> protectedElementIds = const {},
  }) {
    final localById = {
      for (final element in localElements) _id(element): element,
    };
    final added = <String>{};
    final result = <Map<String, Object?>>[];
    final counters = _OwnerRepairCounters();

    for (final remote in remoteElements) {
      final remoteId = _id(remote);
      if (added.contains(remoteId)) {
        continue;
      }
      final local = localById[remoteId];
      final chosen =
          (local != null && protectedElementIds.contains(remoteId)) ||
              _shouldKeepLocal(local, remote)
          ? local!
          : remote;
      result.add(_repairOwner(chosen, local, remote, counters));
      added.add(_id(chosen));
    }

    for (final local in localElements) {
      if (added.add(_id(local))) {
        result.add(local);
      }
    }

    final normalized = _normalizeBoundTextOwners(result, counters);
    result
      ..clear()
      ..addAll(normalized);

    result.sort(_compareFractionalIndex);
    final output = _ensureUniqueIndices(result);
    if (counters.conflictCount > 0 || counters.backfillCount > 0) {
      CollaborationDebugLog.write('scene_reconciler', 'owner_repair', {
        'ownerConflictCount': counters.conflictCount,
        'ownerBackfillCount': counters.backfillCount,
      });
    }
    return output;
  }

  List<Map<String, Object?>> _ensureUniqueIndices(
    List<Map<String, Object?>> elements,
  ) {
    final seen = <String>{};
    var nextFallbackIndex = 0;
    return [
      for (final element in elements)
        _withValidIndex(element, seen, nextFallbackIndex++),
    ];
  }

  Map<String, Object?> _withValidIndex(
    Map<String, Object?> element,
    Set<String> seen,
    int fallbackIndex,
  ) {
    final index = _fractionalIndex(element);
    if (index != null && index.isNotEmpty && seen.add(index)) {
      return element;
    }
    final fallback = fallbackIndex.toString().padLeft(8, '0');
    seen.add(fallback);
    return {...element, 'index': fallback};
  }

  List<Map<String, Object?>> getSyncableElements(
    List<Map<String, Object?>> elements,
  ) {
    final deletedCutoff = _now()
        .subtract(deletedElementTimeout)
        .millisecondsSinceEpoch;
    return [
      for (final element in elements)
        if ((_isDeleted(element) && _updatedAt(element) > deletedCutoff) ||
            (!_isDeleted(element) && !_isInvisiblySmallElement(element)))
          element,
    ];
  }

  bool _shouldKeepLocal(
    Map<String, Object?>? local,
    Map<String, Object?> remote,
  ) {
    if (local == null) {
      return false;
    }
    final localVersion = _version(local);
    final remoteVersion = _version(remote);
    if (localVersion > remoteVersion) {
      return true;
    }
    if (localVersion == remoteVersion &&
        _versionNonce(local) <= _versionNonce(remote)) {
      return true;
    }
    return false;
  }

  /// v4 §5.3：winner 选定后的归属修复。winner 有 owner → 原样（双方都
  /// 非空且不同只计数，不改输出）；winner 缺失 → 从 loser 回填。
  Map<String, Object?> _repairOwner(
    Map<String, Object?> winner,
    Map<String, Object?>? local,
    Map<String, Object?> remote,
    _OwnerRepairCounters counters,
  ) {
    final winnerCreator = readCreatorFromJson(winner);
    final loser = identical(winner, local) ? remote : local;
    final loserCreator = loser == null ? null : readCreatorFromJson(loser);
    if (winnerCreator != null) {
      if (loserCreator != null &&
          loserCreator.creatorKey != winnerCreator.creatorKey) {
        counters.conflictCount++;
      }
      return winner;
    }
    if (loserCreator == null) return winner;
    counters.backfillCount++;
    return withCreatorInJson(winner, loserCreator);
  }

  /// v4 §5.3：结果集父子规范化。containerId 非空的 text 元素 owner 以结果
  /// 集中父元素为准（父缺失或无 owner → 清除）。不改 version/versionNonce，
  /// 所有客户端面对同一结果集得到相同输出。
  List<Map<String, Object?>> _normalizeBoundTextOwners(
    List<Map<String, Object?>> elements,
    _OwnerRepairCounters counters,
  ) {
    final byId = <String, Map<String, Object?>>{
      for (final element in elements) _id(element): element,
    };
    final output = <Map<String, Object?>>[];
    for (final element in elements) {
      final containerId = element['containerId'];
      if (element['type'] != 'text' || containerId is! String) {
        output.add(element);
        continue;
      }
      final parent = byId[containerId];
      final parentCreator = parent == null ? null : readCreatorFromJson(parent);
      final currentCreator = readCreatorFromJson(element);
      if (parentCreator == null) {
        output.add(
          currentCreator == null ? element : withoutCreatorInJson(element),
        );
      } else if (currentCreator != null &&
          currentCreator.creatorKey == parentCreator.creatorKey) {
        output.add(element);
      } else {
        output.add(withCreatorInJson(element, parentCreator));
      }
    }
    return output;
  }

  int getSceneVersion(List<Map<String, Object?>> elements) {
    return elements.fold(0, (sum, element) => sum + _version(element));
  }

  int hashElementsVersion(List<Map<String, Object?>> elements) {
    var hash = 5381;
    for (final element in elements) {
      hash = ((hash << 5) + hash + _versionNonce(element)).toUnsigned(32);
    }
    return hash;
  }

  int _compareFractionalIndex(Map<String, Object?> a, Map<String, Object?> b) {
    final aIndex = _fractionalIndex(a);
    final bIndex = _fractionalIndex(b);
    if (aIndex != null && bIndex != null) {
      final indexCompare = aIndex.compareTo(bIndex);
      if (indexCompare != 0) {
        return indexCompare;
      }
      return _id(a).compareTo(_id(b));
    }
    if (aIndex == null && bIndex == null) {
      return _id(a).compareTo(_id(b));
    }
    return aIndex == null ? 1 : -1;
  }

  String _id(Map<String, Object?> element) => element['id']! as String;

  int _version(Map<String, Object?> element) =>
      (element['version']! as num).toInt();

  int _versionNonce(Map<String, Object?> element) =>
      (element['versionNonce']! as num).toInt();

  int _updatedAt(Map<String, Object?> element) =>
      (element['updated']! as num).toInt();

  String? _fractionalIndex(Map<String, Object?> element) =>
      element['index'] as String?;

  bool _isDeleted(Map<String, Object?> element) =>
      element['isDeleted']! as bool;

  bool _isInvisiblySmallElement(Map<String, Object?> element) {
    final type = element['type'];
    if (type == 'text') {
      return false;
    }
    final width = ((element['width'] as num?) ?? 0).toDouble().abs();
    final height = ((element['height'] as num?) ?? 0).toDouble().abs();
    if (type == 'line' || type == 'arrow' || type == 'freedraw') {
      final points = element['points'];
      return width < 1 && height < 1 && (points is! List || points.length < 2);
    }
    return width < 1 && height < 1;
  }
}

class _OwnerRepairCounters {
  int conflictCount = 0;
  int backfillCount = 0;
}
