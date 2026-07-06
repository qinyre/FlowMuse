import '../models/collaborative_element.dart';

class SceneReconciler {
  SceneReconciler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const Duration deletedElementTimeout = Duration(days: 1);

  final DateTime Function() _now;

  List<CollaborativeElement> reconcile({
    required List<CollaborativeElement> localElements,
    required List<CollaborativeElement> remoteElements,
  }) {
    final localById = {
      for (final element in localElements) element.id: element,
    };
    final added = <String>{};
    final result = <CollaborativeElement>[];

    for (final remote in remoteElements) {
      if (added.contains(remote.id)) {
        continue;
      }
      final local = localById[remote.id];
      final chosen = _shouldKeepLocal(local, remote) ? local! : remote;
      result.add(chosen);
      added.add(chosen.id);
    }

    for (final local in localElements) {
      if (added.add(local.id)) {
        result.add(local);
      }
    }

    result.sort((a, b) => a.fractionalIndex.compareTo(b.fractionalIndex));
    return result;
  }

  List<CollaborativeElement> getSyncableElements(
    List<CollaborativeElement> elements,
  ) {
    final deletedCutoff = _now()
        .subtract(deletedElementTimeout)
        .millisecondsSinceEpoch;
    return [
      for (final element in elements)
        if (!element.isDeleted || element.updatedAt > deletedCutoff) element,
    ];
  }

  bool _shouldKeepLocal(
    CollaborativeElement? local,
    CollaborativeElement remote,
  ) {
    if (local == null) {
      return false;
    }
    if (local.version > remote.version) {
      return true;
    }
    if (local.version == remote.version &&
        local.versionNonce <= remote.versionNonce) {
      return true;
    }
    return false;
  }
}
